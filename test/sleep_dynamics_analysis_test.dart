import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_dynamics_analysis.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  group('SleepDynamicsAnalysis', () {
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
      expect(result.efficiencySamples, 1);
      expect(result.averageEfficiency, closeTo(85.4, 0.2));
      expect(result.awakeningSamples, 1);
      expect(result.averageAwakenings, 1);
      expect(result.qualitySamples, 1);
      expect(result.averageQuality, 4);
      expect(result.wellbeingSamples, 1);
      expect(result.averageWellbeing, 5);
      expect(result.chartValues[1], 410);
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
    });
  });
}
