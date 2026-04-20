// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'soccer_scoring.dart';
import 'api_config.dart';

// ─────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────
const Color _accentColor = Color(0xFF7D58B3);
const Color _headerMuted = Color(0xFF9E9EAD);


// ─────────────────────────────────────────────
// BRACKET MODE
// Determined by group count fetched from get_group_count.php.
//
//   2 grp → 4 teams  → SF → 3RD/FINAL
//   3 grp → 6 teams  → ELIM(2) → SF → 3RD/FINAL
//   4 grp → 8 teams  → QF → SF → 3RD/FINAL
//   5 grp → 10 teams → ELIM(2) → QF → SF → 3RD/FINAL
//   6 grp → 12 teams → ELIM(4) → QF → SF → 3RD/FINAL
//   7 grp → 14 teams → ELIM(6) → QF → SF → 3RD/FINAL
//   8 grp → 16 teams → R16(8)  → QF → SF → 3RD/FINAL
//   9 grp → 18 teams → ELIM(2) → R16 → QF → SF → 3RD/FINAL
// ─────────────────────────────────────────────
enum _BracketMode {
  oneGroup,
  twoGroup,
  threeGroup,
  fourGroup,
  fiveGroup,
  sixGroup,
  sevenGroup,
  eightGroup,
  nineGroup,
}

_BracketMode _modeFromGroupCount(int groups) {
  switch (groups) {
    case 1:  return _BracketMode.oneGroup;
    case 2:  return _BracketMode.twoGroup;
    case 3:  return _BracketMode.threeGroup;
    case 4:  return _BracketMode.fourGroup;
    case 5:  return _BracketMode.fiveGroup;
    case 6:  return _BracketMode.sixGroup;
    case 7:  return _BracketMode.sevenGroup;
    case 8:  return _BracketMode.eightGroup;
    case 9:  return _BracketMode.nineGroup;
    default:
      if (groups <= 1) return _BracketMode.oneGroup;
      if (groups <= 2) return _BracketMode.twoGroup;
      if (groups <= 4) return _BracketMode.fourGroup;
      return _BracketMode.eightGroup;
  }
}

List<String> _roundsForMode(_BracketMode mode) {
  switch (mode) {
    case _BracketMode.oneGroup:
      return ['FINAL'];
    case _BracketMode.twoGroup:
      return ['SEMI-FINAL', 'FINAL'];
    case _BracketMode.fourGroup:
      return ['QUARTER-FINAL', 'SEMI-FINAL', 'FINAL'];
    case _BracketMode.threeGroup:
      return ['ELIM', 'SEMI-FINAL', 'FINAL'];
    case _BracketMode.fiveGroup:
    case _BracketMode.sixGroup:
    case _BracketMode.sevenGroup:
      return ['ELIM', 'QUARTER-FINAL', 'SEMI-FINAL', 'FINAL'];
    case _BracketMode.eightGroup:
      return ['ROUND OF 16', 'QUARTER-FINAL', 'SEMI-FINAL', 'FINAL'];
    case _BracketMode.nineGroup:
      return ['ELIM', 'ROUND OF 16', 'QUARTER-FINAL', 'SEMI-FINAL', 'FINAL'];
  }
}

const Map<String, String> _bracketTypeToRound = {
  'elimination':    'ELIM',
  'round-of-32':    'ELIM',
  'round-of-16':    'ROUND OF 16',
  'round-of-8':     'QUARTER-FINAL',
  'quarter-finals': 'QUARTER-FINAL',
  'semi-finals':    'SEMI-FINAL',
  'third-place':    '3RD PLACE',
  'final':          'FINAL',
};

String _uiRoundFromBracketType(String bt) =>
    _bracketTypeToRound[bt.toLowerCase()] ?? bt.toUpperCase();

int _roundIdForBracketType(String bt) {
  switch (bt.toLowerCase()) {
    case 'elimination':
    case 'round-of-32':
    case 'round-of-16':
      return 2;
    case 'round-of-8':
    case 'quarter-finals':
      return 3;
    case 'semi-finals':
      return 4;
    case 'third-place':
    case 'final':
      return 5;
    default:
      return 2;
  }
}

// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────
class _ScheduleRow {
  final int    matchId;
  final int    teamId;
  final String teamName;
  final String bracketType;
  final int    refereeId;
  final int    arenaNumber;
  final String matchTime;

  const _ScheduleRow({
    required this.matchId,
    required this.teamId,
    required this.teamName,
    required this.bracketType,
    required this.refereeId,
    required this.arenaNumber,
    required this.matchTime,
  });

  factory _ScheduleRow.fromJson(Map<String, dynamic> j) => _ScheduleRow(
    matchId:     int.tryParse(j['match_id'].toString()) ?? 0,
    teamId:      int.tryParse(j['team_id'].toString()) ?? 0,
    teamName:    j['team_name']?.toString() ?? 'Unknown',
    bracketType: j['bracket_type']?.toString() ?? '',
    refereeId:   int.tryParse(j['referee_id'].toString()) ?? 0,
    arenaNumber: int.tryParse(j['arena_number'].toString()) ?? 0,
    matchTime:   j['match_time']?.toString() ?? '',
  );
}

class _ChampMatch {
  final int    matchId;
  final String round;
  final String bracketType;
  final String home;
  final String away;
  final int    homeId;
  final int    awayId;
  final int    refereeId;
  final int    arenaNumber;
  final String matchTime;
  final int    roundId;

  _ChampMatch({
    required this.matchId,
    required this.round,
    required this.bracketType,
    this.home        = 'TBD',
    this.away        = 'TBD',
    this.homeId      = 0,
    this.awayId      = 0,
    this.refereeId   = 0,
    this.arenaNumber = 0,
    this.matchTime   = '',
  }) : roundId = _roundIdForBracketType(bracketType);

  bool get isTbd => homeId == 0 || awayId == 0;
}

class _MatchScore {
  final int matchId;
  final int homeScore;
  final int awayScore;

  const _MatchScore({
    required this.matchId,
    required this.homeScore,
    required this.awayScore,
  });
}

// ─────────────────────────────────────────────
// ICONS / LABELS
// ─────────────────────────────────────────────
IconData _roundIcon(String round) {
  switch (round) {
    case 'ELIM':          return Icons.swap_horiz_rounded;
    case 'ROUND OF 16':   return Icons.filter_none_rounded;
    case 'QUARTER-FINAL': return Icons.shield_outlined;
    case 'SEMI-FINAL':    return Icons.sports_soccer;
    case '3RD PLACE':     return Icons.military_tech_outlined;
    case 'FINAL':         return Icons.emoji_events_rounded;
    default:              return Icons.sports;
  }
}

String _modeBadgeLabel(_BracketMode mode) {
  switch (mode) {
    case _BracketMode.oneGroup:   return '1 GRP / 2T';
    case _BracketMode.twoGroup:   return '2 GRP / 4T';
    case _BracketMode.threeGroup: return '3 GRP / 6T';
    case _BracketMode.fourGroup:  return '4 GRP / 8T';
    case _BracketMode.fiveGroup:  return '5 GRP / 10T';
    case _BracketMode.sixGroup:   return '6 GRP / 12T';
    case _BracketMode.sevenGroup: return '7 GRP / 14T';
    case _BracketMode.eightGroup: return '8 GRP / 16T';
    case _BracketMode.nineGroup:  return '9 GRP / 18T';
  }
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class _ChampApiService {
  /// POSTs to cleanup_champ_seeds.php to remove any championship
  /// tbl_teamschedule slots whose feeder qualification score no longer
  /// exists in the DB (e.g. deleted directly via database).
  /// Called before every load/refresh so match cards show TBD immediately.
  static Future<void> cleanupOrphanedSeeds(int categoryId) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.cleanupChampionshipSeeds),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'category_id': categoryId}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[champ] cleanupOrphanedSeeds done for category=$categoryId');
    } catch (e) {
      debugPrint('[champ] cleanupOrphanedSeeds error: $e');
    }
  }

  static Future<int> fetchGroupCount(int categoryId) async {
    try {
      final url = Uri.parse(
          '${ApiConfig.getGroupCount}?category_id=$categoryId');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return int.tryParse(data['group_count']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  static Future<List<_ScheduleRow>> fetchChampionshipSchedule(
      int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.getTeamSchedule}?category_id=$categoryId');
    final response =
        await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(
          'get_teamschedule failed [${response.statusCode}]');
    }
    final List<dynamic> data = json.decode(response.body);
    return data
        .map((j) => _ScheduleRow.fromJson(j as Map<String, dynamic>))
        .where((r) => r.bracketType.isNotEmpty && r.bracketType != 'group')
        .toList();
  }

  /// Fetches every knockout match shell (match_id + bracket_type) directly
  /// from tbl_match, regardless of whether any team is assigned yet.
  /// This guarantees TBD cards are always shown even for empty slots.
  static Future<List<Map<String, dynamic>>> fetchAllKnockoutMatchShells(
      int categoryId) async {
    try {
      final url = Uri.parse(
          '${ApiConfig.getChampionshipMatchShells}?category_id=$categoryId');
      final response =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[fetchAllKnockoutMatchShells] error: $e');
    }
    return [];
  }

  static Future<Map<int, String>> fetchScoredMatchInfo(
      int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.getScoredChampionshipMatches}?category_id=$categoryId');
    final response =
        await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return {};
    final List<dynamic> data = json.decode(response.body);
    final Map<int, String> result = {};
    for (final j in data) {
      final mid = int.tryParse(j['match_id'].toString()) ?? 0;
      final bt  = j['bracket_type']?.toString() ?? '';
      if (mid != 0) result[mid] = bt;
    }
    return result;
  }

  static Future<Map<int, _MatchScore>> fetchMatchScores(
      int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.getScoredMatches}?category_id=$categoryId');
    final response =
        await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return {};

    final List<dynamic> data = json.decode(response.body);

    const champBracketTypes = {
      'elimination', 'round-of-32', 'round-of-16', 'round-of-8',
      'quarter-finals', 'semi-finals', 'third-place', 'final',
    };

    final Map<int, List<Map<String, dynamic>>> byMatch = {};
    for (final j in data) {
      final bt  = j['bracket_type']?.toString() ?? '';
      if (!champBracketTypes.contains(bt)) continue;
      final mid = int.tryParse(j['match_id'].toString()) ?? 0;
      if (mid == 0) continue;
      byMatch.putIfAbsent(mid, () => []).add(j as Map<String, dynamic>);
    }

    final Map<int, _MatchScore> result = {};
    byMatch.forEach((mid, rows) {
      if (rows.isEmpty) return;
      final homeScore = rows.length >= 2
          ? int.tryParse(rows[1]['score_independentscore'].toString()) ?? 0
          : 0;
      final awayScore =
          int.tryParse(rows[0]['score_independentscore'].toString()) ?? 0;
      result[mid] =
          _MatchScore(matchId: mid, homeScore: homeScore, awayScore: awayScore);
    });
    return result;
  }

  // ── Clear teams from a specific match (admin manual clear) ──────────
  // ignore: unused_element
  static Future<bool> clearMatchTeams(int matchId, int categoryId) async {
    try {
      final url = Uri.parse(ApiConfig.cleanupChampionshipSeeds);
      final resp = await http.delete(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'match_id': matchId, 'category_id': categoryId}),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final result = json.decode(resp.body) as Map<String, dynamic>;
        return result['success'] == true;
      }
    } catch (e) {
      debugPrint('[clearMatchTeams] error: $e');
    }
    return false;
  }

  /// Returns the full PHP response map on success, or null on network/HTTP failure.
  /// The map always contains at least {'success': bool}.
  /// Group matches return {'status': 'pending'} or {'status': 'group_complete'}.
  /// Knockout matches return {'status': 'knockout_advanced'} (injected below).
  static Future<Map<String, dynamic>?> advanceKnockout({
    required int matchId,
    required int homeTeamId,
    required int awayTeamId,
    required int categoryId,
    required bool isGroupMatch,
  }) async {
    try {
      // ── GROUP MATCH: let PHP handle scoring/ranking entirely.
      // We don't pre-compute a winner — PHP reads all group scores itself.
      if (isGroupMatch) {
        final advanceUrl = Uri.parse(ApiConfig.advanceKnockout);
        final body = json.encode({
          'match_id':       matchId,
          'winner_team_id': 0,   // ignored by PHP for group matches
          'loser_team_id':  0,   // ignored by PHP for group matches
          'category_id':    categoryId,
        });
        debugPrint('[advanceKnockout] GROUP POST $advanceUrl body=$body');
        final resp = await http.post(
          advanceUrl,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 10));
        debugPrint('[advanceKnockout] GROUP response [${resp.statusCode}]: ${resp.body}');
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          return json.decode(resp.body) as Map<String, dynamic>;
        }
        return null;
      }

      // ── KNOCKOUT MATCH: determine winner/loser from scores first.
      final scoreUrl = Uri.parse(
          '${ApiConfig.getScore}?match_id=$matchId');
      final scoreResp = await http
          .get(scoreUrl)
          .timeout(const Duration(seconds: 10));

      if (scoreResp.statusCode != 200) {
        debugPrint('[advanceKnockout] score fetch failed: ${scoreResp.statusCode}');
        return null;
      }

      final List<dynamic> matchRows = json.decode(scoreResp.body);
      debugPrint('[advanceKnockout] matchId=$matchId rows=${matchRows.length}');

      if (matchRows.length < 2) {
        debugPrint('[advanceKnockout] not enough score rows: ${matchRows.length}');
        return {'success': false, 'error': 'insufficient_score_rows'};
      }

      final Map<int, int> teamScores = {};
      for (final j in matchRows) {
        final tid   = int.tryParse(j['team_id'].toString()) ?? 0;
        final goals = int.tryParse(
            j['score_independentscore'].toString()) ?? 0;
        if (tid > 0) teamScores[tid] = goals;
        debugPrint('[advanceKnockout] team=$tid goals=$goals');
      }

      final homeGoals = teamScores[homeTeamId] ?? 0;
      final awayGoals = teamScores[awayTeamId] ?? 0;

      debugPrint('[advanceKnockout] home=$homeTeamId ($homeGoals) vs away=$awayTeamId ($awayGoals)');

      if (homeGoals == awayGoals) {
        debugPrint('[advanceKnockout] TIE — cannot advance');
        return {'success': false, 'error': 'tie'};
      }

      final winnerTeamId = homeGoals > awayGoals ? homeTeamId : awayTeamId;
      final loserTeamId  = homeGoals > awayGoals ? awayTeamId : homeTeamId;

      final advanceUrl = Uri.parse(ApiConfig.advanceKnockout);
      final body = json.encode({
        'match_id':       matchId,
        'winner_team_id': winnerTeamId,
        'loser_team_id':  loserTeamId,
        'category_id':    categoryId,
      });

      debugPrint('[advanceKnockout] KNOCKOUT POST $advanceUrl body=$body');

      final advanceResp = await http.post(
        advanceUrl,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('[advanceKnockout] KNOCKOUT response [${advanceResp.statusCode}]: ${advanceResp.body}');

      if (advanceResp.statusCode == 200 || advanceResp.statusCode == 201) {
        final result = json.decode(advanceResp.body) as Map<String, dynamic>;
        if (result['success'] == true) {
          // Inject a status key so _openScoring can identify this case
          result['status'] = 'knockout_advanced';
        } else {
          debugPrint('[advanceKnockout] PHP returned success=false: ${result['error'] ?? result['message']}');
        }
        return result;
      }
      return null;
    } catch (e, stack) {
      debugPrint('[advanceKnockout] Exception: $e\n$stack');
      return null;
    }
  }
}

// ─────────────────────────────────────────────
// MATCH BUILDER
// ─────────────────────────────────────────────
/// Builds [_ChampMatch] list from assigned-team rows merged with all
/// knockout match shells.  Shells ensure every match slot renders a card
/// (as TBD) even when no teams have been seeded into it yet.
List<_ChampMatch> _pairScheduleRows(
  List<_ScheduleRow> rows,
  List<Map<String, dynamic>> shells,
) {
  // Index team rows by matchId
  final Map<int, List<_ScheduleRow>> byMatch = {};
  for (final r in rows) {
    byMatch.putIfAbsent(r.matchId, () => []).add(r);
  }

  // Seed every shell match so empty ones still appear
  for (final shell in shells) {
    final mid = int.tryParse(shell['match_id'].toString()) ?? 0;
    if (mid == 0) continue;
    byMatch.putIfAbsent(mid, () => []); // empty list = TBD both sides
  }

  // Build a bracketType lookup from shells for matches with no team rows
  final Map<int, String> shellBracketType = {
    for (final s in shells)
      if ((int.tryParse(s['match_id'].toString()) ?? 0) != 0)
        int.parse(s['match_id'].toString()): s['bracket_type']?.toString() ?? '',
  };

  final List<_ChampMatch> matches = [];
  byMatch.forEach((matchId, pair) {
    final bracketType = pair.isNotEmpty
        ? pair[0].bracketType
        : (shellBracketType[matchId] ?? '');
    if (bracketType.isEmpty) return;

    final first  = pair.isNotEmpty ? pair[0] : null;
    final second = pair.length >= 2 ? pair[1] : null;
    final round  = _uiRoundFromBracketType(bracketType);

    matches.add(_ChampMatch(
      matchId:     matchId,
      round:       round,
      bracketType: bracketType,
      home:        first?.teamName ?? 'TBD',
      homeId:      first?.teamId   ?? 0,
      away:        second?.teamName ?? 'TBD',
      awayId:      second?.teamId  ?? 0,
      refereeId:   first?.refereeId   ?? 0,
      arenaNumber: first?.arenaNumber ?? 0,
      matchTime:   first?.matchTime   ?? '',
    ));
  });

  matches.sort((a, b) => a.matchId.compareTo(b.matchId));
  return matches;
}

// ─────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────
class ChampionshipScheduleScreen extends StatefulWidget {
  final int    categoryId;
  final String competitionTitle;
  final Color  themeColor;

  const ChampionshipScheduleScreen({
    super.key,
    required this.categoryId,
    required this.competitionTitle,
    required this.themeColor,
  });

  @override
  State<ChampionshipScheduleScreen> createState() =>
      _ChampionshipScheduleScreenState();
}

class _ChampionshipScheduleScreenState
    extends State<ChampionshipScheduleScreen>
    with TickerProviderStateMixin {

  _BracketMode _mode = _BracketMode.fourGroup;
  late TabController _tabController;
  List<GlobalKey> _tabKeys = [];
  final GlobalKey _tabBarKey = GlobalKey();
  Key _bracketKey = const ValueKey('default');

  bool    _loading = true;
  String? _error;

  Map<String, List<_ChampMatch>> _matchesByRound = {};
  Map<int, String>      _scoredMatchInfo = {};
  Map<int, _MatchScore> _matchScores     = {};

  List<String> get _rounds => _roundsForMode(_mode);
  List<_ChampMatch> get _allMatches =>
      _matchesByRound.values.expand((l) => l).toList();

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _roundsForMode(_mode).length, vsync: this);
    _loadBracket();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── LOAD ──────────────────────────────────────────────────────────
  Future<void> _loadBracket() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Always run cleanup on load so seeds orphaned by a direct DB score
      // deletion (outside the app) are cleared when the screen is opened.
      // cleanup_champ_seeds.php has a fast early-exit guard that makes
      // this a near-instant no-op when nothing is stale.
      await _ChampApiService.cleanupOrphanedSeeds(widget.categoryId);

      final groupCount =
          await _ChampApiService.fetchGroupCount(widget.categoryId);
      final mode = _modeFromGroupCount(groupCount > 0 ? groupCount : 4);

      final rows   = await _ChampApiService.fetchChampionshipSchedule(
          widget.categoryId);
      final shells = await _ChampApiService.fetchAllKnockoutMatchShells(
          widget.categoryId);
      final allMatches = _pairScheduleRows(rows, shells);

      final Map<String, List<_ChampMatch>> byRound = {};
      for (final m in allMatches) {
        byRound.putIfAbsent(m.round, () => []).add(m);
      }

      Map<int, String>      scoredInfo  = {};
      Map<int, _MatchScore> matchScores = {};
      try {
        scoredInfo  = await _ChampApiService.fetchScoredMatchInfo(
            widget.categoryId);
        matchScores = await _ChampApiService.fetchMatchScores(
            widget.categoryId);
      } catch (_) {}

      if (!mounted) return;

      final rounds  = _roundsForMode(mode);
      final oldCtrl = _tabController;
      _tabController = TabController(length: rounds.length, vsync: this);
      _tabKeys = List.generate(rounds.length, (_) => GlobalKey());
      WidgetsBinding.instance
          .addPostFrameCallback((_) => oldCtrl.dispose());

      setState(() {
        _mode            = mode;
        _matchesByRound  = byRound;
        _scoredMatchInfo = scoredInfo;
        _matchScores     = matchScores;
        _loading         = false;
        _bracketKey      = ValueKey('mode_${mode.name}');
      });
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  // ── REFRESH ────────────────────────────────────────────────────────
  Future<void> _refreshData() async {
    try {
      // Run cleanup on every refresh so seeds orphaned by a direct DB
      // score deletion are cleared without needing a full re-open.
      // The PHP guard makes this a no-op when nothing is stale.
      await _ChampApiService.cleanupOrphanedSeeds(widget.categoryId);

      final rows   = await _ChampApiService.fetchChampionshipSchedule(
          widget.categoryId);
      final shells = await _ChampApiService.fetchAllKnockoutMatchShells(
          widget.categoryId);
      final allMatches = _pairScheduleRows(rows, shells);
      final Map<String, List<_ChampMatch>> byRound = {};
      for (final m in allMatches) {
        byRound.putIfAbsent(m.round, () => []).add(m);
      }

      final scoredInfo  = await _ChampApiService.fetchScoredMatchInfo(
          widget.categoryId);
      final matchScores = await _ChampApiService.fetchMatchScores(
          widget.categoryId);
      if (!mounted) return;
      setState(() {
        _matchesByRound  = byRound;
        _scoredMatchInfo = scoredInfo;
        _matchScores     = matchScores;
      });
    } catch (_) {}
  }

  // ── OPEN SCORING ───────────────────────────────────────────────────
  void _openScoring(_ChampMatch m) async {
    if (m.homeId == 0 || m.awayId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Teams for this match are not yet determined.'),
        backgroundColor: _accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    final isAlreadyScored = _scoredMatchInfo.containsKey(m.matchId);

    if (!mounted) return;

    // Dismiss any visible snackbar immediately so it doesn't linger while
    // the scoring page is open (matches qualification_sched behaviour).
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final submitted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => SoccerScoringPage(
                  matchId:             m.matchId,
                  teamId:              m.homeId,
                  awayTeamId:          m.awayId,
                  refereeId:           m.refereeId > 0 ? m.refereeId : 1,
                  homeTeamName:        m.home,
                  awayTeamName:        m.away,
                  isChampionship:      true,
                  championshipRoundId: m.roundId,
                )));

    debugPrint('[_openScoring] submitted=$submitted matchId=${m.matchId}');

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    if (!mounted) return;

    if (submitted == true) {

      final bt            = m.bracketType.toLowerCase();
      final isFinalMatch  = bt == 'final' || bt == 'third-place';
      final isGroupMatch  = bt == 'group';

      // ── Build the snackbar BEFORE _refreshData() triggers setState,
      // which would clear any snackbar shown before the rebuild.
      SnackBar? snackBar;
      SnackBar? advanceSnackBar;

      if (isFinalMatch) {
        // Final / 3rd-place match: only show "Score submitted successfully!" — no advancement.
        snackBar = SnackBar(
          content: const Text('Score submitted successfully!'),
          backgroundColor: const Color(0xFF5E975E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        );
      } else {
        final result = await _ChampApiService.advanceKnockout(
          matchId:      m.matchId,
          homeTeamId:   m.homeId,
          awayTeamId:   m.awayId,
          categoryId:   widget.categoryId,
          isGroupMatch: isGroupMatch,
        );

        debugPrint('[_openScoring] advanceKnockout result=$result');

        if (result != null) {
          final status  = result['status']?.toString() ?? '';
          final success = result['success'] == true;

          if (status == 'pending') {
            final grp    = result['group_label']?.toString() ?? '';
            final scored = result['matches_scored']?.toString() ?? '?';
            final total  = result['matches_total']?.toString()  ?? '?';
            snackBar = SnackBar(
              content: Text(
                'Group $grp: $scored/$total matches scored. '
                'Waiting for remaining matches.',
              ),
              backgroundColor: const Color(0xFF5C6BC0),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            );

          } else if (status == 'group_complete') {
            final grp       = result['group_label']?.toString() ?? '';
            final nextRound = result['next_round']?.toString() ?? 'next round';
            final r1        = result['rank1_team_name']?.toString() ?? '';
            final r2        = result['rank2_team_name']?.toString() ?? '';
            final uiRound   = _uiRoundFromBracketType(nextRound);
            snackBar = SnackBar(
              content: Text(
                '✅ Group $grp complete! '
                '$r1 & $r2 seeded into $uiRound.',
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 5),
            );

          } else if (status == 'knockout_advanced') {
            snackBar = SnackBar(
              content: const Text('Score submitted successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            );
            advanceSnackBar = const SnackBar(
              content: Text('Team Advances to next round!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
              duration: Duration(seconds: 4),
            );

          } else if (success) {
            // third-place — no further advancement needed
            snackBar = SnackBar(
              content: Text(result['message']?.toString() ?? '✅ Match scored.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            );

          } else if (result['error'] == 'tie') {
            snackBar = SnackBar(
              content: const Text(
                  '⚠️ Match ended in a tie — winner could not be determined.'),
              backgroundColor: const Color(0xFFFF9F43),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            );

          } else {
            snackBar = SnackBar(
              content: const Text('⚠️ Score saved, but advancement failed. '
                  'Check server logs.'),
              backgroundColor: const Color(0xFFE65100),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            );
          }
        }
      }

      // Cleanup also runs on every load/refresh (above), but we call it
      // here again immediately after a re-score so the QF/SF cards update
      // in the same refresh cycle without waiting for the next open.
      if (isAlreadyScored) {
        await _ChampApiService.cleanupOrphanedSeeds(widget.categoryId);
      }

      // Refresh data first (may call setState internally)
      await _refreshData();

      // Show notifications AFTER rebuild so they aren't cleared by setState.
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (advanceSnackBar != null && snackBar != null) {
          // Both toasts must appear simultaneously — Flutter's snackbar queue
          // would show them one-after-the-other, so we use an Overlay instead.
          _showStackedToasts(context);
        } else if (snackBar != null) {
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      }

    } else {
      // Not submitted — still refresh in case of other state changes
      await _refreshData();
    }

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _scrollSelectedTabIntoView(_tabController.index);
  }

  /// Shows "Team Advances" (top) and "Score submitted" (bottom) simultaneously
  /// using an Overlay, because Flutter's SnackBar queue shows them sequentially.
  void _showStackedToasts(BuildContext ctx) {
    final overlay = Overlay.of(ctx);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).padding.bottom +
            16,
        left: 16,
        right: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top toast: Team Advances ──────────────────────────────
            Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '🏆 Team Advances to next round!',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── Bottom toast: Score submitted ─────────────────────────
            Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '✅ Score submitted successfully!',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  void _scrollSelectedTabIntoView(int index) {
    if (index >= _tabKeys.length) return;

    _tabController.animateTo(index, duration: Duration.zero);

    void tryScroll() {
      final ctx = _tabKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    }

    tryScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tryScroll();
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        _buildTitleBar(),
        Expanded(child: _buildBody()),
      ])),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    color: _accentColor,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.chevron_left,
                  color: _accentColor, size: 20),
            ),
            const SizedBox(width: 8),
            const Text('BACK',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(widget.competitionTitle.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic)),
          const Text('CHAMPIONSHIP',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ]),
      ],
    ),
  );

  Widget _buildTitleBar() => Column(children: [
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5A3A9A), Color(0xFF7D58B3)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
            bottom: BorderSide(color: const Color(0xFFD4A017), width: 3)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFD4A017).withOpacity(0.2),
            border: Border.all(color: const Color(0xFFD4A017), width: 1.5),
          ),
          child: const Icon(Icons.emoji_events_rounded,
              color: Color(0xFFD4A017), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('CHAMPIONSHIP BRACKET',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(
              '${_allMatches.length} matches · ${_rounds.length} rounds',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.65), fontSize: 11)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFD4A017).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFFD4A017).withOpacity(0.6), width: 1),
          ),
          child: Row(children: [
            const Icon(Icons.groups_rounded,
                color: Color(0xFFD4A017), size: 14),
            const SizedBox(width: 5),
            Text(
              _loading ? '...' : _modeBadgeLabel(_mode),
              style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 11,
                  fontWeight: FontWeight.w800),
            ),
          ]),
        ),
      ]),
    ),

    if (!_loading)
      KeyedSubtree(
        key: _bracketKey,
        child: Container(
          color: _accentColor,
          child: TabBar(
            key: _tabBarKey,
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            isScrollable: _rounds.length > 3,
            labelStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8),
            tabs: _rounds.asMap().entries
                .map((e) => Tab(
                  key: e.key < _tabKeys.length ? _tabKeys[e.key] : null,
                  icon: Icon(_roundIcon(e.value), size: 14),
                  text: e.value,
                ))
                .toList(),
          ),
        ),
      ),
  ]);

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadBracket,
        color: _accentColor,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 48),
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadBracket,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: _accentColor),
                ),
              ],
            )),
          ),
        ),
      );
    }
    if (_allMatches.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadBracket,
        color: _accentColor,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sports_soccer,
                    color: _headerMuted, size: 64),
                const SizedBox(height: 16),
                const Text('No championship matches available yet.',
                    style: TextStyle(color: _headerMuted, fontSize: 15)),
                const SizedBox(height: 8),
                const Text(
                    'Qualification matches are not yet completed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _headerMuted, fontSize: 12)),
              ],
            )),
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: _rounds.map((round) {
        // The FINAL tab also absorbs 3RD PLACE matches (classification match).
        final bool isFinalTab = round == 'FINAL';
        final List<_ChampMatch> matches = isFinalTab
            ? [
                ...(_matchesByRound['3RD PLACE'] ?? []),
                ...(_matchesByRound['FINAL'] ?? []),
              ]
            : (_matchesByRound[round] ?? []);

        if (matches.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: _accentColor,
            backgroundColor: Colors.white,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_roundIcon(round), color: _headerMuted, size: 48),
                      const SizedBox(height: 12),
                      Text('No $round matches yet.',
                          style: const TextStyle(color: _headerMuted)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (isFinalTab) {
          // Render 3RD PLACE and FINAL as labelled sections (no re-sorting
          // across the two groups — each section keeps scored-last order).
          List<_ChampMatch> sortSection(List<_ChampMatch> src) =>
              [...src]..sort((a, b) {
                  final aScored = _scoredMatchInfo.containsKey(a.matchId) ? 1 : 0;
                  final bScored = _scoredMatchInfo.containsKey(b.matchId) ? 1 : 0;
                  if (aScored != bScored) return aScored.compareTo(bScored);
                  return a.matchId.compareTo(b.matchId);
                });

          final thirdPlaceMatches = sortSection(_matchesByRound['3RD PLACE'] ?? []);
          final finalMatches      = sortSection(_matchesByRound['FINAL'] ?? []);

          Widget sectionLabel(String label, IconData icon) => Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(children: [
              Icon(icon, size: 13, color: _headerMuted),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: _headerMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: _headerMuted.withOpacity(0.3), thickness: 1)),
            ]),
          );

          return RefreshIndicator(
            onRefresh: _refreshData,
            color: _accentColor,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (thirdPlaceMatches.isNotEmpty) ...[
                  sectionLabel('3RD PLACE', Icons.military_tech_outlined),
                  ...thirdPlaceMatches.map((m) {
                    final isScored   = _scoredMatchInfo.containsKey(m.matchId);
                    final matchScore = _matchScores[m.matchId];
                    return _ChampMatchCard(
                      match: m, isScored: isScored,
                      matchScore: matchScore, onTap: () => _openScoring(m),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
                if (finalMatches.isNotEmpty) ...[
                  sectionLabel('FINAL', Icons.emoji_events_rounded),
                  ...finalMatches.map((m) {
                    final isScored   = _scoredMatchInfo.containsKey(m.matchId);
                    final matchScore = _matchScores[m.matchId];
                    return _ChampMatchCard(
                      match: m, isScored: isScored,
                      matchScore: matchScore, onTap: () => _openScoring(m),
                    );
                  }),
                ],
              ],
            ),
          );
        }

        // Scored matches sink to the bottom; unscored stay on top.
        final sortedMatches = [...matches]..sort((a, b) {
            final aScored = _scoredMatchInfo.containsKey(a.matchId) ? 1 : 0;
            final bScored = _scoredMatchInfo.containsKey(b.matchId) ? 1 : 0;
            if (aScored != bScored) return aScored.compareTo(bScored);
            return a.matchId.compareTo(b.matchId);
          });
        return RefreshIndicator(
          onRefresh: _refreshData,
          color: _accentColor,
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: sortedMatches.length,
            itemBuilder: (_, i) {
              final m        = sortedMatches[i];
              final isScored = _scoredMatchInfo.containsKey(m.matchId);
              final matchScore = _matchScores[m.matchId];
              return _ChampMatchCard(
                match:      m,
                isScored:   isScored,
                matchScore: matchScore,
                onTap:      () => _openScoring(m),
              );
            },
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// MATCH CARD
// ─────────────────────────────────────────────
class _ChampMatchCard extends StatelessWidget {
  final _ChampMatch  match;
  final bool         isScored;
  final _MatchScore? matchScore;
  final VoidCallback onTap;

  const _ChampMatchCard({
    required this.match,
    required this.isScored,
    required this.matchScore,
    required this.onTap,
  });

  bool get _isTbd => match.isTbd;

  String _result(bool isHome) {
    if (matchScore == null) return '';
    if (matchScore!.homeScore > matchScore!.awayScore) return isHome ? 'W' : 'L';
    if (matchScore!.awayScore > matchScore!.homeScore) return isHome ? 'L' : 'W';
    return 'D';
  }

  Widget _resultBadge(String result) {
    final Color bg = result == 'W'
        ? const Color(0xFF1B5E20).withOpacity(0.55)
        : result == 'L'
            ? const Color(0xFFB71C1C).withOpacity(0.55)
            : const Color(0xFF424242).withOpacity(0.55);
    final Color borderCol = result == 'W'
        ? Colors.greenAccent
        : result == 'L'
            ? Colors.redAccent
            : Colors.white54;
    final Color textCol = result == 'W'
        ? Colors.greenAccent
        : result == 'L'
            ? Colors.redAccent.shade100
            : Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderCol, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(result,
          style: TextStyle(
              color: textCol, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      colors: isScored
          ? [const Color(0xFF5A3A9A).withOpacity(0.5),
             const Color(0xFF7D58B3).withOpacity(0.4)]
          : [const Color(0xFF5A3A9A), const Color(0xFF7D58B3)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return GestureDetector(
      onTap: (isScored || _isTbd) ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
          border: null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(children: [

          // ── Header strip ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.20),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(_roundIcon(match.round), size: 13, color: Colors.white70),
              const SizedBox(width: 6),
              Text('MATCH ${match.matchId}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              if (match.matchTime.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.access_time_rounded,
                    size: 11, color: Colors.white54),
                const SizedBox(width: 3),
                Text(match.matchTime,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 9)),
              ],
              const Spacer(),
              if (_isTbd)
                _Chip(label: 'TBD', color: Colors.white54),
            ]),
          ),

          // ── Home / Away row ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // HOME
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HOME',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 3),
                    Text(match.home,
                        style: TextStyle(
                          color: _isTbd ? Colors.white54 : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                )),

                // W/L/D | VS/score | W/L/D
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isScored && matchScore != null &&
                        _result(true).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _resultBadge(_result(true)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white30, width: 1),
                      ),
                      child: isScored && matchScore != null
                          ? Text(
                              '${matchScore!.homeScore}-${matchScore!.awayScore}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900))
                          : const Text('VS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900)),
                    ),
                    if (isScored && matchScore != null &&
                        _result(false).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _resultBadge(_result(false)),
                      ),
                  ],
                ),

                // AWAY
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('AWAY',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 3),
                    Text(match.away,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _isTbd ? Colors.white54 : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                )),
              ],
            ),
          ),

          // ── Arena info row ───────────────────────────────────────
          if (match.arenaNumber > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 11, color: Colors.white54),
                  const SizedBox(width: 3),
                  Text('Arena ${match.arenaNumber}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 9)),
                ],
              ),
            ),

          // ── Footer ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(match.round,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),

                if (_isTbd)
                  Text('WAITING FOR TEAMS',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8))
                else if (!isScored)
                  Row(children: [
                    Text('TAP TO SCORE',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8)),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withOpacity(0.55), size: 14),
                  ])
                else
                  Row(children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: Colors.greenAccent.withOpacity(0.7),
                        size: 12),
                    const SizedBox(width: 4),
                    Text('COMPLETED',
                        style: TextStyle(
                            color: Colors.greenAccent.withOpacity(0.7),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8)),
                  ]),
              ],
            ),
          ),

        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CHIP
// ─────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.20),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.55), width: 1),
    ),
    child: Text(label,
        style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5)),
  );
}