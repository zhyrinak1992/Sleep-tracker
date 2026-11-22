import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/screen_time_sleep_analysis.dart';

void main() {
  test('compares sleep duration, screen duration and last-use gap by median screen time', () {
    final result = ScreenTimeSleepComparison.fromSamples([
      const ScreenTimeSleepSample(screenMinutes: 10, lastUseGapMinutes: 60, sleepMinutes: 420),
      const ScreenTimeSleepSample(screenMinutes: 20, lastUseGapMinutes: 45, sleepMinutes: 430),
      const ScreenTimeSleepSample(screenMinutes: 40, lastUseGapMinutes: 20, sleepMinutes: 450),
      const ScreenTimeSleepSample(screenMinutes: 60, lastUseGapMinutes: 10, sleepMinutes: 480),
    ]);
    expect(result, isNotNull);
    expect(result!.belowMedian.nights, 2);
    expect(result.belowMedian.averageSleepMinutes, 425);
    expect(result.atOrAboveMedian.nights, 2);
    expect(result.atOrAboveMedian.averageSleepMinutes, 465);
    expect(result.atOrAboveMedian.averageLastUseGapMinutes, 15);
  });

  test('requires four valid samples and excludes invalid values', () {
    expect(ScreenTimeSleepComparison.fromSamples([
      const ScreenTimeSleepSample(screenMinutes: 10, lastUseGapMinutes: 10, sleepMinutes: 420),
      const ScreenTimeSleepSample(screenMinutes: 20, lastUseGapMinutes: 10, sleepMinutes: 430),
      const ScreenTimeSleepSample(screenMinutes: 40, lastUseGapMinutes: 10, sleepMinutes: 450),
      const ScreenTimeSleepSample(screenMinutes: 500, lastUseGapMinutes: 10, sleepMinutes: 480),
    ]), isNull);
  });
}
