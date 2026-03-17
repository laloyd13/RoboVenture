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

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────
class SoccerMatchInfo {
  final int matchId;
  final int scheduleId;
  final String scheduleStart;
  final String scheduleEnd;

  SoccerMatchInfo({
    required this.matchId,
    required this.scheduleId,
    required this.scheduleStart,
    required this.scheduleEnd,
  });

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
  static Future<SoccerMatchInfo?> fetchMatch(int matchId) async {
    final response = await _get('get_match', {'match_id': '$matchId'});
    if (response.statusCode == 200) {
      return SoccerMatchInfo.fromJson(json.decode(response.body));
    }
    throw Exception('get_match failed [${response.statusCode}]: ${response.body}');
  }

  // GET referee by ID
  static Future<SoccerRefereeInfo?> fetchReferee(int refereeId) async {
    final response = await _get('get_referee', {'referee_id': '$refereeId'});
    if (response.statusCode == 200) {
      return SoccerRefereeInfo.fromJson(json.decode(response.body));
    }
    throw Exception('get_referee failed [${response.statusCode}]: ${response.body}');
  }

  // GET team by ID
  static Future<SoccerTeamInfo?> fetchTeam(int teamId) async {
    final response = await _get('get_team', {'team_id': '$teamId'});
    if (response.statusCode == 200) {
      return SoccerTeamInfo.fromJson(json.decode(response.body));
    }
    throw Exception('get_team failed [${response.statusCode}]: ${response.body}');
  }

  // GET all active categories
  static Future<List<SoccerCategoryInfo>> fetchCategories() async {
    final response = await _get('get_categories');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => SoccerCategoryInfo.fromJson(e)).toList();
    }
    throw Exception('get_categories failed [${response.statusCode}]: ${response.body}');
  }

  // GET all rounds
  static Future<List<SoccerRoundInfo>> fetchRounds() async {
    final response = await _get('get_rounds');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => SoccerRoundInfo.fromJson(e)).toList();
    }
    throw Exception('get_rounds failed [${response.statusCode}]: ${response.body}');
  }

  // GET existing scores for a match
  static Future<List<Map<String, dynamic>>> fetchMatchScores(int matchId) async {
    try {
      final response = await _get('get_match_scores', {'match_id': '$matchId'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // POST submit score
  static Future<bool> submitScore({
    required int matchId,
    required int roundId,
    required int teamId,
    required int refereeId,
    required int teamAScore,
    required int teamBScore,
    required int teamAFouls,
    required int teamBFouls,
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
        'score_independentscore': teamAScore,
        'score_violation':        teamAFouls + teamBFouls,
        'score_totalscore':       teamBScore,
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
class SoccerSignaturePad extends StatefulWidget {
  final SoccerSaveDelegate delegate;
  final String label;

  const SoccerSignaturePad({super.key, required this.delegate, required this.label});

  @override
  SoccerSignaturePadState createState() => SoccerSignaturePadState();
}

class SoccerSignaturePadState extends State<SoccerSignaturePad> {
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
                  painter: SoccerSignaturePainter(
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

class SoccerSignaturePainter extends CustomPainter {
  SoccerSignaturePainter({required this.points});
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
  bool shouldRepaint(SoccerSignaturePainter oldDelegate) =>
      oldDelegate.points != points;
}

class SoccerSaveDelegate {
  List<Offset?> points = <Offset?>[];
  void addPoint(Offset? point) => points.add(point);
  void clear() => points.clear();
}

// ─────────────────────────────────────────────
// COLOR PALETTE
// ─────────────────────────────────────────────
const Color soccerPrimaryPurple = Color(0xFF7D58B3);
const Color soccerBadgePurple = Color(0xFFC8BFE1);
const Color soccerAccentYellow = Color(0xFFF9D949);
const Color soccerMissionBlue = Color(0xFF8BA3C7);
const Color soccerMissionGreen = Color(0xFF76A379);
const Color soccerMissionAmber = Color(0xFFC7A38B);
const Color soccerMissionPurple = Color(0xFF8789C0);
const Color soccerMissionLavender = Color(0xFF9B8CB8);
const Color soccerPenaltyRed = Color(0xFFB35D65);
const Color soccerBgGrey = Color(0xFFF0F0F0);
const Color soccerInputGrey = Color(0xFFE8E8E8);
const Color soccerSaveGreen = Color(0xFF5E975E);
const Color soccerConfirmPurple = Color(0xFF3B1F6E);
const Color soccerPauseRed = Color(0xFFB35D65);
const Color soccerStartGreen = Color(0xFF5E975E);
const Color soccerResetPurple = Color(0xFF79569A);

// ─────────────────────────────────────────────
// SCORING PAGE
// ─────────────────────────────────────────────
class SoccerScoringPage extends StatefulWidget {

  final int    matchId;
  final int    teamId;          // home team
  final int    awayTeamId;      // away team (0 if not passed)
  final int    refereeId;
  final String homeTeamName;
  final String awayTeamName;

  const SoccerScoringPage({
    super.key,
    required this.matchId,
    required this.teamId,
    this.awayTeamId   = 0,
    required this.refereeId,
    this.homeTeamName = '',
    this.awayTeamName = '',
  });

  @override
  State<SoccerScoringPage> createState() => _SoccerScoringPageState();
}

class _SoccerScoringPageState extends State<SoccerScoringPage> {
  // ── Signature delegates ──────────────────────
  final SoccerSaveDelegate _captainADelegate = SoccerSaveDelegate();
  final SoccerSaveDelegate _refereeDelegate  = SoccerSaveDelegate();
  final GlobalKey _globalKey = GlobalKey();

  // ── Soccer scores ─────────────
  int teamAScore = 0;
  int teamAFouls = 0;
  int teamBScore = 0;
  int teamBFouls = 0;

    // ── Timer state ──────────────────────────────
  bool _timerRunning = false;
  int _remainingSeconds = 300; // fixed 5:00 minutes
  final int _totalSeconds = 300;
  Timer? _countdownTimer;

  void _initTimer() {
    setState(() => _remainingSeconds = _totalSeconds);
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_timerRunning) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timerRunning = false;
          _countdownTimer?.cancel();
        }
      });
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

  SoccerMatchInfo?    _match;
  SoccerRefereeInfo?  _referee;
  SoccerTeamInfo?     _team;      // home team
  SoccerTeamInfo?     _awayTeam;  // away team

  List<SoccerCategoryInfo> _categories = [];
  SoccerCategoryInfo?      _selectedCategory;

  List<SoccerRoundInfo> _rounds = [];
  SoccerRoundInfo?      _selectedRound;

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAllData() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      // Fetch all data in parallel for speed
      final results = await Future.wait([
        SoccerScoringApiService.fetchMatch(widget.matchId),
        SoccerScoringApiService.fetchReferee(widget.refereeId),
        SoccerScoringApiService.fetchTeam(widget.teamId),
        if (widget.awayTeamId > 0)
          SoccerScoringApiService.fetchTeam(widget.awayTeamId),
        SoccerScoringApiService.fetchCategories(),
        SoccerScoringApiService.fetchRounds(),
        SoccerScoringApiService.fetchMatchScores(widget.matchId),
      ]);

      final match      = results[0] as SoccerMatchInfo?;
      final referee    = results[1] as SoccerRefereeInfo?;
      final homeTeam   = results[2] as SoccerTeamInfo?;
      int ri = 3;
      SoccerTeamInfo? awayTeam;
      if (widget.awayTeamId > 0) {
        awayTeam = results[ri] as SoccerTeamInfo?;
        ri++;
      }
      final categories  = results[ri]   as List<SoccerCategoryInfo>;
      final rounds      = results[ri+1] as List<SoccerRoundInfo>;
      final existScores = results[ri+2] as List<Map<String, dynamic>>;

      // Pre-fill scores if already scored
      bool alreadyScored = existScores.isNotEmpty;
      if (alreadyScored) {
        for (final s in existScores) {
          final tid = int.tryParse(s['team_id']?.toString() ?? '0') ?? 0;
          final sc  = int.tryParse(s['score_independentscore']?.toString() ?? '0') ?? 0;
          final foul = int.tryParse(s['score_violation']?.toString() ?? '0') ?? 0;
          if (tid == widget.teamId) {
            teamAScore = sc; teamAFouls = foul;
          } else {
            teamBScore = sc; teamBFouls = foul;
          }
        }
      }

      SoccerCategoryInfo? selCategory;
      if (homeTeam != null && categories.isNotEmpty) {
        selCategory = categories.firstWhere(
          (c) => c.categoryId == homeTeam.categoryId,
          orElse: () => categories.first,
        );
      }

      setState(() {
        _match            = match;
        _referee          = referee;
        _team             = homeTeam;
        _awayTeam         = awayTeam;
        _categories       = categories;
        _selectedCategory = selCategory;
        _rounds           = rounds;
        _selectedRound    = rounds.isNotEmpty ? rounds.first : null;
        _loading          = false;
      });
      _initTimer();
    } catch (e) {
      debugPrint('[SoccerScoringPage] _fetchAllData error: $e');
      setState(() { _errorMsg = e.toString(); _loading = false; });
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
        backgroundColor: soccerSaveGreen,
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
  Future<void> _submitScore(BuildContext localContext) async {
    if (_selectedRound == null) {
      ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(
          content: Text('Please select a Competition Info (round).')));
      return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final elapsed = _totalSeconds - _remainingSeconds;
    final em = (elapsed ~/ 60).toString().padLeft(2, '0');
    final es = (elapsed % 60).toString().padLeft(2, '0');

    // Submit score for HOME team
    final homeSuccess = await SoccerScoringApiService.submitScore(
      matchId:       widget.matchId,
      roundId:       _selectedRound!.roundId,
      teamId:        widget.teamId,
      refereeId:     widget.refereeId,
      teamAScore:    teamAScore,
      teamBScore:    teamBScore,
      teamAFouls:    teamAFouls,
      teamBFouls:    teamBFouls,
      totalDuration: '$em:$es',
    );

    // Submit score for AWAY team (if we have it)
    bool awaySuccess = true;
    if (widget.awayTeamId > 0) {
      awaySuccess = await SoccerScoringApiService.submitScore(
        matchId:       widget.matchId,
        roundId:       _selectedRound!.roundId,
        teamId:        widget.awayTeamId,
        refereeId:     widget.refereeId,
        teamAScore:    teamBScore,   // away team's score
        teamBScore:    teamAScore,   // home team's score (opponent)
        teamAFouls:    teamBFouls,
        teamBFouls:    teamAFouls,
        totalDuration: '$em:$es',
      );
    }

    final success = homeSuccess && awaySuccess;

    if (!mounted) return;
    rootNav.pop();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Score submitted successfully!'),
        backgroundColor: soccerSaveGreen,
      ));
      rootNav.pop();
      rootNav.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submission failed. Please try again.'),
        backgroundColor: soccerPenaltyRed,
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
                  color: soccerPrimaryPurple,
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
                        color: soccerPrimaryPurple,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Home vs Away names
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(child: Text(
                                  widget.homeTeamName.isNotEmpty
                                      ? widget.homeTeamName
                                      : (_team?.teamName ?? '—'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                )),
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('VS',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900)),
                                ),
                                Expanded(child: Text(
                                  widget.awayTeamName.isNotEmpty
                                      ? widget.awayTeamName
                                      : (_awayTeam?.teamName ?? '—'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                )),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildSummaryLabel('${_match?.matchId ?? '—'}', 'MATCH'),
                                _buildSummaryLabel('$teamAScore - $teamBScore', 'SCORE'),
                                _buildSummaryLabel(() {
                                  final elapsed = _totalSeconds - _remainingSeconds;
                                  final m = (elapsed ~/ 60).toString().padLeft(2, '0');
                                  final s = (elapsed % 60).toString().padLeft(2, '0');
                                  return '$m:$s';
                                }(), 'TIME'),
                              ],
                            ),
                            const SizedBox(height: 15),
                            SoccerSignaturePad(
                                delegate: _captainADelegate,
                                label: "CAPTAIN A SIGNATURE"),
                            const SizedBox(height: 10),
                            SoccerSignaturePad(
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
                              soccerSaveGreen,
                              fontSize: 18,
                              onTap: () => _saveToGallery(localCtx),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildActionBtn(
                              "SUBMIT",
                              soccerConfirmPurple,
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
        backgroundColor: soccerBgGrey,
        body: Center(child: CircularProgressIndicator(color: soccerPrimaryPurple)),
      );
    }

    if (_errorMsg != null) {
      return Scaffold(
        backgroundColor: soccerBgGrey,
        appBar: AppBar(
          backgroundColor: soccerPrimaryPurple,
          automaticallyImplyLeading: false,
          title: GestureDetector(
            onTap: () => Navigator.pop(context),
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
              const Icon(Icons.error_outline, color: soccerPenaltyRed, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Failed to Load Data',
                style: TextStyle(color: soccerPenaltyRed, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Scrollable error box so long messages are fully readable
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: soccerPenaltyRed.withOpacity(0.4)),
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
                style: ElevatedButton.styleFrom(backgroundColor: soccerPrimaryPurple),
                onPressed: _fetchAllData,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: soccerBgGrey,
      body: CustomScrollView(
        slivers: [
          // ── APP BAR ───────────────────────────
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: soccerPrimaryPurple,
            automaticallyImplyLeading: false,
            title: GestureDetector(
              onTap: () => Navigator.pop(context),
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
                            color: soccerPrimaryPurple, size: 12, fontWeight: FontWeight.bold)),
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
              painter: SoccerGeometricBackgroundPainter(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // ── HEADER ROW ─────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
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
                                  color: soccerBadgePurple,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.black,
                                      width: 1.5)),
                              child: Text(
                                '${_match?.matchId ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '${_selectedCategory?.categoryType.toUpperCase() ?? 'ROBOVENTURE'} FORM',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: soccerPrimaryPurple),
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

                          // ── VS BANNER ─────────────────────────────
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 10),
                            decoration: BoxDecoration(
                              color: soccerPrimaryPurple.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: soccerPrimaryPurple.withOpacity(0.25)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Home team
                                Expanded(child: Column(
                                  children: [
                                    Text(
                                      widget.homeTeamName.isNotEmpty
                                          ? widget.homeTeamName
                                          : (_team?.teamName ?? '—'),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: soccerPrimaryPurple,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ID: ${widget.teamId}',
                                      style: TextStyle(
                                        color: soccerPrimaryPurple.withOpacity(0.6),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )),
                                // VS badge
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: soccerPrimaryPurple,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('VS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      )),
                                ),
                                // Away team
                                Expanded(child: Column(
                                  children: [
                                    Text(
                                      widget.awayTeamName.isNotEmpty
                                          ? widget.awayTeamName
                                          : (_awayTeam?.teamName ?? '—'),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: soccerPrimaryPurple,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ID: ${widget.awayTeamId > 0 ? widget.awayTeamId : (_awayTeam?.teamId ?? '—')}',
                                      style: TextStyle(
                                        color: soccerPrimaryPurple.withOpacity(0.6),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )),
                              ],
                            ),
                          ),

                          // Category Dropdown (from tbl_category)
                          _buildCategoryDropdown(),

                          // Competition Info / Round Dropdown (from tbl_round)
                          _buildRoundDropdown(),

                          const SizedBox(height: 10),
                          const Text("SCORING",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                          const Divider(height: 30),

                          Row(
                            children: [
                              Expanded(
                                child: _buildTeamScoringColumn(
                                  // Home team name — from widget param, then DB, fallback "TEAM A"
                                  widget.homeTeamName.isNotEmpty
                                      ? widget.homeTeamName
                                      : (_team?.teamName ?? 'TEAM A'),
                                  teamAScore, teamAFouls,
                                  (v) => setState(() => teamAScore = (teamAScore + v).clamp(0, 99)),
                                  (v) => setState(() => teamAFouls = (teamAFouls + v).clamp(0, 99)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildTeamScoringColumn(
                                  // Away team name — from widget param, then DB, fallback "TEAM B"
                                  widget.awayTeamName.isNotEmpty
                                      ? widget.awayTeamName
                                      : (_awayTeam?.teamName ?? 'TEAM B'),
                                  teamBScore, teamBFouls,
                                  (v) => setState(() => teamBScore = (teamBScore + v).clamp(0, 99)),
                                  (v) => setState(() => teamBFouls = (teamBFouls + v).clamp(0, 99)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                                                    _buildActionBtn(
                            "Confirm",
                            soccerPrimaryPurple,
                            fontSize: 18,
                            onTap: _showSignaturePopup,
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
        color: soccerBgGrey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                _timerRunning ? "Pause" : "Start",
                _timerRunning ? soccerPenaltyRed : soccerStartGreen,
                fontSize: 24,
                onTap: () {
                  setState(() {
                    _timerRunning = !_timerRunning;
                    if (_timerRunning) {
                      _startTimer();
                    } else {
                      _countdownTimer?.cancel();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildActionBtn(
                "Reset",
                soccerResetPurple,
                fontSize: 24,
                onTap: () {
                  setState(() {
                    _countdownTimer?.cancel();
                    _timerRunning = false;
                    _remainingSeconds = _totalSeconds;
                    teamAScore = 0;
                    teamAFouls = 0;
                    teamBScore = 0;
                    teamBFouls = 0;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                color: soccerInputGrey, borderRadius: BorderRadius.circular(5)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SoccerCategoryInfo>(
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
                    color: soccerPrimaryPurple,
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
                color: soccerInputGrey, borderRadius: BorderRadius.circular(5)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SoccerRoundInfo>(
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
                    color: soccerPrimaryPurple,
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

  Widget _buildScoringField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            decoration: BoxDecoration(
                color: soccerInputGrey,
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
                      color: soccerPrimaryPurple,
                      fontWeight: FontWeight.bold,
                      fontSize: 10))),
        ],
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
  // ─────────────────────────────────────────────
  // TEAM SCORING COLUMN
  // ─────────────────────────────────────────────
  Widget _buildTeamScoringColumn(
      String name, int score, int fouls,
      Function(int) onScore, Function(int) onFoul) {
    return Column(
      children: [
        Text(name,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 8),
        _buildScoringBox("GOAL", score, const Color(0xFF2ECC71), onScore),
        const SizedBox(height: 10),
        _buildScoringBox("FOUL", fouls, soccerPenaltyRed, onFoul),
      ],
    );
  }

  Widget _buildScoringBox(String label, int value, Color color, Function(int) callback) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSoccerCounterBtn(Icons.remove, onTap: () => callback(-1)),
              Text("$value",
                  style: const TextStyle(
                      color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              _buildSoccerCounterBtn(Icons.add, onTap: () => callback(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSoccerCounterBtn(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// GEOMETRIC BACKGROUND PAINTER
// ─────────────────────────────────────────────
class SoccerGeometricBackgroundPainter extends CustomPainter {
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