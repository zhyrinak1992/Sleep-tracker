import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_dynamics_analysis.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  group('SleepDynamicsAnalysis', () {
    test('creates contiguous current and previous 30-calendar-day windows', () {
      final ranges = SleepDynamicsAnalysis.rollingThirtyDayRanges(DateTime(2026, 11, 23, 14, 30));
      expect(ranges.currentStart, DateTime(2026, 10, 25));
      expect(ranges.currentEndExclusive, DateTime(2026, 11, 24));
      expect(ranges.previousStart, DateTime(2026, 9, 25));
      expect(ranges.previousEndExclusive, DateTime(2026, 10, 25));
      expect(ranges.currentEndExclusive.difference(ranges.currentStart).inDays, 30);
      expect(ranges.previousEndExclusive.difference(ranges.previousStart).inDays, 30);
    });

    test('calculates calendar period boundaries for week, month and year', () {
      final date = DateTime(2026, 11, 25);
      expect(
        SleepDynamicsAnalysis.periodStart(date, SleepDynamicsPeriod.week),
        DateTime(2026, 11, 23),
      );
      expect(
        SleepDynamicsAnalysis.periodStart(date, SleepDynamicsPeriod.month),
        DateTime(2026, 11, 1),
      );
      expect(
        SleepDynamicsAnalysis.periodStart(date, SleepDynamicsPeriod.year),
        DateTime(2026, 1, 1),
      );
      expect(
        SleepDynamicsAnalysis.nextPeriodStart(DateTime(2026, 12, 1), SleepDynamicsPeriod.month),
        DateTime(2027, 1, 1),
      );
    });

    test('builds equal rolling windows for 7, 30, 90 and 365 calendar days', () {
      final now = DateTime(2026, 11, 23, 17, 45);
      for (final days in [7, 30, 90, 365]) {
        final ranges = SleepDynamicsAnalysis.rollingRanges(now, days);
        expect(ranges.currentEndExclusive.difference(ranges.currentStart).inDays, days);
        expect(ranges.previousEndExclusive.difference(ranges.previousStart).inDays, days);
        expect(ranges.previousEndExclusive, ranges.currentStart);
        expect(ranges.currentEndExclusive, DateTime(2026, 11, 24));
      }
      expect(
        () => SleepDynamicsAnalysis.rollingRanges(now, 0),
        throwsArgumentError,
      );
    });

    test('maps chart buckets to exact calendar ranges including the short fifth week', () {
      final week = SleepDynamicsAnalysis.bucketRange(
        DateTime(2026, 11, 23), SleepDynamicsPeriod.week, 6);
      expect(week.start, DateTime(2026, 11, 29));
      expect(week.endExclusive, DateTime(2026, 11, 30));

      final month = SleepDynamicsAnalysis.bucketRange(
        DateTime(2026, 11, 1), SleepDynamicsPeriod.month, 4);
      expect(month.start, DateTime(2026, 11, 29));
      expect(month.endExclusive, DateTime(2026, 12, 1));

      final year = SleepDynamicsAnalysis.bucketRange(
        DateTime(2026, 1, 1), SleepDynamicsPeriod.year, 11);
      expect(year.start, DateTime(2026, 12, 1));
      expect(year.endExclusive, DateTime(2027, 1, 1));
      expect(
        () => SleepDynamicsAnalysis.bucketRange(
          DateTime(2026, 1, 1), SleepDynamicsPeriod.week, 7),
        throwsRangeError,
      );
    });


    test('keeps rolling windows on local calendar midnights across DST boundaries', () {
      // Run this test under a DST-observing local timezone (CI sets Europe/Berlin).
      final ranges = SleepDynamicsAnalysis.rollingRanges(DateTime(2026, 4, 2, 12), 7);
      expect(ranges.currentStart, DateTime(2026, 3, 27));
      expect(ranges.currentEndExclusive, DateTime(2026, 4, 3));
      expect(ranges.previousStart, DateTime(2026, 3, 20));
      expect(ranges.previousEndExclusive, DateTime(2026, 3, 27));
      for (final boundary in [
        ranges.currentStart,
        ranges.currentEndExclusive,
        ranges.previousStart,
        ranges.previousEndExclusive,
      ]) {
        expect(boundary.hour, 0);
        expect(boundary.minute, 0);
      }
    });

    test('keeps weekly chart bucket boundaries at local midnight across DST', () {
      final week = SleepDynamicsAnalysis.bucketRange(
        DateTime(2026, 3, 23), SleepDynamicsPeriod.week, 6);
      expect(week.start, DateTime(2026, 3, 29));
      expect(week.endExclusive, DateTime(2026, 3, 30));
      expect(week.start.hour, 0);
      expect(week.endExclusive.hour, 0);
    });

    test('uses only available samples for efficiency, awakenings and morning ratings', () {
      final session = SleepSession(
        id: 'night-1',
        startedAt: DateTime(2026, 11, 24, 23),
        endedAt: DateTime(2026, 11, 25, 7),
        source: 'health',
        actualSleepStartedAt: DateTime(2026, 11, 24, 23, 10),
        actualSleepEndedAt: DateTime(2026, 11, 25, 6, 10),
      );
      final result = SleepDynamicsAnalysis.summarize(
        sessions: [session],
        stagesBySession: {
          'night-1': [
            {
              'stage': 'core',
              'started_at': DateTime(2026, 11, 24, 23, 10).toIso8601String(),
              'ended_at': DateTime(2026, 11, 25, 6).toIso8601String(),
            },
            {
              'stage': 'awake',
              'started_at': DateTime(2026, 11, 25, 6).toIso8601String(),
              'ended_at': DateTime(2026, 11, 25, 6, 10).toIso8601String(),
            },
          ],
        },
        morningReports: {
          'night-1': {'sleep_quality': 4, 'wellbeing': 5},
        },
        start: DateTime(2026, 11, 23),
        endExclusive: DateTime(2026, 11, 30),
        period: SleepDynamicsPeriod.week,
      );

      expect(result.completedCount, 1);
      expect(result.durationSamples, 1);
      expect(result.averageSleepMinutes, 410);
      expect(result.scoreSamples, 1);
      expect(result.averageSleepScore, isNotNull);
      expect(result.efficiencySamples, 1);
      expect(result.averageEfficiency, closeTo(85.4, 0.2));
      expect(result.awakeningSamples, 1);
      expect(result.averageAwakenings, 1);
      expect(result.qualitySamples, 1);
      expect(result.averageQuality, 4);
      expect(result.wellbeingSamples, 1);
      expect(result.averageWellbeing, 5);
      expect(result.chartValues[1], 410);
      expect(result.chartScoreValues[1], isNotNull);
      expect(result.chartEfficiencyValues[1], closeTo(85.4, 0.2));
      expect(result.chartAwakeningValues[1], 1);
      expect(result.chartQualityValues[1], 4);
      expect(result.chartWellbeingValues[1], 5);
      expect(result.typicalBedtimeMinute, isNull);
      expect(result.typicalWakeMinute, isNull);
    });

    test('does not turn missing phase coverage into zero efficiency or zero awakenings', () {
      final session = SleepSession(
        id: 'night-no-stages',
        startedAt: DateTime(2026, 11, 24, 23),
        endedAt: DateTime(2026, 11, 25, 7),
      );
      final result = SleepDynamicsAnalysis.summarize(
        sessions: [session],
        stagesBySession: const {},
        morningReports: const {},
        start: DateTime(2026, 11, 23),
        endExclusive: DateTime(2026, 11, 30),
        period: SleepDynamicsPeriod.week,
      );
      expect(result.averageSleepMinutes, 480);
      expect(result.averageSleepScore, isNull);
      expect(result.scoreSamples, 0);
      expect(result.chartScoreValues[1], isNull);
      expect(result.averageEfficiency, isNull);
      expect(result.efficiencySamples, 0);
      expect(result.averageAwakenings, isNull);
      expect(result.awakeningSamples, 0);
      expect(result.averageQuality, isNull);
      expect(result.averageWellbeing, isNull);
    });

    test('regularity calculation treats times around midnight as close', () {
      final first = SleepSession(
        id: 'late-1',
        startedAt: DateTime(2026, 11, 24, 23),
        endedAt: DateTime(2026, 11, 25, 7),
        source: 'health',
        actualSleepStartedAt: DateTime(2026, 11, 24, 23, 55),
        actualSleepEndedAt: DateTime(2026, 11, 25, 6, 55),
      );
      final second = SleepSession(
        id: 'late-2',
        startedAt: DateTime(2026, 11, 25, 23),
        endedAt: DateTime(2026, 11, 26, 7),
        source: 'health',
        actualSleepStartedAt: DateTime(2026, 11, 26, 0, 5),
        actualSleepEndedAt: DateTime(2026, 11, 26, 7, 5),
      );
      final result = SleepDynamicsAnalysis.summarize(
        sessions: [first, second],
        stagesBySession: const {},
        morningReports: const {},
        start: DateTime(2026, 11, 24),
        endExclusive: DateTime(2026, 11, 27),
        period: SleepDynamicsPeriod.week,
      );
      expect(result.regularitySamples, 2);
      expect(result.bedtimeDeviationMinutes, 5);
      expect(result.wakeTimeDeviationMinutes, 5);
      expect(result.typicalBedtimeMinute, 23 * 60 + 55);
      expect(result.typicalWakeMinute, 6 * 60 + 55);
    });
  });
}
