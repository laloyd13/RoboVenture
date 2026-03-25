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

    // ── GET MATCH SCORES ─────────────────────────────────────────────
    // GET scoring.php?action=get_match_scores&match_id=1
    // Returns all score rows for a match (home + away)
    case 'get_match_scores':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $match_id = isset($_GET['match_id']) ? intval($_GET['match_id']) : 0;
        if ($match_id <= 0) { badRequest('Invalid or missing match_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT
                sc.score_id,
                sc.team_id,
                t.team_name,
                sc.score_independentscore,
                sc.score_violation,
                sc.score_totalscore,
                sc.score_totalduration,
                sc.score_isapproved,
                sc.round_id,
                sc.referee_id
            FROM tbl_score sc
            JOIN tbl_team t ON t.team_id = sc.team_id
            WHERE sc.match_id = ?
            ORDER BY sc.score_id ASC
        ");
        $stmt->bind_param("i", $match_id);
        $stmt->execute();
        $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
        echo json_encode($rows);
        $stmt->close();
        $conn->close();
        break;

    // ── GET TEAM COUNT ────────────────────────────────────────────────
    // GET scoring.php?action=get_team_count&category_id=4
    // For soccer: counts distinct teams in tbl_soccer_groups for this category.
    // R16 is always active for soccer (top 2 per group × 8 groups = 16 teams).
    case 'get_team_count':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;
        if ($category_id <= 0) { badRequest('Invalid or missing category_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT COUNT(DISTINCT team_id) AS count
            FROM tbl_soccer_groups
            WHERE category_id = ?
        ");
        $stmt->bind_param("i", $category_id);
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();
        // If teams exist in tbl_soccer_groups, use that count.
        // R16 activates when >= 16 teams (8 groups × 2 qualifiers).
        $count = (int) ($row['count'] ?? 0);
        echo json_encode(['count' => $count]);
        $stmt->close();
        $conn->close();
        break;

    // ── GET GROUP STANDINGS ───────────────────────────────────────────
    // GET scoring.php?action=get_group_standings&category_id=4
    // Returns per-group standings with W/D/L/Pts/GD for all teams.
    // Uses tbl_soccer_groups for group membership and tbl_score for results.
    // Match results: score_independentscore = goals scored by that team row.
    // The AWAY team's score is in the partner row of the same match_id.
    case 'get_group_standings':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;
        if ($category_id <= 0) { badRequest('Invalid or missing category_id'); break; }

        $conn = getConnection();

        // 1. Get all group members
        $gStmt = $conn->prepare("
            SELECT group_label, team_id, team_name
            FROM tbl_soccer_groups
            WHERE category_id = ?
            ORDER BY group_label ASC, team_id ASC
        ");
        $gStmt->bind_param("i", $category_id);
        $gStmt->execute();
        $gRows = $gStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $gStmt->close();

        // Build: group_label -> [team_id -> team_name]
        $groups = [];
        $teamGroup = []; // team_id -> group_label
        foreach ($gRows as $r) {
            $g = $r['group_label'];
            $tid = (int)$r['team_id'];
            if (!isset($groups[$g])) $groups[$g] = [];
            $groups[$g][$tid] = $r['team_name'];
            $teamGroup[$tid] = $g;
        }

        // 2. Get all qualification scores for this category
        $sStmt = $conn->prepare("
            SELECT s.match_id, s.team_id, s.score_independentscore AS goals
            FROM tbl_score s
            JOIN tbl_team t ON t.team_id = s.team_id
            WHERE t.category_id = ?
              AND s.round_id = 1
            ORDER BY s.match_id ASC, s.score_id ASC
        ");
        $sStmt->bind_param("i", $category_id);
        $sStmt->execute();
        $sRows = $sStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $sStmt->close();

        // Group scores by match_id (each match has 2 rows: home + away)
        $matchRows = [];
        foreach ($sRows as $r) {
            $matchRows[(int)$r['match_id']][] = $r;
        }

        // 3. Calculate standings per team
        // standings[team_id] = [played, won, drawn, lost, gf, ga, pts]
        $standings = [];
        foreach (array_keys($teamGroup) as $tid) {
            $standings[$tid] = ['played'=>0,'won'=>0,'drawn'=>0,'lost'=>0,
                                'gf'=>0,'ga'=>0,'pts'=>0];
        }

        foreach ($matchRows as $mid => $rows) {
            if (count($rows) < 2) continue;
            $a = $rows[0];
            $b = $rows[1];
            $tidA = (int)$a['team_id'];
            $tidB = (int)$b['team_id'];
            $goalsA = (int)$a['goals'];
            $goalsB = (int)$b['goals'];

            // Only process teams that are in groups for this category
            if (!isset($standings[$tidA]) || !isset($standings[$tidB])) continue;

            $standings[$tidA]['played']++;
            $standings[$tidA]['gf'] += $goalsA;
            $standings[$tidA]['ga'] += $goalsB;

            $standings[$tidB]['played']++;
            $standings[$tidB]['gf'] += $goalsB;
            $standings[$tidB]['ga'] += $goalsA;

            if ($goalsA > $goalsB) {
                $standings[$tidA]['won']++;  $standings[$tidA]['pts'] += 3;
                $standings[$tidB]['lost']++;
            } elseif ($goalsA < $goalsB) {
                $standings[$tidB]['won']++;  $standings[$tidB]['pts'] += 3;
                $standings[$tidA]['lost']++;
            } else {
                $standings[$tidA]['drawn']++; $standings[$tidA]['pts']++;
                $standings[$tidB]['drawn']++; $standings[$tidB]['pts']++;
            }
        }

        // 4. Build response grouped by group_label, sorted by pts desc, gd desc
        $response = [];
        foreach ($groups as $label => $members) {
            $groupStandings = [];
            foreach ($members as $tid => $tname) {
                $s = $standings[$tid] ?? ['played'=>0,'won'=>0,'drawn'=>0,
                                          'lost'=>0,'gf'=>0,'ga'=>0,'pts'=>0];
                $groupStandings[] = [
                    'team_id'    => $tid,
                    'team_name'  => $tname,
                    'group'      => $label,
                    'played'     => $s['played'],
                    'won'        => $s['won'],
                    'drawn'      => $s['drawn'],
                    'lost'       => $s['lost'],
                    'gf'         => $s['gf'],
                    'ga'         => $s['ga'],
                    'gd'         => $s['gf'] - $s['ga'],
                    'pts'        => $s['pts'],
                ];
            }
            // Sort: pts desc → gd desc → gf desc
            usort($groupStandings, function($x, $y) {
                if ($x['pts'] !== $y['pts']) return $y['pts'] - $x['pts'];
                if ($x['gd']  !== $y['gd'])  return $y['gd']  - $x['gd'];
                return $y['gf'] - $x['gf'];
            });
            $response[$label] = $groupStandings;
        }

        echo json_encode($response);
        $conn->close();
        break;

    // ── GET QUALIFIERS (GROUP STAGE AWARE) ───────────────────────────
    // GET scoring.php?action=get_qualifiers&category_id=4
    // For soccer: returns top 2 per group ordered by group A→H, rank 1→2.
    // This gives 16 qualifiers for the R16 bracket in seeded order.
    // Seeding: Group A 1st, Group B 1st … Group H 1st, Group A 2nd … Group H 2nd
    case 'get_qualifiers':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;
        if ($category_id <= 0) { badRequest('Invalid or missing category_id'); break; }

        $conn = getConnection();

        // Reuse group standings logic inline
        $gStmt = $conn->prepare("
            SELECT group_label, team_id, team_name
            FROM tbl_soccer_groups
            WHERE category_id = ?
            ORDER BY group_label ASC
        ");
        $gStmt->bind_param("i", $category_id);
        $gStmt->execute();
        $gRows = $gStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $gStmt->close();

        $groups2 = []; $teamGroup2 = [];
        foreach ($gRows as $r) {
            $g = $r['group_label']; $tid = (int)$r['team_id'];
            if (!isset($groups2[$g])) $groups2[$g] = [];
            $groups2[$g][$tid] = $r['team_name'];
            $teamGroup2[$tid] = $g;
        }

        $sStmt = $conn->prepare("
            SELECT s.match_id, s.team_id, s.score_independentscore AS goals
            FROM tbl_score s
            JOIN tbl_team t ON t.team_id = s.team_id
            WHERE t.category_id = ?
              AND s.round_id = 1
            ORDER BY s.match_id ASC, s.score_id ASC
        ");
        $sStmt->bind_param("i", $category_id);
        $sStmt->execute();
        $sRows2 = $sStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $sStmt->close();

        $matchRows2 = [];
        foreach ($sRows2 as $r) $matchRows2[(int)$r['match_id']][] = $r;

        $standings2 = [];
        foreach (array_keys($teamGroup2) as $tid) {
            $standings2[$tid] = ['played'=>0,'won'=>0,'drawn'=>0,'lost'=>0,
                                  'gf'=>0,'ga'=>0,'pts'=>0,'team_name'=>''];
        }
        foreach ($gRows as $r) {
            $standings2[(int)$r['team_id']]['team_name'] = $r['team_name'];
        }

        foreach ($matchRows2 as $mid => $rows) {
            if (count($rows) < 2) continue;
            $tidA = (int)$rows[0]['team_id']; $goalsA = (int)$rows[0]['goals'];
            $tidB = (int)$rows[1]['team_id']; $goalsB = (int)$rows[1]['goals'];
            if (!isset($standings2[$tidA]) || !isset($standings2[$tidB])) continue;
            $standings2[$tidA]['played']++; $standings2[$tidA]['gf']+=$goalsA; $standings2[$tidA]['ga']+=$goalsB;
            $standings2[$tidB]['played']++; $standings2[$tidB]['gf']+=$goalsB; $standings2[$tidB]['ga']+=$goalsA;
            if ($goalsA > $goalsB)      { $standings2[$tidA]['won']++;  $standings2[$tidA]['pts']+=3; $standings2[$tidB]['lost']++; }
            elseif ($goalsA < $goalsB)  { $standings2[$tidB]['won']++;  $standings2[$tidB]['pts']+=3; $standings2[$tidA]['lost']++; }
            else                        { $standings2[$tidA]['drawn']++; $standings2[$tidA]['pts']++; $standings2[$tidB]['drawn']++; $standings2[$tidB]['pts']++; }
        }

        // Pick top 2 per group
        $firsts = []; $seconds = [];
        foreach ($groups2 as $label => $members) {
            $ranked = [];
            foreach ($members as $tid => $tname) {
                $s = $standings2[$tid];
                $ranked[] = ['team_id'=>$tid,'team_name'=>$s['team_name'],
                             'pts'=>$s['pts'],'gd'=>$s['gf']-$s['ga'],
                             'gf'=>$s['gf'],'total_score'=>$s['pts'],'group'=>$label];
            }
            usort($ranked, function($x,$y){
                if ($x['pts']!==$y['pts']) return $y['pts']-$x['pts'];
                if ($x['gd'] !==$y['gd'])  return $y['gd']-$x['gd'];
                return $y['gf']-$x['gf'];
            });
            if (count($ranked) >= 1) $firsts[]  = $ranked[0];
            if (count($ranked) >= 2) $seconds[] = $ranked[1];
        }

        // Seeding: all group winners first, then all runners-up
        // Within each tier, order by group label (A, B, C...)
        $qualifiers = array_merge($firsts, $seconds);
        echo json_encode($qualifiers);
        $conn->close();
        break;

    // ── CHAMPIONSHIP SUBMIT SCORE ────────────────────────────────────
    // POST scoring.php?action=championship_submit_score
    // Same as submit_score but temporarily disables FK checks so that
    // championship match IDs (101–104, 201–202, 301, 1001–1016) can be
    // inserted without needing rows in tbl_match.
    case 'championship_submit_score':
        if ($method !== 'POST') { methodNotAllowed(); break; }

        $body = file_get_contents('php://input');
        $data = json_decode($body, true);
        if (!$data) { badRequest('Invalid or empty JSON body'); break; }

        $required = [
            'match_id', 'round_id', 'team_id', 'referee_id',
            'score_independentscore', 'score_violation',
            'score_totalscore', 'score_totalduration'
        ];
        foreach ($required as $field) {
            if (!isset($data[$field]) || $data[$field] === '') {
                badRequest("Missing required field: $field"); exit();
            }
        }

        $match_id         = intval($data['match_id']);
        $team_id          = intval($data['team_id']);
        $referee_id       = intval($data['referee_id']);
        $independentScore = intval($data['score_independentscore']);
        $violation        = intval($data['score_violation']);
        $totalScore       = intval($data['score_totalscore']);
        $totalDuration    = $data['score_totalduration'];
        $isApproved       = isset($data['score_isapproved']) ? intval($data['score_isapproved']) : 0;

        // Derive the correct round_id from match_id so the DB always reflects
        // the true round regardless of what the client sends.
        // Qualification = 1 (handled by submit_score, not this endpoint).
        //   ELIM   501–512  → round_id 2
        //   R16   1001–1016 → round_id 2  (same round level as ELIM)
        //   QF     101–104  → round_id 3
        //   SF     201–202  → round_id 4
        //   3RD    401      → round_id 5  (final round, same as FINAL)
        //   FINAL  301      → round_id 5
        if (($match_id >= 501 && $match_id <= 512) ||
            ($match_id >= 1001 && $match_id <= 1016)) {
            $round_id = 2; // ELIM / R16
        } elseif ($match_id >= 101 && $match_id <= 104) {
            $round_id = 3; // Quarter-Final
        } elseif ($match_id >= 201 && $match_id <= 202) {
            $round_id = 4; // Semi-Final
        } elseif ($match_id === 401 || $match_id === 301) {
            $round_id = 5; // 3rd Place / Final
        } else {
            // Fallback: use whatever the client sent
            $round_id = intval($data['round_id']);
        }

        $conn = getConnection();

        // Disable FK checks so championship match IDs don't need tbl_match rows
        $conn->query('SET FOREIGN_KEY_CHECKS=0');

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
            $conn->query('SET FOREIGN_KEY_CHECKS=1');
            http_response_code(500);
            echo json_encode(['error' => 'Prepare failed: ' . $conn->error]);
            $conn->close();
            break;
        }

        $stmt->bind_param(
            "iiisiiiii",
            $independentScore, $violation, $totalScore,
            $totalDuration, $isApproved,
            $match_id, $round_id, $team_id, $referee_id
        );

        $ok = $stmt->execute();
        $conn->query('SET FOREIGN_KEY_CHECKS=1'); // always re-enable

        if ($ok) {
            http_response_code(201);
            echo json_encode([
                'success'  => true,
                'score_id' => $conn->insert_id,
                'message'  => 'Championship score submitted successfully'
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