import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_analytics.dart';
import 'weekday_comparison_screen.dart';
import 'moon_phase_screen.dart';

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
  }

  void _shift(int direction) {
    final start = SleepAnalytics.periodStart(_anchor, _period);
    setState(() => _anchor = direction < 0
        ? SleepAnalytics.previousPeriodStart(start, _period)
        : SleepAnalytics.nextPeriodStart(start, _period));
  }

  String _periodTitle(DateTime start) {
    if (_period == AnalysisPeriod.week) {
      final end = start.add(const Duration(days: 6));
      return '${DateFormat('d MMM', 'ru').format(start)} — ${DateFormat('d MMM', 'ru').format(end)}';
    }
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
          Text('Анализ', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text('Динамика по сохранённым данным', style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 14),
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
          const SizedBox(height: 18),
          SegmentedButton<AnalysisPeriod>(
            segments: const [
              ButtonSegment(value: AnalysisPeriod.week, label: Text('Неделя')),
              ButtonSegment(value: AnalysisPeriod.month, label: Text('Месяц')),
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
              previousValue: previous.averageDurationMinutes,
              unit: 'мин',
            ),
            const SizedBox(height: 10),
            _MetricCard(
              title: 'Средняя оценка самочувствия',
              value: current.averageRating == null ? 'Нет оценок' : '${current.averageRating!.toStringAsFixed(1)} из 5',
              detail: '${current.rated} ${_ratingWord(current.rated)}',
              previousValue: previous.averageRating,
              unit: 'балл',
            ),
            const SizedBox(height: 14),
            SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Продолжительность по дням', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Среднее для дней с завершёнными сессиями', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 18),
              SizedBox(height: 150, child: _DurationChart(values: chart, period: _period)),
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
            const SizedBox(height: 12),
            const Text('Фазы сна, пульс, дыхание и звуковые события появятся в аналитике после подключения соответствующих источников. Сейчас они не учитываются и не заменяются условными значениями.', style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
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
  const _MetricCard({required this.title, required this.value, required this.detail, required this.previousValue, required this.unit});
  final String title, value, detail, unit;
  final double? previousValue;

  @override
  Widget build(BuildContext context) {
    final hasComparison = previousValue != null;
    return SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AppTheme.muted)),
      const SizedBox(height: 7),
      Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(child: Text(detail, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        if (hasComparison) Text('пред. ${unit == 'мин' ? _duration(previousValue) : '${previousValue!.toStringAsFixed(1)} из 5'}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ]),
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
  const _DurationChart({required this.values, required this.period});
  final List<double?> values;
  final AnalysisPeriod period;
  @override
  Widget build(BuildContext context) {
    final labels = period == AnalysisPeriod.week
        ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : List.generate(5, (i) => '${i + 1} нед.');
    final maxValue = values.whereType<double>().fold<double>(0, (a, b) => a > b ? a : b);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(values.length, (i) {
      final value = values[i];
      final height = value == null || maxValue == 0 ? 0.0 : (value / maxValue * 104).clamp(4.0, 104.0).toDouble();
      return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (value != null) Text('${(value / 60).toStringAsFixed(1)}', style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
        const SizedBox(height: 5),
        Container(height: 108, alignment: Alignment.bottomCenter, child: Container(
          height: height,
          width: 18,
          decoration: BoxDecoration(color: value == null ? AppTheme.surfaceLight : AppTheme.teal, borderRadius: BorderRadius.circular(7)),
        )),
        const SizedBox(height: 8),
        Text(labels[i], style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
      ]));
    }));
  }
}
