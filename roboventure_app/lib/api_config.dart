// ─────────────────────────────────────────────────────────────────────────────
// api_config.dart
// Central API configuration for the RoboVenture app.
// ─────────────────────────────────────────────────────────────────────────────

class ApiConfig {
  // ── Server ────────────────────────────────────────────────────────────────
  static const String _host = 'http://175.20.0.63'; // <-- replace with your server IP or hostname

  // ── Base path ─────────────────────────────────────────────────────────────
  static const String _basePath = '/roboventure_api';
  static const String baseUrl = '$_host$_basePath';

  // ── Endpoints ─────────────────────────────────────────────────────────────

  /// dashboard.dart  →  _fetchCategories()
  static const String getCategories  = '$baseUrl/get_categories.php';

  /// qualification_schedule_screen.dart  →  _ScheduleApiService.fetchArenas()
  static const String getArena        = '$baseUrl/get_arena.php';

  /// qualification_schedule_screen.dart  →  _ScheduleApiService.fetchSchedule()
  static const String getTeamSchedule = '$baseUrl/get_teamschedule.php';

  /// qualification_schedule_screen.dart  →  _ScheduleApiService.fetchScoredMatchIds()
  static const String getScoredMatches = '$baseUrl/get_scored_matches.php';

  /// scoring.dart  →  ScoringApiService (all actions)
  static const String scoring         = '$baseUrl/scoring.php';
}