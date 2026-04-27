<?php
// ─────────────────────────────────────────────────────────────────────
// advance_knockout.php  (FIFA-style seeding)
//
// POST (JSON body)
// Called by championship_sched.dart immediately after a match score
// is saved.
//
// ── GROUP STAGE ──────────────────────────────────────────────────────
// After a group match is scored this script checks whether ALL matches
// in that group are now complete.  If so it ranks the group by the
// standard soccer tiebreaker (pts → GD → GF → team_name) and stores
// the result in tbl_group_results (group_label, rank, team_id).
//
// Once ALL groups are complete, the FIFA draw is executed:
//   Rank-1 of Group A  → Match 1 slot HOME  (vs Rank-2 of Group B)
//   Rank-2 of Group B  → Match 1 slot AWAY
//   Rank-1 of Group B  → Match 2 slot HOME  (vs Rank-2 of Group A)
//   Rank-2 of Group A  → Match 2 slot AWAY
//   ... and so on for every pair, sorted alphabetically by group label.
//
// If the group is not yet finished it returns early with "pending".
// If only SOME groups are done it returns "waiting_for_other_groups".
//
// ── KNOCKOUT ROUNDS ──────────────────────────────────────────────────
// Winner is seeded into the next round.
// Semi-final loser is seeded into the third-place match.
// Final / third-place → no advancement.
//
// Body:
// {
//   "match_id":       47,
//   "winner_team_id": 12,   <- ignored for group matches
//   "loser_team_id":  9,    <- ignored for group matches
//   "category_id":    4
// }
//
// No extra DB tables required.  Standings are computed live from
// tbl_score + tbl_soccer_groups (same logic as get_group_standings.php).
// ─────────────────────────────────────────────────────────────────────
ini_set('display_errors', 0);
error_reporting(0);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed. Use POST.']);
    exit();
}

require_once 'db_config.php';

// ── Parse body ────────────────────────────────────────────────────────
$body = file_get_contents('php://input');
$data = json_decode($body, true);

if (!$data) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid or empty JSON body']);
    exit();
}

$required = ['match_id', 'winner_team_id', 'loser_team_id', 'category_id'];
foreach ($required as $field) {
    if (!isset($data[$field]) || $data[$field] === '') {
        http_response_code(400);
        echo json_encode(['error' => "Missing required field: $field"]);
        exit();
    }
}

$match_id       = intval($data['match_id']);
$winner_team_id = intval($data['winner_team_id']);
$loser_team_id  = intval($data['loser_team_id']);
$category_id    = intval($data['category_id']);

if ($match_id <= 0 || $category_id <= 0) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid match_id or category_id']);
    exit();
}

// ── 1. Get bracket_type of this match ─────────────────────────────────
$stmt = $conn->prepare(
    "SELECT bracket_type FROM tbl_match WHERE match_id = ? LIMIT 1"
);
$stmt->bind_param('i', $match_id);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row) {
    http_response_code(404);
    echo json_encode(['error' => "Match $match_id not found"]);
    exit();
}

$currentType = $row['bracket_type'];

// ═════════════════════════════════════════════════════════════════════
// PATH A — GROUP STAGE  (FIFA-style draw)
// ═════════════════════════════════════════════════════════════════════
if ($currentType === 'group') {

    // ── A1. Find which group label this match belongs to ──────────────
    $stmt = $conn->prepare("
        SELECT ts.team_id
        FROM   tbl_teamschedule ts
        WHERE  ts.match_id = ?
        LIMIT  2
    ");
    $stmt->bind_param('i', $match_id);
    $stmt->execute();
    $tsRes = $stmt->get_result();
    $stmt->close();

    $matchTeamIds = [];
    while ($r = $tsRes->fetch_assoc()) {
        $matchTeamIds[] = intval($r['team_id']);
    }

    if (empty($matchTeamIds)) {
        echo json_encode([
            'success' => false,
            'message' => "No teams found in tbl_teamschedule for match $match_id",
        ]);
        exit();
    }

    $stmt = $conn->prepare("
        SELECT group_label
        FROM   tbl_soccer_groups
        WHERE  team_id     = ?
          AND  category_id = ?
        LIMIT 1
    ");
    $stmt->bind_param('ii', $matchTeamIds[0], $category_id);
    $stmt->execute();
    $glRow = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$glRow) {
        echo json_encode([
            'success' => false,
            'message' => "Team {$matchTeamIds[0]} not found in tbl_soccer_groups for category $category_id",
        ]);
        exit();
    }

    $groupLabel = $glRow['group_label'];

    // ── A2. Get all teams in this group ───────────────────────────────
    $stmt = $conn->prepare("
        SELECT team_id
        FROM   tbl_soccer_groups
        WHERE  group_label = ?
          AND  category_id = ?
    ");
    $stmt->bind_param('si', $groupLabel, $category_id);
    $stmt->execute();
    $grpTeamRes = $stmt->get_result();
    $stmt->close();

    $groupTeamIds = [];
    while ($r = $grpTeamRes->fetch_assoc()) {
        $groupTeamIds[] = intval($r['team_id']);
    }

    $n            = count($groupTeamIds);
    $totalMatches = ($n * ($n - 1)) / 2;

    // ── A3. Count scored matches for this group ───────────────────────
    $placeholders = implode(',', array_fill(0, $n, '?'));
    $types        = str_repeat('i', $n + 1);

    $stmt = $conn->prepare("
        SELECT m.match_id
        FROM   tbl_match m
        WHERE  m.bracket_type = 'group'
          AND  (
              SELECT COUNT(*)
              FROM   tbl_teamschedule ts
              WHERE  ts.match_id = m.match_id
                AND  ts.team_id IN ($placeholders)
          ) = 2
          AND  (
              SELECT COUNT(*)
              FROM   tbl_score sc
              WHERE  sc.match_id = m.match_id
          ) = 2
          AND EXISTS (
              SELECT 1
              FROM   tbl_teamschedule ts2
              INNER JOIN tbl_team t ON t.team_id = ts2.team_id
              WHERE  ts2.match_id   = m.match_id
                AND  t.category_id  = ?
          )
    ");
    $bindArgs = array_merge($groupTeamIds, [$category_id]);
    $stmt->bind_param($types, ...$bindArgs);
    $stmt->execute();
    $scoredRes = $stmt->get_result();
    $stmt->close();

    $scoredMatches = [];
    while ($r = $scoredRes->fetch_assoc()) {
        $scoredMatches[] = intval($r['match_id']);
    }
    $scoredCount = count($scoredMatches);

    if ($scoredCount < $totalMatches) {
        echo json_encode([
            'success'        => true,
            'status'         => 'pending',
            'group_label'    => $groupLabel,
            'matches_scored' => $scoredCount,
            'matches_total'  => $totalMatches,
            'message'        => "Group $groupLabel: $scoredCount / $totalMatches matches scored. Waiting for remaining matches.",
        ]);
        exit();
    }

    // ── A4. All matches done — calculate standings via shared helper ─────
    // computeGroupStandings() replicates get_group_standings.php logic
    // in-process. No tbl_group_results table required.
    $rows = computeGroupStandings($conn, $groupTeamIds, $scoredMatches);

    $rank1TeamId = $rows[0]['team_id'];
    $rank2TeamId = $rows[1]['team_id'];

    // ── A5. Check if ALL groups for this category are now complete ────
    // A group is "complete" when its scored-match count equals totalMatches.
    // We recalculate this for every group live — no helper table needed.
    $allGroupsStmt = $conn->prepare("
        SELECT DISTINCT group_label
        FROM   tbl_soccer_groups
        WHERE  category_id = ?
        ORDER  BY group_label ASC
    ");
    $allGroupsStmt->bind_param('i', $category_id);
    $allGroupsStmt->execute();
    $allGroupsRes = $allGroupsStmt->get_result();
    $allGroupsStmt->close();

    $allGroupLabels = [];
    while ($r = $allGroupsRes->fetch_assoc()) {
        $allGroupLabels[] = $r['group_label'];
    }
    $totalGroups = count($allGroupLabels);

    // Count how many groups have all their matches scored
    $doneGroups = 0;
    foreach ($allGroupLabels as $lbl) {
        // Get team IDs for this group
        $gStmt = $conn->prepare("
            SELECT team_id FROM tbl_soccer_groups
            WHERE group_label = ? AND category_id = ?
        ");
        $gStmt->bind_param('si', $lbl, $category_id);
        $gStmt->execute();
        $gRes = $gStmt->get_result();
        $gStmt->close();

        $gTeamIds = [];
        while ($gr = $gRes->fetch_assoc()) {
            $gTeamIds[] = intval($gr['team_id']);
        }

        $gN            = count($gTeamIds);
        $gTotalMatches = ($gN * ($gN - 1)) / 2;
        $gPH           = implode(',', array_fill(0, $gN, '?'));
        $gTypes        = str_repeat('i', $gN + 1);

        $cStmt = $conn->prepare("
            SELECT COUNT(*) AS cnt
            FROM   tbl_match m
            WHERE  m.bracket_type = 'group'
              AND  (
                  SELECT COUNT(*)
                  FROM   tbl_teamschedule ts
                  WHERE  ts.match_id = m.match_id
                    AND  ts.team_id IN ($gPH)
              ) = 2
              AND  (
                  SELECT COUNT(*)
                  FROM   tbl_score sc
                  WHERE  sc.match_id = m.match_id
              ) = 2
              AND EXISTS (
                  SELECT 1
                  FROM   tbl_teamschedule ts2
                  INNER JOIN tbl_team t ON t.team_id = ts2.team_id
                  WHERE  ts2.match_id  = m.match_id
                    AND  t.category_id = ?
              )
        ");
        $cArgs = array_merge($gTeamIds, [$category_id]);
        $cStmt->bind_param($gTypes, ...$cArgs);
        $cStmt->execute();
        $cRow = $cStmt->get_result()->fetch_assoc();
        $cStmt->close();

        if (intval($cRow['cnt']) >= $gTotalMatches) {
            $doneGroups++;
        }
    }

    if ($doneGroups < $totalGroups) {
        // This group is done but others aren't — hold off on seeding
        echo json_encode([
            'success'             => true,
            'status'              => 'waiting_for_other_groups',
            'group_label'         => $groupLabel,
            'groups_complete'     => $doneGroups,
            'groups_total'        => $totalGroups,
            'rank1_team_id'       => $rank1TeamId,
            'rank1_team_name'     => $rows[0]['team_name'],
            'rank2_team_id'       => $rank2TeamId,
            'rank2_team_name'     => $rows[1]['team_name'],
            'standings'           => $rows,
            'message'             => "Group $groupLabel complete ($doneGroups/$totalGroups groups done). Waiting for remaining groups before draw.",
        ]);
        exit();
    }

    // ── A6. ALL groups done — build groupResults live (no helper table) ─
    // For each group, run computeGroupStandings() to get rank-1 and rank-2.
    $groupResults = []; // $groupResults['A'][1] = team_id, [2] = team_id
    foreach ($allGroupLabels as $lbl) {
        // Fetch team IDs for this group
        $gStmt = $conn->prepare("
            SELECT team_id FROM tbl_soccer_groups
            WHERE group_label = ? AND category_id = ?
        ");
        $gStmt->bind_param('si', $lbl, $category_id);
        $gStmt->execute();
        $gRes = $gStmt->get_result();
        $gStmt->close();

        $gTeamIds = [];
        while ($gr = $gRes->fetch_assoc()) {
            $gTeamIds[] = intval($gr['team_id']);
        }

        // Fetch scored match IDs for this group
        $gN  = count($gTeamIds);
        $gPH = implode(',', array_fill(0, $gN, '?'));
        $gTypes = str_repeat('i', $gN + 1);

        $smStmt = $conn->prepare("
            SELECT m.match_id
            FROM   tbl_match m
            WHERE  m.bracket_type = 'group'
              AND  (
                  SELECT COUNT(*)
                  FROM   tbl_teamschedule ts
                  WHERE  ts.match_id = m.match_id
                    AND  ts.team_id IN ($gPH)
              ) = 2
              AND  (
                  SELECT COUNT(*)
                  FROM   tbl_score sc
                  WHERE  sc.match_id = m.match_id
              ) = 2
              AND EXISTS (
                  SELECT 1
                  FROM   tbl_teamschedule ts2
                  INNER JOIN tbl_team t ON t.team_id = ts2.team_id
                  WHERE  ts2.match_id  = m.match_id
                    AND  t.category_id = ?
              )
        ");
        $smArgs = array_merge($gTeamIds, [$category_id]);
        $smStmt->bind_param($gTypes, ...$smArgs);
        $smStmt->execute();
        $smRes = $smStmt->get_result();
        $smStmt->close();

        $gScoredMatches = [];
        while ($sm = $smRes->fetch_assoc()) {
            $gScoredMatches[] = intval($sm['match_id']);
        }

        $gRows = computeGroupStandings($conn, $gTeamIds, $gScoredMatches);
        $groupResults[$lbl][1] = $gRows[0]['team_id'] ?? null;
        $groupResults[$lbl][2] = $gRows[1]['team_id'] ?? null;
    }

    // Sort group labels alphabetically (A, B, C, D …)
    ksort($groupResults);
    $sortedLabels = array_keys($groupResults);

    // ── A7. Find next knockout round ──────────────────────────────────
    $knownOrder = [
        'elimination', 'round-of-32', 'round-of-16',
        'quarter-finals', 'semi-finals', 'third-place', 'final'
    ];

    $roundsStmt = $conn->prepare("
        SELECT DISTINCT m.bracket_type
        FROM   tbl_match m
        WHERE  m.bracket_type IN (
                   'elimination', 'round-of-32', 'round-of-16',
                   'quarter-finals', 'semi-finals', 'third-place', 'final'
               )
    ");
    $roundsStmt->execute();
    $roundsResult = $roundsStmt->get_result();
    $roundsStmt->close();

    $presentRounds = [];
    while ($r = $roundsResult->fetch_assoc()) {
        // Skip third-place and final — they are not valid entry rounds from group stage
        if ($r['bracket_type'] === 'third-place' || $r['bracket_type'] === 'final') continue;
        $presentRounds[] = $r['bracket_type'];
    }

    usort($presentRounds, function ($a, $b) use ($knownOrder) {
        return array_search($a, $knownOrder) - array_search($b, $knownOrder);
    });

    $nextKnockoutType = $presentRounds[0] ?? 'semi-finals';

    // ── A8. Get default referee ───────────────────────────────────────
    $refStmt = $conn->prepare(
        "SELECT referee_id FROM tbl_referee ORDER BY referee_id ASC LIMIT 1"
    );
    $refStmt->execute();
    $refRow     = $refStmt->get_result()->fetch_assoc();
    $refStmt->close();
    $referee_id = $refRow ? intval($refRow['referee_id']) : 1;

    // ── A9. FIFA-style overall seeding draw ──────────────────────────
    //
    // For ANY number of groups we build a flat overall ranking of ALL
    // advancing teams (top-2 per group) using the same tiebreakers as
    // within a group (PTS → GD → GF → team_name).  This matches the
    // FIFA "best runners-up" / overall seeding method used whenever
    // there is an odd number of groups or a non-standard advance count.
    //
    // With 5 groups → 10 teams total:
    //   Seeds 1 & 2 → BYE  (straight to semi-finals)
    //   Seeds 3 & 6 → ELIM match 1  (3 vs 6)
    //   Seeds 4 & 5 → ELIM match 2  (4 vs 5)
    //   ELIM winner vs Seed 2 → SF1
    //   ELIM winner vs Seed 1 → SF2
    //
    // With an even number of groups (4, 6, 8 …) the classic FIFA World
    // Cup group-pair draw is used instead:
    //   For each adjacent pair (A,B), (C,D) …
    //     Match N:   1A vs 2B
    //     Match N+1: 1B vs 2A
    //
    // The logic auto-detects which path to take based on group count.

    // ── Build flat list of ALL advancing teams with their overall stats ─
    // We need full stats (not just team_id) for cross-group tiebreaking.
    $allAdvancers = []; // flat rows: same shape as computeGroupStandings rows + 'group_label'
    foreach ($allGroupLabels as $lbl) {
        // Re-fetch team IDs & scored matches for this group (reuse earlier pattern)
        $gStmt2 = $conn->prepare("
            SELECT team_id FROM tbl_soccer_groups
            WHERE group_label = ? AND category_id = ?
        ");
        $gStmt2->bind_param('si', $lbl, $category_id);
        $gStmt2->execute();
        $gRes2 = $gStmt2->get_result();
        $gStmt2->close();

        $gTeamIds2 = [];
        while ($gr = $gRes2->fetch_assoc()) {
            $gTeamIds2[] = intval($gr['team_id']);
        }

        $gN2  = count($gTeamIds2);
        $gPH2 = implode(',', array_fill(0, $gN2, '?'));
        $gTypes2 = str_repeat('i', $gN2 + 1);

        $smStmt2 = $conn->prepare("
            SELECT m.match_id
            FROM   tbl_match m
            WHERE  m.bracket_type = 'group'
              AND  (
                  SELECT COUNT(*)
                  FROM   tbl_teamschedule ts
                  WHERE  ts.match_id = m.match_id
                    AND  ts.team_id IN ($gPH2)
              ) = 2
              AND  (
                  SELECT COUNT(*)
                  FROM   tbl_score sc
                  WHERE  sc.match_id = m.match_id
              ) = 2
              AND EXISTS (
                  SELECT 1
                  FROM   tbl_teamschedule ts2
                  INNER JOIN tbl_team t ON t.team_id = ts2.team_id
                  WHERE  ts2.match_id  = m.match_id
                    AND  t.category_id = ?
              )
        ");
        $smArgs2 = array_merge($gTeamIds2, [$category_id]);
        $smStmt2->bind_param($gTypes2, ...$smArgs2);
        $smStmt2->execute();
        $smRes2 = $smStmt2->get_result();
        $smStmt2->close();

        $gScoredMatches2 = [];
        while ($sm = $smRes2->fetch_assoc()) {
            $gScoredMatches2[] = intval($sm['match_id']);
        }

        $gRows2 = computeGroupStandings($conn, $gTeamIds2, $gScoredMatches2);

        // Keep only top-2 from each group
        foreach (array_slice($gRows2, 0, 2) as $row) {
            $row['group_label'] = $lbl;
            $allAdvancers[] = $row;
        }
    }

    // ── Sort ALL advancers by overall PTS → GD → GF (stable) ────────
    // Cross-group head-to-head is NOT applied — teams haven't played
    // each other across groups.  Ties after GF keep original group-label
    // order (stable sort via rankAndSeedTeams).
    $allAdvancers = rankAndSeedTeams($allAdvancers);

    // Build lookup and detail log from the ranked result.
    $overallSeeds  = []; // seed (1-based) => team_id
    $seedingDetail = [];
    foreach ($allAdvancers as $adv) {
        $overallSeeds[$adv['seed']] = $adv['team_id'];
        $seedingDetail[] = [
            'rank'      => $adv['rank'],
            'seed'      => $adv['seed'],
            'team_id'   => $adv['team_id'],
            'team_name' => $adv['team_name'],
            'group'     => $adv['group_label'],
            'pts'       => $adv['pts'],
            'gd'        => $adv['gd'],
            'gf'        => $adv['gf'],
        ];
    }

    $totalAdvancers = count($overallSeeds);
    $seedingLog = ['overall_seeds' => $seedingDetail];

    // ── Choose draw method based on EXACT group count ───────────────────
    //
    // Each group count maps to a specific bracket format:
    //
    //  2 groups →  4 teams:  SF → Final/3rd
    //  3 groups →  6 teams:  ELIM(2) → SF → Final/3rd
    //  4 groups →  8 teams:  QF → SF → Final/3rd
    //  5 groups → 10 teams:  ELIM(2) → QF → SF → Final/3rd   ✅ tested/working
    //  6 groups → 12 teams:  ELIM(4) → QF → SF → Final/3rd
    //  7 groups → 14 teams:  ELIM(6) → QF → SF → Final/3rd
    //  8 groups → 16 teams:  R16 → QF → SF → Final/3rd
    //  9 groups → 18 teams:  ELIM(2) → R16 → QF → SF → Final/3rd

    $drawMethod = "group_count_{$totalGroups}";

    if ($totalGroups === 2) {
        // ══════════════════════════════════════════════════════════════
        // 2 GROUPS → 4 TEAMS:  SF → Final/3rd
        // Seeds: 1–4
        //   SF1: Seed 1 vs Seed 4
        //   SF2: Seed 2 vs Seed 3
        // ══════════════════════════════════════════════════════════════
        $sfType = 'semi-finals';

        $s1 = $overallSeeds[1] ?? null;
        $s2 = $overallSeeds[2] ?? null;
        $s3 = $overallSeeds[3] ?? null;
        $s4 = $overallSeeds[4] ?? null;

        // SF1: Seed 1 vs Seed 4
        if ($s1 && $s4) {
            $r = seedIntoMatchTogether($conn, $sfType, $s1, $s4, $referee_id, $category_id);
            $seedingLog['sf_matches'][] = ['match' => 'SF1: Seed 1 vs Seed 4', 'home' => $s1, 'away' => $s4, 'result' => $r];
        }
        // SF2: Seed 2 vs Seed 3
        if ($s2 && $s3) {
            $r = seedIntoMatchTogether($conn, $sfType, $s2, $s3, $referee_id, $category_id);
            $seedingLog['sf_matches'][] = ['match' => 'SF2: Seed 2 vs Seed 3', 'home' => $s2, 'away' => $s3, 'result' => $r];
        }

    } elseif ($totalGroups === 3) {
        // ══════════════════════════════════════════════════════════════
        // 3 GROUPS → 6 TEAMS:  ELIM(2) → SF → Final/3rd
        // Seeds: 1–6
        //   ELIM M1: Seed 3 vs Seed 6
        //   ELIM M2: Seed 4 vs Seed 5
        //   SF1: Seed 1 vs Winner(4/5)   ← Seed 1 BYE, ELIM M2 winner joins
        //   SF2: Seed 2 vs Winner(3/6)   ← Seed 2 BYE, ELIM M1 winner joins
        // ══════════════════════════════════════════════════════════════
        $elimType = 'elimination';
        $sfType   = 'semi-finals';

        $s1 = $overallSeeds[1] ?? null;
        $s2 = $overallSeeds[2] ?? null;
        $s3 = $overallSeeds[3] ?? null;
        $s4 = $overallSeeds[4] ?? null;
        $s5 = $overallSeeds[5] ?? null;
        $s6 = $overallSeeds[6] ?? null;

        // ELIM M1: Seed 3 vs Seed 6
        if ($s3 && $s6) {
            $r = seedIntoMatchTogether($conn, $elimType, $s3, $s6, $referee_id, $category_id);
            $seedingLog['elim_matches'][] = ['match' => 'ELIM M1: Seed 3 vs Seed 6', 'home' => $s3, 'away' => $s6, 'result' => $r];
        }
        // ELIM M2: Seed 4 vs Seed 5
        if ($s4 && $s5) {
            $r = seedIntoMatchTogether($conn, $elimType, $s4, $s5, $referee_id, $category_id);
            $seedingLog['elim_matches'][] = ['match' => 'ELIM M2: Seed 4 vs Seed 5', 'home' => $s4, 'away' => $s5, 'result' => $r];
        }

        // SF seeding order (must match slotMaps for elimination→semi-finals):
        // ELIM M1 winner → SF slot 1 (alongside Seed 2)
        // ELIM M2 winner → SF slot 0 (alongside Seed 1)
        // So seed the fully-known pairs first, then the BYE seeds into empty slots.

        // SF2: Seed 2 (BYE) — awaiting ELIM M1 winner (Seed 3 or 6)
        if ($s2) {
            $r = seedIntoEmptySlot($conn, $sfType, $s2, $referee_id);
            $seedingLog['sf_matches'][] = ['match' => 'SF2: Seed 2 (awaiting ELIM M1 winner 3/6)', 'home' => $s2, 'result' => $r];
        }
        // SF1: Seed 1 (BYE) — awaiting ELIM M2 winner (Seed 4 or 5)
        if ($s1) {
            $r = seedIntoEmptySlot($conn, $sfType, $s1, $referee_id);
            $seedingLog['sf_matches'][] = ['match' => 'SF1: Seed 1 (awaiting ELIM M2 winner 4/5)', 'home' => $s1, 'result' => $r];
        }

    } elseif ($totalGroups === 4) {
        // ══════════════════════════════════════════════════════════════
        // 4 GROUPS → 8 TEAMS:  QF → SF → Final/3rd
        // Seeds: 1–8
        //   QF1: Seed 1 vs Seed 8
        //   QF2: Seed 2 vs Seed 7
        //   QF3: Seed 3 vs Seed 6
        //   QF4: Seed 4 vs Seed 5
        //   SF1: Winner QF1 vs Winner QF4
        //   SF2: Winner QF2 vs Winner QF3
        // ══════════════════════════════════════════════════════════════
        $qfType = 'quarter-finals';

        $s1 = $overallSeeds[1] ?? null;
        $s2 = $overallSeeds[2] ?? null;
        $s3 = $overallSeeds[3] ?? null;
        $s4 = $overallSeeds[4] ?? null;
        $s5 = $overallSeeds[5] ?? null;
        $s6 = $overallSeeds[6] ?? null;
        $s7 = $overallSeeds[7] ?? null;
        $s8 = $overallSeeds[8] ?? null;

        // QF3: Seed 3 vs Seed 6 (seed together first — fully known)
        if ($s3 && $s6) {
            $r = seedIntoMatchTogether($conn, $qfType, $s3, $s6, $referee_id, $category_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF3: Seed 3 vs Seed 6', 'home' => $s3, 'away' => $s6, 'result' => $r];
        }
        // QF4: Seed 4 vs Seed 5
        if ($s4 && $s5) {
            $r = seedIntoMatchTogether($conn, $qfType, $s4, $s5, $referee_id, $category_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF4: Seed 4 vs Seed 5', 'home' => $s4, 'away' => $s5, 'result' => $r];
        }
        // QF1: Seed 1 vs Seed 8
        if ($s1 && $s8) {
            $r = seedIntoMatchTogether($conn, $qfType, $s1, $s8, $referee_id, $category_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF1: Seed 1 vs Seed 8', 'home' => $s1, 'away' => $s8, 'result' => $r];
        }
        // QF2: Seed 2 vs Seed 7
        if ($s2 && $s7) {
            $r = seedIntoMatchTogether($conn, $qfType, $s2, $s7, $referee_id, $category_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF2: Seed 2 vs Seed 7', 'home' => $s2, 'away' => $s7, 'result' => $r];
        }

    } elseif ($totalGroups === 5) {
        // ══════════════════════════════════════════════════════════════
        // 5 GROUPS → 10 TEAMS:  ELIM(2) → QF(4) → SF → Final/3rd
        // Seeds: 1–10
        //   ELIM M1: Seed 7  vs Seed 10
        //   ELIM M2: Seed 8  vs Seed 9
        //   QF1: Seed 1 vs Winner(8/9)   ← Seed 1 BYE
        //   QF2: Seed 2 vs Winner(7/10)  ← Seed 2 BYE
        //   QF3: Seed 3 vs Seed 6
        //   QF4: Seed 4 vs Seed 5
        //   SF1: Winner QF1 vs Winner QF4
        //   SF2: Winner QF2 vs Winner QF3
        // ══════════════════════════════════════════════════════════════
        $elimType = 'elimination';
        $qfType   = 'quarter-finals';

        $s1  = $overallSeeds[1]  ?? null;
        $s2  = $overallSeeds[2]  ?? null;
        $s3  = $overallSeeds[3]  ?? null;
        $s4  = $overallSeeds[4]  ?? null;
        $s5  = $overallSeeds[5]  ?? null;
        $s6  = $overallSeeds[6]  ?? null;
        $s7  = $overallSeeds[7]  ?? null;
        $s8  = $overallSeeds[8]  ?? null;
        $s9  = $overallSeeds[9]  ?? null;
        $s10 = $overallSeeds[10] ?? null;

        // ELIM M1: Seed 7 vs Seed 10
        if ($s7 && $s10) {
            $r = seedIntoMatchTogether($conn, $elimType, $s7, $s10, $referee_id, $category_id);
            $seedingLog['elim_matches'][] = ['match' => 'ELIM M1: Seed 7 vs Seed 10', 'home' => $s7, 'away' => $s10, 'result' => $r];
        }
        // ELIM M2: Seed 8 vs Seed 9
        if ($s8 && $s9) {
            $r = seedIntoMatchTogether($conn, $elimType, $s8, $s9, $referee_id, $category_id);
            $seedingLog['elim_matches'][] = ['match' => 'ELIM M2: Seed 8 vs Seed 9', 'home' => $s8, 'away' => $s9, 'result' => $r];
        }

        // QF seeding — seed fully-known pairs first (seedIntoMatchTogether),
        // then BYE seeds into empty slots (seedIntoEmptySlot) to avoid
        // accidentally sharing a half-filled slot.
        // QF3: Seed 3 vs Seed 6
        if ($s3 && $s6) {
            $r = seedIntoMatchTogether($conn, $qfType, $s3, $s6, $referee_id, $category_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF3: Seed 3 vs Seed 6', 'home' => $s3, 'away' => $s6, 'result' => $r];
        }
        // QF4: Seed 4 vs Seed 5
        if ($s4 && $s5) {
            $r = seedIntoMatchTogether($conn, $qfType, $s4, $s5, $referee_id, $category_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF4: Seed 4 vs Seed 5', 'home' => $s4, 'away' => $s5, 'result' => $r];
        }
        // QF1: Seed 1 (BYE) — ELIM M2 winner (8/9) joins later
        if ($s1) {
            $r = seedIntoEmptySlot($conn, $qfType, $s1, $referee_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF1: Seed 1 (awaiting ELIM winner 8/9)', 'home' => $s1, 'result' => $r];
        }
        // QF2: Seed 2 (BYE) — ELIM M1 winner (7/10) joins later
        if ($s2) {
            $r = seedIntoEmptySlot($conn, $qfType, $s2, $referee_id);
            $seedingLog['qf_matches'][] = ['match' => 'QF2: Seed 2 (awaiting ELIM winner 7/10)', 'home' => $s2, 'result' => $r];
        }

    } elseif ($totalGroups === 6) {
        // ══════════════════════════════════════════════════════════════
        // 6 GROUPS → 12 TEAMS:  ELIM(4) → QF(4) → SF → Final/3rd
        // Seeds: 1–12
        //   ELIM M1: Seed 5  vs Seed 12
        //   ELIM M2: Seed 6  vs Seed 11
        //   ELIM M3: Seed 7  vs Seed 10
        //   ELIM M4: Seed 8  vs Seed 9
        //   QF1: Seed 1 vs Winner(8/9)    ← Seed 1 BYE
        //   QF2: Seed 2 vs Winner(7/10)   ← Seed 2 BYE
        //   QF3: Seed 3 vs Winner(6/11)   ← Seed 3 BYE
        //   QF4: Seed 4 vs Winner(5/12)   ← Seed 4 BYE
        //   SF1: Winner QF1 vs Winner QF4
        //   SF2: Winner QF2 vs Winner QF3
        // ══════════════════════════════════════════════════════════════
        $elimType = 'elimination';
        $qfType   = 'quarter-finals';

        $s1  = $overallSeeds[1]  ?? null;
        $s2  = $overallSeeds[2]  ?? null;
        $s3  = $overallSeeds[3]  ?? null;
        $s4  = $overallSeeds[4]  ?? null;
        $s5  = $overallSeeds[5]  ?? null;
        $s6  = $overallSeeds[6]  ?? null;
        $s7  = $overallSeeds[7]  ?? null;
        $s8  = $overallSeeds[8]  ?? null;
        $s9  = $overallSeeds[9]  ?? null;
        $s10 = $overallSeeds[10] ?? null;
        $s11 = $overallSeeds[11] ?? null;
        $s12 = $overallSeeds[12] ?? null;

        // ELIM matches (all fully-known pairs)
        if ($s5  && $s12) { $r = seedIntoMatchTogether($conn, $elimType, $s5,  $s12, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M1: Seed 5 vs Seed 12',  'home' => $s5,  'away' => $s12, 'result' => $r]; }
        if ($s6  && $s11) { $r = seedIntoMatchTogether($conn, $elimType, $s6,  $s11, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M2: Seed 6 vs Seed 11',  'home' => $s6,  'away' => $s11, 'result' => $r]; }
        if ($s7  && $s10) { $r = seedIntoMatchTogether($conn, $elimType, $s7,  $s10, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M3: Seed 7 vs Seed 10',  'home' => $s7,  'away' => $s10, 'result' => $r]; }
        if ($s8  && $s9)  { $r = seedIntoMatchTogether($conn, $elimType, $s8,  $s9,  $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M4: Seed 8 vs Seed 9',   'home' => $s8,  'away' => $s9,  'result' => $r]; }

        // QF BYE seeds — all 4 top seeds wait for ELIM winners.
        // Must use seedIntoEmptySlot so they each land in their own fresh slot
        // (no two BYE seeds should share a slot before their ELIM partner arrives).
        // Seeding order: QF4, QF3, QF2, QF1 to fill slots from last to first,
        // ensuring ELIM winners (via PATH B seedIntoRound) land in the correct slots.
        // Actually we seed QF1→QF4 in order (slots fill chronologically).
        if ($s1) { $r = seedIntoEmptySlot($conn, $qfType, $s1, $referee_id); $seedingLog['qf_matches'][] = ['match' => 'QF1: Seed 1 (awaiting ELIM winner 8/9)',   'home' => $s1, 'result' => $r]; }
        if ($s2) { $r = seedIntoEmptySlot($conn, $qfType, $s2, $referee_id); $seedingLog['qf_matches'][] = ['match' => 'QF2: Seed 2 (awaiting ELIM winner 7/10)',  'home' => $s2, 'result' => $r]; }
        if ($s3) { $r = seedIntoEmptySlot($conn, $qfType, $s3, $referee_id); $seedingLog['qf_matches'][] = ['match' => 'QF3: Seed 3 (awaiting ELIM winner 6/11)',  'home' => $s3, 'result' => $r]; }
        if ($s4) { $r = seedIntoEmptySlot($conn, $qfType, $s4, $referee_id); $seedingLog['qf_matches'][] = ['match' => 'QF4: Seed 4 (awaiting ELIM winner 5/12)',  'home' => $s4, 'result' => $r]; }

    } elseif ($totalGroups === 7) {
        // ══════════════════════════════════════════════════════════════
        // 7 GROUPS → 14 TEAMS:  ELIM(6) → QF(4) → SF → Final/3rd
        // Seeds: 1–14
        //   ELIM M1: Seed 3  vs Seed 14
        //   ELIM M2: Seed 4  vs Seed 13
        //   ELIM M3: Seed 5  vs Seed 12
        //   ELIM M4: Seed 6  vs Seed 11
        //   ELIM M5: Seed 7  vs Seed 10
        //   ELIM M6: Seed 8  vs Seed 9
        //   QF1: Seed 1 vs Winner(8/9)             ← Seed 1 BYE
        //   QF2: Seed 2 vs Winner(7/10)            ← Seed 2 BYE
        //   QF3: Winner(3/14) vs Winner(6/11)      ← both TBD
        //   QF4: Winner(4/13) vs Winner(5/12)      ← both TBD
        //   SF1: Winner QF1 vs Winner QF4
        //   SF2: Winner QF2 vs Winner QF3
        // ══════════════════════════════════════════════════════════════
        $elimType = 'elimination';
        $qfType   = 'quarter-finals';

        $s1  = $overallSeeds[1]  ?? null;
        $s2  = $overallSeeds[2]  ?? null;
        $s3  = $overallSeeds[3]  ?? null;
        $s4  = $overallSeeds[4]  ?? null;
        $s5  = $overallSeeds[5]  ?? null;
        $s6  = $overallSeeds[6]  ?? null;
        $s7  = $overallSeeds[7]  ?? null;
        $s8  = $overallSeeds[8]  ?? null;
        $s9  = $overallSeeds[9]  ?? null;
        $s10 = $overallSeeds[10] ?? null;
        $s11 = $overallSeeds[11] ?? null;
        $s12 = $overallSeeds[12] ?? null;
        $s13 = $overallSeeds[13] ?? null;
        $s14 = $overallSeeds[14] ?? null;

        // ELIM matches
        if ($s3  && $s14) { $r = seedIntoMatchTogether($conn, $elimType, $s3,  $s14, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M1: Seed 3 vs Seed 14',  'home' => $s3,  'away' => $s14, 'result' => $r]; }
        if ($s4  && $s13) { $r = seedIntoMatchTogether($conn, $elimType, $s4,  $s13, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M2: Seed 4 vs Seed 13',  'home' => $s4,  'away' => $s13, 'result' => $r]; }
        if ($s5  && $s12) { $r = seedIntoMatchTogether($conn, $elimType, $s5,  $s12, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M3: Seed 5 vs Seed 12',  'home' => $s5,  'away' => $s12, 'result' => $r]; }
        if ($s6  && $s11) { $r = seedIntoMatchTogether($conn, $elimType, $s6,  $s11, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M4: Seed 6 vs Seed 11',  'home' => $s6,  'away' => $s11, 'result' => $r]; }
        if ($s7  && $s10) { $r = seedIntoMatchTogether($conn, $elimType, $s7,  $s10, $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M5: Seed 7 vs Seed 10',  'home' => $s7,  'away' => $s10, 'result' => $r]; }
        if ($s8  && $s9)  { $r = seedIntoMatchTogether($conn, $elimType, $s8,  $s9,  $referee_id, $category_id); $seedingLog['elim_matches'][] = ['match' => 'ELIM M6: Seed 8 vs Seed 9',   'home' => $s8,  'away' => $s9,  'result' => $r]; }

        // QF slots:
        //   QF3 and QF4 are fully TBD (both teams come from ELIM winners).
        //   QF1 and QF2 each have one known BYE seed + one ELIM winner.
        //
        // Seed QF1 & QF2 BYE seeds into empty slots first.
        // QF3 & QF4 remain empty — PATH B will fill them when ELIM winners arrive.
        if ($s1) { $r = seedIntoEmptySlot($conn, $qfType, $s1, $referee_id); $seedingLog['qf_matches'][] = ['match' => 'QF1: Seed 1 (awaiting ELIM winner 8/9)',          'home' => $s1, 'result' => $r]; }
        if ($s2) { $r = seedIntoEmptySlot($conn, $qfType, $s2, $referee_id); $seedingLog['qf_matches'][] = ['match' => 'QF2: Seed 2 (awaiting ELIM winner 7/10)',         'home' => $s2, 'result' => $r]; }
        // QF3 & QF4 left empty — ELIM winners land via seedIntoRound in PATH B

    } elseif ($totalGroups === 8) {
        // ══════════════════════════════════════════════════════════════
        // 8 GROUPS → 16 TEAMS:  R16(8) → QF → SF → Final/3rd
        // Seeds: 1–16 — all R16 matches are fully determined now.
        //   R16 M1:  Seed 1  vs Seed 16
        //   R16 M2:  Seed 2  vs Seed 15
        //   R16 M3:  Seed 3  vs Seed 14
        //   R16 M4:  Seed 4  vs Seed 13
        //   R16 M5:  Seed 5  vs Seed 12
        //   R16 M6:  Seed 6  vs Seed 11
        //   R16 M7:  Seed 7  vs Seed 10
        //   R16 M8:  Seed 8  vs Seed 9
        // QF / SF progression handled by PATH B pairing maps.
        // ══════════════════════════════════════════════════════════════
        $r16Type = 'round-of-16';

        for ($i = 1; $i <= 8; $i++) {
            $high = $overallSeeds[$i]        ?? null;
            $low  = $overallSeeds[17 - $i]   ?? null;
            if ($high && $low) {
                $r = seedIntoMatchTogether($conn, $r16Type, $high, $low, $referee_id, $category_id);
                $seedingLog['r16_matches'][] = [
                    'match'  => "R16 M{$i}: Seed {$i} vs Seed " . (17 - $i),
                    'home'   => $high,
                    'away'   => $low,
                    'result' => $r,
                ];
            }
        }

    } elseif ($totalGroups === 9) {
        // ══════════════════════════════════════════════════════════════
        // 9 GROUPS → 18 TEAMS:  ELIM(2) → R16(8) → QF → SF → Final/3rd
        // Seeds: 1–18
        //   ELIM M1: Seed 15 vs Seed 18
        //   ELIM M2: Seed 16 vs Seed 17
        //   R16 M1: Seed 1  vs Winner(16/17)   ← Seed 1 BYE
        //   R16 M2: Seed 2  vs Winner(15/18)   ← Seed 2 BYE
        //   R16 M3: Seed 3  vs Seed 14
        //   R16 M4: Seed 4  vs Seed 13
        //   R16 M5: Seed 5  vs Seed 12
        //   R16 M6: Seed 6  vs Seed 11
        //   R16 M7: Seed 7  vs Seed 10
        //   R16 M8: Seed 8  vs Seed 9
        // QF / SF progression via PATH B pairing maps.
        // ══════════════════════════════════════════════════════════════
        $elimType = 'elimination';
        $r16Type  = 'round-of-16';

        $s1  = $overallSeeds[1]  ?? null;
        $s2  = $overallSeeds[2]  ?? null;

        // ── R16 layout (slot order = DB match_id ASC) ──────────────────
        // slot 0: Seed 3  vs Seed 14
        // slot 1: Seed 5  vs Seed 12
        // slot 2: Seed 7  vs Seed 10
        // slot 3: Seed 1  (BYE) awaiting ELIM M1 winner  ← gitna top
        // slot 4: Seed 2  (BYE) awaiting ELIM M2 winner  ← gitna bottom
        // slot 5: Seed 9  vs Seed 8
        // slot 6: Seed 11 vs Seed 6
        // slot 7: Seed 13 vs Seed 4
        //
        // ELIM M1: Seed 17 vs Seed 18  → winner joins Seed 1 at slot 3
        // ELIM M2: Seed 15 vs Seed 16  → winner joins Seed 2 at slot 4

        // ELIM M1: Seed 17 vs Seed 18
        $s17 = $overallSeeds[17] ?? null;
        $s18 = $overallSeeds[18] ?? null;
        if ($s17 && $s18) {
            $r = seedIntoMatchTogether($conn, $elimType, $s17, $s18, $referee_id, $category_id);
            $seedingLog['elim_matches'][] = ['match' => 'ELIM M1: Seed 17 vs Seed 18', 'home' => $s17, 'away' => $s18, 'result' => $r];
        }
        // ELIM M2: Seed 15 vs Seed 16
        $s15 = $overallSeeds[15] ?? null;
        $s16 = $overallSeeds[16] ?? null;
        if ($s15 && $s16) {
            $r = seedIntoMatchTogether($conn, $elimType, $s15, $s16, $referee_id, $category_id);
            $seedingLog['elim_matches'][] = ['match' => 'ELIM M2: Seed 15 vs Seed 16', 'home' => $s15, 'away' => $s16, 'result' => $r];
        }

        // R16 slots 0,1,2 — direct matchups (seeded first so they fill slots 0,1,2)
        // slot 0: Seed 3  vs Seed 14
        // slot 1: Seed 5  vs Seed 12
        // slot 2: Seed 7  vs Seed 10
        $topPairs = [[3,14],[5,12],[7,10]];
        foreach ($topPairs as $pair) {
            $high = $overallSeeds[$pair[0]] ?? null;
            $low  = $overallSeeds[$pair[1]] ?? null;
            if ($high && $low) {
                $r = seedIntoMatchTogether($conn, $r16Type, $high, $low, $referee_id, $category_id);
                $seedingLog['r16_matches'][] = ['match' => "R16: Seed {$pair[0]} vs Seed {$pair[1]}", 'home' => $high, 'away' => $low, 'result' => $r];
            }
        }

        // R16 slots 3,4 — BYE seeds (Seed 1 & 2 await ELIM winners)
        // seedIntoEmptySlot fills the next completely empty slot → slots 3 then 4
        if ($s1) { $r = seedIntoEmptySlot($conn, $r16Type, $s1, $referee_id); $seedingLog['r16_matches'][] = ['match' => 'R16 slot 3: Seed 1 BYE (awaiting ELIM M1 winner)', 'home' => $s1, 'result' => $r]; }
        if ($s2) { $r = seedIntoEmptySlot($conn, $r16Type, $s2, $referee_id); $seedingLog['r16_matches'][] = ['match' => 'R16 slot 4: Seed 2 BYE (awaiting ELIM M2 winner)', 'home' => $s2, 'result' => $r]; }

        // R16 slots 5,6,7 — direct matchups (seeded after BYEs so they fill slots 5,6,7)
        // slot 5: Seed 9  vs Seed 8
        // slot 6: Seed 11 vs Seed 6
        // slot 7: Seed 13 vs Seed 4
        $botPairs = [[9,8],[11,6],[13,4]];
        foreach ($botPairs as $pair) {
            $high = $overallSeeds[$pair[0]] ?? null;
            $low  = $overallSeeds[$pair[1]] ?? null;
            if ($high && $low) {
                $r = seedIntoMatchTogether($conn, $r16Type, $high, $low, $referee_id, $category_id);
                $seedingLog['r16_matches'][] = ['match' => "R16: Seed {$pair[0]} vs Seed {$pair[1]}", 'home' => $high, 'away' => $low, 'result' => $r];
            }
        }

    } else {
        // ── Fallback: unknown group count — classic group-pair draw ───
        // Standard FIFA World Cup draw:  (A,B), (C,D), (E,F) …
        //   Match N:   1A vs 2B
        //   Match N+1: 1B vs 2A
        for ($i = 0; $i < count($sortedLabels); $i += 2) {
            $labelA = $sortedLabels[$i];
            $labelB = $sortedLabels[$i + 1] ?? $labelA;

            $rank1A = $groupResults[$labelA][1] ?? null;
            $rank2A = $groupResults[$labelA][2] ?? null;
            $rank1B = $groupResults[$labelB][1] ?? null;
            $rank2B = $groupResults[$labelB][2] ?? null;

            if ($rank1A && $rank2B) {
                $r = seedIntoMatchTogether($conn, $nextKnockoutType, $rank1A, $rank2B, $referee_id, $category_id);
                $seedingLog['group_pair_matches'][] = ['match' => "1{$labelA} vs 2{$labelB}", 'result' => $r];
            }
            if ($labelA !== $labelB && $rank1B && $rank2A) {
                $r = seedIntoMatchTogether($conn, $nextKnockoutType, $rank1B, $rank2A, $referee_id, $category_id);
                $seedingLog['group_pair_matches'][] = ['match' => "1{$labelB} vs 2{$labelA}", 'result' => $r];
            }
        }
    }

    $conn->close();

    echo json_encode([
        'success'         => true,
        'status'          => 'group_complete',
        'group_label'     => $groupLabel,
        'groups_complete' => $doneGroups,
        'groups_total'    => $totalGroups,
        'next_round'      => $nextKnockoutType,
        'draw_executed'   => true,
        'draw_method'     => $drawMethod,
        'seeding_log'     => $seedingLog,
        'standings'       => $rows,
        // rank1/rank2 for THIS group — used by the Dart snackbar message
        'rank1_team_id'   => $rank1TeamId,
        'rank1_team_name' => $rows[0]['team_name'] ?? '',
        'rank2_team_id'   => $rank2TeamId,
        'rank2_team_name' => $rows[1]['team_name'] ?? '',
        'message'         => "All $totalGroups groups complete. FIFA draw executed into $nextKnockoutType.",
    ]);
    exit();
}

// ═════════════════════════════════════════════════════════════════════
// PATH B — KNOCKOUT ROUNDS  (FIFA-correct bracket pairing)
//
// Pairing rules (verified against FIFA draw):
//
//   R16  (8 matches) — FIFA draw seeding:
//     M1: 1st A vs 2nd B  |  M2: 1st B vs 2nd A
//     M3: 1st C vs 2nd D  |  M4: 1st D vs 2nd C
//     M5: 1st E vs 2nd F  |  M6: 1st F vs 2nd E
//     M7: 1st G vs 2nd H  |  M8: 1st H vs 2nd G
//
//   R16 → QF  (4 matches):
//     QF1: Winner M1 vs Winner M3  (pos 1 & 3 → QF slot 0)
//     QF2: Winner M2 vs Winner M4  (pos 2 & 4 → QF slot 1)
//     QF3: Winner M5 vs Winner M7  (pos 5 & 7 → QF slot 2)
//     QF4: Winner M6 vs Winner M8  (pos 6 & 8 → QF slot 3)
//
//   QF → SF  (2 matches):
//     SF1: Winner QF1 vs Winner QF2  (pos 1 & 2 → SF slot 0)
//     SF2: Winner QF3 vs Winner QF4  (pos 3 & 4 → SF slot 1)
//
//   SF → Final + 3rd-place:
//     Final: Winner SF1 vs Winner SF2  (pos 1 & 2 → Final)
//     losers → 3rd-place
//
// Strategy:
//   - Get the 1-based position of match_id within its round
//     (ordered by schedule_start ASC, match_id ASC).
//   - Derive which next-round slot this winner belongs to and
//     which match is its "partner".
//   - If the partner is NOT yet scored → winner is the FIRST to
//     arrive: seed alone via seedIntoRound() as a placeholder.
//   - If the partner IS already scored → winner is the SECOND to
//     arrive: find the already-seeded placeholder and pair them
//     together via seedIntoMatchTogether().
// ═════════════════════════════════════════════════════════════════════

// ── B1. No advancement for final or third-place ───────────────────────
if ($currentType === 'final' || $currentType === 'third-place') {
    echo json_encode([
        'success' => true,
        'message' => 'No advancement needed for ' . $currentType,
    ]);
    exit();
}

// ── B2. Determine next round ──────────────────────────────────────────
$knownOrder = [
    'elimination', 'round-of-32', 'round-of-16',
    'quarter-finals', 'semi-finals', 'third-place', 'final'
];

$roundsStmt = $conn->prepare("
    SELECT DISTINCT m.bracket_type
    FROM   tbl_match m
    WHERE  m.bracket_type IN (
               'elimination', 'round-of-32', 'round-of-16',
               'quarter-finals', 'semi-finals', 'third-place', 'final'
           )
");
$roundsStmt->execute();
$roundsResult = $roundsStmt->get_result();
$roundsStmt->close();

$presentRounds = [];
while ($r = $roundsResult->fetch_assoc()) {
    // Exclude third-place — it is a parallel branch, not a sequential round
    if ($r['bracket_type'] === 'third-place') continue;
    $presentRounds[] = $r['bracket_type'];
}
usort($presentRounds, function ($a, $b) use ($knownOrder) {
    return array_search($a, $knownOrder) - array_search($b, $knownOrder);
});

$nextWinnerType = null;
$nextLoserType  = null;

if ($currentType === 'semi-finals') {
    $nextWinnerType = 'final';
    $nextLoserType  = 'third-place';
} else {
    $curIdx = array_search($currentType, $presentRounds);
    if ($curIdx !== false && $curIdx + 1 < count($presentRounds)) {
        $nextWinnerType = $presentRounds[$curIdx + 1];
    } else {
        $nextWinnerType = 'final';
    }
}

// ── B3. Get default referee ───────────────────────────────────────────
$refStmt = $conn->prepare(
    "SELECT referee_id FROM tbl_referee ORDER BY referee_id ASC LIMIT 1"
);
$refStmt->execute();
$refRow     = $refStmt->get_result()->fetch_assoc();
$refStmt->close();
$referee_id = $refRow ? intval($refRow['referee_id']) : 1;

// ── B4. Get 1-based position of current match within its round ────────
// Ordered by schedule_start ASC, match_id ASC — same order used when
// slots were originally created.
$posStmt = $conn->prepare("
    SELECT m.match_id
    FROM   tbl_match m
    LEFT   JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
    WHERE  m.bracket_type = ?
    ORDER  BY s.schedule_start ASC, m.match_id ASC
");
$posStmt->bind_param('s', $currentType);
$posStmt->execute();
$posRes = $posStmt->get_result();
$posStmt->close();

$allMatchIds   = [];
$currentPos    = null;   // 1-based
$posIndex      = 1;
while ($pr = $posRes->fetch_assoc()) {
    $allMatchIds[] = intval($pr['match_id']);
    if (intval($pr['match_id']) === $match_id) {
        $currentPos = $posIndex;
    }
    $posIndex++;
}

if ($currentPos === null) {
    // Fallback: position unknown, use simple seedIntoRound
    $winnerResult = seedIntoRound($conn, $nextWinnerType, $winner_team_id, $referee_id, $category_id);
    $loserResult  = ['seeded' => false];
    if ($nextLoserType && $loser_team_id > 0) {
        $loserResult = seedIntoRound($conn, $nextLoserType, $loser_team_id, $referee_id, $category_id);
    }
    $conn->close();
    echo json_encode([
        'success'            => true,
        'current_round'      => $currentType,
        'winner_advanced_to' => $nextWinnerType,
        'winner_seeded'      => $winnerResult['seeded'] ?? false,
        'winner_detail'      => $winnerResult,
        'message'            => 'Advancement complete (fallback: position unknown)',
    ]);
    exit();
}

// ── B5. Derive partner position using bracket pairing maps ────────────
//
// Pairing maps: which match positions share the same next-round slot.
// slotMaps: the 0-based next-round slot index each position maps to.
//
// ELIMINATION routing depends on total group count:
//   3 groups  (ELIM→SF):   M1→slot1, M2→slot0   (no ELIM partners)
//   5 groups  (ELIM→QF):   M1→slot3, M2→slot2   (no ELIM partners)
//   6 groups  (ELIM→QF):   M1→slot3, M2→slot2, M3→slot1, M4→slot0
//   7 groups  (ELIM→QF):   M1→slot0 (w/ BYE Seed1),
//                           M2↔M3→slot1, M4↔M5→slot2,
//                           M6→slot3 (w/ BYE Seed2)
//   9 groups  (ELIM→R16):  M1→slot3 (w/ Seed1 BYE), M2→slot4 (w/ Seed2 BYE)
//
// R16 → QF: M1↔M3(slot0), M2↔M4(slot1), M5↔M7(slot2), M6↔M8(slot3)
// QF  → SF: QF1↔QF2(slot0), QF3↔QF4(slot1)
// SF  → Final: SF1↔SF2(slot0)

// Detect group count to pick the right ELIM routing
$grpCountStmt = $conn->prepare("
    SELECT COUNT(DISTINCT group_label) AS grp_count
    FROM   tbl_soccer_groups
    WHERE  category_id = ?
");
$grpCountStmt->bind_param('i', $category_id);
$grpCountStmt->execute();
$grpCountRow = $grpCountStmt->get_result()->fetch_assoc();
$grpCountStmt->close();
$totalGroupsForSlot = intval($grpCountRow['grp_count'] ?? 0);

$elimSlotMapByGroupCount = [
    3 => [1 => 1, 2 => 0],
    5 => [1 => 3, 2 => 2],
    6 => [1 => 3, 2 => 2, 3 => 1, 4 => 0],
    // 7 groups: ELIM M1→QF slot0 (w/ BYE Seed1), M2&M3→slot1, M4&M5→slot2, M6→slot3 (w/ BYE Seed2)
    7 => [1 => 0, 2 => 1, 3 => 1, 4 => 2, 5 => 2, 6 => 3],
    9 => [1 => 3, 2 => 4],  // ELIM M1→R16 slot3 (Seed1 BYE), ELIM M2→R16 slot4 (Seed2 BYE)
];
$elimPairingMapByGroupCount = [
    3 => [],
    5 => [],
    6 => [],
    7 => [2 => 3, 3 => 2, 4 => 5, 5 => 4],  // M2↔M3 share slot1, M4↔M5 share slot2
    9 => [],
];

// R16 pairing depends on group count:
//   9 groups: adjacent pairs → 1↔2(QF0), 3↔4(QF1), 5↔6(QF2), 7↔8(QF3)
//   8 groups: cross pairs   → 1↔3(QF0), 2↔4(QF1), 5↔7(QF2), 6↔8(QF3)
$r16PairingMap = ($totalGroupsForSlot === 9)
    ? [1=>2, 2=>1, 3=>4, 4=>3, 5=>6, 6=>5, 7=>8, 8=>7]
    : [1=>3, 3=>1, 2=>4, 4=>2, 5=>7, 7=>5, 6=>8, 8=>6];
$r16SlotMap = ($totalGroupsForSlot === 9)
    ? [1=>0, 2=>0, 3=>1, 4=>1, 5=>2, 6=>2, 7=>3, 8=>3]
    : [1=>0, 3=>0, 2=>1, 4=>1, 5=>2, 7=>2, 6=>3, 8=>3];

$pairingMaps = [
    'elimination'    => $elimPairingMapByGroupCount[$totalGroupsForSlot] ?? [],
    'round-of-32'    => [],
    'round-of-16'    => $r16PairingMap,
    'quarter-finals' => [1=>2, 2=>1, 3=>4, 4=>3],
    'semi-finals'    => [1=>2, 2=>1],
];
$slotMaps = [
    'elimination'    => $elimSlotMapByGroupCount[$totalGroupsForSlot] ?? [],
    'round-of-16'    => $r16SlotMap,
    'quarter-finals' => [1=>0, 2=>0, 3=>1, 4=>1],
    'semi-finals'    => [1=>0, 2=>0],
];

$pairingMap = $pairingMaps[$currentType] ?? [];
$slotMap    = $slotMaps[$currentType]    ?? [];

$partnerPos = $pairingMap[$currentPos] ?? null;
$slotIndex  = $slotMap[$currentPos]    ?? null;

// ── B6. Check if partner match is already scored ──────────────────────
$partnerMatchId  = ($partnerPos !== null) ? ($allMatchIds[$partnerPos - 1] ?? null) : null;
$partnerIsScored = false;

if ($partnerMatchId) {
    $pScoreStmt = $conn->prepare("
        SELECT COUNT(*) AS cnt FROM tbl_score WHERE match_id = ?
    ");
    $pScoreStmt->bind_param('i', $partnerMatchId);
    $pScoreStmt->execute();
    $pScoreRow = $pScoreStmt->get_result()->fetch_assoc();
    $pScoreStmt->close();
    $partnerIsScored = intval($pScoreRow['cnt']) >= 2;
}

// ── B7. Seed winner into next round ───────────────────────────────────
$winnerResult = ['seeded' => false];
$loserResult  = ['seeded' => false];

if ($nextWinnerType && $winner_team_id > 0) {

    if ($partnerPos === null || $slotIndex === null) {
        // No pairing map for this round — fallback to simple slot fill
        $winnerResult = seedIntoRound($conn, $nextWinnerType, $winner_team_id, $referee_id, $category_id);

    } else {
        // ── Shared: resolve the ordered list of next-round match IDs ─────────
        // Used by BOTH the "partner not yet scored" (placeholder) path
        // and the "partner already scored" (pair-up) path.
        // Both need to target the SAME slot ($slotIndex) so winners from
        // the correct pairing (e.g. M1 & M3 → QF slot 0) always land together.
        $nrStmt = $conn->prepare("
            SELECT m.match_id
            FROM   tbl_match m
            LEFT   JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
            WHERE  m.bracket_type = ?
            ORDER  BY s.schedule_start ASC, m.match_id ASC
        ");
        $nrStmt->bind_param('s', $nextWinnerType);
        $nrStmt->execute();
        $nrRes = $nrStmt->get_result();
        $nrStmt->close();

        $nextRoundMatchIds = [];
        while ($nr = $nrRes->fetch_assoc()) {
            $nextRoundMatchIds[] = intval($nr['match_id']);
        }

        $targetNextMatchId = $nextRoundMatchIds[$slotIndex] ?? null;

        if (!$partnerIsScored) {
            // ── PLACEHOLDER path ──────────────────────────────────────────────
            // Partner not finished yet. Seed this winner alone into the CORRECT
            // slot ($slotIndex), NOT just "first available". This prevents e.g.
            // Winner M1 and Winner M2 from both landing in QF slot 0 before M3
            // and M4 are scored.
            if ($targetNextMatchId) {
                // Check how many teams are already in the correct slot
                $slotCountStmt = $conn->prepare("
                    SELECT COUNT(*) AS cnt,
                           MAX(team_id) AS existing_team_id
                    FROM   tbl_teamschedule
                    WHERE  match_id = ?
                ");
                $slotCountStmt->bind_param('i', $targetNextMatchId);
                $slotCountStmt->execute();
                $slotCountRow = $slotCountStmt->get_result()->fetch_assoc();
                $slotCountStmt->close();

                $slotTeamCount     = intval($slotCountRow['cnt']);
                $existingTeamInSlot = intval($slotCountRow['existing_team_id'] ?? 0);

                if ($slotTeamCount === 0) {
                    // Slot is empty — insert as first placeholder
                    $ins = $conn->prepare("
                        INSERT IGNORE INTO tbl_teamschedule
                            (match_id, round_id, team_id, referee_id, arena_number)
                        VALUES (?, 1, ?, ?, 1)
                    ");
                    $ins->bind_param('iii', $targetNextMatchId, $winner_team_id, $referee_id);
                    $ins->execute();
                    $affected = $ins->affected_rows;
                    $ins->close();
                    $winnerResult = [
                        'seeded'   => $affected > 0,
                        'match_id' => $targetNextMatchId,
                        'note'     => "Placeholder seeded alone into correct slot (index $slotIndex, match $targetNextMatchId)",
                    ];
                } elseif ($slotTeamCount === 1 && $existingTeamInSlot !== $winner_team_id) {
                    // One team already there from the other pairing partner —
                    // pair up now (this can happen if the partner scored first
                    // but $partnerIsScored flag missed it due to a timing edge)
                    $winnerResult = seedIntoMatchTogether(
                        $conn, $nextWinnerType,
                        $existingTeamInSlot,
                        $winner_team_id,
                        $referee_id, $category_id
                    );
                    $winnerResult['note'] = "Slot had 1 team already; paired in correct slot (index $slotIndex)";
                } else {
                    // Already in slot (duplicate call) or slot is full
                    $winnerResult = [
                        'seeded' => false,
                        'note'   => "Slot index $slotIndex (match $targetNextMatchId) already has $slotTeamCount team(s); skipped",
                    ];
                }
            } else {
                // Could not resolve slot — fallback to simple fill
                $winnerResult = seedIntoRound($conn, $nextWinnerType, $winner_team_id, $referee_id, $category_id);
                $winnerResult['note'] = "Could not resolve slot index $slotIndex in $nextWinnerType; fallback";
            }
            $winnerResult['note'] = ($winnerResult['note'] ?? '') . " (partner match $partnerMatchId not yet scored)";

        } else {
            // ── PAIR-UP path ──────────────────────────────────────────────────
            // Partner IS finished. Find its winner already sitting as a
            // placeholder in the correct slot and pair them together.
            if ($targetNextMatchId) {
                $partnerTeamStmt = $conn->prepare("
                    SELECT ts.team_id
                    FROM   tbl_teamschedule ts
                    WHERE  ts.match_id = ?
                    LIMIT  1
                ");
                $partnerTeamStmt->bind_param('i', $targetNextMatchId);
                $partnerTeamStmt->execute();
                $partnerTeamRow = $partnerTeamStmt->get_result()->fetch_assoc();
                $partnerTeamStmt->close();

                $partnerTeamId = $partnerTeamRow ? intval($partnerTeamRow['team_id']) : null;

                if ($partnerTeamId) {
                    // Pair them: placeholder (already there) = home, new winner = away
                    $winnerResult = seedIntoMatchTogether(
                        $conn, $nextWinnerType,
                        $partnerTeamId,   // home (already seeded)
                        $winner_team_id,  // away (arriving now)
                        $referee_id, $category_id
                    );
                    $winnerResult['note'] = "Paired with placeholder team_id=$partnerTeamId in match_id=$targetNextMatchId (slot index $slotIndex)";
                } else {
                    // Slot is empty — partner winner was not seeded yet; seed alone in correct slot
                    $ins = $conn->prepare("
                        INSERT IGNORE INTO tbl_teamschedule
                            (match_id, round_id, team_id, referee_id, arena_number)
                        VALUES (?, 1, ?, ?, 1)
                    ");
                    $ins->bind_param('iii', $targetNextMatchId, $winner_team_id, $referee_id);
                    $ins->execute();
                    $affected = $ins->affected_rows;
                    $ins->close();
                    $winnerResult = [
                        'seeded'   => $affected > 0,
                        'match_id' => $targetNextMatchId,
                        'note'     => "Target slot $targetNextMatchId was empty; seeded alone in correct slot (index $slotIndex)",
                    ];
                }
            } else {
                // Could not resolve target slot — fallback
                $winnerResult = seedIntoRound($conn, $nextWinnerType, $winner_team_id, $referee_id, $category_id);
                $winnerResult['note'] = "Could not resolve slot index $slotIndex in $nextWinnerType; fallback";
            }
        }
    }
}

// Loser handling (semi-finals only → third-place, simple slot fill)
if ($nextLoserType && $loser_team_id > 0) {
    $loserResult = seedIntoRound($conn, $nextLoserType, $loser_team_id, $referee_id, $category_id);
}

$conn->close();

$response = [
    'success'            => true,
    'current_round'      => $currentType,
    'current_match_pos'  => $currentPos,
    'partner_match_pos'  => $partnerPos,
    'partner_scored'     => $partnerIsScored,
    'winner_advanced_to' => $nextWinnerType,
    'winner_seeded'      => $winnerResult['seeded'] ?? false,
    'winner_detail'      => $winnerResult,
    'message'            => 'Advancement complete',
];

if ($nextLoserType) {
    $response['loser_advanced_to'] = $nextLoserType;
    $response['loser_seeded']      = $loserResult['seeded'] ?? false;
    $response['loser_detail']      = $loserResult;
}

echo json_encode($response);


// ═════════════════════════════════════════════════════════════════════
// HELPER — rank and seed teams by standard tournament tiebreakers
// ═════════════════════════════════════════════════════════════════════
// Accepts a flat array of team rows.  Each row MUST contain:
//   team_name (string), pts (int), gd (int), gf (int)
// Any extra keys (team_id, group_label, …) are passed through untouched.
//
// Tiebreaker order:
//   1. Higher PTS ranks higher
//   2. Higher GD  ranks higher
//   3. Higher GF  ranks higher
//   4. Stable original order is preserved for any remaining ties
//      (PHP's usort is not stable, so we tag each row with its original
//       index and use it as a final tiebreaker — O(n log n), no extra pass)
//
// Returns a new array sorted highest → lowest, each row extended with:
//   'rank' (int, 1-based position)
//   'seed' (int, identical to rank — change mapping here if needed)
//
// Works for any number of teams and is safe for cross-group pools.
// ─────────────────────────────────────────────────────────────────────
function rankAndSeedTeams(array $teams): array
{
    if (empty($teams)) {
        return [];
    }

    // Tag each row with its original position so we can do a stable sort.
    foreach ($teams as $i => &$row) {
        $row['__orig_idx'] = $i;
    }
    unset($row);

    usort($teams, function (array $a, array $b): int {
        // 1. Points — higher is better
        if ($b['pts'] !== $a['pts']) {
            return $b['pts'] - $a['pts'];
        }
        // 2. Goal difference — higher is better
        if ($b['gd'] !== $a['gd']) {
            return $b['gd'] - $a['gd'];
        }
        // 3. Goals for — higher is better
        if ($b['gf'] !== $a['gf']) {
            return $b['gf'] - $a['gf'];
        }
        // 4. Stable fallback — preserve original insertion order
        return $a['__orig_idx'] - $b['__orig_idx'];
    });

    // Assign rank and seed, then strip the internal tag.
    foreach ($teams as $idx => &$row) {
        $row['rank'] = $idx + 1;
        $row['seed'] = $idx + 1;   // seed == rank; adjust here for custom mappings
        unset($row['__orig_idx']);
    }
    unset($row);

    return $teams;
}

// ═════════════════════════════════════════════════════════════════════
// HELPER — compute standings for one group  (FIFA tiebreaker order)
// ═════════════════════════════════════════════════════════════════════
// FIFA official tiebreaker order (group stage):
//   1. Points (overall)
//   2. Goal difference (overall)
//   3. Goals for (overall)
//   4. Points in head-to-head matches among tied teams
//   5. Goal difference in head-to-head matches among tied teams
//   6. Goals for in head-to-head matches among tied teams
//   7. Team name alphabetical (final fallback — replaces drawing of lots)
//
// $teamIds        — array of team_id ints in this group
// $scoredMatchIds — array of match_id ints that are fully scored
//
// Returns rows sorted by FIFA rules.
// Each row: [ team_id, team_name, pts, gd, gf, ga, mp, w, d, l ]
function computeGroupStandings(mysqli $conn, array $teamIds, array $scoredMatchIds): array {
    if (empty($teamIds)) return [];

    $n = count($teamIds);

    // ── Fetch team names ─────────────────────────────────────────────
    $ph = implode(',', array_fill(0, $n, '?'));
    $nmStmt = $conn->prepare("SELECT team_id, team_name FROM tbl_team WHERE team_id IN ($ph)");
    $nmStmt->bind_param(str_repeat('i', $n), ...$teamIds);
    $nmStmt->execute();
    $nmRes = $nmStmt->get_result();
    $nmStmt->close();

    $teamNames = [];
    while ($r = $nmRes->fetch_assoc()) {
        $teamNames[intval($r['team_id'])] = $r['team_name'];
    }

    // ── Initialise overall stats ─────────────────────────────────────
    $stats = [];
    foreach ($teamIds as $tid) {
        $stats[$tid] = ['mp' => 0, 'w' => 0, 'd' => 0, 'l' => 0,
                        'gf' => 0, 'ga' => 0, 'pts' => 0];
    }

    // ── Fetch scores for all scored matches in this group ────────────
    $matchScores = [];
    if (!empty($scoredMatchIds)) {
        $sm  = count($scoredMatchIds);
        $sph = implode(',', array_fill(0, $sm, '?'));
        $scStmt = $conn->prepare("
            SELECT match_id, team_id, score_independentscore AS goals
            FROM   tbl_score
            WHERE  match_id IN ($sph)
            ORDER  BY match_id ASC
        ");
        $scStmt->bind_param(str_repeat('i', $sm), ...$scoredMatchIds);
        $scStmt->execute();
        $scRes = $scStmt->get_result();
        $scStmt->close();

        while ($r = $scRes->fetch_assoc()) {
            $matchScores[intval($r['match_id'])][intval($r['team_id'])] = intval($r['goals']);
        }

        foreach ($matchScores as $teams) {
            if (count($teams) !== 2) continue;
            $tids = array_keys($teams);
            $t1 = $tids[0]; $t2 = $tids[1];
            $g1 = $teams[$t1]; $g2 = $teams[$t2];
            if (!isset($stats[$t1]) || !isset($stats[$t2])) continue;

            $stats[$t1]['mp']++; $stats[$t2]['mp']++;
            $stats[$t1]['gf'] += $g1; $stats[$t1]['ga'] += $g2;
            $stats[$t2]['gf'] += $g2; $stats[$t2]['ga'] += $g1;

            if ($g1 > $g2) {
                $stats[$t1]['w']++; $stats[$t1]['pts'] += 3;
                $stats[$t2]['l']++;
            } elseif ($g2 > $g1) {
                $stats[$t2]['w']++; $stats[$t2]['pts'] += 3;
                $stats[$t1]['l']++;
            } else {
                $stats[$t1]['d']++; $stats[$t1]['pts']++;
                $stats[$t2]['d']++; $stats[$t2]['pts']++;
            }
        }
    }

    // ── Build rows with overall GD ───────────────────────────────────
    $rows = [];
    foreach ($teamIds as $tid) {
        $s = $stats[$tid];
        $rows[] = [
            'team_id'   => $tid,
            'team_name' => $teamNames[$tid] ?? "Team $tid",
            'mp'        => $s['mp'],
            'w'         => $s['w'],
            'd'         => $s['d'],
            'l'         => $s['l'],
            'gf'        => $s['gf'],
            'ga'        => $s['ga'],
            'gd'        => $s['gf'] - $s['ga'],
            'pts'       => $s['pts'],
        ];
    }

    // ── FIFA sort: overall PTS → GD → GF, then head-to-head for ties ─
    usort($rows, function ($a, $b) use ($matchScores, $teamIds) {
        // 1. Overall points
        if ($b['pts'] !== $a['pts']) return $b['pts'] - $a['pts'];
        // 2. Overall goal difference
        if ($b['gd']  !== $a['gd'])  return $b['gd']  - $a['gd'];
        // 3. Overall goals for
        if ($b['gf']  !== $a['gf'])  return $b['gf']  - $a['gf'];

        // ── Steps 4-6: head-to-head among teams still level ──────────
        // Compute H2H stats only between these two teams.
        $h2h = computeH2HStats([$a['team_id'], $b['team_id']], $matchScores);

        $aPts = $h2h[$a['team_id']]['pts'];
        $bPts = $h2h[$b['team_id']]['pts'];
        // 4. H2H points
        if ($bPts !== $aPts) return $bPts - $aPts;

        $aGD = $h2h[$a['team_id']]['gf'] - $h2h[$a['team_id']]['ga'];
        $bGD = $h2h[$b['team_id']]['gf'] - $h2h[$b['team_id']]['ga'];
        // 5. H2H goal difference
        if ($bGD !== $aGD) return $bGD - $aGD;

        // 6. H2H goals for
        if ($h2h[$b['team_id']]['gf'] !== $h2h[$a['team_id']]['gf'])
            return $h2h[$b['team_id']]['gf'] - $h2h[$a['team_id']]['gf'];

        // 7. Alphabetical (replaces drawing of lots)
        return strcmp($a['team_name'], $b['team_name']);
    });

    return $rows;
}

// ═════════════════════════════════════════════════════════════════════
// HELPER — compute head-to-head stats among a subset of team IDs
// ═════════════════════════════════════════════════════════════════════
// $subsetIds   — team IDs to consider (only matches between these teams)
// $matchScores — full map of [match_id => [team_id => goals]]
//
// Returns [ team_id => ['pts' => x, 'gf' => x, 'ga' => x] ]
function computeH2HStats(array $subsetIds, array $matchScores): array {
    $h2h = [];
    foreach ($subsetIds as $tid) {
        $h2h[$tid] = ['pts' => 0, 'gf' => 0, 'ga' => 0];
    }

    $subsetSet = array_flip($subsetIds);

    foreach ($matchScores as $teams) {
        if (count($teams) !== 2) continue;
        $tids = array_keys($teams);
        $t1 = $tids[0]; $t2 = $tids[1];

        // Only count matches where BOTH teams are in our subset
        if (!isset($subsetSet[$t1]) || !isset($subsetSet[$t2])) continue;

        $g1 = $teams[$t1]; $g2 = $teams[$t2];

        $h2h[$t1]['gf'] += $g1; $h2h[$t1]['ga'] += $g2;
        $h2h[$t2]['gf'] += $g2; $h2h[$t2]['ga'] += $g1;

        if ($g1 > $g2) {
            $h2h[$t1]['pts'] += 3;
        } elseif ($g2 > $g1) {
            $h2h[$t2]['pts'] += 3;
        } else {
            $h2h[$t1]['pts']++;
            $h2h[$t2]['pts']++;
        }
    }

    return $h2h;
}

// ═════════════════════════════════════════════════════════════════════
// HELPER — seed TWO specific teams into the SAME knockout match slot
// ═════════════════════════════════════════════════════════════════════
// Used for the FIFA group-stage draw where we know exactly who faces who.
//
// RE-SCORE AWARE (upsert logic):
//   1. If an unscored slot already has EXACTLY these two teams → no-op.
//   2. If either team is in a stale unscored slot (standings changed after
//      a re-score) → remove that stale seed and re-insert into a fresh slot.
//   3. If neither team is seeded yet → find the first empty slot and insert.
//
// Scored knockout slots are NEVER touched, so already-played matches are safe.
function seedIntoMatchTogether(
    mysqli $conn,
    string $targetType,
    int    $homeTeamId,
    int    $awayTeamId,
    int    $refereeId,
    int    $categoryId
): array {

    // ── Step 1: Are both teams already paired correctly in an unscored slot? ─
    $pairStmt = $conn->prepare("
        SELECT ts1.match_id
        FROM   tbl_teamschedule ts1
        INNER  JOIN tbl_teamschedule ts2 ON ts2.match_id = ts1.match_id
                                        AND ts2.team_id  = ?
        INNER  JOIN tbl_match m          ON m.match_id   = ts1.match_id
        WHERE  ts1.team_id    = ?
          AND  m.bracket_type = ?
          AND  NOT EXISTS (
              SELECT 1 FROM tbl_score sc WHERE sc.match_id = ts1.match_id
          )
        LIMIT 1
    ");
    // FIX: SQL has ts2.team_id=? first, ts1.team_id=? second — params were
    // swapped causing the idempotent check to MISS already-paired teams and
    // insert the same pair into a second slot (Match 1 AND Match 5 both got
    // the same two teams).
    $pairStmt->bind_param('iis', $awayTeamId, $homeTeamId, $targetType);
    $pairStmt->execute();
    $pairRow = $pairStmt->get_result()->fetch_assoc();
    $pairStmt->close();

    if ($pairRow) {
        // Both teams are already correctly paired — nothing to do.
        return [
            'seeded'   => false,
            'reason'   => "Both teams already correctly seeded into '$targetType' (idempotent skip).",
            'match_id' => intval($pairRow['match_id']),
        ];
    }

    // ── Step 2: Clear any stale unscored seeds for either team in this round ─
    // This corrects the draw when standings change after a re-score.
    //
    // SAFETY RULES — a seed is only deleted when it is truly stale:
    //
    //   Rule A: If the team is in an unscored EARLIER round (elim/r32/r16),
    //           its seat in the NEXT round is a valid BYE placeholder — keep it.
    //
    //   Rule B: If the team already shares its current slot with EXACTLY ONE
    //           other team (i.e. the slot is fully paired), it is not stale —
    //           it is a correctly-paired match that must not be broken up.
    //           This prevents re-running the group draw from scattering
    //           already-correct ELIM pairs into new empty slots.
    $earlierRounds = ['elimination', 'round-of-32', 'round-of-16'];

    foreach ([$homeTeamId, $awayTeamId] as $tid) {

        // ── Rule A: skip if team is waiting in an unscored earlier round ──
        $isInEarlierRound = false;
        foreach ($earlierRounds as $er) {
            if ($er === $targetType) continue;
            $erStmt = $conn->prepare("
                SELECT ts.match_id
                FROM   tbl_teamschedule ts
                INNER  JOIN tbl_match m ON m.match_id = ts.match_id
                WHERE  ts.team_id     = ?
                  AND  m.bracket_type = ?
                  AND  NOT EXISTS (
                      SELECT 1 FROM tbl_score sc WHERE sc.match_id = ts.match_id
                  )
                LIMIT 1
            ");
            $erStmt->bind_param('is', $tid, $er);
            $erStmt->execute();
            $erRow = $erStmt->get_result()->fetch_assoc();
            $erStmt->close();
            if ($erRow) { $isInEarlierRound = true; break; }
        }
        if ($isInEarlierRound) continue;

        // ── Find the team's existing unscored seed in this round ─────────
        $staleStmt = $conn->prepare("
            SELECT ts.match_id,
                   (SELECT COUNT(*) FROM tbl_teamschedule ts2
                    WHERE ts2.match_id = ts.match_id) AS slot_count
            FROM   tbl_teamschedule ts
            INNER  JOIN tbl_match m ON m.match_id = ts.match_id
            WHERE  ts.team_id     = ?
              AND  m.bracket_type = ?
              AND  NOT EXISTS (
                  SELECT 1 FROM tbl_score sc WHERE sc.match_id = ts.match_id
              )
            LIMIT 1
        ");
        $staleStmt->bind_param('is', $tid, $targetType);
        $staleStmt->execute();
        $staleRow = $staleStmt->get_result()->fetch_assoc();
        $staleStmt->close();

        if (!$staleRow) continue;

        // ── Rule B: skip if slot already has 2 teams (fully paired) ──────
        // A fully-paired unscored slot means the draw already placed this
        // team correctly with its partner.  Deleting it would break the
        // pair and cause a duplicate entry in a new empty slot.
        if (intval($staleRow['slot_count']) >= 2) continue;

        // Slot has only 1 team (solo placeholder) → safe to delete and re-pair
        $delStmt = $conn->prepare(
            "DELETE FROM tbl_teamschedule WHERE match_id = ? AND team_id = ?"
        );
        $delStmt->bind_param('ii', $staleRow['match_id'], $tid);
        $delStmt->execute();
        $delStmt->close();
    }

    // ── Step 3: Find the first completely empty slot and insert both teams ─
    $stmt = $conn->prepare("
        SELECT m.match_id,
               (
                   SELECT COUNT(*)
                   FROM   tbl_teamschedule ts2
                   WHERE  ts2.match_id = m.match_id
               ) AS team_count
        FROM   tbl_match m
        LEFT   JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE  m.bracket_type = ?
        HAVING team_count = 0
        ORDER  BY s.schedule_start ASC, m.match_id ASC
        LIMIT  1
    ");
    $stmt->bind_param('s', $targetType);
    $stmt->execute();
    $slotRow = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$slotRow) {
        return [
            'seeded' => false,
            'reason' => "No empty match slot found for bracket_type='$targetType'",
        ];
    }

    $targetMatchId = intval($slotRow['match_id']);

    // Insert HOME team
    $ins = $conn->prepare("
        INSERT IGNORE INTO tbl_teamschedule
            (match_id, round_id, team_id, referee_id, arena_number)
        VALUES (?, 1, ?, ?, 1)
    ");
    $ins->bind_param('iii', $targetMatchId, $homeTeamId, $refereeId);
    $ins->execute();
    $homeAffected = $ins->affected_rows;
    $ins->close();

    // Insert AWAY team
    $ins2 = $conn->prepare("
        INSERT IGNORE INTO tbl_teamschedule
            (match_id, round_id, team_id, referee_id, arena_number)
        VALUES (?, 1, ?, ?, 1)
    ");
    $ins2->bind_param('iii', $targetMatchId, $awayTeamId, $refereeId);
    $ins2->execute();
    $awayAffected = $ins2->affected_rows;
    $ins2->close();

    return [
        'seeded'       => ($homeAffected > 0 || $awayAffected > 0),
        'match_id'     => $targetMatchId,
        'home_team_id' => $homeTeamId,
        'away_team_id' => $awayTeamId,
        'home_rows'    => $homeAffected,
        'away_rows'    => $awayAffected,
    ];
}

// ═════════════════════════════════════════════════════════════════════
// HELPER — seed ONE team into the next COMPLETELY EMPTY slot
// ═════════════════════════════════════════════════════════════════════
// Unlike seedIntoRound (team_count < 2), this requires team_count = 0.
// Used for BYE seeds in the 10-team format where QF slots are being
// filled in stages — a half-filled slot (team_count = 1) already
// belongs to another pairing and must not be shared.
function seedIntoEmptySlot(mysqli $conn, string $targetType, int $teamId, int $refereeId): array {

    // Check if team is already seated in any unscored slot of this type
    $chkStmt = $conn->prepare("
        SELECT ts.match_id
        FROM   tbl_teamschedule ts
        INNER  JOIN tbl_match m ON m.match_id = ts.match_id
        WHERE  ts.team_id     = ?
          AND  m.bracket_type = ?
          AND  NOT EXISTS (
              SELECT 1 FROM tbl_score sc WHERE sc.match_id = ts.match_id
          )
        LIMIT 1
    ");
    $chkStmt->bind_param('is', $teamId, $targetType);
    $chkStmt->execute();
    $chkRow = $chkStmt->get_result()->fetch_assoc();
    $chkStmt->close();

    if ($chkRow) {
        return [
            'seeded'   => false,
            'reason'   => "Team $teamId already seated in '$targetType' match {$chkRow['match_id']} (idempotent skip).",
            'match_id' => intval($chkRow['match_id']),
        ];
    }

    // Find the first slot with zero teams assigned (completely empty)
    $stmt = $conn->prepare("
        SELECT m.match_id,
               s.schedule_start,
               (
                   SELECT COUNT(*)
                   FROM   tbl_teamschedule ts2
                   WHERE  ts2.match_id = m.match_id
               ) AS team_count
        FROM   tbl_match m
        LEFT   JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE  m.bracket_type = ?
        HAVING team_count = 0
        ORDER  BY s.schedule_start ASC, m.match_id ASC
        LIMIT  1
    ");
    $stmt->bind_param('s', $targetType);
    $stmt->execute();
    $slotRow = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$slotRow) {
        return [
            'seeded' => false,
            'reason' => "No completely empty slot found for bracket_type='$targetType'",
        ];
    }

    $targetMatchId = intval($slotRow['match_id']);

    $ins = $conn->prepare("
        INSERT IGNORE INTO tbl_teamschedule
            (match_id, round_id, team_id, referee_id, arena_number)
        VALUES (?, 1, ?, ?, 1)
    ");
    $ins->bind_param('iii', $targetMatchId, $teamId, $refereeId);
    $ins->execute();
    $affected = $ins->affected_rows;
    $ins->close();

    if ($affected > 0) {
        return ['seeded' => true, 'match_id' => $targetMatchId];
    }

    return [
        'seeded' => false,
        'reason' => "INSERT IGNORE had 0 affected rows for match_id=$targetMatchId (duplicate?)",
    ];
}

// ═════════════════════════════════════════════════════════════════════
// HELPER — seed ONE team into the next available slot (knockout rounds)
// ═════════════════════════════════════════════════════════════════════
function seedIntoRound(mysqli $conn, string $targetType, int $teamId, int $refereeId, int $categoryId): array {

    $stmt = $conn->prepare("
        SELECT m.match_id,
               s.schedule_start,
               (
                   SELECT COUNT(*)
                   FROM   tbl_teamschedule ts2
                   WHERE  ts2.match_id = m.match_id
               ) AS team_count,
               (
                   SELECT COUNT(*)
                   FROM   tbl_teamschedule ts3
                   WHERE  ts3.match_id = m.match_id
                     AND  ts3.team_id  = ?
               ) AS already_in
        FROM   tbl_match m
        LEFT   JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE  m.bracket_type = ?
        ORDER  BY s.schedule_start ASC, m.match_id ASC
    ");
    $stmt->bind_param('is', $teamId, $targetType);
    $stmt->execute();
    $result = $stmt->get_result();
    $stmt->close();

    $targetMatchId = null;
    while ($r = $result->fetch_assoc()) {
        if (intval($r['already_in']) > 0) continue;
        if (intval($r['team_count']) >= 2) continue;
        $targetMatchId = intval($r['match_id']);
        break;
    }

    if (!$targetMatchId) {
        $debugStmt = $conn->prepare("
            SELECT m.match_id,
                   (SELECT COUNT(*) FROM tbl_teamschedule ts WHERE ts.match_id = m.match_id) AS cnt
            FROM   tbl_match m
            WHERE  m.bracket_type = ?
            ORDER  BY m.match_id ASC
        ");
        $debugStmt->bind_param('s', $targetType);
        $debugStmt->execute();
        $debugRes = $debugStmt->get_result();
        $debugStmt->close();

        $debugInfo = [];
        while ($d = $debugRes->fetch_assoc()) {
            $debugInfo[] = ['match_id' => $d['match_id'], 'team_count' => $d['cnt']];
        }

        return [
            'seeded'  => false,
            'reason'  => "No available slot found for bracket_type='$targetType'",
            'matches' => $debugInfo,
        ];
    }

    $ins = $conn->prepare("
        INSERT IGNORE INTO tbl_teamschedule
            (match_id, round_id, team_id, referee_id, arena_number)
        VALUES (?, 1, ?, ?, 1)
    ");
    $ins->bind_param('iii', $targetMatchId, $teamId, $refereeId);
    $ins->execute();
    $affected = $ins->affected_rows;
    $ins->close();

    if ($affected > 0) {
        return ['seeded' => true, 'match_id' => $targetMatchId];
    }

    return [
        'seeded' => false,
        'reason' => "INSERT IGNORE had 0 affected rows for match_id=$targetMatchId (duplicate?)",
    ];
}
?>