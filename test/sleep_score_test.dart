import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_score.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  group('SleepScoreCalculator', () {
    test('uses approved 40/30/20/10 weights and returns transparent breakdown', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 450,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: 90,
        awakeningCount: 1,
        awakeningDurationMinutes: 20,
        awakeningsAvailable: true,
        subjectiveQuality: 4,
      );
      expect(result.score, closeTo(93.8333333333, 0.001));
      expect(result.availableWeight, 100);
      expect(result.availableComponents, 4);
      expect(result.components.map((x) => x.weight).toList(), [40, 30, 20, 10]);
      expect(result.toMap()['methodVersion'], 2);
    });

    test('redistributes only available weights when components are missing', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 450,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: null,
        awakeningCount: null,
        awakeningDurationMinutes: null,
        awakeningsAvailable: false,
        subjectiveQuality: 5,
      );
      expect(result.score, 100);
      expect(result.availableWeight, 50);
      expect(result.availableComponents, 2);
    });

    test('does not show a score with fewer than two components or less than 50 weight', () {
      final oneComponent = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 450,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: null,
        awakeningCount: null,
        awakeningDurationMinutes: null,
        awakeningsAvailable: false,
        subjectiveQuality: null,
      );
      expect(oneComponent.score, isNull);

      final lowWeight = SleepScoreCalculator.calculate(
        sleepDurationMinutes: null,
        personalLowerMinutes: null,
        personalUpperMinutes: null,
        sleepEfficiencyPercent: 90,
        awakeningCount: null,
        awakeningDurationMinutes: null,
        awakeningsAvailable: false,
        subjectiveQuality: 5,
      );
      expect(lowWeight.score, isNull);
      expect(lowWeight.availableWeight, 40);
    });

    test('awakening component includes both count and total awake minutes', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: null,
        personalLowerMinutes: null,
        personalUpperMinutes: null,
        sleepEfficiencyPercent: null,
        awakeningCount: 2,
        awakeningDurationMinutes: 30,
        awakeningsAvailable: true,
        subjectiveQuality: 5,
      );
      // Count: 60; awake duration: 75; component average: 67.5.
      expect(result.components[2].score, 67.5);
    });

    test('duration component falls linearly outside the personal range', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 330,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: 90,
        awakeningCount: 0,
        awakeningDurationMinutes: 0,
        awakeningsAvailable: true,
        subjectiveQuality: 5,
      );
      expect(result.components.first.score, 50);
    });

    test('rejects invalid or missing inputs instead of inventing zeros', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 0,
        personalLowerMinutes: null,
        personalUpperMinutes: null,
        sleepEfficiencyPercent: 140,
        awakeningCount: -1,
        awakeningDurationMinutes: -1,
        awakeningsAvailable: true,
        subjectiveQuality: 8,
      );
      expect(result.score, isNull);
      expect(result.components.every((x) => x.score == null), isTrue);
    });

    test('recognizes Russian awake-stage labels in a complete night', () {
      final start = DateTime(2026, 11, 20, 22);
      final end = DateTime(2026, 11, 21, 6);
      final session = SleepSession(
        id: 'night-with-awake',
        startedAt: start,
        endedAt: end,
        actualSleepStartedAt: start,
        actualSleepEndedAt: end,
      );
      final stages = [
        {
          'stage': 'Основной',
          'started_at': start.toIso8601String(),
          'ended_at': DateTime(2026, 11, 21, 1).toIso8601String(),
        },
        {
          'stage': 'Бодрствование',
          'started_at': DateTime(2026, 11, 21, 1).toIso8601String(),
          'ended_at': DateTime(2026, 11, 21, 1, 15).toIso8601String(),
        },
        {
          'stage': 'Глубокий',
          'started_at': DateTime(2026, 11, 21, 1, 15).toIso8601String(),
          'ended_at': end.toIso8601String(),
        },
      ];
      final result = SleepScoreCalculator.calculateForSession(
        session: session,
        historySessions: const [],
        morningReports: const {
          'night-with-awake': {'sleep_quality': 4},
        },
        stagesBySession: {'night-with-awake': stages},
      );

      expect(result.components[2].score, isNotNull);
      expect(result.components[2].actualValue, contains('1 · 15'));
    });

    test('does not infer zero awakenings when no awake interval was supplied', () {
      final start = DateTime(2026, 11, 20, 22);
      final end = DateTime(2026, 11, 21, 6);
      final session = SleepSession(
        id: 'night-without-awake-sample',
        startedAt: start,
        endedAt: end,
        actualSleepStartedAt: start,
        actualSleepEndedAt: end,
      );
      final result = SleepScoreCalculator.calculateForSession(
        session: session,
        historySessions: const [],
        morningReports: const {
          'night-without-awake-sample': {'sleep_quality': 4},
        },
        stagesBySession: {
          'night-without-awake-sample': [
            {
              'stage': 'Основной',
              'started_at': start.toIso8601String(),
              'ended_at': end.toIso8601String(),
            },
          ],
        },
      );

      expect(result.components[2].score, isNull);
      expect(result.components[2].actualValue, 'Нет достоверных данных');
    });
  });
}
