import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/sleep_session.dart';
import '../features/diary/sleep_session_metrics.dart';
import '../features/diary/sleep_metric_summary.dart';
import 'sleep_database.dart';

class PdfReportService {
  /// Returns the first local calendar date included in a rolling history export.
  /// The export includes [days] calendar dates, including today; it is not a
  /// fixed 24-hour duration and therefore remains stable across DST changes.
  static DateTime historyRangeStart({required DateTime now, required int days}) {
    if (days <= 0) {
      throw ArgumentError.value(days, 'days', 'Количество дней должно быть положительным.');
    }
    if (days >= 3650) return DateTime.fromMillisecondsSinceEpoch(0);
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(today.year, today.month, today.day - days + 1);
  }

  /// Reads the monthly night count without confusing it with the detailed
  /// night rows stored under the legacy `nights` key.
  static int monthNightCount(Map<String, Object?> month) {
    final explicit = month['nightCount'];
    if (explicit is num && explicit.isFinite && explicit >= 0) {
      return explicit.round();
    }
    final nights = month['nights'];
    if (nights is List) return nights.length;
    if (nights is num && nights.isFinite && nights >= 0) {
      return nights.round();
    }
    return 0;
  }


  /// Exports a user-selected comparison of two date ranges with aggregate
  /// metrics and the actual completed nightly observations behind them.
  static Future<void> exportPeriodComparison({
    required String title,
    required String periodALabel,
    required String periodBLabel,
    required List<Map<String, Object?>> metrics,
    required List<Map<String, Object?>> nightsA,
    required List<Map<String, Object?>> nightsB,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    pw.Widget nightTable(List<Map<String, Object?>> nights) {
      if (nights.isEmpty) return pw.Text('Нет завершённых ночных записей.');
      return pw.TableHelper.fromTextArray(
        headers: ['Дата', 'Начало', 'Конец', 'Сон', 'Эффективность', 'Пробуждения', 'Качество', 'Самочувствие'],
        cellStyle: const pw.TextStyle(fontSize: 7),
        headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        data: nights.map((night) => [
          night['date'] ?? '—',
          night['start'] ?? '—',
          night['end'] ?? '—',
          night['duration'] ?? '—',
          night['efficiency'] ?? '—',
          night['awakenings'] ?? '—',
          night['quality'] ?? '—',
          night['wellbeing'] ?? '—',
        ]).toList(),
      );
    }

    doc.addPage(pw.MultiPage(maxPages: 1000,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => [
        pw.Header(level: 0, child: pw.Text('Sleep Tracker — $title')),
        pw.Text('Сформирован: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}'),
        pw.SizedBox(height: 12),
        pw.Header(level: 1, child: pw.Text('Сводное сравнение')),
        pw.TableHelper.fromTextArray(
          headers: ['Показатель', 'Период A', 'Период B', 'Изменение'],
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          data: metrics.map((metric) => [
            metric['label'] ?? '—',
            metric['a'] ?? 'Нет данных',
            metric['b'] ?? 'Нет данных',
            metric['change'] ?? 'Недостаточно данных',
          ]).toList(),
        ),
        pw.SizedBox(height: 14),
        pw.Header(level: 1, child: pw.Text('Период A — $periodALabel')),
        pw.Text('Завершённых ночей: ${nightsA.length}'),
        nightTable(nightsA),
        pw.SizedBox(height: 14),
        pw.Header(level: 1, child: pw.Text('Период B — $periodBLabel')),
        pw.Text('Завершённых ночей: ${nightsB.length}'),
        nightTable(nightsB),
        pw.SizedBox(height: 12),
        pw.Text('Отчёт содержит сохранённые измерения. Размер выборки зависит от доступности конкретного показателя; отсутствие данных не считается нулём. Сравнение описывает различия между периодами и не устанавливает причины изменений.',
          style: const pw.TextStyle(fontSize: 8)),
      ],
    ));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-comparison-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Сравнение периодов Sleep Tracker');
  }

  /// Exports the currently selected analytics category and period, including
  /// metric samples, trend buckets, and the underlying completed nights.
  static Future<void> exportSleepDynamics({
    required String title,
    required String category,
    required String dateRange,
    required String previousRange,
    required int sessionsCount,
    required int completedCount,
    required int previousCompletedCount,
    required List<Map<String, Object?>> metrics,
    required List<Map<String, Object?>> trend,
    required List<Map<String, Object?>> nights,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(maxPages: 1000,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => [
        pw.Header(level: 0, child: pw.Text('Sleep Tracker — $title')),
        pw.Text('Сформирован: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}'),
        pw.Text('Категория: $category'),
        pw.Text('Выбранный период: $dateRange'),
        pw.Text('Предыдущий равный период: $previousRange'),
        pw.SizedBox(height: 10),
        pw.Header(level: 1, child: pw.Text('Сводные показатели')),
        pw.Text('Записей в выбранном периоде: $sessionsCount · завершённых ночей: $completedCount · в предыдущем периоде: $previousCompletedCount'),
        if (metrics.isEmpty) pw.Text('Для выбранной категории нет доступных показателей.')
        else pw.TableHelper.fromTextArray(
          headers: ['Показатель', 'Текущий период', 'n', 'Предыдущий период', 'n'],
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          data: metrics.map((metric) => [
            metric['label'] ?? '—',
            metric['current'] ?? 'Нет данных',
            metric['currentSamples'] ?? 0,
            metric['previous'] ?? 'Нет данных',
            metric['previousSamples'] ?? 0,
          ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Header(level: 1, child: pw.Text('Графики динамики')),
        if (trend.where((point) => point['rawValue'] is num).isEmpty)
          pw.Text('Нет числовых данных для построения графиков.')
        else ...trend.map((point) => point['metric']).toSet().map((metric) {
          final points = trend.where((point) => point['metric'] == metric && point['rawValue'] is num).toList();
          if (points.isEmpty) return pw.SizedBox();
          final values = points.map((point) => (point['rawValue'] as num).toDouble()).toList();
          final maximum = values.fold<double>(0, (a, b) => b > a ? b : a);
          final safeMaximum = maximum <= 0 ? 1.0 : maximum;
          final barWidth = 420 / points.length * 0.55;
          final gap = 420 / points.length;
          final bars = <String>[];
          for (var i = 0; i < values.length; i++) {
            final height = values[i] / safeMaximum * 82;
            final x = 48 + i * gap + (gap - barWidth) / 2;
            final y = 104 - height;
            bars.add('<rect x="$x" y="$y" width="$barWidth" height="$height" rx="3" fill="#397E9A"/>');
          }
          final svg = '<svg xmlns="http://www.w3.org/2000/svg" width="520" height="125" viewBox="0 0 520 125"><line x1="38" y1="104" x2="490" y2="104" stroke="#9AAAB5" stroke-width="1"/>' + bars.join() + '</svg>';
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(metric.toString(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.SizedBox(height: 3),
              pw.SvgImage(svg: svg, width: 520, height: 125),
              pw.SizedBox(height: 3),
            ],
          );
        }),
        pw.Header(level: 1, child: pw.Text('Точные значения по интервалам')),
        if (trend.isEmpty) pw.Text('Нет данных для графиков.')
        else pw.TableHelper.fromTextArray(
          headers: ['Показатель', 'Интервал', 'Среднее значение'],
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          data: trend.map((point) => [
            point['metric'] ?? '—',
            point['interval'] ?? '—',
            point['value'] ?? 'Нет данных',
          ]).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Header(level: 1, child: pw.Text('Фактические данные отдельных ночей')),
        pw.Text('Завершённых ночей в таблице: ${nights.length}'),
        if (nights.isEmpty) pw.Text('Нет завершённых ночных записей.')
        else pw.TableHelper.fromTextArray(
          headers: ['Дата', 'Засыпание', 'Пробуждение', 'Сон', 'Оценка', 'Эффективность', 'Пробуждения', 'Качество', 'Самочувствие'],
          cellStyle: const pw.TextStyle(fontSize: 6),
          headerStyle: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
          data: nights.map((night) => [
            night['date'] ?? '—',
            night['bedtime'] ?? '—',
            night['wake'] ?? '—',
            night['duration'] ?? '—',
            night['score'] ?? '—',
            night['efficiency'] ?? '—',
            night['awakenings'] ?? '—',
            night['quality'] ?? '—',
            night['wellbeing'] ?? '—',
          ]).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Каждый показатель использует собственную доступную выборку (n). Пропущенные значения обозначены тире и не заменяются нулём. Средние по интервалам отражают доступные завершённые ночи. Отчёт описывает наблюдения и не устанавливает причинно-следственные связи.',
          style: const pw.TextStyle(fontSize: 8)),
      ],
    ));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-analytics-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Аналитика сна Sleep Tracker');
  }

  /// Exports the immutable archived snapshot rather than recalculating a past
  /// period from records that may have been edited since the report was saved.
  static Future<void> exportPeriodicSnapshot(
    Map<String, Object?> snapshot,
    String title,
  ) async {
    double? number(Object? value) => value is num && value.toDouble().isFinite
        ? value.toDouble() : null;
    String duration(Object? value) {
      final minutes = number(value);
      if (minutes == null) return 'Нет данных';
      final rounded = minutes.round();
      return '${rounded ~/ 60} ч ${rounded.remainder(60)} мин';
    }
    String average(Object? value, {String suffix = ''}) {
      final parsed = number(value);
      return parsed == null ? 'Нет данных' : parsed.toStringAsFixed(1) + suffix;
    }

    final score = snapshot['score'] is Map ? Map<String, Object?>.from(snapshot['score'] as Map) : <String, Object?>{};
    final scoreComponents = score['components'] is Map ? Map<String, Object?>.from(score['components'] as Map) : <String, Object?>{};
    final previous = snapshot['previous'] is Map
        ? Map<String, Object?>.from(snapshot['previous'] as Map)
        : <String, Object?>{};
    final categories = snapshot['audioCategories'] is Map
        ? Map<String, Object?>.from(snapshot['audioCategories'] as Map)
        : <String, Object?>{};
    final notes = snapshot['notes'] is List
        ? (snapshot['notes'] as List).whereType<Map>().toList()
        : const <Map>[];
    final months = snapshot['months'] is List
        ? (snapshot['months'] as List).whereType<Map>().toList()
        : const <Map>[];
    final weeklyTrend = snapshot['weeklyTrend'] is List
        ? (snapshot['weeklyTrend'] as List).whereType<Map>().toList()
        : const <Map>[];
    final trendPoints = snapshot['trendPoints'] is List
        ? (snapshot['trendPoints'] as List).whereType<Map>().toList()
        : const <Map>[];
    final weekdayTrend = snapshot['weekdayTrend'] is List
        ? (snapshot['weekdayTrend'] as List).whereType<Map>().toList()
        : const <Map>[];
    final weekdayPatterns = snapshot['weekdayPatterns'] is List
        ? (snapshot['weekdayPatterns'] as List).whereType<Map>().toList()
        : const <Map>[];
    final tagPatterns = snapshot['tagPatterns'] is Map
        ? Map<String, Object?>.from(snapshot['tagPatterns'] as Map)
        : <String, Object?>{};
    final currentTagPatterns = tagPatterns['current'] is List
        ? (tagPatterns['current'] as List).whereType<Map>().toList()
        : const <Map>[];
    final previousTagPatterns = tagPatterns['previous'] is List
        ? (tagPatterns['previous'] as List).whereType<Map>().toList()
        : const <Map>[];
    const monthNames = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];

    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    final content = <pw.Widget>[
      pw.Header(level: 0, child: pw.Text('Sleep Tracker — $title')),
      pw.Text('Сохранённый периодический отчёт'),
      pw.SizedBox(height: 12),
      pw.Text('Завершённых ночей: ${snapshot['nights'] ?? 0}'),
      pw.Text('Средняя оценка сна: ${score['average'] is num ? (score['average'] as num).toStringAsFixed(0) + ' / 100' : 'Недостаточно данных'} · ночей с оценкой ${score['samples'] ?? 0}'),
      if (scoreComponents.isNotEmpty) ...[
        pw.Header(level: 1, child: pw.Text('Состав оценки сна')),
        ...scoreComponents.entries.map((entry) {
          final component = entry.value is Map ? Map<String, Object?>.from(entry.value as Map) : <String, Object?>{};
          final value = component['average'];
          return pw.Text('${component['label'] ?? entry.key}: ${value is num ? value.toStringAsFixed(0) + ' / 100' : 'Нет данных'} · выборка ${component['samples'] ?? 0}');
        }),
      ],
      if (const {'year', 'quarter', 'halfYear'}.contains(snapshot['kind']))
        pw.Text('Суммарная продолжительность сна: ${duration(snapshot['totalSleepMinutes'])}'),
      pw.Text('Средняя продолжительность сна: ${duration(snapshot['averageSleepMinutes'])} · выборка ${snapshot['sleepDurationSamples'] ?? 0}'),
      pw.Text('Среднее время в постели: ${duration(snapshot['averageTimeInBedMinutes'])} · выборка ${snapshot['timeInBedSamples'] ?? 0}'),
      pw.Text('Эффективность: ${average(snapshot['averageEfficiency'], suffix: '%')} · выборка ${snapshot['efficiencySamples'] ?? 0}'),
      pw.Text('Пробуждения: ${average(snapshot['averageAwakenings'])} · выборка ${snapshot['awakeningSamples'] ?? 0}'),
      pw.Text('Субъективное качество: ${average(snapshot['averageQuality'], suffix: ' / 5')} · оценок ${snapshot['qualitySamples'] ?? 0}'),
      pw.Text('Самочувствие: ${average(snapshot['averageWellbeing'], suffix: ' / 5')} · оценок ${snapshot['wellbeingSamples'] ?? 0}'),
      pw.Text('Звуковых событий: ${snapshot['audioEventCount'] ?? 0}'),
      pw.Text('Заметок: ${snapshot['noteCount'] ?? 0}'),
    ];
    if (previous.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Сравнение с предыдущим периодом')));
      content.add(pw.Text('Завершённых ночей: ${previous['nights'] ?? 0}'));
      final previousScore = previous['score'] is Map ? Map<String, Object?>.from(previous['score'] as Map) : <String, Object?>{};
      content.add(pw.Text('Средняя оценка сна: ${previousScore['average'] is num ? (previousScore['average'] as num).toStringAsFixed(0) + ' / 100' : 'Недостаточно данных'} · ночей с оценкой ${previousScore['samples'] ?? 0}'));
      content.add(pw.Text('Средняя продолжительность сна: ${duration(previous['averageSleepMinutes'])}'));
      content.add(pw.Text('Среднее время в постели: ${duration(previous['averageTimeInBedMinutes'])}'));
      content.add(pw.Text('Эффективность: ${average(previous['averageEfficiency'], suffix: '%')}'));
      content.add(pw.Text('Пробуждения: ${average(previous['averageAwakenings'])}'));
      content.add(pw.Text('Субъективное качество: ${average(previous['averageQuality'], suffix: ' / 5')}'));
      content.add(pw.Text('Самочувствие: ${average(previous['averageWellbeing'], suffix: ' / 5')}'));
    }
    final rankedInsights = snapshot['rankedInsights'] is List
        ? (snapshot['rankedInsights'] as List).whereType<Map>().toList()
        : const <Map>[];
    if (rankedInsights.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Что чаще связано с изменениями сна')));
      content.add(pw.Text('Ранжирование по повторяемости, объёму выборки и размеру различия. Это статистические наблюдения, а не доказательство причин.'));
      for (final raw in rankedInsights.take(12)) {
        final insight = Map<String, Object?>.from(raw);
        final key = insight['metricKey'] as String? ?? '';
        String shown(Object? rawValue) {
          if (rawValue is! num) return 'Нет данных';
          if (key == 'duration' || key == 'sleepLatency') {
            final value = rawValue.round();
            return '${value ~/ 60} ч ${value % 60} мин';
          }
          if (key == 'bedtime' || key == 'wakeTime') {
            final minute = rawValue.round() % 1440;
            return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
          }
          return rawValue.toStringAsFixed(1);
        }
        final difference = insight['difference'] as num? ?? 0;
        final delta = key == 'bedtime' || key == 'wakeTime'
          ? ((difference > 0 ? 'позже на ' : 'раньше на ') + difference.abs().round().toString() + ' мин')
          : ((difference > 0 ? 'выше на ' : 'ниже на ') + shown(difference.abs()));
        content.add(pw.Text(
          '${insight['rank']}. ${insight['tagLabel']} — ${insight['metricLabel']}: $delta; с отметкой ${shown(insight['withTagAverage'])} (n=${insight['withTagSamples']}); без отметки ${shown(insight['withoutTagAverage'])} (n=${insight['withoutTagSamples']})${insight['repeatsPreviousPeriod'] == true ? '; повторяется в предыдущем периоде' : ''}.',
        ));
      }
    }
    if (currentTagPatterns.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Персональные закономерности по отметкам')));
      content.add(pw.Text('Сравнение ночей с каждой отметкой и без неё. Наблюдаемая связь не доказывает причинность; для разницы требуется минимум 4 измерения в каждой группе.'));
      for (final rawPattern in currentTagPatterns) {
        final pattern = Map<String, Object?>.from(rawPattern);
        final key = pattern['tagKey'];
        final metrics = pattern['metrics'] is Map
            ? Map<String, Object?>.from(pattern['metrics'] as Map)
            : <String, Object?>{};
        final oldMatches = previousTagPatterns.where((item) => item['tagKey'] == key).toList();
        final oldMetrics = oldMatches.isEmpty || oldMatches.first['metrics'] is! Map
            ? <String, Object?>{}
            : Map<String, Object?>.from(oldMatches.first['metrics'] as Map);
        content.add(pw.SizedBox(height: 7));
        content.add(pw.Text('${pattern['label'] ?? key} · с отметкой: ${pattern['withTagNights'] ?? 0} ночей; без отметки: ${pattern['withoutTagNights'] ?? 0} ночей',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
        const metricLabels = <String, (String, String)>{
          'duration': ('Продолжительность', ' мин'),
          'score': ('Оценка сна', ' балла'),
          'awakenings': ('Пробуждения', ' эпиз.'),
          'efficiency': ('Эффективность сна', '%'),
          'sleepLatency': ('Задержка засыпания', ' мин'),
          'subjectiveQuality': ('Субъективное качество', ' / 5'),
          'wellbeing': ('Утреннее самочувствие', ' / 5'),
          'bedtime': ('Время засыпания', ''),
          'wakeTime': ('Время пробуждения', ''),
          'heartRate': ('Пульс', ' уд/мин'),
          'respiratoryRate': ('Частота дыхания', ' вдох/мин'),
          'bloodOxygen': ('Насыщение кислородом', '%'),
          'hrv': ('Вариабельность пульса SDNN', ' мс'),
          'roomTemperature': ('Температура датчика', ' °C'),
          'roomHumidity': ('Влажность датчика', '%'),
        };
        for (final metric in metricLabels.entries) {
          if (!metrics.containsKey(metric.key)) continue;
          final current = metrics[metric.key] is Map
              ? Map<String, Object?>.from(metrics[metric.key] as Map)
              : <String, Object?>{};
          final old = oldMetrics[metric.key] is Map
              ? Map<String, Object?>.from(oldMetrics[metric.key] as Map)
              : <String, Object?>{};
          final suffix = metric.value.$2;
          final label = metric.value.$1;
          String value(Object? raw) {
            if (metric.key == 'bedtime' || metric.key == 'wakeTime') {
              if (raw is! num) return 'Нет данных';
              final minute = raw.round() % 1440;
              return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
            }
            return average(raw, suffix: suffix);
          }
          final withValue = value(current['withTagAverage']);
          final withoutValue = value(current['withoutTagAverage']);
          final oldWith = value(old['withTagAverage']);
          final oldWithout = value(old['withoutTagAverage']);
          final deltaSuffix = metric.key == 'bedtime' || metric.key == 'wakeTime' ? ' мин' : suffix;
          final delta = current['difference'] is num
              ? ' · разница ${(current['difference'] as num) > 0 ? '+' : ''}${(current['difference'] as num).toStringAsFixed(1)}$deltaSuffix'
              : ' · недостаточно данных для разницы';
          content.add(pw.Text('$label: с отметкой $withValue (n=${current['withTagSamples'] ?? 0}); без отметки $withoutValue (n=${current['withoutTagSamples'] ?? 0})$delta'));
          content.add(pw.Text('Предыдущий период: с отметкой $oldWith; без отметки $oldWithout',
            style: const pw.TextStyle(fontSize: 8)));
        }
      }
    }
    if (categories.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Категории звуковых событий')));
      for (final entry in categories.entries) {
        content.add(pw.Text('${entry.key}: ${entry.value}'));
      }
    }
    if (months.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Динамика по месяцам')));
      content.add(pw.TableHelper.fromTextArray(
        headers: ['Месяц', 'Ночей', 'Сон средн.', 'Оценка', 'Эффект.', 'Пробужд.', 'Качество', 'Самочувствие'],
        cellStyle: const pw.TextStyle(fontSize: 7),
        headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        data: months.map((month) => [
          month['month'] is int && (month['month'] as int) >= 1 && (month['month'] as int) <= 12
              ? monthNames[(month['month'] as int) - 1] : '—',
          monthNightCount(Map<String, Object?>.from(month)).toString(),
          duration(month['averageSleepMinutes']),
          (month['score'] is Map && (month['score'] as Map)['average'] is num)
            ? ((month['score'] as Map)['average'] as num).toStringAsFixed(0) + ' / 100' : '—',
          average(month['averageEfficiency'], suffix: '%') + ' (' + (month['efficiencySamples'] ?? 0).toString() + ')',
          average(month['averageAwakenings']) + ' (' + (month['awakeningSamples'] ?? 0).toString() + ')',
          average(month['averageQuality'], suffix: '/5') + ' (' + (month['qualitySamples'] ?? 0).toString() + ')',
          average(month['averageWellbeing'], suffix: '/5') + ' (' + (month['wellbeingSamples'] ?? 0).toString() + ')',
        ]).toList(),
      ));
      content.add(pw.Text('Лучший и наиболее сложный месяцы ранжируются по средней продолжительности сна при наличии не менее 3 завершённых ночей в месяце. Это описательный критерий, не медицинская оценка.'));
    }
    if (weeklyTrend.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Динамика внутри месяца')));
      content.add(pw.TableHelper.fromTextArray(
        headers: ['Дни месяца', 'Ночей', 'Средний сон'],
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        data: weeklyTrend.map((bucket) => [
          '${bucket['dayFrom'] ?? '—'}–${bucket['dayTo'] ?? '—'}',
          bucket['sleepDurationSamples']?.toString() ?? '0',
          duration(bucket['averageSleepMinutes']),
        ]).toList(),
      ));
    }
    if (weekdayPatterns.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Средняя длительность по дням недели')));
      content.add(pw.TableHelper.fromTextArray(
        headers: ['День', 'Ночей', 'Средний сон'],
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        data: weekdayPatterns.map((pattern) => [
          pattern['label']?.toString() ?? '—',
          pattern['samples']?.toString() ?? '0',
          duration(pattern['averageSleepMinutes']),
        ]).toList(),
      ));
      content.add(pw.Text('Показываются только группы минимум с тремя измерениями; статистика описательная и не устанавливает причины изменений.'));
    }
    if (snapshot['kind'] == 'week' && trendPoints.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Динамика по дням недели')));
      content.add(pw.TableHelper.fromTextArray(
        headers: ['Дата', 'Ночей с измерением', 'Средний сон'],
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        data: trendPoints.map((point) => [
          point['label']?.toString() ?? '—',
          point['samples']?.toString() ?? '0',
          duration(point['sleepMinutes']),
        ]).toList(),
      ));
    }
    if (snapshot['kind'] == 'week' && weekdayTrend.isNotEmpty) {
      content.add(pw.SizedBox(height: 10));
      content.add(pw.Header(level: 1, child: pw.Text('Средняя длительность по дням недели')));
      content.add(pw.TableHelper.fromTextArray(
        headers: ['День', 'Ночей с измерением', 'Средний сон'],
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        data: weekdayTrend.map((point) => [
          point['label']?.toString() ?? '—',
          point['samples']?.toString() ?? '0',
          duration(point['sleepMinutes']),
        ]).toList(),
      ));
    }
    final nightlyBuckets = snapshot['kind'] == 'week' ? trendPoints
        : snapshot['kind'] == 'month' ? weeklyTrend : months;
    final nightlyRows = <List<String>>[];
    for (final bucket in nightlyBuckets) {
      final nights = (bucket['nights'] as List? ?? const []).whereType<Map>();
      for (final night in nights) {
        final date = DateTime.tryParse(night['startedAt']?.toString() ?? '');
        nightlyRows.add([
          date == null ? '—' : DateFormat('dd.MM.yyyy').format(date),
          duration(night['sleepMinutes']),
          night['score'] is num ? (night['score'] as num).toStringAsFixed(0) : 'Нет данных',
          average(night['efficiency'], suffix: '%'),
          night['awakenings'] is num ? (night['awakenings'] as num).toStringAsFixed(1) : 'Нет данных',
          average(night['quality'], suffix: ' / 5'),
          average(night['wellbeing'], suffix: ' / 5'),
        ]);
      }
    }
    if (nightlyRows.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Фактические данные отдельных ночей')));
      content.add(pw.TableHelper.fromTextArray(
        headers: ['Дата', 'Сон', 'Оценка', 'Эффективность', 'Пробуждения', 'Качество', 'Самочувствие'],
        cellStyle: const pw.TextStyle(fontSize: 7),
        headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        data: nightlyRows,
      ));
    }
    if (notes.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Header(level: 1, child: pw.Text('Заметки за период')));
      for (final note in notes) {
        final date = DateTime.tryParse(note['sessionStartedAt'] as String? ?? '');
        final text = note['text'] as String? ?? '';
        content.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text('${date == null ? '' : DateFormat('dd.MM.yyyy').format(date)}: $text',
            style: const pw.TextStyle(fontSize: 8)),
        ));
      }
    }
    content.add(pw.SizedBox(height: 12));
    content.add(pw.Text(
      'Оценка 0–100 использует веса 40/30/20/10: личная продолжительность, эффективность, число и суммарная длительность бодрствования, субъективное качество. ' 
      'Отсутствующие компоненты исключаются, оставшиеся веса нормализуются; оценка показывается минимум при двух компонентах и доступном исходном весе 50%. ' 
      'В компоненте пробуждений число и суммарная длительность бодрствования имеют равный вес; длительность достигает нулевой оценки на 120 минутах. Индивидуальный диапазон берётся из предыдущих 90 дней. Оценка не является медицинским заключением. ' 
      'Отчёт воспроизводит сохранённый снимок данных на момент формирования. '
      'Отсутствующие измерения не заменяются нулями. Показатели являются описательной аналитикой и не устанавливают медицинские диагнозы.',
      style: const pw.TextStyle(fontSize: 8),
    ));
    doc.addPage(pw.MultiPage(maxPages: 1000,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => content,
    ));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-periodic-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Sleep Tracker — $title');
  }


  static Future<void> exportHealthSnapshot(
    Map<String, Object?> snapshot,
    String title,
  ) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    final start = DateTime.parse(snapshot['start'] as String);
    final endExclusive = DateTime.parse(snapshot['endExclusive'] as String);
    final end = DateTime(endExclusive.year, endExclusive.month, endExclusive.day - 1);
    final metrics = (snapshot['metrics'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    final previous = snapshot['previous'] is Map
        ? Map<String, Object?>.from(snapshot['previous'] as Map)
        : <String, Object?>{};
    final previousMetrics = (previous['metrics'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    final previousByKey = {
      for (final metric in previousMetrics)
        '${metric['type']}::${metric['unit']}': metric,
    };
    String value(Object? raw) => raw is num ? raw.toStringAsFixed(1) : '—';

    final content = <pw.Widget>[
      pw.Text(title, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Text('Период: ${DateFormat('dd.MM.yyyy').format(start)} — ${DateFormat('dd.MM.yyyy').format(end)}'),
      pw.Text('Ночей с физиологическими измерениями: ${snapshot['nights'] ?? 0}'),
      pw.SizedBox(height: 12),
      pw.Text('Фактические показатели по ночам',
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 5),
    ];

    if (metrics.isEmpty) {
      content.add(pw.Text('За период нет пригодных физиологических измерений.'));
    } else {
      content.add(pw.Table.fromTextArray(
        headers: const ['Показатель', 'Ед.', 'Среднее', 'Медиана', 'Мин.', 'Макс.', 'Ночей', 'Измерений', 'Пред. период'],
        data: [
          for (final metric in metrics)
            [
              metric['type'] ?? '',
              metric['unit'] ?? '',
              value(metric['average']),
              value(metric['median']),
              value(metric['minimum']),
              value(metric['maximum']),
              metric['nightCount'] ?? 0,
              metric['measurementCount'] ?? 0,
              previousByKey['${metric['type']}::${metric['unit']}'] is Map
                  ? value((previousByKey['${metric['type']}::${metric['unit']}'] as Map)['average'])
                  : '—',
            ],
        ],
        headerStyle: pw.TextStyle(font: bold, fontSize: 7),
        cellStyle: pw.TextStyle(font: regular, fontSize: 7),
        headerDecoration: const pw.BoxDecoration(color: pdf.PdfColor(0.90, 0.92, 0.95)),
        cellAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.all(4),
      ));
      content.add(pw.SizedBox(height: 4));
      content.add(pw.Text(
        'Для предыдущего периода: ${previous['nights'] ?? 0} ночей с измерениями. '
        'Сравнение средних является описательным; число ночей и измерений указано отдельно.',
        style: pw.TextStyle(font: regular, fontSize: 8),
      ));
    }

    final trendPoints = (snapshot['trendPoints'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    if (trendPoints.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(pw.Text('Динамика внутри периода',
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)));
      for (final point in trendPoints) {
        final pointMetrics = (point['metrics'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, Object?>.from(row))
            .toList();
        if (pointMetrics.isEmpty) continue;
        content.add(pw.SizedBox(height: 6));
        content.add(pw.Text('${point['label'] ?? ''} · ${point['nights'] ?? 0} ночей',
          style: pw.TextStyle(font: bold, fontSize: 9)));
        content.add(pw.Table.fromTextArray(
          headers: const ['Показатель', 'Среднее', 'Ночей', 'Измерений', 'Единицы'],
          data: [
            for (final metric in pointMetrics)
              [
                metric['type'] ?? '',
                value(metric['average']),
                metric['nightCount'] ?? 0,
                metric['measurementCount'] ?? 0,
                metric['unit'] ?? '',
              ],
          ],
          headerStyle: pw.TextStyle(font: bold, fontSize: 7),
          cellStyle: pw.TextStyle(font: regular, fontSize: 7),
          headerDecoration: const pw.BoxDecoration(color: pdf.PdfColor(0.94, 0.95, 0.97)),
          cellPadding: const pw.EdgeInsets.all(3),
        ));
      }
    }

    content.add(pw.SizedBox(height: 14));
    content.add(pw.Text('Методика и ограничения',
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)));
    final notes = (snapshot['methodologyNotes'] as List? ?? const []).whereType<String>();
    for (final note in notes) {
      content.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text('• $note', style: pw.TextStyle(font: regular, fontSize: 8)),
      ));
    }
    content.add(pw.SizedBox(height: 8));
    content.add(pw.Text(
      'В отчёт включены только фактические измерения, сохранённые источником. '
      'Отсутствующие значения не заменяются нулями, редкие точки не интерполируются.',
      style: pw.TextStyle(font: regular, fontSize: 8),
    ));

    doc.addPage(pw.MultiPage(
      maxPages: 1000,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => content,
    ));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-health-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Sleep Tracker — $title',
    );
  }

  static Future<void> exportHistory({int days = 30, DateTime? from, DateTime? to, bool includeNotes = false}) async {
    if ((from == null) != (to == null)) {
      throw ArgumentError('Для произвольного периода укажите обе даты: начало и окончание.');
    }
    final now = DateTime.now();
    final rangeStart = from == null
        ? historyRangeStart(now: now, days: days)
        : DateTime(from.year, from.month, from.day);
    final rangeEndExclusive = to == null
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(to.year, to.month, to.day + 1);
    if (!rangeEndExclusive.isAfter(rangeStart)) {
      throw ArgumentError('Дата окончания отчёта должна быть не раньше даты начала.');
    }
    final sessions = await SleepDatabase.instance.getSessions(limit: null);
    final selected = sessions.where((s) =>
      !s.startedAt.isBefore(rangeStart) && s.startedAt.isBefore(rangeEndExclusive) && s.endedAt != null
    ).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final durations = selected.map((s) => s.duration!.inMinutes).toList();
    final stagesBySession = await SleepDatabase.instance.getStagesForSessions(
      selected.map((session) => session.id).toList(),
    );
    final nightMetrics = <String, SleepSessionMetrics>{
      for (final session in selected)
        session.id: SleepSessionMetrics.calculate(
          session: session,
          stages: stagesBySession[session.id] ?? const [],
        ),
    };
    // Include real physiological and bedroom-sensor samples already associated
    // with each night. Keep units separate and never infer missing data.
    final nightContext = <pw.Widget>[];
    for (final session in selected) {
      final healthSamples = await SleepDatabase.instance.getMetrics(session.id);
      final healthSummaries = SleepMetricSummary.fromSamples(healthSamples);
      final climateSamples = await SleepDatabase.instance.getClimateSamples(sessionId: session.id);
      final climateGroups = <(String, String), List<double>>{};
      for (final sample in climateSamples) {
        final type = sample['metric_type'];
        final unit = sample['unit'];
        final value = sample['value'];
        if (type is! String || unit is! String || value is! num || !value.toDouble().isFinite) continue;
        climateGroups.putIfAbsent((type, unit), () => []).add(value.toDouble());
      }
      if (healthSummaries.isEmpty && climateGroups.isEmpty) continue;
      nightContext.add(pw.SizedBox(height: 8));
      nightContext.add(pw.Text('Дополнительные измерения — ' + DateFormat('dd.MM.yyyy').format(session.startedAt),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)));
      for (final summary in healthSummaries) {
        nightContext.add(pw.Text(
          '• ' + summary.metricType + ': среднее ' + summary.average.toStringAsFixed(1) + ' ' + summary.unit + '; мин. ' + summary.minimum.toStringAsFixed(1) + '; макс. ' + summary.maximum.toStringAsFixed(1) + '; измерений: ' + summary.count.toString(),
          style: const pw.TextStyle(fontSize: 8),
        ));
      }
      for (final entry in climateGroups.entries) {
        final values = entry.value;
        final averageValue = values.reduce((a, b) => a + b) / values.length;
        final label = entry.key.$1 == 'temperature' ? 'Температура в спальне' : entry.key.$1 == 'humidity' ? 'Влажность в спальне' : entry.key.$1;
        nightContext.add(pw.Text(
          '• ' + label + ': среднее ' + averageValue.toStringAsFixed(1) + ' ' + entry.key.$2 + '; измерений: ' + values.length.toString(),
          style: const pw.TextStyle(fontSize: 8),
        ));
      }
    }
    final reports = <Map<String, Object?>>[];
    final selectedIds = selected.map((session) => session.id).toSet();
    final savedNotes = includeNotes
        ? (await SleepDatabase.instance.getNotes()).where((note) => selectedIds.contains(note.sessionId)).toList()
        : const [];
    for (final session in selected) { final report = await SleepDatabase.instance.getMorningReport(session.id); if (report != null) reports.add(report); }
    final wellbeing = reports.where((r) => r['wellbeing'] != null).map((r) => (r['wellbeing'] as num).toDouble()).toList();
    final quality = reports.where((r) => r['sleep_quality'] != null).map((r) => (r['sleep_quality'] as num).toDouble()).toList();
    final audio = await SleepDatabase.instance.getAudioEvents();
    final audioInPeriod = audio.where((r) {
      final date = DateTime.tryParse(r['captured_at'] as String? ?? '');
      return date != null && !date.isBefore(rangeStart) && date.isBefore(rangeEndExclusive);
    }).toList();
    final audioCounts = <String, int>{};
    for (final event in audioInPeriod) { final category = event['category'] as String? ?? 'unknown'; audioCounts[category] = (audioCounts[category] ?? 0) + 1; }
    final periodLabel = from != null && to != null
        ? 'с ${DateFormat('dd.MM.yyyy').format(rangeStart)} по ${DateFormat('dd.MM.yyyy').format(to)}'
        : days >= 3650 ? 'за весь период' : 'за последние $days дней';
    final average = durations.isEmpty ? null : durations.reduce((a,b) => a+b) / durations.length;
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(theme: pw.ThemeData.withFont(base: regular, bold: bold), build: (_) => [
      pw.Header(level: 0, child: pw.Text('Sleep Tracker — отчёт $periodLabel')),
      pw.Text('Сформирован: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}'),
      pw.SizedBox(height: 12),
      pw.Text('Количество завершённых ночей: ${selected.length}'),
      pw.Text('Средняя продолжительность: ${average == null ? 'нет данных' : '${(average / 60).toStringAsFixed(1)} ч'}'),
      pw.Text('Среднее самочувствие: ${wellbeing.isEmpty ? 'нет данных' : (wellbeing.reduce((a,b) => a+b) / wellbeing.length).toStringAsFixed(1)} / 5'),
      pw.Text('Среднее субъективное качество сна: ${quality.isEmpty ? 'нет данных' : (quality.reduce((a,b) => a+b) / quality.length).toStringAsFixed(1)} / 5'),
      pw.Text('Аудиособытий за период: ${audioInPeriod.length}'),
      ...audioCounts.entries.map((entry) => pw.Text('  ${entry.key}: ${entry.value}')),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Дата', 'Начало', 'Окончание', 'Сон', 'Пробуждения', 'Бодрствование', 'Латентность', 'Эффективность'],
        cellStyle: const pw.TextStyle(fontSize: 7),
        headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        data: selected.map((SleepSession s) {
          final metrics = nightMetrics[s.id]!;
          String minutes(int? value) => value == null ? '—' : '${value ~/ 60} ч ${value.remainder(60)} мин';
          return [
            DateFormat('dd.MM.yy').format(s.startedAt),
            DateFormat('HH:mm').format(s.startedAt),
            DateFormat('HH:mm').format(s.endedAt!),
            minutes(metrics.sleepDurationMinutes),
            metrics.awakeningCount.toString(),
            minutes(metrics.awakeStageMinutes),
            minutes(metrics.sleepLatencyMinutes),
            metrics.sleepEfficiencyPercent == null ? '—' : '${metrics.sleepEfficiencyPercent!.toStringAsFixed(0)}%',
          ];
        }).toList(),
      ),
      ...nightContext,
      if (savedNotes.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Header(level: 1, child: pw.Text('Заметки за период')),
        ...savedNotes.map((note) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(DateFormat('dd.MM.yyyy').format(note.sessionStartedAt), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text(note.text, style: const pw.TextStyle(fontSize: 8)),
          ]),
        )),
      ],
      pw.SizedBox(height: 10),
      pw.Text('Отчёт содержит только сохранённые данные. Отсутствующие показатели не моделируются. Погодный архив и астрономические расчёты отображаются в карточке ночи в приложении.'),
    ]));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-report-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Отчёт Sleep Tracker');
  }
}
