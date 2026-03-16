<?php
ini_set('display_errors', 0);
error_reporting(0);

require_once 'db_config.php';

$category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;

if ($category_id === 0) {
    http_response_code(400);
    echo json_encode(["error" => "category_id is required"]);
    exit;
}

// Returns match_id + team_id pairs that have a score entry for this category.
// Select team_id directly from tbl_score (not via tbl_teamschedule) so only
// the specific team that was scored is returned — not every team in that match.
$stmt = $conn->prepare(
    "SELECT DISTINCT s.match_id, s.team_id
     FROM tbl_score s
     INNER JOIN tbl_team t ON t.team_id = s.team_id
     WHERE t.category_id = ?"
);

if (!$stmt) {
    http_response_code(500);
    echo json_encode(["error" => "Prepare failed: " . $conn->error]);
    exit;
}

$stmt->bind_param("i", $category_id);
$stmt->execute();
$result = $stmt->get_result();

$rows = [];
while ($row = $result->fetch_assoc()) {
    $rows[] = [
        "match_id" => (int)$row["match_id"],
        "team_id"  => (int)$row["team_id"],
    ];
}

$stmt->close();
$conn->close();

echo json_encode($rows);
?>