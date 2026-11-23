import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/pdf_report_service.dart';

void main() {
  group('PDF history calendar range', () {
    test('includes exactly the requested number of local calendar dates', () {
      final start = PdfReportService.historyRangeStart(
        now: DateTime(2026, 3, 30, 17, 45),
        days: 30,
      );
      expect(start, DateTime(2026, 3, 1));
      expect(start.hour, 0);
      expect(start.minute, 0);
    });

    test('does not shift the date range across the spring DST transition', () {
      final start = PdfReportService.historyRangeStart(
        now: DateTime(2026, 3, 30, 12),
        days: 3,
      );
      expect(start, DateTime(2026, 3, 28));
      expect(start.hour, 0);
    });

    test('uses the complete history sentinel for long exports', () {
      expect(
        PdfReportService.historyRangeStart(
          now: DateTime(2026, 11, 23),
          days: 3650,
        ),
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    test('rejects an empty or negative day count', () {
      expect(
        () => PdfReportService.historyRangeStart(
          now: DateTime(2026, 11, 23),
          days: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PdfReportService.historyRangeStart(
          now: DateTime(2026, 11, 23),
          days: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
