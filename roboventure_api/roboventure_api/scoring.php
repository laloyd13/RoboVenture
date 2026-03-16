<?php
// ─────────────────────────────────────────────────────────────────────
// ENDPOINTS
//   GET  api.php?action=get_match&match_id=1
//   GET  api.php?action=get_referee&referee_id=1
//   GET  api.php?action=get_team&team_id=1
//   GET  api.php?action=get_categories
//   GET  api.php?action=get_rounds
//   POST api.php?action=submit_score   (JSON body)
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// DATABASE CONFIG
// ─────────────────────────────────────────────────────────────────────
require_once 'db_config.php';

// ─────────────────────────────────────────────────────────────────────
// DB CONNECTION
// ─────────────────────────────────────────────────────────────────────
function getConnection() {
    global $conn;
    if ($conn->connect_error) {
        http_response_code(500);
        echo json_encode(['error' => 'Database connection failed: ' . $conn->connect_error]);
        exit();
    }
    return $conn;
}

// ─────────────────────────────────────────────────────────────────────
// ROUTER
// ─────────────────────────────────────────────────────────────────────
$action = $_GET['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];

if (empty($action)) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing action parameter']);
    exit();
}

switch ($action) {

    // ── GET MATCH ─────────────────────────────────────────────────────
    // GET api.php?action=get_match&match_id=1
    // Joins tbl_match with tbl_schedule
    case 'get_match':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $match_id = isset($_GET['match_id']) ? intval($_GET['match_id']) : 0;
        if ($match_id <= 0) { badRequest('Invalid or missing match_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT 
                m.match_id,
                m.schedule_id,
                s.schedule_start,
                s.schedule_end
            FROM tbl_match m
            INNER JOIN tbl_schedule s ON m.schedule_id = s.schedule_id
            WHERE m.match_id = ?
            LIMIT 1
        ");
        $stmt->bind_param("i", $match_id);
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();

        if ($row) {
            echo json_encode($row);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Match not found']);
        }

        $stmt->close();
        $conn->close();
        break;

    // ── GET REFEREE ───────────────────────────────────────────────────
    // GET api.php?action=get_referee&referee_id=1
    case 'get_referee':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $referee_id = isset($_GET['referee_id']) ? intval($_GET['referee_id']) : 0;
        if ($referee_id <= 0) { badRequest('Invalid or missing referee_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT 
                referee_id,
                referee_name,
                arena_id
            FROM tbl_referee
            WHERE referee_id = ?
            LIMIT 1
        ");
        $stmt->bind_param("i", $referee_id);
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();

        if ($row) {
            echo json_encode($row);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Referee not found']);
        }

        $stmt->close();
        $conn->close();
        break;

    // ── GET TEAM ──────────────────────────────────────────────────────
    // GET api.php?action=get_team&team_id=1
    case 'get_team':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $team_id = isset($_GET['team_id']) ? intval($_GET['team_id']) : 0;
        if ($team_id <= 0) { badRequest('Invalid or missing team_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT 
                team_id,
                team_name,
                team_ispresent,
                mentor_id,
                category_id
            FROM tbl_team
            WHERE team_id = ?
            LIMIT 1
        ");
        $stmt->bind_param("i", $team_id);
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();

        if ($row) {
            echo json_encode($row);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Team not found']);
        }

        $stmt->close();
        $conn->close();
        break;

    // ── GET CATEGORIES ────────────────────────────────────────────────
    // GET api.php?action=get_categories
    case 'get_categories':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $conn = getConnection();
        $result = $conn->query("
            SELECT 
                category_id,
                category_type,
                status
            FROM tbl_category
            WHERE status = 'active'
            ORDER BY category_id ASC
        ");

        $categories = [];
        while ($row = $result->fetch_assoc()) {
            $categories[] = $row;
        }

        echo json_encode($categories);
        $conn->close();
        break;

    // ── GET ROUNDS ────────────────────────────────────────────────────
    // GET api.php?action=get_rounds
    case 'get_rounds':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $conn = getConnection();
        $result = $conn->query("
            SELECT 
                round_id,
                round_type
            FROM tbl_round
            ORDER BY round_id ASC
        ");

        $rounds = [];
        while ($row = $result->fetch_assoc()) {
            $rounds[] = $row;
        }

        echo json_encode($rounds);
        $conn->close();
        break;

    // ── SUBMIT SCORE ──────────────────────────────────────────────────
    // POST api.php?action=submit_score
    // Body (JSON):
    // {
    //   "match_id": 1,
    //   "round_id": 1,
    //   "team_id": 1,
    //   "referee_id": 1,
    //   "score_independentscore": 120,
    //   "score_violation": 1,
    //   "score_totalscore": 110,
    //   "score_totalduration": "02:35",
    //   "score_isapproved": 0
    // }
    case 'submit_score':
        if ($method !== 'POST') { methodNotAllowed(); break; }

        $body = file_get_contents('php://input');
        $data = json_decode($body, true);

        if (!$data) { badRequest('Invalid or empty JSON body'); break; }

        // Validate required fields
        $required = [
            'match_id', 'round_id', 'team_id', 'referee_id',
            'score_independentscore', 'score_violation',
            'score_totalscore', 'score_totalduration'
        ];
        foreach ($required as $field) {
            if (!isset($data[$field]) || $data[$field] === '') {
                badRequest("Missing required field: $field");
                exit();
            }
        }

        // Sanitize
        $match_id         = intval($data['match_id']);
        $round_id         = intval($data['round_id']);
        $team_id          = intval($data['team_id']);
        $referee_id       = intval($data['referee_id']);
        $independentScore = intval($data['score_independentscore']);
        $violation        = intval($data['score_violation']);
        $totalScore       = intval($data['score_totalscore']);
        $totalDuration    = $data['score_totalduration'];   // e.g. "02:35"
        $isApproved       = isset($data['score_isapproved']) ? intval($data['score_isapproved']) : 0;

        $conn = getConnection();
        $stmt = $conn->prepare("
            INSERT INTO tbl_score (
                score_independentscore,
                score_violation,
                score_totalscore,
                score_totalduration,
                score_isapproved,
                match_id,
                round_id,
                team_id,
                referee_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");

        if (!$stmt) {
            http_response_code(500);
            echo json_encode(['error' => 'Prepare failed: ' . $conn->error]);
            $conn->close();
            break;
        }

        $stmt->bind_param(
            "iiisiiiii",
            $independentScore,
            $violation,
            $totalScore,
            $totalDuration,
            $isApproved,
            $match_id,
            $round_id,
            $team_id,
            $referee_id
        );

        if ($stmt->execute()) {
            http_response_code(201);
            echo json_encode([
                'success' => true,
                'score_id' => $conn->insert_id,
                'message' => 'Score submitted successfully'
            ]);
        } else {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to insert score: ' . $stmt->error]);
        }

        $stmt->close();
        $conn->close();
        break;

    // ── UNKNOWN ACTION ────────────────────────────────────────────────
    default:
        http_response_code(404);
        echo json_encode(['error' => "Unknown action: '$action'"]);
        break;
}

// ─────────────────────────────────────────────────────────────────────
// HELPER FUNCTIONS
// ─────────────────────────────────────────────────────────────────────
function badRequest(string $msg): void {
    http_response_code(400);
    echo json_encode(['error' => $msg]);
    exit();
}

function methodNotAllowed(): void {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit();
}