import '../../models/daytime_sleep_entry.dart';
import '../../models/sleep_session.dart';

class DaytimeSleepCorrelation {
  const DaytimeSleepCorrelation({
    required this.followingNightCount,
    required this.averageFollowingNightMinutes,
  });

  final int followingNightCount;
  final double? averageFollowingNightMinutes;
}

/// Descriptive association only: finds completed night sessions beginning
/// within 18 hours after a manually logged daytime-rest interval.
class DaytimeSleepAnalytics {
  static DaytimeSleepCorrelation summarizeFollowingNights({
    required List<DaytimeSleepEntry> entries,
    required List<SleepSession> sessions,
  }) {
    final completed = sessions.where((session) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      return end != null && end.isAfter(start);
    }).toList()
      ..sort((a, b) {
        final aStart = a.actualSleepStartedAt ?? a.startedAt;
        final bStart = b.actualSleepStartedAt ?? b.startedAt;
        return aStart.compareTo(bStart);
      });

    final matchedIds = <String>{};
    final durations = <double>[];
    final orderedEntries = [...entries]
      ..sort((a, b) => a.endedAt.compareTo(b.endedAt));

    for (final entry in orderedEntries) {
      SleepSession? next;
      DateTime? nextStart;
      for (final session in completed) {
        if (matchedIds.contains(session.id)) continue;
        final start = session.actualSleepStartedAt ?? session.startedAt;
        if (!start.isAfter(entry.endedAt)) continue;
        if (start.difference(entry.endedAt) > const Duration(hours: 18)) break;
        next = session;
        nextStart = start;
        break;
      }
      if (next == null || nextStart == null) continue;
      final end = next.actualSleepEndedAt ?? next.endedAt!;
      final minutes = end.difference(nextStart).inMinutes;
      if (minutes <= 0) continue;
      matchedIds.add(next.id);
      durations.add(minutes.toDouble());
    }

    final average = durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) / durations.length;
    return DaytimeSleepCorrelation(
      followingNightCount: durations.length,
      averageFollowingNightMinutes: average,
    );
  }
}
