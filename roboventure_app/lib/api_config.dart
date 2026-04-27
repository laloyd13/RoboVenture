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

  /// Call this from LoadingScreen / Retry button.
  /// Forces a fresh scan — ignores cache entirely.
  /// Internally retries up to 3 times with short backoff so the caller
  /// only needs to tap Retry once even on a freshly joined network.
  static Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('roboventure_server');
    _baseUrl = '';

    debugPrint('[ApiConfig] Refreshing — scanning network...');

    // Give the OS a moment to assign an IP after a WiFi switch before
    // we read NetworkInterface (avoids scanning the wrong subnet).
    await Future.delayed(const Duration(milliseconds: 600));

    // Retry the scan up to 3 times with increasing backoff.
    // This way a single tap on "Retry" survives transient failures.
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final found = await _scanNetwork();
      if (found != null) {
        _baseUrl = found;
        await prefs.setString('roboventure_server', found);
        debugPrint('[ApiConfig] Refresh found server (attempt $attempt): $_baseUrl');
        return;
      }
      debugPrint('[ApiConfig] Attempt $attempt/$maxAttempts found no server.');
      if (attempt < maxAttempts) {
        // Short backoff before next attempt (600 ms, 1200 ms)
        await Future.delayed(Duration(milliseconds: 600 * attempt));
      }
    }

    debugPrint('[ApiConfig] Refresh found no server after $maxAttempts attempts.');
  }

  /// Scans all IPs on every active IPv4 subnet and returns the first
  /// URL that responds as the RoboVenture server.
  ///
  /// Uses a Completer so the method returns THE MOMENT the first valid
  /// response arrives — it doesn't wait for all 254 pings to time out.
  static Future<String?> _scanNetwork() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final subnet =
                addr.address.substring(0, addr.address.lastIndexOf('.'));
            debugPrint('[ApiConfig] Scanning subnet $subnet.0/24 ...');

            final result = await _scanSubnet(subnet);
            if (result != null) return result;
          }
        }
      }
    } catch (e) {
      debugPrint('[ApiConfig] Scan error: $e');
    }
    return null;
  }

  /// Pings all 254 hosts on a subnet concurrently and resolves as soon
  /// as the first valid RoboVenture server responds.  Does not block
  /// waiting for the remaining pings to time out.
  static Future<String?> _scanSubnet(String subnet) async {
    final completer = Completer<String?>();
    int pending = 254;

    void onDone() {
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        // All probes finished with no hit.
        completer.complete(null);
      }
    }

    for (int i = 1; i <= 254; i++) {
      final url = 'http://$subnet.$i$_basePath';
      _isRoboventureServer(url).then((ok) {
        if (ok && !completer.isCompleted) {
          completer.complete(url);
        }
        onDone();
      }).catchError((_) { onDone(); return null; });
    }

    return completer.future;
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

  /// qualification_schedule.dart → _ScheduleApiService.fetchTiebreakers()
  /// GET ?category_id=N  →  [ { tiebreaker_id, group_label, team1_id, ... } ]
  static String get getTiebreaker => '$_baseUrl/get_tiebreaker.php';

  /// soccer_scoring.dart → SoccerScoringApiService.saveTiebreakerScore()
  /// POST { tiebreaker_id, team1_score, team2_score, winner_id }
  static String get saveTiebreakerScore => '$_baseUrl/save_tiebreaker_score.php';
}