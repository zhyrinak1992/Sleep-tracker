import 'dart:convert';

import '../../models/sleep_session.dart';

enum TagSleepMetric { sleepDuration, morningRating }

extension TagSleepMetricLabel on TagSleepMetric {
  String get label => switch (this) {
    TagSleepMetric.sleepDuration => 'Продолжительность сна',
    TagSleepMetric.morningRating => 'Утренняя оценка',
  };

  String get unit => switch (this) {
    TagSleepMetric.sleepDuration => 'мин',
    TagSleepMetric.morningRating => 'из 5',
  };
}

class TagSleepGroupSummary {
  const TagSleepGroupSummary({required this.nights, required this.average});
  final int nights;
  final double? average;
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

  static TagSleepComparisonResult calculate({
    required Iterable<SleepSession> sessions,
    required Map<String, Set<String>> tagsBySession,
    required String tagKey,
    required DateTime start,
    required DateTime endExclusive,
    required TagSleepMetric metric,
  }) {
    if (tagKey.trim().isEmpty || !endExclusive.isAfter(start)) {
      throw ArgumentError('Некорректные параметры сравнения.');
    }

    final withValues = <double>[];
    final withoutValues = <double>[];
    for (final session in sessions) {
      if (session.startedAt.isBefore(start) || !session.startedAt.isBefore(endExclusive)) {
        continue;
      }
      if (session.endedAt == null || !session.endedAt!.isAfter(session.startedAt)) continue;

      final value = switch (metric) {
        TagSleepMetric.sleepDuration => session.duration!.inMinutes.toDouble(),
        TagSleepMetric.morningRating => session.morningRating?.toDouble(),
      };
      if (value == null || !value.isFinite) continue;

      final hasTag = tagsBySession[session.id]?.contains(tagKey) ?? false;
      (hasTag ? withValues : withoutValues).add(value);
    }

    double? average(List<double> values) => values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;

    final withAverage = average(withValues);
    final withoutAverage = average(withoutValues);
    final sufficient = withValues.length >= minimumNightsPerGroup &&
        withoutValues.length >= minimumNightsPerGroup;
    return TagSleepComparisonResult(
      withTag: TagSleepGroupSummary(nights: withValues.length, average: withAverage),
      withoutTag: TagSleepGroupSummary(nights: withoutValues.length, average: withoutAverage),
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
    required this.tagKey,
    required this.metric,
  });

  final String id;
  final String name;
  final String tagKey;
  final TagSleepMetric metric;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tagKey': tagKey,
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
    final tagKey = json['tagKey'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty ||
        tagKey is! String || tagKey.isEmpty || metric == null) {
      throw const FormatException('Шаблон сравнения повреждён.');
    }
    return TagComparisonTemplate(
      id: id,
      name: name.trim(),
      tagKey: tagKey,
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
