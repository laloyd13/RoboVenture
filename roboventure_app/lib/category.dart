// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'qualification_schedule_screen.dart';

class MainMenuScreen extends StatelessWidget {
  final int categoryId;
  final String competitionTitle;
  final Color accentColor;

  const MainMenuScreen({
    super.key,
    required this.categoryId,
    required this.competitionTitle,
    required this.accentColor,
  });

  static const Color _headerColor = Color(0xFF7D58B3);

  @override
  Widget build(BuildContext context) {
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
                            border: Border.all(color: _headerColor, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.arrow_back_ios, size: 14, color: _headerColor),
                              const SizedBox(width: 4),
                              const Text(
                                "MAIN MENU",
                                style: TextStyle(
                                  color: _headerColor,
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

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      _MenuButton(
                        label: 'QUALIFICATION',
                        color: _headerColor,
                        isPrimary: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QualificationScheduleScreen(
                                categoryId: categoryId,
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
                        color: _headerColor,
                        isPrimary: false,
                        isDisabled: true,
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _LogoBadge(imagePath: 'assets/makeblock.png'),
                      _LogoBadge(imagePath: 'assets/CreoLogo.png'),
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
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF9B84D1), Color(0xFF7D58B3)],
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
          color: isDisabled
              ? Colors.grey.withOpacity(0.3)
              : (isPrimary ? color : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDisabled ? Colors.grey.withOpacity(0.3) : color,
            width: 2,
          ),
          boxShadow: isDisabled
              ? []
              : [
                  BoxShadow(
                    color: color.withOpacity(0.3),
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
                  color: isDisabled
                      ? Colors.grey
                      : (isPrimary ? Colors.white : color),
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
  final String imagePath;
  const _LogoBadge({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        imagePath,
        height: 20,
        width: 80,
        fit: BoxFit.contain,
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
      paint.color = const Color(0xFFD6D6E5).withOpacity(0.8 + (i * 0.05));
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}