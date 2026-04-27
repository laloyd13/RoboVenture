<?php
// ─────────────────────────────────────────────────────────────────────
// get_tiebreaker.php
// GET ?category_id=4
// GET ?category_id=4&group_label=A   (optional — filter by group)
//
// Returns all scheduled Penalty Shootout matches from tbl_soccer_tiebreaker
// for a given category, formatted to match the structure that
// qualification_schedule.dart already expects so it can display them
// as a Penalty Shootout match card alongside regular group matches.
//
// Response:
// [
//   {
//     "tiebreaker_id":      1,
//     "category_id":        4,
//     "group_label":        "A",
//     "match_id":           0,           // tiebreaker_id used as match reference
//     "team1_id":           12,
//     "team1_name":         "Team Alpha",
//     "team2_id":           15,
//     "team2_name":         "Team Beta",
//     "team1_score":        null,        // null = not yet scored
//     "team2_score":        null,
//     "winner_id":          null,        // null = not yet scored
//     "scheduled_time":     "14:30",
//     "arena_number":       2,
//     "is_penalty_shootout": 1,
//     "is_scored":          false
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
$group_label = isset($_GET['group_label']) ? trim($_GET['group_label'])    : '';

if ($category_id <= 0) {
    http_response_code(400);
    echo json_encode(['error' => 'category_id is required']);
    exit();
}

// ── Build query — join tbl_team to get team names ─────────────────────
if ($group_label !== '') {
    $stmt = $conn->prepare("
        SELECT
            tb.tiebreaker_id,
            tb.category_id,
            tb.group_label,
            tb.team1_id,
            t1.team_name   AS team1_name,
            tb.team2_id,
            t2.team_name   AS team2_name,
            tb.team1_score,
            tb.team2_score,
            tb.winner_id,
            TIME_FORMAT(tb.scheduled_time, '%H:%i') AS scheduled_time,
            tb.arena_number,
            tb.is_penalty_shootout,
            tb.created_at
        FROM tbl_soccer_tiebreaker tb
        INNER JOIN tbl_team t1 ON t1.team_id = tb.team1_id
        INNER JOIN tbl_team t2 ON t2.team_id = tb.team2_id
        WHERE tb.category_id = ?
          AND tb.group_label = ?
        ORDER BY tb.created_at ASC
    ");
    $stmt->bind_param('is', $category_id, $group_label);
} else {
    $stmt = $conn->prepare("
        SELECT
            tb.tiebreaker_id,
            tb.category_id,
            tb.group_label,
            tb.team1_id,
            t1.team_name   AS team1_name,
            tb.team2_id,
            t2.team_name   AS team2_name,
            tb.team1_score,
            tb.team2_score,
            tb.winner_id,
            TIME_FORMAT(tb.scheduled_time, '%H:%i') AS scheduled_time,
            tb.arena_number,
            tb.is_penalty_shootout,
            tb.created_at
        FROM tbl_soccer_tiebreaker tb
        INNER JOIN tbl_team t1 ON t1.team_id = tb.team1_id
        INNER JOIN tbl_team t2 ON t2.team_id = tb.team2_id
        WHERE tb.category_id = ?
        ORDER BY tb.group_label ASC, tb.created_at ASC
    ");
    $stmt->bind_param('i', $category_id);
}

$stmt->execute();
$result = $stmt->get_result();
$stmt->close();

$output = [];
while ($row = $result->fetch_assoc()) {
    $isScored = ($row['winner_id'] !== null);

    $output[] = [
        'tiebreaker_id'       => intval($row['tiebreaker_id']),
        'category_id'         => intval($row['category_id']),
        'group_label'         => $row['group_label'],
        // Use tiebreaker_id as the match reference so the scoring app
        // can pass it to save_tiebreaker_score.php
        'match_id'            => intval($row['tiebreaker_id']),
        'team1_id'            => intval($row['team1_id']),
        'team1_name'          => $row['team1_name'],
        'team2_id'            => intval($row['team2_id']),
        'team2_name'          => $row['team2_name'],
        'team1_score'         => $row['team1_score'] !== null ? intval($row['team1_score']) : null,
        'team2_score'         => $row['team2_score'] !== null ? intval($row['team2_score']) : null,
        'winner_id'           => $row['winner_id']   !== null ? intval($row['winner_id'])   : null,
        'scheduled_time'      => $row['scheduled_time'] ?? '',
        'arena_number'        => intval($row['arena_number']),
        'is_penalty_shootout' => intval($row['is_penalty_shootout']),
        'is_scored'           => $isScored,
    ];
}

$conn->close();
echo json_encode($output);
?>