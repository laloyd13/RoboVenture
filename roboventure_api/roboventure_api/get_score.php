<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

require_once 'db_config.php';

$result = $conn->query("SELECT * FROM tbl_score ORDER BY score_id DESC LIMIT 10");

$data = [];
while($row = $result->fetch_assoc()) {
    $data[] = $row;
}

echo json_encode($data);
$conn->close();
?>