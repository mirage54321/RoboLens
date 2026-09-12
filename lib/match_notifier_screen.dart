import 'package:flutter/material.dart';
import 'tap_cursor.dart';

import 'match/match_data_controller.dart';
import 'match/match_scope.dart';
import 'match/match_theme.dart';
import 'match/match_top_bar.dart';
import 'match/tabs/match_events_tab.dart';
import 'match/tabs/match_simulator_tab.dart';
import 'match/tabs/match_stats_tab.dart';
import 'match/tabs/my_team_tab.dart';


class MatchNotifierScreen extends StatefulWidget {
  const MatchNotifierScreen({super.key});

  @override
  State<MatchNotifierScreen> createState() => _MatchNotifierScreenState();
}

class _MatchNotifierScreenState extends State<MatchNotifierScreen> {
  late final MatchDataController _controller;
  int _tabIndex = 0;
  int _statsFocusToken = 0;

  static const int _myTeamTab = 0;
  static const int _statsTab = 1;
  static const int _eventsTab = 2;
  static const int _simulatorTab = 3;

  @override
  void initState() {
    super.initState();
    _controller = MatchDataController();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MatchScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Scaffold(
              backgroundColor: Color.fromARGB(255, 255, 255, 248),
              body: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
            );
          }

          final showingPushHint = _controller.myTeam?.showPushHint ?? false;
          return Scaffold(
            backgroundColor: const Color.fromARGB(255, 255, 255, 248),
            appBar: const MatchTopBar(),
            body: Stack(
              children: [
                SafeArea(
                  top: false,
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      MyTeamTab(onOpenStats: () => setState(() {
                        _tabIndex = 1;
                        _statsFocusToken++;
                      })),
                      MatchStatsTab(focusMyTeamToken: _statsFocusToken),
                      MatchEventsTab(),
                      MatchSimulatorTab(),
                    ],
                  ),
                ),
                if (showingPushHint)
                  Positioned.fill(
                    child: TapCursor(
                      behavior: HitTestBehavior.opaque,
                      onTap: _controller.dismissPushButtonHint,
                      child: ColoredBox(color: Colors.black.withValues(alpha: .52)),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) {
                if (showingPushHint) {
                  _controller.dismissPushButtonHint();
                  return;
                }
                setState(() => _tabIndex = i);
              },
              backgroundColor: showingPushHint ? const Color(0xff737373) : Colors.white,
              indicatorColor: showingPushHint ? Colors.transparent : MatchColors.yellorLight,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'My Team'),
                NavigationDestination(icon: Icon(Icons.leaderboard_outlined), selectedIcon: Icon(Icons.leaderboard), label: 'Stats'),
                NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Events'),
                NavigationDestination(icon: Icon(Icons.compare_arrows_outlined), selectedIcon: Icon(Icons.compare_arrows), label: 'Sim'),
              ],
            ),
          );
        },
      ),
    );
  }
}