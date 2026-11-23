import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/pdf_report_service.dart';
import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'periodic_report_service.dart';

class PeriodicReportsScreen extends StatefulWidget {
  const PeriodicReportsScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<PeriodicReportsScreen> createState() => _PeriodicReportsScreenState();
}

class _PeriodicReportsScreenState extends State<PeriodicReportsScreen> {
  late Future<List<PeriodicReportSnapshot>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<PeriodicReportSnapshot>> _load() async {
    return PeriodicReportService(widget.database).loadArchive();
  }
  void _refresh() => setState(() => _future = _load());
  Future<void> _export(PeriodicReportSnapshot report) async {
    await PdfReportService.exportHistory(
      from: report.start,
      to: report.endExclusive.subtract(const Duration(days: 1)),
      includeNotes: true,
    );
  }
  String _duration(double? minutes) {
    if (minutes == null) return 'Нет данных';
    final value = minutes.round();
    return (value ~/ 60).toString() + ' ч ' + (value % 60).toString() + ' мин';
  }
  String _average(double? value, String suffix) =>
      value == null ? 'Нет данных' : value.toStringAsFixed(1) + suffix;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Периодические отчёты'), actions: [
      IconButton(tooltip: 'Обновить', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: FutureBuilder<List<PeriodicReportSnapshot>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Не удалось сформировать архив отчётов: ' + snapshot.error.toString()),
        ));
        final reports = snapshot.data ?? const <PeriodicReportSnapshot>[];
        if (reports.isEmpty) return const Center(child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('Здесь будут сохраняться недельные, месячные и годовые отчёты после завершения соответствующих периодов.'),
        ));
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const ScreenHeader(title: 'История отчётов', subtitle: 'Сохранённые сводки по завершённым периодам', icon: Icons.auto_graph_rounded),
            const SizedBox(height: 8),
            ...reports.map((report) => _ReportCard(
              report: report,
              duration: _duration(report.averageSleepMinutes),
              average: _average,
              onExport: () => _export(report),
            )),
            const SizedBox(height: 10),
            const Text(
              'Отчёты создаются при открытии этого раздела. Если приложение было закрыто в день окончания периода, пропущенные отчёты будут сформированы при следующем открытии. iOS не гарантирует запуск приложения в фоне по расписанию. Отчёты используют только сохранённые данные; показатель 0–100 появится после отдельного согласования формулы.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
            ),
          ],
        );
      },
    ),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.duration, required this.average, required this.onExport});
  final PeriodicReportSnapshot report;
  final String duration;
  final String Function(double?, String) average;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final previous = report.data['previous'] is Map
      ? Map<String, Object?>.from(report.data['previous'] as Map) : <String, Object?>{};
    final categories = report.data['audioCategories'] is Map
      ? Map<String, Object?>.from(report.data['audioCategories'] as Map) : <String, Object?>{};
    final notes = report.data['notes'] is List
      ? (report.data['notes'] as List).whereType<Map>().toList() : const <Map>[];
    final months = report.data['months'] is List
      ? (report.data['months'] as List).whereType<Map>().toList() : const <Map>[];
    final monthNames = DateFormat.MMMM('ru');
    final shortest = report.data['shortestAverageMonth'];
    final longest = report.data['longestAverageMonth'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(report.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(tooltip: 'Экспорт PDF', onPressed: onExport, icon: const Icon(Icons.picture_as_pdf_outlined)),
          ]),
          const SizedBox(height: 10),
          _ReportLine(label: 'Завершённых ночей', value: report.nights.toString()),
          _ReportLine(label: 'Средняя продолжительность · ' + (report.data['sleepDurationSamples'] ?? 0).toString() + ' ночей', value: duration),
          _ReportLine(label: 'Эффективность · ' + (report.data['efficiencySamples'] ?? 0).toString() + ' ночей', value: average(report.averageEfficiency, '%')),
          _ReportLine(label: 'Пробуждения · ' + (report.data['awakeningSamples'] ?? 0).toString() + ' ночей', value: average(report.averageAwakenings, '')),
          _ReportLine(label: 'Субъективное качество · ' + (report.data['qualitySamples'] ?? 0).toString() + ' оценок', value: average(report.averageQuality, ' / 5')),
          _ReportLine(label: 'Самочувствие · ' + (report.data['wellbeingSamples'] ?? 0).toString() + ' оценок', value: average(report.averageWellbeing, ' / 5')),
          _ReportLine(label: 'Звуковые события', value: (report.data['audioEventCount'] ?? 0).toString()),
          _ReportLine(label: 'Заметки', value: (report.data['noteCount'] ?? 0).toString()),
          if (previous.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Сравнение с предыдущим периодом', style: TextStyle(fontWeight: FontWeight.w600)),
            _ReportLine(label: 'Ночей', value: report.nights.toString() + ' · ранее ' + (previous['nights'] ?? 0).toString()),
            _ReportLine(label: 'Средняя продолжительность', value: duration + ' · ранее ' + _formatDuration(previous['averageSleepMinutes'])),
          ],
          if (notes.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Заметки за период', style: TextStyle(fontWeight: FontWeight.w600)),
            ...notes.map((note) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(DateFormat('d MMM yyyy', 'ru').format(DateTime.parse(note['sessionStartedAt'] as String)) + ': ' + (note['text'] as String? ?? ''),
                style: const TextStyle(fontSize: 12, height: 1.4)),
            )),
          ],
          if (categories.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Категории звуковых событий', style: TextStyle(fontWeight: FontWeight.w600)),
            ...categories.entries.map((entry) => _ReportLine(label: entry.key, value: entry.value.toString())),
          ],
          if (months.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Динамика по месяцам', style: TextStyle(fontWeight: FontWeight.w600)),
            ...months.map((month) {
              final index = month['month'] as int;
              final value = (month['averageSleepMinutes'] as num?)?.toDouble();
              return _ReportLine(label: monthNames.format(DateTime(report.start.year, index)),
                value: value == null ? 'Нет данных' : _formatDuration(value));
            }),
            if (shortest is int && longest is int)
              Text(
                'Меньшая средняя длительность: ' + monthNames.format(DateTime(report.start.year, shortest)) +
                '. Большая средняя длительность: ' + monthNames.format(DateTime(report.start.year, longest)) +
                '. Критерий — средняя продолжительность, не оценка здоровья.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
          ],
          const SizedBox(height: 6),
          Text('Выборка: ' + report.nights.toString() + ' ночей. Показатели рассчитываются только при наличии соответствующих измерений.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      )),
    );
  }

  static String _formatDuration(Object? value) {
    if (value is! num) return 'Нет данных';
    final minutes = value.round();
    return minutes.toString() + ' мин (' + (minutes ~/ 60).toString() + ' ч ' + (minutes % 60).toString() + ' мин)';
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
    ]),
  );
}
