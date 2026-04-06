// ignore_for_file: unused_element_parameter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'mbot1_scoring.dart';
import 'mbot2_scoring.dart';
import 'timer_scoring.dart';
import 'soccer_scoring.dart';
import 'api_config.dart';

const Color _accentColor = Color(0xFF7D58B3);

// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────
class ArenaInfo {
  final int arenaId;
  final int arenaNumber;
  final String arenaName;

  const ArenaInfo({
    required this.arenaId,
    required this.arenaNumber,
    required this.arenaName,
  });

  factory ArenaInfo.fromJson(Map<String, dynamic> json) => ArenaInfo(
        arenaId:     int.tryParse(json['arena_id']?.toString() ?? '0') ?? 0,
        arenaNumber: int.tryParse(json['arena_number']?.toString() ?? '0') ?? 0,
        arenaName:   json['arena_name']?.toString() ?? 'Arena',
      );
}

class ScheduleEntry {
  final int    teamscheduleId;
  final int    matchId;
  final int    matchNumber;
  final int    teamId;
  final String teamIdDisplay;
  final String teamName;
  final int    refereeId;
  final int    arenaNumber;
  final int    awayTeamId;
  final String homeTeamName;
  final String awayTeamName;
  final String bracketType;  // e.g. 'group', 'quarter-finals', 'final', etc.

  const ScheduleEntry({
    required this.teamscheduleId,
    required this.matchId,
    required this.matchNumber,
    required this.teamId,
    required this.teamIdDisplay,
    required this.teamName,
    required this.refereeId,
    required this.arenaNumber,
    this.awayTeamId   = 0,
    this.homeTeamName = '',
    this.awayTeamName = '',
    this.bracketType  = '',
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    String rawId       = (json['team_id'] ?? '0').toString();
    String numericPart = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericPart.isEmpty) numericPart = '0';
    String paddedId    = numericPart.padLeft(3, '0');

    int safeInt(dynamic v) => int.tryParse((v ?? '0').toString()) ?? 0;

    return ScheduleEntry(
      teamscheduleId: safeInt(json['teamschedule_id']),
      matchId:        safeInt(json['match_id']),
      matchNumber:    safeInt(json['match_number']),
      teamId:         int.tryParse(numericPart) ?? 0,
      teamIdDisplay:  'C${paddedId}R',
      teamName:       (json['team_name'] ?? 'Unknown Team').toString(),
      refereeId:      safeInt(json['referee_id']),
      arenaNumber:    safeInt(json['arena_number']),
      bracketType:    (json['bracket_type'] ?? '').toString(),
    );
  }
}

// Soccer match row — pairs home + away from 2 ScheduleEntry rows
class _SoccerMatchRow {
  final int    matchId;
  final String home;
  final int    homeId;
  final int    homeRefereeId;
  final String away;
  final int    awayId;
  final int    arena;
  final bool   isScored;
  // Winner info — only meaningful when isScored == true
  // 'home' | 'away' | 'draw' | '' (not scored yet)
  final String winner;
  final int    homeScore;
  final int    awayScore;

  const _SoccerMatchRow({
    required this.matchId,
    required this.home,
    required this.homeId,
    required this.homeRefereeId,
    required this.away,
    required this.awayId,
    required this.arena,
    this.isScored  = false,
    this.winner    = '',
    this.homeScore = 0,
    this.awayScore = 0,
  });
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class _ScheduleApiService {
  static Future<List<ArenaInfo>> fetchArenas(int categoryId) async {
    final url = Uri.parse('${ApiConfig.getArena}?category_id=$categoryId');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((j) => ArenaInfo.fromJson(j)).toList();
    }
    try {
      final body = json.decode(response.body);
      throw Exception('Arena error: ${body['error'] ?? response.statusCode}');
    } catch (_) {
      throw Exception('get_arena failed [${response.statusCode}]');
    }
  }

  // Fetch qualification-round matches for a category.
  //
  // Soccer uses bracket_type = 'group' — filter at both DB and client level
  // so championship knockout rounds don't bleed in.
  //
  // All other categories only have qualification matches (no group stage),
  // so we fetch everything for the category and exclude known championship
  // bracket types client-side.
  static const _championshipBrackets = {
    'elimination',
    'round-of-32',
    'round-of-16',
    'round-of-8',
    'quarter-finals',
    'semi-finals',
    'third-place',
    'final',
  };

  static Future<List<ScheduleEntry>> fetchSchedule(
      int categoryId, {bool isSoccer = false}) async {
    final Uri url;
    if (isSoccer) {
      // Soccer: request only group-stage matches from the server.
      url = Uri.parse(
        '${ApiConfig.getTeamSchedule}?category_id=$categoryId&bracket_type=group',
      );
    } else {
      // Other categories: fetch all matches; championship rounds are
      // excluded client-side below.
      url = Uri.parse(
        '${ApiConfig.getTeamSchedule}?category_id=$categoryId',
      );
    }

    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final entries = data
          .map((j) => ScheduleEntry.fromJson(j))
          .where((e) {
            if (isSoccer) {
              // Soccer: keep only group-stage entries (belt-and-suspenders).
              return e.bracketType == 'group';
            } else {
              // Other categories: drop any championship-bracket rows so this
              // screen never shows knockout matches.
              return !_championshipBrackets.contains(e.bracketType);
            }
          })
          .toList();
      entries.sort((a, b) {
        final byMatch = a.matchId.compareTo(b.matchId);
        if (byMatch != 0) return byMatch;
        return a.teamscheduleId.compareTo(b.teamscheduleId);
      });
      return entries;
    }
    throw Exception('get_teamschedule failed [${response.statusCode}]');
  }

  // Qualification-only scored match IDs.
  //
  // Soccer    → keep only bracket_type = 'group'.
  // Non-soccer → exclude championship bracket types; keep everything else
  //              (qualification matches for other categories have their own
  //               bracket_type or 'group', but never knockout labels).
  static Future<Set<String>> fetchScoredMatchIds(
      int categoryId, {bool isSoccer = false}) async {
    final url = Uri.parse('${ApiConfig.getScoredMatches}?category_id=$categoryId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .where((j) {
              final bt = j['bracket_type']?.toString() ?? '';
              if (isSoccer) return bt == 'group';
              return !_championshipBrackets.contains(bt);
            })
            .map((j) {
              final matchId = j['match_id']?.toString() ?? '0';
              final teamId  = j['team_id']?.toString()  ?? '0';
              return '${matchId}_${teamId}';
            })
            .toSet();
      }
    } catch (_) {}
    return {};
  }

  /// Returns a map of "matchId_teamId" → score (int).
  ///
  /// Soccer    → bracket_type = 'group' only.
  /// Non-soccer → excludes championship brackets (qualification rounds only).
  static Future<Map<String, int>> fetchScoreMap(
      int categoryId, {bool isSoccer = false}) async {
    final url = Uri.parse('${ApiConfig.getScoredMatches}?category_id=$categoryId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final Map<String, int> map = {};
        for (final j in data) {
          final bt = j['bracket_type']?.toString() ?? '';
          if (isSoccer) {
            if (bt != 'group') continue;
          } else {
            if (_championshipBrackets.contains(bt)) continue;
          }
          final matchId = j['match_id']?.toString() ?? '0';
          final teamId  = j['team_id']?.toString()  ?? '0';
          final score   = int.tryParse(j['score_totalscore']?.toString() ?? '0') ?? 0;
          map['${matchId}_${teamId}'] = score;
        }
        return map;
      }
    } catch (_) {}
    return {};
  }
}

// ─────────────────────────────────────────────
// HELPER — detect soccer category
// ─────────────────────────────────────────────
bool _isSoccer(String title) =>
    title.toLowerCase().contains('soccer') ||
    title.toLowerCase().contains('football');

// ─────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────
class QualificationScheduleScreen extends StatefulWidget {
  final int    categoryId;
  final String competitionTitle;
  final Color  themeColor;

  const QualificationScheduleScreen({
    super.key,
    required this.categoryId,
    required this.competitionTitle,
    required this.themeColor,
  });

  @override
  State<QualificationScheduleScreen> createState() =>
      _QualificationScheduleScreenState();
}

class _QualificationScheduleScreenState
    extends State<QualificationScheduleScreen>
    with TickerProviderStateMixin {

  List<ArenaInfo> _arenas        = [];
  bool            _arenasLoading = true;
  String?         _arenasError;
  TabController?  _tabController;

  final Map<int, Future<List<ScheduleEntry>>> _scheduleFutures = {};
  Set<String>    _scoredMatchIds = {};
  Map<String, int> _scoreMap    = {};

  bool get _soccer => _isSoccer(widget.competitionTitle);

  @override
  void initState() {
    super.initState();
    _loadArenas();
    _refreshScoredIds();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _refreshScoredIds() async {
    final results = await Future.wait([
      _ScheduleApiService.fetchScoredMatchIds(widget.categoryId, isSoccer: _soccer),
      _ScheduleApiService.fetchScoreMap(widget.categoryId, isSoccer: _soccer),
    ]);
    if (mounted) {
      setState(() {
        _scoredMatchIds = results[0] as Set<String>;
        _scoreMap       = results[1] as Map<String, int>;
      });
    }
  }

  Future<void> _loadArenas() async {
    setState(() { _arenasLoading = true; _arenasError = null; });
    try {
      final arenas = await _ScheduleApiService.fetchArenas(widget.categoryId);
      final oldCtrl = _tabController;
      final tc = TabController(length: arenas.length, vsync: this);
      setState(() {
        _arenas        = arenas;
        _tabController = tc;
        _arenasLoading = false;
      });
      // Dispose old controller AFTER the frame rebuilds with the new one
      WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl?.dispose());
      if (arenas.isNotEmpty) _ensureSchedule();
      tc.addListener(() {
        if (!tc.indexIsChanging) _ensureSchedule();
      });
    } catch (e) {
      setState(() { _arenasError = e.toString(); _arenasLoading = false; });
    }
  }

  void _ensureSchedule([int? arenaNumber]) {
    // We now fetch ALL matches in one call keyed by 0
    if (!_scheduleFutures.containsKey(0)) {
      setState(() {
        _scheduleFutures[0] =
            _ScheduleApiService.fetchSchedule(widget.categoryId, isSoccer: _soccer);
      });
    }
  }

  Future<void> _refreshSchedule([int? arenaNumber]) async {
    setState(() {
      _scheduleFutures[0] =
          _ScheduleApiService.fetchSchedule(widget.categoryId, isSoccer: _soccer);
    });
    await Future.wait([
      _scheduleFutures[0]!,
      _refreshScoredIds(),
    ]);
  }

  Future<void> _openScoringPage(BuildContext context, ScheduleEntry entry) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) {
      if (widget.competitionTitle.toLowerCase().contains('emerging innovators')) {
        return Mbot2ScoringPage(
            matchId: entry.matchId, teamId: entry.teamId,
            refereeId: entry.refereeId);
      }
      if (widget.competitionTitle.toLowerCase().contains('line tracing') ||
          widget.competitionTitle.toLowerCase().contains('navigation')) {
        return TimerScoringPage(
            matchId: entry.matchId, teamId: entry.teamId,
            refereeId: entry.refereeId);
      }
      if (_soccer) {
        return SoccerScoringPage(
            matchId:      entry.matchId,
            teamId:       entry.teamId,
            awayTeamId:   entry.awayTeamId,
            refereeId:    entry.refereeId,
            homeTeamName: entry.homeTeamName,
            awayTeamName: entry.awayTeamName);
      }
      return Mbot1ScoringPage(
          matchId: entry.matchId, teamId: entry.teamId,
          refereeId: entry.refereeId);
    }));
    _refreshScoredIds();
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
          Text(_soccer ? 'MATCH SCHEDULE' : 'QUALIFICATION',
              style: const TextStyle(color: Colors.white70, fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ]),
      ],
    ),
  );

  Widget _buildTitleBar() => Column(children: [
    // ── Banner ─────────────────────────────────────────────
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5A3A9A), Color(0xFF7D58B3)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4A017), width: 3),
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
          child: Icon(
            _soccer
                ? Icons.sports_soccer
                : Icons.precision_manufacturing_outlined,
            color: const Color(0xFFD4A017), size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _soccer ? 'MATCH SCHEDULE' : 'QUALIFICATION SCHEDULE',
              style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w900,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 2),
            Text(
              widget.competitionTitle,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.65), fontSize: 11),
            ),
          ]),
        ),
        if (!_arenasLoading && _arenas.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A017).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFD4A017).withOpacity(0.6), width: 1),
            ),
            child: Row(children: [
              const Icon(Icons.stadium_outlined,
                  color: Color(0xFFD4A017), size: 14),
              const SizedBox(width: 5),
              Text(
                '${_arenas.length} ${_arenas.length == 1 ? 'ARENA' : 'ARENAS'}',
                style: const TextStyle(color: Color(0xFFD4A017),
                    fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ]),
          ),
      ]),
    ),
    if (!_arenasLoading && _arenasError == null && _arenas.isNotEmpty)
      Container(color: _accentColor, child: _buildTabBar()),
  ]);

  Widget _buildTabBar() => AnimatedBuilder(
    animation: _tabController!,
    builder: (context, _) => TabBar(
      controller: _tabController,
      isScrollable: _arenas.length > 3,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      indicatorColor: Colors.white,
      indicatorWeight: 3,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      tabs: _arenas.asMap().entries.map((entry) {
        final isSelected = _tabController!.index == entry.key;
        return Tab(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.stadium_outlined, size: 15,
                color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 5),
            Text(entry.value.arenaName.toUpperCase()),
          ]),
        ));
      }).toList(),
    ),
  );

  Widget _buildBody() {
    if (_arenasLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }
    if (_arenasError != null) {
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: _loadArenas,
          color: _accentColor,
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 12),
                  Text(_arenasError!, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadArenas,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor, foregroundColor: Colors.white),
                  ),
                ],
              )),
            ),
          ),
        ),
      );
    }
    if (_arenas.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: _loadArenas,
          color: _accentColor,
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: const Center(child: Text('No matches found for this category.')),
            ),
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: _arenas.map((arena) => _ArenaScheduleView(
        arenaNumber:    arena.arenaNumber,
        scoredMatchIds: _scoredMatchIds,
        scoreMap:       _scoreMap,
        // All arenas share the same future — filtered locally by arena_number
        scheduleFuture: _scheduleFutures[0],
        isSoccer:       _soccer,
        onRefresh:      () => _refreshSchedule(),
        onTabVisible:   () => _ensureSchedule(),
        onOpenScoring:  (entry) => _openScoringPage(context, entry),
      )).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// PER-ARENA SCHEDULE VIEW
// ─────────────────────────────────────────────
class _ArenaScheduleView extends StatelessWidget {
  final int    arenaNumber;
  final bool   isSoccer;
  final Set<String>    scoredMatchIds;
  final Map<String, int> scoreMap;
  final Future<List<ScheduleEntry>>? scheduleFuture;
  final Future<void> Function() onRefresh;
  final VoidCallback onTabVisible;
  final void Function(ScheduleEntry) onOpenScoring;

  const _ArenaScheduleView({
    required this.arenaNumber,
    required this.isSoccer,
    required this.scoredMatchIds,
    required this.scoreMap,
    required this.scheduleFuture,
    required this.onRefresh,
    required this.onTabVisible,
    required this.onOpenScoring,
  });

  // Pivot flat entries into home+away rows for soccer.
  // Sort by teamschedule_id first — lower ID = HOME, matching Windows app.
  List<_SoccerMatchRow> _pivot(
      List<ScheduleEntry> entries,
      Set<String> scoredMatchIds,
      Map<String, int> scoreMap) {
    final sorted = List<ScheduleEntry>.from(entries)
      ..sort((a, b) => (a.teamscheduleId).compareTo(b.teamscheduleId));

    final Map<int, _SoccerMatchRow?> byMatch = {};
    for (final e in sorted) {
      if (!byMatch.containsKey(e.matchId)) {
        byMatch[e.matchId] = _SoccerMatchRow(
          matchId:       e.matchId,
          home:          e.teamName,
          homeId:        e.teamId,
          homeRefereeId: e.refereeId,
          away:          '',
          awayId:        0,
          arena:         e.arenaNumber,
        );
      } else {
        final existing = byMatch[e.matchId]!;
        byMatch[e.matchId] = _SoccerMatchRow(
          matchId:       existing.matchId,
          home:          existing.home,
          homeId:        existing.homeId,
          homeRefereeId: existing.homeRefereeId,
          away:          e.teamName,
          awayId:        e.teamId,
          arena:         existing.arena,
        );
      }
    }

    final result = byMatch.values.whereType<_SoccerMatchRow>().toList()
      ..sort((a, b) => a.matchId.compareTo(b.matchId));

    // Mark scored when BOTH teams have an entry in tbl_score.
    // Scores are looked up directly by each team's own ID — never swapped
    // by home/away slot order.
    return result.map((row) {
      final team1Key    = '${row.matchId}_${row.homeId}';
      final team2Key    = '${row.matchId}_${row.awayId}';
      final team1Scored = scoredMatchIds.contains(team1Key);
      final team2Scored = row.awayId != 0 && scoredMatchIds.contains(team2Key);
      final bothScored  = team1Scored && team2Scored;

      // Score keyed by each team's own ID — swap corrects the display order
      final hScore = bothScored ? (scoreMap[team2Key] ?? 0) : 0;
      final aScore = bothScored ? (scoreMap[team1Key] ?? 0) : 0;

      return _SoccerMatchRow(
        matchId:       row.matchId,
        home:          row.home,
        homeId:        row.homeId,
        homeRefereeId: row.homeRefereeId,
        away:          row.away,
        awayId:        row.awayId,
        arena:         row.arena,
        isScored:      bothScored,
        winner:        '', // unused — W/L derived from scores directly in UI
        homeScore:     hScore,
        awayScore:     aScore,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (scheduleFuture == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onTabVisible());
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _accentColor,
      child: FutureBuilder<List<ScheduleEntry>>(
        future: scheduleFuture,
        builder: (context, snapshot) {
          if (scheduleFuture == null ||
              (snapshot.connectionState == ConnectionState.waiting &&
               snapshot.data == null && !snapshot.hasError)) {
            return const Center(
                child: CircularProgressIndicator(color: _accentColor));
          }

          if (snapshot.hasError) {
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(height: constraints.maxHeight, child: Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 36),
                    const SizedBox(height: 10),
                    Text('${snapshot.error}', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Pull down or tap to retry'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ))),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(height: constraints.maxHeight, child: const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_busy, color: Colors.grey, size: 40),
                    SizedBox(height: 10),
                    Text('No matches scheduled for this arena.',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ))),
              ),
            );
          }

          // Filter to only this arena's matches
          final entries = snapshot.data!
              .where((e) => e.arenaNumber == arenaNumber)
              .toList();

          // ── SOCCER: show MATCH | HOME | VS | AWAY table ──────────────
          if (isSoccer) {
            // entries already filtered by arenaNumber above — just pivot
            final rows = _pivot(entries, scoredMatchIds, scoreMap)
              // Scored matches sink to the bottom, same as non-soccer
              ..sort((a, b) {
                final aS = a.isScored ? 1 : 0;
                final bS = b.isScored ? 1 : 0;
                if (aS != bS) return aS.compareTo(bS);
                return a.matchId.compareTo(b.matchId);
              });
            return _SoccerMatchTable(
              rows:           rows,
              scoredMatchIds: scoredMatchIds,
              onTap: (row) => onOpenScoring(ScheduleEntry(
                teamscheduleId: 0,
                matchId:        row.matchId,
                matchNumber:    row.matchId,
                teamId:         row.homeId,
                teamIdDisplay:  '',
                teamName:       row.home,
                refereeId:      row.homeRefereeId,
                arenaNumber:    row.arena,
                awayTeamId:     row.awayId,
                homeTeamName:   row.home,
                awayTeamName:   row.away,
              )),
            );
          }

          // ── NON-SOCCER: original card layout ────────────────────────
          entries.sort((a, b) {
            final aScored = scoredMatchIds.contains('${a.matchId}_${a.teamId}') ? 1 : 0;
            final bScored = scoredMatchIds.contains('${b.matchId}_${b.teamId}') ? 1 : 0;
            if (aScored != bScored) return aScored.compareTo(bScored);
            return a.matchNumber.compareTo(b.matchNumber);
          });

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry    = entries[index];
              final isScored = scoredMatchIds
                  .contains('${entry.matchId}_${entry.teamId}');
              return _MatchCard(
                entry:    entry,
                isScored: isScored,
                index:    index,
                onTap:    isScored ? null : () => onOpenScoring(entry),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SOCCER MATCH TABLE  (MATCH | HOME | VS | AWAY)
// ─────────────────────────────────────────────
class _SoccerMatchTable extends StatelessWidget {
  final List<_SoccerMatchRow> rows;
  final Set<String> scoredMatchIds;
  final void Function(_SoccerMatchRow) onTap;

  const _SoccerMatchTable({
    required this.rows,
    required this.scoredMatchIds,
    required this.onTap,
  });

  static const _lblStyle = TextStyle(
    color: Colors.white70, fontSize: 9,
    fontWeight: FontWeight.bold, letterSpacing: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: rows.length,
      itemBuilder: (_, i) => _buildRow(rows[i], i),
    );
  }

  // ── W / L / D badge helper ───────────────────────────────────────────────
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

  Widget _buildRow(_SoccerMatchRow m, int i) {
    // Even index = full colour, odd = slightly dimmed; scored = always dimmed
    final baseColor = i % 2 == 0 ? _accentColor : _accentColor.withOpacity(0.75);
    final cardColor = m.isScored ? _accentColor.withOpacity(0.50) : baseColor;

    // Resolve per-side result label — purely score-based
    final String homeLabel = !m.isScored ? ''
        : m.homeScore > m.awayScore ? 'W'
        : m.homeScore < m.awayScore ? 'L'
        : 'D';
    final String awayLabel = !m.isScored ? ''
        : m.awayScore > m.homeScore ? 'W'
        : m.awayScore < m.homeScore ? 'L'
        : 'D';

    return GestureDetector(
      onTap: m.isScored ? null : () => onTap(m),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          // Dark header strip
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
            decoration: BoxDecoration(
              color: m.isScored
                  ? const Color(0xFF9E9EAD)   // muted dark purple when scored
                  : const Color(0xFF5A3A9A),  // vivid dark purple when active
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8)),
            ),
            child: Row(children: [
              // Wider column so label aligns with the wider match-number area
              const SizedBox(width: 84, child: Text('MATCH', style: _lblStyle)),
              const Expanded(child: Text('TEAM 1', style: _lblStyle)),
              const SizedBox(width: 40,
                  child: Center(child: Text('VS', style: _lblStyle))),
              const Expanded(child: Text('TEAM 2', style: _lblStyle,
                  textAlign: TextAlign.right)),
              if (m.isScored)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.6)),
                  ),
                  child: const Text('SCORED',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          // Values row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Match ID — wider column gives breathing room next to Team 1
                SizedBox(width: 84, child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${m.matchId}',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 28, fontWeight: FontWeight.w900)),
                )),
                // ── Home team (W/L/D now beside VS badge) ───────────────
                Expanded(
                  child: Text(
                    m.home.isNotEmpty ? m.home : 'TBD',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: m.home.isNotEmpty ? Colors.white : Colors.white38,
                      fontSize: 13, fontWeight: FontWeight.w700, height: 1.3,
                    ),
                  ),
                ),
                // Home W/L/D | VS/score | Away W/L/D — all in one row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.isScored && homeLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: _resultBadge(homeLabel),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: m.isScored
                          ? Text('${m.homeScore}-${m.awayScore}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 10, fontWeight: FontWeight.w900))
                          : const Text('vs', textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white,
                                  fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                    if (m.isScored && awayLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: _resultBadge(awayLabel),
                      ),
                  ],
                ),
                // ── Away team (W/L/D now beside VS badge) ──────────────
                Expanded(
                  child: Text(
                    m.away.isNotEmpty ? m.away : 'TBD',
                    textAlign: TextAlign.right,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: m.away.isNotEmpty ? Colors.white : Colors.white38,
                      fontSize: 13, fontWeight: FontWeight.w700, height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!m.isScored) ...[
                  Text('TAP TO SCORE',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      )),
                  const SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.55), size: 14),
                ] else ...[
                  Icon(Icons.check_circle_outline_rounded,
                      color: Colors.greenAccent.withOpacity(0.7), size: 12),
                  const SizedBox(width: 4),
                  Text('COMPLETED',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      )),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ORIGINAL MATCH CARD (non-soccer)
// ─────────────────────────────────────────────
class _MatchCard extends StatelessWidget {
  final ScheduleEntry entry;
  final bool isScored;
  final int index;
  final VoidCallback? onTap;

  const _MatchCard({
    required this.entry,
    required this.isScored,
    required this.index,
    required this.onTap,
  });

  static const _labelStyle = TextStyle(
      color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    // Alternating: even = full, odd = slightly dimmed; scored = always dimmed
    final baseColor = index % 2 == 0
        ? _accentColor
        : _accentColor.withOpacity(0.75);
    final cardColor = isScored ? _accentColor.withOpacity(0.50) : baseColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardColor, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          // ── Header strip ──────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              // Use a solid darkened accent so scored/non-scored cards
              // both show the same dark header strip appearance
              color: isScored
                  ? const Color(0xFF9E9EAD)   // dark muted purple for scored
                  : const Color(0xFF5A3A9A),  // dark vivid purple for active
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8)),
            ),
            child: Row(children: [
              // MATCH label — fixed 72px matching value row
              const SizedBox(
                width: 72,
                child: Text('MATCH:', style: _labelStyle),
              ),
              // TEAM ID label — fixed 90px with left gap matching value row
              const SizedBox(
                width: 90,
                child: Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Text('TEAM ID:', style: _labelStyle),
                ),
              ),
              // TEAM NAME label — fills remaining space
              const Expanded(
                child: Text('TEAM NAME:', style: _labelStyle),
              ),
              // SCORED badge slot — always 68px wide so layout never shifts
              SizedBox(
                width: 68,
                child: isScored
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withOpacity(0.30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.greenAccent.withOpacity(0.6)),
                        ),
                        child: const Text('SCORED',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      )
                    : const SizedBox.shrink(),
              ),
            ]),
          ),
          // ── Values ───────────────────────────
          Padding(
            padding: const EdgeInsets.only(
                top: 8, bottom: 12, left: 12, right: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Match number — fixed 72px, matches header label width
                SizedBox(
                  width: 72,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('${entry.matchNumber}',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 32, fontWeight: FontWeight.w900)),
                  ),
                ),
                // Team ID — fixed 90px with left gap, always same position
                SizedBox(
                  width: 90,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(entry.teamIdDisplay,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Team Name — fills remaining space
                Expanded(
                  child: Text(entry.teamName,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2),
                ),
                // Reserve 68px matching the SCORED badge slot in header
                // so team name width is identical whether scored or not
                const SizedBox(width: 68),
              ],
            ),
          ),
          // ── Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isScored) ...[
                  Text('TAP TO SCORE',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      )),
                  const SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.55), size: 14),
                ] else ...[
                  Icon(Icons.check_circle_outline_rounded,
                      color: Colors.greenAccent.withOpacity(0.7), size: 12),
                  const SizedBox(width: 4),
                  Text('COMPLETED',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      )),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}