import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_score.dart';

void main() {
  group('SleepScoreCalculator', () {
    test('uses approved 40/30/20/10 weights and returns transparent breakdown', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 450,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: 90,
        awakeningCount: 1,
        awakeningsAvailable: true,
        subjectiveQuality: 4,
      );
      expect(result.score, closeTo(90, 0.001));
      expect(result.availableWeight, 100);
      expect(result.availableComponents, 4);
      expect(result.components.map((x) => x.weight).toList(), [40, 30, 20, 10]);
      expect(result.toMap()['methodVersion'], 1);
    });

    test('redistributes only available weights when components are missing', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 450,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: null,
        awakeningCount: null,
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
        awakeningsAvailable: false,
        subjectiveQuality: 5,
      );
      expect(lowWeight.score, isNull);
      expect(lowWeight.availableWeight, 40);
    });

    test('duration component falls linearly outside the personal range', () {
      final result = SleepScoreCalculator.calculate(
        sleepDurationMinutes: 330,
        personalLowerMinutes: 420,
        personalUpperMinutes: 480,
        sleepEfficiencyPercent: 90,
        awakeningCount: 0,
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
        awakeningsAvailable: true,
        subjectiveQuality: 8,
      );
      expect(result.score, isNull);
      expect(result.components.every((x) => x.score == null), isTrue);
    });
  });
}
