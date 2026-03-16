// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  final int matchId;
  final int matchNumber;
  final int teamId;
  final String teamIdDisplay;
  final String teamName;
  final int refereeId;
  final int arenaNumber;

  const ScheduleEntry({
    required this.matchId,
    required this.matchNumber,
    required this.teamId,
    required this.teamIdDisplay,
    required this.teamName,
    required this.refereeId,
    required this.arenaNumber,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    String rawId       = json['team_id']?.toString() ?? '0';
    String numericPart = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    String paddedId    = numericPart.padLeft(3, '0');

    return ScheduleEntry(
      matchId:       int.tryParse(json['match_id']?.toString() ?? '0') ?? 0,
      matchNumber:   int.tryParse(json['match_number']?.toString() ?? '0') ?? 0,
      teamId:        int.tryParse(numericPart) ?? 0,
      teamIdDisplay: 'C${paddedId}R',
      teamName:      json['team_name']?.toString() ?? 'Unknown Team',
      refereeId:     int.tryParse(json['referee_id']?.toString() ?? '0') ?? 0,
      arenaNumber:   int.tryParse(json['arena_number']?.toString() ?? '0') ?? 0,
    );
  }
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class _ScheduleApiService {
  static Future<List<ArenaInfo>> fetchArenas(int categoryId) async {
    final url = Uri.parse(
      '${ApiConfig.getArena}?category_id=$categoryId'
    );
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

  static Future<List<ScheduleEntry>> fetchSchedule(
      int categoryId, int arenaNumber) async {
    final url = Uri.parse(
      '${ApiConfig.getTeamSchedule}?category_id=$categoryId&arena_number=$arenaNumber'
    );
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final entries = data.map((j) => ScheduleEntry.fromJson(j)).toList();
      entries.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
      return entries;
    }
    throw Exception('get_teamschedule failed [${response.statusCode}]');
  }

  static Future<Set<String>> fetchScoredMatchIds(int categoryId) async {
    final url = Uri.parse(
      '${ApiConfig.getScoredMatches}?category_id=$categoryId'
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) {
          final matchId = j['match_id']?.toString() ?? '0';
          final teamId  = j['team_id']?.toString() ?? '0';
          // ignore: unnecessary_brace_in_string_interps
          return '${matchId}_${teamId}';
        }).toSet();
      }
    } catch (_) {}
    return {};
  }
}

// ─────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────
class QualificationScheduleScreen extends StatefulWidget {
  final int categoryId;
  final String competitionTitle;
  final Color themeColor; // kept for API compatibility — not used for header/cards

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
    with SingleTickerProviderStateMixin {

  List<ArenaInfo> _arenas = [];
  bool _arenasLoading = true;
  String? _arenasError;

  TabController? _tabController;

  final Map<int, Future<List<ScheduleEntry>>> _scheduleFutures = {};

  Set<String> _scoredMatchIds = {};

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
    final ids = await _ScheduleApiService.fetchScoredMatchIds(widget.categoryId);
    if (mounted) setState(() => _scoredMatchIds = ids);
  }

  Future<void> _loadArenas() async {
    setState(() { _arenasLoading = true; _arenasError = null; });
    try {
      final arenas = await _ScheduleApiService.fetchArenas(widget.categoryId);
      _tabController?.dispose();
      final tc = TabController(length: arenas.length, vsync: this);
      setState(() {
        _arenas        = arenas;
        _tabController = tc;
        _arenasLoading = false;
      });
      if (arenas.isNotEmpty) _ensureSchedule(arenas.first.arenaNumber);
      tc.addListener(() {
        if (!tc.indexIsChanging) {
          _ensureSchedule(_arenas[tc.index].arenaNumber);
        }
      });
    } catch (e) {
      setState(() { _arenasError = e.toString(); _arenasLoading = false; });
    }
  }

  void _ensureSchedule(int arenaNumber) {
    if (!_scheduleFutures.containsKey(arenaNumber)) {
      setState(() {
        _scheduleFutures[arenaNumber] =
            _ScheduleApiService.fetchSchedule(widget.categoryId, arenaNumber);
      });
    }
  }

  Future<void> _refreshSchedule(int arenaNumber) async {
    setState(() {
      _scheduleFutures[arenaNumber] =
          _ScheduleApiService.fetchSchedule(widget.categoryId, arenaNumber);
    });
    await Future.wait([
      _scheduleFutures[arenaNumber]!,
      _refreshScoredIds(),
    ]);
  }

  Future<void> _openScoringPage(BuildContext context, ScheduleEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (widget.competitionTitle.toLowerCase().contains('emerging innovators')) {
            return Mbot2ScoringPage(
              matchId:   entry.matchId,
              teamId:    entry.teamId,
              refereeId: entry.refereeId,
            );
          }
          if (widget.competitionTitle.toLowerCase().contains('line tracing') ||
              widget.competitionTitle.toLowerCase().contains('navigation')) {
            return TimerScoringPage(
              matchId:   entry.matchId,
              teamId:    entry.teamId,
              refereeId: entry.refereeId,
            );
          }
          if (widget.competitionTitle.toLowerCase().contains('soccer')) {
            return SoccerScoringPage(
              matchId:   entry.matchId,
              teamId:    entry.teamId,
              refereeId: entry.refereeId,
            );
          }
          return Mbot1ScoringPage(
            matchId:   entry.matchId,
            teamId:    entry.teamId,
            refereeId: entry.refereeId,
          );
        },
      ),
    );
    _refreshScoredIds();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTitleBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      color: _accentColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            child: Row(
              children: [
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
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.competitionTitle.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic),
              ),
              const Text('QUALIFICATION',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return Column(
      children: [
        Container(
          color: Colors.grey.withOpacity(0.3),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'QUALIFICATION SCHEDULE',
            textAlign: TextAlign.center,
            style: GoogleFonts.anta(
              color: const Color.fromARGB(255, 71, 32, 161),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        if (!_arenasLoading && _arenasError == null && _arenas.isNotEmpty)
          Container(
            color: _accentColor,
            child: _buildTabBar(),
          ),
      ],
    );
  }

  Widget _buildTabBar() {
    return AnimatedBuilder(
      animation: _tabController!,
      builder: (context, _) {
        return TabBar(
          controller: _tabController,
          isScrollable: _arenas.length > 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: _arenas.asMap().entries.map((entry) {
            final isSelected = _tabController!.index == entry.key;
            return Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stadium_outlined,
                        size: 15,
                        color: isSelected ? Colors.white : Colors.white60),
                    const SizedBox(width: 5),
                    Text(entry.value.arenaName.toUpperCase()),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_arenasLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }

    if (_arenasError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_arenasError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadArenas,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_arenas.isEmpty) {
      return const Center(
          child: Text('No arenas found for this category.'));
    }

    return TabBarView(
      controller: _tabController,
      children: _arenas.map((arena) => _ArenaScheduleView(
        arenaNumber:    arena.arenaNumber,
        scoredMatchIds: _scoredMatchIds,
        scheduleFuture: _scheduleFutures[arena.arenaNumber],
        onRefresh:      () => _refreshSchedule(arena.arenaNumber),
        onTabVisible:   () => _ensureSchedule(arena.arenaNumber),
        onOpenScoring:  (entry) => _openScoringPage(context, entry),
      )).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// PER-ARENA SCHEDULE VIEW
// ─────────────────────────────────────────────
class _ArenaScheduleView extends StatelessWidget {
  final int arenaNumber;
  final Set<String> scoredMatchIds;
  final Future<List<ScheduleEntry>>? scheduleFuture;
  final Future<void> Function() onRefresh;
  final VoidCallback onTabVisible;
  final void Function(ScheduleEntry) onOpenScoring;

  const _ArenaScheduleView({
    required this.arenaNumber,
    required this.scoredMatchIds,
    required this.scheduleFuture,
    required this.onRefresh,
    required this.onTabVisible,
    required this.onOpenScoring,
  });

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
          if (scheduleFuture == null) {
            return const Center(
                child: CircularProgressIndicator(color: _accentColor));
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null &&
              !snapshot.hasError) {
            return const Center(
                child: CircularProgressIndicator(color: _accentColor));
          }

          if (snapshot.hasError) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: 400,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 36),
                      const SizedBox(height: 10),
                      Text('${snapshot.error}',
                          textAlign: TextAlign.center,
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
                  ),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: const SizedBox(
                height: 400,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, color: Colors.grey, size: 40),
                      SizedBox(height: 10),
                      Text('No matches scheduled for this arena.',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            );
          }

          final entries = List<ScheduleEntry>.from(snapshot.data!);
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
              final entry = entries[index];
              final isScored = scoredMatchIds.contains('${entry.matchId}_${entry.teamId}');
              return _MatchCard(
                entry:    entry,
                isScored: isScored,
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
// MATCH CARD
// ─────────────────────────────────────────────
class _MatchCard extends StatelessWidget {
  final ScheduleEntry entry;
  final bool isScored;
  final VoidCallback? onTap;

  const _MatchCard({
    required this.entry,
    required this.isScored,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isScored ? 0.4 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _accentColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Header row — darker overlay left as-is
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 60,  child: Text('MATCH:',    style: _labelStyle)),
                    const SizedBox(width: 100, child: Text('TEAM ID:',  style: _labelStyle)),
                    const Expanded(            child: Text('TEAM NAME:', style: _labelStyle)),
                    if (isScored)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('SCORED',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              // Values row
              Padding(
                padding: const EdgeInsets.only(
                    top: 8, bottom: 12, left: 12, right: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text('${entry.matchNumber}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900)),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(entry.teamIdDisplay,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: Text(entry.teamName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
      color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold);
}