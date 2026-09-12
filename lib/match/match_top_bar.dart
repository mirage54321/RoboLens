import 'package:flutter/material.dart';
import '../tap_cursor.dart';

import 'match_scope.dart';
import 'match_theme.dart';


class MatchTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MatchTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;
    final showingPushHint = team?.showPushHint ?? false;

    return Container(
      color: showingPushHint ? const Color(0xff737373) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Opacity(
            opacity: showingPushHint ? .35 : 1,
            child: TapCursor(
              onTap: () => Navigator.pop(context),
              child: iconTile(Icons.arrow_back),
            ),
          ),
          const Spacer(),
          if (team != null && team.pushState != 'unsupported')
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: team.showPushHint ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOut,
              builder: (context, glow, child) => Transform.scale(
                scale: 1 + glow * 0.16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: showingPushHint ? Colors.white : null,
                    border: Border.all(
                      color: showingPushHint
                          ? MatchColors.yellor
                          : MatchColors.yellor.withValues(alpha: glow),
                      width: showingPushHint ? 4 : 3,
                    ),
                    boxShadow: [BoxShadow(color: MatchColors.yellor.withValues(alpha: showingPushHint ? .75 : glow * .45), blurRadius: 18, spreadRadius: 5)],
                  ),
                  child: child,
                ),
              ),
              child: TapCursor(
              onTap: team.selectedEventKey == null ? null : () => togglePush(context),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: team.pushState == 'subscribed'
                      ? MatchColors.yellor
                      : MatchColors.yellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: team.pushBusy
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2, color: MatchColors.yellor),
                      )
                    : Icon(
                        team.pushState == 'subscribed'
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: team.pushState == 'subscribed' ? Colors.white : MatchColors.yellor,
                        size: 18,
                      ),
              ),
              ),
            ),
        ],
      ),
    );
  }

  Widget iconTile(IconData icon) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: MatchColors.yellor, size: 17),
      );

  Future<void> togglePush(BuildContext context) async {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;
    if (team == null) return;
    controller.dismissPushButtonHint();
    final outcome = await controller.togglePush();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        'subscribed' => 'Match alerts on for Team ${team.teamNumber}',
        'unsubscribed' => 'Match alerts turned off',
        'ios-install-required' => 'On iPhone, open RoboLens from your Home Screen by clicking the three dots at the bottom right corner. Then click all "share", and scroll down to find "Add to Home Screen". You can turn alerts on there.',
        'permission-denied' => 'Notifications are blocked. Enable them for RoboLens in iPhone Settings, then try again.',
        'server-not-configured' => 'Alerts are not configured on the RoboLens server yet.',
        'no-event' => 'Choose a competition before enabling match alerts.',
        'unsupported' => 'This browser does not support match alerts.',
        _ => 'Could not enable alerts. Please try again.',
      }),
      duration: Duration(seconds: outcome == 'ios-install-required' ? 7 : 4),
    ));
  }
}

void showTeamPrompt(BuildContext context) {
  final controller = MatchScope.of(context);
  final ctrl = TextEditingController(text: controller.myTeam?.teamNumber ?? '');
  String? error;
  final isReplacing = controller.myTeam != null;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(isReplacing ? 'Change your team' : 'Set your team'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Team number',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            errorText: error,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatchColors.yellor),
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                setD(() => error = 'Enter a team number');
                return;
              }
              Navigator.pop(ctx);
              controller.setMyTeam(t);
            },
            child: Text(isReplacing ? 'Save' : 'Add'),
          ),
        ],
      ),
    ),
  );
}