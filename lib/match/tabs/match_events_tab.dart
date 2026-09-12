import 'package:flutter/material.dart';
import '../../tap_cursor.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import 'event_detail_screen.dart';


class MatchEventsTab extends StatefulWidget {
  const MatchEventsTab({super.key});

  @override
  State<MatchEventsTab> createState() => _MatchEventsTabState();
}

class _MatchEventsTabState extends State<MatchEventsTab> {
  Future<List<MatchEvent>>? _future;
  bool _filterByLocation = false;
  bool _showPastCompetitions = false;
  String _locationQuery = '';

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    _future ??= controller.loadGlobalEvents();
    final myEventKeys = controller.myTeam?.events.map((e) => e.key).toSet() ?? <String>{};

    return FutureBuilder<List<MatchEvent>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: MatchColors.yellor),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Loading events\u2026 this can take up to 20 seconds if the server was asleep.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          );
        }
        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load events right now.', style: TextStyle(color: Colors.grey[600])),
            ),
          );
        }

        final now = DateTime.now();
        final filtered = _filterByLocation && _locationQuery.isNotEmpty
            ? events.where((event) => event.location.toLowerCase().contains(_locationQuery.toLowerCase())).toList()
            : events;
        int compare(MatchEvent a, MatchEvent b) =>
            (a.startDate ?? DateTime(2100)).compareTo(b.startDate ?? DateTime(2100));


        final live = filtered.where((e) => e.isLiveNow).toList()..sort(compare);
        final liveKeys = live.map((e) => e.key).toSet();
        final upcoming = filtered
            .where((e) => !liveKeys.contains(e.key) && (e.endDate == null || !e.endDate!.isBefore(now)))
            .toList()..sort(compare);
        final past = filtered
            .where((e) => !liveKeys.contains(e.key) && e.endDate != null && e.endDate!.isBefore(now))
            .toList()..sort(compare);

        return RefreshIndicator(
          color: MatchColors.yellor,
          onRefresh: () async {
            final f = controller.loadGlobalEvents();
            setState(() => _future = f);
            await f;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Events', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Your events are highlighted', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Filter by time'), selected: !_filterByLocation, onSelected: (_) => setState(() => _filterByLocation = false)),
                ChoiceChip(label: const Text('Filter by location'), selected: _filterByLocation, onSelected: (_) => setState(() => _filterByLocation = true)),
              ]),
              if (_filterByLocation) ...[
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => setState(() => _locationQuery = value.trim()),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on_outlined), hintText: 'City, state, or country', border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 16),
              if (live.isNotEmpty) ...[
                _sectionLabel('Live now'),
                ...live.map((e) => _eventCard(context, e, myEventKeys.contains(e.key))),
                const SizedBox(height: 12),
              ],
              if (upcoming.isNotEmpty) ...[
                _sectionLabel('Upcoming'),
                ...upcoming.map((e) => _eventCard(context, e, myEventKeys.contains(e.key))),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(
                    () => _showPastCompetitions = !_showPastCompetitions,
                  ),
                  icon: Icon(
                    _showPastCompetitions
                        ? Icons.expand_less
                        : Icons.history,
                  ),
                  label: Text(
                    _showPastCompetitions
                        ? 'Hide past competitions'
                        : 'View past competitions',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MatchColors.yellorDark,
                    side: const BorderSide(color: MatchColors.yellor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                if (_showPastCompetitions) ...[
                  const SizedBox(height: 14),
                  _sectionLabel('Past'),
                  ...past.map(
                    (e) => _eventCard(context, e, myEventKeys.contains(e.key)),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
      );

  Widget _eventCard(BuildContext context, MatchEvent e, bool isMine) {
    final isLive = e.isLiveNow;
    return TapCursor(
      onTap: () {

        final controller = MatchScope.of(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchScope(
              controller: controller,
              child: EventDetailScreen(event: e, isMine: isMine),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMine ? MatchColors.yellorLight : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isMine ? MatchColors.yellor : Colors.black.withValues(alpha: 0.07), width: isMine ? 1.5 : 1),
        ),
        child: Row(
          children: [
            isLive
                ? const Icon(Icons.circle, size: 10, color: MatchColors.green)
                : const Icon(Icons.event_outlined, size: 18, color: MatchColors.yellorDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text(_dateRange(e), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  if (e.location.isNotEmpty)
                    Text(e.location, style: TextStyle(fontSize: 11, color: Colors.grey[500]), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isMine)
              const Icon(Icons.star, color: MatchColors.yellor, size: 18)
            else
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  String _dateRange(MatchEvent e) {
    if (e.startDate == null) return '';
    final s = e.startDate!;
    String fmt(DateTime d) => '${_month(d.month)} ${d.day}';
    if (e.endDate == null) return fmt(s);
    return '${fmt(s)} \u2013 ${fmt(e.endDate!)}, ${e.endDate!.year}';
  }

  String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}