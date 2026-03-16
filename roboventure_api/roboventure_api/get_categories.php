<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
include 'db_config.php';

$sql = "SELECT category_id, category_type, status FROM tbl_category"; 
$result = $conn->query($sql);

$data = [];
while($row = $result->fetch_assoc()) {
    $data[] = $row;
}

echo json_encode($data);
$conn->close();
?>