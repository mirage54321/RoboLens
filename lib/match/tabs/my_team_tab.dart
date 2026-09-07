import 'dart:async';

import 'package:flutter/material.dart';

import '../match_data_controller.dart';
import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import '../match_top_bar.dart';

class MyTeamTab extends StatefulWidget {
  final VoidCallback? onOpenStats;

  const MyTeamTab({super.key, this.onOpenStats});

  @override
  State<MyTeamTab> createState() => _MyTeamTabState();
}

class _MyTeamTabState extends State<MyTeamTab> {
  String? _historyView;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;

    if (team == null) {
      return noTeamState(context);
    }
    if (team.isLoading && team.events.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
    }
    if (team.error != null && team.events.isEmpty) {
      return errorState(context, controller, team);
    }

    return RefreshIndicator(
      color: MatchColors.yellor,
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          teamHeader(context, controller, team),
          const SizedBox(height: 12),
          if (team.pushState != 'subscribed') ...[
            pushCard(controller, team),
            const SizedBox(height: 12),
          ],
          matchOrWaitingCard(controller, team),
          if (team.nextMatch != null) ...[
            const SizedBox(height: 10),
            suggestionsCard(controller, team, team.nextMatch!),
          ],
          const SizedBox(height: 20),
          upcomingMatchesSection(controller, team),
          const SizedBox(height: 20),
          recentMatchesSection(team),
          const SizedBox(height: 20),
          profileSection(team),
        ],
      ),
    );
  }

  Widget noTeamState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.groups_outlined, color: MatchColors.yellorDark, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Set your team', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Add your team number to see its schedule, get match alerts, and track upcoming competitions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MatchColors.yellor),
              onPressed: () => showTeamPrompt(context),
              child: const Text('Set your team'),
            ),
          ],
        ),
      ),
    );
  }

  Widget errorState(BuildContext context, MatchDataController controller, MyTeam team) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(team.error!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: controller.refreshEvents,
              child: const Text('Try again', style: TextStyle(color: MatchColors.yellor, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget teamHeader(BuildContext context, MatchDataController controller, MyTeam team) {
    final status = team.myStatus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(team.teamNumber, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.profile?.teamName ?? 'Team ${team.teamNumber}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                // if (status != null && team.selectedEvent?.isLiveNow == true)
                //   Text(
                //     'Rank ${status.rank ?? '-'}${status.numTeams != null ? '/${status.numTeams}' : ''} · ${status.wins}-${status.losses}-${status.ties}',
                //     overflow: TextOverflow.ellipsis,
                //     style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                //   ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => showTeamPrompt(context),
            child: Icon(Icons.edit_outlined, size: 18, color: Colors.grey[400]),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => confirmStop(context, controller, team),
            child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  void confirmStop(BuildContext context, MatchDataController controller, MyTeam team) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop following Team ${team.teamNumber}?'),
        content: const Text("You'll stop getting its match alerts."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.clearMyTeam();
            },
            child: const Text('Remove', style: TextStyle(color: MatchColors.red)),
          ),
        ],
      ),
    );
  }

  Widget pushCard(MatchDataController controller, MyTeam team) {
    if (team.pushState == 'unsupported') return const SizedBox.shrink();
    final subscribed = team.pushState == 'subscribed';
    return GestureDetector(
      onTap: subscribed ? null : controller.showPushButtonHint,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: subscribed ? MatchColors.yellor : MatchColors.yellorLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(subscribed ? Icons.notifications_active : Icons.notifications_none,
                color: subscribed ? Colors.white : MatchColors.yellor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subscribed ? 'Match alerts on' : 'Get match alerts',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  subscribed
                      ? "You'll get a push notification before Team ${team.teamNumber}'s matches."
                      : 'Turn on the bell up top to get notified before matches start.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget matchOrWaitingCard(MatchDataController controller, MyTeam team) {
    final next = team.nextMatch;
    if (next != null) return countdownCard(controller, team, next);

    final upcomingEvent = team.nextUpcomingEvent;
    if (upcomingEvent != null) {
      return upcomingEventCard(upcomingEvent);
    }

    final nextSeasonYear = DateTime.now().year + 1;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No upcoming matches on the schedule for Team ${team.teamNumber}. Waiting for the $nextSeasonYear game release.',
              style: const TextStyle(fontSize: 13, color: MatchColors.yellorDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget upcomingEventCard(MatchEvent event) {
    final start = event.startDate;
    final days = start != null ? _daysUntil(start, DateTime.now()) : null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No matches scheduled yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MatchColors.yellorDark)),
                const SizedBox(height: 2),
                Text(
                  days == null
                      ? 'Next up: ${event.name}'
                      : days <= 0
                          ? 'Next up: ${event.name} (today)'
                          : 'Next up: ${event.name} in $days day${days == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: MatchColors.yellorDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget countdownCard(MatchDataController controller, MyTeam team, MatchInfo next) {
    final now = DateTime.now();
    final time = next.bestTime;
    final timeUntil = time != null ? time.difference(now) : null;
    final winProb = controller.winProbabilityFor(team, next);
    final withinDay = timeUntil != null && !timeUntil.isNegative && timeUntil <= const Duration(hours: 24);
    final overdue = timeUntil != null && timeUntil.isNegative;

    String bigText;
    if (timeUntil == null) {
      bigText = 'Time not posted yet';
    } else if (overdue) {
      bigText = 'Should be on the field now';
    } else if (withinDay) {
      bigText = 'in ${controller.formatDuration(timeUntil)}';
    } else {
      final days = timeUntil.inDays;
      bigText = 'in $days day${days == 1 ? '' : 's'}';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT MATCH',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(next.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            bigText,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          if (time != null) ...[
            const SizedBox(height: 2),
            Text(
              withinDay || overdue ? clockLabel(time) : '${_dayLabel(time)} ${_shortDate(time)}',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
            ),
          ],
          if (winProb != null) ...[
            const SizedBox(height: 14),
            winBar(winProb),
          ],
        ],
      ),
    );
  }

  Widget winBar(double winProb) {
    final pct = (winProb * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Est. win chance', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
            Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: winProb.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ],
    );
  }

  Widget suggestionsCard(MatchDataController controller, MyTeam team, MatchInfo next) {
    final time = next.bestTime;
    final timeUntil = time != null ? time.difference(DateTime.now()) : Duration.zero;
    final winProb = controller.winProbabilityFor(team, next);
    final tips = controller.suggestionsFor(team, next, timeUntil, winProb);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline, color: MatchColors.yellorDark, size: 18),
            SizedBox(width: 8),
            Text('Before this match',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MatchColors.yellorDark)),
          ]),
          const SizedBox(height: 10),
          ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('•  $t', style: const TextStyle(fontSize: 13)),
              )),
        ],
      ),
    );
  }

  Widget upcomingMatchesSection(MatchDataController controller, MyTeam team) {
    final upcoming = team.upcomingMatches.toList()
      ..sort((a, b) {
        final at = a.bestTime;
        final bt = b.bestTime;
        if (at == null && bt == null) return a.matchNumber.compareTo(b.matchNumber);
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upcoming matches', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
        const SizedBox(height: 10),
        ...upcoming.map((m) => upcomingMatchRow(controller, team, m)),
      ],
    );
  }

  Widget upcomingMatchRow(MatchDataController controller, MyTeam team, MatchInfo m) {
    final onRed = m.teamOnRed(team.teamKey);
    final myColor = onRed ? MatchColors.red : MatchColors.blue;
    final oppColor = onRed ? MatchColors.blue : MatchColors.red;
    final partners = (onRed ? m.redTeams : m.blueTeams)
        .where((k) => k != team.teamKey)
        .map((k) => k.replaceFirst('frc', ''))
        .toList();
    final opponentKeys = onRed ? m.blueTeams : m.redTeams;
    final winProb = controller.winProbabilityFor(team, m);
    final time = m.bestTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: myColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: myColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (winProb != null)
                Text(
                  '${(winProb * 100).round()}% win chance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: myColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            time != null ? '${_dayLabel(time)} ${clockLabel(time)}' : 'Time not posted yet',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text('Opponents', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[400])),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: opponentKeys.map((k) => allianceChip(k, team.worldOprs[k], oppColor)).toList(),
          ),
          if (partners.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('With', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[400])),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: partners
                  .map((n) => allianceChip('frc$n', team.worldOprs['frc$n'], myColor))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget allianceChip(String teamKey, double? opr, Color color) {
    final number = teamKey.replaceFirst('frc', '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(
        opr != null ? '$number · OPR ${opr.toStringAsFixed(1)}' : number,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  String _dayLabel(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[t.weekday - 1];
  }

  Widget recentMatchesSection(MyTeam team) {

    final cutoff = DateTime.now().subtract(const Duration(hours: 5));
    final played = team.myMatches.where((m) {
      if (!m.isPlayed) return false;
      final t = m.bestTime;
      return t == null || !t.isBefore(cutoff);
    }).toList()
      ..sort((a, b) {
        final at = a.bestTime;
        final bt = b.bestTime;
        if (at == null && bt == null) {
          return b.matchNumber.compareTo(a.matchNumber);
        }
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    if (played.isEmpty) return const SizedBox.shrink();

    final status = team.myStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent matches', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            if (status != null)
              Text(
                '${status.wins}-${status.losses}-${status.ties}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[600]),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...played.map((m) => matchResultRow(team, m)),
      ],
    );
  }

  Widget matchResultRow(MyTeam team, MatchInfo m) {
    final onRed = m.teamOnRed(team.teamKey);
    final myScore = onRed ? m.redScore : m.blueScore;
    final oppScore = onRed ? m.blueScore : m.redScore;
    final tied = myScore != null && oppScore != null && myScore == oppScore;
    final won = !tied && myScore != null && oppScore != null && myScore > oppScore;
    final resultLabel = tied ? 'TIE' : (won ? 'WIN' : 'LOSS');
    final resultColor = tied ? Colors.grey[500]! : (won ? MatchColors.green : MatchColors.red);

    final partners = (onRed ? m.redTeams : m.blueTeams)
        .where((k) => k != team.teamKey)
        .map((k) => k.replaceFirst('frc', ''))
        .join(', ');
    final opponents = (onRed ? m.blueTeams : m.redTeams)
        .map((k) => k.replaceFirst('frc', ''))
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: resultColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              resultLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: resultColor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (opponents.isNotEmpty)
                  Text('vs $opponents', style: TextStyle(fontSize: 11, color: Colors.grey[500]), overflow: TextOverflow.ellipsis),
                if (partners.isNotEmpty)
                  Text('with $partners', style: TextStyle(fontSize: 11, color: Colors.grey[400]), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${myScore ?? '-'} \u2013 ${oppScore ?? '-'}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget profileSection(MyTeam team) {
    if (team.loadingProfile && team.profile == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
      );
    }

    final profile = team.profile;
    if (profile == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Team history', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
        const SizedBox(height: 10),
        profileStatsCard(profile),
        const SizedBox(height: 10),
        Text('Tap a category to view it', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        if (_historyView == 'years') ...[
          const SizedBox(height: 12),
          _historyNote(
            Icons.calendar_today_outlined,
            profile.rookieYear == null
                ? 'Rookie year is not available.'
                : 'Team ${team.teamNumber} has competed in FIRST Robotics for ${profile.yearsCompeting} year${profile.yearsCompeting == 1 ? '' : 's'} (since ${profile.rookieYear}).',
          ),
        ],
        if (_historyView == 'awards' && profile.awards.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Awards (${profile.awards.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 10),
          ...profile.awards.map((a) => awardRow(a)),
        ],
        if (_historyView == 'events' && profile.pastEvents.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Past events', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 10),
          ...profile.pastEvents.map((e) => pastEventRow(e)),
        ],
      ],
    );
  }

  Widget profileStatsCard(TeamProfile profile) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          profileStatChip('World Rank', profile.worldRank != null ? '#${profile.worldRank}' : '-', 'world'),
          profileStatChip('Years', profile.yearsCompeting != null ? '${profile.yearsCompeting}' : '-', 'years'),
          profileStatChip('Events', '${profile.pastEvents.length}', 'events'),
          profileStatChip('Awards', '${profile.awards.length}', 'awards'),
        ],
      ),
    );
  }

  Widget profileStatChip(String label, String value, String view) {
    final selected = _historyView == view;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (view == 'world') {
          widget.onOpenStats?.call();
          return;
        }
        setState(() => _historyView = selected ? null : view);
      },
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? MatchColors.yellor : MatchColors.yellorDark), textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500]), textAlign: TextAlign.center),
      ])),
    ));
  }

  Widget _historyNote(IconData icon, String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Icon(icon, size: 18, color: MatchColors.yellorDark),
      const SizedBox(width: 9),
      Expanded(child: Text(message, style: const TextStyle(fontSize: 12, color: MatchColors.yellorDark))),
    ]),
  );

  Widget awardRow(TeamAward award) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined, size: 18, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(award.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${award.eventName} · ${award.year}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget pastEventRow(PastEventResult event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('${event.year}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.eventName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(
                  event.rank != null
                      ? 'Placed ${event.rank}${event.numTeams != null ? ' of ${event.numTeams}' : ''}'
                      : 'No ranking data',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                if (event.awards.isNotEmpty)
                  Text(event.awards.join(', '), style: const TextStyle(fontSize: 11, color: MatchColors.yellorDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String clockLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  int _daysUntil(DateTime target, DateTime from) {
    final targetDay = DateTime(target.year, target.month, target.day);
    final fromDay = DateTime(from.year, from.month, from.day);
    return targetDay.difference(fromDay).inDays;
  }

  String _shortDate(DateTime t) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[t.month - 1]} ${t.day}';
  }
}