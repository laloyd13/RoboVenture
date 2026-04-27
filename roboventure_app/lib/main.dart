import 'dart:async';
import 'package:flutter/material.dart';
import 'api_config.dart';
import 'splash_screen.dart';

/// Extension to replace deprecated `withOpacity()`
extension ColorX on Color {
  Color withOpacityValue(double opacity) {
    return withValues(
      alpha: (opacity * 255),
      red: r.toDouble(),
      green: g.toDouble(),
      blue: b.toDouble(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Auto-discover the RoboVenture server on the local network
  await ApiConfig.init();

  runApp(const RoboVentureApp());
}

class RoboVentureApp extends StatefulWidget {
  const RoboVentureApp({super.key});

  @override
  State<RoboVentureApp> createState() => _RoboVentureAppState();
}

class _RoboVentureAppState extends State<RoboVentureApp>
    with WidgetsBindingObserver {

  Timer? _bgTimer;
  int    _restartKey   = 0;
  bool   _needsRestart = false;
  bool   _blocking     = false; // Shows a black cover instantly on resume

  static const _bgTimeout = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgTimer?.cancel();
    super.dispose();
  }

  Future<void> _restartApp() async {
    // Show black cover immediately so no old screen is visible
    if (mounted) setState(() => _blocking = true);

    await ApiConfig.init();

    if (mounted) {
      setState(() {
        _restartKey++;
        _needsRestart = false;
        _blocking     = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _bgTimer?.cancel();
      _bgTimer = Timer(_bgTimeout, () {
        _needsRestart = true;
        _bgTimer      = null;
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_needsRestart) {
        // Immediately show the black cover then restart behind it
        _restartApp();
      } else {
        _bgTimer?.cancel();
        _bgTimer = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(_restartKey),
      child: MaterialApp(
        title: 'RoboVenture',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'default',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B2FBE)),
          useMaterial3: true,
        ),
        home: const LoadingScreen(),
        builder: (context, child) {
          return Stack(
            children: [
              ?child,
              // Black cover that blocks the old screen the instant the
              // app is resumed after the 2-min timeout, before the
              // widget tree has had a chance to rebuild.
              if (_blocking)
                const Positioned.fill(
                  child: ColoredBox(color: Colors.black),
                ),
            ],
          );
        },
      ),
    );
  }
}