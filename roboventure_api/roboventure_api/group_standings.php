<?php
// ─────────────────────────────────────────────────────────────────────
// get_group_standings.php
// GET ?category_id=4
//
// Returns per-group standings for soccer qualification (group stage).
// Calculates MP, W, D, L, GF, GA, GD, Pts live from tbl_score.
// Groups come from tbl_soccer_groups; goals from score_independentscore.
//
// Tiebreaker order (FIFA standard):
//   1. Points (overall)
//   2. Goal Difference (overall)
//   3. Goals For (overall)
//   4. Head-to-Head Points (among tied teams only)
//   5. Head-to-Head Goal Difference (among tied teams only)
//   6. Head-to-Head Goals For (among tied teams only)
//   7. Alphabetical by team_name (replaces FIFA drawing of lots)
//
// Response: array of rows ordered by group_label ASC, then FIFA tiebreaker
// [
//   {
//     "group_label": "A",
//     "team_id":     12,
//     "team_name":   "Team Alpha",
//     "mp": 2, "w": 1, "d": 1, "l": 0,
//     "gf": 3, "ga": 1, "gd": 2, "pts": 4
//   }, ...
// ]
// ─────────────────────────────────────────────────────────────────────
ini_set('display_errors', 0);
error_reporting(0);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-store, no-cache, must-revalidate');

require_once 'db_config.php';

$category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;

if ($category_id <= 0) {
    http_response_code(400);
    echo json_encode(['error' => 'category_id is required']);
    exit();
}

// ── 1. Get all teams in each group for this category ──────────────────
$stmt = $conn->prepare("
    SELECT sg.group_label, sg.team_id, t.team_name
    FROM tbl_soccer_groups sg
    INNER JOIN tbl_team t ON t.team_id = sg.team_id
    WHERE sg.category_id = ?
    ORDER BY sg.group_label ASC, sg.team_id ASC
");
$stmt->bind_param('i', $category_id);
$stmt->execute();
$groupRes = $stmt->get_result();
$stmt->close();

// Build a map: team_id → { group_label, team_name }
$teamInfo = [];
$groups   = []; // group_label → [ team_id, ... ]
while ($r = $groupRes->fetch_assoc()) {
    $tid   = intval($r['team_id']);
    $label = $r['group_label'];
    $teamInfo[$tid] = [
        'group_label' => $label,
        'team_name'   => $r['team_name'],
    ];
    $groups[$label][] = $tid;
}

if (empty($teamInfo)) {
    echo json_encode([]);
    exit();
}

// ── 2. Get all scored group-stage matches for this category ───────────
// Each tbl_score row = one team's result in one match.
// score_independentscore = goals scored by that team.
$stmt = $conn->prepare("
    SELECT sc.match_id, sc.team_id, sc.score_independentscore AS goals
    FROM tbl_score sc
    INNER JOIN tbl_match  m ON m.match_id = sc.match_id
    INNER JOIN tbl_team   t ON t.team_id  = sc.team_id
    WHERE t.category_id  = ?
      AND m.bracket_type = 'group'
    ORDER BY sc.match_id ASC
");
$stmt->bind_param('i', $category_id);
$stmt->execute();
$scoreRes = $stmt->get_result();
$stmt->close();

// Group score rows by match_id → [ team_id => goals ]
$matchScores = [];
while ($r = $scoreRes->fetch_assoc()) {
    $mid   = intval($r['match_id']);
    $tid   = intval($r['team_id']);
    $goals = intval($r['goals']);
    $matchScores[$mid][$tid] = $goals;
}

// ── 3. Initialise standings table ─────────────────────────────────────
$stats = [];
foreach ($teamInfo as $tid => $_) {
    $stats[$tid] = ['mp' => 0, 'w' => 0, 'd' => 0, 'l' => 0,
                    'gf' => 0, 'ga' => 0, 'pts' => 0];
}

// ── 4. Process each match ─────────────────────────────────────────────
foreach ($matchScores as $mid => $teams) {
    // A match must have exactly 2 team score rows to be fully scored
    if (count($teams) !== 2) continue;

    $tids = array_keys($teams);
    $t1   = $tids[0];
    $t2   = $tids[1];
    $g1   = $teams[$t1];
    $g2   = $teams[$t2];

    // Only process if both teams are in our group map
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

// ── 5. H2H helper — compute head-to-head stats among a subset of teams ─
// Only counts matches where BOTH teams are in the subset.
// Returns [ team_id => ['pts' => x, 'gf' => x, 'ga' => x] ]
function computeH2H(array $subsetIds, array $matchScores): array {
    $h2h       = [];
    $subsetSet = array_flip($subsetIds);
    foreach ($subsetIds as $tid) {
        $h2h[$tid] = ['pts' => 0, 'gf' => 0, 'ga' => 0];
    }
    foreach ($matchScores as $teams) {
        if (count($teams) !== 2) continue;
        $tids = array_keys($teams);
        $t1   = $tids[0];
        $t2   = $tids[1];
        if (!isset($subsetSet[$t1]) || !isset($subsetSet[$t2])) continue;
        $g1 = $teams[$t1];
        $g2 = $teams[$t2];
        $h2h[$t1]['gf'] += $g1; $h2h[$t1]['ga'] += $g2;
        $h2h[$t2]['gf'] += $g2; $h2h[$t2]['ga'] += $g1;
        if ($g1 > $g2)      { $h2h[$t1]['pts'] += 3; }
        elseif ($g2 > $g1)  { $h2h[$t2]['pts'] += 3; }
        else                { $h2h[$t1]['pts']++; $h2h[$t2]['pts']++; }
    }
    return $h2h;
}

// ── 6. Load all resolved Penalty Shootout results for this category ───
// shootoutWins[team_id] = number of shootout wins across all resolved
// tbl_soccer_tiebreaker rows for this category.
// Used as step 7 in the sort — more shootout wins = higher rank when
// all other tiebreakers are exhausted.
$shootoutWins = [];
$tbStmt = $conn->prepare("
    SELECT winner_id
    FROM   tbl_soccer_tiebreaker
    WHERE  category_id = ?
      AND  winner_id  IS NOT NULL
");
$tbStmt->bind_param('i', $category_id);
$tbStmt->execute();
$tbRes = $tbStmt->get_result();
$tbStmt->close();
while ($r = $tbRes->fetch_assoc()) {
    $wid = intval($r['winner_id']);
    $shootoutWins[$wid] = ($shootoutWins[$wid] ?? 0) + 1;
}

// ── 7. Build output grouped and sorted ────────────────────────────────
$output = [];
foreach ($groups as $label => $teamIds) {
    $rows = [];
    foreach ($teamIds as $tid) {
        $s  = $stats[$tid];
        $gd = $s['gf'] - $s['ga'];
        $rows[] = [
            'group_label'    => $label,
            'team_id'        => $tid,
            'team_name'      => $teamInfo[$tid]['team_name'],
            'mp'             => $s['mp'],
            'w'              => $s['w'],
            'd'              => $s['d'],
            'l'              => $s['l'],
            'gf'             => $s['gf'],
            'ga'             => $s['ga'],
            'gd'             => $gd,
            'pts'            => $s['pts'],
            'shootout_wins'  => $shootoutWins[$tid] ?? 0,
        ];
    }

    // ── FIFA tiebreaker sort ──────────────────────────────────────────
    // Steps 1–3: overall PTS → GD → GF
    // Steps 4–6: H2H PTS → H2H GD → H2H GF (among tied teams only)
    // Step  7:   Penalty Shootout wins (Round Robin wins count)
    // Step  8:   Alphabetical (deterministic fallback)
    usort($rows, function($a, $b) use ($matchScores) {
        // 1. Overall points
        if ($b['pts'] !== $a['pts']) return $b['pts'] - $a['pts'];
        // 2. Overall goal difference
        if ($b['gd']  !== $a['gd'])  return $b['gd']  - $a['gd'];
        // 3. Overall goals for
        if ($b['gf']  !== $a['gf'])  return $b['gf']  - $a['gf'];

        // 4–6. Head-to-head between these two teams
        $h2h  = computeH2H([$a['team_id'], $b['team_id']], $matchScores);
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

        // 7. Penalty Shootout wins (Round Robin)
        $aWins = $a['shootout_wins'];
        $bWins = $b['shootout_wins'];
        if ($bWins !== $aWins) return $bWins - $aWins;

        // 8. Alphabetical (replaces drawing of lots)
        return strcmp($a['team_name'], $b['team_name']);
    });

    foreach ($rows as $row) {
        $output[] = $row;
    }
}

$conn->close();
echo json_encode($output);
?>