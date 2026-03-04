import 'package:flutter/material.dart';
import 'package:roboventure/main.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'category.dart'; 

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- Dynamic Theme Configuration ---
  final Map<String, dynamic> _categoryThemes = {
    'mBot 1': {'icon': Icons.build_circle_outlined, 'color': const Color(0xFF7B2FBE)},
    'mBot 2': {'icon': Icons.lightbulb_outline, 'color': const Color(0xFF3498DB)},
    'Line Tracing': {'icon': Icons.route_outlined, 'color': const Color(0xFFE67E22)},
    'Navigation': {'icon': Icons.explore_outlined, 'color': const Color(0xFF27AE60)},
    'Soccer': {'icon': Icons.sports_soccer_outlined, 'color': const Color(0xFFE74C3C)},
  };

  Future<List<dynamic>> _fetchCategories() async {
    final url = Uri.parse('http://localhost/roboventure_api/get_categories.php');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Database connection failed. Is Apache running? \n$e');
    }
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
                future: _fetchCategories(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF7B2FBE)));
                  } else if (snapshot.hasError) {
                    return _buildErrorState(snapshot.error.toString());
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("No categories found."));
                  }

                  final categories = snapshot.data!;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeBanner(),
                        const SizedBox(height: 28),
                        _sectionLabel('COMPETITIONS'),
                        const SizedBox(height: 14),

                        // Dynamically generated list from Database
                        for (var cat in categories)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _CompetitionCard(
                              title: cat['category_type'] ?? 'Unknown',
                              subtitle: "Tournament ID: ${cat['category_id']}",
                              icon: _getIconForCategory(cat['category_type']),
                              accentColor: _getColorForCategory(cat['category_type']),
                              statusLabel: 'ACTIVE',
                              statusColor: const Color(0xFF2ECC71),
                              onTap: () => _navigateToMenu(
                                context, 
                                cat['category_type'].toString().toUpperCase(), 
                                _getColorForCategory(cat['category_type'])
                              ),
                            ),
                          ),
                      ],
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

  // --- Theme Helper Methods ---

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

  void _navigateToMenu(BuildContext context, String title, Color color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MainMenuScreen(
          competitionTitle: title,
          accentColor: color,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF5B2D8E), Color(0xFF8B5BBE)]),
      ),
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
            backgroundColor: Colors.white.withOpacityValue(0.2),
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
        gradient: const LinearGradient(colors: [Color(0xFF7B2FBE), Color(0xFF9B59B6)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome!', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('Live Tournament', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Select a category to start scoring.', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.emoji_events, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 10),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () => setState(() {}),
              child: const Text("Retry Connection"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Row(
      children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: const Color(0xFF7B2FBE), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Color(0xFF5B2D8E), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2)),
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
          _LogoBadge(label: "Makeblock", color: Colors.orange),
          _LogoBadge(label: "CREOTEC", color: Colors.blue),
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
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onTap; // Removed isLocked parameter

  const _CompetitionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.statusLabel,
    required this.statusColor,
    this.onTap,
  });

  @override
  State<_CompetitionCard> createState() => _CompetitionCardState();
}

class _CompetitionCardState extends State<_CompetitionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.accentColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacityValue(0.1), 
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(widget.subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _LogoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFF4F0FF), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}