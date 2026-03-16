<?php
ini_set('display_errors', 0);
error_reporting(0);
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

require_once 'db_config.php';

$cat_id       = isset($_GET['category_id']) ? $_GET['category_id'] : null;
$arena_number = isset($_GET['arena_number']) ? intval($_GET['arena_number']) : null;

if (!$cat_id) {
    echo json_encode(["error" => "No category selected"]);
    exit();
}

if ($arena_number) {
    $sql = "SELECT 
                ts.match_id,
                ts.match_id AS match_number, 
                ts.team_id, 
                t.team_name,
                ts.referee_id,
                ts.arena_number
            FROM tbl_teamschedule ts
            INNER JOIN tbl_team t ON ts.team_id = t.team_id
            WHERE t.category_id  = ?
              AND ts.arena_number = ?
            ORDER BY ts.match_id ASC";
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        echo json_encode(["error" => "Prepare failed: " . $conn->error]);
        exit();
    }
    $stmt->bind_param("ii", $cat_id, $arena_number);
} else {
    // No arena filter — return all (backwards compatible)
    $sql = "SELECT 
                ts.match_id,
                ts.match_id AS match_number, 
                ts.team_id, 
                t.team_name,
                ts.referee_id,
                ts.arena_number
            FROM tbl_teamschedule ts
            INNER JOIN tbl_team t ON ts.team_id = t.team_id
            WHERE t.category_id = ?
            ORDER BY ts.match_id ASC";
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

$schedule = [];
$stmt->bind_result($match_id, $match_number, $team_id, $team_name, $referee_id, $arena_number_val);
while ($stmt->fetch()) {
    $schedule[] = [
        'match_id'     => (int)$match_id,
        'match_number' => (int)$match_number,
        'team_id'      => (int)$team_id,
        'team_name'    => $team_name,
        'referee_id'   => (int)$referee_id,
        'arena_number' => (int)$arena_number_val,
    ];
}

echo json_encode($schedule);

$stmt->close();
$conn->close();
?>