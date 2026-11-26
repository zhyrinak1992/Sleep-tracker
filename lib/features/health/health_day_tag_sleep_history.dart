import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';

enum HealthDayTagNightMetric {
  sleepDuration,
  sleepEfficiency,
  sleepLatency,
  awakenings,
  sleepQuality,
  wellbeing,
  morningRating,
}

extension HealthDayTagNightMetricLabel on HealthDayTagNightMetric {
  String get label => switch (this) {
    HealthDayTagNightMetric.sleepDuration => 'Продолжительность сна',
    HealthDayTagNightMetric.sleepEfficiency => 'Эффективность сна',
    HealthDayTagNightMetric.sleepLatency => 'Задержка засыпания',
    HealthDayTagNightMetric.awakenings => 'Эпизоды бодрствования',
    HealthDayTagNightMetric.sleepQuality => 'Качество сна',
    HealthDayTagNightMetric.wellbeing => 'Самочувствие утром',
    HealthDayTagNightMetric.morningRating => 'Утренняя оценка',
  };

  String get unit => switch (this) {
    HealthDayTagNightMetric.sleepDuration => 'ч',
    HealthDayTagNightMetric.sleepEfficiency => '%',
    HealthDayTagNightMetric.sleepLatency => 'мин',
    HealthDayTagNightMetric.awakenings => 'эп.',
    HealthDayTagNightMetric.sleepQuality => '/ 5',
    HealthDayTagNightMetric.wellbeing => '/ 5',
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


  static HealthDayTagNightMetricPeriodComparison comparePeriods({
    required Iterable<SleepSession> sessions,
    required Map<DateTime, List<String>> tagsByDay,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required String tag,
    required DateTime firstStart,
    required DateTime firstEndExclusive,
    required DateTime secondStart,
    required DateTime secondEndExclusive,
    required HealthDayTagNightMetric metric,
    Map<String, Map<String, Object?>> morningReportsBySession = const {},
  }) {
    HealthDayTagNightMetricPeriodSummary summarizePeriod(
      DateTime start,
      DateTime endExclusive,
    ) {
      final tagged = calculate(
        sessions: sessions,
        tagsByDay: tagsByDay,
        stagesBySession: stagesBySession,
        tag: tag,
        start: start,
        endExclusive: endExclusive,
        metric: metric,
        morningReportsBySession: morningReportsBySession,
        withTag: true,
      );
      final untagged = calculate(
        sessions: sessions,
        tagsByDay: tagsByDay,
        stagesBySession: stagesBySession,
        tag: tag,
        start: start,
        endExclusive: endExclusive,
        metric: metric,
        morningReportsBySession: morningReportsBySession,
        withTag: false,
      );

      HealthDayTagNightMetricGroupSummary summarize(
        List<HealthDayTagNightMetricPoint> points,
      ) {
        final values = points
            .map((point) => point.value)
            .whereType<double>()
            .where((value) => value.isFinite)
            .toList();
        return HealthDayTagNightMetricGroupSummary(
          nights: points.length,
          validSamples: values.length,
          average: values.isEmpty
              ? null
              : values.reduce((a, b) => a + b) / values.length,
        );
      }

      return HealthDayTagNightMetricPeriodSummary(
        start: DateTime(start.year, start.month, start.day),
        endExclusive: DateTime(
          endExclusive.year,
          endExclusive.month,
          endExclusive.day,
        ),
        withTag: summarize(tagged),
        withoutTag: summarize(untagged),
      );
    }

    if (tag.trim().isEmpty ||
        !firstEndExclusive.isAfter(firstStart) ||
        !secondEndExclusive.isAfter(secondStart)) {
      throw ArgumentError('Некорректные периоды сравнения отметки.');
    }
    return HealthDayTagNightMetricPeriodComparison(
      first: summarizePeriod(firstStart, firstEndExclusive),
      second: summarizePeriod(secondStart, secondEndExclusive),
    );
  }

  /// Returns true only when the day has a saved diary entry and its tag
  /// membership matches the requested group. A missing entry is unknown data,
  /// not evidence that the tag was absent.
  static bool matchesTagGroup({
    required SleepSession session,
    required Map<DateTime, List<String>> tagsByDay,
    required String tag,
    required bool withTag,
  }) {
    final endedAt = session.endedAt;
    if (tag.trim().isEmpty ||
        session.deletedAt != null ||
        endedAt == null ||
        !endedAt.isAfter(session.startedAt)) {
      return false;
    }
    final day = DateTime(endedAt.year, endedAt.month, endedAt.day);
    final recordedTags = tagsByDay[day];
    if (recordedTags == null) return false;
    return recordedTags.contains(tag) == withTag;
  }

  static List<HealthDayTagNightMetricPoint> calculate({
    required Iterable<SleepSession> sessions,
    required Map<DateTime, List<String>> tagsByDay,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required String tag,
    required DateTime start,
    required DateTime endExclusive,
    required HealthDayTagNightMetric metric,
    Map<String, Map<String, Object?>> morningReportsBySession = const {},
    bool withTag = true,
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
      if (!matchesTagGroup(
        session: session,
        tagsByDay: tagsByDay,
        tag: tag,
        withTag: withTag,
      )) {
        continue;
      }

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
        HealthDayTagNightMetric.sleepQuality =>
          (morningReportsBySession[session.id]?['sleep_quality'] as num?)
              ?.toDouble(),
        HealthDayTagNightMetric.wellbeing =>
          (morningReportsBySession[session.id]?['wellbeing'] as num?)
              ?.toDouble(),
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


class HealthDayTagNightMetricGroupSummary {
  const HealthDayTagNightMetricGroupSummary({
    required this.nights,
    required this.validSamples,
    required this.average,
  });

  final int nights;
  final int validSamples;
  final double? average;
}

class HealthDayTagNightMetricPeriodSummary {
  const HealthDayTagNightMetricPeriodSummary({
    required this.start,
    required this.endExclusive,
    required this.withTag,
    required this.withoutTag,
  });

  final DateTime start;
  final DateTime endExclusive;
  final HealthDayTagNightMetricGroupSummary withTag;
  final HealthDayTagNightMetricGroupSummary withoutTag;

  /// Mean for tagged nights minus mean for nights without the selected tag.
  double? get difference {
    final taggedAverage = withTag.average;
    final untaggedAverage = withoutTag.average;
    if (taggedAverage == null || untaggedAverage == null) return null;
    return taggedAverage - untaggedAverage;
  }
}

class HealthDayTagNightMetricPeriodComparison {
  const HealthDayTagNightMetricPeriodComparison({
    required this.first,
    required this.second,
  });

  final HealthDayTagNightMetricPeriodSummary first;
  final HealthDayTagNightMetricPeriodSummary second;

  /// Change in the tagged-vs-untagged difference: period 2 minus period 1.
  double? get differenceChange {
    final firstDifference = first.difference;
    final secondDifference = second.difference;
    if (firstDifference == null || secondDifference == null) return null;
    return secondDifference - firstDifference;
  }
}

