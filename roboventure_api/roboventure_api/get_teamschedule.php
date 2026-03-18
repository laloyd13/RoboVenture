<?php
ini_set('display_errors', 0);
error_reporting(0);
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
// Force no cache
header("Cache-Control: no-store, no-cache, must-revalidate");
header("Pragma: no-cache");

require_once 'db_config.php';

$cat_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;

if (!$cat_id) {
    echo json_encode(["error" => "No category selected"]);
    exit();
}

// Fetch ALL matches for category — NO arena filter.
// The mobile app filters by arena_number client-side.
$sql = "SELECT 
            ts.teamschedule_id,
            ts.match_id,
            ts.match_id AS match_number, 
            ts.team_id, 
            t.team_name,
            ts.referee_id,
            ts.arena_number
        FROM tbl_teamschedule ts
        INNER JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE t.category_id = ?
        ORDER BY ts.match_id ASC, ts.teamschedule_id ASC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    echo json_encode(["error" => "Prepare failed: " . $conn->error]);
    exit();
}

$stmt->bind_param("i", $cat_id);
$stmt->execute();

if ($stmt->errno) {
    echo json_encode(["error" => "Execute failed: " . $stmt->error]);
    exit();
}

$schedule = [];
$stmt->bind_result(
    $teamschedule_id, $match_id, $match_number,
    $team_id, $team_name, $referee_id, $arena_number_val
);
while ($stmt->fetch()) {
    $schedule[] = [
        'teamschedule_id' => (int)$teamschedule_id,
        'match_id'        => (int)$match_id,
        'match_number'    => (int)$match_number,
        'team_id'         => (int)$team_id,
        'team_name'       => $team_name,
        'referee_id'      => (int)$referee_id,
        'arena_number'    => (int)$arena_number_val,
    ];
}

echo json_encode($schedule);

$stmt->close();
$conn->close();
?>