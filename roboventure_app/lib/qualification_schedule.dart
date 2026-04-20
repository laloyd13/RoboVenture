// ignore_for_file: unused_element_parameter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'c1_scoring.dart';
import 'c2_scoring.dart';
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

class GroupStanding {
  final String groupLabel;
  final int    teamId;
  final String teamName;
  final int    mp, w, d, l, gf, ga, gd, pts;

  const GroupStanding({
    required this.groupLabel,
    required this.teamId,
    required this.teamName,
    required this.mp, required this.w, required this.d, required this.l,
    required this.gf, required this.ga, required this.gd, required this.pts,
  });

  factory GroupStanding.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) => int.tryParse((v ?? '0').toString()) ?? 0;
    return GroupStanding(
      groupLabel: j['group_label']?.toString() ?? '',
      teamId:     toInt(j['team_id']),
      teamName:   j['team_name']?.toString() ?? '',
      mp: toInt(j['mp']), w: toInt(j['w']), d: toInt(j['d']), l: toInt(j['l']),
      gf: toInt(j['gf']), ga: toInt(j['ga']), gd: toInt(j['gd']), pts: toInt(j['pts']),
    );
  }
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
  final String groupLabel;   // e.g. 'A', 'B', 'C' — from tbl_soccer_groups
  final String matchTime;    // e.g. '09:30' — from tbl_schedule

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
    this.groupLabel   = '',
    this.matchTime    = '',
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
      groupLabel:     (json['group_label'] ?? '').toString(),
      matchTime:      (json['match_time'] ?? '').toString(),
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
  final String groupLabel;
  final String matchTime;
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
    this.isScored   = false,
    this.groupLabel = '',
    this.matchTime  = '',
    this.winner     = '',
    this.homeScore  = 0,
    this.awayScore  = 0,
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
              return '${matchId}_$teamId';
            })
            .toSet();
      }
    } catch (_) {}
    return {};
  }

  /// Calls cleanup_champ_seeds.php (POST) to remove any championship seeds
  /// whose feeder qualification score no longer exists in the DB.
  /// Safe to call on every refresh — no-ops if nothing is orphaned.
  static Future<void> cleanupOrphanedSeeds(int categoryId) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.cleanupChampionshipSeeds),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'category_id': categoryId}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[qual] cleanupOrphanedSeeds done for category=$categoryId');
    } catch (e) {
      debugPrint('[qual] cleanupOrphanedSeeds error: $e');
    }
  }

  static Future<Map<String, List<GroupStanding>>> fetchGroupStandings(
      int categoryId) async {
    try {
      final url = Uri.parse(
          '${ApiConfig.getGroupStandings}?category_id=$categoryId');
      final response =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final Map<String, List<GroupStanding>> byGroup = {};
        for (final j in data) {
          final s = GroupStanding.fromJson(j as Map<String, dynamic>);
          byGroup.putIfAbsent(s.groupLabel, () => []).add(s);
        }
        return byGroup;
      }
    } catch (e) {
      debugPrint('[qual] fetchGroupStandings error: $e');
    }
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
          map['${matchId}_$teamId'] = score;
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
  // One GlobalKey per arena tab so we can call Scrollable.ensureVisible
  // on the selected tab after returning from the scoring page.
  List<GlobalKey> _tabKeys = [];

  final Map<int, Future<List<ScheduleEntry>>> _scheduleFutures = {};
  Set<String>      _scoredMatchIds = {};
  Map<String, int> _scoreMap       = {};

  // ── Group standings (soccer only) ─────────────────────────────────
  Map<String, List<GroupStanding>> _standings     = {};
  bool                              _standingsExpanded = false;
  Timer?                            _standingsTimer;

  bool get _soccer => _isSoccer(widget.competitionTitle);

  @override
  void initState() {
    super.initState();
    _loadArenas();
    _refreshScoredIds();
    // Always fetch standings — panel only renders when _soccer is true,
    // but fetching unconditionally avoids missing data if the title check
    // doesn't match exactly.
    _refreshStandings();
    _standingsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshStandings(),
    );
  }

  @override
  void dispose() {
    _standingsTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _refreshStandings() async {
    final data = await _ScheduleApiService.fetchGroupStandings(
        widget.categoryId);
    if (mounted) setState(() => _standings = data);
  }

  Future<void> _refreshScoredIds() async {
    // Clean up any championship seeds whose qualification score was deleted
    // directly in the DB — runs on every load/refresh so stale seeds are
    // swept out automatically without needing an in-app delete action.
    await _ScheduleApiService.cleanupOrphanedSeeds(widget.categoryId);

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
        _tabKeys       = List.generate(arenas.length, (_) => GlobalKey());
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
    // Save the current tab index so we can restore the tab bar scroll position
    // after returning from the scoring page (setState on refresh would reset it).
    final savedTabIndex = _tabController?.index ?? 0;

    // Capture messenger before any async gap (satisfies use_build_context_synchronously).
    // Dismiss any visible snackbar immediately so it doesn't linger while the
    // scoring page is open.
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final bool? submitted = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) {
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

    // The soccer scoring page is landscape. Its dispose() no longer resets
    // orientation — we do it here, synchronously, before any setState fires,
    // so the schedule screen is already portrait before Flutter rebuilds it.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    if (!mounted) return;

    // ── Soccer group match: seed winner into first knockout round ─────────
    // Only runs when SoccerScoringPage returned true (score submitted OK).
    // Uses scoring.php?action=get_match_scores (same endpoint the scoring
    // page itself uses) to read back goals and determine winner/loser.
    debugPrint('[qual] submitted=$submitted soccer=$_soccer awayId=${entry.awayTeamId}');
    bool soccerAdvanced = false; // true if a winner was seeded into the next round
    if (_soccer && submitted == true && entry.awayTeamId != 0) {
      try {
        // Use the same endpoint the scoring page uses internally
        final scoreRows = await SoccerScoringApiService.fetchMatchScores(entry.matchId);
        debugPrint('[qual] scoreRows count=${scoreRows.length} rows=$scoreRows');

        if (scoreRows.length >= 2) {
          final Map<int, int> teamGoals = {};
          for (final j in scoreRows) {
            final tid   = int.tryParse(j['team_id'].toString()) ?? 0;
            // score_independentscore = goals for this team
            final goals = int.tryParse(j['score_independentscore'].toString()) ?? 0;
            if (tid > 0) teamGoals[tid] = goals;
            debugPrint('[qual] team=$tid goals=$goals');
          }
          final homeGoals = teamGoals[entry.teamId]     ?? 0;
          final awayGoals = teamGoals[entry.awayTeamId] ?? 0;
          debugPrint('[qual] home=${entry.teamId} goals=$homeGoals  away=${entry.awayTeamId} goals=$awayGoals');

          if (homeGoals != awayGoals) {
            soccerAdvanced = true;
            final winnerTeamId = homeGoals > awayGoals ? entry.teamId     : entry.awayTeamId;
            final loserTeamId  = homeGoals > awayGoals ? entry.awayTeamId : entry.teamId;

            // Remove previously seeded teams from knockout slots before
            // re-seeding, so the new winner replaces the old one cleanly.
            try {
              final cleanupUrl = Uri.parse(ApiConfig.cleanupChampionshipSeeds);
              await http.delete(
                cleanupUrl,
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'team_ids':    [entry.teamId, entry.awayTeamId],
                  'category_id': widget.categoryId,
                }),
              ).timeout(const Duration(seconds: 10));
              debugPrint('[qual] cleanup seeds for teams=${entry.teamId},${entry.awayTeamId} done');
            } catch (e) {
              debugPrint('[qual] cleanup seeds error: $e');
            }

            final advanceUrl   = Uri.parse(ApiConfig.advanceKnockout);
            final advResp = await http.post(
              advanceUrl,
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'match_id':       entry.matchId,
                'winner_team_id': winnerTeamId,
                'loser_team_id':  loserTeamId,
                'category_id':    widget.categoryId,
              }),
            ).timeout(const Duration(seconds: 10));
            debugPrint('[qual] advanceKnockout [${advResp.statusCode}]: ${advResp.body}');
          } else {
            debugPrint('[qual] TIE in group match=${entry.matchId} — no advance');
          }
        } else {
          debugPrint('[qual] not enough score rows (${scoreRows.length}) for match=${entry.matchId}');
        }
      } catch (e, st) {
        debugPrint('[qual] advanceKnockout error: $e\n$st');
      }
    }

    // Refresh scored IDs into state for UI update.
    await _refreshScoredIds();
    if (_soccer) await _refreshStandings();

    // ── Show notification toasts ──────────────────────────────────────
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    if (submitted == true) {
      if (soccerAdvanced) {
        // Show both toasts simultaneously via Overlay
        _showStackedToasts(context);
      } else {
        messenger.showSnackBar(SnackBar(
          content: const Text('Score submitted successfully!'),
          backgroundColor: const Color(0xFF5E975E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ));
      }
    }

    // Wait for the orientation change + layout to fully settle before
    // trying to scroll the tab into view. One frame is not enough after
    // a landscape→portrait transition, so we use a short delay then
    // scroll inside a post-frame callback so the RenderObjects are ready.
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _scrollSelectedTabIntoView(savedTabIndex);
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
                  color: const Color(0xFF5E975E),
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
    if (_tabController == null) return;
    if (index >= _tabController!.length) return;
    if (index >= _tabKeys.length) return;

    // Snap the controller to the correct index first.
    _tabController!.animateTo(index, duration: Duration.zero);

    // Then ask Flutter to scroll the tab widget into view.
    // We try immediately, and schedule a second attempt one frame later
    // in case the first fires before the TabBar has finished laying out.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        _buildTitleBar(),
        if (_soccer) _buildStandingsPanel(),
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
          Text(_soccer ? 'GROUP STAGE' : 'QUALIFICATION',
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
              _soccer ? 'GROUP STAGE SCHEDULE' : 'QUALIFICATION SCHEDULE',
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

  Widget _buildTabBar() => TabBar(
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
      return Tab(child: Padding(
        key: entry.key < _tabKeys.length ? _tabKeys[entry.key] : null,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // No explicit color — inherits labelColor/unselectedLabelColor
          // from TabBar so icon and text always match.
          const Icon(Icons.stadium_outlined, size: 15),
          const SizedBox(width: 5),
          Text(entry.value.arenaName.toUpperCase()),
        ]),
      ));
    }).toList(),
  );

  // ── GROUP STANDINGS PANEL ────────────────────────────────────────────
  Widget _buildStandingsPanel() {
    final bool hasData = _standings.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5A3A9A), Color(0xFF7D58B3)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4A017), width: 2),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Collapse toggle ──────────────────────────────────────────
        InkWell(
          onTap: () => setState(
              () => _standingsExpanded = !_standingsExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(children: [
              const Icon(Icons.leaderboard_rounded,
                  color: Color(0xFFD4A017), size: 13),
              const SizedBox(width: 6),
              const Text('GROUP STANDINGS',
                  style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1)),
              const Spacer(),
              if (!hasData && _standingsExpanded)
                Text('loading...',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 9)),
              const SizedBox(width: 6),
              Icon(
                _standingsExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: Colors.white54,
                size: 16,
              ),
            ]),
          ),
        ),
        // ── Table (shown when expanded and data available) ───────────
        if (_standingsExpanded && hasData)
          SizedBox(
            // header(28) + col-labels(28) + divider(1) + rows(34 each) + bottom-pad(10)
            height: ((){
              final maxRows = _standings.values
                  .map((r) => r.length)
                  .fold(0, (a, b) => a > b ? a : b);
              return 28.0 + 28.0 + 1.0 + maxRows * 34.0 + 10.0;
            })(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              itemCount: _standings.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final entry = _standings.entries.elementAt(i);
                return _GroupTable(label: entry.key, rows: entry.value);
              },
            ),
          ),
      ]),
    );
  }

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
          groupLabel:    e.groupLabel,
          matchTime:     e.matchTime,
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
          groupLabel:    existing.groupLabel,
          matchTime:     existing.matchTime,
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

      // Score keyed by each team's own ID
      final hScore = bothScored ? (scoreMap[team1Key] ?? 0) : 0;
      final aScore = bothScored ? (scoreMap[team2Key] ?? 0) : 0;

      return _SoccerMatchRow(
        matchId:       row.matchId,
        home:          row.home,
        homeId:        row.homeId,
        homeRefereeId: row.homeRefereeId,
        away:          row.away,
        awayId:        row.awayId,
        arena:         row.arena,
        groupLabel:    row.groupLabel,
        matchTime:     row.matchTime,
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
// GROUP STANDINGS TABLE WIDGET
// ─────────────────────────────────────────────
class _GroupTable extends StatelessWidget {
  final String              label;
  final List<GroupStanding> rows;

  const _GroupTable({required this.label, required this.rows});

  static const _hdrStyle = TextStyle(
    color: Colors.white54, fontSize: 8.5,
    fontWeight: FontWeight.w800, letterSpacing: 0.8,
  );
  static const _cellStyle = TextStyle(
    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
  );
  static const _namStyle = TextStyle(
    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    // width = 120 (name) + 24*4 (MP/W/D/L) + 28*4 (GF/GA/GD/PTS)
    //       + 20 (horizontal padding 10*2) + 2 (border 1*2) + 8 (extra buffer)
    const double tableWidth = 120 + 24 * 4 + 28 * 4 + 30;
    return SizedBox(
      width: tableWidth,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Group label header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.5),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Text('GROUP $label',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0)),
        ),
        // Column headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(children: [
            const SizedBox(width: 120, child: Text('TEAM', style: _hdrStyle)),
            const SizedBox(width: 24, child: Text('MP', style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 24, child: Text('W',  style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 24, child: Text('D',  style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 24, child: Text('L',  style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 28, child: Text('GF', style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 28, child: Text('GA', style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 28, child: Text('GD', style: _hdrStyle, textAlign: TextAlign.center)),
            const SizedBox(width: 28, child: Text('PTS', style: _hdrStyle, textAlign: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, color: Colors.white12),
        // Data rows
        ...rows.asMap().entries.map((e) {
          final i   = e.key;
          final row = e.value;
          final isTop2   = i < 2;
          final gdStr    = row.gd > 0 ? '+${row.gd}' : '${row.gd}';
          return Container(
            decoration: BoxDecoration(
              color: isTop2
                  ? Colors.greenAccent.withOpacity(0.06)
                  : Colors.transparent,
              border: i < rows.length - 1
                  ? const Border(
                      bottom: BorderSide(color: Colors.white10))
                  : null,
              borderRadius: i == rows.length - 1
                  ? const BorderRadius.vertical(
                      bottom: Radius.circular(8))
                  : null,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              // Rank dot + name
              SizedBox(
                width: 120,
                child: Row(children: [
                  Container(
                    width: 16, height: 16,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isTop2
                          ? Colors.greenAccent.withOpacity(0.25)
                          : Colors.white.withOpacity(0.08),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: isTop2
                                  ? Colors.greenAccent
                                  : Colors.white54,
                              fontSize: 8,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                  Expanded(
                    child: Text(row.teamName,
                        overflow: TextOverflow.ellipsis,
                        style: _namStyle),
                  ),
                ]),
              ),
              SizedBox(width: 24, child: Text('${row.mp}', style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text('${row.w}',  style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text('${row.d}',  style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text('${row.l}',  style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 28, child: Text('${row.gf}', style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 28, child: Text('${row.ga}', style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 28, child: Text(gdStr,        style: _cellStyle, textAlign: TextAlign.center)),
              SizedBox(width: 28,
                child: Text('${row.pts}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isTop2
                            ? Colors.greenAccent
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ),
            ]),
          );
        }),
      ]),
      ), // Container
    ); // SizedBox
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
              Expanded(
                child: Text(
                  m.groupLabel.isNotEmpty ? 'TEAM 1  •  GRP ${m.groupLabel}' : 'TEAM 1',
                  style: _lblStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 40,
                  child: Center(child: Text('VS', style: _lblStyle))),
              Expanded(
                child: Text(
                  m.groupLabel.isNotEmpty ? 'TEAM 2  •  GRP ${m.groupLabel}' : 'TEAM 2',
                  style: _lblStyle,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── Competition time — left side ──────────────────────
                if (m.matchTime.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.access_time_rounded,
                        color: Colors.white.withOpacity(0.55), size: 11),
                    const SizedBox(width: 4),
                    Text(m.matchTime,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        )),
                  ])
                else
                  const SizedBox.shrink(),
                // ── Status — right side ───────────────────────────────
                if (!m.isScored)
                  Row(mainAxisSize: MainAxisSize.min, children: [
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
                else
                  Row(mainAxisSize: MainAxisSize.min, children: [
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