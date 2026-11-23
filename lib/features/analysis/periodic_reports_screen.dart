import 'package:flutter/material.dart';
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
    final service = PeriodicReportService(widget.database);
    await service.generateClosedReports();
    return service.loadArchive();
  }
  void _refresh() => setState(() => _future = _load());
  Future<void> _export(PeriodicReportSnapshot report) async {
    await PdfReportService.exportPeriodicSnapshot(report.data, report.title);
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
    final weeklyTrend = report.data['weeklyTrend'] is List
      ? (report.data['weeklyTrend'] as List).whereType<Map>().toList() : const <Map>[];
    final weekdayPatterns = report.data['weekdayPatterns'] is List
      ? (report.data['weekdayPatterns'] as List).whereType<Map>().toList() : const <Map>[];
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
          if (report.kind == 'year' && report.totalSleepMinutes != null)
            _ReportLine(label: 'Суммарная продолжительность сна', value: _formatDuration(report.totalSleepMinutes)),
          _ReportLine(label: 'Средняя продолжительность сна · ' + (report.data['sleepDurationSamples'] ?? 0).toString() + ' измерений', value: duration),
          _ReportLine(label: 'Время в постели · ' + (report.data['timeInBedSamples'] ?? 0).toString() + ' ночей', value: _formatDuration(report.averageTimeInBedMinutes)),
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
            _ReportLine(label: 'Средняя продолжительность сна', value: duration + ' · ранее ' + _formatDuration(previous['averageSleepMinutes']) + ' (' + (previous['sleepDurationSamples'] ?? 0).toString() + ' изм.)'),
            _ReportLine(label: 'Время в постели', value: _formatDuration(report.averageTimeInBedMinutes) + ' · ранее ' + _formatDuration(previous['averageTimeInBedMinutes']) + ' (' + (previous['timeInBedSamples'] ?? 0).toString() + ' ночей)'),
            _ReportLine(label: 'Эффективность', value: _formatPercent(report.averageEfficiency) + ' · ранее ' + _formatPercent(_number(previous['averageEfficiency'])) + ' (' + (previous['efficiencySamples'] ?? 0).toString() + ' ночей)'),
            _ReportLine(label: 'Пробуждения', value: _formatNumber(report.averageAwakenings) + ' · ранее ' + _formatNumber(_number(previous['averageAwakenings'])) + ' (' + (previous['awakeningSamples'] ?? 0).toString() + ' ночей)'),
            _ReportLine(label: 'Качество сна', value: _formatScale(report.averageQuality) + ' · ранее ' + _formatScale(_number(previous['averageQuality'])) + ' (' + (previous['qualitySamples'] ?? 0).toString() + ' оценок)'),
            _ReportLine(label: 'Самочувствие', value: _formatScale(report.averageWellbeing) + ' · ранее ' + _formatScale(_number(previous['averageWellbeing'])) + ' (' + (previous['wellbeingSamples'] ?? 0).toString() + ' оценок)'),
          ],
          if (notes.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Заметки за период', style: TextStyle(fontWeight: FontWeight.w600)),
            ...notes.map((note) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(_formatNoteDate(DateTime.parse(note['sessionStartedAt'] as String)) + ': ' + (note['text'] as String? ?? ''),
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
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ReportLine(
                  label: PeriodicReportSnapshot.monthName(index) + ' · ' + (month['nights'] ?? 0).toString() + ' ночей',
                  value: _formatDuration(month['averageSleepMinutes']),
                ),
                if (month['averageEfficiency'] is num)
                  _ReportLine(label: '  Эффективность · ' + (month['efficiencySamples'] ?? 0).toString() + ' измерений', value: _formatPercent(_number(month['averageEfficiency']))),
                if (month['averageAwakenings'] is num)
                  _ReportLine(label: '  Пробуждения · ' + (month['awakeningSamples'] ?? 0).toString() + ' ночей', value: _formatNumber(_number(month['averageAwakenings']))),
                if (month['averageQuality'] is num)
                  _ReportLine(label: '  Качество сна · ' + (month['qualitySamples'] ?? 0).toString() + ' оценок', value: _formatScale(_number(month['averageQuality']))),
                if (month['averageWellbeing'] is num)
                  _ReportLine(label: '  Самочувствие · ' + (month['wellbeingSamples'] ?? 0).toString() + ' оценок', value: _formatScale(_number(month['averageWellbeing']))),
              ]);
            }),
            if (shortest is int && longest is int)
              Text(
                'Меньшая средняя длительность: ' + PeriodicReportSnapshot.monthName(shortest) +
                '. Большая средняя длительность: ' + PeriodicReportSnapshot.monthName(longest) +
                '. Критерий — средняя продолжительность при наличии не менее 3 ночей в месяце; это не оценка здоровья.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
          ],
          if (weeklyTrend.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Динамика внутри месяца', style: TextStyle(fontWeight: FontWeight.w600)),
            ...weeklyTrend.map((bucket) => _ReportLine(
              label: 'Дни ' + (bucket['dayFrom'] ?? '').toString() + '–' + (bucket['dayTo'] ?? '').toString() +
                ' · ' + (bucket['sleepDurationSamples'] ?? 0).toString() + ' ночей',
              value: _formatDuration(bucket['averageSleepMinutes']),
            )),
          ],
          if (weekdayPatterns.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Средняя длительность по дням недели', style: TextStyle(fontWeight: FontWeight.w600)),
            ...weekdayPatterns.map((pattern) => _ReportLine(
              label: (pattern['label'] ?? 'День').toString() + ' · ' + (pattern['samples'] ?? 0).toString() + ' ночей',
              value: _formatDuration(pattern['averageSleepMinutes']),
            )),
            const Text('Показываются только группы минимум с тремя фактическими измерениями; это описательная статистика, а не причинный вывод.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text('Выборка: ' + report.nights.toString() + ' ночей. Показатели рассчитываются только при наличии соответствующих измерений.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      )),
    );
  }

  static String _formatNoteDate(DateTime date) =>
      date.day.toString() + ' ' + PeriodicReportSnapshot.monthName(date.month) + ' ' + date.year.toString();

  static double? _number(Object? value) => value is num ? value.toDouble() : null;

  static String _formatPercent(double? value) => value == null ? 'Нет данных' : value.toStringAsFixed(1) + '%';
  static String _formatNumber(double? value) => value == null ? 'Нет данных' : value.toStringAsFixed(1);
  static String _formatScale(double? value) => value == null ? 'Нет данных' : value.toStringAsFixed(1) + ' / 5';

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
