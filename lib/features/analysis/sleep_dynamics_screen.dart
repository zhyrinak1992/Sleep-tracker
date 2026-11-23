import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'sleep_dynamics_analysis.dart';

class SleepDynamicsScreen extends StatefulWidget {
  const SleepDynamicsScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<SleepDynamicsScreen> createState() => _SleepDynamicsScreenState();
}

class _DynamicsData {
  const _DynamicsData({required this.sessions, required this.stages, required this.morning});
  final List<SleepSession> sessions;
  final Map<String, List<Map<String, Object?>>> stages;
  final Map<String, Map<String, Object?>> morning;
}

class _SleepDynamicsScreenState extends State<SleepDynamicsScreen> {
  late Future<_DynamicsData> _future;
  SleepDynamicsPeriod _period = SleepDynamicsPeriod.week;
  DateTime _anchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DynamicsData> _load() async {
    final sessions = await widget.database.getSessions(limit: 10000);
    final ids = sessions.where((s) => s.endedAt != null).map((s) => s.id).toList();
    final stages = await widget.database.getStagesForSessions(ids);
    final morning = await widget.database.getMorningReportsForSessions(ids);
    return _DynamicsData(sessions: sessions, stages: stages, morning: morning);
  }

  void _refresh() => setState(() => _future = _load());

  void _shift(int direction) {
    final start = SleepDynamicsAnalysis.periodStart(_anchor, _period);
    setState(() => _anchor = direction < 0
      ? SleepDynamicsAnalysis.previousPeriodStart(start, _period)
      : SleepDynamicsAnalysis.nextPeriodStart(start, _period));
  }

  SleepDynamicsSummary _summarize(_DynamicsData data, DateTime start, DateTime end, SleepDynamicsPeriod period) =>
    SleepDynamicsAnalysis.summarize(
      sessions: data.sessions,
      stagesBySession: data.stages,
      morningReports: data.morning,
      start: start,
      endExclusive: end,
      period: period,
    );

  String _periodTitle(DateTime start) {
    if (_period == SleepDynamicsPeriod.week) {
      final end = start.add(const Duration(days: 6));
      return DateFormat('d MMM', 'ru').format(start) + ' — ' + DateFormat('d MMM yyyy', 'ru').format(end);
    }
    if (_period == SleepDynamicsPeriod.month) return DateFormat('LLLL yyyy', 'ru').format(start);
    return start.year.toString();
  }

  String _duration(double? minutes) {
    if (minutes == null) return 'Нет данных';
    final value = minutes.round();
    return value ~/ 60 == 0
      ? value.toString() + ' мин'
      : (value ~/ 60).toString() + ' ч ' + (value % 60).toString() + ' мин';
  }

  String _number(double? value, String suffix, {int decimals = 1}) =>
    value == null ? 'Нет данных' : value.toStringAsFixed(decimals) + suffix;

  String _clock(int? minute) {
    if (minute == null) return 'Нет данных';
    final hour = (minute ~/ 60).toString().padLeft(2, '0');
    final value = (minute % 60).toString().padLeft(2, '0');
    return hour + ':' + value;
  }

  String _clockDelta(int? current, int? previous) {
    if (current == null || previous == null) return 'Недостаточно данных';
    var delta = current - previous;
    if (delta > 720) delta -= 1440;
    if (delta < -720) delta += 1440;
    if (delta == 0) return 'Без изменения';
    return delta > 0
      ? delta.toString() + ' мин позже'
      : delta.abs().toString() + ' мин раньше';
  }

  bool _hasData(List<double?> values) => values.any((value) => value != null);

  String _signed(double? value, String suffix, {int decimals = 1}) {
    if (value == null) return 'Нет сопоставимых данных';
    final sign = value > 0 ? '+' : '';
    return sign + value.toStringAsFixed(decimals) + suffix;
  }

  String _dateRange(DateTime start, DateTime endExclusive) =>
    DateFormat('d MMM', 'ru').format(start) + ' — ' +
    DateFormat('d MMM yyyy', 'ru').format(endExclusive.subtract(const Duration(days: 1)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Моя динамика сна'), actions: [
      IconButton(tooltip: 'Обновить данные', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: FutureBuilder<_DynamicsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить историю сна: ' + snapshot.error.toString()),
          ));
        }
        final data = snapshot.data!;
        final today = DateTime.now();
        final rolling = SleepDynamicsAnalysis.rollingThirtyDayRanges(today);
        final rollingCurrent = _summarize(data, rolling.currentStart, rolling.currentEndExclusive, SleepDynamicsPeriod.month);
        final rollingPrevious = _summarize(data, rolling.previousStart, rolling.previousEndExclusive, SleepDynamicsPeriod.month);

        final start = SleepDynamicsAnalysis.periodStart(_anchor, _period);
        final end = SleepDynamicsAnalysis.nextPeriodStart(start, _period);
        final previousStart = SleepDynamicsAnalysis.previousPeriodStart(start, _period);
        final current = _summarize(data, start, end, _period);
        final previous = _summarize(data, previousStart, start, _period);
        final currentPeriodStart = SleepDynamicsAnalysis.periodStart(todayStart, _period);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const ScreenHeader(
              title: 'Моя динамика сна',
              subtitle: 'Долгосрочные изменения по сохранённым ночам',
              icon: Icons.show_chart_rounded,
            ),
            const SizedBox(height: 10),
            _RollingComparisonCard(
              current: rollingCurrent,
              previous: rollingPrevious,
              dateRange: _dateRange,
              duration: _duration,
              number: _number,
              signed: _signed,
            ),
            const SizedBox(height: 18),
            const Text('Динамика за выбранный период', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<SleepDynamicsPeriod>(
              segments: const [
                ButtonSegment(value: SleepDynamicsPeriod.week, label: Text('Неделя')),
                ButtonSegment(value: SleepDynamicsPeriod.month, label: Text('Месяц')),
                ButtonSegment(value: SleepDynamicsPeriod.year, label: Text('Год')),
              ],
              selected: {_period},
              onSelectionChanged: (value) => setState(() {
                _period = value.first;
                _anchor = DateTime.now();
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(child: Center(child: Text(_periodTitle(start), style: const TextStyle(fontWeight: FontWeight.w600)))),
              IconButton(
                onPressed: start.isBefore(currentPeriodStart) ? () => _shift(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
            SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _period == SleepDynamicsPeriod.week ? 'Средняя длительность по дням'
                  : _period == SleepDynamicsPeriod.month ? 'Средняя длительность по неделям месяца'
                  : 'Средняя длительность по месяцам',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text('Шкала графика — до 12 часов. Пустой столбец означает отсутствие завершённых ночей, а не нулевой сон.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
              const SizedBox(height: 16),
              SizedBox(height: 150, child: _DynamicsChart(
                values: current.chartValues, period: _period, maxValue: 720,
                formatValue: (value) => (value / 60).toStringAsFixed(1) + ' ч',
              )),
            ])),
            if (_hasData(current.chartEfficiencyValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Эффективность по периодам',
                values: current.chartEfficiencyValues,
                period: _period,
                maxValue: 100,
                formatValue: (value) => value.toStringAsFixed(0) + '%',
              ),
            ],
            if (_hasData(current.chartAwakeningValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Пробуждения по периодам',
                values: current.chartAwakeningValues,
                period: _period,
                maxValue: 10,
                formatValue: (value) => value.toStringAsFixed(1),
              ),
            ],
            if (_hasData(current.chartQualityValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Субъективное качество по периодам',
                values: current.chartQualityValues,
                period: _period,
                maxValue: 5,
                formatValue: (value) => value.toStringAsFixed(1) + ' / 5',
              ),
            ],
            if (_hasData(current.chartWellbeingValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Самочувствие по периодам',
                values: current.chartWellbeingValues,
                period: _period,
                maxValue: 5,
                formatValue: (value) => value.toStringAsFixed(1) + ' / 5',
              ),
            ],
            const SizedBox(height: 12),
            _DynamicsMetricCard(
              title: 'Средняя продолжительность сна',
              value: _duration(current.averageSleepMinutes),
              samples: current.durationSamples,
              previousValue: _duration(previous.averageSleepMinutes),
              note: 'Завершённых ночей: ' + current.completedCount.toString() + '. Для длительности используются доступные фазы/фактические границы, а при их отсутствии — сохранённый интервал ночной сессии.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Эффективность сна',
              value: _number(current.averageEfficiency, '%'),
              samples: current.efficiencySamples,
              previousValue: _number(previous.averageEfficiency, '%'),
              note: 'Учитываются только ночи с достаточным покрытием фаз сна.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Зарегистрированные пробуждения',
              value: _number(current.averageAwakenings, ''),
              samples: current.awakeningSamples,
              previousValue: _number(previous.averageAwakenings, ''),
              note: 'Пробуждения включаются только при наличии стадий сна и достаточного покрытия. Отсутствие данных не считается нулём.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Субъективное качество сна',
              value: _number(current.averageQuality, ' / 5'),
              samples: current.qualitySamples,
              previousValue: _number(previous.averageQuality, ' / 5'),
              note: 'Среднее по сохранённым утренним оценкам качества.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Утреннее самочувствие',
              value: _number(current.averageWellbeing, ' / 5'),
              samples: current.wellbeingSamples,
              previousValue: _number(previous.averageWellbeing, ' / 5'),
              note: 'Среднее по сохранённым ответам о самочувствии.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Типичное время засыпания',
              value: _clock(current.typicalBedtimeMinute),
              samples: current.regularitySamples,
              previousValue: _clock(previous.typicalBedtimeMinute),
              note: 'Круговая медиана фактического времени засыпания; ручные и изменённые записи не включаются.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Типичное время пробуждения',
              value: _clock(current.typicalWakeMinute),
              samples: current.regularitySamples,
              previousValue: _clock(previous.typicalWakeMinute),
              note: 'Круговая медиана фактического времени пробуждения; ручные и изменённые записи не включаются.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Разброс времени засыпания',
              value: _number(current.bedtimeDeviationMinutes, ' мин', decimals: 0),
              samples: current.regularitySamples,
              previousValue: _number(previous.bedtimeDeviationMinutes, ' мин', decimals: 0),
              note: 'Медианное абсолютное отклонение фактического времени засыпания; ручные и изменённые записи не включаются.',
            ),
            const SizedBox(height: 10),
            _DynamicsMetricCard(
              title: 'Разброс времени пробуждения',
              value: _number(current.wakeTimeDeviationMinutes, ' мин', decimals: 0),
              samples: current.regularitySamples,
              previousValue: _number(previous.wakeTimeDeviationMinutes, ' мин', decimals: 0),
              note: 'Медианное абсолютное отклонение фактического времени пробуждения; меньшее значение означает меньший разброс.',
            ),
            const SizedBox(height: 12),
            Text(
              'В выбранном периоде: ' + current.sessionsCount.toString() + ' записей, ' +
              current.completedCount.toString() + ' завершённых. Предыдущий равный период: ' +
              previous.completedCount.toString() + ' завершённых ночей. Метрики рассчитываются независимо и используют только собственные доступные выборки. Все сравнения описывают наблюдаемые изменения и не устанавливают причины.',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
            ),
          ],
        );
      },
    ),
  );
}

class _RollingComparisonCard extends StatelessWidget {
  const _RollingComparisonCard({
    required this.current,
    required this.previous,
    required this.dateRange,
    required this.duration,
    required this.number,
    required this.signed,
  });
  final SleepDynamicsSummary current;
  final SleepDynamicsSummary previous;
  final String Function(DateTime, DateTime) dateRange;
  final String Function(double?) duration;
  final String Function(double?, String, {int decimals}) number;
  final String Function(double?, String, {int decimals}) signed;

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Скользящее сравнение 30 + 30 дней', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 5),
      const Text('Последние 30 календарных дней сопоставляются с непосредственно предшествующими 30 днями.',
        style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
      const SizedBox(height: 12),
      _RollingMetric(
        label: 'Средняя длительность сна',
        currentValue: duration(current.averageSleepMinutes),
        previousValue: duration(previous.averageSleepMinutes),
        change: current.averageSleepMinutes == null || previous.averageSleepMinutes == null
          ? 'Недостаточно данных'
          : _durationDelta(current.averageSleepMinutes! - previous.averageSleepMinutes!),
        currentSamples: current.durationSamples,
        previousSamples: previous.durationSamples,
      ),
      _RollingMetric(
        label: 'Эффективность',
        currentValue: number(current.averageEfficiency, '%'),
        previousValue: number(previous.averageEfficiency, '%'),
        change: current.averageEfficiency == null || previous.averageEfficiency == null
          ? 'Недостаточно данных'
          : signed(current.averageEfficiency! - previous.averageEfficiency!, ' п. п.'),
        currentSamples: current.efficiencySamples,
        previousSamples: previous.efficiencySamples,
      ),
      _RollingMetric(
        label: 'Пробуждения',
        currentValue: number(current.averageAwakenings, ''),
        previousValue: number(previous.averageAwakenings, ''),
        change: current.averageAwakenings == null || previous.averageAwakenings == null
          ? 'Недостаточно данных'
          : signed(current.averageAwakenings! - previous.averageAwakenings!, ''),
        currentSamples: current.awakeningSamples,
        previousSamples: previous.awakeningSamples,
      ),
      _RollingMetric(
        label: 'Качество сна',
        currentValue: number(current.averageQuality, ' / 5'),
        previousValue: number(previous.averageQuality, ' / 5'),
        change: current.averageQuality == null || previous.averageQuality == null
          ? 'Недостаточно данных'
          : signed(current.averageQuality! - previous.averageQuality!, ' балла'),
        currentSamples: current.qualitySamples,
        previousSamples: previous.qualitySamples,
      ),
      _RollingMetric(
        label: 'Самочувствие',
        currentValue: number(current.averageWellbeing, ' / 5'),
        previousValue: number(previous.averageWellbeing, ' / 5'),
        change: current.averageWellbeing == null || previous.averageWellbeing == null
          ? 'Недостаточно данных'
          : signed(current.averageWellbeing! - previous.averageWellbeing!, ' балла'),
        currentSamples: current.wellbeingSamples,
        previousSamples: previous.wellbeingSamples,
      ),
      _RollingMetric(
        label: 'Типичное время засыпания',
        currentValue: _clock(current.typicalBedtimeMinute),
        previousValue: _clock(previous.typicalBedtimeMinute),
        change: _clockDelta(current.typicalBedtimeMinute, previous.typicalBedtimeMinute),
        currentSamples: current.regularitySamples,
        previousSamples: previous.regularitySamples,
      ),
      _RollingMetric(
        label: 'Типичное время пробуждения',
        currentValue: _clock(current.typicalWakeMinute),
        previousValue: _clock(previous.typicalWakeMinute),
        change: _clockDelta(current.typicalWakeMinute, previous.typicalWakeMinute),
        currentSamples: current.regularitySamples,
        previousSamples: previous.regularitySamples,
      ),
      _RollingMetric(
        label: 'Разброс засыпания',
        currentValue: number(current.bedtimeDeviationMinutes, ' мин', decimals: 0),
        previousValue: number(previous.bedtimeDeviationMinutes, ' мин', decimals: 0),
        change: current.bedtimeDeviationMinutes == null || previous.bedtimeDeviationMinutes == null
          ? 'Недостаточно данных'
          : signed(current.bedtimeDeviationMinutes! - previous.bedtimeDeviationMinutes!, ' мин', decimals: 0),
        currentSamples: current.regularitySamples,
        previousSamples: previous.regularitySamples,
      ),
      _RollingMetric(
        label: 'Разброс пробуждения',
        currentValue: number(current.wakeTimeDeviationMinutes, ' мин', decimals: 0),
        previousValue: number(previous.wakeTimeDeviationMinutes, ' мин', decimals: 0),
        change: current.wakeTimeDeviationMinutes == null || previous.wakeTimeDeviationMinutes == null
          ? 'Недостаточно данных'
          : signed(current.wakeTimeDeviationMinutes! - previous.wakeTimeDeviationMinutes!, ' мин', decimals: 0),
        currentSamples: current.regularitySamples,
        previousSamples: previous.regularitySamples,
      ),
      const SizedBox(height: 8),
      Text(
        'Последние 30 дней: ' + dateRange(current.start, current.endExclusive) +
        ' · предыдущие 30 дней: ' + dateRange(previous.start, previous.endExclusive) + '.',
        style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
      ),
    ],
  ));

  static String _clock(int? minute) {
    if (minute == null) return 'Нет данных';
    return (minute ~/ 60).toString().padLeft(2, '0') + ':' +
      (minute % 60).toString().padLeft(2, '0');
  }

  static String _clockDelta(int? current, int? previous) {
    if (current == null || previous == null) return 'Недостаточно данных';
    var delta = current - previous;
    if (delta > 720) delta -= 1440;
    if (delta < -720) delta += 1440;
    if (delta == 0) return 'Без изменения';
    return delta > 0 ? delta.toString() + ' мин позже' : delta.abs().toString() + ' мин раньше';
  }

  static String _durationDelta(double value) {
    final minutes = value.round().abs();
    final text = minutes ~/ 60 == 0
      ? minutes.toString() + ' мин'
      : (minutes ~/ 60).toString() + ' ч ' + (minutes % 60).toString() + ' мин';
    return (value > 0 ? '+' : value < 0 ? '−' : '') + text;
  }
}

class _RollingMetric extends StatelessWidget {
  const _RollingMetric({
    required this.label,
    required this.currentValue,
    required this.previousValue,
    required this.change,
    required this.currentSamples,
    required this.previousSamples,
  });
  final String label, currentValue, previousValue, change;
  final int currentSamples, previousSamples;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Text('Последние: ' + currentValue + ' · n=' + currentSamples.toString(),
          style: const TextStyle(fontSize: 11, color: AppTheme.muted))),
        Expanded(child: Text('Ранее: ' + previousValue + ' · n=' + previousSamples.toString(),
          style: const TextStyle(fontSize: 11, color: AppTheme.muted))),
      ]),
      const SizedBox(height: 3),
      Text('Разница: ' + change, style: const TextStyle(fontSize: 12, color: AppTheme.teal)),
    ]),
  );
}

class _DynamicsMetricCard extends StatelessWidget {
  const _DynamicsMetricCard({
    required this.title,
    required this.value,
    required this.samples,
    required this.previousValue,
    required this.note,
  });
  final String title, value, previousValue, note;
  final int samples;

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
        Text('n=' + samples.toString(), style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ]),
      const SizedBox(height: 4),
      Text('Предыдущий период: ' + previousValue, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 5),
      Text(note, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
    ],
  ));
}

class _DynamicsChartCard extends StatelessWidget {
  const _DynamicsChartCard({
    required this.title, required this.values, required this.period,
    required this.maxValue, required this.formatValue,
  });
  final String title;
  final List<double?> values;
  final SleepDynamicsPeriod period;
  final double maxValue;
  final String Function(double) formatValue;

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 14),
      SizedBox(height: 150, child: _DynamicsChart(
        values: values, period: period, maxValue: maxValue, formatValue: formatValue,
      )),
    ],
  ));
}

class _DynamicsChart extends StatelessWidget {
  const _DynamicsChart({
    required this.values, required this.period, required this.maxValue, required this.formatValue,
  });
  final List<double?> values;
  final SleepDynamicsPeriod period;
  final double maxValue;
  final String Function(double) formatValue;

  @override
  Widget build(BuildContext context) {
    final labels = switch (period) {
      SleepDynamicsPeriod.week => const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      SleepDynamicsPeriod.month => const ['1 нед.', '2 нед.', '3 нед.', '4 нед.', '5 нед.'],
      SleepDynamicsPeriod.year => const ['Ян', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'],
    };
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(values.length, (index) {
      final value = values[index];
      final height = value == null ? 0.0 : (value / maxValue * 105).clamp(0.0, 105.0).toDouble();
      return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (value != null) Text(formatValue(value), style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
        const SizedBox(height: 4),
        Container(
          height: 108,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 17,
            height: height,
            decoration: BoxDecoration(
              color: value == null ? AppTheme.surfaceLight : AppTheme.teal,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(labels[index], style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
      ]));
    }));
  }
}
