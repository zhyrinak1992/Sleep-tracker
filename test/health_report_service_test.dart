import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/health/health_report_service.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  group('HealthReportService', () {
    final sessions = {
      'night-a': SleepSession(
        id: 'night-a',
        startedAt: DateTime(2026, 10, 1, 22),
        endedAt: DateTime(2026, 10, 2, 6),
      ),
      'night-b': SleepSession(
        id: 'night-b',
        startedAt: DateTime(2026, 10, 2, 22),
        endedAt: DateTime(2026, 10, 3, 6),
      ),
    };

    test('averages samples within each night before averaging nights', () {
      final summaries = HealthReportService.summarizeMetrics(
        sessionsById: sessions,
        rows: [
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 60, 'source': 'Apple Watch'},
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 80, 'source': 'Apple Watch'},
          {'session_id': 'night-b', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 90, 'source': 'Apple Watch'},
        ],
      );

      expect(summaries, hasLength(1));
      final pulse = summaries.single;
      expect(pulse['average'], 80);
      expect(pulse['median'], 80);
      expect(pulse['minimum'], 70);
      expect(pulse['maximum'], 90);
      expect(pulse['nightCount'], 2);
      expect(pulse['measurementCount'], 3);
      expect(pulse['sources'], ['Apple Watch']);
    });

    test('keeps different units separate and ignores invalid or unrelated rows', () {
      final summaries = HealthReportService.summarizeMetrics(
        sessionsById: sessions,
        rows: [
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 60},
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'bpm', 'value': 62},
          {'session_id': 'missing-night', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 70},
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': double.nan},
        ],
      );

      expect(summaries, hasLength(2));
      expect(summaries.map((item) => item['unit']).toSet(), {'bpm', 'уд/мин'});
      expect(summaries.every((item) => item['nightCount'] == 1), isTrue);
    });

    test('decodes saved report and formats weekly monthly and annual titles', () {
      final report = HealthReportSnapshot.decode('''
        {
          "id": "month_2026-10-01",
          "kind": "month",
          "start": "2026-10-01T00:00:00.000",
          "endExclusive": "2026-11-01T00:00:00.000",
          "nights": 5,
          "metrics": []
        }
      ''');
      expect(report.nights, 5);
      expect(report.title, 'Физиологический отчёт — октября 2026');
    });


    test('keeps weekly and monthly trend boundaries at local midnight across DST', () {
      final nextWeek = HealthReportService.nextPeriodStartForTesting(
        DateTime(2026, 3, 23),
        HealthReportKind.week,
      );
      expect(nextWeek, DateTime(2026, 3, 30));
      expect(nextWeek.hour, 0);

      final previousWeek = HealthReportService.previousPeriodStartForTesting(
        DateTime(2026, 3, 30),
        HealthReportKind.week,
      );
      expect(previousWeek, DateTime(2026, 3, 23));
      expect(previousWeek.hour, 0);

      final week = HealthReportService.trendIntervalsForTesting(
        HealthReportKind.week,
        DateTime(2026, 3, 23),
        DateTime(2026, 3, 30),
      );
      expect(week.last.$1, DateTime(2026, 3, 29));
      expect(week.last.$2, DateTime(2026, 3, 30));
      expect(week.every((interval) => interval.$1.hour == 0 && interval.$2.hour == 0), isTrue);

      final month = HealthReportService.trendIntervalsForTesting(
        HealthReportKind.month,
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
      );
      expect(month.map((interval) => interval.$1.day).toList(), [1, 8, 15, 22, 29]);
      expect(month.last.$2, DateTime(2026, 4, 1));
      expect(month.every((interval) => interval.$1.hour == 0 && interval.$2.hour == 0), isTrue);
    });

    test('does not create metric summaries for absent data', () {
      expect(
        HealthReportService.summarizeMetrics(rows: [], sessionsById: sessions),
        isEmpty,
      );
    });
  });
}
