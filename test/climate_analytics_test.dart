import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/climate_analytics.dart';

void main() {
  group('ClimateMetricSummary', () {
    test('calculates real sample statistics and last timestamp', () {
      final rows = [
        {'metric_type':'temperature','value':20.0,'unit':'°C','measured_at':'2026-11-22T22:00:00Z'},
        {'metric_type':'temperature','value':22.0,'unit':'°C','measured_at':'2026-11-22T23:00:00Z'},
        {'metric_type':'temperature','value':21.0,'unit':'°C','measured_at':'2026-11-23T00:00:00Z'},
      ];
      final result = ClimateMetricSummary.fromSamples(rows, metricType:'temperature',
        expectedInterval: const Duration(hours:1));
      expect(result, isNotNull);
      expect(result!.count, 3);
      expect(result.minimum, 20);
      expect(result.maximum, 22);
      expect(result.average, 21);
      expect(result.standardDeviation, closeTo(0.81649658, 0.000001));
      expect(result.lastValue, 21);
      expect(result.coveragePercent, 100);
    });

    test('returns null instead of inventing zero for missing measurements', () {
      expect(ClimateMetricSummary.fromSamples([], metricType:'humidity'), isNull);
    });

    test('ignores non-finite values and wrong metric types', () {
      final rows = [
        {'metric_type':'humidity','value':double.nan,'unit':'%','measured_at':'2026-11-22T22:00:00Z'},
        {'metric_type':'temperature','value':19.0,'unit':'°C','measured_at':'2026-11-22T22:00:00Z'},
      ];
      expect(ClimateMetricSummary.fromSamples(rows, metricType:'humidity'), isNull);
    });
  });
}
