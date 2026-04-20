// ─────────────────────────────────────────────────────────────────────────────
// api_config.dart
// Central API configuration for the RoboVenture app.
// Auto-discovers server IP at runtime via network scan.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // ── Base path ─────────────────────────────────────────────────────────────
  static const String _basePath = '/roboventure_api';

  // ── Runtime base URL (set by init() or refresh()) ─────────────────────────
  static String _baseUrl = '';
  static String get baseUrl => _baseUrl;

  /// True if a valid server has been found.
  static bool get isConnected => _baseUrl.isNotEmpty;

  // ── Auto-discovery ────────────────────────────────────────────────────────

  /// Call once in main.dart before runApp().
  /// Tries cached server first, then scans the local network if stale.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('roboventure_server');

    // 1. Try last known working URL first (instant if still valid)
    if (cached != null && await _isRoboventureServer(cached)) {
      _baseUrl = cached;
      debugPrint('[ApiConfig] Using cached server: $_baseUrl');
      return;
    }

    // Cached URL is stale (network changed) — clear it and scan fresh
    await prefs.remove('roboventure_server');
    _baseUrl = '';

    // 2. Scan the local network for the server
    debugPrint('[ApiConfig] Scanning network for RoboVenture server...');
    final found = await _scanNetwork();
    if (found != null) {
      _baseUrl = found;
      await prefs.setString('roboventure_server', found);
      debugPrint('[ApiConfig] Found server: $_baseUrl');
      return;
    }

    debugPrint('[ApiConfig] No server found!');
  }

  /// Call this from LoadingScreen every time it mounts.
  /// Forces a fresh scan — ignores cache entirely.
  /// Use this so switching hotspots is detected without a hot restart.
  static Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('roboventure_server');
    _baseUrl = '';

    debugPrint('[ApiConfig] Refreshing — scanning network...');
    final found = await _scanNetwork();
    if (found != null) {
      _baseUrl = found;
      await prefs.setString('roboventure_server', found);
      debugPrint('[ApiConfig] Refresh found server: $_baseUrl');
    } else {
      debugPrint('[ApiConfig] Refresh found no server.');
    }
  }

  /// Pings all IPs on the subnet simultaneously to find the server.
  static Future<String?> _scanNetwork() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final subnet =
                addr.address.substring(0, addr.address.lastIndexOf('.'));

            // Ping all 254 IPs simultaneously
            final futures = List.generate(254, (i) {
              final ip = '$subnet.${i + 1}';
              return _isRoboventureServer('http://$ip$_basePath')
                  .then((ok) => ok ? 'http://$ip$_basePath' : null);
            });

            final results = await Future.wait(futures);
            return results.firstWhere((r) => r != null, orElse: () => null);
          }
        }
      }
    } catch (e) {
      debugPrint('[ApiConfig] Scan error: $e');
    }
    return null;
  }

  /// Returns true if the given base URL responds as the RoboVenture server.
  static Future<bool> _isRoboventureServer(String base) async {
    try {
      final res = await http
          .get(Uri.parse('$base/ping.php'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['app'] == 'roboventure';
      }
    } catch (_) {}
    return false;
  }

  // ── Endpoints ─────────────────────────────────────────────────────────────

  /// dashboard.dart  →  _fetchCategories()
  static String get getCategories => '$_baseUrl/get_categories.php';

  /// qualification_schedule_screen.dart  →  _ScheduleApiService.fetchArenas()
  static String get getArena => '$_baseUrl/get_arena.php';

  /// qualification_schedule_screen.dart  →  _ScheduleApiService.fetchSchedule()
  static String get getTeamSchedule => '$_baseUrl/get_teamschedule.php';

  /// qualification_schedule_screen.dart  →  _ScheduleApiService.fetchScoredMatchIds()
  static String get getScoredMatches => '$_baseUrl/get_scored_matches.php';

  /// scoring.dart  →  ScoringApiService (all actions)
  static String get scoring => '$_baseUrl/score_submit.php';

  /// championship_sched.dart  →  _ChampApiService.fetchScoredMatchIds()
  static String get getScoredChampionshipMatches =>
      '$_baseUrl/get_scored_championship_matches.php';

  /// championship_sched.dart  →  _ChampApiService.fetchGroupCount()
  /// GET ?category_id=N  →  { "group_count": N }
  static String get getGroupCount => '$_baseUrl/group_count.php';

  /// championship_sched.dart / get_score.php
  /// GET ?category_id=N | ?match_id=N | ?category_id=N&bracket_type=`<round>`
  static String get getScore => '$_baseUrl/get_score.php';

  static String get advanceKnockout => '$_baseUrl/advance_knockout.php';

  static String get cleanupChampionshipSeeds =>
      '$_baseUrl/championship_seeds_reset.php';

  /// qualification_sched.dart → _ScheduleApiService.fetchGroupStandings()
  /// GET ?category_id=N  →  [ { group_label, team_id, team_name, mp, w, d, l, gf, ga, gd, pts } ]
  static String get getGroupStandings => '$_baseUrl/group_standings.php';

  static String get getChampionshipMatchShells =>
      '$_baseUrl/get_championship_match_shells.php';
}