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
      }.entries) {
        final withValues = withTag.map((s) => entry.value[s.id])
          .whereType<double>().where((v) => v.isFinite).toList();
        final withoutValues = withoutTag.map((s) => entry.value[s.id])
          .whereType<double>().where((v) => v.isFinite).toList();
        double? average(List<double> values) => values.isEmpty
          ? null : values.reduce((a, b) => a + b) / values.length;
        final withAverage = average(withValues);
        final withoutAverage = average(withoutValues);
        final sufficient = withValues.length >= minimumNightsPerGroup &&
          withoutValues.length >= minimumNightsPerGroup;
        metrics[entry.key] = <String, Object?>{
          'withTagAverage': withAverage,
          'withoutTagAverage': withoutAverage,
          'difference': sufficient && withAverage != null && withoutAverage != null
            ? withAverage - withoutAverage : null,
          'withTagSamples': withValues.length,
          'withoutTagSamples': withoutValues.length,
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
