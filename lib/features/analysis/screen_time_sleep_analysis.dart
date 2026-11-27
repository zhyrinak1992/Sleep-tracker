import 'dart:math' as math;

enum ScreenTimeSleepMetric {
  sleepStartTime,
  sleepDuration,
  sleepEfficiency,
  awakenings,
  morningRating,
  sleepQuality,
  wellbeing,
}

class ScreenTimeSleepSample {
  const ScreenTimeSleepSample({
    required this.exposureMinutes,
    this.sleepStartMinutesOfDay,
    this.sleepDurationMinutes,
    this.sleepEfficiencyPercent,
    this.awakeningCount,
    this.morningRating,
    this.sleepQuality,
    this.wellbeing,
  });

  final double exposureMinutes;
  final double? sleepStartMinutesOfDay;
  final double? sleepDurationMinutes;
  final double? sleepEfficiencyPercent;
  final double? awakeningCount;
  final double? morningRating;
  final double? sleepQuality;
  final double? wellbeing;

  double? valueFor(ScreenTimeSleepMetric metric) => switch (metric) {
    ScreenTimeSleepMetric.sleepStartTime => sleepStartMinutesOfDay,
    ScreenTimeSleepMetric.sleepDuration => sleepDurationMinutes,
    ScreenTimeSleepMetric.sleepEfficiency => sleepEfficiencyPercent,
    ScreenTimeSleepMetric.awakenings => awakeningCount,
    ScreenTimeSleepMetric.morningRating => morningRating,
    ScreenTimeSleepMetric.sleepQuality => sleepQuality,
    ScreenTimeSleepMetric.wellbeing => wellbeing,
  };
}

class ScreenTimeMetricSummary {
  const ScreenTimeMetricSummary({required this.validSamples, required this.average});
  final int validSamples;
  final double? average;
}

class ScreenTimeGroupSummary {
  const ScreenTimeGroupSummary({required this.nights, required this.metrics});
  final int nights;
  final Map<ScreenTimeSleepMetric, ScreenTimeMetricSummary> metrics;
  ScreenTimeMetricSummary metric(ScreenTimeSleepMetric metric) =>
      metrics[metric] ?? const ScreenTimeMetricSummary(validSamples: 0, average: null);
}

class ScreenTimeComparison {
  const ScreenTimeComparison({
    required this.medianExposureMinutes,
    required this.lowerExposure,
    required this.upperExposure,
    required this.lowerGroup,
    required this.upperGroup,
  });

  final double medianExposureMinutes;
  final double lowerExposure;
  final double upperExposure;
  final ScreenTimeGroupSummary lowerGroup;
  final ScreenTimeGroupSummary upperGroup;

  bool get hasSufficientGroups =>
      lowerGroup.nights >= ScreenTimeSleepAnalysis.minimumValidSamplesPerGroup &&
      upperGroup.nights >= ScreenTimeSleepAnalysis.minimumValidSamplesPerGroup;

  double? differenceFor(ScreenTimeSleepMetric metric) {
    if (!hasSufficientGroups) return null;
    final lower = lowerGroup.metric(metric);
    final upper = upperGroup.metric(metric);
    if (lower.validSamples < ScreenTimeSleepAnalysis.minimumValidSamplesPerGroup ||
        upper.validSamples < ScreenTimeSleepAnalysis.minimumValidSamplesPerGroup ||
        lower.average == null || upper.average == null) return null;
    final difference = upper.average! - lower.average!;
    if (metric != ScreenTimeSleepMetric.sleepStartTime) return difference;
    if (difference > 720) return difference - 1440;
    if (difference < -720) return difference + 1440;
    return difference;
  }
}

class ScreenTimeSleepAnalysis {
  static const minimumValidSamplesPerGroup = 4;

  /// Returns local clock minutes. Group means are calculated circularly to handle midnight.
  static double? sleepStartMinutesOfDay(DateTime? value) {
    if (value == null) return null;
    return (value.hour * 60 + value.minute).toDouble();
  }

  static String formatSleepStartMinutes(double value) {
    final minutes = ((value.round() % 1440) + 1440) % 1440;
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static double _circularMeanMinutes(List<double> values) {
    final angles = values.map((value) => value * 2 * math.pi / 1440);
    final sinMean = angles.map(math.sin).reduce((a, b) => a + b) / values.length;
    final cosMean = angles.map(math.cos).reduce((a, b) => a + b) / values.length;
    if (sinMean.abs() < 1e-10 && cosMean.abs() < 1e-10) return double.nan;
    final angle = math.atan2(sinMean, cosMean);
    return ((angle * 1440 / (2 * math.pi)) % 1440 + 1440) % 1440;
  }

  static ScreenTimeComparison? compare(Iterable<ScreenTimeSleepSample> samples) {
    final valid = samples.where((sample) =>
      sample.exposureMinutes.isFinite && sample.exposureMinutes >= 0
    ).toList()..sort((a, b) => a.exposureMinutes.compareTo(b.exposureMinutes));
    if (valid.isEmpty) return null;

    final middle = valid.length ~/ 2;
    final median = valid.length.isOdd
        ? valid[middle].exposureMinutes
        : (valid[middle - 1].exposureMinutes + valid[middle].exposureMinutes) / 2;
    final lower = valid.where((sample) => sample.exposureMinutes <= median).toList();
    final upper = valid.where((sample) => sample.exposureMinutes > median).toList();

    ScreenTimeGroupSummary summarize(List<ScreenTimeSleepSample> group) {
      final metrics = <ScreenTimeSleepMetric, ScreenTimeMetricSummary>{};
      for (final metric in ScreenTimeSleepMetric.values) {
        final values = group.map((sample) => sample.valueFor(metric))
            .whereType<double>().where((value) => value.isFinite).toList();
        final average = values.isEmpty
            ? null
            : metric == ScreenTimeSleepMetric.sleepStartTime
                ? _circularMeanMinutes(values)
                : values.reduce((a, b) => a + b) / values.length;
        metrics[metric] = ScreenTimeMetricSummary(
          validSamples: values.length,
          average: average != null && average.isFinite ? average : null,
        );
      }
      return ScreenTimeGroupSummary(nights: group.length, metrics: Map.unmodifiable(metrics));
    }

    return ScreenTimeComparison(
      medianExposureMinutes: median,
      lowerExposure: lower.isEmpty ? median : lower.last.exposureMinutes,
      upperExposure: upper.isEmpty ? median : upper.first.exposureMinutes,
      lowerGroup: summarize(lower),
      upperGroup: summarize(upper),
    );
  }
}