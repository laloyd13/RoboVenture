// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'feedback_utils.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────
class SoccerMatchInfo {
  final int matchId;
  final int scheduleId;
  final String scheduleStart;
  final String scheduleEnd;
  SoccerMatchInfo({required this.matchId, required this.scheduleId,
      required this.scheduleStart, required this.scheduleEnd});
  factory SoccerMatchInfo.fromJson(Map<String, dynamic> j) => SoccerMatchInfo(
        matchId:       int.tryParse(j['match_id'].toString()) ?? 0,
        scheduleId:    int.tryParse(j['schedule_id'].toString()) ?? 0,
        scheduleStart: j['schedule_start'] ?? '',
        scheduleEnd:   j['schedule_end'] ?? '',
      );
}

class SoccerRefereeInfo {
  final int refereeId;
  final String refereeName;
  SoccerRefereeInfo({required this.refereeId, required this.refereeName});
  factory SoccerRefereeInfo.fromJson(Map<String, dynamic> j) => SoccerRefereeInfo(
        refereeId:   int.tryParse(j['referee_id'].toString()) ?? 0,
        refereeName: j['referee_name'] ?? '',
      );
}

class SoccerTeamInfo {
  final int teamId;
  final String teamName;
  final int categoryId;
  SoccerTeamInfo({required this.teamId, required this.teamName, required this.categoryId});
  factory SoccerTeamInfo.fromJson(Map<String, dynamic> j) => SoccerTeamInfo(
        teamId:     int.tryParse(j['team_id'].toString()) ?? 0,
        teamName:   j['team_name'] ?? '',
        categoryId: int.tryParse(j['category_id'].toString()) ?? 0,
      );
}

class SoccerCategoryInfo {
  final int categoryId;
  final String categoryType;
  SoccerCategoryInfo({required this.categoryId, required this.categoryType});
  factory SoccerCategoryInfo.fromJson(Map<String, dynamic> j) => SoccerCategoryInfo(
        categoryId:   int.tryParse(j['category_id'].toString()) ?? 0,
        categoryType: j['category_type'] ?? '',
      );
}

class SoccerRoundInfo {
  final int roundId;
  final String roundType;
  SoccerRoundInfo({required this.roundId, required this.roundType});
  factory SoccerRoundInfo.fromJson(Map<String, dynamic> j) => SoccerRoundInfo(
        roundId:   int.tryParse(j['round_id'].toString()) ?? 0,
        roundType: j['round_type'] ?? '',
      );
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class SoccerScoringApiService {
  static Future<http.Response> _get(String action, [Map<String, String>? params]) async {
    var q = 'action=$action';
    if (params != null) params.forEach((k, v) => q += '&$k=$v');
    final url = Uri.parse('${ApiConfig.scoring}?$q');
    return http.get(url).timeout(const Duration(seconds: 10));
  }

  static Future<SoccerMatchInfo?> fetchMatch(int id) async {
    try {
      final r = await _get('get_match', {'match_id': '$id'});
      if (r.statusCode == 200) return SoccerMatchInfo.fromJson(json.decode(r.body));
    } catch (_) {}
    return null;
  }

  static Future<SoccerRefereeInfo?> fetchReferee(int id) async {
    try {
      final r = await _get('get_referee', {'referee_id': '$id'});
      if (r.statusCode == 200) return SoccerRefereeInfo.fromJson(json.decode(r.body));
    } catch (_) {}
    return null;
  }

  static Future<SoccerTeamInfo?> fetchTeam(int id) async {
    try {
      final r = await _get('get_team', {'team_id': '$id'});
      if (r.statusCode == 200) return SoccerTeamInfo.fromJson(json.decode(r.body));
    } catch (_) {}
    return null;
  }

  static Future<List<SoccerCategoryInfo>> fetchCategories() async {
    try {
      final r = await _get('get_categories');
      if (r.statusCode == 200) {
        return (json.decode(r.body) as List).map((e) => SoccerCategoryInfo.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<SoccerRoundInfo>> fetchRounds() async {
    try {
      final r = await _get('get_rounds');
      if (r.statusCode == 200) {
        return (json.decode(r.body) as List).map((e) => SoccerRoundInfo.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchMatchScores(int id) async {
    try {
      final r = await _get('get_match_scores', {'match_id': '$id'});
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        if (data is List) { return List<Map<String, dynamic>>.from(data); }
      }
    } catch (_) {}
    return [];
  }

  // GET check whether a score already exists for this match + team
  static Future<bool> scoreExists(int matchId, int teamId) async {
    try {
      final r = await _get('check_score', {
        'match_id': '$matchId',
        'team_id':  '$teamId',
      });
      if (r.statusCode == 200) {
        final body = json.decode(r.body);
        return (body['exists'] == true || body['exists'] == 1);
      }
    } catch (_) {}
    return false; // on error, allow submission to proceed
  }

  static Future<bool> submitScore({
    required int matchId, required int roundId, required int teamId,
    required int refereeId, required int teamAScore, required int teamBScore,
    required int teamAFouls, required int teamBFouls,
    required String totalDuration,
    bool isChampionship = false,
  }) async {
    // Championship matches use a separate action that bypasses FK checks
    // since their match IDs don't exist in tbl_match.
    final action = isChampionship ? 'championship_submit_score' : 'submit_score';
    final url = Uri.parse('${ApiConfig.scoring}?action=$action');

    // score_totalscore = this team's own score minus their violations.
    // For soccer there are no fouls tracked so this always equals teamAScore,
    // but the formula is kept generic for correctness.
    final int violations  = teamAFouls + teamBFouls;
    final int totalScore  = teamAScore - violations;

    final res = await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'match_id': matchId, 'round_id': roundId, 'team_id': teamId,
        'referee_id': refereeId,
        'score_independentscore': teamAScore,
        'score_violation':        violations,
        'score_totalscore':       totalScore,
        'score_totalduration':    totalDuration,
        'score_isapproved':       0,
      }),
    ).timeout(const Duration(seconds: 10));
    return res.statusCode == 200 || res.statusCode == 201;
  }
}

// ─────────────────────────────────────────────
// SIGNATURE PAD
// ─────────────────────────────────────────────
class SoccerSaveDelegate {
  List<Offset?> points = [];
  void addPoint(Offset? p) => points.add(p);
  void clear() => points.clear();
}

class SoccerSignaturePad extends StatefulWidget {
  final SoccerSaveDelegate delegate;
  final String label;
  const SoccerSignaturePad({super.key, required this.delegate, required this.label});
  @override
  SoccerSignaturePadState createState() => SoccerSignaturePadState();
}

class SoccerSignaturePadState extends State<SoccerSignaturePad> {
  final GlobalKey _key = GlobalKey();
  void _onPanUpdate(DragUpdateDetails d) {
    final rb = _key.currentContext?.findRenderObject() as RenderBox;
    final lp = rb.globalToLocal(d.globalPosition);
    if (lp.dx >= 0 && lp.dx <= rb.size.width && lp.dy >= 0 && lp.dy <= rb.size.height) {
      setState(() => widget.delegate.addPoint(lp));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(widget.label,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        GestureDetector(
            onTap: () => setState(() => widget.delegate.clear()),
            child: const Icon(Icons.clear, color: Colors.white60, size: 16)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => widget.delegate.addPoint(null),
          child: Container(key: _key, height: 100, width: double.infinity,
              color: Colors.white,
              child: CustomPaint(painter: _SigPainter(List.from(widget.delegate.points)))),
        ),
      ),
    ],
  );
}

class _SigPainter extends CustomPainter {
  final List<Offset?> points;
  _SigPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black..strokeCap = StrokeCap.round..strokeWidth = 3;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i+1] != null) { canvas.drawLine(points[i]!, points[i+1]!, p); }
    }
  }
  @override
  bool shouldRepaint(_SigPainter old) => old.points != points;
}

// ─────────────────────────────────────────────
// COLORS
// ─────────────────────────────────────────────
const Color _purple        = Color(0xFF7D58B3);
const Color _penaltyRed    = Color(0xFFB35D65);
const Color _bgGrey        = Color(0xFFF2F2F2);
const Color _saveGreen     = Color(0xFF5E975E);
const Color _confirmPurple = Color(0xFF3B1F6E);
const Color _startGreen    = Color(0xFF4CAF50);
const Color _pauseRed      = Color(0xFFE53935);
const Color _resetPurple   = Color(0xFF79569A);
const Color _swapGold    = Color(0xFFFFBF00);
const Color _teamBlue      = Color(0xFF3A7BD5);
const Color _teamGreen     = Color(0xFF2E8B57);

// ─────────────────────────────────────────────
// TEAM COLOR ASSIGNMENT
// Persisted to SharedPreferences so it survives app crashes/restarts.
// Key format: "soccer_color_<matchId>" → "blue" | "green"
// Value is what the HOME team got; away gets the other one.
// ─────────────────────────────────────────────
class _ColorAssignment {
  /// true  = home is Blue,  away is Green
  /// false = home is Green, away is Blue
  final bool homeIsBlue;

  const _ColorAssignment({required this.homeIsBlue});

  Color get homeColor => homeIsBlue ? _teamBlue  : _teamGreen;
  Color get awayColor => homeIsBlue ? _teamGreen : _teamBlue;
  String get homeLabel => homeIsBlue ? 'BLUE'  : 'GREEN';
  String get awayLabel => homeIsBlue ? 'GREEN' : 'BLUE';

  _ColorAssignment swapped() => _ColorAssignment(homeIsBlue: !homeIsBlue);

  // ── Persistence ───────────────────────────────────────────────────
  static String _key(int matchId) => 'soccer_color_$matchId';

  /// Load from prefs. Returns null if no assignment saved yet.
  static Future<_ColorAssignment?> load(int matchId) async {
    final prefs = await SharedPreferences.getInstance();
    final val   = prefs.getString(_key(matchId));
    if (val == null) return null;
    return _ColorAssignment(homeIsBlue: val == 'blue');
  }

  /// Randomly pick and immediately save.
  static Future<_ColorAssignment> createAndSave(int matchId) async {
    final homeIsBlue = Random().nextBool();
    final assignment = _ColorAssignment(homeIsBlue: homeIsBlue);
    await assignment.save(matchId);
    return assignment;
  }

  /// Save current assignment.
  Future<void> save(int matchId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(matchId), homeIsBlue ? 'blue' : 'green');
  }
}

// ─────────────────────────────────────────────
// MATCH STATE PERSISTENCE
// Saves scores + timer to SharedPreferences on every change.
// Key prefix: "soccer_state_<matchId>_<field>"
// Saved state expires after 5 minutes of inactivity — if the user doesn't
// return within that window, the stale state is discarded automatically.
// ─────────────────────────────────────────────
class _MatchStatePersistence {
  static const int _maxAgeMinutes = 5;
  static String _k(int matchId, String field) => 'soccer_state_${matchId}_$field';

  static Future<void> save({
    required int matchId,
    required int teamAScore,
    required int teamBScore,
    required int remainingSeconds,
    required bool hasStarted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(matchId, 'scoreA'),    teamAScore);
    await prefs.setInt(_k(matchId, 'scoreB'),    teamBScore);
    await prefs.setInt(_k(matchId, 'timer'),     remainingSeconds);
    await prefs.setBool(_k(matchId, 'started'),  hasStarted);
    // Stamp the wall-clock time so we can expire stale saves on next load.
    await prefs.setInt(_k(matchId, 'savedAt'),
        DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<String, dynamic>?> load(int matchId) async {
    final prefs = await SharedPreferences.getInstance();
    // If no saved state exists yet, return null
    if (!prefs.containsKey(_k(matchId, 'scoreA'))) return null;

    // ── Expiry check ──────────────────────────────────────────────────
    // Discard the saved state if it is older than _maxAgeMinutes minutes.
    // This handles the case where the user left the screen for a long time
    // and the in-memory timer has long since lapsed.
    final savedAt = prefs.getInt(_k(matchId, 'savedAt'));
    if (savedAt != null) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
      if (age.inMinutes >= _maxAgeMinutes) {
        debugPrint('[SoccerPersistence] Saved state expired (${age.inMinutes}m old). Discarding.');
        await clear(matchId);
        return null;
      }
    }

    return {
      'scoreA':   prefs.getInt(_k(matchId, 'scoreA'))   ?? 0,
      'scoreB':   prefs.getInt(_k(matchId, 'scoreB'))   ?? 0,
      'timer':    prefs.getInt(_k(matchId, 'timer'))    ?? 300,
      'started':  prefs.getBool(_k(matchId, 'started')) ?? false,
    };
  }

  static Future<void> clear(int matchId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_k(matchId, 'scoreA'));
    await prefs.remove(_k(matchId, 'scoreB'));
    await prefs.remove(_k(matchId, 'timer'));
    await prefs.remove(_k(matchId, 'started'));
    await prefs.remove(_k(matchId, 'savedAt'));
  }
}

// ─────────────────────────────────────────────
// SOCCER SCORING PAGE
// ─────────────────────────────────────────────
class SoccerScoringPage extends StatefulWidget {
  final int    matchId;
  final int    teamId;
  final int    awayTeamId;
  final int    refereeId;
  final String homeTeamName;
  final String awayTeamName;
  final bool   isChampionship;
  final int?   championshipRoundId;

  const SoccerScoringPage({
    super.key,
    required this.matchId,
    required this.teamId,
    this.awayTeamId          = 0,
    required this.refereeId,
    this.homeTeamName        = '',
    this.awayTeamName        = '',
    this.isChampionship      = false,
    this.championshipRoundId,
  });

  @override
  State<SoccerScoringPage> createState() => _SoccerScoringPageState();
}

class _SoccerScoringPageState extends State<SoccerScoringPage>
    with WidgetsBindingObserver {
  final SoccerSaveDelegate _captainDelegate = SoccerSaveDelegate();
  final SoccerSaveDelegate _refereeDelegate = SoccerSaveDelegate();
  final GlobalKey _globalKey = GlobalKey();

  int teamAScore = 0;
  int teamBScore = 0;

  bool _timerRunning = false;
  bool _hasStarted = false; // true once Start is pressed for the first time
  bool _overtimeConfirmed = false; // true if referee chose to extend after tie
  bool _isSubmitting = false; // guard against duplicate submissions
  int _remainingSeconds = 300;
  final int _totalSeconds = 300;
  Timer? _timer;
  bool _wasBackgrounded = false; // true only when timer was stopped due to AppLifecycle.paused
  DateTime? _backgroundedAt; // tracks when the app was backgrounded

  bool get _timerEnded => _hasStarted && _remainingSeconds == 0;

  bool _loading = true;
  String? _errorMsg;

  // ── Team color assignment ─────────────────────────────────────────
  _ColorAssignment? _colors; // null only during initial async load

  SoccerMatchInfo?      _match;
  SoccerTeamInfo?       _team;
  SoccerTeamInfo?       _awayTeam;
  SoccerRoundInfo?      _selectedRound;

  // ── Timer ─────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_timerRunning) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          if (_remainingSeconds == 0) {
            _timerRunning = false;
            _timer?.cancel();
            FeedbackUtils.timesUp(); // vibration burst + alert sound
            // Check for tie when timer naturally reaches 0
            if (teamAScore == teamBScore && !_overtimeConfirmed && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _showOvertimeDialog());
            }
          }
        }
      });
      _saveMatchState();
    });
  }

  String get _mm => (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
  String get _ss => (_remainingSeconds % 60).toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initColorAndData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
        _timer?.cancel();
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
    final safeAreaPad = MediaQuery.of(context).padding;
    final dialogDx = -(safeAreaPad.left - safeAreaPad.right) / 2;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final sw = MediaQuery.of(ctx).size.shortestSide;
        final isSmall = sw < 500;
        return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Transform.translate(
          offset: Offset(dialogDx, 0),
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
          padding: EdgeInsets.all(isSmall ? 16 : 24),
          decoration: BoxDecoration(
            color: _purple,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: isSmall ? 44 : 52, height: isSmall ? 44 : 52,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orangeAccent, width: 1.5),
              ),
              child: Icon(Icons.timer_off, color: Colors.orangeAccent, size: isSmall ? 22 : 26),
            ),
            SizedBox(height: isSmall ? 10 : 14),
            Text(
              "YOU'VE BEEN AWAY FOR A WHILE",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmall ? 12 : 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: isSmall ? 6 : 8),
            Text(
              "The match timer was paused. What would you like to do with the current scores?",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: isSmall ? 11 : 12, height: 1.5),
            ),
            SizedBox(height: isSmall ? 14 : 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: isSmall ? 38 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('KEEP CURRENT SCORES',
                    style: TextStyle(color: Colors.white, fontSize: isSmall ? 12 : 13, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(height: isSmall ? 8 : 10),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  teamAScore = 0;
                  teamBScore = 0;
                  _remainingSeconds = _totalSeconds;
                  _hasStarted = false;
                  _timerRunning = false;
                  _overtimeConfirmed = false;
                });
                _timer?.cancel();
                _saveMatchState();
              },
              child: Container(
                width: double.infinity, height: isSmall ? 38 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30),
                ),
                child: Text('RESET SCORES & TIMER',
                    style: TextStyle(color: Colors.white, fontSize: isSmall ? 12 : 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
        ),
        ),
      );
      },
    );
  }

  /// Load persisted color assignment (or create+save a new random one),
  /// restore scores/timer if available, then fetch match data.
  Future<void> _initColorAndData() async {
    // 1. Color assignment
    final existing = await _ColorAssignment.load(widget.matchId);
    final colors   = existing ?? await _ColorAssignment.createAndSave(widget.matchId);

    // 2. Restore match state if a previous session saved one
    final saved = await _MatchStatePersistence.load(widget.matchId);
    if (mounted) {
      setState(() {
        _colors = colors;
        if (saved != null) {
          teamAScore        = saved['scoreA'] as int;
          teamBScore        = saved['scoreB'] as int;
          _remainingSeconds = saved['timer']  as int;
          _hasStarted       = saved['started'] as bool;
        }
      });
    }
    _fetchAllData();
  }

  // ── Back-button interception ──────────────────────────────────────
  /// Called by both the custom BACK button and PopScope (Android back gesture).
  /// If the match has never started, just pop immediately.
  /// Otherwise show a dialog that lets the referee keep scores, reset, or leave.
  void _handleBackPress() {
    if (!_hasStarted) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _showBackWarningDialog();
  }

  void _showBackWarningDialog() {
    final safeAreaPad = MediaQuery.of(context).padding;
    final dialogDx = -(safeAreaPad.left - safeAreaPad.right) / 2;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final sw = MediaQuery.of(ctx).size.shortestSide;
        final isSmall = sw < 500;
        return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Transform.translate(
          offset: Offset(dialogDx, 0),
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
          padding: EdgeInsets.all(isSmall ? 16 : 24),
          decoration: BoxDecoration(
            color: _purple,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: isSmall ? 44 : 52, height: isSmall ? 44 : 52,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orangeAccent, width: 1.5),
              ),
              child: Icon(Icons.timer_off, color: Colors.orangeAccent, size: isSmall ? 22 : 26),
            ),
            SizedBox(height: isSmall ? 10 : 14),
            Text(
              'LEAVE THE MATCH?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmall ? 12 : 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: isSmall ? 6 : 8),
            Text(
              'The match is still in progress. The timer and scores will be reset. What would you like to do?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: isSmall ? 11 : 12, height: 1.5),
            ),
            SizedBox(height: isSmall ? 14 : 20),
            // Stay and keep scores
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: isSmall ? 38 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('STAY',
                    style: TextStyle(color: Colors.white, fontSize: isSmall ? 12 : 13, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(height: isSmall ? 8 : 10),
            // Actually leave
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  teamAScore = 0;
                  teamBScore = 0;
                  _remainingSeconds = _totalSeconds;
                  _hasStarted = false;
                  _timerRunning = false;
                  _overtimeConfirmed = false;
                });
                _timer?.cancel();
                _saveMatchState();
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                width: double.infinity, height: isSmall ? 38 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30),
                ),
                child: Text('BACK',
                    style: TextStyle(color: Colors.white, fontSize: isSmall ? 12 : 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
        ),
        ),
      );
      },
    );
  }

  /// Persist current scores + timer to disk. Called on every change.
  Future<void> _saveMatchState() => _MatchStatePersistence.save(
    matchId:          widget.matchId,
    teamAScore:       teamAScore,
    teamBScore:       teamBScore,
    remainingSeconds: _remainingSeconds,
    hasStarted:       _hasStarted,
  );

  Future<void> _fetchAllData() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      if (widget.isChampionship) {
        // Championship: skip get_match & get_team — use passed names directly.
        // Only fetch rounds so the round dropdown works.
        final rounds = await SoccerScoringApiService.fetchRounds();
        setState(() {
          _match = SoccerMatchInfo(
            matchId: widget.matchId, scheduleId: 0,
            scheduleStart: '—', scheduleEnd: '—',
          );
          _team = SoccerTeamInfo(
            teamId: widget.teamId,
            teamName: widget.homeTeamName.isNotEmpty
                ? widget.homeTeamName : 'Home Team',
            categoryId: 0,
          );
          _awayTeam = widget.awayTeamId > 0
              ? SoccerTeamInfo(
                  teamId: widget.awayTeamId,
                  teamName: widget.awayTeamName.isNotEmpty
                      ? widget.awayTeamName : 'Away Team',
                  categoryId: 0,
                )
              : null;
          _selectedRound = rounds.isNotEmpty ? rounds.first : null;
          _loading = false;
        });
        return;
      }

      // Standard qualification flow
      final results = await Future.wait([
        SoccerScoringApiService.fetchMatch(widget.matchId),
        SoccerScoringApiService.fetchReferee(widget.refereeId),
        SoccerScoringApiService.fetchTeam(widget.teamId),
        if (widget.awayTeamId > 0) SoccerScoringApiService.fetchTeam(widget.awayTeamId),
        SoccerScoringApiService.fetchCategories(),
        SoccerScoringApiService.fetchRounds(),
        SoccerScoringApiService.fetchMatchScores(widget.matchId),
      ]);

      final match    = results[0] as SoccerMatchInfo?;
      final homeTeam = results[2] as SoccerTeamInfo?;
      int ri = 3;
      SoccerTeamInfo? awayTeam;
      if (widget.awayTeamId > 0) awayTeam = results[ri++] as SoccerTeamInfo?;
      ri++; // skip categories
      final rounds      = results[ri]   as List<SoccerRoundInfo>;
      final existScores = results[ri+1] as List<Map<String, dynamic>>;

      // DB scores are the source of truth. If the DB has scores, apply them
      // and sync SharedPreferences. If the DB has NO scores (e.g. deleted),
      // clear SharedPreferences so stale local state doesn't survive.
      if (existScores.isNotEmpty) {
        int newA = 0, newB = 0;
        for (final s in existScores) {
          final tid = int.tryParse(s['team_id']?.toString() ?? '0') ?? 0;
          final sc  = int.tryParse(s['score_independentscore']?.toString() ?? '0') ?? 0;
          if (tid == widget.teamId) { newA = sc; } else { newB = sc; }
        }
        setState(() { teamAScore = newA; teamBScore = newB; });
        _saveMatchState(); // keep SharedPreferences in sync with DB
      } else {
        // No scores in DB (never submitted or deleted) — wipe local cache
        await _MatchStatePersistence.clear(widget.matchId);
        setState(() { teamAScore = 0; teamBScore = 0; });
      }

      setState(() {
        _match         = match;
        _team          = homeTeam;
        _awayTeam      = awayTeam;
        _selectedRound = rounds.isNotEmpty ? rounds.first : null;
        _loading       = false;
      });
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  Future<void> _saveToGallery(BuildContext ctx) async {
    try {
      final boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
      final file  = await File('${dir.path}/match_${widget.matchId}_${DateTime.now().millisecondsSinceEpoch}.jpg').create();
      await file.writeAsBytes(bytes);
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(file.path);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Saved!'), backgroundColor: _saveGreen, duration: Duration(seconds: 2)));
    } catch (e) { debugPrint('Gallery: $e'); }
  }

  Future<void> _submitScore(BuildContext ctx) async {
    // ── Duplicate-submission guard ────────────────────────────────────
    if (_isSubmitting) return;

    // ── Validation 1: Timer never started ─────────────────────────
    if (!_hasStarted) {
      _showValidationDialog(
        icon: Icons.timer_off_outlined,
        iconColor: Colors.orangeAccent,
        title: 'MATCH NOT STARTED',
        message: 'The timer was never started. Please start the match before submitting scores.',
      );
      return;
    }

    // ── Validation 2: Timer elapsed = 0 (started but no time played) ─
    final elapsed = _totalSeconds - _remainingSeconds;
    if (elapsed == 0) {
      _showValidationDialog(
        icon: Icons.timer_off_outlined,
        iconColor: Colors.orangeAccent,
        title: 'NO TIME ELAPSED',
        message: 'No match time has been recorded. Start and play the match before submitting.',
      );
      return;
    }

    // ── Validation 3: Empty signatures ────────────────────────────
    final captainSigned = _captainDelegate.points.any((p) => p != null);
    final refereeSigned = _refereeDelegate.points.any((p) => p != null);
    if (!captainSigned || !refereeSigned) {
      _showValidationDialog(
        icon: Icons.draw_outlined,
        iconColor: Colors.orangeAccent,
        title: 'SIGNATURES REQUIRED',
        message: !captainSigned && !refereeSigned
            ? 'Both the captain and referee signatures are required before submitting.'
            : !captainSigned
                ? 'The captain signature is missing. Please have the captain sign before submitting.'
                : 'The referee signature is missing. Please sign before submitting.',
      );
      return;
    }

    // ── Validation 4: Tied + timer ended, not yet confirmed ───────
    if (_timerEnded && teamAScore == teamBScore && !_overtimeConfirmed) {
      _showOvertimeDialog();
      Navigator.pop(ctx); // close the summary popup so dialog is on top
      return;
    }

    if (_selectedRound == null && widget.championshipRoundId == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Please select Competition Info.')));
      return;
    }

    // ── Zero-score confirmation ───────────────────────────────────────
    if (teamAScore == 0 && teamBScore == 0) {
      final safeAreaPadZ = MediaQuery.of(context).padding;
      final dialogDxZ = -(safeAreaPadZ.left - safeAreaPadZ.right) / 2;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dlgCtx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
            child: Transform.translate(
              offset: Offset(dialogDxZ, 0),
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: _purple, borderRadius: BorderRadius.circular(20)),
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
              const Text('ZERO SCORE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Text(
                'Both teams have 0 goals. This may be a mistake. Are you sure you want to submit?',
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
                    onTap: () => Navigator.pop(dlgCtx, false),
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
                    onTap: () => Navigator.pop(dlgCtx, true),
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
          ), // ConstrainedBox+Transform
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));

    // ── Duplicate-submission check (server-side) ──────────────────────
    final homeExists = await SoccerScoringApiService.scoreExists(
        widget.matchId, widget.teamId);
    if (homeExists) {
      if (!mounted) return;
      rootNav.pop(); // dismiss loading dialog
      setState(() => _isSubmitting = false);
      _showValidationDialog(
        icon: Icons.block,
        iconColor: Colors.orangeAccent,
        title: 'ALREADY SUBMITTED',
        message:
            'A score for this match and team has already been recorded. Duplicate submissions are not allowed.',
      );
      return;
    }

    final dur = '${(elapsed ~/ 60).toString().padLeft(2,'0')}:${(elapsed % 60).toString().padLeft(2,'0')}';

    final homeOk = await SoccerScoringApiService.submitScore(
      matchId: widget.matchId, roundId: widget.championshipRoundId ?? _selectedRound!.roundId,
      teamId: widget.teamId, refereeId: widget.refereeId,
      teamAScore: teamAScore, teamBScore: teamBScore,
      teamAFouls: 0, teamBFouls: 0, totalDuration: dur,
      isChampionship: widget.isChampionship,
    );
    bool awayOk = true;
    if (widget.awayTeamId > 0) {
      // For the away team row: pass the away team's own score as teamAScore.
      // submitScore always uses teamAScore as score_independentscore and
      // score_totalscore = teamAScore - violations, so each team gets
      // their own correct score stored — never the opponent's.
      awayOk = await SoccerScoringApiService.submitScore(
        matchId: widget.matchId, roundId: widget.championshipRoundId ?? _selectedRound!.roundId,
        teamId: widget.awayTeamId, refereeId: widget.refereeId,
        teamAScore: teamBScore,  // ✅ away team's OWN score
        teamBScore: teamAScore,  // unused in payload — kept for API signature
        teamAFouls: 0, teamBFouls: 0, totalDuration: dur,
        isChampionship: widget.isChampionship,
      );
    }
    if (!mounted) return;
    rootNav.pop(); // dismiss loading dialog
    if (homeOk && awayOk) {
      // Clear saved state — match is done, next open should start fresh
      await _MatchStatePersistence.clear(widget.matchId);
      if (!mounted) return;
      if (ctx.mounted) Navigator.pop(ctx); // close the MATCH SUMMARY dialog
      if (mounted) Navigator.pop(context, true); // return true → schedule screen shows snackbar
    } else {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Submission failed.'), backgroundColor: _penaltyRed));
    }
  }

  // Generic validation error dialog
  void _showValidationDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    final safeAreaPad = MediaQuery.of(context).padding;
    final dialogDx = -(safeAreaPad.left - safeAreaPad.right) / 2;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Transform.translate(
          offset: Offset(dialogDx, 0),
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: _purple, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: iconColor, width: 2),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.7),
                    fontSize: 11, height: 1.5)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: iconColor, borderRadius: BorderRadius.circular(12)),
                child: const Text('OK',
                    style: TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
        ),
        ), // ConstrainedBox+Transform
      ),
    );
  }

  // Overtime / extra time dialog — shown when timer ends and scores are tied
  void _showOvertimeDialog() {
    if (!mounted) return;
    final safeAreaPad = MediaQuery.of(context).padding;
    final dialogDx = -(safeAreaPad.left - safeAreaPad.right) / 2;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Transform.translate(
          offset: Offset(dialogDx, 0),
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: _purple, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Icon
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orangeAccent, width: 2),
              ),
              child: const Icon(Icons.sports_soccer,
                  color: Colors.orangeAccent, size: 28),
            ),
            const SizedBox(height: 14),
            const Text("TIME'S UP — IT'S A TIE!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text('$teamAScore  –  $teamBScore',
                style: const TextStyle(color: Colors.orangeAccent,
                    fontSize: 28, fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Text('What would you like to do?',
                style: TextStyle(color: Colors.white.withOpacity(0.65),
                    fontSize: 11)),
            const SizedBox(height: 20),
            // EXTEND — set extra time via SET dialog
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _showSetTimerDialog(); // referee sets extra time manually
              },
              child: Container(
                width: double.infinity, height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.orangeAccent,
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('EXTEND TIME',
                        style: TextStyle(color: Colors.white,
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // ACCEPT TIE — proceed to submit as-is
            GestureDetector(
              onTap: () {
                setState(() => _overtimeConfirmed = true);
                Navigator.pop(ctx);
              },
              child: Container(
                width: double.infinity, height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30),
                ),
                child: const Text('ACCEPT TIE RESULT',
                    style: TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
        ),
        ), // ConstrainedBox+Transform
      ),
    );
  }

  // SET button → edit timer dialog
  void _showSetTimerDialog() {
    // Stop timer while editing
    _timer?.cancel();
    if (_timerRunning) setState(() => _timerRunning = false);

    int tempMinutes = _remainingSeconds ~/ 60;
    int tempSeconds = _remainingSeconds % 60;

    final safeAreaPad = MediaQuery.of(context).padding;
    final dialogDx = -(safeAreaPad.left - safeAreaPad.right) / 2;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final sw = MediaQuery.of(ctx).size.shortestSide;
          final isSmall = sw < 500;
          return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
            child: Transform.translate(
              offset: Offset(dialogDx, 0),
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
            padding: EdgeInsets.all(isSmall ? 16 : 24),
            decoration: BoxDecoration(
                color: _purple, borderRadius: BorderRadius.circular(20)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Title
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const SizedBox(width: 32),
                Text('SET TIMER',
                    style: TextStyle(color: Colors.white, fontSize: isSmall ? 14 : 16,
                        fontWeight: FontWeight.w900, letterSpacing: 1)),
                GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white)),
              ]),
              const Divider(color: Colors.white24, height: 20),

              // Minutes and Seconds pickers — FittedBox prevents overflow on narrow screens
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Minutes
                Column(children: [
                  const Text('MIN', style: TextStyle(color: Colors.white70,
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _timerPickerBtn(Icons.remove_rounded, () {
                      setDialogState(() {
                        if (tempMinutes > 0) { tempMinutes--; }
                      });
                    }),
                    const SizedBox(width: 10),
                    Container(
                      width: 72, height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white38, width: 1.5),
                      ),
                      child: Text(tempMinutes.toString().padLeft(2, '0'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 10),
                    _timerPickerBtn(Icons.add_rounded, () {
                      setDialogState(() {
                        if (tempMinutes < 99) { tempMinutes++; }
                      });
                    }),
                  ]),
                ]),

                const Padding(
                  padding: EdgeInsets.only(top: 24, left: 12, right: 12),
                  child: Text(':', style: TextStyle(color: Colors.white,
                      fontSize: 32, fontWeight: FontWeight.bold)),
                ),

                // Seconds
                Column(children: [
                  const Text('SEC', style: TextStyle(color: Colors.white70,
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _timerPickerBtn(Icons.remove_rounded, () {
                      setDialogState(() {
                        if (tempSeconds > 0) { tempSeconds--; }
                        else if (tempMinutes > 0) { tempMinutes--; tempSeconds = 59; }
                      });
                    }),
                    const SizedBox(width: 10),
                    Container(
                      width: 72, height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white38, width: 1.5),
                      ),
                      child: Text(tempSeconds.toString().padLeft(2, '0'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 10),
                    _timerPickerBtn(Icons.add_rounded, () {
                      setDialogState(() {
                        if (tempSeconds < 59) { tempSeconds++; }
                        else { tempSeconds = 0; if (tempMinutes < 99) { tempMinutes++; } }
                      });
                    }),
                  ]),
                ]),
              ]),
              ),

              SizedBox(height: isSmall ? 16 : 24),
              // Confirm button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _remainingSeconds = (tempMinutes * 60) + tempSeconds;
                  });
                  _saveMatchState();
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  height: isSmall ? 40 : 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _confirmPurple, borderRadius: BorderRadius.circular(12)),
                  child: Text('CONFIRM',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white,
                          fontSize: isSmall ? 13 : 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
          ),
          ),
        );
        },
      ),
    );
  }

  // SET popup → signature + submit
  // SET button → signature + submit popup
  void _showSetPopup() {
    final safeAreaPad = MediaQuery.of(context).padding;
    final dialogDx = -(safeAreaPad.left - safeAreaPad.right) / 2;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final sw = mq.size.shortestSide;
        final isSmall = sw < 500;
        return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Transform.translate(
          offset: Offset(dialogDx, 0),
          child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isSmall ? mq.size.width * 0.92 : 520,
            maxHeight: mq.size.height * 0.92,
          ),
          child: Container(
          padding: EdgeInsets.all(isSmall ? 14 : 20),
          decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Title
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const SizedBox(width: 32),
            Text('MATCH SUMMARY',
                style: TextStyle(color: Colors.white, fontSize: isSmall ? 13 : 15,
                    fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            GestureDetector(onTap: () => Navigator.pop(ctx),
                child: const Icon(Icons.close, color: Colors.white)),
          ]),
          Divider(color: Colors.white24, height: isSmall ? 10 : 16),
          RepaintBoundary(
            key: _globalKey,
            child: Container(
              color: _purple, padding: EdgeInsets.all(isSmall ? 6 : 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Score
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 16, vertical: isSmall ? 6 : 10),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Expanded(child: Text(
                      widget.homeTeamName.isNotEmpty ? widget.homeTeamName : (_team?.teamName ?? '—'),
                      textAlign: TextAlign.center, maxLines: 2,
                      style: TextStyle(color: Colors.white, fontSize: isSmall ? 11 : 13, fontWeight: FontWeight.bold),
                    )),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 16),
                      child: Text('$teamAScore  –  $teamBScore',
                          style: TextStyle(color: Colors.white, fontSize: isSmall ? 22 : 30,
                              fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                    ),
                    Expanded(child: Text(
                      widget.awayTeamName.isNotEmpty ? widget.awayTeamName : (_awayTeam?.teamName ?? '—'),
                      textAlign: TextAlign.center, maxLines: 2,
                      style: TextStyle(color: Colors.white, fontSize: isSmall ? 11 : 13, fontWeight: FontWeight.bold),
                    )),
                  ]),
                ),
                SizedBox(height: isSmall ? 2 : 4),
                Text('MATCH ${_match?.matchId ?? '—'}  •  TIME $_mm:$_ss',
                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
                SizedBox(height: isSmall ? 8 : 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SoccerSignaturePad(delegate: _captainDelegate, label: 'CAPTAIN SIGNATURE')),
                  const SizedBox(width: 12),
                  Expanded(child: SoccerSignaturePad(delegate: _refereeDelegate, label: 'REFEREE SIGNATURE')),
                ]),
                SizedBox(height: isSmall ? 6 : 10),
                const Text(
                  'I confirm that I have examined the scores and am willing to submit them without any alterations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ]),
            ),
          ),
          SizedBox(height: isSmall ? 8 : 12),
          Builder(builder: (localCtx) => Row(children: [
            Expanded(child: _popupBtn('SAVE', _saveGreen, () => _saveToGallery(localCtx))),
            const SizedBox(width: 10),
            Expanded(child: _popupBtn('SUBMIT', _confirmPurple, () => _submitScore(localCtx))),
          ])),
        ]),
        ),
        ),
        ), // ConstrainedBox+Transform
      );
      },
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading || _colors == null) {
      return const Scaffold(
        backgroundColor: _bgGrey,
        body: Center(child: CircularProgressIndicator(color: _purple)),
      );
    }

    if (_errorMsg != null) {
      return Scaffold(
        backgroundColor: _bgGrey,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: _penaltyRed, size: 48),
          const SizedBox(height: 12),
          const Text('Failed to load data',
              style: TextStyle(color: _penaltyRed, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _purple),
            onPressed: _fetchAllData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ])),
      );
    }

    final homeName = widget.homeTeamName.isNotEmpty ? widget.homeTeamName : (_team?.teamName ?? 'TEAM A');
    final awayName = widget.awayTeamName.isNotEmpty ? widget.awayTeamName : (_awayTeam?.teamName ?? 'TEAM B');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackPress();
      },
      child: Scaffold(
      backgroundColor: _bgGrey,
      body: Column(children: [

          // ── TOP BAR: BACK left │ TIMER center ─────────────────────
          Container(
            height: 52,
            color: _purple,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              // BACK — fixed width so the spacer on the right can match it exactly
              SizedBox(
                width: 80,
                child: GestureDetector(
                  onTap: _handleBackPress,
                  child: Row(children: [
                    Container(
                      width: 30, height: 30,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Center(
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: _purple, size: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('BACK',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),

              // TIMER — fills remaining space and is centered in it
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _remainingSeconds <= 30 ? Colors.redAccent : Colors.white38,
                          width: 1.5),
                    ),
                    child: Text(
                      '$_mm:$_ss',
                      style: TextStyle(
                          color: _remainingSeconds <= 30 ? Colors.redAccent : Colors.white,
                          fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),

              // Exact same width as the BACK button so timer is perfectly centered
              const SizedBox(width: 80),
            ]),
          ),

          // ── MAIN: TEAM A left │ TEAM B right ─────────────────────
          Expanded(
            child: Row(children: [
              // TEAM A
              Expanded(child: _buildTeamPanel(
                teamName: homeName,
                score: teamAScore,
                color: _colors!.homeColor,
                colorLabel: _colors!.homeLabel,
                onInc: _hasStarted && _timerRunning ? () { setState(() => teamAScore++); _saveMatchState(); } : null,
                onDec: _hasStarted && _timerRunning ? () { setState(() { if (teamAScore > 0) teamAScore--; }); _saveMatchState(); } : null,
              )),

              // vertical divider
              Container(width: 2, color: Colors.grey.shade300),

              // TEAM B
              Expanded(child: _buildTeamPanel(
                teamName: awayName,
                score: teamBScore,
                color: _colors!.awayColor,
                colorLabel: _colors!.awayLabel,
                onInc: _hasStarted && _timerRunning ? () { setState(() => teamBScore++); _saveMatchState(); } : null,
                onDec: _hasStarted && _timerRunning ? () { setState(() { if (teamBScore > 0) teamBScore--; }); _saveMatchState(); } : null,
              )),
            ]),
          ),

          // ── BOTTOM BAR: START │ SET │ RESET ─────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(child: _bottomBtn(
                label: _timerRunning ? 'PAUSE' : 'START',
                color: _timerRunning ? _pauseRed : _startGreen,
                icon: _timerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: () {
                  setState(() {
                    _timerRunning = !_timerRunning;
                    if (_timerRunning) { _hasStarted = true; _startTimer(); } else { _timer?.cancel(); }
                  });
                  _saveMatchState();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _bottomBtn(
                label: 'SET',
                color: _purple,
                icon: Icons.timer_outlined,
                onTap: _showSetTimerDialog,
              )),
              const SizedBox(width: 8),
              Expanded(child: _bottomBtn(
                label: 'RESET',
                color: _resetPurple,
                icon: Icons.refresh_rounded,
                onTap: () {
                  setState(() {
                    _timer?.cancel(); _timerRunning = false; _hasStarted = false;
                    _remainingSeconds = _totalSeconds;
                    teamAScore = 0; teamBScore = 0;
                  });
                  _MatchStatePersistence.clear(widget.matchId); // wipe saved state
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _bottomBtn(
                label: 'SWAP',
                color: _swapGold,
                icon: Icons.swap_horiz_rounded,
                onTap: () async {
                  final safeAreaPadS = MediaQuery.of(context).padding;
                  final dialogDxS = -(safeAreaPadS.left - safeAreaPadS.right) / 2;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) {
                      final sw = MediaQuery.of(ctx).size.shortestSide;
                      final isSmall = sw < 500;
                      return Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: EdgeInsets.zero,
                      child: Transform.translate(
                        offset: Offset(dialogDxS, 0),
                        child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                        padding: EdgeInsets.all(isSmall ? 16 : 24),
                        decoration: BoxDecoration(
                          color: _purple,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon
                            Container(
                              width: isSmall ? 44 : 56, height: isSmall ? 44 : 56,
                              decoration: BoxDecoration(
                                color: _swapGold.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: _swapGold, width: 2),
                              ),
                              child: Icon(Icons.swap_horiz_rounded,
                                  color: _swapGold, size: isSmall ? 22 : 30),
                            ),
                            SizedBox(height: isSmall ? 10 : 16),
                            // Title
                            Text('SWAP SIDES?',
                                style: TextStyle(color: Colors.white,
                                    fontSize: isSmall ? 13 : 16, fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                            SizedBox(height: isSmall ? 6 : 8),
                            // Current assignment
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isSmall ? 10 : 16, vertical: isSmall ? 6 : 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _swapPreviewTeam(
                                    label: 'HOME',
                                    colorName: _colors!.homeLabel,
                                    color: _colors!.homeColor,
                                    arrowColor: _swapGold,
                                    newColorName: _colors!.awayLabel,
                                    newColor: _colors!.awayColor,
                                  ),
                                  const Icon(Icons.swap_horiz_rounded,
                                      color: _swapGold, size: 28),
                                  _swapPreviewTeam(
                                    label: 'AWAY',
                                    colorName: _colors!.awayLabel,
                                    color: _colors!.awayColor,
                                    arrowColor: _swapGold,
                                    newColorName: _colors!.homeLabel,
                                    newColor: _colors!.homeColor,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isSmall ? 4 : 6),
                            Text('This will be saved and cannot be\nautomatically undone.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: isSmall ? 9 : 10)),
                            SizedBox(height: isSmall ? 14 : 20),
                            // Buttons
                            Row(children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(ctx, false),
                                  child: Container(
                                    height: isSmall ? 38 : 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: Text('CANCEL',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white,
                                            fontSize: isSmall ? 12 : 13,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(ctx, true),
                                  child: Container(
                                    height: isSmall ? 38 : 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _swapGold,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('SWAP',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white,
                                            fontSize: isSmall ? 12 : 13,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      ),
                      ),
                    );
                    },
                  );
                  if (confirmed != true || !mounted) return;
                  final swapped = _colors!.swapped();
                  // ignore: use_build_context_synchronously
                  final messenger = ScaffoldMessenger.of(context);
                  await swapped.save(widget.matchId);
                  if (!mounted) return;
                  setState(() => _colors = swapped);
                  messenger.showSnackBar(SnackBar(
                    content: Text(
                      'Sides swapped — Home: ${swapped.homeLabel}  ·  Away: ${swapped.awayLabel}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: _swapGold,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _bottomBtn(
                label: 'CONFIRM',
                color: _confirmPurple,
                icon: Icons.check_rounded,
                onTap: _showSetPopup,
              )),
            ]),
          ),

        ]),
    ), // Scaffold
    ); // PopScope
  }

  // ─────────────────────────────────────────────
  // TEAM PANEL  —  name top, score box center, − + below
  // ─────────────────────────────────────────────
  Widget _buildTeamPanel({
    required String teamName,
    required int score,
    required Color color,
    required String colorLabel,
    required VoidCallback? onInc,
    required VoidCallback? onDec,
  }) {
    return Container(
      color: _bgGrey,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Team name + color badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(teamName,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                          color: color, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Text(colorLabel,
                    style: TextStyle(color: color, fontSize: 10,
                        fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Score box
          Expanded(
            child: Container(
              width: double.infinity,
                    decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: color, width: 3),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                    color: color.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(score.toString().padLeft(2, '0'),
                    style: TextStyle(fontSize: 80, fontWeight: FontWeight.w900, color: color)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // − and + buttons
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _scoreBtn(Icons.remove_rounded, color, onDec),
            const SizedBox(width: 24),
            _scoreBtn(Icons.add_rounded, color, onInc),
          ]),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────
  Widget _timerPickerBtn(IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38, width: 1.5)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _scoreBtn(IconData icon, Color color, VoidCallback? onTap) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap == null ? null : () {
        FeedbackUtils.counterTap();
        onTap();
      },
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
            color: enabled ? color.withOpacity(0.12) : Colors.grey.shade300,
            shape: BoxShape.circle,
            border: Border.all(color: enabled ? color : Colors.grey.shade400, width: 2)),
        child: Icon(icon, color: enabled ? color : Colors.grey.shade500, size: 28),
      ),
    );
  }

  Widget _bottomBtn({
    required String label, required Color color,
    required IconData icon, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final isSmall = MediaQuery.of(context).size.width < 600;
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: isSmall ? 7 : 10,
            ),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))]),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(
                    color: Colors.white, fontSize: isSmall ? 11 : 14, fontWeight: FontWeight.bold)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _swapPreviewTeam({
    required String label,
    required String colorName,
    required Color color,
    required Color arrowColor,
    required String newColorName,
    required Color newColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
        const SizedBox(height: 6),
        // Current color pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Text(colorName,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Icon(Icons.arrow_downward_rounded, color: arrowColor, size: 14),
        const SizedBox(height: 4),
        // New color pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: newColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: newColor, width: 1.5),
          ),
          child: Text(newColorName,
              style: TextStyle(
                  color: newColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  Widget _popupBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      );
}