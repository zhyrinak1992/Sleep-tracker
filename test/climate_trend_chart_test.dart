import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/climate_trend_chart.dart';

Map<String, Object?> _sample(String time, double value, {String metric = 'temperature'}) => {
  'metric_type': metric,
  'measured_at': time,
  'value': value,
};

void main() {
  group('climateTrendSegments', () {
    test('sorts real samples chronologically', () {
      final result = climateTrendSegments([
        _sample('2026-11-22T00:30:00Z', 19),
        _sample('2026-11-22T00:00:00Z', 18),
      ], metricType: 'temperature');

      expect(result, hasLength(1));
      expect(result.single.map((point) => point.value), [18, 19]);
    });

    test('does not connect points across long collection gaps', () {
      final result = climateTrendSegments([
        _sample('2026-11-22T00:00:00Z', 18),
        _sample('2026-11-22T00:15:00Z', 19),
        _sample('2026-11-22T03:00:00Z', 20),
      ], metricType: 'temperature');

      expect(result, hasLength(2));
      expect(result.first, hasLength(2));
      expect(result.last, hasLength(1));
    });

    test('ignores other metrics and malformed values', () {
      final result = climateTrendSegments([
        _sample('2026-11-22T00:00:00Z', 18),
        _sample('2026-11-22T00:15:00Z', 50, metric: 'humidity'),
        {'metric_type': 'temperature', 'measured_at': 'bad-date', 'value': 19},
        {'metric_type': 'temperature', 'measured_at': '2026-11-22T00:30:00Z', 'value': double.nan},
      ], metricType: 'temperature');

      expect(result, hasLength(1));
      expect(result.single, hasLength(1));
      expect(result.single.single.value, 18);
    });

    test('returns no segments when there are no valid measurements', () {
      expect(climateTrendSegments([], metricType: 'temperature'), isEmpty);
    });
  });
}
