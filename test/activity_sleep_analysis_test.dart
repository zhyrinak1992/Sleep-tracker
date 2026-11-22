import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/activity_sleep_analysis.dart';

void main() {
  test('compares sleep duration below and at-or-above the selected-period step median', () {
    final result = ActivitySleepComparison.fromSamples([
      const ActivitySleepSample(steps: 1000, sleepMinutes: 420),
      const ActivitySleepSample(steps: 2000, sleepMinutes: 450),
      const ActivitySleepSample(steps: 3000, sleepMinutes: 480),
      const ActivitySleepSample(steps: 4000, sleepMinutes: 510),
      const ActivitySleepSample(steps: 5000, sleepMinutes: 540),
    ]);

    expect(result, isNotNull);
    expect(result!.belowMedian.nights, 2);
    expect(result.belowMedian.averageSleepMinutes, 435);
    expect(result.atOrAboveMedian.nights, 3);
    expect(result.atOrAboveMedian.averageSleepMinutes, 510);
  });

  test('does not produce a comparison with fewer than four nights', () {
    expect(ActivitySleepComparison.fromSamples([
      const ActivitySleepSample(steps: 1000, sleepMinutes: 420),
      const ActivitySleepSample(steps: 2000, sleepMinutes: 450),
      const ActivitySleepSample(steps: 3000, sleepMinutes: 480),
    ]), isNull);
  });
}
