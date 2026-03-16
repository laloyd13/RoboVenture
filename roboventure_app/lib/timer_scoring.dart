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

  const TimerSignaturePad({super.key, required this.delegate, required this.label});

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
              height: 120,
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
// COLOR PALETTE
// ─────────────────────────────────────────────
const Color _primaryPurple = Color(0xFF7D58B3);
const Color _badgePurple   = Color(0xFFC8BFE1);
const Color _penaltyRed    = Color(0xFFB35D65);
const Color _bgGrey        = Color(0xFFF0F0F0);
const Color _inputGrey     = Color(0xFFE8E8E8);
const Color _saveGreen     = Color(0xFF5E975E);
const Color _confirmPurple = Color(0xFF3B1F6E);
const Color _startGreen    = Color(0xFF5E975E);
const Color _resetPurple   = Color(0xFF79569A);

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

class _TimerScoringPageState extends State<TimerScoringPage> {
  // ── Signature delegates ──────────────────────
  final TimerSaveDelegate _captainDelegate = TimerSaveDelegate();
  final TimerSaveDelegate _refereeDelegate = TimerSaveDelegate();
  final GlobalKey _globalKey = GlobalKey();

  // ── Stopwatch state ──────────────────────────
  bool _timerRunning = false;
  int _elapsedSeconds = 0;
  Timer? _stopwatchTimer;

  void _startTimer() {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_timerRunning) return;
      setState(() => _elapsedSeconds++);
    });
  }

  String get _timerDisplay {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Fetched data ─────────────────────────────
  bool _loading = true;
  String? _errorMsg;

  TimerMatchInfo?    _match;
  TimerRefereeInfo?  _referee;
  TimerTeamInfo?     _team;

  List<TimerCategoryInfo> _categories = [];
  TimerCategoryInfo?      _selectedCategory;

  List<TimerRoundInfo> _rounds = [];
  TimerRoundInfo?      _selectedRound;

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    super.dispose();
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
      debugPrint('[TimerScoringPage] _fetchAllData error: $e');
      setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  // ─────────────────────────────────────────────
  // SAVE SCREENSHOT TO GALLERY
  // ─────────────────────────────────────────────
  Future<void> _saveToGallery(BuildContext localContext) async {
    try {
      RenderRepaintBoundary? boundary =
          _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
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
        backgroundColor: _saveGreen,
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
      ScaffoldMessenger.of(localContext).showSnackBar(
          const SnackBar(content: Text('Please select a Competition Info (round).')));
      return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
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
        content: Text('Score submitted successfully!'),
        backgroundColor: _saveGreen,
      ));
      rootNav.pop();
      rootNav.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submission failed. Please try again.'),
        backgroundColor: _penaltyRed,
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: const BoxDecoration(
                  color: _primaryPurple,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(25), topRight: Radius.circular(25)),
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
                        color: _primaryPurple,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _team?.teamName ?? '—',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'ID: ${widget.teamId}',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildSummaryLabel('${_match?.matchId ?? '—'}', 'MATCH'),
                                _buildSummaryLabel(_timerDisplay, 'TIME'),
                              ],
                            ),
                            const SizedBox(height: 15),
                            TimerSignaturePad(delegate: _captainDelegate, label: "CAPTAIN SIGNATURE"),
                            const SizedBox(height: 10),
                            TimerSignaturePad(delegate: _refereeDelegate, label: "REFEREE SIGNATURE"),
                            const SizedBox(height: 15),
                            const Text(
                              "I confirm that I have examined the scores and am willing to submit them without any alterations.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
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
                            child: _buildActionBtn("SAVE", _saveGreen,
                                fontSize: 18, onTap: () => _saveToGallery(localCtx)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildActionBtn("SUBMIT", _confirmPurple,
                                fontSize: 18, onTap: () => _submitScore(localCtx)),
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
        backgroundColor: _bgGrey,
        body: Center(child: CircularProgressIndicator(color: _primaryPurple)),
      );
    }

    if (_errorMsg != null) {
      return Scaffold(
        backgroundColor: _bgGrey,
        appBar: AppBar(
          backgroundColor: _primaryPurple,
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
              const Icon(Icons.error_outline, color: _penaltyRed, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to Load Data',
                  style: TextStyle(color: _penaltyRed, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _penaltyRed.withOpacity(0.4)),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(_errorMsg!,
                      style: const TextStyle(
                          color: Colors.black87, fontSize: 12, fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _primaryPurple),
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
      backgroundColor: _bgGrey,
      body: CustomScrollView(
        slivers: [
          // ── APP BAR ───────────────────────────
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: _primaryPurple,
            automaticallyImplyLeading: false,
            title: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Center(
                      child: Icon(Icons.arrow_back_ios_new_rounded, color: _primaryPurple, size: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("BACK",
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            actions: [
              // Stopwatch display in app bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 1.5),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 5),
                    Text(_timerDisplay,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: CustomPaint(
              painter: TimerGeometricBackgroundPainter(),
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
                                    color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Container(
                              width: 50, height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: _badgePurple,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.black, width: 1.5)),
                              child: Text(
                                '${_match?.matchId ?? '—'}',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              '${_selectedCategory?.categoryType.toUpperCase() ?? 'ROBOVENTURE'} FORM',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold, color: _primaryPurple),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),
                    const Divider(color: Colors.black26, thickness: 1, height: 1),
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
                                  color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                          const SizedBox(height: 20),

                          _buildScoringField("COMPETITION TIME",
                              _match != null
                                  ? '${_match!.scheduleStart} – ${_match!.scheduleEnd}'
                                  : '—'),
                          _buildScoringField("REFEREE NAME", _referee?.refereeName ?? '—'),
                          _buildScoringField("TEAM NAME", _team?.teamName ?? '—'),

                          Row(
                            children: [
                              Expanded(child: _buildScoringField("TEAM ID", '${widget.teamId}')),
                              const SizedBox(width: 15),
                              Expanded(child: _buildCategoryDropdown()),
                            ],
                          ),

                          _buildRoundDropdown(),

                          const SizedBox(height: 10),
                          _buildActionBtn("Confirm", _primaryPurple,
                              fontSize: 18, onTap: _showSignaturePopup),
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
        color: _bgGrey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                _timerRunning ? "Pause" : "Start",
                _timerRunning ? _penaltyRed : _startGreen,
                fontSize: 24,
                onTap: () {
                  setState(() {
                    _timerRunning = !_timerRunning;
                    if (_timerRunning) {
                      _startTimer();
                    } else {
                      _stopwatchTimer?.cancel();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildActionBtn(
                "Reset",
                _resetPurple,
                fontSize: 24,
                onTap: () {
                  setState(() {
                    _stopwatchTimer?.cancel();
                    _timerRunning = false;
                    _elapsedSeconds = 0;
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
  // DROPDOWNS
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
            decoration: BoxDecoration(color: _inputGrey, borderRadius: BorderRadius.circular(5)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TimerCategoryInfo>(
                isExpanded: true,
                value: _selectedCategory,
                hint: const Text('Select Category', style: TextStyle(fontSize: 12)),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                onChanged: (val) => setState(() => _selectedCategory = val),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.categoryType, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ),
          ),
          const Positioned(
            top: -12, left: 5,
            child: Text("CATEGORY",
                style: TextStyle(color: _primaryPurple, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: _inputGrey, borderRadius: BorderRadius.circular(5)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TimerRoundInfo>(
                isExpanded: true,
                value: _selectedRound,
                hint: const Text('Select Competition Info', style: TextStyle(fontSize: 12)),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                onChanged: (val) => setState(() => _selectedRound = val),
                items: _rounds
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.roundType, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ),
          ),
          const Positioned(
            top: -12, left: 5,
            child: Text("COMPETITION INFO",
                style: TextStyle(color: _primaryPurple, fontWeight: FontWeight.bold, fontSize: 10)),
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
                color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 24, fontStyle: FontStyle.italic)),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
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
            decoration: BoxDecoration(color: _inputGrey, borderRadius: BorderRadius.circular(5)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
          Positioned(
            top: -12, left: 5,
            child: Text(label,
                style: const TextStyle(
                    color: _primaryPurple, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
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
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(label,
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// GEOMETRIC BACKGROUND PAINTER
// ─────────────────────────────────────────────
class TimerGeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final List<List<Offset>> polygons = [
      [const Offset(0, 0), Offset(size.width * 0.45, 0), Offset(size.width * 0.25, size.height * 0.15), Offset(0, size.height * 0.1)],
      [Offset(0, size.height * 0.1), Offset(size.width * 0.25, size.height * 0.15), Offset(0, size.height * 0.35)],
      [Offset(size.width * 0.45, 0), Offset(size.width, 0), Offset(size.width * 0.75, size.height * 0.18)],
      [Offset(size.width * 0.45, 0), Offset(size.width * 0.75, size.height * 0.18), Offset(size.width * 0.25, size.height * 0.15)],
      [Offset(0, size.height * 0.35), Offset(size.width * 0.25, size.height * 0.15), Offset(size.width * 0.6, size.height * 0.4), Offset(size.width * 0.1, size.height * 0.55)],
      [Offset(size.width * 0.75, size.height * 0.18), Offset(size.width, size.height * 0.4), Offset(size.width * 0.6, size.height * 0.4)],
      [Offset(size.width, size.height * 0.4), Offset(size.width, size.height * 0.8), Offset(size.width * 0.65, size.height * 0.6)],
      [Offset(0, size.height * 0.55), Offset(size.width * 0.35, size.height * 0.75), Offset(0, size.height * 0.9)],
    ];
    for (int i = 0; i < polygons.length; i++) {
      paint.color = const Color(0xFFD6D6E5).withOpacity(0.12 + (i % 3 * 0.08));
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}