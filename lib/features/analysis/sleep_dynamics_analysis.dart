import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_regularity_analysis.dart';

enum SleepDynamicsPeriod { week, month, year }

class SleepDynamicsSummary {
  const SleepDynamicsSummary({
    required this.start,
    required this.endExclusive,
    required this.sessionsCount,
    required this.completedCount,
    required this.averageSleepMinutes,
    required this.durationSamples,
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
    required this.chartValues,
  });

  final DateTime start;
  final DateTime endExclusive;
  final int sessionsCount;
  final int completedCount;
  final double? averageSleepMinutes;
  final int durationSamples;
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
  final List<double?> chartValues;
}

class SleepDynamicsAnalysis {
  static DateTime periodStart(DateTime value, SleepDynamicsPeriod period) {
    final day = DateTime(value.year, value.month, value.day);
    if (period == SleepDynamicsPeriod.week) {
      return day.subtract(Duration(days: day.weekday - DateTime.monday));
    }
    if (period == SleepDynamicsPeriod.month) return DateTime(value.year, value.month);
    return DateTime(value.year);
  }

  static DateTime nextPeriodStart(DateTime start, SleepDynamicsPeriod period) {
    if (period == SleepDynamicsPeriod.week) return start.add(const Duration(days: 7));
    if (period == SleepDynamicsPeriod.month) return DateTime(start.year, start.month + 1);
    return DateTime(start.year + 1);
  }

  static DateTime previousPeriodStart(DateTime start, SleepDynamicsPeriod period) {
    if (period == SleepDynamicsPeriod.week) return start.subtract(const Duration(days: 7));
    if (period == SleepDynamicsPeriod.month) return DateTime(start.year, start.month - 1);
    return DateTime(start.year - 1);
  }

  static SleepDynamicsSummary summarize({
    required Iterable<SleepSession> sessions,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required Map<String, Map<String, Object?>> morningReports,
    required DateTime start,
    required DateTime endExclusive,
    required SleepDynamicsPeriod period,
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
    final bucketCount = switch (period) {
      SleepDynamicsPeriod.week => 7,
      SleepDynamicsPeriod.month => 5,
      SleepDynamicsPeriod.year => 12,
    };
    final bucketTotals = List<double>.filled(bucketCount, 0);
    final bucketSamples = List<int>.filled(bucketCount, 0);

    for (final session in completed) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
      // Use stage-derived/actual boundaries where available; otherwise retain
      // the saved session interval, clearly counted as an available duration sample.
      final duration = metrics.sleepDurationMinutes ?? session.duration!.inMinutes;
      if (duration > 0) {
        durations.add(duration.toDouble());
        final bucket = switch (period) {
          SleepDynamicsPeriod.week => session.startedAt.weekday - 1,
          SleepDynamicsPeriod.month => ((session.startedAt.day - 1) ~/ 7).clamp(0, 4),
          SleepDynamicsPeriod.year => session.startedAt.month - 1,
        };
        bucketTotals[bucket] += duration;
        bucketSamples[bucket]++;
      }
      final efficiency = metrics.sleepEfficiencyPercent;
      if (efficiency != null && efficiency.isFinite) efficiencies.add(efficiency);
      if (stages.isNotEmpty && metrics.stageCoveragePercent != null) {
        awakenings.add(metrics.awakeningCount.toDouble());
      }
      final report = morningReports[session.id];
      final quality = report?['sleep_quality'];
      final feel = report?['wellbeing'];
      if (quality is num && quality.toDouble().isFinite) qualities.add(quality.toDouble());
      if (feel is num && feel.toDouble().isFinite) wellbeing.add(feel.toDouble());
    }

    double? average(List<double> values) => values.isEmpty
      ? null
      : values.reduce((a, b) => a + b) / values.length;

    final regularity = SleepRegularityAnalysis.calculate(completed);
    final chart = List<double?>.generate(bucketCount, (index) =>
      bucketSamples[index] == 0 ? null : bucketTotals[index] / bucketSamples[index]);

    return SleepDynamicsSummary(
      start: from,
      endExclusive: until,
      sessionsCount: selected.length,
      completedCount: completed.length,
      averageSleepMinutes: average(durations),
      durationSamples: durations.length,
      averageEfficiency: average(efficiencies),
      efficiencySamples: efficiencies.length,
      averageAwakenings: average(awakenings),
      awakeningSamples: awakenings.length,
      averageQuality: average(qualities),
      qualitySamples: qualities.length,
      averageWellbeing: average(wellbeing),
      wellbeingSamples: wellbeing.length,
      bedtimeDeviationMinutes: regularity.bedtimeMad,
      wakeTimeDeviationMinutes: regularity.wakeMad,
      regularitySamples: regularity.nights.length,
      chartValues: chart,
    );
  }
}
