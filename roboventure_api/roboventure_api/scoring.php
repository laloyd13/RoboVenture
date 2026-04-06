<?php
// ─────────────────────────────────────────────────────────────────────
// scoring.php
//
// ENDPOINTS
//   GET  scoring.php?action=get_match&match_id=1
//   GET  scoring.php?action=get_referee&referee_id=1
//   GET  scoring.php?action=get_team&team_id=1
//   GET  scoring.php?action=get_categories
//   GET  scoring.php?action=get_rounds
//   GET  scoring.php?action=get_match_scores&match_id=1
//   GET  scoring.php?action=get_team_count&category_id=4
//   GET  scoring.php?action=get_group_standings&category_id=4
//   GET  scoring.php?action=get_qualifiers&category_id=4
//   GET  scoring.php?action=get_knockout_matches&category_id=4&bracket_type=quarter-finals
//   POST scoring.php?action=submit_score          (JSON body)
//   POST scoring.php?action=championship_submit_score  (JSON body)
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
    // GET scoring.php?action=get_match&match_id=1
    // Returns match info including bracket_type so the app knows the round.
    case 'get_match':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $match_id = isset($_GET['match_id']) ? intval($_GET['match_id']) : 0;
        if ($match_id <= 0) { badRequest('Invalid or missing match_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT
                m.match_id,
                m.schedule_id,
                m.bracket_type,
                s.schedule_start,
                s.schedule_end,
                TIME_FORMAT(s.schedule_start, '%H:%i') AS match_time
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
    // GET scoring.php?action=get_referee&referee_id=1
    case 'get_referee':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $referee_id = isset($_GET['referee_id']) ? intval($_GET['referee_id']) : 0;
        if ($referee_id <= 0) { badRequest('Invalid or missing referee_id'); break; }

        $conn = getConnection();
        $stmt = $conn->prepare("
            SELECT
                referee_id,
                referee_name
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
    // GET scoring.php?action=get_team&team_id=1
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
    // GET scoring.php?action=get_categories
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
    // GET scoring.php?action=get_rounds
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
    // POST scoring.php?action=submit_score
    // Used for group stage / qualification rounds.
    // Body (JSON):
    // {
    //   "match_id": 47,
    //   "round_id": 1,
    //   "team_id": 12,
    //   "referee_id": 1,
    //   "score_independentscore": 3,
    //   "score_violation": 0,
    //   "score_totalscore": 3,
    //   "score_totalduration": "02:35",
    //   "score_isapproved": 0
    // }
    case 'submit_score':
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
                badRequest("Missing required field: $field");
                exit();
            }
        }

        $match_id         = intval($data['match_id']);
        $round_id         = intval($data['round_id']);
        $team_id          = intval($data['team_id']);
        $referee_id       = intval($data['referee_id']);
        $independentScore = intval($data['score_independentscore']);
        $violation        = intval($data['score_violation']);
        $totalScore       = intval($data['score_totalscore']);
        $totalDuration    = $data['score_totalduration'];
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
                'success'  => true,
                'score_id' => $conn->insert_id,
                'message'  => 'Score submitted successfully'
            ]);
        } else {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to insert score: ' . $stmt->error]);
        }

        $stmt->close();
        $conn->close();
        break;

    // ── GET MATCH SCORES ─────────────────────────────────────────────
    // GET scoring.php?action=get_match_scores&match_id=47
    // Returns all score rows for a match (home + away).
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
        $row   = $stmt->get_result()->fetch_assoc();
        $count = (int)($row['count'] ?? 0);
        echo json_encode(['count' => $count]);
        $stmt->close();
        $conn->close();
        break;

    // ── GET GROUP STANDINGS ───────────────────────────────────────────
    // GET scoring.php?action=get_group_standings&category_id=4
    // Returns per-group standings with W/D/L/Pts/GD for all teams.
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

        $groups    = [];
        $teamGroup = [];
        foreach ($gRows as $r) {
            $g   = $r['group_label'];
            $tid = (int)$r['team_id'];
            if (!isset($groups[$g])) $groups[$g] = [];
            $groups[$g][$tid] = $r['team_name'];
            $teamGroup[$tid]  = $g;
        }

        // 2. Get all group-stage scores for this category using bracket_type
        $sStmt = $conn->prepare("
            SELECT s.match_id, s.team_id, s.score_independentscore AS goals
            FROM tbl_score s
            JOIN tbl_team  t ON t.team_id  = s.team_id
            JOIN tbl_match m ON m.match_id = s.match_id
            WHERE t.category_id = ?
              AND m.bracket_type = 'group'
            ORDER BY s.match_id ASC, s.score_id ASC
        ");
        $sStmt->bind_param("i", $category_id);
        $sStmt->execute();
        $sRows = $sStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $sStmt->close();

        $matchRows = [];
        foreach ($sRows as $r) {
            $matchRows[(int)$r['match_id']][] = $r;
        }

        $standings = [];
        foreach (array_keys($teamGroup) as $tid) {
            $standings[$tid] = ['played'=>0,'won'=>0,'drawn'=>0,'lost'=>0,
                                'gf'=>0,'ga'=>0,'pts'=>0];
        }

        foreach ($matchRows as $mid => $rows) {
            if (count($rows) < 2) continue;
            $a      = $rows[0];
            $b      = $rows[1];
            $tidA   = (int)$a['team_id'];
            $tidB   = (int)$b['team_id'];
            $goalsA = (int)$a['goals'];
            $goalsB = (int)$b['goals'];

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

        $response = [];
        foreach ($groups as $label => $members) {
            $groupStandings = [];
            foreach ($members as $tid => $tname) {
                $s = $standings[$tid] ?? ['played'=>0,'won'=>0,'drawn'=>0,
                                          'lost'=>0,'gf'=>0,'ga'=>0,'pts'=>0];
                $groupStandings[] = [
                    'team_id'   => $tid,
                    'team_name' => $tname,
                    'group'     => $label,
                    'played'    => $s['played'],
                    'won'       => $s['won'],
                    'drawn'     => $s['drawn'],
                    'lost'      => $s['lost'],
                    'gf'        => $s['gf'],
                    'ga'        => $s['ga'],
                    'gd'        => $s['gf'] - $s['ga'],
                    'pts'       => $s['pts'],
                ];
            }
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

    // ── GET QUALIFIERS ────────────────────────────────────────────────
    // GET scoring.php?action=get_qualifiers&category_id=4
    // Returns top 2 per group ordered by group A→H, rank 1→2.
    // Uses bracket_type = 'group' instead of round_id = 1.
    case 'get_qualifiers':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $category_id = isset($_GET['category_id']) ? intval($_GET['category_id']) : 0;
        if ($category_id <= 0) { badRequest('Invalid or missing category_id'); break; }

        $conn = getConnection();

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
            $g   = $r['group_label'];
            $tid = (int)$r['team_id'];
            if (!isset($groups2[$g])) $groups2[$g] = [];
            $groups2[$g][$tid] = $r['team_name'];
            $teamGroup2[$tid]  = $g;
        }

        // Use bracket_type = 'group' instead of round_id = 1
        $sStmt = $conn->prepare("
            SELECT s.match_id, s.team_id, s.score_independentscore AS goals
            FROM tbl_score s
            JOIN tbl_team  t ON t.team_id  = s.team_id
            JOIN tbl_match m ON m.match_id = s.match_id
            WHERE t.category_id = ?
              AND m.bracket_type = 'group'
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
            $tidA   = (int)$rows[0]['team_id']; $goalsA = (int)$rows[0]['goals'];
            $tidB   = (int)$rows[1]['team_id']; $goalsB = (int)$rows[1]['goals'];
            if (!isset($standings2[$tidA]) || !isset($standings2[$tidB])) continue;
            $standings2[$tidA]['played']++; $standings2[$tidA]['gf'] += $goalsA; $standings2[$tidA]['ga'] += $goalsB;
            $standings2[$tidB]['played']++; $standings2[$tidB]['gf'] += $goalsB; $standings2[$tidB]['ga'] += $goalsA;
            if ($goalsA > $goalsB)     { $standings2[$tidA]['won']++;  $standings2[$tidA]['pts'] += 3; $standings2[$tidB]['lost']++; }
            elseif ($goalsA < $goalsB) { $standings2[$tidB]['won']++;  $standings2[$tidB]['pts'] += 3; $standings2[$tidA]['lost']++; }
            else                       { $standings2[$tidA]['drawn']++; $standings2[$tidA]['pts']++; $standings2[$tidB]['drawn']++; $standings2[$tidB]['pts']++; }
        }

        $firsts = []; $seconds = [];
        foreach ($groups2 as $label => $members) {
            $ranked = [];
            foreach ($members as $tid => $tname) {
                $s        = $standings2[$tid];
                $ranked[] = ['team_id'    => $tid,
                             'team_name'  => $s['team_name'],
                             'pts'        => $s['pts'],
                             'gd'         => $s['gf'] - $s['ga'],
                             'gf'         => $s['gf'],
                             'total_score'=> $s['pts'],
                             'group'      => $label];
            }
            usort($ranked, function($x, $y) {
                if ($x['pts'] !== $y['pts']) return $y['pts'] - $x['pts'];
                if ($x['gd']  !== $y['gd'])  return $y['gd']  - $x['gd'];
                return $y['gf'] - $x['gf'];
            });
            if (count($ranked) >= 1) $firsts[]  = $ranked[0];
            if (count($ranked) >= 2) $seconds[] = $ranked[1];
        }

        $qualifiers = array_merge($firsts, $seconds);
        echo json_encode($qualifiers);
        $conn->close();
        break;

    // ── GET KNOCKOUT MATCHES BY ROUND ─────────────────────────────────
    // GET scoring.php?action=get_knockout_matches&category_id=4&bracket_type=quarter-finals
    //
    // Returns all matches for a specific knockout round with both teams,
    // using real auto-generated match IDs from tbl_match (set by admin).
    //
    // bracket_type values:
    //   elimination, round-of-32, round-of-16, round-of-8,
    //   quarter-finals, semi-finals, third-place, final
    case 'get_knockout_matches':
        if ($method !== 'GET') { methodNotAllowed(); break; }

        $category_id  = isset($_GET['category_id'])  ? intval($_GET['category_id'])  : 0;
        $bracket_type = isset($_GET['bracket_type'])  ? trim($_GET['bracket_type'])   : '';

        if ($category_id <= 0)    { badRequest('Invalid or missing category_id');  break; }
        if ($bracket_type === '') { badRequest('Invalid or missing bracket_type'); break; }

        $conn = getConnection();

        // Returns every match of that bracket_type for this category,
        // with both team slots per match.
        $stmt = $conn->prepare("
            SELECT
                m.match_id,
                m.bracket_type,
                TIME_FORMAT(s.schedule_start, '%H:%i') AS match_time,
                ts.team_id,
                t.team_name,
                ts.arena_number,
                ts.referee_id
            FROM tbl_match m
            JOIN tbl_schedule     s  ON s.schedule_id = m.schedule_id
            JOIN tbl_teamschedule ts ON ts.match_id   = m.match_id
            JOIN tbl_team         t  ON t.team_id     = ts.team_id
            WHERE t.category_id  = ?
              AND m.bracket_type = ?
            ORDER BY s.schedule_start ASC, m.match_id ASC, ts.teamschedule_id ASC
        ");

        if (!$stmt) {
            http_response_code(500);
            echo json_encode(['error' => 'Prepare failed: ' . $conn->error]);
            $conn->close();
            break;
        }

        $stmt->bind_param("is", $category_id, $bracket_type);
        $stmt->execute();
        $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        // Pivot: 2 rows per match_id → one entry with team1 + team2
        $matches = [];
        foreach ($rows as $row) {
            $mid = (int)$row['match_id'];
            if (!isset($matches[$mid])) {
                $matches[$mid] = [
                    'match_id'     => $mid,
                    'bracket_type' => $row['bracket_type'],
                    'match_time'   => $row['match_time'],
                    'arena_number' => (int)$row['arena_number'],
                    'referee_id'   => (int)$row['referee_id'],
                    'team1_id'     => null,
                    'team1_name'   => null,
                    'team2_id'     => null,
                    'team2_name'   => null,
                ];
            }
            if ($matches[$mid]['team1_id'] === null) {
                $matches[$mid]['team1_id']   = (int)$row['team_id'];
                $matches[$mid]['team1_name'] = $row['team_name'];
            } else {
                $matches[$mid]['team2_id']   = (int)$row['team_id'];
                $matches[$mid]['team2_name'] = $row['team_name'];
            }
        }

        echo json_encode(array_values($matches));
        $conn->close();
        break;

    // ── CHAMPIONSHIP SUBMIT SCORE ─────────────────────────────────────
    // POST scoring.php?action=championship_submit_score
    //
    // Saves a score for a knockout match using the REAL match_id from
    // tbl_match (as generated by the admin app). round_id is derived
    // from bracket_type in tbl_match — no hardcoded ID ranges needed.
    //
    // Body (JSON):
    // {
    //   "match_id": 47,
    //   "team_id": 12,
    //   "referee_id": 1,
    //   "score_independentscore": 3,
    //   "score_violation": 0,
    //   "score_totalscore": 3,
    //   "score_totalduration": "02:35",
    //   "score_isapproved": 0
    // }
    case 'championship_submit_score':
        if ($method !== 'POST') { methodNotAllowed(); break; }

        $body = file_get_contents('php://input');
        $data = json_decode($body, true);
        if (!$data) { badRequest('Invalid or empty JSON body'); break; }

        $required = [
            'match_id', 'team_id', 'referee_id',
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

        $conn = getConnection();

        // Derive round_id from bracket_type in tbl_match — no hardcoded ranges
        $btStmt = $conn->prepare(
            "SELECT bracket_type FROM tbl_match WHERE match_id = ? LIMIT 1"
        );
        $btStmt->bind_param("i", $match_id);
        $btStmt->execute();
        $btRow        = $btStmt->get_result()->fetch_assoc();
        $btStmt->close();
        $bracketType  = $btRow['bracket_type'] ?? '';

        // Map bracket_type → round_id
        // group         → 1  (handled by submit_score, but included for safety)
        // elimination / round-of-32 / round-of-16 / round-of-8 → 2
        // quarter-finals → 3
        // semi-finals    → 4
        // third-place / final → 5
        switch ($bracketType) {
            case 'group':
                $round_id = 1; break;
            case 'elimination':
            case 'round-of-32':
            case 'round-of-16':
            case 'round-of-8':
                $round_id = 2; break;
            case 'quarter-finals':
                $round_id = 3; break;
            case 'semi-finals':
                $round_id = 4; break;
            case 'third-place':
            case 'final':
                $round_id = 5; break;
            default:
                // Fallback: use client-supplied round_id if bracket_type unknown
                $round_id = isset($data['round_id']) ? intval($data['round_id']) : 1;
        }

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
            ON DUPLICATE KEY UPDATE
                score_independentscore = VALUES(score_independentscore),
                score_violation        = VALUES(score_violation),
                score_totalscore       = VALUES(score_totalscore),
                score_totalduration    = VALUES(score_totalduration),
                score_isapproved       = VALUES(score_isapproved)
        ");

        if (!$stmt) {
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

        if ($ok) {
            http_response_code(201);
            echo json_encode([
                'success'      => true,
                'score_id'     => $conn->insert_id,
                'round_id'     => $round_id,
                'bracket_type' => $bracketType,
                'message'      => 'Championship score submitted successfully'
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