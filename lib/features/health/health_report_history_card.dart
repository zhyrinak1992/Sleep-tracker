import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'health_report_service.dart';

class HealthReportHistoryCard extends StatefulWidget {
  const HealthReportHistoryCard({
    super.key,
    required this.reports,
    required this.onExport,
  });

  final Future<List<HealthReportSnapshot>> reports;
  final ValueChanged<HealthReportSnapshot> onExport;

  @override
  State<HealthReportHistoryCard> createState() => _HealthReportHistoryCardState();
}

class _HealthReportHistoryCardState extends State<HealthReportHistoryCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: FutureBuilder<List<HealthReportSnapshot>>(
      future: widget.reports,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <HealthReportSnapshot>[];
        final visibleItems = _showAll ? items : items.take(12).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Физиологические отчёты',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text(
              'Сохранённые сводки по фактическим измерениям Apple Health. Отсутствующие показатели не заменяются нулями.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting && items.isEmpty)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              Text('Не удалось загрузить историю отчётов: ${snapshot.error}',
                style: const TextStyle(color: AppTheme.accentPink, fontSize: 12))
            else if (items.isEmpty)
              const Text(
                'Отчёты появятся после завершения недели, месяца или календарного года, если за период есть физиологические измерения.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
              )
            else ...[
              ...visibleItems.map((report) {
                final end = report.endInclusive;
                final range = '${DateFormat('dd.MM.yyyy').format(report.start)} — ${DateFormat('dd.MM.yyyy').format(end)}';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(report.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${report.nights} ночей · ${report.metrics.length} показателей\n$range',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
                  ),
                  trailing: IconButton(
                    tooltip: 'Экспорт отчёта в PDF',
                    onPressed: () => widget.onExport(report),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                );
              }),
              if (items.length > 12)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Свернуть список' : 'Показать все отчёты (${items.length})'),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}
