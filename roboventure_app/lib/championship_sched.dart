// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'soccer_scoring.dart';
import 'api_config.dart';

// ─────────────────────────────────────────────
// THEME  (pure lavender — matches app accent)
// ─────────────────────────────────────────────
const Color _accentColor = Color(0xFF7D58B3);
const Color _headerDark  = Color(0xFF5A3A9A);
const Color _headerMuted = Color(0xFF9E9EAD);

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

class _ChampMatch {
  final int    matchId;
  final String round;
  final String home;
  final String away;
  final int    homeId;
  final int    awayId;

  const _ChampMatch({
    required this.matchId,
    required this.round,
    required this.home,
    required this.away,
    this.homeId = 0,
    this.awayId = 0,
  });
}

// ─────────────────────────────────────────────
// MATCH SCORE RESULT  (fetched after scoring)
// ─────────────────────────────────────────────
class _MatchScore {
  final int matchId;
  final int homeScore; // score_independentscore of home team row
  final int awayScore; // score_independentscore of away team row

  const _MatchScore({
    required this.matchId,
    required this.homeScore,
    required this.awayScore,
  });
}

// Primary rounds — R16 is injected at runtime only when 32 teams are registered
const _primaryRoundOrder = ['QUARTER-FINAL', 'SEMI-FINAL', 'FINAL'];
const _r16RoundOrder     = ['ROUND OF 16', 'QUARTER-FINAL', 'SEMI-FINAL', 'FINAL'];

IconData _roundIcon(String round) {
  switch (round) {
    case 'ROUND OF 16':    return Icons.filter_none_rounded;
    case 'QUARTER-FINAL': return Icons.shield_outlined;
    case 'SEMI-FINAL':    return Icons.sports_soccer;
    case 'FINAL':         return Icons.emoji_events_rounded;
    default:              return Icons.sports;
  }
}

String _roundLabel(String round) {
  switch (round) {
    case 'ROUND OF 16':    return 'R16';
    case 'QUARTER-FINAL': return 'QF';
    case 'SEMI-FINAL':    return 'SF';
    case 'FINAL':         return 'FINAL';
    default:              return round;
  }
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class _ChampApiService {
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

  /// Returns the total number of registered teams for [categoryId].
  /// Used to decide whether to show the Round of 16.
  static Future<int> fetchTeamCount(int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.scoring}?action=get_team_count&category_id=$categoryId');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return int.tryParse(data['count'].toString()) ?? 0;
    }
    throw Exception('get_team_count failed [${response.statusCode}]');
  }

  /// Returns match IDs where the match has been scored for [categoryId].
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

  /// Returns score results (home/away scores) for all scored championship matches.
  static Future<Map<int, _MatchScore>> fetchMatchScores(int categoryId) async {
    final url = Uri.parse(
        '${ApiConfig.getScoredMatches}?category_id=$categoryId');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return {};

    final List<dynamic> data = json.decode(response.body);
    // Group by match_id — ideally 2 rows per match (home + away team),
    // but we handle 1-row entries gracefully so a partial save never hides scores.
    final Map<int, List<Map<String, dynamic>>> byMatch = {};
    for (final j in data) {
      final mid = int.tryParse(j['match_id'].toString()) ?? 0;
      if (mid == 0) continue;
      // Only championship match IDs
      if (![101,102,103,104,201,202,301,
            1001,1002,1003,1004,1005,1006,
            1007,1008,1009,1010,1011,1012,
            1013,1014,1015,1016].contains(mid)) continue;
      byMatch.putIfAbsent(mid, () => []).add(j as Map<String, dynamic>);
    }

    final Map<int, _MatchScore> result = {};
    byMatch.forEach((mid, rows) {
      // FIX: was `< 2` — silently skipped every match with only 1 stored row.
      // Now we accept 1 or 2 rows; missing away score safely defaults to 0.
      if (rows.isEmpty) return;

      // ORDER BY score_id DESC means the row inserted LAST (away team, higher
      // teamschedule_id) arrives in rows[0].  Swap so that:
      //   rows[0] → away team score  (inserted second, higher score_id)
      //   rows[1] → home team score  (inserted first,  lower  score_id)
      // FIX: was reading rows[0] as home and rows[1] as away — pts were swapped.
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
// BUILD QF MATCHES FROM QUALIFIERS
// Seeded bracket: #1 vs #8, #2 vs #7, #3 vs #6, #4 vs #5
// ─────────────────────────────────────────────
List<_ChampMatch> _buildQFMatches(List<_Qualifier> qualifiers) {
  // Pad to 8 with TBD if fewer than 8 qualified
  while (qualifiers.length < 8) {
    qualifiers.add(const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
  }

  return [
    _ChampMatch(matchId: 101, round: 'QUARTER-FINAL',
        home: qualifiers[0].teamName, homeId: qualifiers[0].teamId,
        away: qualifiers[7].teamName, awayId: qualifiers[7].teamId),
    _ChampMatch(matchId: 102, round: 'QUARTER-FINAL',
        home: qualifiers[1].teamName, homeId: qualifiers[1].teamId,
        away: qualifiers[6].teamName, awayId: qualifiers[6].teamId),
    _ChampMatch(matchId: 103, round: 'QUARTER-FINAL',
        home: qualifiers[2].teamName, homeId: qualifiers[2].teamId,
        away: qualifiers[5].teamName, awayId: qualifiers[5].teamId),
    _ChampMatch(matchId: 104, round: 'QUARTER-FINAL',
        home: qualifiers[3].teamName, homeId: qualifiers[3].teamId,
        away: qualifiers[4].teamName, awayId: qualifiers[4].teamId),
  ];
}

// ─────────────────────────────────────────────
// BUILD R16 MATCHES FROM 32 QUALIFIERS
// Seeded bracket: #1 vs #32, #2 vs #31 … #16 vs #17
// ─────────────────────────────────────────────
List<_ChampMatch> _buildR16Matches(List<_Qualifier> qualifiers) {
  // Pad to 32 with TBD if needed
  while (qualifiers.length < 32) {
    qualifiers.add(const _Qualifier(teamId: 0, teamName: 'TBD', totalScore: 0));
  }

  return List.generate(16, (i) {
    final hi = qualifiers[i];
    final lo = qualifiers[31 - i];
    return _ChampMatch(
      matchId: 1000 + i + 1,
      round:   'ROUND OF 16',
      home:    hi.teamName, homeId: hi.teamId,
      away:    lo.teamName, awayId: lo.teamId,
    );
  });
}


// ─────────────────────────────────────────────
// BRACKET ADVANCEMENT HELPERS
// Seeded pairing:
//   SF201 = winner(QF101) vs winner(QF102)
//   SF202 = winner(QF103) vs winner(QF104)
//   Final301 = winner(SF201) vs winner(SF202)
// ─────────────────────────────────────────────

/// Returns the winner team info (name, id) of [matchId] from [qfMatches]
/// and [matchScores], or null/TBD if the match hasn't been scored yet.
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

  if (score.homeScore > score.awayScore) {
    return (name: match.home, id: match.homeId);
  } else if (score.awayScore > score.homeScore) {
    return (name: match.away, id: match.awayId);
  }
  // Draw — home team advances (can be changed to a tiebreaker rule)
  return (name: match.home, id: match.homeId);
}

/// Builds the SF and Final matches by resolving QF/SF winners.
List<_ChampMatch> _buildSFAndFinal(
  List<_ChampMatch> qfMatches,
  Map<int, _MatchScore> matchScores,
) {
  // SF feeds: QF101→SF201 home, QF102→SF201 away
  //           QF103→SF202 home, QF104→SF202 away
  final w101 = _winner(101, qfMatches, matchScores);
  final w102 = _winner(102, qfMatches, matchScores);
  final w103 = _winner(103, qfMatches, matchScores);
  final w104 = _winner(104, qfMatches, matchScores);

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

  // Final feeds: SF201 winner vs SF202 winner
  // Pass the just-built SF matches so _winner can look up names/IDs
  final sfMatches = [sf1, sf2];
  final w201 = _winner(201, sfMatches, matchScores);
  final w202 = _winner(202, sfMatches, matchScores);

  final finalMatch = _ChampMatch(
    matchId: 301, round: 'FINAL',
    home: w201.name, homeId: w201.id,
    away: w202.name, awayId: w202.id,
  );

  return [sf1, sf2, finalMatch];
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

  // ── R16 flag ── true only when exactly 32 teams are registered
  bool _showR16 = false;

  List<String> get _roundOrder =>
      _showR16 ? _r16RoundOrder : _primaryRoundOrder;

  // Single TabController — replaced safely via postFrameCallback.
  // Never disposed mid-build; always swapped after the frame completes.
  late TabController _tabController;

  // Changing this key forces the entire TabBar + TabBarView subtree to
  // remount cleanly whenever the bracket mode switches (3 tabs ↔ 4 tabs).
  Key _bracketKey = const ValueKey('primary');

  // Fetch state
  bool              _loading         = true;
  String?           _error;
  List<_ChampMatch> _qfMatches       = [];
  List<_ChampMatch> _r16Matches      = [];
  List<_ChampMatch> _sfAndFinalMatches = [];

  // All matches combined (R16 prepended only when active)
  List<_ChampMatch> get _allMatches => [
    if (_showR16) ..._r16Matches,
    ..._qfMatches,
    ..._sfAndFinalMatches,
  ];

  final Set<int>          _scoredMatchIds = {};
  Map<int, _MatchScore>   _matchScores    = {};

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _primaryRoundOrder.length, vsync: this);
    _loadQualifiers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadQualifiers() async {
    setState(() { _loading = true; _error = null; });
    try {
      // 1. Determine bracket mode from registered team count
      final teamCount =
          await _ChampApiService.fetchTeamCount(widget.categoryId);
      // R16 activates when 32 or more teams have qualification scores
      final useR16 = teamCount >= 32;

      // 2. Fetch qualifier data for the appropriate bracket
      List<_ChampMatch> r16 = [];
      List<_ChampMatch> qf;

      if (useR16) {
        final qualifiers = await _ChampApiService.fetchQualifiers(
            widget.categoryId, limit: 32);
        r16 = _buildR16Matches(List.from(qualifiers));
        // QF placeholders — filled by R16 winners
        qf = List.generate(4, (i) => _ChampMatch(
          matchId: 101 + i,
          round:   'QUARTER-FINAL',
          home:    'R16 Match ${i * 2 + 1} Winner',
          away:    'R16 Match ${i * 2 + 2} Winner',
        ));
      } else {
        final qualifiers =
            await _ChampApiService.fetchQualifiers(widget.categoryId);
        qf = _buildQFMatches(List.from(qualifiers));
      }

      if (!mounted) return;

      // 3. Fetch already-scored match IDs from the API so that scored state
      //    is restored even after navigating away and back to this screen.
      //    Wrapped in its own try/catch — a failure here (e.g. no scores yet)
      //    must never crash the whole screen load.
      Set<int> scoredIds = {};
      Map<int, _MatchScore> matchScores = {};
      try {
        scoredIds   = await _ChampApiService.fetchScoredMatchIds(widget.categoryId);
        matchScores = await _ChampApiService.fetchMatchScores(widget.categoryId);
      } catch (_) {
        // No scores yet or endpoint unavailable — safe to proceed with empty set.
      }

      if (!mounted) return;

      // 4. Swap TabController safely:
      //    - Create the new controller first.
      //    - Schedule disposal of the OLD one for AFTER this frame so no
      //      widget still in the tree holds a reference to a disposed object.
      //    - Assign _bracketKey inside setState to remount Tab widgets.
      final newLength =
          useR16 ? _r16RoundOrder.length : _primaryRoundOrder.length;
      final oldController = _tabController;
      _tabController = TabController(length: newLength, vsync: this);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => oldController.dispose());

      setState(() {
        _showR16    = useR16;
        _r16Matches = r16;
        _qfMatches  = qf;
        _scoredMatchIds
          ..clear()
          ..addAll(scoredIds);
        _matchScores        = matchScores;
        _sfAndFinalMatches  = _buildSFAndFinal(qf, matchScores);
        _loading    = false;
        _bracketKey = ValueKey(useR16 ? 'r16' : 'primary');
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Lightweight refresh — re-fetches scored IDs and scores only,
  /// without rebuilding the entire bracket. Used by pull-to-refresh and
  /// the refresh icon button, matching qualification_sched behaviour.
  Future<void> _refreshData() async {
    try {
      final scoredIds   = await _ChampApiService.fetchScoredMatchIds(widget.categoryId);
      final matchScores = await _ChampApiService.fetchMatchScores(widget.categoryId);
      if (mounted) {
        setState(() {
          _scoredMatchIds..clear()..addAll(scoredIds);
          _matchScores       = matchScores;
          // Re-derive SF and Final slots from the latest QF/SF scores
          _sfAndFinalMatches = _buildSFAndFinal(_qfMatches, matchScores);
        });
      }
    } catch (_) {
      // Silently ignore — stale data is better than a crash on pull-to-refresh.
    }
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
          matchId:        m.matchId,
          teamId:         m.homeId,
          awayTeamId:     m.awayId,
          refereeId:      1,
          homeTeamName:   m.home,
          awayTeamName:   m.away,
          isChampionship: true,
        )));
    if (submitted == true && mounted) {
      // Re-fetch from API to stay in sync with the backend rather than
      // relying solely on in-memory state (which is lost on navigation).
      try {
        final scoredIds   = await _ChampApiService.fetchScoredMatchIds(widget.categoryId);
        final matchScores = await _ChampApiService.fetchMatchScores(widget.categoryId);
        if (mounted) {
          setState(() {
            _scoredMatchIds..clear()..addAll(scoredIds);
            _matchScores       = matchScores;
            // Re-derive SF and Final slots from the latest QF/SF scores
            _sfAndFinalMatches = _buildSFAndFinal(_qfMatches, matchScores);
          });
        }
      } catch (_) {
        // Fallback: at least mark this match locally if the fetch fails.
        if (mounted) setState(() => _scoredMatchIds.add(m.matchId));
      }
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

  // ── HEADER ──────────────────────────────────────────────────────────────
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

  // ── BANNER + TAB BAR ────────────────────────────────────────────────────
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
              '${_allMatches.length} matches · ${_roundOrder.length} rounds',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.65), fontSize: 11)),
          ]),
        ),
        // Teams badge — shows qualifier count or loading indicator
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
            _loading ? '...' : '${_showR16 ? 32 : _qfMatches.length * 2} TEAMS',
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
            final order = _roundOrder;
            return TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              tabs: order.asMap().entries.map((e) {
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

  // ── BODY ────────────────────────────────────────────────────────────────
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
            onPressed: _loadQualifiers,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white),
          ),
        ],
      ));
    }

    // _bracketKey changes when the bracket mode switches, which forces
    // TabBar + TabBarView to fully remount with the new controller length,
    // eliminating the _dependents / null-check cascade errors.
    return KeyedSubtree(
      key: _bracketKey,
      child: TabBarView(
        controller: _tabController,
        children: _roundOrder.map((round) {
          final matches = _matchesForRound(round)
            ..sort((a, b) {
              final aS = _scoredMatchIds.contains(a.matchId) ? 1 : 0;
              final bS = _scoredMatchIds.contains(b.matchId) ? 1 : 0;
              if (aS != bS) return aS.compareTo(bS);
              return a.matchId.compareTo(b.matchId);
            });
          // Use a LayoutBuilder → Column with fixed+flexible children so
          // the list never tries to measure itself in an unbounded context
          // (which was causing the 99 273 px overflow).
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── R16 info banner ────────────────────────────────────────
              if (round == 'ROUND OF 16')
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
                        '32 teams registered — Round of 16 is active. '
                        'QF slots are filled by winners from this round.',
                        style: TextStyle(
                          fontSize: 10,
                          color: _accentColor.withOpacity(0.75),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ]),
                ),
              // ── Match list — RefreshIndicator enables pull-to-refresh,
              //    matching qualification_sched behaviour. Expanded keeps
              //    the list in bounded space (prevents overflow).
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
}

// ─────────────────────────────────────────────
// MATCH CARD
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

  // W/L/D helpers
  String _result(bool isHome) {
    if (matchScore == null) return '';
    final h = matchScore!.homeScore;
    final a = matchScore!.awayScore;
    if (h == a) return 'D';
    return (isHome ? h > a : a > h) ? 'W' : 'L';
  }

  // Circular W/L/D badge — matches qualification_sched design exactly
  Widget _resultBadge(String label) {
    final Color bg;
    final Color border;
    final Color text;

    switch (label) {
      case 'W':
        bg     = const Color(0xFF1B5E20).withOpacity(0.85);
        border = Colors.greenAccent;
        text   = Colors.greenAccent;
        break;
      case 'L':
        bg     = const Color(0xFFB71C1C).withOpacity(0.75);
        border = Colors.redAccent;
        text   = Colors.redAccent.shade100;
        break;
      default: // 'D'
        bg     = const Color(0xFF424242).withOpacity(0.80);
        border = Colors.white54;
        text   = Colors.white70;
    }

    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: TextStyle(
              color: text, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  // Score text colour — matches qualification_sched
  Color _scoreColor(String label) {
    switch (label) {
      case 'W': return Colors.greenAccent;
      case 'L': return Colors.redAccent.shade100;
      default:  return Colors.white60;
    }
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

          // ── Header strip ──────────────────────
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
              if (isScored)
                _Chip(label: 'SCORED', color: Colors.greenAccent)
              else if (_isTbd)
                _Chip(label: 'TBD', color: Colors.white54),
            ]),
          ),

          // ── Home / Away row ───────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── HOME side ──────────────────
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
                    if (isScored && matchScore != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        // W/L/D circular badge
                        if (_result(true).isNotEmpty) ...[
                          _resultBadge(_result(true)),
                          const SizedBox(width: 6),
                        ],
                        // Score pts
                        Text('${matchScore!.homeScore} pts',
                            style: TextStyle(
                                color: _scoreColor(_result(true)),
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ],
                  ],
                )),

                // ── VS / SCORE centre ──────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white30, width: 1),
                  ),
                  child: isScored && matchScore != null
                      ? Text(
                          '${matchScore!.homeScore} - ${matchScore!.awayScore}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w900))
                      : const Text('VS', style: TextStyle(
                              color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w900)),
                ),

                // ── AWAY side ──────────────────
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
                    if (isScored && matchScore != null) ...[
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                        // Score pts
                        Text('${matchScore!.awayScore} pts',
                            style: TextStyle(
                                color: _scoreColor(_result(false)),
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                        // W/L/D circular badge
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

          // ── Footer ────────────────────────────
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
                if (!isScored && !_isTbd)
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