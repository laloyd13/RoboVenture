// ignore_for_file: unused_field, deprecated_member_use

import 'package:flutter/material.dart';
import 'qualification_sched.dart';
import 'championship_sched.dart';

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

  bool get _isSoccerCategory =>
      competitionTitle.toLowerCase().contains('soccer') ||
      competitionTitle.toLowerCase().contains('football');

  @override
  Widget build(BuildContext context) {
    List<String> words = competitionTitle.split(' ');
    String firstLine = words.isNotEmpty ? words[0].toUpperCase() : '';
    String secondLine =
        words.length > 1 ? words.sublist(1).join(' ').toUpperCase() : '';

    return Scaffold(
      backgroundColor: const Color(0xFFE8E8F0),
      body: Stack(
        children: [
          Positioned.fill(
              child: CustomPaint(painter: GeometricBackgroundPainter())),

          Positioned(
            top: -60,
            left: -60,
            right: -60,
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.8,
                  colors: [
                    accentColor.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── TOP BAR ──────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: accentColor, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.arrow_back_ios_new_rounded,
                                  size: 13, color: accentColor),
                              const SizedBox(width: 5),
                              Text(
                                "MAIN MENU",
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Category type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: accentColor.withOpacity(0.3), width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isSoccerCategory
                                  ? Icons.sports_soccer
                                  : Icons.precision_manufacturing_outlined,
                              size: 13,
                              color: accentColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isSoccerCategory ? 'SOCCER' : 'ROBOTICS',
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ── TITLE ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: accentColor.withOpacity(0.25), width: 1),
                        ),
                        child: Text(
                          'COMPETITION CATEGORY',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      _buildGradientText(firstLine, 48),
                      if (secondLine.isNotEmpty)
                        _buildGradientText(secondLine, 56),

                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 30, height: 2,
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                  color: accentColor, shape: BoxShape.circle),
                            ),
                            Container(
                              width: 30, height: 2,
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                // ── MENU BUTTONS ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      // Section label
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Icon(Icons.tune_rounded,
                                size: 13, color: Colors.black45),
                            const SizedBox(width: 6),
                            const Text(
                              'SELECT MODE',
                              style: TextStyle(
                                color: Colors.black45,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      _MenuButton(
                        label: 'QUALIFICATION',
                        icon: Icons.format_list_numbered_rounded,
                        color: accentColor,
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
                      const SizedBox(height: 14),
                      _MenuButton(
                        label: 'CHAMPIONSHIP',
                        icon: Icons.emoji_events_rounded,
                        color: accentColor,
                        isPrimary: false,
                        isDisabled: !_isSoccerCategory,
                        onTap: _isSoccerCategory
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChampionshipScheduleScreen(
                                      categoryId: categoryId,
                                      competitionTitle: competitionTitle,
                                      themeColor: accentColor,
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ── LOGOS ─────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _LogoBadge(imagePath: 'assets/RV_logo.png'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
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
      shaderCallback: (bounds) => LinearGradient(
        colors: [accentColor.withOpacity(0.75), accentColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
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

// ─────────────────────────────────────────────
// MENU BUTTON
// ─────────────────────────────────────────────
class _MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isPrimary;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _MenuButton({
    required this.label,
    required this.icon,
    required this.color,
    this.isPrimary = false,
    this.isDisabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isDisabled ? Colors.grey.shade400 : color;

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        decoration: BoxDecoration(
          color: isDisabled
              ? Colors.grey.withOpacity(0.12)
              : (isPrimary ? color : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDisabled
                ? Colors.grey.withOpacity(0.25)
                : color,
            width: isPrimary ? 0 : 2,
          ),
          boxShadow: isDisabled
              ? []
              : [
                  BoxShadow(
                    color: color.withOpacity(isPrimary ? 0.35 : 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.grey.withOpacity(0.15)
                    : (isPrimary
                        ? Colors.white.withOpacity(0.2)
                        : color.withOpacity(0.1)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDisabled ? Icons.lock_outline_rounded : icon,
                size: 18,
                color: isDisabled
                    ? Colors.grey.shade400
                    : (isPrimary ? Colors.white : color),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isDisabled
                      ? Colors.grey.shade400
                      : (isPrimary ? Colors.white : color),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDisabled
                  ? Colors.grey.shade300
                  : (isPrimary
                      ? Colors.white.withOpacity(0.6)
                      : effectiveColor.withOpacity(0.4)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LOGO BADGE
// ─────────────────────────────────────────────
class _LogoBadge extends StatelessWidget {
  final String imagePath;
  const _LogoBadge({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 6,
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

// ─────────────────────────────────────────────
// GEOMETRIC BACKGROUND PAINTER
// ─────────────────────────────────────────────
class GeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final List<List<Offset>> polygons = [
      [
        const Offset(0, 0),
        Offset(size.width * 0.4, 0),
        Offset(size.width * 0.2, size.height * 0.25),
        Offset(0, size.height * 0.15)
      ],
      [
        Offset(size.width * 0.4, 0),
        Offset(size.width, 0),
        Offset(size.width, size.height * 0.3),
        Offset(size.width * 0.6, size.height * 0.1)
      ],
      [
        Offset(0, size.height * 0.15),
        Offset(size.width * 0.2, size.height * 0.25),
        Offset(size.width * 0.15, size.height * 0.55),
        Offset(0, size.height * 0.45)
      ],
      [
        Offset(size.width * 0.2, size.height * 0.25),
        Offset(size.width * 0.6, size.height * 0.1),
        Offset(size.width * 0.75, size.height * 0.4),
        Offset(size.width * 0.4, size.height * 0.5)
      ],
      [
        Offset(size.width * 0.7, size.height * 0.75),
        Offset(size.width, size.height * 0.6),
        Offset(size.width, size.height),
        Offset(size.width * 0.5, size.height),
      ],
    ];

    final opacities = [0.80, 0.85, 0.78, 0.82, 0.70];
    for (int i = 0; i < polygons.length; i++) {
      paint.color = const Color(0xFFD6D6E5).withOpacity(opacities[i]);
      final path = Path()..addPolygon(polygons[i], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}