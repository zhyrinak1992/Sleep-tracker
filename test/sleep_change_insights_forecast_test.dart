import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_change_insights.dart';
import 'package:sleep_tracker/features/analysis/sleep_dynamics_analysis.dart';
import 'package:sleep_tracker/features/analysis/sleep_forecast_analysis.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepDynamicsSummary summary({
  double? duration = 480,
  int durationSamples = 10,
  double? score = 75,
  int scoreSamples = 10,
  double? efficiency,
  int efficiencySamples = 0,
  double? awakenings,
  int awakeningSamples = 0,
  double? quality,
  int qualitySamples = 0,
  double? wellbeing,
  int wellbeingSamples = 0,
  double? bedtimeMad,
  double? wakeMad,
  int regularitySamples = 0,
  int? bedtime,
  int? wake,
}) => SleepDynamicsSummary(
  start: DateTime(2026, 10, 1),
  endExclusive: DateTime(2026, 10, 31),
  sessionsCount: durationSamples,
  completedCount: durationSamples,
  averageSleepMinutes: duration,
  durationSamples: durationSamples,
  averageSleepScore: score,
  scoreSamples: scoreSamples,
  averageEfficiency: efficiency,
  efficiencySamples: efficiencySamples,
  averageAwakenings: awakenings,
  awakeningSamples: awakeningSamples,
  averageQuality: quality,
  qualitySamples: qualitySamples,
  averageWellbeing: wellbeing,
  wellbeingSamples: wellbeingSamples,
  bedtimeDeviationMinutes: bedtimeMad,
  wakeTimeDeviationMinutes: wakeMad,
  regularitySamples: regularitySamples,
  typicalBedtimeMinute: bedtime,
  typicalWakeMinute: wake,
  chartValues: const [],
  chartScoreValues: const [],
  chartEfficiencyValues: const [],
  chartAwakeningValues: const [],
  chartQualityValues: const [],
  chartWellbeingValues: const [],
);

void main() {
  group('SleepChangeInsights', () {
    test('creates a traceable duration summary and selects it when clearly dominant', () {
      final previous = summary(duration: 420, score: 70);
      final current = summary(duration: 450, score: 70);
      final result = SleepChangeInsights.calculate(current: current, previous: previous);

      expect(result.items, hasLength(1));
      expect(result.mainChange?.kind, SleepChangeKind.duration);
      expect(result.mainChange?.delta, 30);
      expect(result.mainChange?.previousSamples, 10);
      expect(result.mainChange?.currentSamples, 10);
      expect(result.personalSummary, contains('увеличилась на 30 мин'));
      expect(result.personalSummary, contains('7 ч → 7 ч 30 мин'));
    });

    test('does not create conclusions from insufficient samples', () {
      final previous = summary(duration: 420, durationSamples: 4, scoreSamples: 4);
      final current = summary(duration: 500, durationSamples: 4, scoreSamples: 4);
      final result = SleepChangeInsights.calculate(current: current, previous: previous);

      expect(result.hasComparableData, isFalse);
      expect(result.items, isEmpty);
      expect(result.mainChange, isNull);
      expect(result.personalSummary, contains('недостаточно'));
    });

    test('does not select an arbitrary winner when two changes have equal normalized significance', () {
      final previous = summary(duration: 420, score: 70);
      final current = summary(duration: 440, score: 73);
      final result = SleepChangeInsights.calculate(current: current, previous: previous);

      expect(result.items, hasLength(2));
      expect(result.mainChange, isNull);
    });

    test('handles bedtime shifts around midnight using circular time arithmetic', () {
      final previous = summary(
        duration: null, durationSamples: 0, score: null, scoreSamples: 0,
        regularitySamples: 8, bedtime: 23 * 60 + 50, wake: 7 * 60,
      );
      final current = summary(
        duration: null, durationSamples: 0, score: null, scoreSamples: 0,
        regularitySamples: 8, bedtime: 10, wake: 7 * 60,
      );
      final result = SleepChangeInsights.calculate(current: current, previous: previous);

      expect(result.items, hasLength(1));
      expect(result.items.single.kind, SleepChangeKind.bedtimeShift);
      expect(result.items.single.delta, 20);
      expect(result.items.single.description, contains('20 мин позже'));
    });
  });

  group('SleepForecastAnalysis', () {
    test('uses personal sleep latency and calculates a gradual recovery scenario', () {
      final now = DateTime(2026, 11, 23, 12);
      final sessions = List.generate(7, (index) {
        final night = DateTime(2026, 11, 22 - index, 22);
        return SleepSession(
          id: 'night-$index',
          startedAt: night,
          endedAt: night.add(const Duration(hours: 7)),
          source: 'health',
          buttonStartedAt: night,
          actualSleepStartedAt: night.add(const Duration(minutes: 20)),
          actualSleepEndedAt: night.add(const Duration(hours: 7, minutes: 20)),
        );
      });
      final result = SleepForecastAnalysis.calculate(
        sessions: sessions,
        now: now,
        plannedWakeMinute: 7 * 60,
        plannedBedtimeMinute: 23 * 60,
        targetSleepMinutes: 480,
      );

      expect(result.personalLatencyAvailable, isTrue);
      expect(result.latencySamples, 7);
      expect(result.medianLatencyMinutes, 20);
      expect(result.availableWindowMinutes, 480);
      expect(result.estimatedSleepMinutes, 460);
      expect(result.recommendedBedtimeStartMinute, 22 * 60 + 40);
      expect(result.recommendedBedtimeEndMinute, 22 * 60 + 40);
      expect(result.accumulatedShortfallMinutes, 7 * 60);
      expect(result.recoveryNightsAtThirtyMinutes, 14);
    });

    test('falls back to neutral time arithmetic when personal latency sample is insufficient', () {
      final now = DateTime(2026, 11, 23, 12);
      final result = SleepForecastAnalysis.calculate(
        sessions: const [],
        now: now,
        plannedWakeMinute: 7 * 60,
        plannedBedtimeMinute: 23 * 60,
        targetSleepMinutes: 480,
      );

      expect(result.availableWindowMinutes, 480);
      expect(result.personalLatencyAvailable, isFalse);
      expect(result.estimatedSleepMinutes, isNull);
      expect(result.recommendedBedtimeStartMinute, isNull);
      expect(result.accumulatedShortfallMinutes, isNull);
    });

    test('handles cross-midnight and identical plan times explicitly', () {
      final now = DateTime(2026, 11, 23, 12);
      final overnight = SleepForecastAnalysis.calculate(
        sessions: const [], now: now,
        plannedWakeMinute: 6 * 60,
        plannedBedtimeMinute: 22 * 60,
        targetSleepMinutes: 480,
      );
      final same = SleepForecastAnalysis.calculate(
        sessions: const [], now: now,
        plannedWakeMinute: 7 *  60,
        plannedBedtimeMinute: 7 * 60,
        targetSleepMinutes: 480,
      );
      expect(overnight.availableWindowMinutes, 480);
      expect(same.availableWindowMinutes, 0);
    });
  });
}
