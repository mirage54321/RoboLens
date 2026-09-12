import 'dart:async';

import 'package:flutter/material.dart';
import '../../tap_cursor.dart';

import '../match_data_controller.dart';
import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import '../team_detail_screen.dart';


class MatchStatsTab extends StatefulWidget {
  final int focusMyTeamToken;

  const MatchStatsTab({super.key, this.focusMyTeamToken = 0});

  @override
  State<MatchStatsTab> createState() => MatchStatsTabState();
}

enum _StatsView { top, searchResult }

class MatchStatsTabState extends State<MatchStatsTab> {
  final TextEditingController _searchController = TextEditingController();
  Future<List<TeamStats>>? statsFuture;
  bool _loaded = false;
  _StatsView _view = _StatsView.top;

  String query = '';
  Timer? _debounce;

  bool searchLoading = false;
  String? searchError;
  TeamStats? searchedTeam;
  List<TeamStats> searchedNearby = [];

  bool showMyTeam = false;

  @override
  void didUpdateWidget(covariant MatchStatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusMyTeamToken != oldWidget.focusMyTeamToken) {
      final number = MatchScope.of(context).myTeam?.teamNumber;
      if (number != null) {
        _showTeam(number);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    if (!_loaded) {
      _loaded = true;
      statsFuture = controller.loadWorldTeamStats();
      _view = _StatsView.top;
      searchedTeam = null;
      searchedNearby = [];
      searchError = null;
    }
    final myTeamNumber = controller.myTeam?.teamNumber;
    final showToggle = myTeamNumber != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Team Stats',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Season-wide RoboLens World Rating · built from TBA event OPRs',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey[400], size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: 'Search team number',
                                border: InputBorder.none,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: onQueryChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showToggle) ...[
                    const SizedBox(width: 8),
                    TapCursor(
                      onTap: () => toggleMyTeam(myTeamNumber),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: showMyTeam
                              ? MatchColors.yellor
                              : MatchColors.yellorLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Your team',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: showMyTeam
                                ? Colors.white
                                : MatchColors.yellorDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(child: body(context, myTeamNumber)),
      ],
    );
  }

  Widget body(BuildContext context, String? myTeamNumber) {
    if (statsFuture == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Loading the RoboLens World Rating…',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_view == _StatsView.searchResult) {
      if (searchLoading) {
        return const Center(
          child: CircularProgressIndicator(color: MatchColors.yellor),
        );
      }
      if (searchError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              searchError!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (searchedTeam == null) {
        return const SizedBox.shrink();
      }
   
      final list = [
        ...searchedNearby,
        if (!searchedNearby.any(
          (team) => team.teamNumber == searchedTeam!.teamNumber,
        ))
          searchedTeam!,
      ]..sort((a, b) => a.rank.compareTo(b.rank));
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        itemCount: list.length,
        itemBuilder: (ctx, i) => teamRow(
          context,
          list[i],
          list[i].rank,
          list[i].teamNumber == searchedTeam!.teamNumber,
        ),
      );
    }

    return FutureBuilder<List<TeamStats>>(
      future: statsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: MatchColors.yellor),
          );
        }

        if (snapshot.hasError || !(snapshot.data?.isNotEmpty ?? false)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'Could not reach the event stats service.'
                        : 'No event rankings are available yet.',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TapCursor(
                    onTap: () {
                      final controller = MatchScope.of(context);
                      setState(
                        () => statsFuture = controller.loadWorldTeamStats(
                          forceRefresh: true,
                        ),
                      );
                    },
                    child: const Text(
                      'Try again',
                      style: TextStyle(
                        color: MatchColors.yellor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final stats = snapshot.data!;
        return RefreshIndicator(
          color: MatchColors.yellor,
          onRefresh: () async {
            final controller = MatchScope.of(context);
            final f = controller.loadWorldTeamStats(forceRefresh: true);
            setState(() => statsFuture = f);
            await f;
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            itemCount: stats.length,
            itemBuilder: (ctx, i) => teamRow(
              context,
              stats[i],
              stats[i].rank,
              stats[i].teamNumber == myTeamNumber,
            ),
          ),
        );
      },
    );
  }

  void onQueryChanged(String v) {
    query = v.trim();
    _debounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _view = _StatsView.top;
        searchedTeam = null;
        searchedNearby = [];
        searchError = null;
      });
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => runSearch(query),
    );
  }

  Future<void> runSearch(String teamNumber) async {
    if (teamNumber.isEmpty) return;
    setState(() {
      _view = _StatsView.searchResult;
      searchLoading = true;
      searchError = null;
    });

    final controller = MatchScope.of(context);
    try {
      final result = await controller.loadWorldTeamStat(teamNumber);
      final team = result.team;
      if (!mounted || query != teamNumber) return;
      setState(() {
        searchLoading = false;
        searchedTeam = team;
        searchedNearby = result.nearby;
      });
    } catch (_) {
      if (!mounted || query != teamNumber) return;
      setState(() {
        searchLoading = false;
        searchError =
            'Could not reach the event stats service. Try again shortly.';
        searchedTeam = null;
        searchedNearby = [];
      });
    }
  }

  void toggleMyTeam(String myTeamNumber) {
    if (!showMyTeam) {
      _showTeam(myTeamNumber);
    } else {
      setState(() {
        showMyTeam = false;
        _view = _StatsView.top;
        searchedTeam = null;
        searchedNearby = [];
        searchError = null;
      });
    }
  }

  void _showTeam(String teamNumber) {
    _debounce?.cancel();
    setState(() {
      showMyTeam = true;
      query = teamNumber;
      _searchController.text = teamNumber;
      _searchController.selection = TextSelection.collapsed(
        offset: teamNumber.length,
      );
    });
    runSearch(teamNumber);
  }

  Widget teamRow(
    BuildContext context,
    TeamStats team,
    int position,
    bool isMine,
  ) {
    return TapCursor(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMine ? MatchColors.yellorLight : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMine
                ? MatchColors.yellor
                : Colors.black.withValues(alpha: 0.07),
            width: isMine ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '$position',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[400],
                ),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MatchColors.yellorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                team.teamNumber,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MatchColors.yellorDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'World rank ${team.rank} · ${team.wins}-${team.losses}-${team.ties}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(

                  team.opr?.toStringAsFixed(1) ?? '-',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: MatchColors.yellorDark,
                  ),
                ),
                Text(
                  'Average Points',
                  style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}