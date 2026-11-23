import '../../models/sleep_session.dart';

/// Сравнивает ночи с отметкой и без неё, не подменяя отсутствующие измерения нулями.
class PeriodicTagPatternAnalyzer {
  static const minimumNightsPerGroup = 4;

  static List<Map<String, Object?>> analyze({
    required Iterable<SleepSession> sessions,
    required Map<String, Set<String>> tagsBySession,
    required Map<String, double> durationBySession,
    required Map<String, double> scoreBySession,
    required Map<String, double> awakeningsBySession,
    Map<String, Map<String, double>> additionalMetrics = const <String, Map<String, double>>{},
    Set<String> circularMetricKeys = const <String>{},
    required Map<String, String> tagLabels,
  }) {
    final completed = sessions.where((s) =>
      s.endedAt != null && s.endedAt!.isAfter(s.startedAt)).toList();
    final keys = <String>{};
    for (final session in completed) {
      keys.addAll(tagsBySession[session.id] ?? const <String>{});
    }
    final result = <Map<String, Object?>>[];
    for (final key in keys.toList()..sort()) {
      final withTag = completed.where((s) =>
        (tagsBySession[s.id] ?? const <String>{}).contains(key)).toList();
      final withoutTag = completed.where((s) =>
        !(tagsBySession[s.id] ?? const <String>{}).contains(key)).toList();
      final metrics = <String, Object?>{};
      for (final entry in <String, Map<String, double>>{
        'duration': durationBySession,
        'score': scoreBySession,
        'awakenings': awakeningsBySession,
        ...additionalMetrics,
      }.entries) {
        final withObservations = withTag
          .where((s) => entry.value[s.id] != null && entry.value[s.id]!.isFinite)
          .map((s) => <String, Object?>{
            'sessionId': s.id,
            'startedAt': s.startedAt.toIso8601String(),
            'value': entry.value[s.id],
          }).toList();
        final withoutObservations = withoutTag
          .where((s) => entry.value[s.id] != null && entry.value[s.id]!.isFinite)
          .map((s) => <String, Object?>{
            'sessionId': s.id,
            'startedAt': s.startedAt.toIso8601String(),
            'value': entry.value[s.id],
          }).toList();
        final withValues = withObservations.map((item) => item['value'] as double).toList();
        final withoutValues = withoutObservations.map((item) => item['value'] as double).toList();
        double? average(List<double> values) {
          if (values.isEmpty) return null;
          if (!circularMetricKeys.contains(entry.key)) {
            return values.reduce((a, b) => a + b) / values.length;
          }
          var best = values.first;
          var bestCost = double.infinity;
          for (final candidate in values) {
            final cost = values.fold<double>(0, (sum, value) {
              final raw = (value - candidate).abs() % 1440;
              return sum + (raw > 720 ? 1440 - raw : raw);
            });
            if (cost < bestCost) {
              best = candidate;
              bestCost = cost;
            }
          }
          return best;
        }
        final withAverage = average(withValues);
        final withoutAverage = average(withoutValues);
        final sufficient = withValues.length >= minimumNightsPerGroup &&
          withoutValues.length >= minimumNightsPerGroup;
        double circularDifference(double a, double b) {
          final normalized = ((a - b) % 1440 + 1440) % 1440;
          return normalized > 720 ? normalized - 1440 : normalized;
        }
        metrics[entry.key] = <String, Object?>{
          'withTagAverage': withAverage,
          'withoutTagAverage': withoutAverage,
          'difference': sufficient && withAverage != null && withoutAverage != null
            ? (circularMetricKeys.contains(entry.key)
                ? circularDifference(withAverage, withoutAverage)
                : withAverage - withoutAverage) : null,
          'withTagSamples': withValues.length,
          'withoutTagSamples': withoutValues.length,
          'withTagObservations': withObservations,
          'withoutTagObservations': withoutObservations,
          'isSufficient': sufficient,
        };
      }
      result.add(<String, Object?>{
        'tagKey': key,
        'label': tagLabels[key] ?? key,
        'withTagNights': withTag.length,
        'withoutTagNights': withoutTag.length,
        'metrics': metrics,
      });
    }
    return result;
  }
}
