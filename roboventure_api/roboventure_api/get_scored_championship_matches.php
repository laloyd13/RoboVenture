<?php
ini_set('display_errors', 0);
error_reporting(0);

header('Content-Type: application/json');

require_once 'db_config.php';

$category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;

if ($category_id === 0) {
    http_response_code(400);
    echo json_encode(["error" => "category_id is required"]);
    exit;
}

// Championship + ELIM match IDs recognised by the Flutter app:
//
//   ELIM:          501–512   (up to 12 matches; actual count depends on group count)
//   R16:           1001–1016
//   QUARTER-FINAL: 101–104
//   SEMI-FINAL:    201–202
//   FINAL:         301
//
// A match is considered scored when at least ONE team entry exists in tbl_score
// for that match_id, joined to tbl_team to confirm it belongs to this category.

$stmt = $conn->prepare(
    "SELECT DISTINCT s.match_id
     FROM tbl_score s
     INNER JOIN tbl_team t ON t.team_id = s.team_id
     WHERE t.category_id = ?
       AND s.match_id IN (
           501, 502, 503, 504, 505, 506,
           507, 508, 509, 510, 511, 512,
           101, 102, 103, 104,
           201, 202,
           301,
           1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008,
           1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016
       )"
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
    $rows[] = ["match_id" => (int)$row["match_id"]];
}

$stmt->close();
$conn->close();

echo json_encode($rows);
?>