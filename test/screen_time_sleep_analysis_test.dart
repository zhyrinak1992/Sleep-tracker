import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/screen_time_sleep_analysis.dart';

void main() {
  test('splits screen-time observations by their data median', () {
    final samples = List.generate(8, (index) => ScreenTimeSleepSample(
      exposureMinutes: index * 10,
      sleepDurationMinutes: 400 + index * 10,
      sleepEfficiencyPercent: 80 + index.toDouble(),
      awakeningCount: index.toDouble(),
      morningRating: 2 + index / 10,
      sleepQuality: 2 + index / 10,
      wellbeing: 3 + index / 10,
    ));
    final result = ScreenTimeSleepAnalysis.compare(samples)!;
    expect(result.medianExposureMinutes, 35);
    expect(result.lowerGroup.nights, 4);
    expect(result.upperGroup.nights, 4);
    expect(result.hasSufficientGroups, isTrue);
    expect(result.differenceFor(ScreenTimeSleepMetric.sleepDuration), 40);
    expect(result.differenceFor(ScreenTimeSleepMetric.sleepEfficiency), 4);
  });

  test('does not compare groups when one side has fewer than four nights', () {
    final samples = List.generate(7, (index) => ScreenTimeSleepSample(
      exposureMinutes: index.toDouble(), sleepDurationMinutes: 400 + index.toDouble(),
    ));
    final result = ScreenTimeSleepAnalysis.compare(samples)!;
    expect(result.lowerGroup.nights, 4);
    expect(result.upperGroup.nights, 3);
    expect(result.hasSufficientGroups, isFalse);
    expect(result.differenceFor(ScreenTimeSleepMetric.sleepDuration), isNull);
  });

  test('equal exposure values do not create artificial high and low groups', () {
    final samples = List.generate(8, (_) => const ScreenTimeSleepSample(
      exposureMinutes: 30, sleepDurationMinutes: 420,
    ));
    final result = ScreenTimeSleepAnalysis.compare(samples)!;
    expect(result.lowerGroup.nights, 8);
    expect(result.upperGroup.nights, 0);
    expect(result.hasSufficientGroups, isFalse);
    expect(result.differenceFor(ScreenTimeSleepMetric.sleepDuration), isNull);
  });

  test('each sleep metric requires four valid values in both groups', () {
    final samples = List.generate(8, (index) => ScreenTimeSleepSample(
      exposureMinutes: index.toDouble(),
      sleepDurationMinutes: 400 + index.toDouble(),
      sleepEfficiencyPercent: index < 3 || index > 3 ? 80 : null,
    ));
    final result = ScreenTimeSleepAnalysis.compare(samples)!;
    expect(result.differenceFor(ScreenTimeSleepMetric.sleepDuration), isNotNull);
    expect(result.lowerGroup.metric(ScreenTimeSleepMetric.sleepEfficiency).validSamples, 3);
    expect(result.differenceFor(ScreenTimeSleepMetric.sleepEfficiency), isNull);
  });

  test('missing exposure values are not represented as zero', () {
    expect(ScreenTimeSleepAnalysis.compare(const []), isNull);
  });
}