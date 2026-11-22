import 'dart:math' as math;

/// Aggregates real HealthKit samples for one night without mixing units
/// or manufacturing values for missing intervals.
class SleepMetricSummary {
  const SleepMetricSummary({
    required this.metricType,
    required this.unit,
    required this.count,
    required this.minimum,
    required this.maximum,
    required this.average,
    required this.firstMeasuredAt,
    required this.lastMeasuredAt,
  });

  final String metricType;
  final String unit;
  final int count;
  final double minimum;
  final double maximum;
  final double average;
  final DateTime firstMeasuredAt;
  final DateTime lastMeasuredAt;

  static List<SleepMetricSummary> fromSamples(
    List<Map<String, Object?>> samples,
  ) {
    final groups = <(String, String), List<(double, DateTime)>>{};
    for (final row in samples) {
      final type = row['metric_type'];
      final unit = row['unit'];
      final rawValue = row['value'];
      final rawTime = row['measured_at'];
      if (type is! String || type.trim().isEmpty ||
          unit is! String || rawValue is! num ||
          !rawValue.toDouble().isFinite || rawTime is! String) {
        continue;
      }
      final measuredAt = DateTime.tryParse(rawTime)?.toLocal();
      if (measuredAt == null) continue;
      groups.putIfAbsent((type, unit), () => []).add((rawValue.toDouble(), measuredAt));
    }

    final summaries = <SleepMetricSummary>[];
    for (final entry in groups.entries) {
      final values = entry.value..sort((a, b) => a.$2.compareTo(b.$2));
      final numbers = values.map((sample) => sample.$1).toList();
      summaries.add(SleepMetricSummary(
        metricType: entry.key.$1,
        unit: entry.key.$2,
        count: values.length,
        minimum: numbers.reduce(math.min),
        maximum: numbers.reduce(math.max),
        average: numbers.reduce((a, b) => a + b) / numbers.length,
        firstMeasuredAt: values.first.$2,
        lastMeasuredAt: values.last.$2,
      ));
    }
    summaries.sort((a, b) => a.metricType.compareTo(b.metricType));
    return List.unmodifiable(summaries);
  }
}
