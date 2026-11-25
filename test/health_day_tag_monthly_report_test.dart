import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/health/health_day_tag_monthly_report.dart';

void main() {
  group('HealthDayTagMonthlyReportService', () {
    test('builds monthly counts and compares shares with the previous month', () {
      final report = HealthDayTagMonthlyReportService.buildReport(
        monthKey: '2026-11',
        generatedAt: DateTime(2026, 12, 1),
        entries: {
          DateTime(2026, 10, 1): ['Стресс', 'Кофеин'],
          DateTime(2026, 10, 2): ['Стресс'],
          DateTime(2026, 10, 3): [],
          DateTime(2026, 11, 1): ['Стресс'],
          DateTime(2026, 11, 2): ['Кофеин'],
          DateTime(2026, 11, 3): [],
        },
      );

      expect(report.monthKey, '2026-11');
      expect(report.recordedDays, 3);
      expect(report.daysInMonth, 30);
      expect(report.previousRecordedDays, 3);
      expect(report.previousDaysInMonth, 31);
      final stress = report.tags.singleWhere((entry) => entry.tag == 'Стресс');
      expect(stress.days, 1);
      expect(stress.previousDays, 2);
      expect(stress.share, closeTo(100 / 3, 0.0001));
      expect(stress.previousShare, closeTo(200 / 3, 0.0001));
      expect(stress.differencePercentagePoints, closeTo(-100 / 3, 0.0001));
    });

    test('does not invent percentages when a month has no recorded days', () {
      final report = HealthDayTagMonthlyReportService.buildReport(
        monthKey: '2026-11',
        generatedAt: DateTime(2026, 12, 1),
        entries: {
          DateTime(2026, 10, 1): ['Стресс'],
        },
      );

      expect(report.recordedDays, 0);
      expect(report.tags.single.share, isNull);
      expect(report.tags.single.previousShare, 100);
      expect(report.tags.single.differencePercentagePoints, isNull);
    });

    test('keeps unavailable progress distinct from a real zero share', () {
      expect(HealthDayTagMonthlyReportEntry.progressFraction(null), isNull);
      expect(HealthDayTagMonthlyReportEntry.progressFraction(0), 0);
      expect(HealthDayTagMonthlyReportEntry.progressFraction(50), 0.5);
      expect(HealthDayTagMonthlyReportEntry.progressFraction(125), 1);
    });

    test('serializes and restores report snapshots', () {
      final report = HealthDayTagMonthlyReportService.buildReport(
        monthKey: '2026-11',
        generatedAt: DateTime(2026, 12, 1),
        entries: {
          DateTime(2026, 11, 1): ['Путешествие'],
        },
      );

      final restored = HealthDayTagMonthlyReport.fromJson(report.toJson());

      expect(restored.monthKey, report.monthKey);
      expect(restored.recordedDays, report.recordedDays);
      expect(restored.tags.single.tag, 'Путешествие');
      expect(restored.tags.single.share, 100);
    });
  });
}
