// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

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
    final r = await _get('get_match', {'match_id': '$id'});
    if (r.statusCode == 200) return SoccerMatchInfo.fromJson(json.decode(r.body));
    throw Exception('get_match failed');
  }

  static Future<SoccerRefereeInfo?> fetchReferee(int id) async {
    final r = await _get('get_referee', {'referee_id': '$id'});
    if (r.statusCode == 200) return SoccerRefereeInfo.fromJson(json.decode(r.body));
    throw Exception('get_referee failed');
  }

  static Future<SoccerTeamInfo?> fetchTeam(int id) async {
    final r = await _get('get_team', {'team_id': '$id'});
    if (r.statusCode == 200) return SoccerTeamInfo.fromJson(json.decode(r.body));
    throw Exception('get_team failed');
  }

  static Future<List<SoccerCategoryInfo>> fetchCategories() async {
    final r = await _get('get_categories');
    if (r.statusCode == 200) {
      return (json.decode(r.body) as List).map((e) => SoccerCategoryInfo.fromJson(e)).toList();
    }
    throw Exception('get_categories failed');
  }

  static Future<List<SoccerRoundInfo>> fetchRounds() async {
    final r = await _get('get_rounds');
    if (r.statusCode == 200) {
      return (json.decode(r.body) as List).map((e) => SoccerRoundInfo.fromJson(e)).toList();
    }
    throw Exception('get_rounds failed');
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
    final res = await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'match_id': matchId, 'round_id': roundId, 'team_id': teamId,
        'referee_id': refereeId,
        'score_independentscore': teamAScore,
        'score_violation':        teamAFouls + teamBFouls,
        'score_totalscore':       teamBScore,
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
    for (int i = 0; i < points.length - 1; i++)
      if (points[i] != null && points[i+1] != null) { canvas.drawLine(points[i]!, points[i+1]!, p); }
  }
  @override
  bool shouldRepaint(_SigPainter old) => old.points != points;
}

// ─────────────────────────────────────────────
// COLORS
// ─────────────────────────────────────────────
const Color _purple      = Color(0xFF7D58B3);
const Color _penaltyRed  = Color(0xFFB35D65);
const Color _bgGrey      = Color(0xFFF2F2F2);
const Color _saveGreen   = Color(0xFF5E975E);
const Color _confirmPurple = Color(0xFF3B1F6E);
const Color _startGreen  = Color(0xFF4CAF50);
const Color _pauseRed    = Color(0xFFE53935);
const Color _resetPurple = Color(0xFF79569A);
const Color _teamAColor  = Color(0xFF3A7BD5);
const Color _teamBColor  = Color(0xFF2E8B57);

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

  final bool isChampionship;

  const SoccerScoringPage({
    super.key,
    required this.matchId,
    required this.teamId,
    this.awayTeamId    = 0,
    required this.refereeId,
    this.homeTeamName  = '',
    this.awayTeamName  = '',
    this.isChampionship = false,
  });

  @override
  State<SoccerScoringPage> createState() => _SoccerScoringPageState();
}

class _SoccerScoringPageState extends State<SoccerScoringPage> {
  final SoccerSaveDelegate _captainDelegate = SoccerSaveDelegate();
  final SoccerSaveDelegate _refereeDelegate = SoccerSaveDelegate();
  final GlobalKey _globalKey = GlobalKey();

  int teamAScore = 0;
  int teamBScore = 0;

  bool _timerRunning = false;
  int _remainingSeconds = 300;
  final int _totalSeconds = 300;
  Timer? _timer;

  bool _loading = true;
  String? _errorMsg;

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
        if (_remainingSeconds > 0) _remainingSeconds--;
        else { _timerRunning = false; _timer?.cancel(); }
      });
    });
  }

  String get _mm => (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
  String get _ss => (_remainingSeconds % 60).toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide status bar and navigation bar for full screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fetchAllData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    // Restore system UI when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

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

      if (existScores.isNotEmpty) {
        for (final s in existScores) {
          final tid = int.tryParse(s['team_id']?.toString() ?? '0') ?? 0;
          final sc  = int.tryParse(s['score_independentscore']?.toString() ?? '0') ?? 0;
          if (tid == widget.teamId) { teamAScore = sc; } else { teamBScore = sc; }
        }
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
    if (_selectedRound == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Please select Competition Info.')));
      return;
    }
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));

    final elapsed = _totalSeconds - _remainingSeconds;
    final dur = '${(elapsed ~/ 60).toString().padLeft(2,'0')}:${(elapsed % 60).toString().padLeft(2,'0')}';

    final homeOk = await SoccerScoringApiService.submitScore(
      matchId: widget.matchId, roundId: _selectedRound!.roundId,
      teamId: widget.teamId, refereeId: widget.refereeId,
      teamAScore: teamAScore, teamBScore: teamBScore,
      teamAFouls: 0, teamBFouls: 0, totalDuration: dur,
      isChampionship: widget.isChampionship,
    );
    bool awayOk = true;
    if (widget.awayTeamId > 0) {
      awayOk = await SoccerScoringApiService.submitScore(
        matchId: widget.matchId, roundId: _selectedRound!.roundId,
        teamId: widget.awayTeamId, refereeId: widget.refereeId,
        teamAScore: teamBScore, teamBScore: teamAScore,
        teamAFouls: 0, teamBFouls: 0, totalDuration: dur,
        isChampionship: widget.isChampionship,
      );
    }
    if (!mounted) return;
    rootNav.pop(); // dismiss loading dialog
    if (homeOk && awayOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Score submitted!'), backgroundColor: _saveGreen));
      Navigator.pop(ctx);           // close the MATCH SUMMARY dialog
      Navigator.pop(context, true); // return true → championship marks as scored
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Submission failed.'), backgroundColor: _penaltyRed));
    }
  }

  // SET button → edit timer dialog
  void _showSetTimerDialog() {
    // Stop timer while editing
    _timer?.cancel();
    if (_timerRunning) setState(() => _timerRunning = false);

    int tempMinutes = _remainingSeconds ~/ 60;
    int tempSeconds = _remainingSeconds % 60;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: _purple, borderRadius: BorderRadius.circular(20)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Title
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const SizedBox(width: 32),
                const Text('SET TIMER',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w900, letterSpacing: 1)),
                GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white)),
              ]),
              const Divider(color: Colors.white24, height: 20),

              // Minutes and Seconds pickers
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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

              const SizedBox(height: 24),
              // Confirm button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _remainingSeconds = (tempMinutes * 60) + tempSeconds;
                  });
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _confirmPurple, borderRadius: BorderRadius.circular(12)),
                  child: const Text('CONFIRM',
                      style: TextStyle(color: Colors.white,
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // SET popup → signature + submit
  // SET button → signature + submit popup
  void _showSetPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Title
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const SizedBox(width: 32),
              const Text('MATCH SUMMARY',
                  style: TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              GestureDetector(onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close, color: Colors.white)),
            ]),
            const Divider(color: Colors.white24, height: 16),
            RepaintBoundary(
              key: _globalKey,
              child: Container(
                color: _purple, padding: const EdgeInsets.all(10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Score
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      Expanded(child: Text(
                        widget.homeTeamName.isNotEmpty ? widget.homeTeamName : (_team?.teamName ?? '—'),
                        textAlign: TextAlign.center, maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      )),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('$teamAScore  –  $teamBScore',
                            style: const TextStyle(color: Colors.white, fontSize: 30,
                                fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                      ),
                      Expanded(child: Text(
                        widget.awayTeamName.isNotEmpty ? widget.awayTeamName : (_awayTeam?.teamName ?? '—'),
                        textAlign: TextAlign.center, maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text('MATCH ${_match?.matchId ?? '—'}  •  TIME $_mm:$_ss',
                      style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: SoccerSignaturePad(delegate: _captainDelegate, label: 'CAPTAIN A SIGNATURE')),
                    const SizedBox(width: 12),
                    Expanded(child: SoccerSignaturePad(delegate: _refereeDelegate, label: 'REFEREE SIGNATURE')),
                  ]),
                  const SizedBox(height: 10),
                  const Text(
                    'I confirm that I have examined the scores and am willing to submit them without any alterations.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Builder(builder: (localCtx) => Row(children: [
              Expanded(child: _popupBtn('SAVE', _saveGreen, () => _saveToGallery(localCtx))),
              const SizedBox(width: 10),
              Expanded(child: _popupBtn('SUBMIT', _confirmPurple, () => _submitScore(localCtx))),
            ])),
          ]),
          ),
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
      backgroundColor: _bgGrey,
      body: Center(child: CircularProgressIndicator(color: _purple)),
    );

    if (_errorMsg != null) return Scaffold(
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

    final homeName = widget.homeTeamName.isNotEmpty ? widget.homeTeamName : (_team?.teamName ?? 'TEAM A');
    final awayName = widget.awayTeamName.isNotEmpty ? widget.awayTeamName : (_awayTeam?.teamName ?? 'TEAM B');

    // ── LANDSCAPE LAYOUT — matches sketch exactly ──────────────────
    //
    //  ┌─────────────────────────────────────────────────┐
    //  │  [← BACK]          [00] [00]  ← TIMER           │  top bar
    //  ├──────────────────────┬──────────────────────────┤
    //  │                      │                          │
    //  │   TEAM A             │           TEAM B         │
    //  │   [score box]        │           [score box]    │  main
    //  │   [−]  [+]           │           [−]  [+]       │
    //  │                      │                          │
    //  ├──────────────────────┴──────────────────────────┤
    //  │          [START]   [SET]   [RESET]              │  bottom bar
    //  └─────────────────────────────────────────────────┘
    return Scaffold(
      backgroundColor: _bgGrey,
      body: Column(children: [

          // ── TOP BAR: BACK left │ TIMER center ─────────────────────
          Container(
            height: 52,
            color: _purple,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              // BACK
              GestureDetector(
                onTap: () => Navigator.pop(context),
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

              // TIMER — centered, single box
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

              // spacer to balance BACK button width
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
                color: _teamAColor,
                onInc: () => setState(() => teamAScore++),
                onDec: () => setState(() { if (teamAScore > 0) { teamAScore--; } }),
              )),

              // vertical divider
              Container(width: 2, color: Colors.grey.shade300),

              // TEAM B
              Expanded(child: _buildTeamPanel(
                teamName: awayName,
                score: teamBScore,
                color: _teamBColor,
                onInc: () => setState(() => teamBScore++),
                onDec: () => setState(() { if (teamBScore > 0) { teamBScore--; } }),
              )),
            ]),
          ),

          // ── BOTTOM BAR: START │ SET │ RESET ─────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _bottomBtn(
                label: _timerRunning ? 'PAUSE' : 'START',
                color: _timerRunning ? _pauseRed : _startGreen,
                icon: _timerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: () => setState(() {
                  _timerRunning = !_timerRunning;
                  if (_timerRunning) { _startTimer(); } else { _timer?.cancel(); }
                }),
              ),
              _bottomBtn(
                label: 'SET',
                color: _purple,
                icon: Icons.timer_outlined,
                onTap: _showSetTimerDialog,
              ),
              _bottomBtn(
                label: 'RESET',
                color: _resetPurple,
                icon: Icons.refresh_rounded,
                onTap: () => setState(() {
                  _timer?.cancel(); _timerRunning = false;
                  _remainingSeconds = _totalSeconds;
                  teamAScore = 0; teamBScore = 0;
                }),
              ),
              _bottomBtn(
                label: 'CONFIRM',
                color: _confirmPurple,
                icon: Icons.check_rounded,
                onTap: _showSetPopup,
              ),
            ]),
          ),

        ]),
    );
  }

  // ─────────────────────────────────────────────
  // TEAM PANEL  —  name top, score box center, − + below
  // ─────────────────────────────────────────────
  Widget _buildTeamPanel({
    required String teamName,
    required int score,
    required Color color,
    required VoidCallback onInc,
    required VoidCallback onDec,
  }) {
    return Container(
      color: _bgGrey,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Team name
          Text(teamName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                  color: color, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          // Score box — takes remaining space
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
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

  Widget _scoreBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2)),
          child: Icon(icon, color: color, size: 28),
        ),
      );

  Widget _bottomBtn({
    required String label, required Color color,
    required IconData icon, required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))]),
          child: Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      );

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