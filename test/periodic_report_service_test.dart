import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/periodic_report_service.dart';

void main() {
  group('PeriodicReportSnapshot', () {
    test('decodes a saved weekly report and exposes its period values', () {
      final report = PeriodicReportSnapshot.decode('''
        {
          "schemaVersion": 2,
          "id": "week_2026-11-16",
          "kind": "week",
          "start": "2026-11-16T00:00:00.000",
          "endExclusive": "2026-11-23T00:00:00.000",
          "nights": 5,
          "averageSleepMinutes": 431.5,
          "totalSleepMinutes": 2157,
          "averageTimeInBedMinutes": 472.0,
          "averageEfficiency": 88.2,
          "averageAwakenings": 2.0,
          "averageQuality": 4.0,
          "averageWellbeing": 3.8
        }
      ''');
      expect(report.id, 'week_2026-11-16');
      expect(report.kind, 'week');
      expect(report.nights, 5);
      expect(report.averageSleepMinutes, 431.5);
      expect(report.totalSleepMinutes, 2157);
      expect(report.averageTimeInBedMinutes, 472.0);
      expect(report.averageEfficiency, 88.2);
      expect(report.averageAwakenings, 2.0);
      expect(report.averageQuality, 4.0);
      expect(report.averageWellbeing, 3.8);
      expect(report.title, contains('Неделя'));
    });

    test('keeps missing measurements unavailable rather than converting them to zero', () {
      final report = PeriodicReportSnapshot.decode('''
        {
          "id": "month_2026-10-01",
          "kind": "month",
          "start": "2026-10-01T00:00:00.000",
          "endExclusive": "2026-11-01T00:00:00.000",
          "nights": 2
        }
      ''');
      expect(report.averageSleepMinutes, isNull);
      expect(report.totalSleepMinutes, isNull);
      expect(report.averageTimeInBedMinutes, isNull);
      expect(report.averageEfficiency, isNull);
      expect(report.averageAwakenings, isNull);
      expect(report.averageQuality, isNull);
      expect(report.averageWellbeing, isNull);
    });

    test('rejects malformed snapshot JSON', () {
      expect(() => PeriodicReportSnapshot.decode('[]'), throwsFormatException);
    });
  });
}
