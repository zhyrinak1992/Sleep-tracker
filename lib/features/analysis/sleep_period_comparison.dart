import '../../models/sleep_session.dart';
import 'audio_event_analysis.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_regularity_analysis.dart';

class SleepRangeSummary {
  const SleepRangeSummary({
    required this.start,
    required this.endExclusive,
    required this.sessions,
    required this.completed,
    required this.rated,
    required this.averageDurationMinutes,
    required this.averageRating,
    required this.bedtimeDeviationMinutes,
    required this.wakeTimeDeviationMinutes,
    required this.regularitySampleCount,
  });

  final DateTime start;
  final DateTime endExclusive;
  final List<SleepSession> sessions;
  final int completed;
  final int rated;
  final double? averageDurationMinutes;
  final double? averageRating;
  final double? bedtimeDeviationMinutes;
  final double? wakeTimeDeviationMinutes;
  final int regularitySampleCount;
}

class SleepPeriodComparison {
  static SleepRangeSummary summarize(
    Iterable<SleepSession> source,
    DateTime start,
    DateTime endInclusive,
  ) {
    final from = DateTime(start.year, start.month, start.day);
    final until = DateTime(endInclusive.year, endInclusive.month, endInclusive.day)
        .add(const Duration(days: 1));
    if (!until.isAfter(from)) {
      throw ArgumentError('Конец периода должен быть не раньше начала.');
    }
    final selected = source.where((session) =>
      !session.startedAt.isBefore(from) && session.startedAt.isBefore(until))
      .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed = selected.where((session) =>
      session.duration != null && session.duration!.inMinutes > 0).toList();
    final rated = selected.where((session) => session.morningRating != null).toList();
    final regularity = SleepRegularityAnalysis.calculate(completed);
    return SleepRangeSummary(
      start: from,
      endExclusive: until,
      sessions: selected,
      completed: completed.length,
      rated: rated.length,
      averageDurationMinutes: completed.isEmpty ? null :
        completed.fold<int>(0, (sum, item) => sum + item.duration!.inMinutes) / completed.length,
      averageRating: rated.isEmpty ? null :
        rated.fold<int>(0, (sum, item) => sum + item.morningRating!) / rated.length,
      bedtimeDeviationMinutes: regularity.bedtimeMad,
      wakeTimeDeviationMinutes: regularity.wakeMad,
      regularitySampleCount: regularity.nights.length,
    );
  }

  static double? percentageChange(double? current, double? previous) {
    if (current == null || previous == null || previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}


class SleepPeriodDetailSummary {
  const SleepPeriodDetailSummary({
    required this.averageEfficiency,
    required this.efficiencySamples,
    required this.averageAwakenings,
    required this.awakeningSamples,
    required this.averageQuality,
    required this.qualitySamples,
    required this.averageWellbeing,
    required this.wellbeingSamples,
    required this.typicalBedtimeMinute,
    required this.typicalWakeMinute,
    required this.regularitySamples,
    required this.audio,
  });

  final double? averageEfficiency;
  final int efficiencySamples;
  final double? averageAwakenings;
  final int awakeningSamples;
  final double? averageQuality;
  final int qualitySamples;
  final double? averageWellbeing;
  final int wellbeingSamples;
  final int? typicalBedtimeMinute;
  final int? typicalWakeMinute;
  final int regularitySamples;
  final AudioEventPeriodSummary audio;

  static SleepPeriodDetailSummary summarize({
    required SleepRangeSummary range,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required Map<String, Map<String, Object?>> morningReports,
    required Iterable<Map<String, Object?>> audioEvents,
  }) {
    final efficiency = <double>[];
    final awakenings = <double>[];
    final quality = <double>[];
    final wellbeing = <double>[];
    final completed = range.sessions.where((session) =>
      session.endedAt != null && session.duration != null && session.duration!.inMinutes > 0).toList();

    for (final session in completed) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
      final efficiencyValue = metrics.sleepEfficiencyPercent;
      if (efficiencyValue != null && efficiencyValue.isFinite) efficiency.add(efficiencyValue);
      if (stages.isNotEmpty && metrics.stageCoveragePercent != null) {
        awakenings.add(metrics.awakeningCount.toDouble());
      }
      final report = morningReports[session.id];
      final qualityValue = report?['sleep_quality'];
      final wellbeingValue = report?['wellbeing'];
      if (qualityValue is num && qualityValue.toDouble().isFinite) quality.add(qualityValue.toDouble());
      if (wellbeingValue is num && wellbeingValue.toDouble().isFinite) wellbeing.add(wellbeingValue.toDouble());
    }

    double? average(List<double> values) => values.isEmpty
      ? null
      : values.reduce((a, b) => a + b) / values.length;
    final regularity = SleepRegularityAnalysis.calculate(completed);
    final audio = AudioEventPeriodSummary.summarize(
      events: audioEvents,
      sessionIds: completed.map((session) => session.id).toSet(),
    );

    return SleepPeriodDetailSummary(
      averageEfficiency: average(efficiency),
      efficiencySamples: efficiency.length,
      averageAwakenings: average(awakenings),
      awakeningSamples: awakenings.length,
      averageQuality: average(quality),
      qualitySamples: quality.length,
      averageWellbeing: average(wellbeing),
      wellbeingSamples: wellbeing.length,
      typicalBedtimeMinute: regularity.typicalBedtimeMinute,
      typicalWakeMinute: regularity.typicalWakeMinute,
      regularitySamples: regularity.nights.length,
      audio: audio,
    );
  }
}
