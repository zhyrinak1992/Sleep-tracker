class PeriodicReportExport {
  PeriodicReportExport._();

  static String toCsv(Map<String, Object?> snapshot) {
    final rows = <List<Object?>>[
      ['Показатель', 'Значение'],
      ['Тип отчёта', _kindLabel(snapshot['kind'])],
      ['Начало периода', snapshot['start']],
      ['Окончание периода (не включительно)', snapshot['endExclusive']],
      ['Завершённых ночей', snapshot['nights']],
      ['Средняя продолжительность сна, мин', snapshot['averageSleepMinutes']],
      ['Суммарная продолжительность сна, мин', snapshot['totalSleepMinutes']],
      ['Количество ночей с данными о длительности', snapshot['sleepDurationSamples']],
      ['Среднее время в постели, мин', snapshot['averageTimeInBedMinutes']],
      ['Эффективность сна, %', snapshot['averageEfficiency']],
      ['Количество пробуждений в среднем', snapshot['averageAwakenings']],
      ['Субъективное качество сна', snapshot['averageQuality']],
      ['Утреннее самочувствие', snapshot['averageWellbeing']],
      ['Звуковых событий', snapshot['audioEventCount']],
      ['Заметок', snapshot['noteCount']],
    ];

    final score = snapshot['score'] is Map
        ? Map<String, Object?>.from(snapshot['score'] as Map)
        : <String, Object?>{};
    rows.add(['Средняя оценка сна 0–100', score['average']]);
    rows.add(['Ночей с оценкой сна', score['samples']]);

    final components = score['components'] is Map
        ? Map<String, Object?>.from(score['components'] as Map)
        : <String, Object?>{};
    for (final entry in components.entries) {
      final component = entry.value is Map
          ? Map<String, Object?>.from(entry.value as Map)
          : <String, Object?>{};
      rows.add([
        'Компонент оценки: ${component['label'] ?? entry.key}',
        component['average'],
        'Наблюдений',
        component['samples'],
      ]);
    }

    final trend = snapshot['trendPoints'] is List
        ? (snapshot['trendPoints'] as List).whereType<Map>().toList()
        : <Map>[];
    final months = snapshot['months'] is List
        ? (snapshot['months'] as List).whereType<Map>().toList()
        : <Map>[];
    final points = months.isNotEmpty ? months : trend;
    if (points.isNotEmpty) {
      rows.add([]);
      rows.add([
        'Динамика внутри периода',
        'Ночей',
        'Средняя длительность, мин',
        'Оценка сна 0–100',
        'Эффективность, %',
        'Пробуждения',
        'Качество',
        'Самочувствие',
      ]);
      for (final point in points) {
        final scoreData = point['score'] is Map
            ? Map<String, Object?>.from(point['score'] as Map)
            : <String, Object?>{};
        final rawNights = point['nights'];
        final nightCount = rawNights is List
            ? rawNights.length
            : rawNights is num ? rawNights : null;
        rows.add([
          point['label'] ?? point['bucket'] ?? point['month'],
          nightCount,
          point['averageSleepMinutes'] ?? point['sleepMinutes'],
          scoreData['average'],
          point['averageEfficiency'],
          point['averageAwakenings'],
          point['averageQuality'],
          point['averageWellbeing'],
        ]);
      }
    }

    final insights = snapshot['rankedInsights'] is List
        ? (snapshot['rankedInsights'] as List).whereType<Map>().toList()
        : <Map>[];
    if (insights.isNotEmpty) {
      rows.add([]);
      rows.add([
        'Персональные закономерности',
        'Показатель',
        'С отметкой',
        'Ночей',
        'Без отметки',
        'Ночей',
        'Разница',
      ]);
      for (final raw in insights) {
        rows.add([
          raw['tagLabel'],
          raw['metricLabel'],
          raw['withTagAverage'],
          raw['withTagSamples'],
          raw['withoutTagAverage'],
          raw['withoutTagSamples'],
          raw['difference'],
        ]);
      }
    }

    final tagPatterns = snapshot['tagPatterns'] is Map
        ? Map<String, Object?>.from(snapshot['tagPatterns'] as Map)
        : <String, Object?>{};
    final currentPatterns = tagPatterns['current'] is List
        ? (tagPatterns['current'] as List).whereType<Map>().toList()
        : <Map>[];
    if (currentPatterns.isNotEmpty) {
      rows.add([]);
      rows.add([
        'Сравнение по отметкам',
        'Показатель',
        'С отметкой',
        'Ночей',
        'Без отметки',
        'Ночей',
        'Разница',
      ]);
      for (final pattern in currentPatterns) {
        final metrics = pattern['metrics'] is Map
            ? Map<String, Object?>.from(pattern['metrics'] as Map)
            : <String, Object?>{};
        for (final entry in metrics.entries) {
          final metric = entry.value is Map
              ? Map<String, Object?>.from(entry.value as Map)
              : <String, Object?>{};
          rows.add([
            pattern['label'] ?? pattern['tagKey'],
            entry.key,
            metric['withTagAverage'],
            metric['withTagSamples'],
            metric['withoutTagAverage'],
            metric['withoutTagSamples'],
            metric['difference'],
          ]);
        }
      }
    }

    return '\uFEFF' + rows.map((row) => row.map(_field).join(';')).join('\r\n');
  }

  static String _kindLabel(Object? kind) => switch (kind) {
    'week' => 'Неделя',
    'month' => 'Месяц',
    'quarter' => 'Квартал',
    'halfYear' => 'Полугодие',
    'year' => 'Год',
    _ => 'Период',
  };

  static String _field(Object? value) {
    if (value == null) return '';
    final text = value is num
        ? (value.toDouble().isFinite ? value.toString() : '')
        : value.toString();
    if (text.contains(';') || text.contains('"') ||
        text.contains('\n') || text.contains('\r')) {
      return '"' + text.replaceAll('"', '""') + '"';
    }
    return text;
  }
}
