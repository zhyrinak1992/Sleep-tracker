import 'dart:convert';

/// Merges only the achievement/record metadata owned by the unified
/// achievements feature. Other app metadata keeps the existing local-wins rule.
Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String mergeAchievementMetadata({
  required String key,
  required String? localRaw,
  required String importedRaw,
}) {
  Object? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  final local = decode(localRaw);
  final imported = decode(importedRaw);

  switch (key) {
    case 'sleep_achievements_history_v1':
      return jsonEncode(_mergeAchievementDates(local, imported));
    case 'sleep_personal_records_v1':
      return jsonEncode(_mergePersonalRecords(local, imported));
    case 'sleep_personal_records_history_v1':
      return jsonEncode(_mergePersonalRecordHistory(local, imported));
    case 'sleep_records_history_v1':
      return jsonEncode(_mergeRecordEvents(local, imported));
    case 'sleep_records_celebrated_v1':
    case 'sleep_personal_records_celebrated_v1':
      return jsonEncode(_mergeStringSet(local, imported));
    default:
      return importedRaw;
  }
}

Map<String, String> _mergeAchievementDates(Object? local, Object? imported) {
  final result = <String, String>{};
  void add(Object? value) {
    if (value is! Map) return;
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final date = DateTime.tryParse(entry.value as String);
      if (date == null) continue;
      final id = entry.key as String;
      final previous = result[id];
      final previousDate = previous == null ? null : DateTime.tryParse(previous);
      if (previousDate == null || date.isBefore(previousDate)) {
        result[id] = date.toUtc().toIso8601String();
      }
    }
  }
  add(local);
  add(imported);
  return result;
}

List<Map<String, Object?>> _mergePersonalRecordHistory(
  Object? local,
  Object? imported,
) {
  final byId = <String, Map<String, Object?>>{};

  void add(Object? value) {
    if (value is! List) return;
    for (final item in value) {
      if (item is! Map) continue;
      final id = item['id'];
      final metric = item['metric'];
      final rawValue = item['value'];
      final achievedAt = item['achievedAt'];
      final sessionId = item['sessionId'];
      if (id is! String || id.isEmpty ||
          metric is! String ||
          !const {
            'longestSleepMinutes',
            'bestSleepScore',
            'bestEfficiencyPercent',
            'fewestAwakenings',
            'shortestLatencyMinutes',
            'longestStreakDays',
          }.contains(metric) ||
          rawValue is! num || !rawValue.toDouble().isFinite ||
          achievedAt is! String ||
          DateTime.tryParse(achievedAt) == null ||
          (sessionId != null && sessionId is! String)) {
        continue;
      }
      final number = rawValue.toDouble();
      final valid = switch (metric) {
        'longestSleepMinutes' => number > 0 && number % 1 == 0,
        'bestSleepScore' => number >= 0 && number <= 100 && number % 1 == 0,
        'bestEfficiencyPercent' => number >= 0 && number <= 100,
        'fewestAwakenings' => number >= 0 && number % 1 == 0,
        'shortestLatencyMinutes' =>
          number >= 0 && number <= 1440 && number % 1 == 0,
        'longestStreakDays' => number >= 1 && number % 1 == 0,
        _ => false,
      };
      if (!valid) continue;
      byId.putIfAbsent(id, () => {
        'id': id,
        'metric': metric,
        'value': number,
        'achievedAt': DateTime.parse(achievedAt).toUtc().toIso8601String(),
        'sessionId': sessionId,
      });
    }
  }

  add(local);
  add(imported);
  final result = byId.values.toList()
    ..sort((a, b) {
      final aDate = DateTime.parse(a['achievedAt']! as String);
      final bDate = DateTime.parse(b['achievedAt']! as String);
      final date = aDate.compareTo(bDate);
      if (date != 0) return date;
      return (a['metric']! as String).compareTo(b['metric']! as String);
    });
  return result;
}

Map<String, Object?> _mergePersonalRecords(Object? local, Object? imported) {
  final a = _stringKeyedMap(local);
  final b = _stringKeyedMap(imported);
  final result = Map<String, Object?>.from(a);
  final versions = [a['recordSchemaVersion'], b['recordSchemaVersion']]
      .whereType<int>()
      .toList();
  if (versions.isNotEmpty) {
    result['recordSchemaVersion'] = versions.reduce((x, y) => x > y ? x : y);
  }

  num? validRecordValue(String key, Object? value) {
    if (value is! num || !value.isFinite || value < 0) return null;
    if (key == 'bestEfficiencyPercent' || key == 'bestSleepScore') {
      return value <= 100 ? value : null;
    }
    if (key == 'shortestLatencyMinutes' && value > 1440) return null;
    if (value % 1 != 0) return null;
    return value;
  }

  bool hasAssociatedValue(Map<String, Object?> source, String key) {
    final value = source[key];
    if (key.endsWith('At')) {
      return value is String && DateTime.tryParse(value) != null;
    }
    if (key.endsWith('SessionId')) {
      return value is String && value.isNotEmpty;
    }
    return value != null;
  }

  bool importedHasMissingSourceMetadata(List<String> associatedKeys) =>
      associatedKeys.any((key) =>
          !hasAssociatedValue(a, key) && hasAssociatedValue(b, key));

  void applyImportedRecord(
    String valueKey,
    List<String> associatedKeys, {
    required bool tiedValue,
  }) {
    result[valueKey] = b[valueKey];
    for (final key in associatedKeys) {
      if (hasAssociatedValue(b, key)) {
        result[key] = b[key];
      } else if (!tiedValue || !hasAssociatedValue(a, key)) {
        result.remove(key);
      }
    }
  }

  void chooseMaximum(String valueKey, List<String> associatedKeys) {
    final an = validRecordValue(valueKey, a[valueKey]);
    final bn = validRecordValue(valueKey, b[valueKey]);
    if (an == null && bn == null) return;
    final tiedValue = an != null && bn != null && an == bn;
    final takeImported = an == null || (bn != null && bn > an) ||
        (tiedValue && importedHasMissingSourceMetadata(associatedKeys));
    if (takeImported) {
      applyImportedRecord(valueKey, associatedKeys, tiedValue: tiedValue);
    }
  }

  void chooseMinimum(String valueKey, List<String> associatedKeys) {
    final an = validRecordValue(valueKey, a[valueKey]);
    final bn = validRecordValue(valueKey, b[valueKey]);
    if (an == null && bn == null) return;
    final tiedValue = an != null && bn != null && an == bn;
    final takeImported = an == null || (bn != null && bn < an) ||
        (tiedValue && importedHasMissingSourceMetadata(associatedKeys));
    if (takeImported) {
      applyImportedRecord(valueKey, associatedKeys, tiedValue: tiedValue);
    }
  }

  chooseMaximum('longestSleepMinutes', ['longestSleepSessionId', 'longestSleepAt']);
  chooseMaximum('bestSleepScore', ['bestSleepScoreSessionId', 'bestSleepScoreAt']);
  chooseMaximum('bestEfficiencyPercent', ['bestEfficiencySessionId', 'bestEfficiencyAt']);
  chooseMinimum('fewestAwakenings', ['fewestAwakeningsSessionId', 'fewestAwakeningsAt']);
  chooseMinimum('shortestLatencyMinutes', ['shortestLatencySessionId', 'shortestLatencyAt']);
  chooseMaximum('longestStreakDays', ['longestStreakAt']);
  return result;
}

List<Map<String, Object?>> _mergeRecordEvents(Object? local, Object? imported) {
  final bySessionMetric = <String, Map<String, Object?>>{};
  void add(Object? value) {
    if (value is! List) return;
    for (final item in value) {
      if (item is! Map) continue;
      final event = _stringKeyedMap(item);
      final type = event['type'];
      final sessionId = event['sessionId'];
      final metricValue = event['value'];
      final date = event['achievedAt'];
      if ((type != 'sleep_score' && type != 'awakening_count') ||
          sessionId is! String || sessionId.isEmpty ||
          metricValue is! num || !metricValue.isFinite ||
          metricValue < 0 || metricValue % 1 != 0 ||
          (type == 'sleep_score' && metricValue > 100) ||
          date is! String || DateTime.tryParse(date) == null) continue;
      final key = '$type|$sessionId';
      // If the same source night/metric exists locally, local wins. This
      // avoids importing a stale value after the night was edited locally.
      bySessionMetric.putIfAbsent(key, () => event);
    }
  }
  add(local);
  add(imported);
  final result = bySessionMetric.values.toList()
    ..sort((a, b) => DateTime.parse(a['achievedAt'] as String)
        .compareTo(DateTime.parse(b['achievedAt'] as String)));
  return result;
}

List<String> _mergeStringSet(Object? local, Object? imported) {
  final result = <String>{};
  if (local is List) result.addAll(local.whereType<String>());
  if (imported is List) result.addAll(imported.whereType<String>());
  return result.toList();
}
