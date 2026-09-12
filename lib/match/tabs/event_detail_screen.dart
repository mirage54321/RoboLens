import 'package:flutter/material.dart';
import '../../tap_cursor.dart';

import '../match_scope.dart';
import '../match_models.dart';
import '../match_theme.dart';
import 'match_schedule_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final MatchEvent event;
  final bool isMine;

  const EventDetailScreen({super.key, required this.event, required this.isMine});

  @override
  State<EventDetailScreen> createState() => EventDetailScreenState();
}

class EventDetailScreenState extends State<EventDetailScreen> {
  List<EventTeamInfo> competitors = [];
  bool loadingCompetitors = false;
  bool competitorsFailed = false;
  bool showCompetitors = false;
  Map<String, double> avgPointsByTeam = {};

  EventAlliance? winningAlliance;
  EventAlliance? runnerUpAlliance;
  int? winningScore;
  int? losingScore;
  bool loadingResults = true;
  bool resultsFailed = false;

  bool get isPastEvent {
    final end = widget.event.endDate;
    if (end == null) return false;
    return end.isBefore(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    if (isPastEvent) {
      loadResultsSummary();
    } else {
      loadingResults = false;
      loadCompetitors();
    }
  }

  Future<void> loadResultsSummary() async {
    final controller = MatchScope.of(context);
    setState(() {
      loadingResults = true;
      resultsFailed = false;
    });
    try {
      final alliances = await controller
          .loadEventAlliances(widget.event.key)
          .timeout(const Duration(seconds: 20));
      final matches = await controller
          .loadEventMatches(widget.event.key)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      final winner = alliances.where((a) => a.won).firstOrNull;
      final runnerUp = alliances.where((a) => a.isRunnerUp).firstOrNull;
      int? winScore;
      int? loseScore;
      if (winner != null) {
        final finals = matches.where((m) => m.compLevel == 'f' && m.isPlayed).toList()
          ..sort((a, b) => b.matchNumber.compareTo(a.matchNumber));
        final decidingMatch = finals.firstOrNull;
        if (decidingMatch != null) {
          final onRed = decidingMatch.redTeams.any((k) => winner.picks.contains(k));
          winScore = onRed ? decidingMatch.redScore : decidingMatch.blueScore;
          loseScore = onRed ? decidingMatch.blueScore : decidingMatch.redScore;
        }
      }

      setState(() {
        winningAlliance = winner;
        runnerUpAlliance = runnerUp;
        winningScore = winScore;
        losingScore = loseScore;
        loadingResults = false;
      });
    } catch (e) {
      debugPrint('loadResultsSummary failed: $e');
      controller.evictEventAlliancesCache(widget.event.key);
      controller.evictEventMatchesCache(widget.event.key);
      if (!mounted) return;
      setState(() {
        loadingResults = false;
        resultsFailed = true;
      });
    }
  }

  Future<void> loadCompetitors() async {
    final controller = MatchScope.of(context);
    setState(() {
      loadingCompetitors = true;
      competitorsFailed = false;
    });
    try {
      final loaded = await controller
          .loadEventTeams(widget.event.key)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        competitors = loaded;
        loadingCompetitors = false;
      });
    } catch (e) {
      debugPrint('loadCompetitors timed out or failed: $e');

      controller.evictEventTeamsCache(widget.event.key);
      if (!mounted) return;
      setState(() {
        loadingCompetitors = false;
        competitorsFailed = true;
      });
    }

    try {
      final stats = await controller
          .loadWorldTeamStats()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        avgPointsByTeam = {
          for (final s in stats)
            if (s.opr != null) s.teamNumber: s.opr!,
        };
      });
    } catch (e) {
      debugPrint('loadCompetitorStats failed: $e');
    }
  }

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
                      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back, color: MatchColors.yellor, size: 17),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.event.name,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: isPastEvent ? pastEventChildren(context) : upcomingEventChildren(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> pastEventChildren(BuildContext context) {
    return [
      Text('Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
      const SizedBox(height: 10),
      if (loadingResults)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
        )
      else if (resultsFailed)
        retryTile('Could not load the event result.', loadResultsSummary)
      else if (winningAlliance == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Results not posted yet.', style: TextStyle(color: Colors.grey[500])),
        )
      else
        winnerCard(winningAlliance!, winningScore, losingScore),
      if (runnerUpAlliance != null) ...[
        const SizedBox(height: 12),
        runnerUpCard(runnerUpAlliance!),
      ],
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            if (!showCompetitors && competitors.isEmpty && !loadingCompetitors) {
              loadCompetitors();
            }
            setState(() => showCompetitors = !showCompetitors);
          },
          icon: Icon(showCompetitors ? Icons.expand_less : Icons.groups_outlined),
          label: Text(showCompetitors ? 'Hide attending teams' : 'View all teams'),
          style: OutlinedButton.styleFrom(
            foregroundColor: MatchColors.yellorDark,
            side: const BorderSide(color: MatchColors.yellor),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      if (showCompetitors) ...[
        const SizedBox(height: 16),
        if (loadingCompetitors)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
          )
        else if (competitorsFailed)
          retryTile('Could not load the team list.', loadCompetitors)
        else if (competitors.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Team list not available for this event.', style: TextStyle(color: Colors.grey[500])),
          )
        else
          ...competitors.map((c) => competitorTile(c)),
      ],
    ];
  }

  List<Widget> upcomingEventChildren(BuildContext context) {
    return [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            final controller = MatchScope.of(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MatchScope(
                  controller: controller,
                  child: MatchScheduleScreen(event: widget.event),
                ),
              ),
            );
          },
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Match schedule'),
          style: OutlinedButton.styleFrom(
            foregroundColor: MatchColors.yellorDark,
            side: const BorderSide(color: MatchColors.yellor),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text('Competing teams', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
      const SizedBox(height: 10),
      if (loadingCompetitors)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
        )
      else if (competitorsFailed)
        retryTile('Could not load the team list.', loadCompetitors)
      else if (competitors.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Team list not available yet for this event.', style: TextStyle(color: Colors.grey[500])),
        )
      else
        ...competitors.map((c) => competitorTile(c)),
    ];
  }

  Widget retryTile(String message, Future<void> Function() onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          TapCursor(
            onTap: onRetry,
            child: const Text('Try again', style: TextStyle(color: MatchColors.yellorDark, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget runnerUpCard(EventAlliance runnerUp) {
    final captain = runnerUp.picks.isNotEmpty ? runnerUp.picks[0].replaceFirst('frc', '') : null;
    final pick2 = runnerUp.picks.length > 1 ? runnerUp.picks[1].replaceFirst('frc', '') : null;
    final pick3 = runnerUp.picks.length > 2 ? runnerUp.picks[2].replaceFirst('frc', '') : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech_outlined, color: Colors.grey[500], size: 20),
              const SizedBox(width: 8),
              Text('2nd place', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey[700])),
            ],
          ),
          const SizedBox(height: 14),
          if (captain != null) allianceMemberRow('Captain', captain),
          if (pick2 != null) allianceMemberRow('2nd pick', pick2),
          if (pick3 != null) allianceMemberRow('3rd pick', pick3),
        ],
      ),
    );
  }

  Widget winnerCard(EventAlliance winner, int? winScore, int? loseScore) {
    final captain = winner.picks.isNotEmpty ? winner.picks[0].replaceFirst('frc', '') : null;
    final pick2 = winner.picks.length > 1 ? winner.picks[1].replaceFirst('frc', '') : null;
    final pick3 = winner.picks.length > 2 ? winner.picks[2].replaceFirst('frc', '') : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MatchColors.yellorLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MatchColors.yellor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: MatchColors.yellorDark, size: 20),
              SizedBox(width: 8),
              Text('Event winner', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
            ],
          ),
          if (winScore != null && loseScore != null) ...[
            const SizedBox(height: 12),
            Text('Won $winScore \u2013 $loseScore', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 14),
          if (captain != null) allianceMemberRow('Captain', captain),
          if (pick2 != null) allianceMemberRow('2nd pick', pick2),
          if (pick3 != null) allianceMemberRow('3rd pick', pick3),
        ],
      ),
    );
  }

  Widget allianceMemberRow(String role, String teamNumber) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 74, child: Text(role, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          Text(teamNumber, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
        ],
      ),
    );
  }

  Widget competitorTile(EventTeamInfo team) {
    final avgPoints = avgPointsByTeam[team.teamNumber];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(team.teamNumber, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(team.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
          if (avgPoints != null) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  avgPoints.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MatchColors.yellorDark),
                ),
                Text('Avg pts', style: TextStyle(fontSize: 9, color: Colors.grey[400])),
              ],
            ),
          ],
        ],
      ),
    );
  }
}