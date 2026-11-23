import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';
import 'sleep_analytics.dart';
import 'individual_sleep_need_card.dart';
import 'weekday_comparison_screen.dart';
import 'moon_phase_screen.dart';
import 'climate_analytics.dart';
import 'climate_trend_chart.dart';
import 'daytime_sleep_card.dart';
import 'activity_summary_card.dart';
import 'activity_analysis_card.dart';
import 'screen_time_analysis_card.dart';
import 'weather_analysis_card.dart';
import 'sleep_period_comparison_screen.dart';
import 'tag_sleep_comparison_card.dart';
import 'sleep_regularity_analysis.dart';
import 'sleep_achievements_card.dart';
import 'audio_event_analysis_card.dart';
import 'periodic_report_service.dart';
import 'periodic_reports_screen.dart';
import '../diary/sleep_session_detail_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late Future<List<SleepSession>> _future;
  AnalysisPeriod _period = AnalysisPeriod.week;
  DateTime _anchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = widget.database.getSessions(limit: 10000);
    unawaited(_generateClosedReports());
  }

  void _reload() {
    setState(() => _future = widget.database.getSessions(limit: 10000));
    unawaited(_generateClosedReports());
  }

  Future<void> _generateClosedReports() async {
    try {
      await PeriodicReportService(widget.database).generateClosedReports();
    } catch (_) {
      // Report generation must not block the primary analysis screen.
    }
  }

  void _shift(int direction) {
    final start = SleepAnalytics.periodStart(_anchor, _period);
    setState(() => _anchor = direction < 0
        ? SleepAnalytics.previousPeriodStart(start, _period)
        : SleepAnalytics.nextPeriodStart(start, _period));
  }

  DateTime _bucketStart(DateTime periodStart, int index) {
    if (_period == AnalysisPeriod.week) return periodStart.add(Duration(days: index));
    if (_period == AnalysisPeriod.month) {
      return DateTime(periodStart.year, periodStart.month, index * 7 + 1);
    }
    return DateTime(periodStart.year, index + 1);
  }

  DateTime _bucketEnd(DateTime periodStart, int index) {
    if (_period == AnalysisPeriod.week) return periodStart.add(Duration(days: index + 1));
    if (_period == AnalysisPeriod.year) return DateTime(periodStart.year, index + 2);
    final next = DateTime(periodStart.year, periodStart.month, (index + 1) * 7 + 1);
    final monthEnd = DateTime(periodStart.year, periodStart.month + 1);
    return next.isBefore(monthEnd) ? next : monthEnd;
  }

  Future<void> _showChartDetails(
    BuildContext context,
    List<SleepSession> all,
    DateTime currentPeriodStart,
    DateTime previousPeriodStart,
    int index,
  ) async {
    List<SleepSession> bucket(DateTime periodStart) {
      final from = _bucketStart(periodStart, index);
      final to = _bucketEnd(periodStart, index);
      return all.where((session) =>
        !session.startedAt.isBefore(from) && session.startedAt.isBefore(to) &&
        session.duration != null && session.duration!.inMinutes > 0).toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    }

    final currentSessions = bucket(currentPeriodStart);
    final previousSessions = bucket(previousPeriodStart);
    double? average(List<SleepSession> sessions) => sessions.isEmpty ? null :
      sessions.fold<int>(0, (sum, item) => sum + item.duration!.inMinutes) / sessions.length;
    String averageLabel(List<SleepSession> sessions) {
      final value = average(sessions);
      return value == null ? 'Нет данных' : _duration(value);
    }
    String bucketTitle(DateTime start, DateTime end) =>
      '${DateFormat('d MMM', 'ru').format(start)} — ${DateFormat('d MMM', 'ru').format(end.subtract(const Duration(days: 1)))}';

    Widget sessionList(List<SleepSession> sessions) {
      if (sessions.isEmpty) return const Text('Нет завершённых записей', style: TextStyle(color: AppTheme.muted));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: sessions.map((session) =>
        Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
          SizedBox(width: 48, child: Text(DateFormat('HH:mm').format(session.startedAt), style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(_duration(session.duration!.inMinutes.toDouble()))),
          if (session.morningRating != null) Text('Оценка ${session.morningRating}/5', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]))).toList());
    }

    final currentFrom = _bucketStart(currentPeriodStart, index);
    final currentTo = _bucketEnd(currentPeriodStart, index);
    final previousFrom = _bucketStart(previousPeriodStart, index);
    final previousTo = _bucketEnd(previousPeriodStart, index);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_period == AnalysisPeriod.week
          ? DateFormat('EEEE, d MMMM', 'ru').format(currentFrom)
          : _period == AnalysisPeriod.month
              ? 'Неделя ${index + 1} месяца'
              : DateFormat('LLLL yyyy', 'ru').format(currentFrom)),
        content: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Текущий период · ${bucketTitle(currentFrom, currentTo)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('Средняя длительность: ${averageLabel(currentSessions)}'),
            Text('Завершённых ночей: ${currentSessions.length}'),
            sessionList(currentSessions),
            const Divider(height: 24),
            Text('Предыдущий период · ${bucketTitle(previousFrom, previousTo)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('Средняя длительность: ${averageLabel(previousSessions)}'),
            Text('Завершённых ночей: ${previousSessions.length}'),
            sessionList(previousSessions),
          ],
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
      ),
    );
  }

  String _periodTitle(DateTime start) {
    if (_period == AnalysisPeriod.week) {
      final end = start.add(const Duration(days: 6));
      return '${DateFormat('d MMM', 'ru').format(start)} — ${DateFormat('d MMM', 'ru').format(end)}';
    }
    if (_period == AnalysisPeriod.year) return start.year.toString();
    return DateFormat('LLLL yyyy', 'ru').format(start);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _future,
    builder: (context, snapshot) {
      final all = snapshot.data ?? const <SleepSession>[];
      final start = SleepAnalytics.periodStart(_anchor, _period);
      final current = SleepAnalytics.summarize(all, start, _period);
      final previousStart = SleepAnalytics.previousPeriodStart(start, _period);
      final previous = SleepAnalytics.summarize(all, previousStart, _period);
      final chart = SleepAnalytics.chartValues(current, _period);
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Анализ',
            subtitle: 'Динамика по сохранённым данным',
            icon: Icons.insights_rounded,
          ),
          const SizedBox(height: 2),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WeekdayComparisonScreen(database: widget.database),
            )),
            icon: const Icon(Icons.date_range_outlined),
            label: const Text('Сравнить сон по дням недели'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MoonPhaseScreen(database: widget.database),
            )),
            icon: const Icon(Icons.nightlight_round),
            label: const Text('Сопоставить сон с фазами Луны'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SleepPeriodComparisonScreen(database: widget.database),
            )),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Сравнить любые два периода'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PeriodicReportsScreen(database: widget.database),
            )),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Периодические отчёты'),
          ),
          const SizedBox(height: 18),
          SegmentedButton<AnalysisPeriod>(
            segments: const [
              ButtonSegment(value: AnalysisPeriod.week, label: Text('Неделя')),
              ButtonSegment(value: AnalysisPeriod.month, label: Text('Месяц')),
              ButtonSegment(value: AnalysisPeriod.year, label: Text('Год')),
            ],
            selected: {_period},
            onSelectionChanged: (value) => setState(() {
              _period = value.first;
              _anchor = DateTime.now();
            }),
          ),
          const SizedBox(height: 12),
          Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Center(child: Text(_periodTitle(start), style: const TextStyle(fontWeight: FontWeight.w600)))),
            IconButton(
              onPressed: start.isBefore(SleepAnalytics.periodStart(DateTime.now(), _period)) ? () => _shift(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(tooltip: 'Обновить данные', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
          ]),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (snapshot.hasError)
            SectionCard(child: Text('Не удалось загрузить аналитику: ${snapshot.error}'))
          else ...[
            _MetricCard(
              title: 'Средняя длительность',
              value: _duration(current.averageDurationMinutes),
              detail: '${current.completed} завершённых ${_nightWord(current.completed)}',
              currentValue: current.averageDurationMinutes,
              previousValue: previous.averageDurationMinutes,
              unit: 'мин',
            ),
            const SizedBox(height: 10),
            _MetricCard(
              title: 'Средняя оценка самочувствия',
              value: current.averageRating == null ? 'Нет оценок' : '${current.averageRating!.toStringAsFixed(1)} из 5',
              detail: '${current.rated} ${_ratingWord(current.rated)}',
              currentValue: current.averageRating,
              previousValue: previous.averageRating,
              unit: 'балл',
            ),
            const SizedBox(height: 14),
            SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _period == AnalysisPeriod.year
                    ? 'Продолжительность по месяцам'
                    : _period == AnalysisPeriod.month
                        ? 'Продолжительность по неделям'
                        : 'Продолжительность по дням',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _period == AnalysisPeriod.year
                    ? 'Среднее за каждый календарный месяц · шкала 0–12 ч'
                    : _period == AnalysisPeriod.month
                        ? 'Среднее по неделям месяца · шкала 0–12 ч'
                        : 'Среднее по дням недели · шкала 0–12 ч',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              SizedBox(height: 150, child: _DurationChart(values: chart, period: _period, onTap: (index) => _showChartDetails(context, all, start, previousStart, index))),
            ])),
            const SizedBox(height: 14),
            SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Сравнение с предыдущим периодом', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _ComparisonRow(label: 'Завершённые ночи', current: '${current.completed}', previous: '${previous.completed}'),
              const Divider(height: 20, color: AppTheme.surfaceLight),
              _ComparisonRow(label: 'Ночи с оценкой', current: '${current.rated}', previous: '${previous.rated}'),
              const SizedBox(height: 8),
              const Text('Сравнение рассчитывается отдельно для каждого показателя. Нет данных — нет процента изменения. Длительность учитывается только для завершённых сессий, оценка — только там, где она действительно сохранена.', style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
            ])),
            const SizedBox(height: 14),
            // Регулярность оценивается по всей доступной истории, а не по выбранной неделе/месяцу:
            // иначе порог в 7 ночей недостижим для большинства недельных срезов.
            _RegularityCard(sessions: all, database: widget.database),
            const SizedBox(height: 14),
            TagSleepComparisonCard(
              database: widget.database,
              sessions: current.sessions,
              start: start,
              endExclusive: SleepAnalytics.nextPeriodStart(start, _period),
            ),
            const SizedBox(height: 14),
            SleepAchievementsCard(sessions: all),
            const SizedBox(height: 14),
            IndividualSleepNeedCard(database: widget.database),
            const SizedBox(height: 14),
            DaytimeSleepCard(database: widget.database, sessions: current.sessions),
            const SizedBox(height: 14),
            ActivitySummaryCard(database: widget.database),
            const SizedBox(height: 14),
            ActivityAnalysisCard(database: widget.database, sessions: current.sessions),
            const SizedBox(height: 14),
            ScreenTimeAnalysisCard(database: widget.database, sessions: current.sessions),
            const SizedBox(height: 14),
            WeatherAnalysisCard(database: widget.database, sessions: current.sessions),
            const SizedBox(height: 14),
            _ClimateSummary(database: widget.database),
            const SizedBox(height: 14),
            AudioEventAnalysisCard(
              database: widget.database,
              currentSessions: current.sessions,
              previousSessions: previous.sessions,
            ),
            const SizedBox(height: 12),
            const Text('Подробные физиологические измерения и сравнение периодов доступны в разделе «Моё здоровье». Фазы сна и показатели отдельной ночи — в карточке этой ночи.', style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
          ],
        ],
      );
    },
  );
}

String _duration(double? minutes) {
  if (minutes == null) return 'Недостаточно данных';
  final value = minutes.round();
  return '${value ~/ 60} ч ${value % 60} мин';
}

String _nightWord(int count) {
  final n = count % 10;
  final n100 = count % 100;
  if (n == 1 && n100 != 11) return 'ночь';
  if (n >= 2 && n <= 4 && (n100 < 12 || n100 > 14)) return 'ночи';
  return 'ночей';
}

String _ratingWord(int count) => count == 1 ? 'оценка' : (count >= 2 && count <= 4 ? 'оценки' : 'оценок');

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.detail, required this.currentValue, required this.previousValue, required this.unit});
  final String title, value, detail, unit;
  final double? currentValue;
  final double? previousValue;

  @override
  Widget build(BuildContext context) {
    final hasComparison = currentValue != null && previousValue != null;
    String? changeLabel;
    IconData? changeIcon;
    Color? changeColor;
    if (hasComparison) {
      final difference = currentValue! - previousValue!;
      if (unit == 'мин' && previousValue! > 0) {
        final percent = difference / previousValue! * 100;
        changeLabel = '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(0)}%';
      } else if (unit == 'балл') {
        changeLabel = '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(1)} балла';
      }
      if (difference > 0) {
        changeIcon = Icons.trending_up_rounded;
        changeColor = AppTheme.teal;
      } else if (difference < 0) {
        changeIcon = Icons.trending_down_rounded;
        changeColor = const Color(0xFFFFA6B5);
      } else {
        changeIcon = Icons.trending_flat_rounded;
        changeColor = AppTheme.muted;
      }
    }
    return SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AppTheme.muted)),
      const SizedBox(height: 7),
      Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(child: Text(detail, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        if (hasComparison && changeLabel != null) ...[
          Icon(changeIcon, size: 16, color: changeColor),
          const SizedBox(width: 3),
          Text(changeLabel, style: TextStyle(color: changeColor, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ]),
      if (previousValue != null) ...[
        const SizedBox(height: 5),
        Text('Предыдущий период: ${unit == 'мин' ? _duration(previousValue) : '${previousValue!.toStringAsFixed(1)} из 5'}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ],
    ]));
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.label, required this.current, required this.previous});
  final String label, current, previous;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
    Text(current, style: const TextStyle(fontWeight: FontWeight.w600)),
    const SizedBox(width: 12),
    Text('пред. $previous', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
  ]);
}

class _DurationChart extends StatelessWidget {
  const _DurationChart({required this.values, required this.period, required this.onTap});
  final List<double?> values;
  final AnalysisPeriod period;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final labels = switch (period) {
      AnalysisPeriod.week => const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      AnalysisPeriod.month => List.generate(5, (i) => '${i + 1} нед.'),
      AnalysisPeriod.year => const ['Ян', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'],
    };
    const maxValue = 720.0; // Единая шкала 0–12 часов для сопоставимости периодов.
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(values.length, (i) {
      final value = values[i];
      final height = value == null ? 0.0 : (value / maxValue * 104).clamp(0.0, 104.0).toDouble();
      return Expanded(child: InkWell(onTap: () => onTap(i), borderRadius: BorderRadius.circular(10), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (value != null) Text('${(value / 60).toStringAsFixed(1).replaceAll('.', ',')} ч', style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
        const SizedBox(height: 5),
        Container(height: 108, alignment: Alignment.bottomCenter, child: Container(
          height: height,
          width: 18,
          decoration: BoxDecoration(color: value == null ? AppTheme.surfaceLight : AppTheme.teal, borderRadius: BorderRadius.circular(7)),
        )),
        const SizedBox(height: 8),
        Text(labels[i], style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
      ])));
    }));
  }
}


class _ClimateSummary extends StatelessWidget {
  const _ClimateSummary({required this.database});
  final SleepDatabase database;

  Future<List<Map<String, Object?>>> _loadSamples() async {
    final selectedDevice = await database.getAppMetadata('yandex_selected_device_id');
    if (selectedDevice == null || selectedDevice.isEmpty) return const [];
    return database.getClimateSamples(
      deviceId: selectedDevice,
      from: DateTime.now().subtract(const Duration(days: 30)),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: _loadSamples(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const SectionCard(child: LinearProgressIndicator());
      if (snapshot.hasError) return SectionCard(child: Text('Не удалось загрузить климатические измерения: ${snapshot.error}'));
      final samples = snapshot.data ?? const <Map<String, Object?>>[];
      final temperature = ClimateMetricSummary.fromSamples(
        samples, metricType: 'temperature', expectedInterval: const Duration(minutes: 15),
      );
      final humidity = ClimateMetricSummary.fromSamples(
        samples, metricType: 'humidity', expectedInterval: const Duration(minutes: 15),
      );
      return SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Микроклимат спальни', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        const Text('Показания выбранного датчика за последние 30 дней', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 12),
        _ClimateMetricLine(title: 'Температура', summary: temperature, samples: samples, metricType: 'temperature'),
        const Divider(height: 18, color: AppTheme.surfaceLight),
        _ClimateMetricLine(title: 'Влажность', summary: humidity, samples: samples, metricType: 'humidity'),
        const SizedBox(height: 8),
        Text('Всего измерений: ${samples.length}. Новые значения появляются при доступности датчика и работе приложения. Отсутствующие интервалы не заполняются искусственными данными.',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
      ]));
    },
  );
}

class _ClimateMetricLine extends StatelessWidget {
  const _ClimateMetricLine({required this.title, required this.summary, required this.samples, required this.metricType});
  final String title;
  final ClimateMetricSummary? summary;
  final List<Map<String, Object?>> samples;
  final String metricType;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    if (value == null) {
      return Row(children: [Expanded(child: Text(title)), const Text('Нет измерений', style: TextStyle(color: AppTheme.muted))]);
    }
    final last = DateFormat('d MMM, HH:mm', 'ru').format(value.lastMeasuredAt);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      const SizedBox(height: 5),
      Text('Мин. ${value.minimum.toStringAsFixed(1)}${value.unit} · сред. ${value.average.toStringAsFixed(1)}${value.unit} · макс. ${value.maximum.toStringAsFixed(1)}${value.unit}', style: const TextStyle(fontSize: 12)),
      Text('Стандартное отклонение (σ): ${value.standardDeviation.toStringAsFixed(2)}${value.unit}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      Text('Последнее: ${value.lastValue.toStringAsFixed(1)}${value.unit} · $last · точек: ${value.count}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      if (value.coveragePercent != null)
        Text('Покрытие 15-минутного интервала: ${value.coveragePercent!.toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 8),
      ClimateTrendChart(samples: samples, metricType: metricType, unit: value.unit),
    ]);
  }
}


class _RegularityCard extends StatelessWidget {
  const _RegularityCard({required this.sessions, required this.database});
  final List<SleepSession> sessions;
  final SleepDatabase database;

  String _clock(int? minute) {
    if (minute == null) return 'Недостаточно данных';
    final hour = (minute ~/ 60).toString().padLeft(2, '0');
    final valueMinute = (minute % 60).toString().padLeft(2, '0');
    return '$hour:$valueMinute';
  }

  String _spread(double? value) =>
      value == null ? '—' : '±${value.round()} мин';

  String _duration(int? value) {
    if (value == null) return '—';
    return '${value ~/ 60} ч ${value % 60} мин';
  }

  @override
  Widget build(BuildContext context) {
    final result = SleepRegularityAnalysis.calculate(sessions);
    final outliers = result.nights.where((night) => night.isOutlier).toList()
      ..sort((a, b) => (b.bedtimeDeviation + b.wakeDeviation)
          .compareTo(a.bedtimeDeviation + a.wakeDeviation));
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Регулярность режима сна', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Расчёт по всей доступной истории, независимо от выбранной недели или месяца.',
          style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
        const SizedBox(height: 7),
        Text('Фактические ночи: ${result.nights.length} · исключено неполных или изменённых записей: ${result.excludedCount}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        if (!result.isReliable) ...[
          const SizedBox(height: 9),
          const Text('Пока недостаточно сопоставимых ночей для надёжной оценки. Нужно не менее 7 фактических записей.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
        ],
        const SizedBox(height: 12),
        _RegularityValueRow(label: 'Типичное засыпание', value: _clock(result.typicalBedtimeMinute)),
        _RegularityValueRow(label: 'Разброс засыпания', value: _spread(result.bedtimeMad)),
        const Divider(height: 18, color: AppTheme.surfaceLight),
        _RegularityValueRow(label: 'Типичное пробуждение', value: _clock(result.typicalWakeMinute)),
        _RegularityValueRow(label: 'Разброс пробуждения', value: _spread(result.wakeMad)),
        const Divider(height: 18, color: AppTheme.surfaceLight),
        _RegularityValueRow(label: 'Типичная длительность', value: _duration(result.typicalDurationMinutes)),
        _RegularityValueRow(label: 'Разброс длительности', value: _spread(result.durationMad)),
        if (result.isReliable && outliers.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Ночи с заметными отклонениями', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...outliers.take(5).map((night) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(DateFormat('d MMMM yyyy', 'ru').format(night.session.startedAt)),
            subtitle: Text('Засыпание: ${night.bedtimeDeviation} мин · пробуждение: ${night.wakeDeviation} мин'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SleepSessionDetailScreen(database: database, session: night.session),
            )),
          )),
        ],
        const SizedBox(height: 8),
        const Text(
          'Типичное время рассчитывается по медиане, разброс — по медианному абсолютному отклонению. Используются только завершённые фактические интервалы; ручные, изменённые и неполные записи не включаются в статистику. Время суток учитывает переход через полночь. При смене часового пояса историческое локальное время может быть ограничено текущими данными устройства.',
          style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
        ),
      ],
    ));
  }
}

class _RegularityValueRow extends StatelessWidget {
  const _RegularityValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
      const SizedBox(width: 12),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );
}
