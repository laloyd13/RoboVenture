<?php
// ─────────────────────────────────────────────────────────────────────
// get_scored_matches.php
// GET ?category_id=4
//
// Returns all scored match entries (qualification AND knockout) for the
// given category. The client uses bracket_type to filter by round.
//
// Previously relied on hardcoded match ID ranges (501–512, 101–104 etc).
// Now uses bracket_type from tbl_match so it works with auto-generated
// match IDs from the admin app.
// ─────────────────────────────────────────────────────────────────────
ini_set('display_errors', 0);
error_reporting(0);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-store, no-cache, must-revalidate');

require_once 'db_config.php';

$category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;

if ($category_id === 0) {
    http_response_code(400);
    echo json_encode(["error" => "category_id is required"]);
    exit;
}

// Returns the latest score row per (match_id, team_id) pair.
// bracket_type is included so the client can filter by round without
// relying on hardcoded match ID ranges.
$stmt = $conn->prepare("
    SELECT
        s.match_id,
        s.team_id,
        s.score_totalscore,
        s.score_independentscore,
        m.bracket_type
    FROM tbl_score s
    INNER JOIN tbl_team  t ON t.team_id  = s.team_id
    INNER JOIN tbl_match m ON m.match_id = s.match_id
    WHERE t.category_id = ?
    ORDER BY s.score_id DESC
");

if (!$stmt) {
    http_response_code(500);
    echo json_encode(["error" => "Prepare failed: " . $conn->error]);
    exit;
}

$stmt->bind_param("i", $category_id);
$stmt->execute();
$result = $stmt->get_result();

$rows = [];
$seen = [];
while ($row = $result->fetch_assoc()) {
    // ORDER BY score_id DESC → first occurrence is the latest score
    $key = $row['match_id'] . '_' . $row['team_id'];
    if (!isset($seen[$key])) {
        $seen[$key] = true;
        $rows[] = [
            "match_id"               => (int)$row["match_id"],
            "team_id"                => (int)$row["team_id"],
            "score_totalscore"       => (int)$row["score_totalscore"],
            "score_independentscore" => (int)$row["score_independentscore"],
            "bracket_type"           => $row["bracket_type"],
        ];
    }
}

$stmt->close();
$conn->close();

echo json_encode($rows);
?>