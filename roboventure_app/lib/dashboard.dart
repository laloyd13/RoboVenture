// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'category.dart'; 
import 'api_config.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  Future<List<dynamic>>? _categoriesFuture;

  final Map<String, dynamic> _categoryThemes = {
    'Aspiring Makers': {'icon': Icons.build_circle_outlined, 'color': const Color(0xFF9B84D1)},
    'Emerging Innovators': {'icon': Icons.lightbulb_outline, 'color': const Color(0xFF3498DB)},
    'Line Tracing': {'icon': Icons.route_outlined, 'color': const Color(0xFFE67E22)},
    'Navigation': {'icon': Icons.explore_outlined, 'color': const Color(0xFF27AE60)},
    'Soccer': {'icon': Icons.sports_soccer_outlined, 'color': const Color(0xFFE74C3C)},
  };

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _fetchCategories();
  }

  Future<List<dynamic>> _fetchCategories() async {
    final url = Uri.parse(ApiConfig.getCategories);
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
      data.sort((a, b) {
        final aActive = (a['status'] == 'active') ? 0 : 1;
        final bActive = (b['status'] == 'active') ? 0 : 1;
        if (aActive != bActive) return aActive.compareTo(bActive);
        final aId = int.tryParse(a['category_id'].toString()) ?? 0;
        final bId = int.tryParse(b['category_id'].toString()) ?? 0;
        return aId.compareTo(bId);
      });
        return data;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Database connection failed. \n$e');
    }
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _categoriesFuture = _fetchCategories();
    });
    await _categoriesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F0FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _categoriesFuture,
                builder: (context, snapshot) {
                  if (_categoriesFuture == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF9B84D1)));
                  } else if (snapshot.hasError) {
                    return RefreshIndicator(
                      onRefresh: _handleRefresh,
                      color: const Color(0xFF7B56B3),
                      backgroundColor: Colors.white,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildErrorState(snapshot.error.toString()),
                        ),
                      ),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _handleRefresh,
                      color: const Color(0xFF7B56B3),
                      backgroundColor: Colors.white,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: const Center(child: Text("No categories found.")),
                        ),
                      ),
                    );
                  }

                  final categories = snapshot.data!;

                  return RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: const Color(0xFF7B56B3),
                    backgroundColor: Colors.white,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWelcomeBanner(),
                          const SizedBox(height: 28),
                          _sectionLabel('COMPETITIONS', count: categories.length),
                          const SizedBox(height: 14),
                          for (var cat in categories) ...[
                            _buildCategoryCard(context, cat),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, dynamic cat) {
    final int catId = int.tryParse(cat['category_id'].toString()) ?? 0;
    final String categoryName = cat['category_type'] ?? 'Unknown';
    final bool isActive = cat['status'] == 'active';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: _CompetitionCard(
        title: categoryName,
        subtitle: isActive
            ? "Qualification & Championship rounds"
            : "Coming soon — not yet available",
        icon: _getIconForCategory(categoryName),
        accentColor: _getColorForCategory(categoryName),
        isLocked: !isActive,
        onTap: () => _navigateToMenu(
          context,
          catId,
          categoryName.toUpperCase(),
          _getColorForCategory(categoryName),
        ),
      ),
    );
  }

  void _navigateToMenu(BuildContext context, int id, String title, Color color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MainMenuScreen(
          categoryId: id,
          competitionTitle: title,
          accentColor: color,
        ),
      ),
    );
  }

  IconData _getIconForCategory(String? name) {
    if (name == null) return Icons.help_outline;
    for (var key in _categoryThemes.keys) {
      if (name.contains(key)) return _categoryThemes[key]['icon'];
    }
    return Icons.category_outlined;
  }

  Color _getColorForCategory(String? name) {
    if (name == null) return Colors.grey;
    for (var key in _categoryThemes.keys) {
      if (name.contains(key)) return _categoryThemes[key]['color'];
    }
    return Colors.blueGrey;
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: const Color(0xFF7D58B3),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ROBOVENTURE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('Competition Dashboard', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1)),
            ],
          ),
          const Spacer(),
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(Icons.person, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF7D58B3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome!', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('Select a Competition', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Tap a competition below to view its categories.', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 10),
          Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 15),
          ElevatedButton(onPressed: _handleRefresh, child: const Text("Retry")),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, {int? count}) {
    return Row(
      children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: const Color(0xFF7B56B3), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Color(0xFF7B56B3), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF7B56B3).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(color: Color(0xFF7B56B3), fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _LogoBadge(imagePath: 'assets/RV_logo.png'),
          _LogoBadge(imagePath: 'assets/CreoLogo.png'),
        ],
      ),
    );
  }
}

class _CompetitionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;
  final bool isLocked;

  const _CompetitionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.onTap,
    this.isLocked = false,
  });

  @override
  State<_CompetitionCard> createState() => _CompetitionCardState();
}

class _CompetitionCardState extends State<_CompetitionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isLocked ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.isLocked ? null : (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: widget.isLocked ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && !widget.isLocked ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.isLocked ? Colors.white.withOpacity(0.7) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isLocked
                  ? widget.accentColor.withOpacity(0.2)
                  : widget.accentColor.withOpacity(0.8),
              width: 2.0,
            ),
            boxShadow: [
              if (!widget.isLocked)
                BoxShadow(
                  color: widget.accentColor.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacity(widget.isLocked ? 0.1 : 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.accentColor.withOpacity(widget.isLocked ? 0.4 : 1.0), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Opacity(
                  opacity: widget.isLocked ? 0.4 : 1.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3436))),
                      const SizedBox(height: 2),
                      Text(widget.subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.isLocked ? Colors.grey.withOpacity(0.2) : const Color(0xFF2ECC71).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.isLocked ? "SOON" : "ACTIVE",
                      style: TextStyle(
                        color: widget.isLocked ? Colors.grey : const Color(0xFF2ECC71),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    widget.isLocked ? Icons.lock_outline : Icons.chevron_right,
                    color: widget.isLocked ? Colors.grey.withOpacity(0.4) : widget.accentColor,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  final String imagePath;
  const _LogoBadge({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        imagePath,
        height: 20,
        width: 80,
        fit: BoxFit.contain,
      ),
    );
  }
}