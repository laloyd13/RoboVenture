import 'package:flutter/material.dart';
import 'dashboard.dart';

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

void main() {
  runApp(const RoboVentureApp());
}

class RoboVentureApp extends StatelessWidget {
  const RoboVentureApp({super.key});

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
      home: const DashboardScreen(), // ← Landing point is now the Dashboard
    );
  }
}