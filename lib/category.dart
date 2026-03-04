import 'package:flutter/material.dart';
import 'package:roboventure/main.dart';
import 'qualification_schedule_screen.dart';

class MainMenuScreen extends StatelessWidget {
  final String competitionTitle;
  final Color accentColor;

  const MainMenuScreen({
    super.key,
    required this.competitionTitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // Split title into two lines for the design
    List<String> words = competitionTitle.split(' ');
    String firstLine = words.isNotEmpty ? words[0].toUpperCase() : '';
    String secondLine = words.length > 1 ? words.sublist(1).join(' ').toUpperCase() : '';

    return Scaffold(
      backgroundColor: const Color(0xFFE8E8F0),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: GeometricBackgroundPainter())),
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: accentColor, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.arrow_back_ios, size: 14, color: accentColor),
                              const SizedBox(width: 4),
                              Text(
                                "MAIN MENU",
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // Dynamic Header Text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _buildGradientText(firstLine, 48),
                      if (secondLine.isNotEmpty)
                        _buildGradientText(secondLine, 56),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                // Menu Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      _MenuButton(
                        label: 'QUALIFICATION',
                        color: accentColor,
                        isPrimary: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QualificationScheduleScreen(
                                competitionTitle: competitionTitle,
                                themeColor: accentColor,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _MenuButton(
                        label: 'CHAMPIONSHIP',
                        color: accentColor,
                        isPrimary: false,
                        isDisabled: true,
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // Bottom Badges
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _LogoBadge(label: "Makeblock", color: Colors.orange.shade700),
                      _LogoBadge(label: "CREOTEC", color: Colors.blue.shade700),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientText(String text, double fontSize) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [accentColor.withOpacityValue(0.7), accentColor],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontStyle: FontStyle.italic,
          height: 0.9,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isPrimary;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _MenuButton({
    required this.label,
    required this.color,
    this.isPrimary = false,
    this.isDisabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDisabled ? Colors.grey.withOpacityValue(0.1) : (isPrimary ? color : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDisabled ? Colors.grey.withOpacityValue(0.3) : color,
            width: 2,
          ),
          boxShadow: isDisabled ? [] : [
            BoxShadow(
              color: color.withOpacityValue(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isDisabled ? Colors.grey : (isPrimary ? Colors.white : color),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              if (isDisabled) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock_outline, size: 18, color: Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _LogoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacityValue(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}

class GeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final List<List<Offset>> polygons = [
      [const Offset(0, 0), Offset(size.width * 0.4, 0), Offset(size.width * 0.2, size.height * 0.25), Offset(0, size.height * 0.15)],
      [Offset(size.width * 0.4, 0), Offset(size.width, 0), Offset(size.width, size.height * 0.3), Offset(size.width * 0.6, size.height * 0.1)],
      [Offset(0, size.height * 0.15), Offset(size.width * 0.2, size.height * 0.25), Offset(size.width * 0.15, size.height * 0.55), Offset(0, size.height * 0.45)],
      [Offset(size.width * 0.2, size.height * 0.25), Offset(size.width * 0.6, size.height * 0.1), Offset(size.width * 0.75, size.height * 0.4), Offset(size.width * 0.4, size.height * 0.5)],
    ];

    for (int i = 0; i < polygons.length; i++) {
      paint.color = const Color(0xFFD6D6E5).withOpacityValue(0.1 + (i * 0.05));
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}