import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; // Ensure path_provider is in pubspec.yaml
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:roboventure/main.dart'; 

void main() {
  runApp(const MaterialApp(
    home: ScoringPage(),
    debugShowCheckedModeBanner: false,
  ));
}

// --- SignaturePad Widget for freehand drawing ---
class SignaturePad extends StatefulWidget {
  final SaveDelegate delegate;
  final String label;

  const SignaturePad({super.key, required this.delegate, required this.label});

  @override
  SignaturePadState createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  // Logic: Use a local reference to points for faster UI updates
  void _handlePanUpdate(DragUpdateDetails details) {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    
    setState(() {
      widget.delegate.addPoint(localPosition);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
              onPressed: () => setState(() => widget.delegate.clear()),
            ),
          ],
        ),
        const SizedBox(height: 5),
        GestureDetector(
          onPanUpdate: _handlePanUpdate,
          onPanEnd: (details) => widget.delegate.addPoint(null),
          child: Container(
            color: Colors.white,
            height: 100,
            width: double.infinity,
            // CustomPaint will now repaint immediately because of setState above
            child: CustomPaint(
              painter: SignaturePainter(points: List.from(widget.delegate.points)),
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
  bool shouldRepaint(SignaturePainter oldDelegate) => oldDelegate.points != points; 
}

class SaveDelegate {
  List<Offset?> points = <Offset?>[];

  void addPoint(Offset? point) {
    points.add(point); 
  }

  void clear() {
    points.clear(); 
  }
}

// Color Palette
const Color primaryPurple = Color(0xFF7B52A1);
const Color badgePurple = Color(0xFFC8BFE1);
const Color accentYellow = Color(0xFFF9D949);
const Color missionBlue = Color(0xFF8BA3C7);
const Color missionGreen = Color(0xFF76A379);
const Color missionPurple = Color(0xFF8789C0);
const Color missionLavender = Color(0xFF9B8CB8);
const Color penaltyRed = Color(0xFFB35D65);
const Color bgGrey = Color(0xFFF0F0F0);
const Color inputGrey = Color(0xFFE8E8E8);
const Color dividerGrey = Color(0xFFD6D6E5);
const Color startGreen = Color(0xFF5E975E);
const Color resetPurple = Color(0xFF79569A);
const Color confirmPurple = Color(0xFF4A2E83);

class ScoringPage extends StatefulWidget {
  const ScoringPage({super.key});

  @override
  State<ScoringPage> createState() => _ScoringPageState();
}

class _ScoringPageState extends State<ScoringPage> {
  final SaveDelegate _captainDelegate = SaveDelegate();
  final SaveDelegate _refereeDelegate = SaveDelegate();

  // Fixed: Diagnostic 'prefer_final_fields'
  final GlobalKey _globalKey = GlobalKey(); 

  Future<void> _saveToGallery() async {
    try {
      RenderRepaintBoundary? boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png); 
      Uint8List pngBytes = byteData!.buffer.asUint8List(); 

      final tempDir = await getTemporaryDirectory(); 
      final file = await File('${tempDir.path}/match_summary_${DateTime.now().millisecondsSinceEpoch}.png').create(); 
      await file.writeAsBytes(pngBytes); 

      // Fixed: Diagnostic 'avoid_print'
      debugPrint('Saved to path: ${file.path}'); 

      // Fixed: Diagnostic 'use_build_context_synchronously'
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Match summary is saved to the gallery"))); 

    } catch (e) {
      debugPrint('Error saving file: $e'); 
    }
  }

  void _showSignaturePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // Use StatefullyBuilder if the parent needs to react, 
        // but for signatures, SignaturePad's internal setState is usually enough.
        return IntrinsicHeight(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: const BoxDecoration(
              color: primaryPurple,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
            ),
            child: Column(
              children: [
                // CLOSE BUTTON ROW
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Text("SINGLE MATCH SUMMARY", 
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                // ... rest of your UI code remains the same
                const SizedBox(height: 10),
                const Text("ST SCHO-BOTICS 1", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Text("C002R", style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryLabel("2", "MATCH"),
                    _buildSummaryLabel("290", "TOTAL SCORE"),
                    _buildSummaryLabel("00:15", "TIME"),
                  ],
                ),
                const SizedBox(height: 30),
                RepaintBoundary(
                  key: _globalKey,
                  child: Column(
                    children: [
                      SignaturePad(delegate: _captainDelegate, label: "CAPTAIN SIGNATURE"),
                      const SizedBox(height: 20),
                      SignaturePad(delegate: _refereeDelegate, label: "REFEREE SIGNATURE"),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  "I confirm that I have examined the scores and am willing to submit them without any alterations.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(child: _buildActionBtn("SAVE", confirmPurple, fontSize: 18, onTap: _saveToGallery)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildActionBtn("SUBMIT", confirmPurple, fontSize: 18, onTap: () => Navigator.pop(context))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryLabel(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, fontStyle: FontStyle.italic)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: primaryPurple,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                  child: const Center(child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16)),
                ),
                const SizedBox(width: 10),
                const Text("BACK", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.5), borderRadius: BorderRadius.circular(10)),
                child: const Row(
                  children: [
                    Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 5),
                    Text("00:00", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
          SliverToBoxAdapter(
            child: CustomPaint(
              painter: GeometricBackgroundPainter(), 
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          children: [
                            const Text("MATCH", style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Container(
                              width: 50, height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: badgePurple, 
                                borderRadius: BorderRadius.circular(10), 
                                border: Border.all(color: Colors.black, width: 1.5)
                              ),
                              child: const Text("1", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 5),
                            child: Text("ASPIRING MAKERS FORM", 
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryPurple)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Divider(color: Colors.black26, thickness: 1, height: 1),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacityValue(0.05), blurRadius: 10, offset: const Offset(0, 5))]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("MATCH INFORMATION", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                          const SizedBox(height: 20),
                          _buildScoringField("REFEREE NAME", "Rolly"),
                          _buildScoringField("TEAM NAME", "Bossing"),
                          Row(
                            children: [
                              Expanded(child: _buildScoringField("TEAM ID", "C001R")),
                              const SizedBox(width: 15),
                              Expanded(child: _buildScoringDropdown("CATEGORY", "Aspiring Makers")),
                            ],
                          ),
                          _buildScoringDropdown("COMPETITION INFO", "Qualification"),
                          const SizedBox(height: 10),
                          const Text("AUTOMATIC MISSION", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                          const Divider(height: 30),
                          _buildMissionCard("M01 Line Following", "0", "20", "0", missionBlue),
                          const SizedBox(height: 20),
                          _buildMissionCard("M02 Object Manipulation", "0", "30", "0", missionGreen.withOpacityValue(0.7)),
                          const SizedBox(height: 20),
                          _buildMissionCard("M03 Fruit Collection", "0", "20", "0", missionPurple.withOpacityValue(0.7)),
                          const SizedBox(height: 20),
                          _buildMissionCard("M04 Yield Management", "0", "30", "0", missionLavender.withOpacityValue(0.7)),
                          const SizedBox(height: 30),
                          const Text("PENALTY", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                          const Divider(height: 30),
                          _buildMissionCard("VIOLATION", "0", "0", "0", penaltyRed),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.grey.shade100),
                              ),
                              const SizedBox(width: 10),
                              const Text("Disqualified", style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 30),
                          const Text("SINGLE MATCH SCORE", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                          const SizedBox(height: 20),
                          _buildScoreRow("Independent Score", "0"),
                          _buildScoreRow("Violation", "0"),
                          _buildScoreRow("Total Score", "0"),
                          _buildScoreRow("Competition Time", "00:00"),
                          const SizedBox(height: 30),
                          _buildActionBtn("Confirm", primaryPurple, fontSize: 18, onTap: _showSignaturePopup),
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
      bottomNavigationBar: Container(
        color: bgGrey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            Expanded(child: _buildActionBtn("Start", startGreen, fontSize: 24, onTap: (){})),
            const SizedBox(width: 15),
            Expanded(child: _buildActionBtn("Reset", resetPurple, fontSize: 24, onTap: (){})),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _buildMissionCard(String title, String qty, String points, String total, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCounterBtn(Icons.remove),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                width: 90, height: 90,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Text(qty, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              ),
              _buildCounterBtn(Icons.add),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: accentYellow, borderRadius: BorderRadius.circular(5)),
            child: const Text("Quantity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildScoreLabel(points, "Points / Each"),
              _buildScoreLabel(total, "Total Score"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreLabel(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 9)),
      ],
    );
  }

  Widget _buildScoreRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: primaryPurple, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(color: primaryPurple, fontWeight: FontWeight.bold)),
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
            decoration: BoxDecoration(color: inputGrey, borderRadius: BorderRadius.circular(5)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 16)),
          ),
          Positioned(top: -12, left: 5, child: Text(label, style: const TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 10))),
        ],
      ),
    );
  }

  Widget _buildScoringDropdown(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 45,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: inputGrey, borderRadius: BorderRadius.circular(5)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value, style: const TextStyle(fontSize: 14)),
                const Icon(Icons.arrow_drop_down, color: Colors.black54),
              ],
            ),
          ),
          Positioned(top: -12, left: 5, child: Text(label, style: const TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 10))),
        ],
      ),
    );
  }

  Widget _buildCounterBtn(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(color: accentYellow, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.black, size: 24),
    );
  }

  Widget _buildActionBtn(String label, Color color, {double fontSize = 24, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, height: 55,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class GeometricBackgroundPainter extends CustomPainter {
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
      paint.color = const Color(0xFFD6D6E5).withOpacityValue(0.12 + (i % 3 * 0.08));
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}