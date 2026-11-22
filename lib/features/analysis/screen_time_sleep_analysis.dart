class ScreenTimeSleepSample {
  const ScreenTimeSleepSample({
    required this.screenMinutes,
    required this.lastUseGapMinutes,
    required this.sleepMinutes,
  });

  final double screenMinutes;
  final double lastUseGapMinutes;
  final double sleepMinutes;
}

class ScreenTimeSleepGroupSummary {
  const ScreenTimeSleepGroupSummary({
    required this.nights,
    required this.averageScreenMinutes,
    required this.averageLastUseGapMinutes,
    required this.averageSleepMinutes,
  });

  final int nights;
  final double averageScreenMinutes;
  final double averageLastUseGapMinutes;
  final double averageSleepMinutes;
}

class ScreenTimeSleepComparison {
  const ScreenTimeSleepComparison({
    required this.belowMedian,
    required this.atOrAboveMedian,
  });

  final ScreenTimeSleepGroupSummary belowMedian;
  final ScreenTimeSleepGroupSummary atOrAboveMedian;

  static ScreenTimeSleepComparison? fromSamples(Iterable<ScreenTimeSleepSample> samples) {
    final valid = samples.where((sample) =>
      sample.screenMinutes.isFinite &&
      sample.screenMinutes >= 0 &&
      sample.screenMinutes <= 360 &&
      sample.lastUseGapMinutes.isFinite &&
      sample.lastUseGapMinutes >= 0 &&
      sample.lastUseGapMinutes <= 1440 &&
      sample.sleepMinutes.isFinite &&
      sample.sleepMinutes > 0
    ).toList()..sort((a, b) => a.screenMinutes.compareTo(b.screenMinutes));
    if (valid.length < 4) return null;

    final midpoint = valid.length ~/ 2;
    ScreenTimeSleepGroupSummary summarize(List<ScreenTimeSleepSample> group) =>
      ScreenTimeSleepGroupSummary(
        nights: group.length,
        averageScreenMinutes: group.map((x) => x.screenMinutes).reduce((a, b) => a + b) / group.length,
        averageLastUseGapMinutes: group.map((x) => x.lastUseGapMinutes).reduce((a, b) => a + b) / group.length,
        averageSleepMinutes: group.map((x) => x.sleepMinutes).reduce((a, b) => a + b) / group.length,
      );

    return ScreenTimeSleepComparison(
      belowMedian: summarize(valid.take(midpoint).toList()),
      atOrAboveMedian: summarize(valid.skip(midpoint).toList()),
    );
  }
}
