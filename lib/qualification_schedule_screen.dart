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

  // ToDo : Replace this with real data from the database when ready. For now, it just shows placeholder data in a nice format.
  // Keep the data dynamic or from your placeholder list
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
      backgroundColor: const Color(0xFFE5E5E5),
      body: SafeArea(
        child: Column(
          children: [
            // --- Themed Header (Merged) ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: themeColor, // Using dynamic themeColor
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
                        competitionTitle.toUpperCase(), // Using dynamic title
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

            // --- Section Title with Geometric Background ---
            Container(
              width: double.infinity,
              color: Colors.white,
              child: CustomPaint(
                painter: GeometricBackgroundPainter(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
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
              ),
            ),

            // --- List of Themed Cards ---
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor, // Primary theme color for the card
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header Label Row
          Container(
            padding: const EdgeInsets.only(top: 8, bottom: 4, left: 12, right: 12),
            color: Colors.black.withOpacityValue(0.15), // Darken slightly for the labels
            child: const Row(
              children: [
                SizedBox(width: 60, child: Text('MATCH:', style: _labelStyle)),
                SizedBox(width: 100, child: Text('TEAM ID:', style: _labelStyle)),
                Expanded(child: Text('TEAM NAME:', style: _labelStyle)),
              ],
            ),
          ),
          // Data Row
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12, left: 12, right: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    '${entry.matchNumber}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
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

class GeometricBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = const Color(0xFFE2E2F0).withOpacityValue(0.4)
      ..style = PaintingStyle.fill;

    final paint2 = Paint()
      ..color = const Color(0xFFD0D0E5).withOpacityValue(0.4)
      ..style = PaintingStyle.fill;

    final leftPath = Path()
      ..moveTo(0, size.height * 0.1)
      ..lineTo(size.width * 0.25, size.height * 0.3)
      ..lineTo(size.width * 0.15, size.height * 0.7)
      ..lineTo(0, size.height * 0.9)
      ..close();
    canvas.drawPath(leftPath, paint1);

    final bottomPath = Path()
      ..moveTo(size.width * 0.3, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.6)
      ..lineTo(size.width * 0.8, size.height * 0.85)
      ..lineTo(size.width * 0.7, size.height)
      ..close();
    canvas.drawPath(bottomPath, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}