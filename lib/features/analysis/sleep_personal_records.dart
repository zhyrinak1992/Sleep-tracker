import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';

/// Personal bests derived only from completed, non-deleted sessions.
/// Dates are compared as local calendar days (not 24-hour durations), so DST
/// transitions cannot break a streak.
class SleepPersonalRecords {
  const SleepPersonalRecords({
    this.longestSleepMinutes,
    this.longestSleepSessionId,
    this.longestSleepAt,
    this.bestEfficiencyPercent,
    this.bestEfficiencySessionId,
    this.bestEfficiencyAt,
    this.shortestLatencyMinutes,
    this.shortestLatencySessionId,
    this.shortestLatencyAt,
    this.longestStreakDays = 0,
  });

  final int? longestSleepMinutes;
  final String? longestSleepSessionId;
  final DateTime? longestSleepAt;
  final double? bestEfficiencyPercent;
  final String? bestEfficiencySessionId;
  final DateTime? bestEfficiencyAt;
  final int? shortestLatencyMinutes;
  final String? shortestLatencySessionId;
  final DateTime? shortestLatencyAt;
  final int longestStreakDays;

  static SleepPersonalRecords calculate({
    required Iterable<SleepSession> sessions,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
  }) {
    final valid = sessions.where((session) {
      final duration = session.duration;
      return session.deletedAt == null &&
          session.endedAt != null &&
          duration != null &&
          duration.inMinutes > 0;
    }).toList(growable: false);

    int? longestSleep;
    String? longestSleepId;
    DateTime? longestSleepAt;
    double? bestEfficiency;
    String? bestEfficiencyId;
    DateTime? bestEfficiencyAt;
    int? shortestLatency;
    String? shortestLatencyId;
    DateTime? shortestLatencyAt;

    for (final session in valid) {
      final metrics = SleepSessionMetrics.calculate(
        session: session,
        stages: stagesBySession[session.id] ?? const [],
      );
      final sleepMinutes = metrics.sleepDurationMinutes;
      if (sleepMinutes != null && sleepMinutes > 0 &&
          (longestSleep == null || sleepMinutes > longestSleep)) {
        longestSleep = sleepMinutes;
        longestSleepId = session.id;
        longestSleepAt = session.startedAt;
      }

      final efficiency = metrics.sleepEfficiencyPercent;
      if (efficiency != null && efficiency.isFinite &&
          efficiency >= 0 && efficiency <= 100 &&
          (bestEfficiency == null || efficiency > bestEfficiency)) {
        bestEfficiency = efficiency;
        bestEfficiencyId = session.id;
        bestEfficiencyAt = session.startedAt;
      }

      final latency = metrics.sleepLatencyMinutes;
      if (latency != null && latency >= 0 && latency <= 1440 &&
          (shortestLatency == null || latency < shortestLatency)) {
        shortestLatency = latency;
        shortestLatencyId = session.id;
        shortestLatencyAt = session.startedAt;
      }
    }

    return SleepPersonalRecords(
      longestSleepMinutes: longestSleep,
      longestSleepSessionId: longestSleepId,
      longestSleepAt: longestSleepAt,
      bestEfficiencyPercent: bestEfficiency,
      bestEfficiencySessionId: bestEfficiencyId,
      bestEfficiencyAt: bestEfficiencyAt,
      shortestLatencyMinutes: shortestLatency,
      shortestLatencySessionId: shortestLatencyId,
      shortestLatencyAt: shortestLatencyAt,
      longestStreakDays: longestStreak(valid),
    );
  }

  static int longestStreak(Iterable<SleepSession> sessions) {
    final days = sessions
        .where((session) => session.deletedAt == null &&
            session.endedAt != null &&
            session.duration != null &&
            session.duration!.inMinutes > 0)
        .map((session) => DateTime.utc(
              session.startedAt.year,
              session.startedAt.month,
              session.startedAt.day,
            ))
        .toSet()
        .toList()
      ..sort();

    if (days.isEmpty) return 0;
    var longest = 1;
    var current = 1;
    for (var i = 1; i < days.length; i++) {
      final difference = days[i].difference(days[i - 1]).inDays;
      if (difference == 1) {
        current++;
        if (current > longest) longest = current;
      } else if (difference > 1) {
        current = 1;
      }
    }
    return longest;
  }

  Map<String, Object?> toMap() => {
        'longestSleepMinutes': longestSleepMinutes,
        'longestSleepSessionId': longestSleepSessionId,
        'longestSleepAt': longestSleepAt?.toUtc().toIso8601String(),
        'bestEfficiencyPercent': bestEfficiencyPercent,
        'bestEfficiencySessionId': bestEfficiencySessionId,
        'bestEfficiencyAt': bestEfficiencyAt?.toUtc().toIso8601String(),
        'shortestLatencyMinutes': shortestLatencyMinutes,
        'shortestLatencySessionId': shortestLatencySessionId,
        'shortestLatencyAt': shortestLatencyAt?.toUtc().toIso8601String(),
        'longestStreakDays': longestStreakDays,
      };

  factory SleepPersonalRecords.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final value = map[key];
      return value is String ? DateTime.tryParse(value)?.toLocal() : null;
    }

    int? integer(String key) {
      final value = map[key];
      return value is int && value >= 0 ? value : null;
    }

    double? decimal(String key) {
      final value = map[key];
      if (value is! num || !value.toDouble().isFinite) return null;
      final result = value.toDouble();
      return result >= 0 && result <= 100 ? result : null;
    }

    String? string(String key) => map[key] is String ? map[key] as String : null;

    return SleepPersonalRecords(
      longestSleepMinutes: integer('longestSleepMinutes'),
      longestSleepSessionId: string('longestSleepSessionId'),
      longestSleepAt: date('longestSleepAt'),
      bestEfficiencyPercent: decimal('bestEfficiencyPercent'),
      bestEfficiencySessionId: string('bestEfficiencySessionId'),
      bestEfficiencyAt: date('bestEfficiencyAt'),
      shortestLatencyMinutes: integer('shortestLatencyMinutes'),
      shortestLatencySessionId: string('shortestLatencySessionId'),
      shortestLatencyAt: date('shortestLatencyAt'),
      longestStreakDays: integer('longestStreakDays') ?? 0,
    );
  }

  /// Merges a new calculation with the persisted all-time bests. Deleting or
  /// editing an old night therefore cannot silently erase an earned record.
  SleepPersonalRecords preserveBest(SleepPersonalRecords previous) {
    final keepSleep = previous.longestSleepMinutes != null &&
        (longestSleepMinutes == null ||
            previous.longestSleepMinutes! >= longestSleepMinutes!);
    final keepEfficiency = previous.bestEfficiencyPercent != null &&
        (bestEfficiencyPercent == null ||
            previous.bestEfficiencyPercent! >= bestEfficiencyPercent!);
    final keepLatency = previous.shortestLatencyMinutes != null &&
        (shortestLatencyMinutes == null ||
            previous.shortestLatencyMinutes! <= shortestLatencyMinutes!);
    return SleepPersonalRecords(
      longestSleepMinutes: keepSleep ? previous.longestSleepMinutes : longestSleepMinutes,
      longestSleepSessionId: keepSleep ? previous.longestSleepSessionId : longestSleepSessionId,
      longestSleepAt: keepSleep ? previous.longestSleepAt : longestSleepAt,
      bestEfficiencyPercent: keepEfficiency ? previous.bestEfficiencyPercent : bestEfficiencyPercent,
      bestEfficiencySessionId: keepEfficiency ? previous.bestEfficiencySessionId : bestEfficiencySessionId,
      bestEfficiencyAt: keepEfficiency ? previous.bestEfficiencyAt : bestEfficiencyAt,
      shortestLatencyMinutes: keepLatency ? previous.shortestLatencyMinutes : shortestLatencyMinutes,
      shortestLatencySessionId: keepLatency ? previous.shortestLatencySessionId : shortestLatencySessionId,
      shortestLatencyAt: keepLatency ? previous.shortestLatencyAt : shortestLatencyAt,
      longestStreakDays: longestStreakDays > previous.longestStreakDays
          ? longestStreakDays
          : previous.longestStreakDays,
    );
  }
}
