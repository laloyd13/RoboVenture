<?php
// ─────────────────────────────────────────────────────────────────────
// get_teamschedule.php
// GET ?category_id=4
// GET ?category_id=4&bracket_type=quarter-finals   (optional filter)
//
// Returns all team schedule entries for the given category.
// bracket_type is now included in every row so the scoring app can
// identify which round each match belongs to without hardcoded IDs.
//
// Optional bracket_type filter:
//   group, elimination, round-of-32, round-of-16, round-of-8,
//   quarter-finals, semi-finals, third-place, final
// ─────────────────────────────────────────────────────────────────────
ini_set('display_errors', 0);
error_reporting(0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Cache-Control: no-store, no-cache, must-revalidate");
header("Pragma: no-cache");

require_once 'db_config.php';

$cat_id       = isset($_GET['category_id'])  ? intval($_GET['category_id'])      : 0;
$bracket_type = isset($_GET['bracket_type']) ? trim($_GET['bracket_type'])        : '';

if (!$cat_id) {
    echo json_encode(["error" => "No category selected"]);
    exit();
}

// Build query — optionally filter by bracket_type
if ($bracket_type !== '') {
    $sql = "
        SELECT
            ts.teamschedule_id,
            ts.match_id,
            ts.match_id        AS match_number,
            ts.team_id,
            t.team_name,
            ts.referee_id,
            ts.arena_number,
            m.bracket_type,
            TIME_FORMAT(s.schedule_start, '%H:%i') AS match_time
        FROM tbl_teamschedule ts
        INNER JOIN tbl_team     t ON t.team_id     = ts.team_id
        INNER JOIN tbl_match    m ON m.match_id    = ts.match_id
        INNER JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE t.category_id = ?
          AND m.bracket_type = ?
        ORDER BY s.schedule_start ASC, ts.match_id ASC, ts.teamschedule_id ASC";

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        echo json_encode(["error" => "Prepare failed: " . $conn->error]);
        exit();
    }
    $stmt->bind_param("is", $cat_id, $bracket_type);
} else {
    $sql = "
        SELECT
            ts.teamschedule_id,
            ts.match_id,
            ts.match_id        AS match_number,
            ts.team_id,
            t.team_name,
            ts.referee_id,
            ts.arena_number,
            m.bracket_type,
            TIME_FORMAT(s.schedule_start, '%H:%i') AS match_time
        FROM tbl_teamschedule ts
        INNER JOIN tbl_team     t ON t.team_id     = ts.team_id
        INNER JOIN tbl_match    m ON m.match_id    = ts.match_id
        INNER JOIN tbl_schedule s ON s.schedule_id = m.schedule_id
        WHERE t.category_id = ?
        ORDER BY s.schedule_start ASC, ts.match_id ASC, ts.teamschedule_id ASC";

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        echo json_encode(["error" => "Prepare failed: " . $conn->error]);
        exit();
    }
    $stmt->bind_param("i", $cat_id);
}

$stmt->execute();

if ($stmt->errno) {
    echo json_encode(["error" => "Execute failed: " . $stmt->error]);
    exit();
}

$result   = $stmt->get_result();
$schedule = [];

while ($row = $result->fetch_assoc()) {
    $schedule[] = [
        'teamschedule_id' => (int)$row['teamschedule_id'],
        'match_id'        => (int)$row['match_id'],
        'match_number'    => (int)$row['match_number'],
        'team_id'         => (int)$row['team_id'],
        'team_name'       => $row['team_name'],
        'referee_id'      => (int)$row['referee_id'],
        'arena_number'    => (int)$row['arena_number'],
        'bracket_type'    => $row['bracket_type'],
        'match_time'      => $row['match_time'] ?? '',
    ];
}

echo json_encode($schedule);

$stmt->close();
$conn->close();
?>