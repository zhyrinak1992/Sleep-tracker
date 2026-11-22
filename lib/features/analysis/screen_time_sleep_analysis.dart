import '../../models/screen_time_entry.dart';
import '../../models/sleep_session.dart';

class ScreenTimeSleepGroup {
  const ScreenTimeSleepGroup({
    required this.label,
    required this.nights,
    required this.averageSleepMinutes,
    required this.averageScreenMinutes,
  });

  final String label;
  final int nights;
  final double averageSleepMinutes;
  final double averageScreenMinutes;
}

class ScreenTimeSleepAnalysis {
  ScreenTimeSleepAnalysis._();

  static const _groups = [
    (label: 'До 30 минут', maxGap: 30),
    (label: '31–60 минут', maxGap: 60),
    (label: '61–120 минут', maxGap: 120),
    (label: 'Более 120 минут', maxGap: 1440),
  ];

  static List<ScreenTimeSleepGroup> summarize({
    required Iterable<SleepSession> sessions,
    required Map<String, ScreenTimeEntry> entries,
  }) {
    final values = <({int gap, int screen, double sleep})>[];
    for (final session in sessions) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      if (end == null || !end.isAfter(start)) continue;
      final entry = entries[session.id];
      if (entry == null || entry.sessionId != session.id) continue;
      final gap = start.difference(entry.lastUseAt).inMinutes;
      if (gap < 0 || gap > 1440) continue;
      if (entry.durationMinutes < 0 || entry.durationMinutes > 360) continue;
      values.add((
        gap: gap,
        screen: entry.durationMinutes,
        sleep: end.difference(start).inMinutes.toDouble(),
      ));
    }

    final result = <ScreenTimeSleepGroup>[];
    var lowerBound = 0;
    for (final group in _groups) {
      final selected = values.where((value) =>
        value.gap >= lowerBound && value.gap <= group.maxGap).toList();
      if (selected.isNotEmpty) {
        result.add(ScreenTimeSleepGroup(
          label: group.label,
          nights: selected.length,
          averageSleepMinutes: selected.map((value) => value.sleep).reduce((a, b) => a + b) / selected.length,
          averageScreenMinutes: selected.map((value) => value.screen.toDouble()).reduce((a, b) => a + b) / selected.length,
        ));
      }
      lowerBound = group.maxGap + 1;
    }
    return result;
  }
}
