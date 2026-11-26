enum ScreenTimeSleepMetric {
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
    this.sleepDurationMinutes,
    this.sleepEfficiencyPercent,
    this.awakeningCount,
    this.morningRating,
    this.sleepQuality,
    this.wellbeing,
  });

  final double exposureMinutes;
  final double? sleepDurationMinutes;
  final double? sleepEfficiencyPercent;
  final double? awakeningCount;
  final double? morningRating;
  final double? sleepQuality;
  final double? wellbeing;

  double? valueFor(ScreenTimeSleepMetric metric) => switch (metric) {
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
    return upper.average! - lower.average!;
  }
}

class ScreenTimeSleepAnalysis {
  static const minimumValidSamplesPerGroup = 4;

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
        metrics[metric] = ScreenTimeMetricSummary(
          validSamples: values.length,
          average: values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length,
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