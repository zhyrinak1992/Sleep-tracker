import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/periodic_report_export.dart';
import 'package:sleep_tracker/data/pdf_report_service.dart';

void main() {
  test('PDF monthly night count handles new, legacy and detail-list snapshots', () {
    expect(PdfReportService.monthNightCount({
      'nightCount': 3,
      'nights': [{'id': 'a'}, {'id': 'b'}],
    }), 3);
    expect(PdfReportService.monthNightCount({
      'nights': [{'id': 'a'}, {'id': 'b'}],
    }), 2);
    expect(PdfReportService.monthNightCount({'nights': 5}), 5);
    expect(PdfReportService.monthNightCount(const {}), 0);
  });

  test('exports summary and report trends as Excel-compatible semicolon CSV', () {
    final csv = PeriodicReportExport.toCsv({
      'kind': 'quarter',
      'start': '2026-04-01T00:00:00.000',
      'endExclusive': '2026-07-01T00:00:00.000',
      'nights': 12,
      'averageSleepMinutes': 420,
      'totalSleepMinutes': 5040,
      'score': {'average': 82.5, 'samples': 10},
      'trendPoints': [
        {
          'label': 'Апрель',
          'nights': [{'id': '1'}, {'id': '2'}],
          'averageSleepMinutes': 410,
          'score': {'average': 80},
        },
      ],
    });

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('Квартал'));
    expect(csv, contains('Средняя продолжительность сна, мин;420'));
    expect(csv, contains('Апрель;2;410;80'));
  });

  test('quotes fields containing separators, quotes and line breaks', () {
    final csv = PeriodicReportExport.toCsv({
      'kind': 'month',
      'tagPatterns': {
        'current': [
          {
            'label': 'кофе; поздно',
            'tagKey': 'coffee',
            'metrics': {
              'duration': {
                'withTagAverage': 400,
                'withTagSamples': 5,
                'withoutTagAverage': 420,
                'withoutTagSamples': 6,
                'difference': -20,
              },
            },
          },
        ],
      },
    });

    expect(csv, contains('"кофе; поздно"'));
  });
}
