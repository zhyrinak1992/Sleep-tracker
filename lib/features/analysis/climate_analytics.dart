import 'dart:math' as math;

/// Итог по реально полученным показаниям одного типа климатического датчика.
/// Пустая выборка возвращает null: отсутствие данных никогда не превращается в 0.
class ClimateMetricSummary {
  const ClimateMetricSummary({
    required this.metricType,
    required this.unit,
    required this.count,
    required this.minimum,
    required this.maximum,
    required this.average,
    required this.lastValue,
    required this.lastMeasuredAt,
    required this.firstMeasuredAt,
    required this.standardDeviation,
    required this.coveragePercent,
  });

  final String metricType;
  final String unit;
  final int count;
  final double minimum;
  final double maximum;
  final double average;
  final double lastValue;
  final DateTime lastMeasuredAt;
  final DateTime firstMeasuredAt;
  final double standardDeviation;
  /// null, если нет согласованного интервала опроса для расчёта покрытия.
  final double? coveragePercent;

  static ClimateMetricSummary? fromSamples(
    List<Map<String, Object?>> samples, {
    required String metricType,
    Duration? expectedInterval,
  }) {
    final valid = samples.where((row) =>
      row['metric_type'] == metricType &&
      row['value'] is num &&
      (row['value'] as num).toDouble().isFinite &&
      row['measured_at'] is String
    ).toList()
      ..sort((a, b) => DateTime.parse(a['measured_at']! as String)
        .compareTo(DateTime.parse(b['measured_at']! as String)));
    if (valid.isEmpty) return null;

    final values = valid.map((row) => (row['value'] as num).toDouble()).toList();
    final sum = values.fold<double>(0, (total, value) => total + value);
    final average = sum / values.length;
    final variance = values.fold<double>(0,
      (total, value) => total + math.pow(value - average, 2).toDouble()) / values.length;
    final first = DateTime.parse(valid.first['measured_at']! as String).toLocal();
    final last = DateTime.parse(valid.last['measured_at']! as String).toLocal();
    double? coverage;
    if (expectedInterval != null && expectedInterval.inSeconds > 0) {
      final span = last.difference(first).inSeconds;
      if (span == 0) {
        coverage = 0;
      } else {
        final expected = (span / expectedInterval.inSeconds).ceil() + 1;
        coverage = (values.length / expected * 100).clamp(0, 100).toDouble();
      }
    }
    return ClimateMetricSummary(
      metricType: metricType,
      unit: valid.last['unit'] as String? ?? '',
      count: values.length,
      minimum: values.reduce((a, b) => a < b ? a : b),
      maximum: values.reduce((a, b) => a > b ? a : b),
      average: average,
      lastValue: values.last,
      lastMeasuredAt: last,
      firstMeasuredAt: first,
      standardDeviation: math.sqrt(variance),
      coveragePercent: coverage,
    );
  }
}
