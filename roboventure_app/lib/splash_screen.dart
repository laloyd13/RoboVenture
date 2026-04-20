// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dashboard.dart';
import 'api_config.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {

  // ── Controllers ────────────────────────────────────────────────────
  late final AnimationController _bgCtrl;       // rotating geometric bg
  late final AnimationController _entryCtrl;    // staggered entry sequence
  late final AnimationController _pulseCtrl;    // logo glow pulse
  late final AnimationController _barCtrl;      // progress bar fill

  // ── Entry animations ───────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset>  _logoSlide;
  late final Animation<double> _taglineFade;
  late final Animation<Offset>  _taglineSlide;
  late final Animation<double> _dotsFade;
  late final Animation<double> _barFade;

  // ── Pulse ──────────────────────────────────────────────────────────
  late final Animation<double> _glowPulse;

  // ── Network check state ────────────────────────────────────────────
  bool _networkError = false;

  // ── Check server reachability ──────────────────────────────────────
  Future<bool> _checkNetwork() async {
    try {
      final response = await http
          .get(Uri.parse(ApiConfig.getCategories))
          .timeout(const Duration(seconds: 6));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();

    // Background slow rotation
    _bgCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 20))
      ..repeat();

    // Entry sequence — 1.8 s total
    _entryCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

    _logoFade  = CurvedAnimation(parent: _entryCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut));
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.30), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl,
            curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic)));
    _logoScale = Tween<double>(begin: 0.75, end: 1.0)
        .animate(CurvedAnimation(parent: _entryCtrl,
            curve: const Interval(0.0, 0.50, curve: Curves.easeOutBack)));

    _taglineFade  = CurvedAnimation(parent: _entryCtrl,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut));
    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl,
            curve: const Interval(0.35, 0.70, curve: Curves.easeOutCubic)));

    _dotsFade = CurvedAnimation(parent: _entryCtrl,
        curve: const Interval(0.55, 0.80, curve: Curves.easeOut));
    _barFade  = CurvedAnimation(parent: _entryCtrl,
        curve: const Interval(0.60, 0.85, curve: Curves.easeOut));

    // Glow pulse — repeating after entry
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _glowPulse = Tween<double>(begin: 0.35, end: 0.75)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Progress bar — fills over 4.5 s then navigates
    _barCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4500));
    _barCtrl.forward();

    _entryCtrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    // Wait for animation to settle, then check network in parallel
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;

    final reachable = await _checkNetwork();
    if (!mounted) return;

    if (!reachable) {
      // Stop the progress bar where it is and show the error overlay
      _barCtrl.stop();
      setState(() => _networkError = true);
      return;
    }

    // Wait out the remainder of the original delay then navigate
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  Future<void> _retry() async {
    setState(() => _networkError = false);
    // Reset and restart the progress bar from zero
    _barCtrl.reset();
    _barCtrl.forward();
    // Re-scan the network for the server before checking reachability
    await ApiConfig.refresh();
    if (!mounted) return;
    final reachable = await _checkNetwork();
    if (!mounted) return;

    if (!reachable) {
      _barCtrl.stop();
      setState(() => _networkError = true);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _barCtrl.dispose();
    super.dispose();
  }

  // ── Background painter ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A1F4E),
      body: Stack(children: [

        // ── Rotating geometric background ──────────────────────────
        AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, _) => CustomPaint(
            painter: _GeoBgPainter(_bgCtrl.value),
            size: MediaQuery.of(context).size,
          ),
        ),

        // ── Radial glow behind logo ────────────────────────────────
        AnimatedBuilder(
          animation: _glowPulse,
          builder: (_, _) => Center(
            child: Container(
              width: 380, height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF7D58B3).withOpacity(_glowPulse.value * 0.65),
                  const Color(0xFF7D58B3).withOpacity(_glowPulse.value * 0.15),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),

        // ── Main content ───────────────────────────────────────────
        SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),

              // ── Logo image ─────────────────────────────────────
              SlideTransition(
                position: _logoSlide,
                child: FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Column(children: [
                      // Logo image asset
                      Image.asset(
                        'assets/RV_logo.png',
                        height: 90,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 20),
                      // Decorative line under logo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GradientLine(width: 48),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD4A017),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          _GradientLine(width: 48),
                        ],
                      ),
                    ]),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Tagline ────────────────────────────────────────
              SlideTransition(
                position: _taglineSlide,
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: Column(children: [
                    const Text(
                      'COMPETITION SCORING SYSTEM',
                      style: TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Powered by CREOTEC',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ]),
                ),
              ),

              const Spacer(flex: 3),

              // ── Animated dots ──────────────────────────────────
              FadeTransition(
                opacity: _dotsFade,
                child: _PulseDots(),
              ),

              const SizedBox(height: 20),

              // ── Progress bar ───────────────────────────────────
              FadeTransition(
                opacity: _barFade,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(children: [
                    AnimatedBuilder(
                      animation: _barCtrl,
                      builder: (_, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: _barCtrl.value,
                          minHeight: 3,
                          backgroundColor:
                              Colors.white.withOpacity(0.18),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFB48EE8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedBuilder(
                      animation: _barCtrl,
                      builder: (_, _) => Text(
                        _networkError
                            ? 'CONNECTION FAILED'
                            : 'LOADING ${(_barCtrl.value * 100).toInt()}%',
                        style: TextStyle(
                          color: _networkError
                              ? const Color(0xFFE57373).withOpacity(0.85)
                              : Colors.white.withOpacity(0.55),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),

        // ── Network error overlay ──────────────────────────────
        if (_networkError)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF2A1F4E).withOpacity(0.92),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFFE57373).withOpacity(0.5),
                                width: 1.5),
                            color: const Color(0xFFE57373).withOpacity(0.08),
                          ),
                          child: const Icon(Icons.wifi_off_rounded,
                              color: Color(0xFFE57373), size: 28),
                        ),
                        const SizedBox(height: 20),
                        // Title
                        const Text(
                          'NO CONNECTION',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Message
                        Text(
                          'Connection Lost\nMake sure both devices are on the same network.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Server address hint
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.10)),
                          ),
                          child: Text(
                            ApiConfig.baseUrl,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 10,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Retry button
                        GestureDetector(
                          onTap: _retry,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 36, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7D58B3),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'RETRY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// GRADIENT LINE DECORATION
// ─────────────────────────────────────────────
class _GradientLine extends StatelessWidget {
  final double width;
  const _GradientLine({required this.width});

  @override
  Widget build(BuildContext context) => Container(
    width: width, height: 1.5,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(1),
      gradient: LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF7D58B3).withOpacity(0.7),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// PULSING DOTS INDICATOR
// ─────────────────────────────────────────────
class _PulseDots extends StatefulWidget {
  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots>
    with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];
  final List<Animation<double>>   _anims = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true);
      // stagger each dot
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted) c.forward();
      });
      _ctrls.add(c);
      _anims.add(Tween<double>(begin: 0.25, end: 1.0)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(5, (i) => AnimatedBuilder(
      animation: _anims[i],
      builder: (_, _) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 5, height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF7D58B3)
              .withOpacity(_anims[i].value),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7D58B3)
                  .withOpacity(_anims[i].value * 0.6),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    )),
  );
}

// ─────────────────────────────────────────────
// GEOMETRIC BACKGROUND PAINTER
// ─────────────────────────────────────────────
class _GeoBgPainter extends CustomPainter {
  final double t; // 0.0 → 1.0, repeating
  _GeoBgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final angle = t * 2 * math.pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Subtle diagonal grid lines
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFF9B78D4).withOpacity(0.10);
    const gridSpacing = 48.0;
    for (double x = -size.height; x < size.width + size.height; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), gridPaint);
      canvas.drawLine(Offset(x + size.height, 0), Offset(x, size.height), gridPaint);
    }

    // Concentric rotating hexagons — much more visible
    final radii     = [size.width * 0.72, size.width * 0.52, size.width * 0.34, size.width * 0.18];
    final opacities = [0.28, 0.38, 0.45, 0.30];
    final widths    = [1.2, 1.5, 1.8, 1.0];
    final speeds    = [1.0, -0.7, 0.5, -1.2];

    for (int r = 0; r < radii.length; r++) {
      paint
        ..color = const Color(0xFF9B78D4).withOpacity(opacities[r])
        ..strokeWidth = widths[r];
      final a = angle * speeds[r];
      final path = Path();
      for (int i = 0; i < 6; i++) {
        final x = cx + radii[r] * math.cos(a + i * math.pi / 3);
        final y = cy + radii[r] * math.sin(a + i * math.pi / 3);
        if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      }
      path.close();
      canvas.drawPath(path, paint);

      // Spoke lines from center to each vertex on outermost hex
      if (r == 0) {
        final spokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = const Color(0xFF9B78D4).withOpacity(0.12);
        for (int i = 0; i < 6; i++) {
          final x = cx + radii[r] * math.cos(a + i * math.pi / 3);
          final y = cy + radii[r] * math.sin(a + i * math.pi / 3);
          canvas.drawLine(Offset(cx, cy), Offset(x, y), spokePaint);
        }
      }
    }

    // Corner triangle accents
    final triPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF7D58B3).withOpacity(0.30);
    final triSize = size.width * 0.18;
    final triOffsets = [
      Offset(size.width * 0.05, size.height * 0.05),
      Offset(size.width * 0.95, size.height * 0.05),
      Offset(size.width * 0.05, size.height * 0.92),
      Offset(size.width * 0.95, size.height * 0.92),
    ];
    for (int ti = 0; ti < triOffsets.length; ti++) {
      final to = triOffsets[ti];
      final ta = angle * (ti.isEven ? 0.3 : -0.3);
      final triPath = Path();
      for (int i = 0; i < 3; i++) {
        final x = to.dx + triSize * math.cos(ta + i * 2 * math.pi / 3);
        final y = to.dy + triSize * math.sin(ta + i * 2 * math.pi / 3);
        if (i == 0) { triPath.moveTo(x, y); } else { triPath.lineTo(x, y); }
      }
      triPath.close();
      canvas.drawPath(triPath, triPaint);
    }

    // Scattered diamond shapes — brighter and larger
    final seed = [
      Offset(size.width * 0.12, size.height * 0.15),
      Offset(size.width * 0.88, size.height * 0.12),
      Offset(size.width * 0.08, size.height * 0.80),
      Offset(size.width * 0.92, size.height * 0.78),
      Offset(size.width * 0.50, size.height * 0.08),
      Offset(size.width * 0.22, size.height * 0.55),
      Offset(size.width * 0.78, size.height * 0.50),
    ];
    final dp = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFD4A017).withOpacity(0.45);
    final dpStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFD4A017).withOpacity(0.55);

    for (final s in seed) {
      final size2 = 6.0 + 3 * math.sin(angle + s.dx * 0.01);
      final path = Path()
        ..moveTo(s.dx, s.dy - size2)
        ..lineTo(s.dx + size2, s.dy)
        ..lineTo(s.dx, s.dy + size2)
        ..lineTo(s.dx - size2, s.dy)
        ..close();
      canvas.drawPath(path, dp);
      canvas.drawPath(path, dpStroke);
    }
  }

  @override
  bool shouldRepaint(_GeoBgPainter old) => old.t != t;
}