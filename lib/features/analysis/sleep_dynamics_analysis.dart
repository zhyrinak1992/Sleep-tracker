import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_regularity_analysis.dart';
import 'sleep_score.dart';

enum SleepDynamicsPeriod { week, month, year }

class SleepDynamicsSummary {
  const SleepDynamicsSummary({
    required this.start,
    required this.endExclusive,
    required this.sessionsCount,
    required this.completedCount,
    required this.averageSleepMinutes,
    required this.durationSamples,
    required this.averageSleepScore,
    required this.scoreSamples,
    required this.averageEfficiency,
    required this.efficiencySamples,
    required this.averageAwakenings,
    required this.awakeningSamples,
    required this.averageQuality,
    required this.qualitySamples,
    required this.averageWellbeing,
    required this.wellbeingSamples,
    required this.bedtimeDeviationMinutes,
    required this.wakeTimeDeviationMinutes,
    required this.regularitySamples,
    required this.typicalBedtimeMinute,
    required this.typicalWakeMinute,
    required this.chartValues,
    required this.chartScoreValues,
    required this.chartEfficiencyValues,
    required this.chartAwakeningValues,
    required this.chartQualityValues,
    required this.chartWellbeingValues,
  });

  final DateTime start;
  final DateTime endExclusive;
  final int sessionsCount;
  final int completedCount;
  final double? averageSleepMinutes;
  final int durationSamples;
  final double? averageSleepScore;
  final int scoreSamples;
  final double? averageEfficiency;
  final int efficiencySamples;
  final double? averageAwakenings;
  final int awakeningSamples;
  final double? averageQuality;
  final int qualitySamples;
  final double? averageWellbeing;
  final int wellbeingSamples;
  final double? bedtimeDeviationMinutes;
  final double? wakeTimeDeviationMinutes;
  final int regularitySamples;
  final int? typicalBedtimeMinute;
  final int? typicalWakeMinute;
  final List<double?> chartValues;
  final List<double?> chartScoreValues;
  final List<double?> chartEfficiencyValues;
  final List<double?> chartAwakeningValues;
  final List<double?> chartQualityValues;
  final List<double?> chartWellbeingValues;
}

class SleepDynamicsRollingRanges {
  const SleepDynamicsRollingRanges({
    required this.currentStart,
    required this.currentEndExclusive,
    required this.previousStart,
    required this.previousEndExclusive,
  });
  final DateTime currentStart;
  final DateTime currentEndExclusive;
  final DateTime previousStart;
  final DateTime previousEndExclusive;
}

class SleepDynamicsAnalysis {
  static DateTime addCalendarDays(DateTime value, int days) =>
      DateTime(value.year, value.month, value.day + days);

  static SleepDynamicsRollingRanges rollingRanges(DateTime now, int days) {
    if (days <= 0) throw ArgumentError.value(days, 'days', 'Длительность должна быть положительной.');
    final today = DateTime(now.year, now.month, now.day);
    // Use calendar construction instead of Duration(days: ...): a fixed
    // 24-hour subtraction can land at 23:00/01:00 across DST transitions.
    final currentStart = DateTime(today.year, today.month, today.day - days + 1);
    final currentEnd = DateTime(today.year, today.month, today.day + 1);
    final previousStart = DateTime(currentStart.year, currentStart.month, currentStart.day - days);
    return SleepDynamicsRollingRanges(
      currentStart: currentStart,
      currentEndExclusive: currentEnd,
      previousStart: previousStart,
      previousEndExclusive: currentStart,
    );
  }

  static SleepDynamicsRollingRanges rollingThirtyDayRanges(DateTime now) =>
    rollingRanges(now, 30);
  static DateTime periodStart(DateTime value, SleepDynamicsPeriod period) {
    final day = DateTime(value.year, value.month, value.day);
    if (period == SleepDynamicsPeriod.week) {
      return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
    }
    if (period == SleepDynamicsPeriod.month) return DateTime(value.year, value.month);
    return DateTime(value.year);
  }

  static DateTime nextPeriodStart(DateTime start, SleepDynamicsPeriod period) {
    if (period == SleepDynamicsPeriod.week) return DateTime(start.year, start.month, start.day + 7);
    if (period == SleepDynamicsPeriod.month) return DateTime(start.year, start.month + 1);
    return DateTime(start.year + 1);
  }

  static DateTime previousPeriodStart(DateTime start, SleepDynamicsPeriod period) {
    if (period == SleepDynamicsPeriod.week) return DateTime(start.year, start.month, start.day - 7);
    if (period == SleepDynamicsPeriod.month) return DateTime(start.year, start.month - 1);
    return DateTime(start.year - 1);
  }

  static ({DateTime start, DateTime endExclusive}) bucketRange(
    DateTime periodStart,
    SleepDynamicsPeriod period,
    int index,
  ) {
    final start = switch (period) {
      SleepDynamicsPeriod.week => DateTime(periodStart.year, periodStart.month, periodStart.day + index),
      SleepDynamicsPeriod.month => DateTime(periodStart.year, periodStart.month, index * 7 + 1),
      SleepDynamicsPeriod.year => DateTime(periodStart.year, index + 1),
    };
    final end = switch (period) {
      SleepDynamicsPeriod.week => DateTime(start.year, start.month, start.day + 1),
      SleepDynamicsPeriod.month => DateTime(periodStart.year, periodStart.month, (index + 1) * 7 + 1).isBefore(DateTime(periodStart.year, periodStart.month + 1))
        ? DateTime(periodStart.year, periodStart.month, (index + 1) * 7 + 1)
        : DateTime(periodStart.year, periodStart.month + 1),
      SleepDynamicsPeriod.year => DateTime(periodStart.year, index + 2),
    };
    if (index < 0 || index >= switch (period) {
      SleepDynamicsPeriod.week => 7,
      SleepDynamicsPeriod.month => 5,
      SleepDynamicsPeriod.year => 12,
    }) {
      throw RangeError.index(index, List<int>.generate(switch (period) {
        SleepDynamicsPeriod.week => 7,
        SleepDynamicsPeriod.month => 5,
        SleepDynamicsPeriod.year => 12,
      }, (i) => i));
    }
    return (start: start, endExclusive: end);
  }

  static SleepDynamicsSummary summarize({
    required Iterable<SleepSession> sessions,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required Map<String, Map<String, Object?>> morningReports,
    required DateTime start,
    required DateTime endExclusive,
    required SleepDynamicsPeriod period,
    Map<String, SleepScoreResult>? scoreCache,
  }) {
    final from = DateTime(start.year, start.month, start.day);
    final until = DateTime(endExclusive.year, endExclusive.month, endExclusive.day);
    if (!until.isAfter(from)) throw ArgumentError('Конец периода должен быть позже начала.');

    final selected = sessions.where((session) =>
      !session.startedAt.isBefore(from) && session.startedAt.isBefore(until)).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed = selected.where((session) =>
      session.endedAt != null && session.duration != null && session.duration!.inMinutes > 0).toList();

    final durations = <double>[];
    final efficiencies = <double>[];
    final awakenings = <double>[];
    final qualities = <double>[];
    final wellbeing = <double>[];
    final sleepScores = <double>[];
    final cache = scoreCache ?? <String, SleepScoreResult>{};
    final bucketCount = switch (period) {
      SleepDynamicsPeriod.week => 7,
      SleepDynamicsPeriod.month => 5,
      SleepDynamicsPeriod.year => 12,
    };
    final bucketTotals = List<double>.filled(bucketCount, 0);
    final bucketSamples = List<int>.filled(bucketCount, 0);
    final bucketScoreTotals = List<double>.filled(bucketCount, 0);
    final bucketScoreSamples = List<int>.filled(bucketCount, 0);
    final bucketEfficiencyTotals = List<double>.filled(bucketCount, 0);
    final bucketEfficiencySamples = List<int>.filled(bucketCount, 0);
    final bucketAwakeningTotals = List<double>.filled(bucketCount, 0);
    final bucketAwakeningSamples = List<int>.filled(bucketCount, 0);
    final bucketQualityTotals = List<double>.filled(bucketCount, 0);
    final bucketQualitySamples = List<int>.filled(bucketCount, 0);
    final bucketWellbeingTotals = List<double>.filled(bucketCount, 0);
    final bucketWellbeingSamples = List<int>.filled(bucketCount, 0);

    for (final session in completed) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
      final score = cache.putIfAbsent(session.id, () =>
        SleepScoreCalculator.calculateForSession(
          session: session,
          historySessions: sessions,
          morningReports: morningReports,
          stagesBySession: stagesBySession,
        ),
      ).score;
      if (score != null) {
        sleepScores.add(score);
      }
      final bucket = switch (period) {
        SleepDynamicsPeriod.week => session.startedAt.weekday - 1,
        SleepDynamicsPeriod.month => ((session.startedAt.day - 1) ~/ 7).clamp(0, 4),
        SleepDynamicsPeriod.year => session.startedAt.month - 1,
      };
      // Use stage-derived/actual boundaries where available; otherwise retain
      // the saved session interval, clearly counted as an available duration sample.
      final duration = metrics.sleepDurationMinutes ?? session.duration!.inMinutes;
      if (duration > 0) {
        durations.add(duration.toDouble());
        bucketTotals[bucket] += duration;
        bucketSamples[bucket]++;
      }
      if (score != null) {
        bucketScoreTotals[bucket] += score;
        bucketScoreSamples[bucket]++;
      }
      final efficiency = metrics.sleepEfficiencyPercent;
      if (efficiency != null && efficiency.isFinite) {
        efficiencies.add(efficiency);
        bucketEfficiencyTotals[bucket] += efficiency;
        bucketEfficiencySamples[bucket]++;
      }
      if (stages.isNotEmpty && metrics.stageCoveragePercent != null) {
        final count = metrics.awakeningCount.toDouble();
        awakenings.add(count);
        bucketAwakeningTotals[bucket] += count;
        bucketAwakeningSamples[bucket]++;
      }
      final report = morningReports[session.id];
      final quality = report?['sleep_quality'];
      final feel = report?['wellbeing'];
      if (quality is num && quality.toDouble().isFinite) {
        qualities.add(quality.toDouble());
        bucketQualityTotals[bucket] += quality.toDouble();
        bucketQualitySamples[bucket]++;
      }
      if (feel is num && feel.toDouble().isFinite) {
        wellbeing.add(feel.toDouble());
        bucketWellbeingTotals[bucket] += feel.toDouble();
        bucketWellbeingSamples[bucket]++;
      }
    }

    double? average(List<double> values) => values.isEmpty
      ? null
      : values.reduce((a, b) => a + b) / values.length;

    final regularity = SleepRegularityAnalysis.calculate(completed);
    List<double?> chart(List<double> totals, List<int> samples) =>
      List<double?>.generate(bucketCount, (index) =>
        samples[index] == 0 ? null : totals[index] / samples[index]);
    final chartDurations = chart(bucketTotals, bucketSamples);
    final chartScores = chart(bucketScoreTotals, bucketScoreSamples);
    final chartEfficiency = chart(bucketEfficiencyTotals, bucketEfficiencySamples);
    final chartAwakenings = chart(bucketAwakeningTotals, bucketAwakeningSamples);
    final chartQuality = chart(bucketQualityTotals, bucketQualitySamples);
    final chartWellbeing = chart(bucketWellbeingTotals, bucketWellbeingSamples);

    return SleepDynamicsSummary(
      start: from,
      endExclusive: until,
      sessionsCount: selected.length,
      completedCount: completed.length,
      averageSleepMinutes: average(durations),
      durationSamples: durations.length,
      averageSleepScore: average(sleepScores),
      scoreSamples: sleepScores.length,
      averageEfficiency: average(efficiencies),
      efficiencySamples: efficiencies.length,
      averageAwakenings: average(awakenings),
      awakeningSamples: awakenings.length,
      averageQuality: average(qualities),
      qualitySamples: qualities.length,
      averageWellbeing: average(wellbeing),
      wellbeingSamples: wellbeing.length,
      bedtimeDeviationMinutes: regularity.nights.length < 2 ? null : regularity.bedtimeMad,
      wakeTimeDeviationMinutes: regularity.nights.length < 2 ? null : regularity.wakeMad,
      regularitySamples: regularity.nights.length,
      typicalBedtimeMinute: regularity.nights.length < 2 ? null : regularity.typicalBedtimeMinute,
      typicalWakeMinute: regularity.nights.length < 2 ? null : regularity.typicalWakeMinute,
      chartValues: chartDurations,
      chartScoreValues: chartScores,
      chartEfficiencyValues: chartEfficiency,
      chartAwakeningValues: chartAwakenings,
      chartQualityValues: chartQuality,
      chartWellbeingValues: chartWellbeing,
    );
  }
}
