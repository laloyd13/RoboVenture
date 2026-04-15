// ─────────────────────────────────────────────────────────────────────────────
// api_config.dart
// Central API configuration for the RoboVenture app.
// ─────────────────────────────────────────────────────────────────────────────

class ApiConfig {
  // ── Server ────────────────────────────────────────────────────────────────
  static const String _host = 'http://192.168.254.103'; // <-- replace with your server IP or hostname

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

  /// championship_sched.dart  →  _ChampApiService.fetchScoredMatchIds()
  static const String getScoredChampionshipMatches = '$baseUrl/get_scored_championship_matches.php';

  /// championship_sched.dart  →  _ChampApiService.fetchGroupCount()
  /// GET ?category_id=N  →  { "group_count": N }
  static const String getGroupCount = '$baseUrl/get_group_count.php';

  /// championship_sched.dart / get_score.php
  /// GET ?category_id=N | ?match_id=N | ?category_id=N&bracket_type=`<round>`
  static const String getScore = '$baseUrl/get_score.php';

  static const String advanceKnockout = '$baseUrl/advance_knockout.php';

  static const String cleanupChampionshipSeeds = '$baseUrl/cleanup_champ_seeds.php';

  /// qualification_sched.dart → _ScheduleApiService.fetchGroupStandings()
  /// GET ?category_id=N  →  [ { group_label, team_id, team_name, mp, w, d, l, gf, ga, gd, pts } ]
  static const String getGroupStandings = '$baseUrl/get_group_standings.php';

  static const String getChampionshipMatchShells = '$baseUrl/get_championship_match_shells.php';
}