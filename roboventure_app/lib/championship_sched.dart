// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'soccer_scoring.dart';
import 'api_config.dart';

// ─────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────
const Color _accentColor = Color(0xFF7D58B3);
const Color _headerDark  = Color(0xFF5A3A9A);
const Color _headerMuted = Color(0xFF9E9EAD);

// ─────────────────────────────────────────────
// BRACKET MODE
// Determined by group count fetched from the server.
//
//   2 grp → 4 teams  → SF → 3RD → FINAL
//   3 grp → 6 teams  → ELIM(3) → QF → SF → FINAL
//   4 grp → 8 teams  → QF → SF → 3RD → FINAL
//   5 grp → 10 teams → ELIM(2) → QF → SF → FINAL
//   6 grp → 12 teams → ELIM(4) → QF → SF → FINAL
//   7 grp → 14 teams → ELIM(6) → QF → SF → FINAL
//   8 grp → 16 teams → R16(8)  → QF → SF → FINAL
//   9 grp → 18 teams → ELIM(2) → R16(8) → QF → SF → FINAL
// ─────────────────────────────────────────────
enum _BracketMode {
  twoGroup,    // 2 grp  → SF direct
  threeGroup,  // 3 grp  → ELIM(3) → QF
  fourGroup,   // 4 grp  → QF exact
  fiveGroup,   // 5 grp  → ELIM(2) → QF
  sixGroup,    // 6 grp  → ELIM(4) → QF
  sevenGroup,  // 7 grp  → ELIM(6) → QF
  eightGroup,  // 8 grp  → R16(8) → QF
  nineGroup,   // 9 grp  → ELIM(2) → R16 → QF
}

_BracketMode _modeFromGroupCount(int groups) {
  switch (groups) {
    case 2:  return _BracketMode.twoGroup;
    case 3:  return _BracketMode.threeGroup;
    case 4:  return _BracketMode.fourGroup;
    case 5:  return _BracketMode.fiveGroup;
    case 6:  return _BracketMode.sixGroup;
    case 7:  return _BracketMode.sevenGroup;
    case 8:  return _BracketMode.eightGroup;
    case 9:  return _BracketMode.nineGroup;
    default:
      // Fallback: if more groups, try to fit into nearest known mode
      if (groups <= 2) return _BracketMode.twoGroup;
      if (groups <= 4) return _BracketMode.fourGroup;
      return _BracketMode.eightGroup;
  }
}

/// Round tab labels shown in the UI for each bracket mode.
List<String> _roundsForMode(_BracketMode mode) {
  switch (mode) {
    case _BracketMode.twoGroup:
      return ['SEMI-FINAL', '3RD PLACE', 'FINAL'];
    case _BracketMode.fourGroup:
      return ['QUARTER-FINAL', 'SEMI-FINAL', '3RD PLACE', 'FINAL'];
    case _BracketMode.threeGroup:
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

// ─────────────────────────────────────────────
// ELIM match ID range: 501–512
// R16  match ID range: 1001–1016
// QF   match ID range: 101–104
// SF   match ID range: 201–202
// 3RD  match ID:       401
// FINAL match ID:      301
// ─────────────────────────────────────────────
const int _kElimBase  = 501;   // 501, 502, ... up to 512
const int _kR16Base   = 1001;  // 1001–1016
const int _kQfBase    = 101;   // 101–104
const int _k3rdId     = 401;
const int _kFinalId   = 301;

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────
class _Qualifier {
  final int    teamId;
  final String teamName;
  final int    totalScore;

  const _Qualifier({
    required this.teamId,
    required this.teamName,
    required this.totalScore,
  });

  factory _Qualifier.fromJson(Map<String, dynamic> j) => _Qualifier(
    teamId:     int.tryParse(j['team_id'].toString()) ?? 0,
    teamName:   j['team_name']?.toString() ?? 'Unknown',
    totalScore: int.tryParse(j['total_score'].toString()) ?? 0,
  );
}

// Maps a championship round name to the DB round_id stored in tbl_score.
// Qualification = 1 (handled by the qualification screen).
// Championship rounds start at 2.
int _roundIdForRound(String round) {
  switch (round) {
    case 'ELIM':          return 2; // ELIM / R16 share round_id 2
    case 'ROUND OF 16':   return 2;
    case 'QUARTER-FINAL': return 3;
    case 'SEMI-FINAL':    return 4;
    case '3RD PLACE':     return 5; // 3rd place is part of the Final round
    case 'FINAL':         return 5;
    default:              return 2;
  }
}

class _ChampMatch {
  final int    matchId;
  final String round;
  final String home;
  final String away;
  final int    homeId;
  final int    awayId;
  /// DB round_id to store in tbl_score when this match is scored.
  final int    roundId;
  /// true = this team has a BYE and advances automatically
  final bool   homeBye = false;
  final bool   awayBye = false;

  _ChampMatch({
    required this.matchId,
    required this.round,
    required this.home,
    required this.away,
    this.homeId  = 0,
    this.awayId  = 0,
  }) : roundId = _roundIdForRound(round);

  bool get isByeMatch => homeBye || awayBye;
}

// ─────────────────────────────────────────────
// MATCH SCORE RESULT
// ─────────────────────────────────────────────
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

String _roundLabel(String round) {
  switch (round) {
    case 'ELIM':          return 'ELIM';
    case 'ROUND OF 16':   return 'R16';
    case 'QUARTER-FINAL': return 'QF';
    case 'SEMI-FINAL':    return 'SF';
    case '3RD PLACE':     return '3RD';
    case 'FINAL':         return 'FINAL';
    default:              return round;
  }
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class _ChampApiService {
  /// Fetch group count for the category from tbl_soccer_groups via scoring.php.
  /// get_team_count now returns the distinct team count from tbl_soccer_groups;
  /// we derive group count by fetching group standings and counting distinct labels.
  static Future<int> fetchGroupCount(int categoryId) async {
    try {
      final url = Uri.parse(
          '${ApiConfig.scoring}?action=get_group_standings&category_id=$categoryId');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data.keys.length; // number of distinct group labels (A, B, C…)
      }
    } catch (_) {}
    return 0;
  }

  static Future<List<_Qualifier>> fetchQualifiers(int categoryId,
      {int limit = 8}) async {
    final url = Uri.parse(
        '${ApiConfig.scoring}?action=get_qualifiers&category_id=$categoryId&limit=$limit');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((j) => _Qualifier.fromJson(j)).toList();
    }
    throw Exception('get_qualifiers failed [${response.statusCode}]');
  }

  static Future<Set<int>> fetchScoredMatchIds(int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.getScoredChampionshipMatches}?category_id=$categoryId');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data
          .map<int>((j) => int.tryParse(j['match_id'].toString()) ?? 0)
          .where((id) => id != 0)
          .toSet();
    }
    throw Exception('get_scored_championship_matches failed [${response.statusCode}]');
  }

  static Future<Map<int, _MatchScore>> fetchMatchScores(int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.getScoredMatches}?category_id=$categoryId');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return {};

    final List<dynamic> data = json.decode(response.body);

    // All championship match IDs we care about
    const champIds = {
      501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512,
      101, 102, 103, 104,
      201, 202,
      301, 401,
      1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008,
      1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016,
    };

    final Map<int, List<Map<String, dynamic>>> byMatch = {};
    for (final j in data) {
      final mid = int.tryParse(j['match_id'].toString()) ?? 0;
      if (mid == 0 || !champIds.contains(mid)) continue;
      byMatch.putIfAbsent(mid, () => []).add(j as Map<String, dynamic>);
    }

    final Map<int, _MatchScore> result = {};
    byMatch.forEach((mid, rows) {
      if (rows.isEmpty) return;
      final awayGoals = int.tryParse(
              rows[0]['score_independentscore'].toString()) ?? 0;
      final homeGoals = rows.length >= 2
          ? int.tryParse(rows[1]['score_independentscore'].toString()) ?? 0
          : 0;
      result[mid] = _MatchScore(
          matchId: mid, homeScore: homeGoals, awayScore: awayGoals);
    });
    return result;
  }
}

// ─────────────────────────────────────────────
// BRACKET BUILDERS
// ─────────────────────────────────────────────

/// Seeded QF: #1 vs #8, #2 vs #7, #3 vs #6, #4 vs #5
List<_ChampMatch> _buildQFFromQualifiers(List<_Qualifier> q) {
  while (q.length < 8) {
    q.add(const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
  }
  return [
    _ChampMatch(matchId: 101, round: 'QUARTER-FINAL',
        home: q[0].teamName, homeId: q[0].teamId,
        away: q[7].teamName, awayId: q[7].teamId),
    _ChampMatch(matchId: 102, round: 'QUARTER-FINAL',
        home: q[1].teamName, homeId: q[1].teamId,
        away: q[6].teamName, awayId: q[6].teamId),
    _ChampMatch(matchId: 103, round: 'QUARTER-FINAL',
        home: q[2].teamName, homeId: q[2].teamId,
        away: q[5].teamName, awayId: q[5].teamId),
    _ChampMatch(matchId: 104, round: 'QUARTER-FINAL',
        home: q[3].teamName, homeId: q[3].teamId,
        away: q[4].teamName, awayId: q[4].teamId),
  ];
}

/// Build ELIM matches for [elimCount] matches.
/// [qualifiers] are sorted by score descending (top seeds).
/// Top [byeCount] seeds get BYEs directly into QF.
/// Remaining teams play ELIM; winners fill remaining QF slots.
///
/// ELIM match IDs: 501, 502, ..., 500+elimCount
List<_ChampMatch> _buildElimMatches(
    List<_Qualifier> qualifiers, int elimCount) {
  // Pad to ensure we have enough teams
  while (qualifiers.length < elimCount * 2) {
    qualifiers.add(
        const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
  }

  // Bottom seeds (lowest ranked) play ELIM.
  // Top seed plays bottom seed, etc. (FIFA-style seeding).
  // The bottom 2*elimCount teams play; we pair them:
  //   last vs second-last, third-last vs fourth-last, etc.
  final int total = qualifiers.length;
  final List<_ChampMatch> matches = [];
  for (int i = 0; i < elimCount; i++) {
    final hiIdx = total - 1 - (i * 2 + 1); // higher ranked
    final loIdx = total - 1 - (i * 2);     // lower ranked
    final hi = hiIdx >= 0 ? qualifiers[hiIdx]
        : const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0);
    final lo = loIdx >= 0 ? qualifiers[loIdx]
        : const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0);
    matches.add(_ChampMatch(
      matchId: _kElimBase + i,
      round:   'ELIM',
      home:    hi.teamName, homeId: hi.teamId,
      away:    lo.teamName, awayId: lo.teamId,
    ));
  }
  return matches;
}

/// Build R16 (round of 16) from 16–32 qualifiers.
/// Match IDs 1001–1016.
List<_ChampMatch> _buildR16Matches(List<_Qualifier> qualifiers) {
  // For 8-group format: top 2 per group = 16 qualifiers.
  // Seeding: group winners (indices 0-7) vs runners-up (indices 8-15).
  // Match pairing: Group A winner vs Group H runner-up, etc.
  while (qualifiers.length < 16) {
    qualifiers.add(
        const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
  }
  // Standard R16 seeding: #1 vs #16, #2 vs #15 … #8 vs #9
  return List.generate(8, (i) {
    final hi = qualifiers[i];           // top 8 seeds (group winners)
    final lo = qualifiers[15 - i];      // bottom 8 seeds (runners-up)
    return _ChampMatch(
      matchId: _kR16Base + i,
      round:   'ROUND OF 16',
      home:    hi.teamName, homeId: hi.teamId,
      away:    lo.teamName, awayId: lo.teamId,
    );
  });
}

/// Build QF placeholder list for when QF is fed by ELIM/R16 winners.
List<_ChampMatch> _qfPlaceholders() => List.generate(4, (i) => _ChampMatch(
  matchId: _kQfBase + i,
  round:   'QUARTER-FINAL',
  home:    'ELIM/R16 Winner',
  away:    'ELIM/R16 Winner',
));

/// Build SF direct (2-group bracket: 4 teams → SF directly).
/// Uses qualifiers[0..3].
List<_ChampMatch> _buildSFDirect(List<_Qualifier> qualifiers) {
  while (qualifiers.length < 4) {
    qualifiers.add(
        const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
  }
  return [
    _ChampMatch(matchId: 201, round: 'SEMI-FINAL',
        home: qualifiers[0].teamName, homeId: qualifiers[0].teamId,
        away: qualifiers[3].teamName, awayId: qualifiers[3].teamId),
    _ChampMatch(matchId: 202, round: 'SEMI-FINAL',
        home: qualifiers[1].teamName, homeId: qualifiers[1].teamId,
        away: qualifiers[2].teamName, awayId: qualifiers[2].teamId),
  ];
}

// ─────────────────────────────────────────────
// WINNER RESOLVER
// ─────────────────────────────────────────────
({String name, int id}) _winner(
  int matchId,
  List<_ChampMatch> allMatches,
  Map<int, _MatchScore> matchScores,
) {
  final score = matchScores[matchId];
  if (score == null) return (name: 'TBD', id: 0);
  final match = allMatches.cast<_ChampMatch?>().firstWhere(
    (m) => m?.matchId == matchId,
    orElse: () => null,
  );
  if (match == null) return (name: 'TBD', id: 0);

  // BYE match — the present team wins automatically
  if (match.isByeMatch) {
    if (match.homeBye) return (name: match.away, id: match.awayId);
    return (name: match.home, id: match.homeId);
  }

  if (score.homeScore > score.awayScore) {
    return (name: match.home, id: match.homeId);
  } else if (score.awayScore > score.homeScore) {
    return (name: match.away, id: match.awayId);
  }
  return (name: match.home, id: match.homeId); // draw → home advances
}

// ─────────────────────────────────────────────
// Build SF + FINAL (and optionally 3rd-place)
// from resolved QF winners — works for all modes.
// ─────────────────────────────────────────────
({
  List<_ChampMatch> sf,
  _ChampMatch? thirdPlace,
  _ChampMatch final_,
}) _buildSFAndFinal(
  List<_ChampMatch> qfMatches,       // exactly 4 QF matches (IDs 101–104)
  Map<int, _MatchScore> matchScores,
  {bool includeThirdPlace = false}
) {
  final allMatches = qfMatches;

  final w101 = _winner(101, allMatches, matchScores);
  final w102 = _winner(102, allMatches, matchScores);
  final w103 = _winner(103, allMatches, matchScores);
  final w104 = _winner(104, allMatches, matchScores);

  final sf1 = _ChampMatch(
    matchId: 201, round: 'SEMI-FINAL',
    home: w101.name, homeId: w101.id,
    away: w102.name, awayId: w102.id,
  );
  final sf2 = _ChampMatch(
    matchId: 202, round: 'SEMI-FINAL',
    home: w103.name, homeId: w103.id,
    away: w104.name, awayId: w104.id,
  );

  final sfMatches = [sf1, sf2];
  final w201 = _winner(201, sfMatches, matchScores);
  final w202 = _winner(202, sfMatches, matchScores);

  _ChampMatch? thirdPlace;
  if (includeThirdPlace) {
    // 3rd-place match: the two SF losers
    final l201 = sf1.homeId == w201.id
        ? (name: sf1.away, id: sf1.awayId)
        : (name: sf1.home, id: sf1.homeId);
    final l202 = sf2.homeId == w202.id
        ? (name: sf2.away, id: sf2.awayId)
        : (name: sf2.home, id: sf2.homeId);
    thirdPlace = _ChampMatch(
      matchId: _k3rdId, round: '3RD PLACE',
      home: l201.name, homeId: l201.id,
      away: l202.name, awayId: l202.id,
    );
  }

  final finalMatch = _ChampMatch(
    matchId: _kFinalId, round: 'FINAL',
    home: w201.name, homeId: w201.id,
    away: w202.name, awayId: w202.id,
  );

  return (sf: [sf1, sf2], thirdPlace: thirdPlace, final_: finalMatch);
}

/// Build SF→3RD→FINAL for 2-group mode (no QF).
({
  _ChampMatch? thirdPlace,
  _ChampMatch final_,
}) _buildThirdAndFinal(
  List<_ChampMatch> sfMatches,
  Map<int, _MatchScore> matchScores,
) {
  final w201 = _winner(201, sfMatches, matchScores);
  final w202 = _winner(202, sfMatches, matchScores);

  final sf1 = sfMatches.firstWhere((m) => m.matchId == 201,
      orElse: () => _ChampMatch(matchId: 201, round: 'SEMI-FINAL',
          home: 'TBD', away: 'TBD'));
  final sf2 = sfMatches.firstWhere((m) => m.matchId == 202,
      orElse: () => _ChampMatch(matchId: 202, round: 'SEMI-FINAL',
          home: 'TBD', away: 'TBD'));

  final l201 = sf1.homeId == w201.id
      ? (name: sf1.away, id: sf1.awayId)
      : (name: sf1.home, id: sf1.homeId);
  final l202 = sf2.homeId == w202.id
      ? (name: sf2.away, id: sf2.awayId)
      : (name: sf2.home, id: sf2.homeId);

  final thirdPlace = _ChampMatch(
    matchId: _k3rdId, round: '3RD PLACE',
    home: l201.name, homeId: l201.id,
    away: l202.name, awayId: l202.id,
  );

  final finalMatch = _ChampMatch(
    matchId: _kFinalId, round: 'FINAL',
    home: w201.name, homeId: w201.id,
    away: w202.name, awayId: w202.id,
  );

  return (thirdPlace: thirdPlace, final_: finalMatch);
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

  _BracketMode _mode = _BracketMode.fourGroup; // default until loaded
  late TabController _tabController;
  Key _bracketKey = const ValueKey('default');

  bool    _loading = true;
  String? _error;

  // Separate match lists per round
  List<_ChampMatch> _elimMatches    = [];
  List<_ChampMatch> _r16Matches     = [];
  List<_ChampMatch> _qfMatches      = [];
  List<_ChampMatch> _sfMatches      = [];
  _ChampMatch?      _thirdPlace;
  _ChampMatch?      _finalMatch;

  final Set<int>        _scoredMatchIds = {};
  Map<int, _MatchScore> _matchScores    = {};

  List<String> get _rounds => _roundsForMode(_mode);

  List<_ChampMatch> get _allMatches => [
    ..._elimMatches,
    ..._r16Matches,
    ..._qfMatches,
    ..._sfMatches,
    ?_thirdPlace,
    ?_finalMatch,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: _roundsForMode(_mode).length, vsync: this);
    _loadBracket();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBracket() async {
    setState(() { _loading = true; _error = null; });
    try {
      // 1. Fetch group count to determine bracket mode
      final groupCount =
          await _ChampApiService.fetchGroupCount(widget.categoryId);
      final mode = _modeFromGroupCount(groupCount > 0 ? groupCount : 4);

      // 2. Fetch qualifiers — limit depends on mode
      final qualLimit = _qualifierLimit(mode);
      final qualifiers = await _ChampApiService.fetchQualifiers(
          widget.categoryId, limit: qualLimit);

      // 3. Fetch scored match IDs and scores
      Set<int> scoredIds = {};
      Map<int, _MatchScore> matchScores = {};
      try {
        scoredIds   = await _ChampApiService.fetchScoredMatchIds(widget.categoryId);
        matchScores = await _ChampApiService.fetchMatchScores(widget.categoryId);
      } catch (_) {}

      if (!mounted) return;

      // 4. Build match lists for the mode
      final built = _buildAllMatches(mode, List.from(qualifiers), matchScores);

      // 5. Swap TabController safely
      final rounds    = _roundsForMode(mode);
      final oldCtrl   = _tabController;
      _tabController  = TabController(length: rounds.length, vsync: this);
      WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl.dispose());

      setState(() {
        _mode          = mode;
        _elimMatches   = built.elim;
        _r16Matches    = built.r16;
        _qfMatches     = built.qf;
        _sfMatches     = built.sf;
        _thirdPlace    = built.thirdPlace;
        _finalMatch    = built.final_;
        _scoredMatchIds..clear()..addAll(scoredIds);
        _matchScores   = matchScores;
        _loading       = false;
        _bracketKey    = ValueKey('mode_${mode.name}');
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  int _qualifierLimit(_BracketMode mode) {
    switch (mode) {
      case _BracketMode.twoGroup:   return 4;
      case _BracketMode.threeGroup: return 6;
      case _BracketMode.fourGroup:  return 8;
      case _BracketMode.fiveGroup:  return 10;
      case _BracketMode.sixGroup:   return 12;
      case _BracketMode.sevenGroup: return 14;
      case _BracketMode.eightGroup: return 16;
      case _BracketMode.nineGroup:  return 18;
    }
  }

  ({
    List<_ChampMatch> elim,
    List<_ChampMatch> r16,
    List<_ChampMatch> qf,
    List<_ChampMatch> sf,
    _ChampMatch?      thirdPlace,
    _ChampMatch?      final_,
  }) _buildAllMatches(
    _BracketMode mode,
    List<_Qualifier> qualifiers,
    Map<int, _MatchScore> scores,
  ) {
    List<_ChampMatch> elim = [];
    List<_ChampMatch> r16  = [];
    List<_ChampMatch> qf   = [];
    List<_ChampMatch> sf   = [];
    _ChampMatch?      third;
    _ChampMatch?      final_;

    switch (mode) {
      // ── 2 groups: 4 teams → SF → 3RD → FINAL ────────────────────
      case _BracketMode.twoGroup:
        sf = _buildSFDirect(List.from(qualifiers));
        final r = _buildThirdAndFinal(sf, scores);
        third  = r.thirdPlace;
        final_ = r.final_;
        break;

      // ── 3 groups: 6 teams → ELIM(3) → QF → SF → FINAL ──────────
      case _BracketMode.threeGroup:
        elim = _buildElimMatches(List.from(qualifiers), 3);
        qf   = _qfPlaceholders();
        final r = _buildSFAndFinal(qf, scores);
        sf     = r.sf;
        final_ = r.final_;
        break;

      // ── 4 groups: 8 teams → QF → SF → 3RD → FINAL ──────────────
      case _BracketMode.fourGroup:
        qf = _buildQFFromQualifiers(List.from(qualifiers));
        final r = _buildSFAndFinal(qf, scores, includeThirdPlace: true);
        sf     = r.sf;
        third  = r.thirdPlace;
        final_ = r.final_;
        break;

      // ── 5 groups: 10 teams → ELIM(2) → QF → SF → FINAL ─────────
      case _BracketMode.fiveGroup:
        elim = _buildElimMatches(List.from(qualifiers), 2);
        // Top 8 seeds go direct to QF; 2 ELIM winners fill remaining 2 slots
        final top8 = List<_Qualifier>.from(
            qualifiers.take(qualifiers.length - 4).take(6));
        while (top8.length < 6) {
          top8.add(const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
        }
        // QF: slots 1–2 filled by ELIM winners (resolved from scores),
        //     slots 3–6 filled by top seeds
        qf = _buildQFWithElimSlots(elim, scores, top8);
        final r = _buildSFAndFinal(qf, scores);
        sf     = r.sf;
        final_ = r.final_;
        break;

      // ── 6 groups: 12 teams → ELIM(4) → QF → SF → FINAL ─────────
      case _BracketMode.sixGroup:
        elim = _buildElimMatches(List.from(qualifiers), 4);
        final top8q = qualifiers.take(qualifiers.length - 8).take(8).toList();
        qf = _buildQFWithElimSlots(elim, scores, top8q);
        final r = _buildSFAndFinal(qf, scores);
        sf     = r.sf;
        final_ = r.final_;
        break;

      // ── 7 groups: 14 teams → ELIM(6) → QF → SF → FINAL ─────────
      case _BracketMode.sevenGroup:
        elim = _buildElimMatches(List.from(qualifiers), 6);
        // Only top 2 seeds get BYEs to QF; 6 ELIM winners fill rest
        final top2 = qualifiers.take(2).toList();
        qf = _buildQFWithElimSlots(elim, scores, top2);
        final r = _buildSFAndFinal(qf, scores);
        sf     = r.sf;
        final_ = r.final_;
        break;

      // ── 8 groups: 16 teams → R16(8) → QF → SF → FINAL ──────────
      case _BracketMode.eightGroup:
        r16 = _buildR16Matches(List.from(qualifiers));
        qf  = _qfPlaceholders();
        final r = _buildSFAndFinal(qf, scores);
        sf     = r.sf;
        final_ = r.final_;
        break;

      // ── 9 groups: 18 teams → ELIM(2) → R16 → QF → SF → FINAL ───
      case _BracketMode.nineGroup:
        elim = _buildElimMatches(List.from(qualifiers), 2);
        // 16 teams in R16: top 14 get BYE to R16, 2 ELIM winners fill remaining
        final top16 = qualifiers.take(qualifiers.length - 4).take(14).toList();
        r16  = _buildR16WithElimSlots(elim, scores, top16);
        qf   = _qfPlaceholders();
        final r = _buildSFAndFinal(qf, scores);
        sf     = r.sf;
        final_ = r.final_;
        break;
    }

    return (
      elim:       elim,
      r16:        r16,
      qf:         qf,
      sf:         sf,
      thirdPlace: third,
      final_:     final_,
    );
  }

  /// Build QF with some slots pre-filled by BYE seeds and others by ELIM winners.
  /// [elimMatches] have IDs 501, 502, ...; their winners fill the lowest QF seeds.
  /// [byeSeeds] are the top-ranked teams that skip ELIM.
  List<_ChampMatch> _buildQFWithElimSlots(
    List<_ChampMatch> elimMatches,
    Map<int, _MatchScore> scores,
    List<_Qualifier> byeSeeds,
  ) {
    // Resolve ELIM winners (or 'TBD' if not yet scored)
    final elimWinners = elimMatches.map((m) => _winner(m.matchId, elimMatches, scores)).toList();

    // Build a pool of 8 teams for QF seeding:
    // byeSeeds (top ranked) + elim winners (lower ranked)
    final List<({String name, int id})> pool = [
      ...byeSeeds.map((q) => (name: q.teamName, id: q.teamId)),
      ...elimWinners,
    ];
    while (pool.length < 8) {
      pool.add((name: 'TBD', id: 0));
    }

    return [
      _ChampMatch(matchId: 101, round: 'QUARTER-FINAL',
          home: pool[0].name, homeId: pool[0].id,
          away: pool[7].name, awayId: pool[7].id),
      _ChampMatch(matchId: 102, round: 'QUARTER-FINAL',
          home: pool[1].name, homeId: pool[1].id,
          away: pool[6].name, awayId: pool[6].id),
      _ChampMatch(matchId: 103, round: 'QUARTER-FINAL',
          home: pool[2].name, homeId: pool[2].id,
          away: pool[5].name, awayId: pool[5].id),
      _ChampMatch(matchId: 104, round: 'QUARTER-FINAL',
          home: pool[3].name, homeId: pool[3].id,
          away: pool[4].name, awayId: pool[4].id),
    ];
  }

  /// Build R16 with ELIM winners filling the last slots (9-group mode).
  List<_ChampMatch> _buildR16WithElimSlots(
    List<_ChampMatch> elimMatches,
    Map<int, _MatchScore> scores,
    List<_Qualifier> byeSeeds, // 14 top seeds
  ) {
    final elimWinners = elimMatches.map((m) => _winner(m.matchId, elimMatches, scores)).toList();

    final List<({String name, int id})> pool = [
      ...byeSeeds.map((q) => (name: q.teamName, id: q.teamId)),
      ...elimWinners,
    ];
    while (pool.length < 16) {
      pool.add((name: 'TBD', id: 0));
    }

    return List.generate(8, (i) {
      final hi = pool[i];
      final lo = pool[15 - i];
      return _ChampMatch(
        matchId: _kR16Base + i,
        round:   'ROUND OF 16',
        home:    hi.name, homeId: hi.id,
        away:    lo.name, awayId: lo.id,
      );
    });
  }

  Future<void> _refreshData() async {
    try {
      final scoredIds   = await _ChampApiService.fetchScoredMatchIds(widget.categoryId);
      final matchScores = await _ChampApiService.fetchMatchScores(widget.categoryId);
      if (!mounted) return;

      // Re-resolve all advancement rounds from the latest scores,
      // using the already-built ELIM / R16 / QF match lists (team names
      // are fixed; only winners propagating forward change).
      final newQf     = _resolveQfFromScores(_elimMatches, _r16Matches, matchScores);
      final sfFinal   = _resolveSfAndFinalFromScores(newQf, matchScores);

      setState(() {
        _scoredMatchIds..clear()..addAll(scoredIds);
        _matchScores = matchScores;
        if (newQf.isNotEmpty) _qfMatches = newQf;
        if (sfFinal.sf.isNotEmpty) _sfMatches = sfFinal.sf;
        _thirdPlace = sfFinal.thirdPlace ?? _thirdPlace;
        _finalMatch = sfFinal.final_    ?? _finalMatch;
      });
    } catch (_) {}
  }

  /// Re-derive QF match slots from current ELIM / R16 scores.
  /// Returns the existing _qfMatches unchanged if no ELIM / R16 matches exist.
  List<_ChampMatch> _resolveQfFromScores(
    List<_ChampMatch> elim,
    List<_ChampMatch> r16,
    Map<int, _MatchScore> scores,
  ) {
    if (_qfMatches.isEmpty) return _qfMatches;

    // For modes fed by ELIM winners, rebuild the QF pool from the current
    // ELIM winners (now resolved from real scores) + BYE seeds already in QF.
    if (elim.isNotEmpty && r16.isEmpty) {
      final elimWinners = elim
          .map((m) => _winner(m.matchId, elim, scores))
          .toList();
      // Collect BYE seeds: QF slots whose team is NOT an ELIM-winner placeholder
      final elimWinnerIds = elimWinners.map((w) => w.id).where((id) => id != 0).toSet();
      final byeSlots = _qfMatches
          .expand((m) => [
                (name: m.home, id: m.homeId),
                (name: m.away, id: m.awayId),
              ])
          .where((t) => t.id != 0 && !elimWinnerIds.contains(t.id))
          .toSet()
          .toList();
      final List<({String name, int id})> pool = [
        ...byeSlots,
        ...elimWinners,
      ];
      while (pool.length < 8) { pool.add((name: 'TBD', id: 0)); }
      return [
        _ChampMatch(matchId: 101, round: 'QUARTER-FINAL',
            home: pool[0].name, homeId: pool[0].id,
            away: pool[7].name, awayId: pool[7].id),
        _ChampMatch(matchId: 102, round: 'QUARTER-FINAL',
            home: pool[1].name, homeId: pool[1].id,
            away: pool[6].name, awayId: pool[6].id),
        _ChampMatch(matchId: 103, round: 'QUARTER-FINAL',
            home: pool[2].name, homeId: pool[2].id,
            away: pool[5].name, awayId: pool[5].id),
        _ChampMatch(matchId: 104, round: 'QUARTER-FINAL',
            home: pool[3].name, homeId: pool[3].id,
            away: pool[4].name, awayId: pool[4].id),
      ];
    }

    // For R16 → QF: resolve R16 winners into QF slots (seeded 1v8, 2v7, etc.)
    if (r16.isNotEmpty) {
      final r16Winners = r16
          .map((m) => _winner(m.matchId, r16, scores))
          .toList();
      while (r16Winners.length < 8) { r16Winners.add((name: 'TBD', id: 0)); }
      return [
        _ChampMatch(matchId: 101, round: 'QUARTER-FINAL',
            home: r16Winners[0].name, homeId: r16Winners[0].id,
            away: r16Winners[7].name, awayId: r16Winners[7].id),
        _ChampMatch(matchId: 102, round: 'QUARTER-FINAL',
            home: r16Winners[1].name, homeId: r16Winners[1].id,
            away: r16Winners[6].name, awayId: r16Winners[6].id),
        _ChampMatch(matchId: 103, round: 'QUARTER-FINAL',
            home: r16Winners[2].name, homeId: r16Winners[2].id,
            away: r16Winners[5].name, awayId: r16Winners[5].id),
        _ChampMatch(matchId: 104, round: 'QUARTER-FINAL',
            home: r16Winners[3].name, homeId: r16Winners[3].id,
            away: r16Winners[4].name, awayId: r16Winners[4].id),
      ];
    }

    return _qfMatches; // QF seeded directly from qualifiers — no change needed
  }

  /// Re-derive SF / 3rd / Final from current QF (or SF for 2-group mode).
  ({
    List<_ChampMatch> sf,
    _ChampMatch?      thirdPlace,
    _ChampMatch?      final_,
  }) _resolveSfAndFinalFromScores(
    List<_ChampMatch> qf,
    Map<int, _MatchScore> scores,
  ) {
    // 2-group mode: SF matches were seeded from qualifiers directly — no QF exists
    if (_mode == _BracketMode.twoGroup) {
      final r = _buildThirdAndFinal(_sfMatches, scores);
      return (sf: _sfMatches, thirdPlace: r.thirdPlace, final_: r.final_);
    }
    if (qf.isEmpty) return (sf: [], thirdPlace: null, final_: null);

    final includeThirdPlace = _mode == _BracketMode.fourGroup;
    final r = _buildSFAndFinal(qf, scores, includeThirdPlace: includeThirdPlace);
    return (sf: r.sf, thirdPlace: r.thirdPlace, final_: r.final_);
  }

  List<_ChampMatch> _matchesForRound(String r) =>
      _allMatches.where((m) => m.round == r).toList();

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
    final submitted = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) =>
        SoccerScoringPage(
          matchId:           m.matchId,
          teamId:            m.homeId,
          awayTeamId:        m.awayId,
          refereeId:         1,
          homeTeamName:      m.home,
          awayTeamName:      m.away,
          isChampionship:    true,
          championshipRoundId: m.roundId,
        )));
    if (submitted == true && mounted) {
      // Full refresh: update scores AND propagate winners into the next round.
      await _refreshData();
    }
  }

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
            const Text('BACK', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold,
                fontSize: 14)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(widget.competitionTitle.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
          const Text('CHAMPIONSHIP',
              style: TextStyle(color: Colors.white70, fontSize: 10,
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
          bottom: BorderSide(color: const Color(0xFFD4A017), width: 3),
        ),
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
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CHAMPIONSHIP BRACKET',
                style: TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w900,
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
              style: const TextStyle(color: Color(0xFFD4A017),
                  fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ]),
        ),
      ]),
    ),

    KeyedSubtree(
      key: _bracketKey,
      child: Container(
        color: _accentColor,
        child: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            return TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              isScrollable: _rounds.length > 3,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              tabs: _rounds.asMap().entries.map((e) {
                final isSelected = _tabController.index == e.key;
                final round      = e.value;
                final count      = _matchesForRound(round).length;
                return Tab(
                  height: 46,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_roundIcon(round), size: 14,
                        color: isSelected ? Colors.white : Colors.white60),
                    const SizedBox(width: 5),
                    Text('${_roundLabel(round)} ($count)'),
                  ]),
                );
              }).toList(),
            );
          },
        ),
      ),
    ),
  ]);

  String _modeBadgeLabel(_BracketMode mode) {
    switch (mode) {
      case _BracketMode.twoGroup:   return '4 TEAMS';
      case _BracketMode.threeGroup: return '6 TEAMS';
      case _BracketMode.fourGroup:  return '8 TEAMS';
      case _BracketMode.fiveGroup:  return '10 TEAMS';
      case _BracketMode.sixGroup:   return '12 TEAMS';
      case _BracketMode.sevenGroup: return '14 TEAMS';
      case _BracketMode.eightGroup: return '16 TEAMS';
      case _BracketMode.nineGroup:  return '18 TEAMS';
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }

    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadBracket,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white),
          ),
        ],
      ));
    }

    return KeyedSubtree(
      key: _bracketKey,
      child: TabBarView(
        controller: _tabController,
        children: _rounds.map((round) {
          final matches = _matchesForRound(round)
            ..sort((a, b) {
              final aS = _scoredMatchIds.contains(a.matchId) ? 1 : 0;
              final bS = _scoredMatchIds.contains(b.matchId) ? 1 : 0;
              if (aS != bS) return aS.compareTo(bS);
              return a.matchId.compareTo(b.matchId);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_infoBannerText(round) != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _headerDark.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _accentColor.withOpacity(0.25), width: 1),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: _accentColor.withOpacity(0.7)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _infoBannerText(round)!,
                        style: TextStyle(
                          fontSize: 10,
                          color: _accentColor.withOpacity(0.75),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ]),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  color: _accentColor,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    itemCount: matches.length,
                    itemBuilder: (_, i) {
                      final m      = matches[i];
                      final scored = _scoredMatchIds.contains(m.matchId);
                      return _ChampMatchCard(
                        match:       m,
                        isScored:    scored,
                        matchScore:  _matchScores[m.matchId],
                        index:       i,
                        onTap:       scored ? null : () => _openScoring(m),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  String? _infoBannerText(String round) {
    switch (round) {
      case 'ELIM':
        return 'Elimination round — winners advance to the next stage. '
            'Teams with a BYE advance automatically.';
      case 'ROUND OF 16':
        return 'Round of 16 — 16 teams competing. '
            'QF slots are filled by winners from this round.';
      default:
        return null;
    }
  }
}

// ─────────────────────────────────────────────
// MATCH CARD  (reused from original, unchanged)
// ─────────────────────────────────────────────
class _ChampMatchCard extends StatelessWidget {
  final _ChampMatch   match;
  final bool          isScored;
  final _MatchScore?  matchScore;
  final int           index;
  final VoidCallback? onTap;

  const _ChampMatchCard({
    required this.match,
    required this.isScored,
    this.matchScore,
    required this.index,
    this.onTap,
  });

  bool get _isTbd => match.homeId == 0 || match.awayId == 0;

  String _result(bool isHome) {
    if (matchScore == null) return '';
    if (match.isByeMatch) {
      return isHome ? (match.homeBye ? 'BYE' : 'W') : (match.awayBye ? 'BYE' : 'W');
    }
    final h = matchScore!.homeScore;
    final a = matchScore!.awayScore;
    if (h == a) return 'D';
    return (isHome ? h > a : a > h) ? 'W' : 'L';
  }

  Widget _resultBadge(String label) {
    final Color bg, border, text;
    if (label == 'W' || label == 'BYE') {
      bg = const Color(0xFF1B5E20).withOpacity(0.85);
      border = Colors.greenAccent;
      text = Colors.greenAccent;
    } else if (label == 'L') {
      bg = const Color(0xFFB71C1C).withOpacity(0.75);
      border = Colors.redAccent;
      text = Colors.redAccent.shade100;
    } else {
      bg = const Color(0xFF424242).withOpacity(0.80);
      border = Colors.white54;
      text = Colors.white70;
    }
    return Container(
      width: label == 'BYE' ? 36 : 24, height: 24,
      decoration: BoxDecoration(
        color: bg, shape: label == 'BYE' ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: label == 'BYE' ? BorderRadius.circular(6) : null,
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: TextStyle(
              color: text, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }

  Color _scoreColor(String label) {
    if (label == 'W' || label == 'BYE') return Colors.greenAccent;
    if (label == 'L')                   return Colors.redAccent.shade100;
    return Colors.white60;
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = index % 2 == 0
        ? _accentColor
        : _accentColor.withOpacity(0.75);
    final cardColor = isScored ? _accentColor.withOpacity(0.50) : baseColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isScored
              ? []
              : [BoxShadow(color: _accentColor.withOpacity(0.25),
                    blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(children: [

          // ── Header strip ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            decoration: BoxDecoration(
              color: isScored ? _headerMuted : _headerDark,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(_roundIcon(match.round), size: 13, color: Colors.white70),
              const SizedBox(width: 6),
              Text('MATCH ${match.matchId}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
              const Spacer(),
              if (match.isByeMatch)
                _Chip(label: 'BYE', color: Colors.orangeAccent)
              else if (isScored)
                _Chip(label: 'SCORED', color: Colors.greenAccent)
              else if (_isTbd)
                _Chip(label: 'TBD', color: Colors.white54),
            ]),
          ),

          // ── Home / Away row ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HOME', style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
                    const SizedBox(height: 3),
                    Text(match.home,
                        style: TextStyle(
                          color: _isTbd ? Colors.white54 : Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w800,
                          height: 1.2),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if ((isScored || match.homeBye) && matchScore != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        if (_result(true).isNotEmpty) ...[
                          _resultBadge(_result(true)),
                          const SizedBox(width: 6),
                        ],
                        if (!match.homeBye)
                          Text('${matchScore!.homeScore} pts',
                              style: TextStyle(
                                  color: _scoreColor(_result(true)),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                      ]),
                    ],
                  ],
                )),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white30, width: 1),
                  ),
                  child: isScored && matchScore != null && !match.isByeMatch
                      ? Text(
                          '${matchScore!.homeScore} - ${matchScore!.awayScore}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w900))
                      : const Text('VS', style: TextStyle(
                              color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w900)),
                ),

                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('AWAY', style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
                    const SizedBox(height: 3),
                    Text(match.away,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _isTbd ? Colors.white54 : Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w800,
                          height: 1.2),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if ((isScored || match.awayBye) && matchScore != null) ...[
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                        if (!match.awayBye)
                          Text('${matchScore!.awayScore} pts',
                              style: TextStyle(
                                  color: _scoreColor(_result(false)),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        if (_result(false).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _resultBadge(_result(false)),
                        ],
                      ]),
                    ],
                  ],
                )),
              ],
            ),
          ),

          // ── Footer ────────────────────────────────────────────────
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
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      )),
                ),
                if (match.isByeMatch)
                  Row(children: [
                    Icon(Icons.arrow_forward_rounded,
                        color: Colors.orangeAccent.withOpacity(0.8), size: 12),
                    const SizedBox(width: 4),
                    Text('BYE — AUTO ADVANCE',
                        style: TextStyle(
                          color: Colors.orangeAccent.withOpacity(0.8),
                          fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        )),
                  ])
                else if (!isScored && !_isTbd)
                  Row(children: [
                    Text('TAP TO SCORE',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        )),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withOpacity(0.55), size: 14),
                  ])
                else if (isScored)
                  Row(children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: Colors.greenAccent.withOpacity(0.7), size: 12),
                    const SizedBox(width: 4),
                    Text('COMPLETED',
                        style: TextStyle(
                          color: Colors.greenAccent.withOpacity(0.7),
                          fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        )),
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
        style: TextStyle(color: color, fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
  );
}