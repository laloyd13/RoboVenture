// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'feedback_utils.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────
class MatchInfo {
  final int matchId;
  final int scheduleId;
  final String scheduleStart;
  final String scheduleEnd;

  MatchInfo({
    required this.matchId,
    required this.scheduleId,
    required this.scheduleStart,
    required this.scheduleEnd,
  });

  factory MatchInfo.fromJson(Map<String, dynamic> j) => MatchInfo(
          matchId:       int.tryParse(j['match_id'].toString()) ?? 0,
          scheduleId:    int.tryParse(j['schedule_id'].toString()) ?? 0,
          scheduleStart: j['schedule_start'] ?? '',
          scheduleEnd:   j['schedule_end'] ?? '',
      );
}

  class RefereeInfo {
    final int refereeId;
    final String refereeName;

    RefereeInfo({required this.refereeId, required this.refereeName});

    factory RefereeInfo.fromJson(Map<String, dynamic> j) => RefereeInfo(
      refereeId:   int.tryParse(j['referee_id'].toString()) ?? 0,
      refereeName: j['referee_name'] ?? '',
    );
  }

class TeamInfo {
  final int teamId;
  final String teamName;
  final int categoryId;

  TeamInfo({required this.teamId, required this.teamName, required this.categoryId});

  factory TeamInfo.fromJson(Map<String, dynamic> j) => TeamInfo(
    teamId:     int.tryParse(j['team_id'].toString()) ?? 0,
    teamName:   j['team_name'] ?? '',
    categoryId: int.tryParse(j['category_id'].toString()) ?? 0,
  );
}

class CategoryInfo {
  final int categoryId;
  final String categoryType;

  CategoryInfo({required this.categoryId, required this.categoryType});

  factory CategoryInfo.fromJson(Map<String, dynamic> j) => CategoryInfo(
    categoryId:   int.tryParse(j['category_id'].toString()) ?? 0,
    categoryType: j['category_type'] ?? '',
  );
}

class RoundInfo {
  final int roundId;
  final String roundType;

  RoundInfo({required this.roundId, required this.roundType});

  factory RoundInfo.fromJson(Map<String, dynamic> j) => RoundInfo(
    roundId:   int.tryParse(j['round_id'].toString()) ?? 0,
    roundType: j['round_type'] ?? '',
  );
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class ScoringApiService {

  static Future<http.Response> _get(String action, [Map<String, String>? params]) async {
    var queryParams = 'action=$action';
    if (params != null) {
      params.forEach((k, v) => queryParams += '&$k=$v');
    }
    final url = Uri.parse('${ApiConfig.scoring}?$queryParams');
    debugPrint('[API] GET $url');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    debugPrint('[API] ${response.statusCode} ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    return response;
  }

  // GET match joined with schedule
  static Future<MatchInfo?> fetchMatch(int matchId) async {
    final response = await _get('get_match', {'match_id': '$matchId'});
    if (response.statusCode == 200) {
      return MatchInfo.fromJson(json.decode(response.body));
    }
    throw Exception('get_match failed [${response.statusCode}]: ${response.body}');
  }

  // GET referee by ID
  static Future<RefereeInfo?> fetchReferee(int refereeId) async {
    final response = await _get('get_referee', {'referee_id': '$refereeId'});
    if (response.statusCode == 200) {
      return RefereeInfo.fromJson(json.decode(response.body));
    }
    throw Exception('get_referee failed [${response.statusCode}]: ${response.body}');
  }

  // GET team by ID
  static Future<TeamInfo?> fetchTeam(int teamId) async {
    final response = await _get('get_team', {'team_id': '$teamId'});
    if (response.statusCode == 200) {
      return TeamInfo.fromJson(json.decode(response.body));
    }
    throw Exception('get_team failed [${response.statusCode}]: ${response.body}');
  }

  // GET all active categories
  static Future<List<CategoryInfo>> fetchCategories() async {
    final response = await _get('get_categories');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => CategoryInfo.fromJson(e)).toList();
    }
    throw Exception('get_categories failed [${response.statusCode}]: ${response.body}');
  }

  // GET all rounds
  static Future<List<RoundInfo>> fetchRounds() async {
    final response = await _get('get_rounds');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => RoundInfo.fromJson(e)).toList();
    }
    throw Exception('get_rounds failed [${response.statusCode}]: ${response.body}');
  }

  // GET check whether a score already exists for this match + team
  static Future<bool> scoreExists(int matchId, int teamId) async {
    final response = await _get('check_score', {
      'match_id': '$matchId',
      'team_id':  '$teamId',
    });
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return (body['exists'] == true || body['exists'] == 1);
    }
    return false; // on error, allow submission to proceed
  }

  // POST submit score
  static Future<bool> submitScore({
    required int matchId,
    required int roundId,
    required int teamId,
    required int refereeId,
    required int independentScore,
    required int violation,
    required int totalScore,
    required String totalDuration,
  }) async {
    final url = Uri.parse('${ApiConfig.scoring}?action=submit_score');
    debugPrint('[API] POST $url');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'match_id': matchId,
        'round_id': roundId,
        'team_id': teamId,
        'referee_id': refereeId,
        'score_independentscore': independentScore,
        'score_violation': violation,
        'score_totalscore': totalScore,
        'score_totalduration': totalDuration,
        'score_isapproved': 0,
      }),
    ).timeout(const Duration(seconds: 10));
    debugPrint('[API] submit_score ${response.statusCode}: ${response.body}');
    return response.statusCode == 200 || response.statusCode == 201;
  }
}

// ─────────────────────────────────────────────
// SIGNATURE PAD
// ─────────────────────────────────────────────
class SignaturePad extends StatefulWidget {
  final SaveDelegate delegate;
  final String label;

  const SignaturePad({super.key, required this.delegate, required this.label});

  @override
  SignaturePadState createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final GlobalKey _paintKey = GlobalKey();

  void _handlePanUpdate(DragUpdateDetails details) {
    final RenderBox renderBox =
        _paintKey.currentContext?.findRenderObject() as RenderBox;
    final Offset localPosition =
        renderBox.globalToLocal(details.globalPosition);

    if (localPosition.dx >= 0 &&
        localPosition.dx <= renderBox.size.width &&
        localPosition.dy >= 0 &&
        localPosition.dy <= renderBox.size.height) {
      setState(() => widget.delegate.addPoint(localPosition));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
              onPressed: () =>
                  setState(() => widget.delegate.clear()),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onPanUpdate: _handlePanUpdate,
            onPanEnd: (details) => widget.delegate.addPoint(null),
            child: Container(
              key: _paintKey,
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: SignaturePainter(
                      points: List.from(widget.delegate.points)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SignaturePainter extends CustomPainter {
  SignaturePainter({required this.points});
  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) =>
      oldDelegate.points != points;
}

class SaveDelegate {
  List<Offset?> points = <Offset?>[];
  void addPoint(Offset? point) => points.add(point);
  void clear() => points.clear();
}

// ─────────────────────────────────────────────
// MATCH STATE PERSISTENCE
// Saves mission counters + timer to SharedPreferences on every change.
// Key prefix: "mbot2_state_<matchId>_<field>"
// Saved state expires after 5 minutes of inactivity — if the user doesn't
// return within that window, the stale state is discarded automatically.
// ─────────────────────────────────────────────
class _Mbot2StatePersistence {
  static const int _maxAgeMinutes = 5;
  static String _k(int matchId, String field) => 'mbot2_state_${matchId}_$field';

  static Future<void> save({
    required int matchId,
    required int m01Qty,
    required int m02Qty,
    required int m03Qty,
    required int m04Qty,
    required int m05Qty,
    required int violations,
    required int remainingSeconds,
    required bool hasStarted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(matchId, 'm01'),       m01Qty);
    await prefs.setInt(_k(matchId, 'm02'),       m02Qty);
    await prefs.setInt(_k(matchId, 'm03'),       m03Qty);
    await prefs.setInt(_k(matchId, 'm04'),       m04Qty);
    await prefs.setInt(_k(matchId, 'm05'),       m05Qty);
    await prefs.setInt(_k(matchId, 'viol'),      violations);
    await prefs.setInt(_k(matchId, 'timer'),     remainingSeconds);
    await prefs.setBool(_k(matchId, 'started'),  hasStarted);
    // Stamp the wall-clock time so we can expire stale saves on next load.
    await prefs.setInt(_k(matchId, 'savedAt'),
        DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<String, dynamic>?> load(int matchId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_k(matchId, 'timer'))) return null;

    // ── Expiry check ──────────────────────────────────────────────────
    // Discard the saved state if it is older than _maxAgeMinutes minutes.
    // This handles the case where the user left the screen for a long time
    // and the in-memory timer has long since lapsed.
    final savedAt = prefs.getInt(_k(matchId, 'savedAt'));
    if (savedAt != null) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
      if (age.inMinutes >= _maxAgeMinutes) {
        debugPrint('[Mbot2Persistence] Saved state expired (${age.inMinutes}m old). Discarding.');
        await clear(matchId);
        return null;
      }
    }

    return {
      'm01':     prefs.getInt(_k(matchId, 'm01'))      ?? 0,
      'm02':     prefs.getInt(_k(matchId, 'm02'))      ?? 0,
      'm03':     prefs.getInt(_k(matchId, 'm03'))      ?? 0,
      'm04':     prefs.getInt(_k(matchId, 'm04'))      ?? 0,
      'm05':     prefs.getInt(_k(matchId, 'm05'))      ?? 0,
      'viol':    prefs.getInt(_k(matchId, 'viol'))     ?? 0,
      'timer':   prefs.getInt(_k(matchId, 'timer'))    ?? 240,
      'started': prefs.getBool(_k(matchId, 'started')) ?? false,
    };
  }

  static Future<void> clear(int matchId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final f in ['m01','m02','m03','m04','m05','viol','timer','started','savedAt']) {
      await prefs.remove(_k(matchId, f));
    }
  }
}

// ─────────────────────────────────────────────
// COLOR PALETTE
// ─────────────────────────────────────────────
const Color primaryPurple = Color(0xFF7D58B3);
const Color badgePurple = Color(0xFFC8BFE1);
const Color accentYellow = Color(0xFFF9D949);
const Color missionBlue = Color(0xFF8BA3C7);
const Color missionGreen = Color(0xFF76A379);
const Color missionAmber = Color(0xFFC7A38B);
const Color missionPurple = Color(0xFF8789C0);
const Color missionLavender = Color(0xFF9B8CB8);
const Color penaltyRed = Color(0xFFB35D65);
const Color bgGrey = Color(0xFFF0F0F0);
const Color inputGrey = Color(0xFFE8E8E8);
const Color saveGreen = Color(0xFF5E975E);
const Color confirmPurple = Color(0xFF3B1F6E);
const Color pauseRed = Color(0xFFB35D65);
const Color startGreen = Color(0xFF5E975E);
const Color resetPurple = Color(0xFF79569A);

// ─────────────────────────────────────────────
// SCORING PAGE
// ─────────────────────────────────────────────
class Mbot2ScoringPage extends StatefulWidget {

  final int matchId;
  final int teamId;
  final int refereeId;

  const Mbot2ScoringPage({
    super.key,
    required this.matchId,
    required this.teamId,
    required this.refereeId,
  });

  @override
  State<Mbot2ScoringPage> createState() => _Mbot2ScoringPageState();
}

class _Mbot2ScoringPageState extends State<Mbot2ScoringPage>
    with WidgetsBindingObserver {
  // ── Signature delegates ──────────────────────
  final SaveDelegate _captainDelegate = SaveDelegate();
  final SaveDelegate _refereeDelegate = SaveDelegate();
  final GlobalKey _globalKey = GlobalKey();

  // ── Submission guard ─────────────────────────
  bool _isSubmitting = false;

  // ── Mission counters ─────────────────────────
  int m01Qty = 0, m02Qty = 0, m03Qty = 0, m04Qty = 0, m05Qty = 0,
      violations = 0;
  final int m01Points = 30, m02Points = 30, m03Points = 30, m04Points = 30,
      m05Points = 30;

  int get independentScore =>
      (m01Qty * m01Points) +
      (m02Qty * m02Points) +
      (m03Qty * m03Points) +
      (m04Qty * m04Points) +
      (m05Qty * m05Points);
  int get violationPenalty => violations * 10;
  int get totalScore => independentScore - violationPenalty;

  // ── Timer state ──────────────────────────────
  bool _timerRunning = false;
  bool _hasStarted = false; // true once Start is pressed for the first time
  int _remainingSeconds = 240; // fixed 4:00 minutes
  final int _totalSeconds = 240;
  Timer? _countdownTimer;
  bool _wasBackgrounded = false; // true only when timer was stopped due to AppLifecycle.paused
  DateTime? _backgroundedAt; // tracks when the app was backgrounded

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_timerRunning) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds == 0) {
            _timerRunning = false;
            _countdownTimer?.cancel();
            FeedbackUtils.timesUp(); // vibration burst + alert sound
          }
        }
      });
      _saveMatchState();
    });
  }

  String get _timerDisplay {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Fetched data ─────────────────────────────
  bool _loading = true;
  String? _errorMsg;

  MatchInfo? _match;
  RefereeInfo? _referee;
  TeamInfo? _team;

  List<CategoryInfo> _categories = [];
  CategoryInfo? _selectedCategory;

  List<RoundInfo> _rounds = [];
  RoundInfo? _selectedRound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initStateAndData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` fires for notification panel, recent-apps switcher, and
    // incoming calls — the user hasn't left the app, so the timer must keep
    // running through those transient states. Do NOT stop the timer here.
    //
    // `paused` fires only when the app is truly backgrounded (home button,
    // switched to another app). Stop the ticker and record time here.
    //
    // `resumed` fires when returning from EITHER inactive OR paused.
    // Only show the away-warning if we actually went to background (_wasBackgrounded).
    if (state == AppLifecycleState.paused) {
      if (_timerRunning) {
        setState(() => _timerRunning = false);
        _countdownTimer?.cancel();
        _saveMatchState();
        _wasBackgrounded = true;
      }
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        final bg = _backgroundedAt;
        _backgroundedAt = null;
        if (bg != null) {
          final away = DateTime.now().difference(bg);
          if (away.inSeconds >= 60 && _hasStarted && mounted) {
            _showAwayWarningDialog();
          }
        }
      }
      // If _wasBackgrounded is false we came back from `inactive`
      // (notification panel / recent-apps peek) — nothing to do.
    }
  }
  void _showAwayWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: primaryPurple,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orangeAccent, width: 1.5),
              ),
              child: const Icon(Icons.timer_off, color: Colors.orangeAccent, size: 26),
            ),
            const SizedBox(height: 14),
            const Text(
              "YOU'VE BEEN AWAY FOR A WHILE",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "The match timer was paused. What would you like to do with the current scores?",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('KEEP CURRENT SCORES',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  m01Qty = 0; m02Qty = 0; m03Qty = 0;
                  m04Qty = 0; m05Qty = 0; violations = 0;
                  _remainingSeconds = _totalSeconds;
                  _hasStarted = false;
                  _timerRunning = false;
                });
                _countdownTimer?.cancel();
                _saveMatchState();
              },
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30),
                ),
                child: const Text('RESET SCORES & TIMER',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Back-button interception ──────────────────────────────────────
  void _handleBackPress() {
    if (!_hasStarted) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _showBackWarningDialog();
  }

  void _showBackWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: primaryPurple,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orangeAccent, width: 1.5),
              ),
              child: const Icon(Icons.timer_off, color: Colors.orangeAccent, size: 26),
            ),
            const SizedBox(height: 14),
            const Text(
              'LEAVE THE MATCH?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The match is still in progress. The timer and will be reset. What would you like to do?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('STAY',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  m01Qty = 0; m02Qty = 0; m03Qty = 0;
                  m04Qty = 0; m05Qty = 0; violations = 0;
                  _remainingSeconds = _totalSeconds;
                  _hasStarted = false;
                  _timerRunning = false;
                });
                _countdownTimer?.cancel();
                _saveMatchState();
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30),
                ),
                child: const Text('BACK',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Persist current state to disk. Called on every scoring or timer change.
  Future<void> _saveMatchState() => _Mbot2StatePersistence.save(
    matchId:          widget.matchId,
    m01Qty:           m01Qty,
    m02Qty:           m02Qty,
    m03Qty:           m03Qty,
    m04Qty:           m04Qty,
    m05Qty:           m05Qty,
    violations:       violations,
    remainingSeconds: _remainingSeconds,
    hasStarted:       _hasStarted,
  );

  /// Restore previously saved state (if any), then fetch match data.
  Future<void> _initStateAndData() async {
    final saved = await _Mbot2StatePersistence.load(widget.matchId);
    if (saved != null && mounted) {
      setState(() {
        m01Qty            = saved['m01'] as int;
        m02Qty            = saved['m02'] as int;
        m03Qty            = saved['m03'] as int;
        m04Qty            = saved['m04'] as int;
        m05Qty            = saved['m05'] as int;
        violations        = saved['viol'] as int;
        _remainingSeconds = saved['timer'] as int;
        _hasStarted       = saved['started'] as bool;
      });
    }
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() { _loading = true; _errorMsg = null; });

    try {
      final match      = await ScoringApiService.fetchMatch(widget.matchId);
      final referee    = await ScoringApiService.fetchReferee(widget.refereeId);
      final team       = await ScoringApiService.fetchTeam(widget.teamId);
      final categories = await ScoringApiService.fetchCategories();
      final rounds     = await ScoringApiService.fetchRounds();

      CategoryInfo? selCategory;
      if (team != null && categories.isNotEmpty) {
        selCategory = categories.firstWhere(
          (c) => c.categoryId == team.categoryId,
          orElse: () => categories.first,
        );
      }

      setState(() {
        _match             = match;
        _referee           = referee;
        _team              = team;
        _categories        = categories;
        _selectedCategory  = selCategory;
        _rounds            = rounds;
        _selectedRound     = rounds.isNotEmpty ? rounds.first : null;
        _loading           = false;
      });
      // Do NOT reset the timer here — restored state takes precedence
    } catch (e) {
      debugPrint('[ScoringPage] _fetchAllData error: $e');
      setState(() {
        _errorMsg = e.toString();
        _loading  = false;
      });
    }
  }

  // ─────────────────────────────────────────────
  // SAVE SCREENSHOT TO GALLERY
  // ─────────────────────────────────────────────
  Future<void> _saveToGallery(BuildContext localContext) async {
    try {
      RenderRepaintBoundary? boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/match_${widget.teamId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await File(filePath).create();
      await file.writeAsBytes(pngBytes);

      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(file.path);

      if (!localContext.mounted) return;
      ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(
        content: Text("Match summary saved as JPG!"),
        backgroundColor: saveGreen,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      debugPrint('Error: $e');
      if (!localContext.mounted) return;
      ScaffoldMessenger.of(localContext).showSnackBar(
          const SnackBar(content: Text("Failed to save image.")));
    }
  }

  // ─────────────────────────────────────────────
  // SUBMIT SCORE TO DB
  // ─────────────────────────────────────────────

  void _showValidationDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: primaryPurple,
              borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orangeAccent, width: 1.5),
              ),
              child: Icon(icon, color: Colors.orangeAccent, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.5)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.orangeAccent,
                    borderRadius: BorderRadius.circular(12)),
                child: const Text('OK',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _submitScore(BuildContext localContext) async {
    // ── Duplicate-submission guard ────────────────────────────────────
    if (_isSubmitting) return;

    // Capture navigator before any async gap so context is guaranteed valid.
    final rootNav = Navigator.of(context, rootNavigator: true);

    // ── Validate signatures ───────────────────────────────────────────
    final captainSigned = _captainDelegate.points.any((p) => p != null);
    final refereeSigned = _refereeDelegate.points.any((p) => p != null);
    if (!captainSigned || !refereeSigned) {
      _showValidationDialog(
        icon: Icons.draw_outlined,
        iconColor: penaltyRed,
        title: 'SIGNATURES REQUIRED',
        message: !captainSigned && !refereeSigned
            ? 'Both the captain and referee signatures are required before submitting.'
            : !captainSigned
                ? 'The captain signature is missing. Please have the captain sign before submitting.'
                : 'The referee signature is missing. Please sign before submitting.',
      );
      return;
    }

    if (_selectedRound == null) {
      ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(
          content: Text('Please select a Competition Info (round).')));
      return;
    }

    // ── Zero-score confirmation ───────────────────────────────────────
    if (totalScore <= 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: primaryPurple, borderRadius: BorderRadius.circular(20)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orangeAccent, width: 1.5),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orangeAccent, size: 26),
              ),
              const SizedBox(height: 14),
              const Text('ZERO TOTAL SCORE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Text(
                'The total score is 0. This may be a mistake. Are you sure you want to submit?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                    height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white30)),
                      child: const Text('CANCEL',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text('SUBMIT ANYWAY',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // ── Duplicate-submission check (server-side) ──────────────────────
    final alreadyExists = await ScoringApiService.scoreExists(
        widget.matchId, widget.teamId);
    if (alreadyExists) {
      if (!mounted) return;
      rootNav.pop(); // dismiss loading dialog
      setState(() => _isSubmitting = false);
      _showValidationDialog(
        icon: Icons.block,
        iconColor: penaltyRed,
        title: 'ALREADY SUBMITTED',
        message:
            'A score for this match and team has already been recorded. Duplicate submissions are not allowed.',
      );
      return;
    }

    final success = await ScoringApiService.submitScore(
      matchId: widget.matchId,
      roundId: _selectedRound!.roundId,
      teamId: widget.teamId,
      refereeId: widget.refereeId,
      independentScore: independentScore,
      violation: violations,
      totalScore: totalScore,
      totalDuration: () {
        final elapsed = _totalSeconds - _remainingSeconds;
        final m = (elapsed ~/ 60).toString().padLeft(2, '0');
        final s = (elapsed % 60).toString().padLeft(2, '0');
        return '$m:$s';
      }(),
    );

    if (!mounted) return;
    rootNav.pop(); // dismiss loading dialog

    if (success) {
      // Clear saved state — match is done, next open should start fresh
      await _Mbot2StatePersistence.clear(widget.matchId);
      if (!mounted) return;
      rootNav.pop(); // dismiss the summary bottom sheet
      if (!mounted) return;
      rootNav.pop(true); // pop the scoring page → qualification screen shows snackbar
    } else {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submission failed. Please try again.'),
        backgroundColor: penaltyRed,
      ));
    }
  }

  // ─────────────────────────────────────────────
  // SIGNATURE + SUBMIT POPUP
  // ─────────────────────────────────────────────
  void _showSignaturePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: IntrinsicHeight(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: const BoxDecoration(
                  color: primaryPurple,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 48),
                        const Text(
                          "SINGLE MATCH SUMMARY",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, thickness: 1, height: 1),
                    const SizedBox(height: 12),
                    RepaintBoundary(
                      key: _globalKey,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        color: primaryPurple,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _team?.teamName ?? '—',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'ID: ${widget.teamId}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildSummaryLabel(
                                    '${_match?.matchId ?? '—'}', 'MATCH'),
                                _buildSummaryLabel(
                                    '$totalScore', 'TOTAL SCORE'),
                                _buildSummaryLabel(() {
                                  final elapsed = _totalSeconds - _remainingSeconds;
                                  final m = (elapsed ~/ 60).toString().padLeft(2, '0');
                                  final s = (elapsed % 60).toString().padLeft(2, '0');
                                  return '$m:$s';
                                }(), 'TIME'),
                              ],
                            ),
                            const SizedBox(height: 15),
                            SignaturePad(
                                delegate: _captainDelegate,
                                label: "CAPTAIN SIGNATURE"),
                            const SizedBox(height: 10),
                            SignaturePad(
                                delegate: _refereeDelegate,
                                label: "REFEREE SIGNATURE"),
                            const SizedBox(height: 15),
                            const Text(
                              "I confirm that I have examined the scores and am willing to submit them without any alterations.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (localCtx) => Row(
                        children: [
                          Expanded(
                            child: _buildActionBtn(
                              "SAVE",
                              saveGreen,
                              fontSize: 18,
                              onTap: () => _saveToGallery(localCtx),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildActionBtn(
                              "SUBMIT",
                              confirmPurple,
                              fontSize: 18,
                              onTap: () => _submitScore(localCtx),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: bgGrey,
        body: Center(child: CircularProgressIndicator(color: primaryPurple)),
      );
    }

    if (_errorMsg != null) {
      return Scaffold(
        backgroundColor: bgGrey,
        appBar: AppBar(
          backgroundColor: primaryPurple,
          automaticallyImplyLeading: false,
          title: GestureDetector(
            onTap: _handleBackPress,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text('BACK', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: penaltyRed, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Failed to Load Data',
                style: TextStyle(color: penaltyRed, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Scrollable error box so long messages are fully readable
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: penaltyRed.withOpacity(0.4)),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    _errorMsg!,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check the error above, then verify:\n'
                '• IP address is correct in scoring.dart\n'
                '• DB credentials are correct in scoring.php\n'
                '• Device and server are on the same network',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: primaryPurple),
                onPressed: _fetchAllData,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackPress();
      },
      child: Scaffold(
      backgroundColor: bgGrey,
      body: CustomScrollView(
        slivers: [
          // ── APP BAR ───────────────────────────
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: primaryPurple,
            automaticallyImplyLeading: false,
            toolbarHeight: 70,
            title: GestureDetector(
              onTap: _handleBackPress,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Center(
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: primaryPurple, size: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  const Text("BACK",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            actions: [
              // Live timer display
              Container(
                margin: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    border: Border.all(
                        color: _remainingSeconds <= 30
                            ? Colors.redAccent
                            : Colors.white,
                        width: 1.5),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        color: _remainingSeconds <= 30
                            ? Colors.redAccent
                            : Colors.white,
                        size: 20),
                    const SizedBox(width: 5),
                    Text(_timerDisplay,
                        style: TextStyle(
                            color: _remainingSeconds <= 30
                                ? Colors.redAccent
                                : Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: CustomPaint(
              painter: GeometricBackgroundPainter(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // ── HEADER ROW ─────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            const Text("MATCH",
                                style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Container(
                              width: 50,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: badgePurple,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.black,
                                      width: 1.5)),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_match?.matchId ?? '—'}',
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              '${_selectedCategory?.categoryType.toUpperCase() ?? 'ROBOVENTURE'} FORM',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryPurple),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),
                    const Divider(
                        color: Colors.black26, thickness: 1, height: 1),
                    const SizedBox(height: 10),

                    // ── MATCH INFO CARD ────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 5))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("MATCH INFORMATION",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                          const SizedBox(height: 20),

                          // Competition Time (from schedule)
                          _buildScoringField(
                            "COMPETITION TIME",
                            _match != null
                                ? '${_match!.scheduleStart} – ${_match!.scheduleEnd}'
                                : '—',
                          ),

                          // Referee Name (from DB)
                          _buildScoringField(
                            "REFEREE NAME",
                            _referee?.refereeName ?? '—',
                          ),

                          // Team Name (from DB)
                          _buildScoringField(
                            "TEAM NAME",
                            _team?.teamName ?? '—',
                          ),

                          Row(
                            children: [
                              // Team ID (from DB)
                              Expanded(
                                child: _buildScoringField(
                                  "TEAM ID",
                                  '${widget.teamId}',
                                ),
                              ),
                              const SizedBox(width: 15),
                              // Category Dropdown (from tbl_category)
                              Expanded(
                                child: _buildCategoryDropdown(),
                              ),
                            ],
                          ),

                          // Competition Info / Round Dropdown (from tbl_round)
                          _buildRoundDropdown(),

                          const SizedBox(height: 10),
                          const Text("AUTOMATIC MISSION",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                          const Divider(height: 30),

                          // ── MISSIONS ────────────────
                          _buildMissionCard(
                              "M01: Smart Triage Sorting (Cylinder)",
                              m01Qty,
                              m01Points,
                              1,
                              missionBlue,
                              (val) =>
                                  setState(() => m01Qty = val)),
                          const SizedBox(height: 20),
                          _buildMissionCard(
                              "M02: Smart Triage Sorting (Cube)",
                              m02Qty,
                              m02Points,
                              1,
                              missionGreen.withOpacity(0.7),
                              (val) =>
                                  setState(() => m02Qty = val)),
                          const SizedBox(height: 20),
                          _buildMissionCard(
                              "M03: LifeSaver Alert",
                              m03Qty,
                              m03Points,
                              4,
                              missionAmber.withOpacity(0.7),
                              (val) =>
                                  setState(() => m03Qty = val)),
                          const SizedBox(height: 20),
                          _buildMissionCard(
                              "M04: Voice-Assisted Medical Routing",
                              m04Qty,
                              m04Points,
                              4,
                              missionPurple.withOpacity(0.7),
                              (val) =>
                                  setState(() => m04Qty = val)),
                          const SizedBox(height: 30),
                          _buildMissionCard(
                              "M05: Companion Assistance Transfer",
                              m05Qty,
                              m05Points,
                              4,
                              missionLavender.withOpacity(0.7),
                              (val) =>
                                  setState(() => m05Qty = val)),
                          const SizedBox(height: 30),

                          // ── PENALTY ──────────────────
                          const Text("PENALTY",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                          const Divider(height: 30),
                          _buildMissionCard(
                              "VIOLATION",
                              violations,
                              10,
                              99,
                              penaltyRed,
                              (val) =>
                                  setState(() => violations = val)),
                          const SizedBox(height: 30),

                          // ── SCORE SUMMARY ────────────
                          const Text("SINGLE MATCH SCORE",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                          const SizedBox(height: 20),
                          _buildScoreRow(
                              "Independent Score", "$independentScore"),
                          _buildScoreRow(
                              "Violation", "-$violationPenalty"),
                          _buildScoreRow(
                              "Total Score", "$totalScore"),
                          _buildScoreRow(
                              "Competition Time", () {
                            final elapsed = _totalSeconds - _remainingSeconds;
                            final m = (elapsed ~/ 60).toString().padLeft(2, '0');
                            final s = (elapsed % 60).toString().padLeft(2, '0');
                            return '$m:$s';
                          }()),
                          const SizedBox(height: 30),
                          _buildActionBtn(
                            "Confirm",
                            _hasStarted && !_timerRunning ? primaryPurple : Colors.grey.shade400,
                            fontSize: 18,
                            onTap: _hasStarted && !_timerRunning ? _showSignaturePopup : () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),

      // ── BOTTOM BUTTONS ───────────────────────
      bottomNavigationBar: Container(
        color: bgGrey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                _timerRunning ? "Pause" : "Start",
                _timerRunning
                    ? penaltyRed
                    : (_remainingSeconds == 0 ? Colors.grey.shade400 : startGreen),
                fontSize: 24,
                onTap: _remainingSeconds == 0 && !_timerRunning
                    ? () {}
                    : () {
                        setState(() {
                          _timerRunning = !_timerRunning;
                          if (_timerRunning) {
                            _hasStarted = true;
                            _startTimer();
                          } else {
                            _countdownTimer?.cancel();
                          }
                        });
                        _saveMatchState();
                      },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildActionBtn(
                "Reset",
                resetPurple,
                fontSize: 24,
                onTap: () {
                  setState(() {
                    _countdownTimer?.cancel();
                    _timerRunning = false;
                    _hasStarted = false;
                    _remainingSeconds = _totalSeconds;
                    m01Qty = 0;
                    m02Qty = 0;
                    m03Qty = 0;
                    m04Qty = 0;
                    m05Qty = 0;
                    violations = 0;
                  });
                  _Mbot2StatePersistence.clear(widget.matchId);
                },
              ),
            ),
          ],
        ),
      ),
    ), // Scaffold
    ); // PopScope
  }

  // ─────────────────────────────────────────────
  // DROPDOWN: CATEGORY (from tbl_category)
  // ─────────────────────────────────────────────
  Widget _buildCategoryDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: inputGrey, borderRadius: BorderRadius.circular(5)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CategoryInfo>(
                isExpanded: true,
                value: _selectedCategory,
                hint: const Text('Select Category',
                    style: TextStyle(fontSize: 12)),
                icon: const Icon(Icons.arrow_drop_down,
                    color: Colors.black54),
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87),
                onChanged: (val) =>
                    setState(() => _selectedCategory = val),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.categoryType,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ),
          ),
          const Positioned(
            top: -12,
            left: 5,
            child: Text("CATEGORY",
                style: TextStyle(
                    color: primaryPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DROPDOWN: COMPETITION INFO / ROUND (from tbl_round)
  // ─────────────────────────────────────────────
  Widget _buildRoundDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: inputGrey, borderRadius: BorderRadius.circular(5)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<RoundInfo>(
                isExpanded: true,
                value: _selectedRound,
                hint: const Text('Select Competition Info',
                    style: TextStyle(fontSize: 12)),
                icon: const Icon(Icons.arrow_drop_down,
                    color: Colors.black54),
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87),
                onChanged: (val) =>
                    setState(() => _selectedRound = val),
                items: _rounds
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.roundType,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ),
          ),
          const Positioned(
            top: -12,
            left: 5,
            child: Text("COMPETITION INFO",
                style: TextStyle(
                    color: primaryPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HELPER WIDGETS
  // ─────────────────────────────────────────────
  Widget _buildSummaryLabel(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 24,
                fontStyle: FontStyle.italic)),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMissionCard(String title, int qty, int points, int maxQty, Color color,
      ValueChanged<int> onChanged) {
    final bool canScore = _hasStarted && _timerRunning;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCounterBtn(Icons.remove,
                  onTap: canScore
                      ? () { if (qty > 0) { onChanged(qty - 1); _saveMatchState(); } }
                      : null),
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 15),
                width: 70,
                height: 70,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Text("$qty",
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
              ),
              _buildCounterBtn(Icons.add,
                  onTap: canScore
                      ? () { if (qty < maxQty) { onChanged(qty + 1); _saveMatchState(); } }
                      : null),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildScoreLabel("$points", "Points / Each"),
              _buildScoreLabel("${qty * points}", "Total Score"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreLabel(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        Text(label,
            style:
                const TextStyle(color: Colors.white, fontSize: 9)),
      ],
    );
  }

  Widget _buildScoreRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: primaryPurple,
                  fontWeight: FontWeight.bold)),
          Text(value,
              style: const TextStyle(
                  color: primaryPurple,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildScoringField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            decoration: BoxDecoration(
                color: inputGrey,
                borderRadius: BorderRadius.circular(5)),
            padding:
                const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontSize: 14)),
          ),
          Positioned(
              top: -12,
              left: 5,
              child: Text(label,
                  style: const TextStyle(
                      color: primaryPurple,
                      fontWeight: FontWeight.bold,
                      fontSize: 10))),
        ],
      ),
    );
  }

  Widget _buildCounterBtn(IconData icon, {VoidCallback? onTap}) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap == null ? null : () {
        FeedbackUtils.counterTap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: enabled ? accentYellow : Colors.grey.shade400,
            shape: BoxShape.circle),
        child: Icon(icon, color: enabled ? Colors.black : Colors.white54, size: 24),
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color,
      {double fontSize = 24, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 55,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(label,
            style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// GEOMETRIC BACKGROUND PAINTER
// ─────────────────────────────────────────────
class GeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final List<List<Offset>> polygons = [
      [
        const Offset(0, 0),
        Offset(size.width * 0.45, 0),
        Offset(size.width * 0.25, size.height * 0.15),
        Offset(0, size.height * 0.1)
      ],
      [
        Offset(0, size.height * 0.1),
        Offset(size.width * 0.25, size.height * 0.15),
        Offset(0, size.height * 0.35)
      ],
      [
        Offset(size.width * 0.45, 0),
        Offset(size.width, 0),
        Offset(size.width * 0.75, size.height * 0.18)
      ],
      [
        Offset(size.width * 0.45, 0),
        Offset(size.width * 0.75, size.height * 0.18),
        Offset(size.width * 0.25, size.height * 0.15)
      ],
      [
        Offset(0, size.height * 0.35),
        Offset(size.width * 0.25, size.height * 0.15),
        Offset(size.width * 0.6, size.height * 0.4),
        Offset(size.width * 0.1, size.height * 0.55)
      ],
      [
        Offset(size.width * 0.75, size.height * 0.18),
        Offset(size.width, size.height * 0.4),
        Offset(size.width * 0.6, size.height * 0.4)
      ],
      [
        Offset(size.width, size.height * 0.4),
        Offset(size.width, size.height * 0.8),
        Offset(size.width * 0.65, size.height * 0.6)
      ],
      [
        Offset(0, size.height * 0.55),
        Offset(size.width * 0.35, size.height * 0.75),
        Offset(0, size.height * 0.9)
      ],
    ];

    for (int i = 0; i < polygons.length; i++) {
      paint.color =
          const Color(0xFFD6D6E5).withOpacity(0.12 + (i % 3 * 0.08));
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}