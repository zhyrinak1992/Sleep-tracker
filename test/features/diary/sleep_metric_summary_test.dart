import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/diary/sleep_metric_summary.dart';

void main() {
  test('summarizes samples by metric and unit in timestamp order', () {
    final result = SleepMetricSummary.fromSamples([
      {'metric_type': 'Пульс', 'value': 72, 'unit': 'уд/мин', 'measured_at': '2026-11-22T02:00:00Z'},
      {'metric_type': 'SpO2', 'value': 97, 'unit': '%', 'measured_at': '2026-11-22T01:00:00Z'},
      {'metric_type': 'Пульс', 'value': 64, 'unit': 'уд/мин', 'measured_at': '2026-11-22T01:00:00Z'},
      {'metric_type': 'Пульс', 'value': 80, 'unit': 'уд/мин', 'measured_at': '2026-11-22T03:00:00Z'},
      {'metric_type': 'Пульс', 'value': 1, 'unit': 'bpm', 'measured_at': '2026-11-22T04:00:00Z'},
      {'metric_type': 'Пульс', 'value': double.nan, 'unit': 'уд/мин', 'measured_at': '2026-11-22T05:00:00Z'},
      {'metric_type': 'Пульс', 'value': 99, 'unit': 'уд/мин', 'measured_at': 'not-a-date'},
      {'metric_type': 'Пульс', 'value': 'bad', 'unit': 'уд/мин', 'measured_at': '2026-11-22T06:00:00Z'},
    ]);

    expect(result, hasLength(3));
    final pulse = result.firstWhere((item) => item.metricType == 'Пульс' && item.unit == 'уд/мин');
    expect(pulse.count, 3);
    expect(pulse.minimum, 64);
    expect(pulse.maximum, 80);
    expect(pulse.average, closeTo(72, 0.001));
    expect(pulse.firstMeasuredAt, DateTime.parse('2026-11-22T01:00:00Z').toLocal());
    expect(pulse.lastMeasuredAt, DateTime.parse('2026-11-22T03:00:00Z').toLocal());
  });

  test('returns an empty summary for empty or invalid samples', () {
    expect(SleepMetricSummary.fromSamples([]), isEmpty);
    expect(SleepMetricSummary.fromSamples([
      {'metric_type': 'Пульс', 'value': double.infinity, 'unit': 'уд/мин', 'measured_at': '2026-11-22T01:00:00Z'},
    ]), isEmpty);
  });
}
