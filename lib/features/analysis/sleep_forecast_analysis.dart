import 'dart:math' as math;

import '../../models/sleep_session.dart';

class SleepForecastResult {
  const SleepForecastResult({
    required this.personalLatencyAvailable,
    required this.latencySamples,
    required this.medianLatencyMinutes,
    required this.lowerLatencyMinutes,
    required this.upperLatencyMinutes,
    required this.availableWindowMinutes,
    required this.estimatedSleepMinutes,
    required this.recommendedBedtimeStartMinute,
    required this.recommendedBedtimeEndMinute,
    required this.targetSleepMinutes,
    required this.recentSleepSamples,
    required this.recentSleepMinutes,
    required this.accumulatedShortfallMinutes,
    required this.recoveryNightsAtThirtyMinutes,
  });

  final bool personalLatencyAvailable;
  final int latencySamples;
  final int? medianLatencyMinutes;
  final int? lowerLatencyMinutes;
  final int? upperLatencyMinutes;
  final int availableWindowMinutes;
  final int? estimatedSleepMinutes;
  final int? recommendedBedtimeStartMinute;
  final int? recommendedBedtimeEndMinute;
  final int targetSleepMinutes;
  final int recentSleepSamples;
  final int? recentSleepMinutes;
  final int? accumulatedShortfallMinutes;
  final int? recoveryNightsAtThirtyMinutes;
}

class SleepForecastAnalysis {
  SleepForecastAnalysis._();

  static SleepForecastResult calculate({
    required Iterable<SleepSession> sessions,
    required DateTime now,
    required int plannedWakeMinute,
    required int plannedBedtimeMinute,
    required int targetSleepMinutes,
  }) {
    if (plannedWakeMinute < 0 || plannedWakeMinute >= 1440 ||
        plannedBedtimeMinute < 0 || plannedBedtimeMinute >= 1440) {
      throw ArgumentError('Время должно находиться в пределах суток.');
    }
    if (targetSleepMinutes < 180 || targetSleepMinutes > 900) {
      throw ArgumentError.value(targetSleepMinutes, 'targetSleepMinutes');
    }

    var available = plannedWakeMinute - plannedBedtimeMinute;
    if (available < 0) available += 1440;

    final cutoff90 = now.subtract(const Duration(days: 90));
    final recent = sessions.where((session) =>
      session.endedAt != null &&
      !session.startedAt.isBefore(cutoff90) &&
      !session.startedAt.isAfter(now) &&
      !session.userEdited &&
      session.source.toLowerCase() != 'manual'
    ).toList();

    final latencies = <int>[];
    for (final session in recent) {
      final buttonStart = session.buttonStartedAt;
      final actualStart = session.actualSleepStartedAt;
      if (buttonStart == null || actualStart == null ||
          !actualStart.isAfter(buttonStart)) continue;
      final latency = actualStart.difference(buttonStart).inMinutes;
      if (latency >= 0 && latency <= 180) latencies.add(latency);
    }
    latencies.sort();

    int? percentile(List<int> values, double fraction) {
      if (values.isEmpty) return null;
      final position = (values.length - 1) * fraction;
      final lower = position.floor();
      final upper = position.ceil();
      if (lower == upper) return values[lower];
      final weight = position - lower;
      return (values[lower] * (1 - weight) + values[upper] * weight).round();
    }

    final personalLatency = latencies.length >= 7;
    final medianLatency = personalLatency ? percentile(latencies, 0.5) : null;
    final lowerLatency = personalLatency ? percentile(latencies, 0.25) : null;
    final upperLatency = personalLatency ? percentile(latencies, 0.75) : null;

    final recentCutoff = DateTime(now.year, now.month, now.day - 7);
    final recentMinutes = <int>[];
    for (final session in sessions) {
      if (session.endedAt == null ||
          session.startedAt.isBefore(recentCutoff) ||
          session.startedAt.isAfter(now) ||
          session.userEdited ||
          session.source.toLowerCase() == 'manual') continue;
      final start = session.actualSleepStartedAt;
      final end = session.actualSleepEndedAt;
      if (start == null || end == null || !end.isAfter(start)) continue;
      final duration = end.difference(start).inMinutes;
      if (duration >= 120 && duration <= 960) recentMinutes.add(duration);
    }
    final enoughRecent = recentMinutes.length >= 5;
    final totalRecent = recentMinutes.isEmpty
        ? null
        : recentMinutes.reduce((a, b) => a + b);
    final shortfall = enoughRecent
        ? math.max(0, targetSleepMinutes * recentMinutes.length - totalRecent!)
        : null;

    final recommendedStart = personalLatency
        ? (plannedWakeMinute - targetSleepMinutes - upperLatency! + 2880) % 1440
        : null;
    final recommendedEnd = personalLatency
        ? (plannedWakeMinute - targetSleepMinutes - lowerLatency! + 2880) % 1440
        : null;

    return SleepForecastResult(
      personalLatencyAvailable: personalLatency,
      latencySamples: latencies.length,
      medianLatencyMinutes: medianLatency,
      lowerLatencyMinutes: lowerLatency,
      upperLatencyMinutes: upperLatency,
      availableWindowMinutes: available,
      estimatedSleepMinutes: personalLatency
          ? math.max(0, available - medianLatency!)
          : null,
      recommendedBedtimeStartMinute: recommendedStart,
      recommendedBedtimeEndMinute: recommendedEnd,
      targetSleepMinutes: targetSleepMinutes,
      recentSleepSamples: recentMinutes.length,
      recentSleepMinutes: totalRecent,
      accumulatedShortfallMinutes: shortfall,
      recoveryNightsAtThirtyMinutes: shortfall == null || shortfall == 0
          ? (shortfall == 0 ? 0 : null)
          : (shortfall / 30).ceil(),
    );
  }
}
