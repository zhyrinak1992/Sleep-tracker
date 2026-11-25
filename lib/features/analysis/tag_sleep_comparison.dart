import 'dart:convert';

import '../../models/sleep_session.dart';

enum TagSleepMetric { sleepDuration, sleepEfficiency, sleepLatency, morningRating, awakeningCount }

extension TagSleepMetricLabel on TagSleepMetric {
  String get label => switch (this) {
    TagSleepMetric.sleepDuration => 'Продолжительность сна',
    TagSleepMetric.sleepEfficiency => 'Эффективность сна',
    TagSleepMetric.sleepLatency => 'Задержка засыпания',
    TagSleepMetric.morningRating => 'Утренняя оценка',
    TagSleepMetric.awakeningCount => 'Зарегистрированные эпизоды бодрствования',
  };

  String get unit => switch (this) {
    TagSleepMetric.sleepDuration => 'мин',
    TagSleepMetric.sleepEfficiency => '%',
    TagSleepMetric.sleepLatency => 'мин',
    TagSleepMetric.morningRating => 'из 5',
    TagSleepMetric.awakeningCount => 'эпизодов',
  };
}

class TagSleepGroupSummary {
  const TagSleepGroupSummary({required this.nights, required this.average, this.sessionIds = const [], this.values = const []});
  final int nights;
  final double? average;
  final List<String> sessionIds;
  final List<double> values;
}

class TagSleepComparisonResult {
  const TagSleepComparisonResult({
    required this.withTag,
    required this.withoutTag,
    required this.difference,
    required this.metric,
    required this.isSufficient,
  });

  final TagSleepGroupSummary withTag;
  final TagSleepGroupSummary withoutTag;
  final double? difference;
  final TagSleepMetric metric;
  final bool isSufficient;
}

class TagSleepComparison {
  static const minimumNightsPerGroup = 4;

  static double? _actualSleepMinutes(SleepSession session) {
    final imported = session.source.startsWith('apple_health:');
    final start = session.actualSleepStartedAt ?? (imported ? session.startedAt : null);
    final end = session.actualSleepEndedAt ?? (imported ? session.endedAt : null);
    if (start == null || end == null || !end.isAfter(start)) return null;
    return end.difference(start).inMinutes.toDouble();
  }

  static bool _isValidMetricValue(TagSleepMetric metric, double value) =>
      switch (metric) {
        TagSleepMetric.sleepDuration => value > 0,
        TagSleepMetric.sleepEfficiency => value >= 0 && value <= 100,
        TagSleepMetric.sleepLatency => value >= 0 && value <= 1440,
        TagSleepMetric.morningRating =>
          value >= 1 && value <= 5 && value == value.roundToDouble(),
        TagSleepMetric.awakeningCount =>
          value >= 0 && value == value.roundToDouble(),
      };

  static TagSleepComparisonResult calculate({
    required Iterable<SleepSession> sessions,
    required Map<String, Set<String>> tagsBySession,
    required Set<String> tagKeys,
    required DateTime start,
    required DateTime endExclusive,
    required TagSleepMetric metric,
    Map<String, int> awakeningCountsBySession = const {},
    Map<String, double> efficiencyBySession = const {},
    Map<String, int> sleepLatencyBySession = const {},
  }) {
    if (tagKeys.isEmpty || tagKeys.any((key) => key.trim().isEmpty) || !endExclusive.isAfter(start)) {
      throw ArgumentError('Некорректные параметры сравнения.');
    }

    final withValues = <double>[];
    final withoutValues = <double>[];
    final withSessionIds = <String>[];
    final withoutSessionIds = <String>[];
    for (final session in sessions) {
      if (session.startedAt.isBefore(start) || !session.startedAt.isBefore(endExclusive)) {
        continue;
      }
      if (session.endedAt == null || !session.endedAt!.isAfter(session.startedAt)) continue;

      final value = switch (metric) {
        TagSleepMetric.sleepDuration => _actualSleepMinutes(session),
        TagSleepMetric.sleepEfficiency => efficiencyBySession[session.id],
        TagSleepMetric.sleepLatency => sleepLatencyBySession[session.id]?.toDouble(),
        TagSleepMetric.morningRating => session.morningRating?.toDouble(),
        TagSleepMetric.awakeningCount => awakeningCountsBySession[session.id]?.toDouble(),
      };
      if (value == null || !value.isFinite || !_isValidMetricValue(metric, value)) continue;

      final sessionTags = tagsBySession[session.id] ?? const <String>{};
      final hasTag = tagKeys.every(sessionTags.contains);
      (hasTag ? withValues : withoutValues).add(value);
      (hasTag ? withSessionIds : withoutSessionIds).add(session.id);
    }

    double? average(List<double> values) => values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;

    final withAverage = average(withValues);
    final withoutAverage = average(withoutValues);
    final sufficient = withValues.length >= minimumNightsPerGroup &&
        withoutValues.length >= minimumNightsPerGroup;
    return TagSleepComparisonResult(
      withTag: TagSleepGroupSummary(nights: withValues.length, average: withAverage, sessionIds: List.unmodifiable(withSessionIds), values: List.unmodifiable(withValues)),
      withoutTag: TagSleepGroupSummary(nights: withoutValues.length, average: withoutAverage, sessionIds: List.unmodifiable(withoutSessionIds), values: List.unmodifiable(withoutValues)),
      difference: sufficient && withAverage != null && withoutAverage != null
          ? withAverage - withoutAverage
          : null,
      metric: metric,
      isSufficient: sufficient,
    );
  }
}

class TagComparisonTemplate {
  const TagComparisonTemplate({
    required this.id,
    required this.name,
    required this.tagKeys,
    required this.metric,
  });

  final String id;
  final String name;
  final List<String> tagKeys;
  final TagSleepMetric metric;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tagKeys': tagKeys,
    'metric': metric.name,
  };

  factory TagComparisonTemplate.fromJson(Map<String, dynamic> json) {
    final metricName = json['metric'];
    TagSleepMetric? metric;
    for (final item in TagSleepMetric.values) {
      if (item.name == metricName) { metric = item; break; }
    }
    final id = json['id'];
    final name = json['name'];
    final rawTagKeys = json['tagKeys'];
    final legacyTagKey = json['tagKey'];
    final List<String>? tagKeys;
    if (rawTagKeys is List && rawTagKeys.isNotEmpty &&
        rawTagKeys.every((item) => item is String && item.trim().isNotEmpty)) {
      tagKeys = rawTagKeys.cast<String>().toSet().toList();
    } else if (rawTagKeys == null && legacyTagKey is String && legacyTagKey.trim().isNotEmpty) {
      // Read templates created by the first single-tag implementation.
      tagKeys = [legacyTagKey];
    } else {
      tagKeys = null;
    }
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty ||
        tagKeys == null || tagKeys.isEmpty || metric == null) {
      throw const FormatException('Шаблон сравнения повреждён.');
    }
    return TagComparisonTemplate(
      id: id,
      name: name.trim(),
      tagKeys: tagKeys,
      metric: metric,
    );
  }
}

class TagComparisonTemplateStore {
  TagComparisonTemplateStore(this._read, this._write);

  static const metadataKey = 'sleep_tag_comparison_templates_v1';
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  Future<List<TagComparisonTemplate>> load() async {
    final raw = await _read(metadataKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Список шаблонов сравнения повреждён.');
    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Шаблон сравнения повреждён.');
      }
      return TagComparisonTemplate.fromJson(item);
    }).toList();
  }

  Future<void> save(List<TagComparisonTemplate> templates) =>
      _write(metadataKey, jsonEncode(templates.map((item) => item.toJson()).toList()));
}
