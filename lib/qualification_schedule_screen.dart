import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:roboventure/main.dart';

class ScheduleEntry {
  final int matchNumber;
  final String teamId;
  final String teamName;

  const ScheduleEntry({
    required this.matchNumber,
    required this.teamId,
    required this.teamName,
  });
}

class QualificationScheduleScreen extends StatelessWidget {
  final String competitionTitle;
  final Color themeColor;

  const QualificationScheduleScreen({
    super.key,
    required this.competitionTitle,
    required this.themeColor,
  });

  static const List<ScheduleEntry> _placeholderEntries = [
    ScheduleEntry(matchNumber: 1, teamId: 'C001R', teamName: 'AUP_ROBOTICS'),
    ScheduleEntry(matchNumber: 2, teamId: 'C002R', teamName: 'ST SCHO-BOTICS 1'),
    ScheduleEntry(matchNumber: 3, teamId: 'C003R', teamName: 'ST SCHOBOTICS 2'),
    ScheduleEntry(matchNumber: 4, teamId: 'C004R', teamName: 'WCI_MBOTI_TEAM1'),
    ScheduleEntry(matchNumber: 5, teamId: 'C005R', teamName: 'WCI_MBOTI_TEAM2'),
    ScheduleEntry(matchNumber: 6, teamId: 'C006R', teamName: 'WCI_MBOTI_TEAM3'),
    ScheduleEntry(matchNumber: 7, teamId: 'C007R', teamName: 'WCI_MBOTI_TEAM4'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Standardized background color to match the rest of the app
      backgroundColor: const Color(0xFFF0F0F0), 
      body: SafeArea(
        child: Column(
          children: [
            // --- Themed Header ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: themeColor,
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
                          child: Icon(Icons.chevron_left, color: themeColor, size: 20),
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
                        competitionTitle.toUpperCase(),
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

            // --- Section Title (Background Pattern Removed) ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 25),
              color: Colors.white,
              child: Text(
                'QUALIFICATION SCHEDULE',
                textAlign: TextAlign.center,
                style: GoogleFonts.anta(
                  color: themeColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            // --- List of Themed Cards ---
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                itemCount: _placeholderEntries.length,
                itemBuilder: (context, index) {
                  return _MatchCard(
                    entry: _placeholderEntries[index],
                    cardColor: themeColor,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8), // Slightly more rounded for a modern look
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacityValue(0.1),
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
    );
  }

  static const _labelStyle = TextStyle(
    color: Colors.white70,
    fontSize: 9,
    fontWeight: FontWeight.bold,
  );
}