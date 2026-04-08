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
import 'api_config.dart';
import 'feedback_utils.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────
class TimerMatchInfo {
  final int matchId;
  final int scheduleId;
  final String scheduleStart;
  final String scheduleEnd;

  TimerMatchInfo({
    required this.matchId,
    required this.scheduleId,
    required this.scheduleStart,
    required this.scheduleEnd,
  });

  factory TimerMatchInfo.fromJson(Map<String, dynamic> j) => TimerMatchInfo(
        matchId:       int.tryParse(j['match_id'].toString()) ?? 0,
        scheduleId:    int.tryParse(j['schedule_id'].toString()) ?? 0,
        scheduleStart: j['schedule_start'] ?? '',
        scheduleEnd:   j['schedule_end'] ?? '',
      );
}

class TimerRefereeInfo {
  final int refereeId;
  final String refereeName;

  TimerRefereeInfo({required this.refereeId, required this.refereeName});

  factory TimerRefereeInfo.fromJson(Map<String, dynamic> j) => TimerRefereeInfo(
        refereeId:   int.tryParse(j['referee_id'].toString()) ?? 0,
        refereeName: j['referee_name'] ?? '',
      );
}

class TimerTeamInfo {
  final int teamId;
  final String teamName;
  final int categoryId;

  TimerTeamInfo({required this.teamId, required this.teamName, required this.categoryId});

  factory TimerTeamInfo.fromJson(Map<String, dynamic> j) => TimerTeamInfo(
        teamId:     int.tryParse(j['team_id'].toString()) ?? 0,
        teamName:   j['team_name'] ?? '',
        categoryId: int.tryParse(j['category_id'].toString()) ?? 0,
      );
}

class TimerCategoryInfo {
  final int categoryId;
  final String categoryType;

  TimerCategoryInfo({required this.categoryId, required this.categoryType});

  factory TimerCategoryInfo.fromJson(Map<String, dynamic> j) => TimerCategoryInfo(
        categoryId:   int.tryParse(j['category_id'].toString()) ?? 0,
        categoryType: j['category_type'] ?? '',
      );
}

class TimerRoundInfo {
  final int roundId;
  final String roundType;

  TimerRoundInfo({required this.roundId, required this.roundType});

  factory TimerRoundInfo.fromJson(Map<String, dynamic> j) => TimerRoundInfo(
        roundId:   int.tryParse(j['round_id'].toString()) ?? 0,
        roundType: j['round_type'] ?? '',
      );
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class TimerScoringApiService {
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

  static Future<TimerMatchInfo?> fetchMatch(int matchId) async {
    final response = await _get('get_match', {'match_id': '$matchId'});
    if (response.statusCode == 200) return TimerMatchInfo.fromJson(json.decode(response.body));
    throw Exception('get_match failed [${response.statusCode}]: ${response.body}');
  }

  static Future<TimerRefereeInfo?> fetchReferee(int refereeId) async {
    final response = await _get('get_referee', {'referee_id': '$refereeId'});
    if (response.statusCode == 200) return TimerRefereeInfo.fromJson(json.decode(response.body));
    throw Exception('get_referee failed [${response.statusCode}]: ${response.body}');
  }

  static Future<TimerTeamInfo?> fetchTeam(int teamId) async {
    final response = await _get('get_team', {'team_id': '$teamId'});
    if (response.statusCode == 200) return TimerTeamInfo.fromJson(json.decode(response.body));
    throw Exception('get_team failed [${response.statusCode}]: ${response.body}');
  }

  static Future<List<TimerCategoryInfo>> fetchCategories() async {
    final response = await _get('get_categories');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TimerCategoryInfo.fromJson(e)).toList();
    }
    throw Exception('get_categories failed [${response.statusCode}]: ${response.body}');
  }

  static Future<List<TimerRoundInfo>> fetchRounds() async {
    final response = await _get('get_rounds');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TimerRoundInfo.fromJson(e)).toList();
    }
    throw Exception('get_rounds failed [${response.statusCode}]: ${response.body}');
  }

  static Future<bool> submitScore({
    required int matchId,
    required int roundId,
    required int teamId,
    required int refereeId,
    required String totalDuration,
  }) async {
    final url = Uri.parse('${ApiConfig.scoring}?action=submit_score');
    debugPrint('[API] POST $url');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'match_id':               matchId,
        'round_id':               roundId,
        'team_id':                teamId,
        'referee_id':             refereeId,
        'score_independentscore': 0,
        'score_violation':        0,
        'score_totalscore':       0,
        'score_totalduration':    totalDuration,
        'score_isapproved':       0,
      }),
    ).timeout(const Duration(seconds: 10));
    debugPrint('[API] submit_score ${response.statusCode}: ${response.body}');
    return response.statusCode == 200 || response.statusCode == 201;
  }
}

// ─────────────────────────────────────────────
// SIGNATURE PAD
// ─────────────────────────────────────────────
class TimerSignaturePad extends StatefulWidget {
  final TimerSaveDelegate delegate;
  final String label;
  final bool isSmall;

  const TimerSignaturePad({super.key, required this.delegate, required this.label, this.isSmall = false});

  @override
  TimerSignaturePadState createState() => TimerSignaturePadState();
}

class TimerSignaturePadState extends State<TimerSignaturePad> {
  final GlobalKey _paintKey = GlobalKey();

  void _handlePanUpdate(DragUpdateDetails details) {
    final RenderBox renderBox = _paintKey.currentContext?.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
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
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
              onPressed: () => setState(() => widget.delegate.clear()),
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
              height: widget.isSmall ? 80 : 120,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: TimerSignaturePainter(points: List.from(widget.delegate.points)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class TimerSignaturePainter extends CustomPainter {
  TimerSignaturePainter({required this.points});
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
  bool shouldRepaint(TimerSignaturePainter oldDelegate) => oldDelegate.points != points;
}

class TimerSaveDelegate {
  List<Offset?> points = <Offset?>[];
  void addPoint(Offset? point) => points.add(point);
  void clear() => points.clear();
}

// ─────────────────────────────────────────────
// COLOR PALETTE  —  Matches mbot1_scoring
// ─────────────────────────────────────────────
const Color _bgDark        = Color(0xFFF0F0F0); // bgGrey
const Color _bgCard        = Color(0xFFFFFFFF); // white cards
const Color _bgCardAlt     = Color(0xFFE8E8E8); // inputGrey
const Color _accentGreen   = Color(0xFF5E975E); // saveGreen
const Color _accentAmber   = Color(0xFFF9D949); // accentYellow
const Color _accentRed     = Color(0xFFB35D65); // penaltyRed / pauseRed
const Color _accentPurple  = Color(0xFF7D58B3); // primaryPurple
const Color _textPrimary   = Color(0xFF1A1A2E); // near-black on light bg
const Color _textMuted     = Color(0xFF9E9E9E); // muted grey
const Color _divider       = Color(0xFFDDDDDD); // light grey divider
const Color _timerIdle     = Color(0x557D58B3); // low-opacity purple for disabled state

// ─────────────────────────────────────────────
// TIMER SCORING PAGE
// ─────────────────────────────────────────────
class TimerScoringPage extends StatefulWidget {
  final int matchId;
  final int teamId;
  final int refereeId;

  const TimerScoringPage({
    super.key,
    required this.matchId,
    required this.teamId,
    required this.refereeId,
  });

  @override
  State<TimerScoringPage> createState() => _TimerScoringPageState();
}

class _TimerScoringPageState extends State<TimerScoringPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ── Signature delegates ──────────────────────
  final TimerSaveDelegate _captainDelegate = TimerSaveDelegate();
  final TimerSaveDelegate _refereeDelegate = TimerSaveDelegate();
  final GlobalKey _globalKey = GlobalKey();

  // ── Stopwatch state ──────────────────────────
  bool _timerRunning    = false;
  bool _hasStarted      = false;
  bool _wasBackgrounded = false; // true only when paused via AppLifecycle.paused
  int  _elapsedMs       = 0; // total elapsed ms (updated each tick)
  int  _baseElapsedMs   = 0; // accumulated ms before current run segment
  DateTime? _startTime;        // wall-clock time when current run segment started
  Timer? _stopwatchTimer;

  // ── Pulse animation for running timer ────────
  late AnimationController _pulseCtrl;
  late Animation<double>    _pulseAnim;

  void _startTimer() {
    _stopwatchTimer?.cancel();
    _startTime = DateTime.now(); // record wall-clock start of this segment
    _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_timerRunning || _startTime == null) return;
      setState(() {
        _elapsedMs = _baseElapsedMs +
            DateTime.now().difference(_startTime!).inMilliseconds;
      });
    });
  }

  String _formatMs(int ms) {
    final m  = (ms ~/ 60000).toString().padLeft(2, '0');
    final s  = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$cs';
  }

  String get _timerDisplay => _formatMs(_elapsedMs);

  // ── Fetched data ─────────────────────────────
  bool _loading = true;
  String? _errorMsg;

  TimerMatchInfo?    _match;
  TimerRefereeInfo?  _referee;
  TimerTeamInfo?     _team;

  List<TimerCategoryInfo> _categories = [];
  TimerCategoryInfo?      _selectedCategory;
  List<TimerRoundInfo>    _rounds = [];
  TimerRoundInfo?         _selectedRound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _fetchAllData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatchTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` fires when the notification panel is pulled down OR the
    // recent-apps overlay appears. The ticker is still running — do nothing.
    //
    // `paused` fires only when the app is truly backgrounded (home button,
    // user switched to another app). Stop the ticker here and record elapsed.
    //
    // `resumed` fires when returning from EITHER inactive OR paused. We must
    // only restart the ticker when we actually stopped it (i.e. _wasBackgrounded).
    if (state == AppLifecycleState.paused) {
      if (_timerRunning) {
        _baseElapsedMs   = _elapsedMs; // freeze current time
        _startTime       = null;
        _wasBackgrounded = true;
        _stopwatchTimer?.cancel();
        // _timerRunning stays true so it auto-resumes on foreground
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_timerRunning && _wasBackgrounded) {
        _wasBackgrounded = false;
        _startTimer(); // picks up from _baseElapsedMs
      }
      // If _wasBackgrounded is false we came back from `inactive` (notification
      // panel / recent-apps peek) — the ticker was never stopped, nothing to do.
    }
  }

  Future<void> _fetchAllData() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final match      = await TimerScoringApiService.fetchMatch(widget.matchId);
      final referee    = await TimerScoringApiService.fetchReferee(widget.refereeId);
      final team       = await TimerScoringApiService.fetchTeam(widget.teamId);
      final categories = await TimerScoringApiService.fetchCategories();
      final rounds     = await TimerScoringApiService.fetchRounds();

      TimerCategoryInfo? selCategory;
      if (team != null && categories.isNotEmpty) {
        selCategory = categories.firstWhere(
          (c) => c.categoryId == team.categoryId,
          orElse: () => categories.first,
        );
      }

      setState(() {
        _match            = match;
        _referee          = referee;
        _team             = team;
        _categories       = categories;
        _selectedCategory = selCategory;
        _rounds           = rounds;
        _selectedRound    = rounds.isNotEmpty ? rounds.first : null;
        _loading          = false;
      });
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  // ─────────────────────────────────────────────
  // SAVE SCREENSHOT
  // ─────────────────────────────────────────────
  Future<void> _saveToGallery(BuildContext localContext) async {
    try {
      final boundary =
          _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes    = byteData!.buffer.asUint8List();
      final dir      = await getTemporaryDirectory();
      final file     = await File(
          '${dir.path}/timer_${widget.teamId}_${DateTime.now().millisecondsSinceEpoch}.jpg')
          .create();
      await file.writeAsBytes(bytes);
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(file.path);
      if (!localContext.mounted) return;
      ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(
        content: Text('Saved to gallery!'),
        backgroundColor: _accentGreen,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      debugPrint('Gallery error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // SUBMIT
  // ─────────────────────────────────────────────
  Future<void> _submitScore(BuildContext localContext) async {
    // Validate signatures
    final captainSigned = _captainDelegate.points.any((p) => p != null);
    final refereeSigned = _refereeDelegate.points.any((p) => p != null);
    if (!captainSigned || !refereeSigned) {
      _showValidationDialog(
        icon: Icons.draw_outlined,
        iconColor: _accentRed,
        title: 'SIGNATURES REQUIRED',
        message: !captainSigned && !refereeSigned
            ? 'Both captain and referee signatures are required.'
            : !captainSigned
                ? 'Captain signature is missing.'
                : 'Referee signature is missing.',
      );
      return;
    }

    if (_selectedRound == null) {
      ScaffoldMessenger.of(localContext).showSnackBar(
          const SnackBar(content: Text('Please select a round.')));
      return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _accentGreen)),
    );

    final success = await TimerScoringApiService.submitScore(
      matchId:       widget.matchId,
      roundId:       _selectedRound!.roundId,
      teamId:        widget.teamId,
      refereeId:     widget.refereeId,
      totalDuration: _timerDisplay,
    );

    if (!mounted) return;
    rootNav.pop();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Score submitted!'),
        backgroundColor: _accentGreen,
      ));
      rootNav.pop();
      rootNav.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submission failed. Please try again.'),
        backgroundColor: _accentRed,
      ));
    }
  }

  // ─────────────────────────────────────────────
  // VALIDATION DIALOG
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
              color: _accentPurple, borderRadius: BorderRadius.circular(20)),
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
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.5)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.orangeAccent, borderRadius: BorderRadius.circular(12)),
                child: const Text('OK',
                    style: TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SIGNATURE + SUBMIT POPUP
  // ─────────────────────────────────────────────
  // Remove this because the confirm button is disabled if it hasnt start yet
  void _showSignaturePopup() {
    if (!_hasStarted || _elapsedMs == 0) {
      _showValidationDialog(
        icon: Icons.timer_off_outlined,
        iconColor: _accentAmber,
        title: 'NO TIME RECORDED',
        message: 'Start and run the timer before confirming results.',
      );
      return;
    }
    if (_timerRunning) {
      _showValidationDialog(
        icon: Icons.pause_circle_outline,
        iconColor: _accentAmber,
        title: 'TIMER STILL RUNNING',
        message: 'Pause the timer before confirming the result.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final mq = MediaQuery.of(ctx);
        final isSmall = mq.size.height < 650;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: IntrinsicHeight(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmall ? 16 : 24,
                  vertical: isSmall ? 14 : 20,
                ),
                decoration: const BoxDecoration(
                  color: _accentPurple,
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
                        Text(
                          'RUN SUMMARY',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmall ? 15 : 18,
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
                    SizedBox(height: isSmall ? 8 : 12),
                    RepaintBoundary(
                      key: _globalKey,
                      child: Container(
                        padding: EdgeInsets.all(isSmall ? 6 : 10),
                        color: _accentPurple,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _team?.teamName ?? '—',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isSmall ? 15 : 18,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              'ID: ${widget.teamId}',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: isSmall ? 12 : 14),
                            ),
                            SizedBox(height: isSmall ? 10 : 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildSummaryLabel('${_match?.matchId ?? '—'}', 'MATCH', isSmall: isSmall),
                                _buildSummaryLabel(_timerDisplay, 'TIME', isSmall: isSmall),
                                _buildSummaryLabel(
                                    _selectedRound?.roundType ?? '—', 'ROUND', isSmall: isSmall),
                              ],
                            ),
                            SizedBox(height: isSmall ? 10 : 15),
                            TimerSignaturePad(
                                delegate: _captainDelegate,
                                label: 'CAPTAIN SIGNATURE',
                                isSmall: isSmall),
                            SizedBox(height: isSmall ? 6 : 10),
                            TimerSignaturePad(
                                delegate: _refereeDelegate,
                                label: 'REFEREE SIGNATURE',
                                isSmall: isSmall),
                            SizedBox(height: isSmall ? 10 : 15),
                            Text(
                              'I confirm that I have examined the scores and am willing to submit them without any alterations.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: isSmall ? 10 : 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: isSmall ? 12 : 20),
                    Builder(
                      builder: (localCtx) => Row(
                        children: [
                          Expanded(child: _actionBtn('SAVE', const Color(0xFF5E975E),
                              () => _saveToGallery(localCtx))),
                          const SizedBox(width: 10),
                          Expanded(child: _actionBtn('SUBMIT', const Color(0xFF3B1F6E),
                              () => _submitScore(localCtx))),
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

  Widget _buildSummaryLabel(String value, String label, {bool isSmall = false}) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: isSmall ? 18 : 24,
                  fontStyle: FontStyle.italic)),
        ),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // BACK BUTTON INTERCEPTION
  // ─────────────────────────────────────────────
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
            color: _accentPurple,
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
              'LEAVE THE RUN?',
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
              'The timer is still running. The recorded time will be lost. What would you like to do?',
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
                _stopwatchTimer?.cancel();
                setState(() {
                  _timerRunning = false;
                  _hasStarted   = false;
                  _elapsedMs    = 0;
                });
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

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      backgroundColor: _bgDark,
      body: Center(child: CircularProgressIndicator(color: _accentGreen)),
    );

    if (_errorMsg != null) return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _accentPurple,
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: _accentRed, size: 48),
          const SizedBox(height: 16),
          const Text('Failed to load data',
              style: TextStyle(color: _accentRed, fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(_errorMsg!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textMuted, fontSize: 12)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _accentPurple),
            onPressed: _fetchAllData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ]),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) { if (!didPop) _handleBackPress(); },
      child: Scaffold(
      backgroundColor: _bgDark,
      body: CustomScrollView(
        slivers: [
          // ── APP BAR ─────────────────────────────
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: _accentPurple,
            automaticallyImplyLeading: false,
            toolbarHeight: 70,
            leading: GestureDetector(
              onTap: _handleBackPress,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: const Center(
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: _accentPurple, size: 12)),
                    ),
                    const SizedBox(width: 6),
                    const Text('BACK',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            leadingWidth: 100,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _selectedCategory?.categoryType.toUpperCase() ?? 'TIMER SCORING',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'MATCH ${_match?.matchId ?? "—"}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── BODY ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(children: [

                // ── HERO TIMER ─────────────────────
                _buildHeroTimer(),
                const SizedBox(height: 16),

                // ── TEAM INFO STRIP ─────────────────
                _buildTeamStrip(),
                const SizedBox(height: 16),

                // ── MATCH INFO CARD ─────────────────
                _buildLapPanel(),
                const SizedBox(height: 16),

                // ── CONFIRM BUTTON ──────────────────
                _actionBtn(
                  'CONFIRM RESULT',
                  _hasStarted && !_timerRunning && _elapsedMs > 0
                      ? _accentPurple
                      : _timerIdle,
                  _hasStarted && !_timerRunning && _elapsedMs > 0
                      ? _showSignaturePopup
                      : () {},
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),

      // ── BOTTOM CONTROLS ─────────────────────────
      bottomNavigationBar: _buildBottomControls(),
    ), // Scaffold
    ); // PopScope
  }

  // ─────────────────────────────────────────────
  // HERO TIMER
  // ─────────────────────────────────────────────
  Widget _buildHeroTimer() {
    final Color timerColor = _timerRunning
        ? _accentGreen
        : _hasStarted
            ? _accentAmber
            : _accentPurple.withOpacity(0.4);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _timerRunning
              ? _accentGreen.withOpacity(0.4)
              : _divider,
          width: _timerRunning ? 1.5 : 1,
        ),
        boxShadow: _timerRunning
            ? [BoxShadow(
                color: _accentGreen.withOpacity(0.08),
                blurRadius: 24, spreadRadius: 4)]
            : [],
      ),
      child: Column(children: [
        // Status chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: timerColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: timerColor.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Pulsing dot
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: _timerRunning
                      ? _accentGreen.withOpacity(_pulseAnim.value)
                      : timerColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _timerRunning ? 'RUNNING' : _hasStarted ? 'PAUSED' : 'READY',
              style: TextStyle(color: timerColor, fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Main time display
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _timerDisplay,
            style: TextStyle(
              color: timerColor,
              fontSize: 72,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // TEAM INFO STRIP
  // ─────────────────────────────────────────────
  Widget _buildTeamStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _divider),
      ),
      child: Row(children: [
        // Team avatar
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _accentPurple.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accentPurple.withOpacity(0.4)),
          ),
          child: const Icon(Icons.precision_manufacturing_outlined,
              color: _accentPurple, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TEAM',
                style: TextStyle(color: _textMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 2),
            // FittedBox keeps the name on one line regardless of length
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_team?.teamName ?? '—',
                  maxLines: 1,
                  style: const TextStyle(color: _textPrimary, fontSize: 25,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        )),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // MATCH INFORMATION CARD
  // ─────────────────────────────────────────────
  Widget _buildLapPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
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
          const Text('MATCH INFORMATION',
              style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 11)),
          const SizedBox(height: 20),
          _buildScoringField('COMPETITION TIME',
              _match != null
                  ? '${_match!.scheduleStart} – ${_match!.scheduleEnd}'
                  : '—'),
          _buildScoringField('REFEREE NAME', _referee?.refereeName ?? '—'),
          Row(children: [
            Expanded(child: _buildScoringField('TEAM ID', '${widget.teamId}')),
            const SizedBox(width: 15),
            Expanded(child: _buildScoringField('ROUND',
                _selectedRound?.roundType ?? '—')),
          ]),
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
                color: _bgCardAlt,
                borderRadius: BorderRadius.circular(5)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
          Positioned(
            top: -12,
            left: 5,
            child: Text(label,
                style: const TextStyle(
                    color: _accentPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BOTTOM CONTROLS
  // ─────────────────────────────────────────────
  Widget _buildBottomControls() {
    return Container(
      color: _bgDark,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(children: [
        // START / PAUSE
        Expanded(
          flex: 3,
          child: GestureDetector(
            onTap: () {
              FeedbackUtils.controlTap();
              setState(() {
                _timerRunning = !_timerRunning;
                if (_timerRunning) { _hasStarted = true; _startTimer(); }
                else {
                  _stopwatchTimer?.cancel();
                  _baseElapsedMs = _elapsedMs; // save progress on pause
                  _startTime = null;
                }
              });
            },
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: _timerRunning
                    ? _accentRed.withOpacity(0.15)
                    : _accentGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _timerRunning ? _accentRed : _accentGreen,
                  width: 1.5,
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  _timerRunning
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: _timerRunning ? _accentRed : _accentGreen,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  _timerRunning ? 'PAUSE' : 'START',
                  style: TextStyle(
                    color: _timerRunning ? _accentRed : _accentGreen,
                    fontSize: 16, fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // RESET
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () {
              FeedbackUtils.controlTap();
              setState(() {
                _stopwatchTimer?.cancel();
                _timerRunning   = false;
                _hasStarted     = false;
                _elapsedMs      = 0;
                _baseElapsedMs  = 0;
                _startTime      = null;
              });
            },
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF79569A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                SizedBox(width: 6),
                Text('RESET', style: TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w900, letterSpacing: 1)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity, height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(14)),
          child: Text(label,
              style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      );
}