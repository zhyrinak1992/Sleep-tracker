import 'dart:convert';

/// Persistent history for the daily "What may influence your sleep" analysis.
///
/// Snapshots are stored in app_metadata, which is already included in backup
/// export and merge. A new snapshot is written only when analyzed observations
/// change; source-night details remain in the sleep database.
class TagInsightHistoryStore {
  TagInsightHistoryStore(this._read, this._write);

  static const metadataKey = 'tag_insight_history_v1';

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  Future<List<Map<String, Object?>>> loadHistory() async {
    final raw = await _read(metadataKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! Map)) {
      throw const FormatException('История закономерностей повреждена.');
    }
    return decoded
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
  }

  Future<Map<String, Object?>?> loadCurrent() async {
    final history = await loadHistory();
    return history.isEmpty ? null : history.last;
  }

  Future<Map<String, Object?>?> record({
    required String fingerprint,
    required DateTime generatedAt,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Map<String, Object?> tagPatterns,
  }) async {
    final history = await loadHistory();
    final periodStartIso = periodStart.toIso8601String();
    final periodEndIso = periodEndExclusive.toIso8601String();
    final previousIndex = history.lastIndexWhere((snapshot) =>
        snapshot['periodStart'] == periodStartIso &&
        snapshot['periodEndExclusive'] == periodEndIso);
    final previousSnapshot =
        previousIndex >= 0 ? history[previousIndex] : null;
    if (previousSnapshot != null &&
        previousSnapshot['fingerprint'] == fingerprint) {
      return null;
    }

    final previousInsights = <String, Map<String, Object?>>{};
    if (previousSnapshot != null && previousSnapshot['insights'] is List) {
      for (final raw in previousSnapshot['insights'] as List) {
        if (raw is! Map) continue;
        final insight = Map<String, Object?>.from(raw);
        final id = insight['id'];
        if (id is String && id.isNotEmpty) previousInsights[id] = insight;
      }
    }

    final currentById = _flattenCurrentPatterns(tagPatterns);
    final updated = <String, Map<String, Object?>>{};

    for (final entry in previousInsights.entries) {
      final previous = Map<String, Object?>.from(entry.value);
      final current = currentById.remove(entry.key);
      final statusBefore = previous['status'] as String? ?? 'new';
      final events = (previous['statusEvents'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
      final lastComparable = previous['lastComparable'] is Map
          ? Map<String, Object?>.from(previous['lastComparable'] as Map)
          : null;

      String nextStatus;
      if (current == null || current['isSufficient'] != true ||
          current['difference'] is! num) {
        // Missing or insufficient observations do not disprove an earlier
        // pattern. Keep the last comparable result and explain the limitation.
        nextStatus = 'insufficientData';
      } else {
        final difference = (current['difference'] as num).toDouble();
        if (lastComparable == null || lastComparable['difference'] is! num) {
          nextStatus = difference == 0 ? 'noLongerObserved' : 'new';
        } else {
          final oldDifference =
              (lastComparable['difference'] as num).toDouble();
          if (difference == 0 || difference.sign != oldDifference.sign) {
            nextStatus = 'noLongerObserved';
          } else if (difference.abs() < oldDifference.abs()) {
            nextStatus = 'weakened';
          } else {
            nextStatus = 'confirmed';
          }
        }
        if (difference != 0) {
          previous['lastComparable'] = _comparableValues(
            current,
            periodStart,
            periodEndExclusive,
          );
        }
      }

      if (nextStatus != statusBefore) {
        events.add({
          'status': nextStatus,
          'at': generatedAt.toIso8601String(),
        });
      }
      previous['status'] = nextStatus;
      previous['current'] = current;
      previous['updatedAt'] = generatedAt.toIso8601String();
      previous['statusEvents'] = events;
      updated[entry.key] = previous;
    }

    for (final entry in currentById.entries) {
      final current = entry.value;
      if (current['isSufficient'] != true ||
          current['difference'] is! num ||
          (current['difference'] as num) == 0) {
        continue;
      }
      updated[entry.key] = {
        'id': entry.key,
        'tagKey': current['tagKey'],
        'tagLabel': current['tagLabel'],
        'metricKey': current['metricKey'],
        'metricLabel': current['metricLabel'],
        'status': 'new',
        'createdAt': generatedAt.toIso8601String(),
        'updatedAt': generatedAt.toIso8601String(),
        'current': current,
        'lastComparable': _comparableValues(
          current,
          periodStart,
          periodEndExclusive,
        ),
        'statusEvents': [
          {'status': 'new', 'at': generatedAt.toIso8601String()},
        ],
      };
    }

    final insights = updated.values.toList()
      ..sort((a, b) {
        final byTag = (a['tagLabel'] as String? ?? '')
            .compareTo(b['tagLabel'] as String? ?? '');
        if (byTag != 0) return byTag;
        return (a['metricLabel'] as String? ?? '')
            .compareTo(b['metricLabel'] as String? ?? '');
      });
    final snapshot = <String, Object?>{
      'schemaVersion': 1,
      'snapshotId': '$periodStartIso|${generatedAt.toIso8601String()}|$fingerprint',
      'fingerprint': fingerprint,
      'generatedAt': generatedAt.toIso8601String(),
      'periodStart': periodStart.toIso8601String(),
      'periodEndExclusive': periodEndExclusive.toIso8601String(),
      'insights': insights,
    };
    await _write(metadataKey, jsonEncode([...history, snapshot]));
    return snapshot;
  }

  Map<String, Map<String, Object?>> _flattenCurrentPatterns(
    Map<String, Object?> tagPatterns,
  ) {
    final result = <String, Map<String, Object?>>{};
    final rawPatterns = tagPatterns['current'];
    if (rawPatterns is! List) return result;
    for (final rawPattern in rawPatterns) {
      if (rawPattern is! Map) continue;
      final pattern = Map<String, Object?>.from(rawPattern);
      final tagKey = pattern['tagKey'];
      if (tagKey is! String || tagKey.isEmpty) continue;
      final metrics = pattern['metrics'];
      if (metrics is! Map) continue;
      for (final entry in metrics.entries) {
        if (entry.value is! Map) continue;
        final metricKey = entry.key.toString();
        final metric = Map<String, Object?>.from(entry.value as Map);
        final id = jsonEncode([tagKey, metricKey]);
        result[id] = {
          'tagKey': tagKey,
          'tagLabel': pattern['label']?.toString() ?? tagKey,
          'metricKey': metricKey,
          'metricLabel': _metricLabels[metricKey] ?? metricKey,
          'isSufficient': metric['isSufficient'] == true,
          'withTagAverage': metric['withTagAverage'],
          'withoutTagAverage': metric['withoutTagAverage'],
          'difference': metric['difference'],
          'withTagSamples': metric['withTagSamples'] ?? 0,
          'withoutTagSamples': metric['withoutTagSamples'] ?? 0,
        };
      }
    }
    return result;
  }

  Map<String, Object?> _comparableValues(
    Map<String, Object?> current,
    DateTime periodStart,
    DateTime periodEndExclusive,
  ) => {
    'difference': current['difference'],
    'withTagAverage': current['withTagAverage'],
    'withoutTagAverage': current['withoutTagAverage'],
    'withTagSamples': current['withTagSamples'],
    'withoutTagSamples': current['withoutTagSamples'],
    'periodStart': periodStart.toIso8601String(),
    'periodEndExclusive': periodEndExclusive.toIso8601String(),
  };

  static const _metricLabels = <String, String>{
    'duration': 'Продолжительность сна',
    'score': 'Оценка сна',
    'awakenings': 'Пробуждения',
    'efficiency': 'Эффективность сна',
    'sleepLatency': 'Задержка засыпания',
    'subjectiveQuality': 'Субъективное качество',
    'wellbeing': 'Утреннее самочувствие',
    'bedtime': 'Время засыпания',
    'wakeTime': 'Время пробуждения',
    'heartRate': 'Пульс',
    'respiratoryRate': 'Частота дыхания',
    'bloodOxygen': 'Насыщение кислородом',
    'hrv': 'Вариабельность пульса SDNN',
    'roomTemperature': 'Температура датчика',
    'roomHumidity': 'Влажность датчика',
  };

  static String statusLabel(String? status) => switch (status) {
    'new' => 'Новая закономерность',
    'confirmed' => 'Сохраняется / подтверждается',
    'weakened' => 'Ослабевает',
    'noLongerObserved' => 'Больше не наблюдается',
    'insufficientData' => 'Недостаточно данных для перепроверки',
    _ => 'Статус не определён',
  };
}
