import 'package:flutter/material.dart';
import 'package:roboventure/main.dart';
import 'main_menu_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F0FF),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF5B2D8E), Color(0xFF8B5BBE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'ROBOVENTURE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        'Competition Dashboard',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white.withOpacityValue(0.2),
                    child: const Icon(Icons.person, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7B2FBE), Color(0xFF9B59B6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B2FBE).withOpacityValue(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Welcome!',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Select a Competition',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Tap a competition below to\nview its categories.',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacityValue(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emoji_events,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),
                    _sectionLabel('COMPETITIONS'),
                    const SizedBox(height: 14),

                    _CompetitionCard(
                      title: 'Aspiring Makers',
                      subtitle: 'Qualification & Championship rounds',
                      icon: Icons.build_circle_outlined,
                      accentColor: const Color(0xFF7B2FBE),
                      statusLabel: 'ACTIVE',
                      statusColor: const Color(0xFF2ECC71),
                      isLocked: false,
                      onTap: () => _navigateToMenu(context, 'ASPIRING MAKERS', const Color(0xFF7B2FBE)),
                    ),

                    const SizedBox(height: 12),

                    _CompetitionCard(
                      title: 'Emerging Innovators',
                      subtitle: 'Intermediate logic and design',
                      icon: Icons.lightbulb_outline,
                      accentColor: const Color(0xFF3498DB),
                      statusLabel: 'ACTIVE',
                      statusColor: const Color(0xFF2ECC71),
                      isLocked: false,
                      onTap: () => _navigateToMenu(context, 'EMERGING INNOVATORS', const Color(0xFF3498DB)),
                    ),

                    const SizedBox(height: 12),

                    _CompetitionCard(
                      title: 'Line Tracing',
                      subtitle: 'High-speed precision racing',
                      icon: Icons.route_outlined,
                      accentColor: const Color(0xFFE67E22),
                      statusLabel: 'ACTIVE',
                      statusColor: const Color(0xFF2ECC71),
                      isLocked: false,
                      onTap: () => _navigateToMenu(context, 'LINE TRACING', const Color(0xFFE67E22)),
                    ),

                    const SizedBox(height: 12),

                    const _CompetitionCard(
                      title: 'Navigation',
                      subtitle: 'Coming soon — not yet available',
                      icon: Icons.explore_outlined,
                      accentColor: Color(0xFF27AE60),
                      statusLabel: 'SOON',
                      statusColor: Color(0xFF95A5A6),
                      isLocked: true,
                    ),

                    const SizedBox(height: 12),

                    const _CompetitionCard(
                      title: 'Soccer',
                      subtitle: 'Coming soon — not yet available',
                      icon: Icons.sports_soccer_outlined,
                      accentColor: Color(0xFFE74C3C),
                      statusLabel: 'SOON',
                      statusColor: Color(0xFF95A5A6),
                      isLocked: true,
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Bottom logos ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                children: const [
                  _LogoBadge(label: 'Makebook', color: Color(0xFFE67E22)),
                  _LogoBadge(label: 'CREOTEC', color: Color(0xFF2ECC71)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToMenu(BuildContext context, String title, Color color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MainMenuScreen(
          competitionTitle: title,
          accentColor: color,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Row(
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
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF5B2D8E),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ── Competition Card ──────────────────────────────────────────────────────────

class _CompetitionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String statusLabel;
  final Color statusColor;
  final bool isLocked;
  final VoidCallback? onTap;

  const _CompetitionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.statusLabel,
    required this.statusColor,
    this.isLocked = false,
    this.onTap,
  });

  @override
  State<_CompetitionCard> createState() => _CompetitionCardState();
}

class _CompetitionCardState extends State<_CompetitionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.isLocked ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: widget.isLocked ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.isLocked
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onTap?.call();
              },
        onTapCancel: widget.isLocked ? null : () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Opacity(
            opacity: widget.isLocked ? 0.5 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.isLocked
                      ? const Color(0xFFE0DCF0)
                      : widget.accentColor.withOpacityValue(0.35),
                  width: 1.5,
                ),
                boxShadow: widget.isLocked
                    ? []
                    : [
                        BoxShadow(
                          color: widget.accentColor.withOpacityValue(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withOpacityValue(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.isLocked
                          ? const Color(0xFFBDB9C8)
                          : widget.accentColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: widget.isLocked
                                ? const Color(0xFFAAAAAA)
                                : const Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF95A5A6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.statusColor.withOpacityValue(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.statusLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: widget.statusColor,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        widget.isLocked
                            ? Icons.lock_outline
                            : Icons.chevron_right,
                        color: widget.isLocked
                            ? const Color(0xFFCCCCCC)
                            : widget.accentColor,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
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