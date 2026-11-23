import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/sleep_session.dart';
import '../features/diary/sleep_session_metrics.dart';
import '../features/diary/sleep_metric_summary.dart';
import 'sleep_database.dart';

class PdfReportService {

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

    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    final content = <pw.Widget>[
      pw.Header(level: 0, child: pw.Text('Sleep Tracker — $title')),
      pw.Text('Сохранённый периодический отчёт'),
      pw.SizedBox(height: 12),
      pw.Text('Завершённых ночей: ${snapshot['nights'] ?? 0}'),
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
      content.add(pw.Text('Средняя продолжительность сна: ${duration(previous['averageSleepMinutes'])}'));
      content.add(pw.Text('Среднее время в постели: ${duration(previous['averageTimeInBedMinutes'])}'));
      content.add(pw.Text('Эффективность: ${average(previous['averageEfficiency'], suffix: '%')}'));
      content.add(pw.Text('Пробуждения: ${average(previous['averageAwakenings'])}'));
      content.add(pw.Text('Субъективное качество: ${average(previous['averageQuality'], suffix: ' / 5')}'));
      content.add(pw.Text('Самочувствие: ${average(previous['averageWellbeing'], suffix: ' / 5')}'));
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
        headers: ['Месяц', 'Ночей', 'Средний сон'],
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        data: months.map((month) => [
          month['month']?.toString() ?? '—',
          month['nights']?.toString() ?? '0',
          duration(month['averageSleepMinutes']),
        ]).toList(),
      ));
      content.add(pw.Text('Лучший и наиболее сложный месяцы ранжируются только по средней продолжительности сна. Это описательный критерий, не медицинская оценка.'));
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
      'Отчёт воспроизводит сохранённый снимок данных на момент формирования. '
      'Отсутствующие измерения не заменяются нулями. Унифицированный балл 0–100 '
      'не рассчитывается до отдельного согласования формулы.',
      style: const pw.TextStyle(fontSize: 8),
    ));
    doc.addPage(pw.MultiPage(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => content,
    ));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-periodic-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Sleep Tracker — $title');
  }

  static Future<void> exportHistory({int days = 30, DateTime? from, DateTime? to, bool includeNotes = false}) async {
    if ((from == null) != (to == null)) {
      throw ArgumentError('Для произвольного периода укажите обе даты: начало и окончание.');
    }
    final now = DateTime.now();
    final rangeStart = from == null
        ? (days >= 3650 ? DateTime.fromMillisecondsSinceEpoch(0) : now.subtract(Duration(days: days)))
        : DateTime(from.year, from.month, from.day);
    final rangeEndExclusive = to == null
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(to.year, to.month, to.day + 1);
    if (!rangeEndExclusive.isAfter(rangeStart)) {
      throw ArgumentError('Дата окончания отчёта должна быть не раньше даты начала.');
    }
    final sessions = await SleepDatabase.instance.getSessions(limit: 10000);
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
