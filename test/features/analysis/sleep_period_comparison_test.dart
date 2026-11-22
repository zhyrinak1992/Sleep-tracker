import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_period_comparison.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession session(String id, DateTime start, {DateTime? end, int? rating}) =>
    SleepSession(id: id, startedAt: start, endedAt: end, morningRating: rating);

void main() {
  group('SleepPeriodComparison', () {
    test('uses inclusive calendar dates and excludes the following day', () {
      final data = [
        session('a', DateTime(2026, 11, 1, 23), end: DateTime(2026, 11, 2, 6), rating: 4),
        session('b', DateTime(2026, 11, 2, 23), end: DateTime(2026, 11, 3, 5), rating: 3),
        session('c', DateTime(2026, 11, 3, 0), end: DateTime(2026, 11, 3, 7)),
      ];
      final result = SleepPeriodComparison.summarize(
        data, DateTime(2026, 11, 1), DateTime(2026, 11, 2));
      expect(result.sessions.map((item) => item.id), ['a', 'b']);
      expect(result.completed, 2);
      expect(result.rated, 2);
      expect(result.averageDurationMinutes, 390);
      expect(result.averageRating, 3.5);
    });

    test('does not count open or zero-length sessions in duration average', () {
      final data = [
        session('completed', DateTime(2026, 11, 1), end: DateTime(2026, 11, 1, 6)),
        session('open', DateTime(2026, 11, 1, 8), rating: 5),
        session('zero', DateTime(2026, 11, 1, 10), end: DateTime(2026, 11, 1, 10)),
      ];
      final result = SleepPeriodComparison.summarize(
        data, DateTime(2026, 11, 1), DateTime(2026, 11, 1));
      expect(result.sessions, hasLength(3));
      expect(result.completed, 1);
      expect(result.averageDurationMinutes, 360);
      expect(result.rated, 1);
      expect(result.averageRating, 5);
    });

    test('rejects reversed ranges', () {
      expect(
        () => SleepPeriodComparison.summarize(
          [], DateTime(2026, 11, 2), DateTime(2026, 11, 1)),
        throwsArgumentError,
      );
    });

    test('percentage change requires two real non-zero comparable values', () {
      expect(SleepPeriodComparison.percentageChange(120, 100), 20);
      expect(SleepPeriodComparison.percentageChange(80, 100), -20);
      expect(SleepPeriodComparison.percentageChange(null, 100), isNull);
      expect(SleepPeriodComparison.percentageChange(100, null), isNull);
      expect(SleepPeriodComparison.percentageChange(100, 0), isNull);
    });
  });
}
