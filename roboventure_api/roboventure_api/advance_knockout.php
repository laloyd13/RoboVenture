<?php
// ─────────────────────────────────────────────────────────────────────
// advance_knockout.php  (FIXED)
//
// POST (JSON body)
// Called by championship_sched.dart immediately after a knockout score
// is saved. Seeds the winner into the next round and (if semi-finals)
// the loser into the 3rd-place match.
//
// FIX 1: seedIntoRound() now also checks matches whose tbl_teamschedule
//         slot count is < 2, INCLUDING matches with 0 rows (pure empty
//         slots pre-created by the admin).
// FIX 2: Improved error messages so the Flutter app can debug failures.
// FIX 3: Returns detailed seeding status per team.
//
// Body:
// {
//   "match_id":       47,
//   "winner_team_id": 12,
//   "loser_team_id":  9,
//   "category_id":    4
// }
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

if ($match_id <= 0 || $winner_team_id <= 0 || $category_id <= 0) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid match_id, winner_team_id, or category_id']);
    exit();
}

// ── 1. Get current bracket_type of this match ─────────────────────────
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

// ── 2. No advancement needed for final or third-place ─────────────────
if ($currentType === 'final' || $currentType === 'third-place') {
    echo json_encode([
        'success' => true,
        'message' => 'No advancement needed for ' . $currentType,
    ]);
    exit();
}

// ── 3. Determine next round(s) ────────────────────────────────────────
$nextWinnerType = null;
$nextLoserType  = null;

if ($currentType === 'semi-finals') {
    $nextWinnerType = 'final';
    $nextLoserType  = 'third-place';
} else {
    // Query actual KO rounds present in DB, ordered chronologically.
    $roundsStmt = $conn->prepare("
        SELECT DISTINCT m.bracket_type,
               MIN(s.schedule_start) AS first_time
        FROM tbl_match m
        JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE m.bracket_type IN (
            'round-of-32', 'elimination', 'round-of-16',
            'quarter-finals', 'semi-finals', 'final'
        )
        GROUP BY m.bracket_type
        ORDER BY first_time ASC
    ");
    $roundsStmt->execute();
    $roundsResult = $roundsStmt->get_result();
    $roundsStmt->close();

    $presentRounds = [];
    while ($r = $roundsResult->fetch_assoc()) {
        $presentRounds[] = $r['bracket_type'];
    }

    $curIdx = array_search($currentType, $presentRounds);
    if ($curIdx !== false && $curIdx + 1 < count($presentRounds)) {
        $nextWinnerType = $presentRounds[$curIdx + 1];
    } else {
        $nextWinnerType = 'final'; // fallback
    }
}

// ── 4. Get default referee ────────────────────────────────────────────
$refStmt = $conn->prepare(
    "SELECT referee_id FROM tbl_referee ORDER BY referee_id ASC LIMIT 1"
);
$refStmt->execute();
$refRow     = $refStmt->get_result()->fetch_assoc();
$refStmt->close();
$referee_id = $refRow ? intval($refRow['referee_id']) : 1;

// ── 5. Seed team into first available slot of target round ────────────
//
// FIX: The original query only found matches that already had at least
// one tbl_teamschedule row (via LEFT JOIN + HAVING team_count < 2).
// If the admin pre-created empty match shells with NO teamschedule rows
// yet, the HAVING clause would exclude them (COUNT = 0 is still < 2 but
// the match never appeared because the LEFT JOIN produced nothing to GROUP).
//
// New approach: find the earliest match of the target bracket_type that
// does NOT already contain this team AND has fewer than 2 assigned teams.
// Uses a subquery to count existing assignments so empty matches (0 rows)
// are correctly included.
// ─────────────────────────────────────────────────────────────────────
function seedIntoRound(mysqli $conn, string $targetType, int $teamId, int $refereeId, int $categoryId): array {

    // Step A: Find ALL matches of this bracket type for this category,
    //         ordered by schedule time so we always fill the earliest slot.
    $stmt = $conn->prepare("
        SELECT m.match_id,
               s.schedule_start,
               (
                   SELECT COUNT(*)
                   FROM tbl_teamschedule ts2
                   WHERE ts2.match_id = m.match_id
               ) AS team_count,
               (
                   SELECT COUNT(*)
                   FROM tbl_teamschedule ts3
                   WHERE ts3.match_id = m.match_id
                     AND ts3.team_id  = ?
               ) AS already_in
        FROM tbl_match m
        JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE m.bracket_type = ?
        ORDER BY s.schedule_start ASC, m.match_id ASC
    ");
    $stmt->bind_param('is', $teamId, $targetType);
    $stmt->execute();
    $result = $stmt->get_result();
    $stmt->close();

    $targetMatchId = null;
    while ($r = $result->fetch_assoc()) {
        $teamCount  = intval($r['team_count']);
        $alreadyIn  = intval($r['already_in']);

        // Skip if team is already assigned to this match
        if ($alreadyIn > 0) continue;

        // Skip if match already has 2 teams
        if ($teamCount >= 2) continue;

        $targetMatchId = intval($r['match_id']);
        break; // take the first available slot
    }

    if (!$targetMatchId) {
        // Debug: return which matches exist so caller can log it
        $debugStmt = $conn->prepare("
            SELECT m.match_id,
                   (SELECT COUNT(*) FROM tbl_teamschedule ts WHERE ts.match_id = m.match_id) AS cnt
            FROM tbl_match m
            WHERE m.bracket_type = ?
            ORDER BY m.match_id ASC
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
            'seeded'   => false,
            'reason'   => "No available slot found for bracket_type='$targetType'",
            'matches'  => $debugInfo,
        ];
    }

    // Step B: Insert team into that match slot
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

// ── 6. Perform advancements ───────────────────────────────────────────
$winnerResult = ['seeded' => false];
$loserResult  = ['seeded' => false];

if ($nextWinnerType) {
    $winnerResult = seedIntoRound($conn, $nextWinnerType, $winner_team_id, $referee_id, $category_id);
}
if ($nextLoserType && $loser_team_id > 0) {
    $loserResult = seedIntoRound($conn, $nextLoserType, $loser_team_id, $referee_id, $category_id);
}

$conn->close();

// ── 7. Respond ────────────────────────────────────────────────────────
$response = [
    'success'            => true,
    'current_round'      => $currentType,
    'winner_advanced_to' => $nextWinnerType,
    'winner_seeded'      => $winnerResult['seeded'],
    'winner_detail'      => $winnerResult,
    'message'            => 'Advancement complete',
];

if ($nextLoserType) {
    $response['loser_advanced_to'] = $nextLoserType;
    $response['loser_seeded']      = $loserResult['seeded'];
    $response['loser_detail']      = $loserResult;
}

echo json_encode($response);
?>