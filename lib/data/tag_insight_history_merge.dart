import 'dart:convert';

/// Merge and validation for the persisted history of tag-related sleep insights.
class TagInsightHistoryMerge {
  TagInsightHistoryMerge._();

  static const metadataKey = 'tag_insight_history_v1';
  static const _statuses = {
    'new',
    'confirmed',
    'weakened',
    'noLongerObserved',
    'insufficientData',
  };

  static List<Map<String, Object?>> decode(String? raw, String source) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('$source: история закономерностей имеет неверный формат.');
    }
    final result = <Map<String, Object?>>[];
    for (final item in decoded) {
      if (item is! Map) {
        throw FormatException('$source: история закономерностей содержит некорректный снимок.');
      }
      final snapshot = Map<String, Object?>.from(item);
      _validateSnapshot(snapshot, source);
      result.add(snapshot);
    }
    return result;
  }

  static void validateRaw(String raw, String source) {
    decode(raw, source);
  }

  static void validateBackupMetadata(Map<String, dynamic> data) {
    final metadata = data['app_metadata'];
    if (metadata is! List) return;
    for (final raw in metadata) {
      if (raw is! Map || raw['key'] != metadataKey) continue;
      final value = raw['value'];
      if (value is! String) {
        throw const FormatException('История закономерностей в резервной копии повреждена.');
      }
      validateRaw(value, 'Резервная копия');
    }
  }

  static List<Map<String, Object?>> merge({
    required List<Map<String, Object?>> local,
    required List<Map<String, Object?>> imported,
  }) {
    final byFingerprint = <String, Map<String, Object?>>{};
    for (final snapshot in [...local, ...imported]) {
      _validateSnapshot(snapshot, 'История');
      final fingerprint = snapshot['fingerprint'] as String;
      final existing = byFingerprint[fingerprint];
      byFingerprint[fingerprint] = existing == null
          ? Map<String, Object?>.from(snapshot)
          : _mergeSnapshot(existing, snapshot);
    }
    final result = byFingerprint.values.toList()
      ..sort((a, b) {
        final aDate = DateTime.parse(a['generatedAt'] as String);
        final bDate = DateTime.parse(b['generatedAt'] as String);
        final byDate = aDate.compareTo(bDate);
        return byDate != 0
            ? byDate
            : (a['fingerprint'] as String)
                .compareTo(b['fingerprint'] as String);
      });
    return result;
  }

  static Map<String, Object?> _mergeSnapshot(
    Map<String, Object?> first,
    Map<String, Object?> second,
  ) {
    final firstDate = DateTime.parse(first['generatedAt'] as String);
    final secondDate = DateTime.parse(second['generatedAt'] as String);
    final newer = secondDate.isAfter(firstDate) ? second : first;
    final older = identical(newer, second) ? first : second;
    final insights = <String, Map<String, Object?>>{};

    void addInsights(Map<String, Object?> source) {
      final raw = source['insights'];
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final insight = Map<String, Object?>.from(item);
        final id = insight['id'];
        if (id is! String) continue;
        final existing = insights[id];
        if (existing == null) {
          insights[id] = insight;
          continue;
        }
        final existingDate = DateTime.tryParse(
              existing['updatedAt'] as String? ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final incomingDate = DateTime.tryParse(
              insight['updatedAt'] as String? ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final latest = incomingDate.isAfter(existingDate)
            ? insight
            : existing;
        final events = <String, Map<String, Object?>>{};
        for (final rawEvent in [
          ...(existing['statusEvents'] as List? ?? const []),
          ...(insight['statusEvents'] as List? ?? const []),
        ]) {
          if (rawEvent is! Map) continue;
          final event = Map<String, Object?>.from(rawEvent);
          final key = '${event['status']}|${event['at']}';
          events[key] = event;
        }
        final mergedEvents = events.values.toList()
          ..sort((a, b) => DateTime.parse(a['at'] as String)
              .compareTo(DateTime.parse(b['at'] as String)));
        insights[id] = {
          ...existing,
          ...latest,
          'statusEvents': mergedEvents,
        };
      }
    }

    addInsights(older);
    addInsights(newer);
    final sortedInsights = insights.values.toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return {
      ...older,
      ...newer,
      'insights': sortedInsights,
    };
  }

  static void _validateSnapshot(
    Map<String, Object?> snapshot,
    String source,
  ) {
    DateTime parseDate(Object? value, String label) {
      if (value is! String) {
        throw FormatException('$source: в истории закономерностей отсутствует $label.');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw FormatException('$source: некорректная дата $label в истории закономерностей.');
      }
      return parsed;
    }

    if (snapshot['schemaVersion'] != 1 ||
        snapshot['fingerprint'] is! String ||
        (snapshot['fingerprint'] as String).isEmpty ||
        snapshot['insights'] is! List) {
      throw FormatException('$source: некорректный снимок истории закономерностей.');
    }
    parseDate(snapshot['generatedAt'], 'даты создания');
    final start = parseDate(snapshot['periodStart'], 'начала периода');
    final end = parseDate(snapshot['periodEndExclusive'], 'окончания периода');
    if (!end.isAfter(start)) {
      throw FormatException('$source: некорректные границы периода истории закономерностей.');
    }
    final ids = <String>{};
    for (final raw in snapshot['insights'] as List) {
      if (raw is! Map) {
        throw FormatException('$source: некорректная закономерность в истории.');
      }
      final insight = Map<String, Object?>.from(raw);
      final id = insight['id'];
      if (id is! String || id.isEmpty || !ids.add(id) ||
          insight['tagKey'] is! String ||
          insight['tagLabel'] is! String ||
          insight['metricKey'] is! String ||
          insight['metricLabel'] is! String ||
          insight['status'] is! String ||
          !_statuses.contains(insight['status']) ||
          insight['statusEvents'] is! List) {
        throw FormatException('$source: некорректная запись закономерности в истории.');
      }
      parseDate(insight['createdAt'], 'даты создания закономерности');
      parseDate(insight['updatedAt'], 'даты обновления закономерности');
      if (insight['current'] != null && insight['current'] is! Map) {
        throw FormatException('$source: некорректные текущие значения закономерности.');
      }
      if (insight['lastComparable'] != null &&
          insight['lastComparable'] is! Map) {
        throw FormatException('$source: некорректные последние сопоставимые значения.');
      }
      for (final event in insight['statusEvents'] as List) {
        if (event is! Map ||
            event['status'] is! String ||
            !_statuses.contains(event['status'])) {
          throw FormatException('$source: некорректное событие статуса закономерности.');
        }
        parseDate(event['at'], 'даты события статуса');
      }
    }
  }
}
