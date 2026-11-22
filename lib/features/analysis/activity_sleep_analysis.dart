class ActivitySleepSample {
  const ActivitySleepSample({required this.steps, required this.sleepMinutes});
  final double steps;
  final double sleepMinutes;
}

class ActivitySleepGroupSummary {
  const ActivitySleepGroupSummary({required this.nights, required this.averageSleepMinutes});
  final int nights;
  final double averageSleepMinutes;
}

class ActivitySleepComparison {
  const ActivitySleepComparison({required this.belowMedian, required this.atOrAboveMedian});

  final ActivitySleepGroupSummary belowMedian;
  final ActivitySleepGroupSummary atOrAboveMedian;

  static ActivitySleepComparison? fromSamples(Iterable<ActivitySleepSample> samples) {
    final ordered = samples.toList()..sort((a, b) => a.steps.compareTo(b.steps));
    if (ordered.length < 4) return null;
    final midpoint = ordered.length ~/ 2;
    ActivitySleepGroupSummary summarize(List<ActivitySleepSample> group) =>
        ActivitySleepGroupSummary(
          nights: group.length,
          averageSleepMinutes: group.map((sample) => sample.sleepMinutes).reduce((a, b) => a + b) / group.length,
        );
    return ActivitySleepComparison(
      belowMedian: summarize(ordered.take(midpoint).toList()),
      atOrAboveMedian: summarize(ordered.skip(midpoint).toList()),
    );
  }
}
