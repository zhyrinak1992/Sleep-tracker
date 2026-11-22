import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/sleep_session.dart';
import '../features/diary/sleep_session_metrics.dart';
import 'sleep_database.dart';

class PdfReportService {
  static Future<void> exportHistory({int days = 30, DateTime? from, DateTime? to}) async {
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
    final reports = <Map<String, Object?>>[];
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
      pw.SizedBox(height: 10),
      pw.Text('Отчёт содержит только сохранённые данные. Отсутствующие показатели не моделируются.'),
    ]));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'SleepTracker-report-${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Отчёт Sleep Tracker');
  }
}
