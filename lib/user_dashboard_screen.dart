import 'package:flutter/material.dart';
import 'package:roboventure/main.dart';
import 'qualification_schedule_screen.dart';

/// Which button was tapped on the Main Menu
enum DashboardMode { qualification, championship }

class UserDashboardScreen extends StatelessWidget {
  final DashboardMode mode;

  const UserDashboardScreen({
    super.key,
    required this.mode,
  });

  String get _title =>
      mode == DashboardMode.qualification ? 'QUALIFICATION' : 'CHAMPIONSHIP';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F0FF),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF5B2D8E), Color(0xFF8B5BBE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacityValue(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacityValue(0.4),
                            width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.chevron_left,
                              color: Colors.white, size: 18),
                          SizedBox(width: 2),
                          Text(
                            'MAIN MENU',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  // Spacer mirror for centering title
                  const SizedBox(width: 90),
                ],
              ),
            ),

            // ── Section label ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacityValue(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B2FBE),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'CATEGORIES',
                    style: TextStyle(
                      color: Color(0xFF5B2D8E),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: _CategoriesBody(mode: mode),
            ),

            // ── Bottom logos ────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacityValue(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LogoBadge(
                      label: 'Makebook', color: const Color(0xFFE67E22)),
                  _LogoBadge(
                      label: 'CREOTEC', color: const Color(0xFF2ECC71)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Categories Body ───────────────────────────────────────────────────────────

class _CategoriesBody extends StatelessWidget {
  final DashboardMode mode;
  const _CategoriesBody({required this.mode});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> categories = [
      {
        'name': 'Aspiring Makers',
        'icon': Icons.build_circle_outlined,
        'color': const Color(0xFF7B2FBE),
        'active': true,
      },
      {
        'name': 'Emerging Innovators',
        'icon': Icons.lightbulb_outline,
        'color': const Color(0xFF3498DB),
        'active': false,
      },
      {
        'name': 'Line Tracing',
        'icon': Icons.route_outlined,
        'color': const Color(0xFFE67E22),
        'active': false,
      },
      {
        'name': 'Navigation',
        'icon': Icons.explore_outlined,
        'color': const Color(0xFF27AE60),
        'active': false,
      },
      {
        'name': 'Soccer',
        'icon': Icons.sports_soccer_outlined,
        'color': const Color(0xFFE74C3C),
        'active': false,
      },
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final bool active = cat['active'] as bool;
        final String name = cat['name'] as String;
        final Color themeColor = cat['color'] as Color;

        return _CategoryCard(
          name: name,
          icon: cat['icon'] as IconData,
          color: themeColor,
          isActive: active,
          onTap: active && mode == DashboardMode.qualification
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QualificationScheduleScreen(
                        // FIX: Pass the required data to the next screen
                        competitionTitle: name,
                        themeColor: themeColor,
                      ),
                    ),
                  );
                }
              : null,
        );
      },
    );
  }
}

// ── Category Card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final String name;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;

  const _CategoryCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.isActive,
    this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.isActive;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            },
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Opacity(
          opacity: disabled ? 0.45 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: disabled
                    ? const Color(0xFFE0DCF0)
                    : widget.color.withOpacityValue(0.35),
                width: 1.5,
              ),
              boxShadow: disabled
                  ? []
                  : [
                      BoxShadow(
                        color: widget.color.withOpacityValue(0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacityValue(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.icon,
                    color: disabled ? const Color(0xFFBDB9C8) : widget.color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),

                // Name
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: disabled
                          ? const Color(0xFFAAAAAA)
                          : const Color(0xFF2C3E50),
                    ),
                  ),
                ),

                // Arrow or lock
                Icon(
                  disabled ? Icons.lock_outline : Icons.chevron_right,
                  color: disabled ? const Color(0xFFCCCCCC) : widget.color,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Logo Badge ────────────────────────────────────────────────────────────────

class _LogoBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _LogoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacityValue(0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}