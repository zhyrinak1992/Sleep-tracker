import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/home/comparison_statistics.dart';

void main() {
  group('ComparisonStatistics.mannWhitneyTwoSidedPValue', () {
    test('uses an exact two-sided probability for small fully separated groups', () {
      final p = ComparisonStatistics.mannWhitneyTwoSidedPValue(
        [5, 5, 5, 5],
        [3, 3, 3, 3],
      );
      expect(p, closeTo(2 / 70, 1e-9));
      expect(p, lessThan(0.05));
    });

    test('does not call identical distributions statistically different', () {
      final p = ComparisonStatistics.mannWhitneyTwoSidedPValue(
        [3, 3, 4, 4],
        [3, 3, 4, 4],
      );
      expect(p, 1);
    });

    test('uses a tie-corrected large-sample approximation', () {
      final p = ComparisonStatistics.mannWhitneyTwoSidedPValue(
        List<double>.generate(15, (i) => i.toDouble()),
        List<double>.generate(15, (i) => (i + 20).toDouble()),
      );
      expect(p, isNotNull);
      expect(p!, lessThan(0.001));
      expect(p, greaterThanOrEqualTo(0));
    });

    test('returns null when either group is too small', () {
      expect(
        ComparisonStatistics.mannWhitneyTwoSidedPValue([1], [2, 3, 4]),
        isNull,
      );
    });
  });
}
