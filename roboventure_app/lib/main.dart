import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Timeout duration
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // App moved to background / recent apps — start the countdown
      _bgTimer?.cancel();
      _bgTimer = Timer(_bgTimeout, () {
        SystemNavigator.pop();
      });
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground — cancel the countdown
      _bgTimer?.cancel();
      _bgTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboVenture',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'default',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B2FBE)),
        useMaterial3: true,
      ),
      home: const LoadingScreen(),
    );
  }
}