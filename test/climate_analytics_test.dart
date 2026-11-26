import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/climate_analytics.dart';

void main() {
  group('ClimateMetricSummary', () {
    test('calculates actual sample statistics, coverage and last timestamp', () {
      final rows = [
        {'metric_type': 'temperature', 'value': 20.0, 'unit': '°C', 'measured_at': '2026-11-22T22:00:00Z'},
        {'metric_type': 'temperature', 'value': 22.0, 'unit': '°C', 'measured_at': '2026-11-22T22:15:00Z'},
        {'metric_type': 'temperature', 'value': 21.0, 'unit': '°C', 'measured_at': '2026-11-22T22:30:00Z'},
        {'metric_type': 'humidity', 'value': 55.0, 'unit': '%', 'measured_at': '2026-11-22T22:30:00Z'},
      ];
      final result = ClimateMetricSummary.fromSamples(
        rows,
        metricType: 'temperature',
        expectedInterval: const Duration(minutes: 15),
      );
      expect(result, isNotNull);
      expect(result!.count, 3);
      expect(result.minimum, 20);
      expect(result.maximum, 22);
      expect(result.average, 21);
      expect(result.standardDeviation, closeTo(0.816496, 0.00001));
      expect(result.lastValue, 21);
      expect(result.unit, '°C');
      expect(result.lastMeasuredAt.toUtc(), DateTime.utc(2026, 11, 22, 22, 30));
      expect(result.coveragePercent, 100);
    });

    test('returns null instead of inventing zero for missing measurements', () {
      expect(ClimateMetricSummary.fromSamples([], metricType: 'humidity'), isNull);
      expect(
        ClimateMetricSummary.fromSamples(
          [
            {'metric_type': 'temperature', 'value': 20.0, 'unit': '°C', 'measured_at': '2026-11-22T22:00:00Z'},
          ],
          metricType: 'humidity',
        ),
        isNull,
      );
    });

    test('ignores non-finite values and unrelated metric types', () {
      final rows = [
        {'metric_type': 'humidity', 'value': double.nan, 'unit': '%', 'measured_at': '2026-11-22T22:00:00Z'},
        {'metric_type': 'temperature', 'value': 19.0, 'unit': '°C', 'measured_at': '2026-11-22T22:15:00Z'},
      ];
      final result = ClimateMetricSummary.fromSamples(rows, metricType: 'temperature');
      expect(result, isNotNull);
      expect(result!.count, 1);
      expect(result.minimum, 19);
      expect(result.maximum, 19);
      expect(result.average, 19);
    });
  });
}
