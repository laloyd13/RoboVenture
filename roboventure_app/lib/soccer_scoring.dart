// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

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
        colorSchemeSeed: const Color(0xFF9B84D1),
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
  int teamAScore = 2;
  int teamAFouls = 0;
  int teamBScore = 1;
  int teamBFouls = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: CustomPaint(
              painter: GeometricBackgroundPainter(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildHeaderSection(),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.black26, thickness: 1),
                    const SizedBox(height: 1),
                    _buildMatchInfoCard(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER & APP BAR ───────────────────────────────────────────

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: const Color(0xFF9B84D1),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () {},
      ),
      title: const Text("BACK", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      actions: [
        const Center(
          child: Padding(
            padding: EdgeInsets.only(right: 16),
            child: Text("00:00", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text("MATCH", style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              width: 55,
              height: 45,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFC8BFE1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1.5),
              ),
              child: const Text("1", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.0)),
            ),
          ],
        ),
        const SizedBox(width: 15),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 14),
              Text(
                'mbot SOCCER Form',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF9B84D1)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── MATCH INFORMATION CONTAINER ────────────────────────────────

  Widget _buildMatchInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
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

          // Info Fields with Stacked labels
          _buildInfoField("COMPETITION TIME", "09:00 AM – 10:30 AM"),
          _buildInfoField("REFEREE NAME", "Lloyd"),
          _buildInfoField("TEAM NAME", "Team A vs Team B"),
          Row(
            children: [
              Expanded(child: _buildInfoField("TEAM ID", "COO1R / COO2R")),
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
          _buildConfirmButton(),
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
                color: const Color(0xFFE8E8E8), 
                borderRadius: BorderRadius.circular(5)),
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          // Label positioned to touch the top border like in scoring.dart
          Positioned(
            top: -12, 
            left: 5, 
            child: Text(label, 
              style: const TextStyle(
                color: Color(0xFF9B84D1), 
                fontWeight: FontWeight.bold, 
                fontSize: 10
              )
            )
          ),
        ],
      ),
    );
  }

  // ── SCORING COLUMNS ────────────────────────────────────────────

  Widget _buildDualScoringSection() {
    return Row(
      children: [
        Expanded(child: _buildTeamScoringColumn("TEAM A", teamAScore, teamAFouls, (v) => setState(() => teamAScore += v), (v) => setState(() => teamAFouls += v))),
        const SizedBox(width: 16),
        Expanded(child: _buildTeamScoringColumn("TEAM B", teamBScore, teamBFouls, (v) => setState(() => teamBScore += v), (v) => setState(() => teamBFouls += v))),
      ],
    );
  }

  Widget _buildTeamScoringColumn(String name, int score, int fouls, Function(int) onScore, Function(int) onFoul) {
    return Column(
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 8),
        _scoringBox("GOAL", score, const Color(0xFF2ECC71), onScore),
        const SizedBox(height: 10),
        _scoringBox("FOUL", fouls, Colors.redAccent, onFoul),
      ],
    );
  }

  Widget _scoringBox(String label, int value, Color color, Function(int) callback) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline, color: Colors.white, size: 20), 
                onPressed: () => callback(-1)
              ),
              Text("$value", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20), 
                onPressed: () => callback(1)
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9B84D1), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        onPressed: () => _showSignaturePopup(),
        child: const Text("CONFIRM", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── SIGNATURE POPUP ─────────────────────────────────

  void _showSignaturePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Color(0xFF9B84D1), borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                const Text("MATCH SUMMARY", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white)),
              ],
            ),
            const Divider(color: Colors.white24, thickness: 1),
            const SizedBox(height: 10),
            const Text(
              "Team A vs Team B",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSummaryItem("1", "MATCH ID"),
                _buildSummaryItem("$teamAScore - $teamBScore", "SCORE"),
                _buildSummaryItem("00:00", "TIME"),
              ],
            ),
            const SizedBox(height: 25),
            _signatureField("CAPTAIN A SIGNATURE", () {}),
            const SizedBox(height: 10),
            _signatureField("CAPTAIN B SIGNATURE", () {}),
            const SizedBox(height: 10),
            _signatureField("REFEREE SIGNATURE", () {}),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      side: const BorderSide(color: Colors.white),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("SAVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ECC71),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("SUBMIT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _signatureField(String label, VoidCallback onClear) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            GestureDetector(onTap: onClear, child: const Icon(Icons.close, color: Colors.white, size: 14)),
          ],
        ),
        Container(
          height: 70,
          width: double.infinity,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        ),
      ],
    );
  }
}

class GeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.45, 0)
      ..lineTo(size.width * 0.25, size.height * 0.15)
      ..close();
    paint.color = const Color(0xFFD6D6E5).withOpacity(0.1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}