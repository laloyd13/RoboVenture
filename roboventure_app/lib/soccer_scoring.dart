// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'dart:async';

// ─────────────────────────────────────────────
// COLOR PALETTE — matches scoring.dart
// ─────────────────────────────────────────────
const Color primaryPurple  = Color(0xFF7D58B3);
const Color badgePurple    = Color(0xFFC8BFE1);
const Color bgGrey         = Color(0xFFF0F0F0);
const Color inputGrey      = Color(0xFFE8E8E8);
const Color saveGreen      = Color(0xFF5E975E);
const Color confirmPurple  = Color(0xFF3B1F6E);
const Color pauseRed       = Color(0xFFB35D65);
const Color startGreen     = Color(0xFF5E975E);
const Color resetPurple    = Color(0xFF79569A);
const Color goalGreen      = Color(0xFF2ECC71);
const Color foulRed        = Color(0xFFB35D65);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: primaryPurple,
      ),
      home: const SoccerScorerUI(),
    );
  }
}

class SoccerScorerUI extends StatefulWidget {
  const SoccerScorerUI({super.key});

  @override
  State<SoccerScorerUI> createState() => _SoccerScorerUIState();
}

class _SoccerScorerUIState extends State<SoccerScorerUI> {
  int teamAScore = 0;
  int teamAFouls = 0;
  int teamBScore = 0;
  int teamBFouls = 0;

  // ── Timer state — matches scoring.dart ──
  bool _timerRunning = false;
  int _remainingSeconds = 300; // 5:00 minutes for soccer
  final int _totalSeconds = 300;
  Timer? _countdownTimer;

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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildHeaderSection(),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.black26, thickness: 1, height: 1),
                    const SizedBox(height: 10),
                    _buildMatchInfoCard(),
                    const SizedBox(height: 30),
                  ],
                ),
            ),
          ),  // SliverToBoxAdapter
        ],  // slivers
      ),  // CustomScrollView

      // ── BOTTOM TIMER BUTTONS — matches scoring.dart ──
      bottomNavigationBar: Container(
        color: bgGrey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                _timerRunning ? "Pause" : "Start",
                _timerRunning ? pauseRed : startGreen,
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
                resetPurple,
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

  // ── APP BAR — circle back button + bordered timer like scoring.dart ──
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: primaryPurple,
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
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: primaryPurple, size: 12),
              ),
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
        // Bordered timer — matches scoring.dart style
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: _remainingSeconds <= 30 ? Colors.redAccent : Colors.white,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_outlined,
                  color: _remainingSeconds <= 30
                      ? Colors.redAccent
                      : Colors.white,
                  size: 20),
              const SizedBox(width: 5),
              Text(
                _timerDisplay,
                style: TextStyle(
                  color: _remainingSeconds <= 30
                      ? Colors.redAccent
                      : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── HEADER — match badge + form title ──
  Widget _buildHeaderSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 1.5),
              ),
              child: const Text("1",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(width: 15),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: 5),
            child: Text(
              'mbot SOCCER FORM',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryPurple),
            ),
          ),
        ),
      ],
    );
  }

  // ── MATCH INFO CARD ──
  Widget _buildMatchInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5)),
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
          _buildInfoField("COMPETITION TIME", "09:00 AM – 10:30 AM"),
          _buildInfoField("REFEREE NAME", "Lloyd"),
          _buildInfoField("TEAM NAME", "Team A vs Team B"),
          Row(
            children: [
              Expanded(child: _buildInfoField("TEAM ID", "C001R / C002R")),
              const SizedBox(width: 10),
              Expanded(child: _buildInfoField("CATEGORY", "mbot Soccer")),
            ],
          ),
          _buildInfoField("COMPETITION INFO", "Qualification"),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Colors.black12, thickness: 1),
          ),
          _buildDualScoringSection(),
          const SizedBox(height: 20),
          _buildActionBtn("Confirm", primaryPurple,
              onTap: _showSignaturePopup),
        ],
      ),
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: inputGrey, borderRadius: BorderRadius.circular(5)),
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Positioned(
            top: -12,
            left: 5,
            child: Text(label,
                style: const TextStyle(
                    color: primaryPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ── DUAL SCORING ──
  Widget _buildDualScoringSection() {
    return Row(
      children: [
        Expanded(
          child: _buildTeamScoringColumn(
            "TEAM A", teamAScore, teamAFouls,
            (v) => setState(() => teamAScore = (teamAScore + v).clamp(0, 99)),
            (v) => setState(() => teamAFouls = (teamAFouls + v).clamp(0, 99)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildTeamScoringColumn(
            "TEAM B", teamBScore, teamBFouls,
            (v) => setState(() => teamBScore = (teamBScore + v).clamp(0, 99)),
            (v) => setState(() => teamBFouls = (teamBFouls + v).clamp(0, 99)),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamScoringColumn(
      String name, int score, int fouls,
      Function(int) onScore, Function(int) onFoul) {
    return Column(
      children: [
        Text(name,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black54,
                fontSize: 12)),
        const SizedBox(height: 8),
        _scoringBox("GOAL", score, goalGreen, onScore),
        const SizedBox(height: 10),
        _scoringBox("FOUL", fouls, foulRed, onFoul),
      ],
    );
  }

  Widget _scoringBox(
      String label, int value, Color color, Function(int) callback) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white, size: 20),
                onPressed: () => callback(-1),
              ),
              Text("$value",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline,
                    color: Colors.white, size: 20),
                onPressed: () => callback(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ACTION BUTTON — matches scoring.dart _buildActionBtn ──
  Widget _buildActionBtn(String label, Color color,
      {double fontSize = 18, required VoidCallback onTap}) {
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

  // ── SIGNATURE POPUP — matches scoring.dart layout exactly ──
  void _showSignaturePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: const BoxDecoration(
              color: primaryPurple,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(25),
                topRight: Radius.circular(25),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Title + X on same row with divider below ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 48),
                    const Text(
                      "MATCH SUMMARY",
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

                // ── Team name ──
                const Text(
                  "Team A vs Team B",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),

                // ── Summary row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryItem("1", "MATCH ID"),
                    _buildSummaryItem("$teamAScore - $teamBScore", "SCORE"),
                    _buildSummaryItem(_timerDisplay, "TIME"),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Signature fields with rounded pads ──
                _signatureField("CAPTAIN A SIGNATURE"),
                const SizedBox(height: 10),
                _signatureField("CAPTAIN B SIGNATURE"),
                const SizedBox(height: 10),
                _signatureField("REFEREE SIGNATURE"),
                const SizedBox(height: 20),

                const Text(
                  "I confirm that I have examined the scores and am willing to submit them without any alterations.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // ── SAVE / SUBMIT buttons — matches scoring.dart colors ──
                Row(
                  children: [
                    Expanded(
                      child: _buildActionBtn(
                        "SAVE",
                        saveGreen,
                        onTap: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildActionBtn(
                        "SUBMIT",
                        confirmPurple,
                        onTap: () => Navigator.pop(ctx),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic)),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Signature field with rounded white pad — matches scoring.dart ──
  Widget _signatureField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 120,
            width: double.infinity,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class GeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final List<List<Offset>> polygons = [
      [
        const Offset(0, 0),
        Offset(size.width * 0.45, 0),
        Offset(size.width * 0.25, size.height * 0.15),
        Offset(0, size.height * 0.1),
      ],
      [
        Offset(0, size.height * 0.1),
        Offset(size.width * 0.25, size.height * 0.15),
        Offset(0, size.height * 0.35),
      ],
      [
        Offset(size.width * 0.45, 0),
        Offset(size.width, 0),
        Offset(size.width * 0.75, size.height * 0.18),
      ],
      [
        Offset(size.width * 0.45, 0),
        Offset(size.width * 0.75, size.height * 0.18),
        Offset(size.width * 0.25, size.height * 0.15),
      ],
    ];

    for (int i = 0; i < polygons.length; i++) {
      paint.color = const Color(0xFFD6D6E5).withOpacity((0.12 + (i % 3) * 0.08).clamp(0.0, 1.0));
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}