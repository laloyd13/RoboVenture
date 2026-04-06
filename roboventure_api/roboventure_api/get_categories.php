<?php
// ─────────────────────────────────────────────────────────────────────
// get_categories.php
// GET (no params) — returns all active categories with access_code
// ─────────────────────────────────────────────────────────────────────
ini_set('display_errors', 0);
error_reporting(0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Cache-Control: no-store, no-cache, must-revalidate");

require_once 'db_config.php';

$result = $conn->query("
    SELECT
        category_id,
        category_type,
        status,
        access_code
    FROM tbl_category
    ORDER BY category_id ASC
");

if (!$result) {
    http_response_code(500);
    echo json_encode(["error" => "Query failed: " . $conn->error]);
    exit;
}

$data = [];
while ($row = $result->fetch_assoc()) {
    $data[] = [
        'category_id'   => (int)$row['category_id'],
        'category_type' => $row['category_type'],
        'status'        => $row['status'],
        'access_code'   => $row['access_code'],
    ];
}

echo json_encode($data);
$conn->close();
?>