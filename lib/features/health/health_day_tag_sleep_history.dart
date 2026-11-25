import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';

enum HealthDayTagNightMetric {
  sleepDuration,
  sleepEfficiency,
  sleepLatency,
  awakenings,
  morningRating,
}

extension HealthDayTagNightMetricLabel on HealthDayTagNightMetric {
  String get label => switch (this) {
    HealthDayTagNightMetric.sleepDuration => 'Продолжительность сна',
    HealthDayTagNightMetric.sleepEfficiency => 'Эффективность сна',
    HealthDayTagNightMetric.sleepLatency => 'Задержка засыпания',
    HealthDayTagNightMetric.awakenings => 'Эпизоды бодрствования',
    HealthDayTagNightMetric.morningRating => 'Утренняя оценка',
  };

  String get unit => switch (this) {
    HealthDayTagNightMetric.sleepDuration => 'ч',
    HealthDayTagNightMetric.sleepEfficiency => '%',
    HealthDayTagNightMetric.sleepLatency => 'мин',
    HealthDayTagNightMetric.awakenings => 'эп.',
    HealthDayTagNightMetric.morningRating => '/ 5',
  };
}

class HealthDayTagNightMetricPoint {
  const HealthDayTagNightMetricPoint({
    required this.date,
    required this.sessionId,
    required this.value,
  });

  final DateTime date;
  final String sessionId;
  final double? value;
}

class HealthDayTagNightHistory {
  const HealthDayTagNightHistory._();

  static List<HealthDayTagNightMetricPoint> calculate({
    required Iterable<SleepSession> sessions,
    required Map<DateTime, List<String>> tagsByDay,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required String tag,
    required DateTime start,
    required DateTime endExclusive,
    required HealthDayTagNightMetric metric,
  }) {
    if (tag.trim().isEmpty || !endExclusive.isAfter(start)) {
      throw ArgumentError('Некорректные параметры истории отметки.');
    }
    final first = DateTime(start.year, start.month, start.day);
    final end = DateTime(endExclusive.year, endExclusive.month, endExclusive.day);
    final result = <HealthDayTagNightMetricPoint>[];
    for (final session in sessions) {
      final endedAt = session.endedAt;
      if (session.deletedAt != null || endedAt == null ||
          !endedAt.isAfter(session.startedAt)) continue;
      final day = DateTime(endedAt.year, endedAt.month, endedAt.day);
      if (day.isBefore(first) || !day.isBefore(end)) continue;
      final tags = tagsByDay[day] ?? const <String>[];
      if (!tags.contains(tag)) continue;

      final sessionStages = stagesBySession[session.id] ?? const [];
      final metrics = SleepSessionMetrics.calculate(
        session: session,
        stages: sessionStages,
      );
      final coverage = metrics.stageCoveragePercent;
      final value = switch (metric) {
        HealthDayTagNightMetric.sleepDuration =>
          metrics.sleepDurationMinutes == null
              ? null
              : metrics.sleepDurationMinutes! / 60,
        HealthDayTagNightMetric.sleepEfficiency =>
          metrics.sleepEfficiencyPercent,
        HealthDayTagNightMetric.sleepLatency =>
          metrics.sleepLatencyMinutes?.toDouble(),
        HealthDayTagNightMetric.awakenings =>
          coverage != null && coverage >= 80 && metrics.hasAwakeSamples
              ? metrics.awakeningCount.toDouble()
              : null,
        HealthDayTagNightMetric.morningRating =>
          session.morningRating?.toDouble(),
      };
      result.add(HealthDayTagNightMetricPoint(
        date: day,
        sessionId: session.id,
        value: value != null && value.isFinite ? value : null,
      ));
    }
    result.sort((a, b) {
      final date = a.date.compareTo(b.date);
      return date == 0 ? a.sessionId.compareTo(b.sessionId) : date;
    });
    return List.unmodifiable(result);
  }
}
