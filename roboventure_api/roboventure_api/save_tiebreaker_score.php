<?php
// ─────────────────────────────────────────────────────────────────────
// save_tiebreaker_score.php
// POST  body: {
//   "tiebreaker_id": 1,
//   "team1_score":   3,
//   "team2_score":   2,
//   "winner_id":     12
// }
//
// Saves the Penalty Shootout result to tbl_soccer_tiebreaker.
// Updates team1_score, team2_score, and winner_id.
//
// The scoring app (soccer_scoring.dart) calls this after the referee
// submits the shootout score, the same way it calls submit_score for
// regular group matches.
//
// Response (success):
//   { "success": true, "winner_id": 12 }
//
// Response (error):
//   { "error": "..." }
// ─────────────────────────────────────────────────────────────────────
ini_set('display_errors', 0);
error_reporting(0);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store, no-cache, must-revalidate');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'POST required']);
    exit();
}

require_once 'db_config.php';

// ── Parse request body ────────────────────────────────────────────────
$body = json_decode(file_get_contents('php://input'), true);

$tiebreaker_id = isset($body['tiebreaker_id']) ? intval($body['tiebreaker_id']) : 0;
$team1_score   = isset($body['team1_score'])   ? intval($body['team1_score'])   : null;
$team2_score   = isset($body['team2_score'])   ? intval($body['team2_score'])   : null;
$winner_id     = isset($body['winner_id'])     ? intval($body['winner_id'])     : null;

// ── Validate ──────────────────────────────────────────────────────────
if ($tiebreaker_id <= 0) {
    http_response_code(400);
    echo json_encode(['error' => 'tiebreaker_id is required']);
    exit();
}
if ($team1_score === null || $team2_score === null) {
    http_response_code(400);
    echo json_encode(['error' => 'team1_score and team2_score are required']);
    exit();
}
if ($winner_id === null || $winner_id <= 0) {
    http_response_code(400);
    echo json_encode(['error' => 'winner_id is required']);
    exit();
}
if ($team1_score === $team2_score) {
    http_response_code(400);
    echo json_encode(['error' => 'Penalty Shootout cannot end in a draw — a winner must be determined']);
    exit();
}

// ── Verify the tiebreaker row exists and is not already scored ────────
$check = $conn->prepare("
    SELECT tiebreaker_id, team1_id, team2_id, winner_id
    FROM tbl_soccer_tiebreaker
    WHERE tiebreaker_id = ?
");
$check->bind_param('i', $tiebreaker_id);
$check->execute();
$row = $check->get_result()->fetch_assoc();
$check->close();

if (!$row) {
    http_response_code(404);
    echo json_encode(['error' => 'Tiebreaker match not found']);
    exit();
}
if ($row['winner_id'] !== null) {
    // Already scored — return the existing result instead of erroring
    echo json_encode([
        'success'   => true,
        'winner_id' => intval($row['winner_id']),
        'message'   => 'Already scored',
    ]);
    exit();
}

// ── Verify winner_id is one of the two teams ──────────────────────────
if ($winner_id !== intval($row['team1_id']) && $winner_id !== intval($row['team2_id'])) {
    http_response_code(400);
    echo json_encode(['error' => 'winner_id must be team1_id or team2_id']);
    exit();
}

// ── Save the result ───────────────────────────────────────────────────
$update = $conn->prepare("
    UPDATE tbl_soccer_tiebreaker
    SET team1_score = ?,
        team2_score = ?,
        winner_id   = ?
    WHERE tiebreaker_id = ?
");
$update->bind_param('iiii', $team1_score, $team2_score, $winner_id, $tiebreaker_id);
$update->execute();

if ($update->affected_rows < 1) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to save score — no rows updated']);
    $update->close();
    $conn->close();
    exit();
}
$update->close();

// ── Check if all shootouts for this category are now resolved ─────────
// If so, fire advance_knockout.php to attempt the draw. We pass the
// highest scored group match_id as the trigger — same pattern as
// championship_schedule.dart's reRunGroupDraw.
$allDoneStmt = $conn->prepare("
    SELECT COUNT(*) AS pending
    FROM   tbl_soccer_tiebreaker
    WHERE  category_id = ?
      AND  winner_id   IS NULL
");
// We need category_id — fetch it from the tiebreaker row we just scored
$catStmt = $conn->prepare("
    SELECT category_id FROM tbl_soccer_tiebreaker WHERE tiebreaker_id = ?
");
$catStmt->bind_param('i', $tiebreaker_id);
$catStmt->execute();
$catRow  = $catStmt->get_result()->fetch_assoc();
$catStmt->close();
$tiebreakerCategoryId = intval($catRow['category_id'] ?? 0);

$pendingStmt = $conn->prepare("
    SELECT COUNT(*) AS pending
    FROM   tbl_soccer_tiebreaker
    WHERE  category_id = ?
      AND  winner_id   IS NULL
");
$pendingStmt->bind_param('i', $tiebreakerCategoryId);
$pendingStmt->execute();
$pendingRow = $pendingStmt->get_result()->fetch_assoc();
$pendingStmt->close();

$allShootoutsDone = (intval($pendingRow['pending'] ?? 1) === 0);

// ── If all shootouts resolved, trigger advance_knockout with last scored group match ─
$drawTriggered = false;
if ($allShootoutsDone && $tiebreakerCategoryId > 0) {
    // Find highest scored group match_id for this category
    $trigStmt = $conn->prepare("
        SELECT MAX(sc.match_id) AS last_match_id
        FROM   tbl_score sc
        INNER  JOIN tbl_match m ON m.match_id = sc.match_id
        INNER  JOIN tbl_teamschedule ts ON ts.match_id = sc.match_id
        INNER  JOIN tbl_team t ON t.team_id = ts.team_id
        WHERE  m.bracket_type = 'group'
          AND  t.category_id  = ?
    ");
    $trigStmt->bind_param('i', $tiebreakerCategoryId);
    $trigStmt->execute();
    $trigRow = $trigStmt->get_result()->fetch_assoc();
    $trigStmt->close();

    $triggerMatchId = intval($trigRow['last_match_id'] ?? 0);
    if ($triggerMatchId > 0) {
        $advancePayload = json_encode([
            'match_id'       => $triggerMatchId,
            'winner_team_id' => 0,
            'loser_team_id'  => 0,
            'category_id'    => $tiebreakerCategoryId,
        ]);
        // Internal HTTP call to advance_knockout.php on same server
        $advUrl = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http')
                . '://' . $_SERVER['HTTP_HOST']
                . dirname($_SERVER['SCRIPT_NAME']) . '/advance_knockout.php';
        $ch = curl_init($advUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $advancePayload);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_exec($ch);
        $drawTriggered = true;
    }
}

$conn->close();

echo json_encode([
    'success'       => true,
    'winner_id'     => $winner_id,
    'all_shootouts_done' => $allShootoutsDone,
    'draw_triggered'     => $drawTriggered,
]);
?>