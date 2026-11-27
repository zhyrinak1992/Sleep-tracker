import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/health/health_day_tag_period_comparison.dart';

void main() {
  group('HealthDayTagPeriodComparison', () {
    final entries = <DateTime, List<String>>{
      DateTime(2026, 10, 1): ['Стресс', 'Кофеин'],
      DateTime(2026, 10, 3): ['Стресс'],
      DateTime(2026, 10, 4): ['Путешествие'],
      DateTime(2026, 11, 1): ['Стресс'],
      DateTime(2026, 11, 2): ['Кофеин'],
    };

    test('compares tag share using only days with saved day entries', () {
      final october = HealthDayTagPeriodComparison.calculate(
        entries: entries,
        tag: 'Стресс',
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );
      final november = HealthDayTagPeriodComparison.calculate(
        entries: entries,
        tag: 'Стресс',
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      );

      expect(october.recordedDays, 3);
      expect(october.taggedDays, 2);
      expect(october.percentage, closeTo(200 / 3, 0.0001));
      expect(november.recordedDays, 2);
      expect(november.taggedDays, 1);
      expect(november.percentage, 50);
      expect(
        HealthDayTagPeriodComparison.differencePercentagePoints(
          first: october,
          second: november,
        ),
        closeTo(50 - 200 / 3, 0.0001),
      );
    });

    test('includes both calendar boundaries and normalizes time components', () {
      final stats = HealthDayTagPeriodComparison.calculate(
        entries: {
          DateTime(2026, 10, 1, 23, 59): ['Кофеин'],
          DateTime(2026, 10, 2): ['Кофеин'],
          DateTime(2026, 10, 3): ['Стресс'],
        },
        tag: 'Кофеин',
        start: DateTime(2026, 10, 1, 12),
        end: DateTime(2026, 10, 2, 1),
      );

      expect(stats.recordedDays, 2);
      expect(stats.taggedDays, 2);
      expect(stats.percentage, 100);
    });

    test('returns unavailable percentages when a period has no recorded days', () {
      final empty = HealthDayTagPeriodComparison.calculate(
        entries: entries,
        tag: 'Стресс',
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 31),
      );

      expect(empty.recordedDays, 0);
      expect(empty.taggedDays, 0);
      expect(empty.percentage, isNull);
      expect(
        HealthDayTagPeriodComparison.differencePercentagePoints(
          first: empty,
          second: HealthDayTagPeriodComparison.calculate(
            entries: entries,
            tag: 'Стресс',
            start: DateTime(2026, 10, 1),
            end: DateTime(2026, 10, 31),
          ),
        ),
        isNull,
      );
    });

    test('rejects reversed calendar ranges', () {
      expect(
        () => HealthDayTagPeriodComparison.calculate(
          entries: entries,
          tag: 'Стресс',
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 10, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
