// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'scoring.dart';

class ScheduleEntry {
  final int matchNumber;
  final String teamId;
  final String teamName;

  const ScheduleEntry({
    required this.matchNumber,
    required this.teamId,
    required this.teamName,
  });

  // Factory to create an entry from JSON
  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      // Force match_number to int safely
      matchNumber: int.tryParse(json['match_number'].toString()) ?? 0,
      
      // Force team_id to String safely (This fixes your error!)
      teamId: json['team_id']?.toString() ?? 'N/A',
      
      teamName: json['team_name']?.toString() ?? 'Unknown Team',
    );
  }
}

class QualificationScheduleScreen extends StatefulWidget {
  final int categoryId;
  final String competitionTitle;
  final Color themeColor;

  const QualificationScheduleScreen({
    super.key,
    required this.categoryId,
    required this.competitionTitle,
    required this.themeColor,
  });

  @override
  State<QualificationScheduleScreen> createState() => _QualificationScheduleScreenState();
}

class _QualificationScheduleScreenState extends State<QualificationScheduleScreen> {
  
  // Replace this URL with your actual endpoint for tbl_team
  Future<List<ScheduleEntry>> _fetchSchedule() async {
    final url = Uri.parse('http://175.20.0.32/roboventure_api/get_teamschedule.php?category_id=${widget.categoryId}');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((json) => ScheduleEntry.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load schedule');
      }
    } catch (e) {
      throw Exception('Connection Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(
        child: Column(
          children: [
            // --- Themed Header ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              color: widget.themeColor,
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
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.chevron_left, color: widget.themeColor, size: 20),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'BACK',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
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
                      const Text(
                        'QUALIFICATION',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- Section Title ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 25),
              color: Colors.white,
              child: Text(
                'QUALIFICATION SCHEDULE',
                textAlign: TextAlign.center,
                style: GoogleFonts.anta(
                  color: widget.themeColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            // --- Dynamic List using FutureBuilder ---
            Expanded(
              child: FutureBuilder<List<ScheduleEntry>>(
                future: _fetchSchedule(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: widget.themeColor));
                  } else if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("No schedule entries found."));
                  }

                  final entries = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      return _MatchCard(
                        entry: entries[index],
                        cardColor: widget.themeColor,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final ScheduleEntry entry;
  final Color cardColor;

  const _MatchCard({required this.entry, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScoringPage(
              teamId: entry.teamId,
              teamName: entry.teamName,
              // Since _MatchCard is a separate class, you'll need to 
              // pass categoryId to it or access it if it's in scope.
              categoryId: 1, // Replace with the actual categoryId variable
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 60, child: Text('MATCH:', style: _labelStyle)),
                  SizedBox(width: 100, child: Text('TEAM ID:', style: _labelStyle)),
                  Expanded(child: Text('TEAM NAME:', style: _labelStyle)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12, left: 12, right: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${entry.matchNumber}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(
                      entry.teamId,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.teamName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color: Colors.white70,
    fontSize: 9,
    fontWeight: FontWeight.bold,
  );
}