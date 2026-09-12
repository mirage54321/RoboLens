import 'package:flutter/material.dart';
import '../tap_cursor.dart';

import 'match_theme.dart';

class MatchIntroScreen extends StatelessWidget {
  final void Function(String) onAddTeam;

  const MatchIntroScreen({super.key, required this.onAddTeam});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  TapCursor(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: MatchColors.yellorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: MatchColors.yellor,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: MatchColors.yellorLight,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.query_stats,
                        color: MatchColors.yellorDark,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Team Stats & Match Center',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Track your team's upcoming matches with live countdowns and alerts, browse event rankings and OPRs, and simulate matchups before they happen.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _feature(
                      Icons.notifications_active_outlined,
                      'Match alerts',
                      'Get notified before your matches start',
                    ),
                    _feature(
                      Icons.leaderboard_outlined,
                      'Team stats',
                      'Event OPR, rankings, and records for every team',
                    ),
                    _feature(
                      Icons.compare_arrows,
                      'Matchup simulator',
                      "Type in teams and see who's favored",
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: MatchColors.yellor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => _showAddTeamDialog(context),
                        child: const Text(
                          'Add your team',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MatchColors.yellorLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: MatchColors.yellorDark, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [ 
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTeamDialog(BuildContext context) {
    final ctrl = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add your team'),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Team number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MatchColors.yellor,
              ),
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isEmpty) {
                  setD(() => error = 'Enter a team number');
                  return;
                }
                Navigator.pop(ctx);
                onAddTeam(t);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}