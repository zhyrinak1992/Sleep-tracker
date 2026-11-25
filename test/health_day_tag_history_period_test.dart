import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/health/health_day_tag_history_period.dart';

void main() {
  group('HealthDayTagHistoryPeriodCalculator', () {
    final now = DateTime(2026, 11, 25, 18, 30);

    test('week is the last seven local calendar days including today', () {
      final range = HealthDayTagHistoryPeriodCalculator.range(
        period: HealthDayTagHistoryPeriod.week,
        now: now,
      );
      final buckets = HealthDayTagHistoryPeriodCalculator.buckets(
        period: HealthDayTagHistoryPeriod.week,
        range: range,
      );

      expect(range.start, DateTime(2026, 11, 19));
      expect(range.endExclusive, DateTime(2026, 11, 26));
      expect(buckets, hasLength(7));
      expect(buckets.first.label, '19.11');
      expect(buckets.last.label, '25.11');
    });

    test('month uses the current partial calendar month', () {
      final range = HealthDayTagHistoryPeriodCalculator.range(
        period: HealthDayTagHistoryPeriod.month,
        now: now,
      );
      final buckets = HealthDayTagHistoryPeriodCalculator.buckets(
        period: HealthDayTagHistoryPeriod.month,
        range: range,
      );

      expect(range.start, DateTime(2026, 11, 1));
      expect(range.endExclusive, DateTime(2026, 11, 26));
      expect(buckets, hasLength(25));
      expect(buckets.first.start, DateTime(2026, 11, 1));
      expect(buckets.last.start, DateTime(2026, 11, 25));
    });

    test('half-year contains six calendar-month buckets', () {
      final range = HealthDayTagHistoryPeriodCalculator.range(
        period: HealthDayTagHistoryPeriod.halfYear,
        now: now,
      );
      final buckets = HealthDayTagHistoryPeriodCalculator.buckets(
        period: HealthDayTagHistoryPeriod.halfYear,
        range: range,
      );

      expect(range.start, DateTime(2026, 6, 1));
      expect(buckets, hasLength(6));
      expect(buckets.first.label, '06.2026');
      expect(buckets.last.label, '11.2026');
    });

    test('all-time starts on the earliest saved date and groups by month', () {
      final range = HealthDayTagHistoryPeriodCalculator.range(
        period: HealthDayTagHistoryPeriod.allTime,
        now: now,
        earliestEntry: DateTime(2025, 3, 17, 22),
      );
      final buckets = HealthDayTagHistoryPeriodCalculator.buckets(
        period: HealthDayTagHistoryPeriod.allTime,
        range: range,
      );

      expect(range.start, DateTime(2025, 3, 17));
      expect(range.endExclusive, DateTime(2026, 11, 26));
      expect(buckets.first.label, '03.2025');
      expect(buckets.last.label, '11.2026');
      expect(buckets, hasLength(21));
    });

    test('all-time without saved entries does not invent an earlier date', () {
      final range = HealthDayTagHistoryPeriodCalculator.range(
        period: HealthDayTagHistoryPeriod.allTime,
        now: now,
      );

      expect(range.start, DateTime(2026, 11, 25));
      expect(range.endExclusive, DateTime(2026, 11, 26));
    });
  });
}
