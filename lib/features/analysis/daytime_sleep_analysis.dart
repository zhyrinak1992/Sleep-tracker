import '../models/daytime_sleep_entry.dart';
import '../models/sleep_session.dart';

class DaytimeSleepComparison {
  const DaytimeSleepComparison({
    required this.nightsWithNap,
    required this.nightsWithoutNap,
    required this.averageSleepWithNapMinutes,
    required this.averageSleepWithoutNapMinutes,
  });

  final int nightsWithNap;
  final int nightsWithoutNap;
  final double? averageSleepWithNapMinutes;
  final double? averageSleepWithoutNapMinutes;

  double? get differenceMinutes =>
      averageSleepWithNapMinutes == null || averageSleepWithoutNapMinutes == null
          ? null
          : averageSleepWithNapMinutes! - averageSleepWithoutNapMinutes!;
}

class DaytimeSleepAnalysis {
  DaytimeSleepAnalysis._();

  /// Descriptively groups completed nights by whether a recorded nap occurred
  /// during the preceding waking interval (capped to the prior 24 hours).
  static DaytimeSleepComparison compareWithFollowingNights({
    required Iterable<SleepSession> sessions,
    required Iterable<DaytimeSleepEntry> naps,
  }) {
    final ordered = sessions.where((session) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      return end != null && end.isAfter(start);
    }).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final orderedNaps = naps.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final withNap = <double>[];
    final withoutNap = <double>[];
    for (var i = 0; i < ordered.length; i++) {
      final session = ordered[i];
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt!;
      var wakingStart = start.subtract(const Duration(hours: 24));
      if (i > 0) {
        final previous = ordered[i - 1];
        final previousEnd = previous.actualSleepEndedAt ?? previous.endedAt;
        if (previousEnd != null && previousEnd.isAfter(wakingStart) && previousEnd.isBefore(start)) {
          wakingStart = previousEnd;
        }
      }
      final hadNap = orderedNaps.any((nap) =>
        nap.startedAt.isBefore(start) &&
        nap.endedAt.isAfter(wakingStart) &&
        !nap.endedAt.isAfter(start));
      final duration = end.difference(start).inMinutes.toDouble();
      if (hadNap) {
        withNap.add(duration);
      } else {
        withoutNap.add(duration);
      }
    }

    double? average(List<double> values) => values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;

    return DaytimeSleepComparison(
      nightsWithNap: withNap.length,
      nightsWithoutNap: withoutNap.length,
      averageSleepWithNapMinutes: average(withNap),
      averageSleepWithoutNapMinutes: average(withoutNap),
    );
  }
}
