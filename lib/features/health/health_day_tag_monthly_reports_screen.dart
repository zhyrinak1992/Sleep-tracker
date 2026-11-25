import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'health_day_tag_monthly_report.dart';

class HealthDayTagMonthlyReportsScreen extends StatefulWidget {
  const HealthDayTagMonthlyReportsScreen({super.key, required this.database});

  final SleepDatabase database;

  @override
  State<HealthDayTagMonthlyReportsScreen> createState() =>
      _HealthDayTagMonthlyReportsScreenState();
}

class _HealthDayTagMonthlyReportsScreenState
    extends State<HealthDayTagMonthlyReportsScreen> {
  late Future<List<HealthDayTagMonthlyReport>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = _loadReports();
  }

  Future<List<HealthDayTagMonthlyReport>> _loadReports() =>
      HealthDayTagMonthlyReportService(widget.database).generateClosedReports();

  Future<void> _refresh() async {
    setState(() => _reports = _loadReports());
    await _reports;
  }

  String _monthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    const months = [
      'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
      'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
    ];
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return key;
    return '${months[month - 1]} ${parts[0]}';
  }

  String _share(double? value) =>
      value == null ? 'нет данных' : '${value.toStringAsFixed(1)}%';

  String _difference(double? value) {
    if (value == null) return 'нет сравнимых данных';
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} п. п.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<List<HealthDayTagMonthlyReport>>(
        future: _reports,
        builder: (context, snapshot) {
          final reports = snapshot.data ?? const <HealthDayTagMonthlyReport>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Назад'),
                ),
              ),
              ScreenHeader(
                title: 'Отчёты по отметкам',
                subtitle: 'Новые закрытые месяцы формируются при открытии раздела; фоновый запуск зависит от iOS',
                icon: Icons.event_note_rounded,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Обновить',
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 4),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SectionCard(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                SectionCard(
                  child: Text('Не удалось загрузить отчёты: ${snapshot.error}'),
                )
              else if (reports.isEmpty)
                const SectionCard(
                  child: Text(
                    'Месячные отчёты появятся после закрытия календарного месяца, когда в календаре здоровья будут сохранены дневные записи.',
                    style: TextStyle(color: AppTheme.muted, height: 1.45),
                  ),
                )
              else
                for (final report in reports)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SectionCard(
                      padding: EdgeInsets.zero,
                      child: ExpansionTile(
                        initiallyExpanded: reports.first == report,
                        title: Text(
                          _monthLabel(report.monthKey),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${report.recordedDays} из ${report.daysInMonth} дней с дневными записями',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        children: [
                          if (report.recordedDays == 0)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'За этот месяц дневных записей нет. Частота отметок не рассчитывается.',
                                style: TextStyle(color: AppTheme.muted, fontSize: 12),
                              ),
                            )
                          else if (report.tags.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Дневные записи есть, но отметки в этом месяце не использовались.',
                                style: TextStyle(color: AppTheme.muted, fontSize: 12),
                              ),
                            )
                          else
                            for (final entry in report.tags) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  entry.tag,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(children: [
                                const SizedBox(width: 82, child: Text('Этот месяц',
                                  style: TextStyle(color: AppTheme.muted, fontSize: 10))),
                                Expanded(child: LinearProgressIndicator(
                                  value: entry.share == null ? 0 : (entry.share! / 100).clamp(0.0, 1.0),
                                  minHeight: 7,
                                  color: AppTheme.teal,
                                  backgroundColor: AppTheme.surfaceLight,
                                  borderRadius: BorderRadius.circular(5),
                                )),
                                const SizedBox(width: 8),
                                SizedBox(width: 52, child: Text(_share(entry.share),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 10))),
                              ]),
                              const SizedBox(height: 5),
                              Row(children: [
                                const SizedBox(width: 82, child: Text('Прошлый',
                                  style: TextStyle(color: AppTheme.muted, fontSize: 10))),
                                Expanded(child: LinearProgressIndicator(
                                  value: entry.previousShare == null ? 0 : (entry.previousShare! / 100).clamp(0.0, 1.0),
                                  minHeight: 7,
                                  color: const Color(0xFFB9A7FF),
                                  backgroundColor: AppTheme.surfaceLight,
                                  borderRadius: BorderRadius.circular(5),
                                )),
                                const SizedBox(width: 8),
                                SizedBox(width: 52, child: Text(_share(entry.previousShare),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 10))),
                              ]),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${entry.days} дней с отметкой · прошлый месяц: ${entry.previousDays} дней · ${_difference(entry.differencePercentagePoints)}',
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 10,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Сравнение долей учитывает только дни с сохранёнными дневными записями. Частота отметок не доказывает их влияние на сон.',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    ),
  );
}
