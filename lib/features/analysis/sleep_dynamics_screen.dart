import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../data/pdf_report_service.dart';
import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'sleep_dynamics_analysis.dart';
import 'sleep_score.dart';

class SleepDynamicsScreen extends StatefulWidget {
  const SleepDynamicsScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<SleepDynamicsScreen> createState() => _SleepDynamicsScreenState();
}

class _DynamicsData {
  const _DynamicsData({required this.sessions, required this.stages, required this.morning, required this.scoreCache});
  final List<SleepSession> sessions;
  final Map<String, List<Map<String, Object?>>> stages;
  final Map<String, Map<String, Object?>> morning;
  final Map<String, SleepScoreResult> scoreCache;
}

class _SleepDynamicsScreenState extends State<SleepDynamicsScreen> {
  late Future<_DynamicsData> _future;
  SleepDynamicsPeriod _period = SleepDynamicsPeriod.week;
  int _rollingDays = 30;
  String _metricGroup = 'all';
  bool _showGroup(String group) => _metricGroup == 'all' || _metricGroup == group;

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
    return _DynamicsData(sessions: sessions, stages: stages, morning: morning, scoreCache: <String, SleepScoreResult>{});
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
      scoreCache: data.scoreCache,
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

  bool _hasData(List<double?> values) => values.any((value) => value != null);

  String _signed(double? value, String suffix, {int decimals = 1}) {
    if (value == null) return 'Нет сопоставимых данных';
    final sign = value > 0 ? '+' : '';
    return sign + value.toStringAsFixed(decimals) + suffix;
  }

  String _dateRange(DateTime start, DateTime endExclusive) =>
    DateFormat('d MMM', 'ru').format(start) + ' — ' +
    DateFormat('d MMM yyyy', 'ru').format(endExclusive.subtract(const Duration(days: 1)));

  Future<void> _exportDynamics(
    _DynamicsData data,
    SleepDynamicsSummary current,
    SleepDynamicsSummary previous,
    DateTime start,
    DateTime end,
  ) async {
    final metrics = <Map<String, Object?>>[];
    void addMetric(String label, double? value, int samples, double? previousValue, int previousSamples, String suffix, {int decimals = 1, bool asDuration = false}) {
      String shown(double? number) {
        if (number == null) return 'Нет данных';
        if (asDuration) return _duration(number);
        return number.toStringAsFixed(decimals) + suffix;
      }
      metrics.add({
        'label': label,
        'current': shown(value),
        'currentSamples': samples,
        'previous': shown(previousValue),
        'previousSamples': previousSamples,
      });
    }

    if (_showGroup('sleep')) {
      addMetric('Продолжительность сна', current.averageSleepMinutes, current.durationSamples, previous.averageSleepMinutes, previous.durationSamples, '', asDuration: true);
      addMetric('Оценка качества сна', current.averageSleepScore, current.scoreSamples, previous.averageSleepScore, previous.scoreSamples, ' / 100', decimals: 0);
      addMetric('Эффективность сна', current.averageEfficiency, current.efficiencySamples, previous.averageEfficiency, previous.efficiencySamples, '%');
      addMetric('Пробуждения', current.averageAwakenings, current.awakeningSamples, previous.averageAwakenings, previous.awakeningSamples, '');
    }
    if (_showGroup('wellbeing')) {
      addMetric('Субъективное качество', current.averageQuality, current.qualitySamples, previous.averageQuality, previous.qualitySamples, ' / 5');
      addMetric('Утреннее самочувствие', current.averageWellbeing, current.wellbeingSamples, previous.averageWellbeing, previous.wellbeingSamples, ' / 5');
    }
    if (_showGroup('routine')) {
      metrics.addAll([
        {'label':'Типичное время засыпания','current':_clock(current.typicalBedtimeMinute),'currentSamples':current.regularitySamples,'previous':_clock(previous.typicalBedtimeMinute),'previousSamples':previous.regularitySamples},
        {'label':'Типичное время пробуждения','current':_clock(current.typicalWakeMinute),'currentSamples':current.regularitySamples,'previous':_clock(previous.typicalWakeMinute),'previousSamples':previous.regularitySamples},
      ]);
      addMetric('Разброс времени засыпания', current.bedtimeDeviationMinutes, current.regularitySamples, previous.bedtimeDeviationMinutes, previous.regularitySamples, ' мин', decimals: 0);
      addMetric('Разброс времени пробуждения', current.wakeTimeDeviationMinutes, current.regularitySamples, previous.wakeTimeDeviationMinutes, previous.regularitySamples, ' мин', decimals: 0);
    }

    final trend = <Map<String, Object?>>[];
    void addTrend(String title, List<double?> values, String suffix, {bool asDuration = false, int decimals = 1}) {
      for (var i = 0; i < values.length; i++) {
        final range = SleepDynamicsAnalysis.bucketRange(start, _period, i);
        final label = _period == SleepDynamicsPeriod.week
          ? DateFormat('EEE d MMM', 'ru').format(range.start)
          : _period == SleepDynamicsPeriod.month
            ? 'Неделя ${i + 1}'
            : DateFormat('LLLL', 'ru').format(range.start);
        final value = values[i];
        trend.add({
          'metric': title,
          'interval': label,
          'value': value == null ? 'Нет данных' : asDuration ? _duration(value) : value.toStringAsFixed(decimals) + suffix,
          'rawValue': value,
        });
      }
    }
    if (_showGroup('sleep')) {
      addTrend('Длительность сна', current.chartValues, '', asDuration: true);
      addTrend('Оценка сна', current.chartScoreValues, ' / 100', decimals: 0);
      addTrend('Эффективность', current.chartEfficiencyValues, '%');
      addTrend('Пробуждения', current.chartAwakeningValues, '');
    }
    if (_showGroup('wellbeing')) {
      addTrend('Субъективное качество', current.chartQualityValues, ' / 5');
      addTrend('Самочувствие', current.chartWellbeingValues, ' / 5');
    }

    final nights = <Map<String, Object?>>[];
    final selected = data.sessions.where((session) =>
      !session.startedAt.isBefore(start) && session.startedAt.isBefore(end) &&
      session.endedAt != null && session.duration != null && session.duration!.inMinutes > 0).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    for (final session in selected) {
      final stages = data.stages[session.id] ?? const <Map<String, Object?>>[];
      final calculated = SleepSessionMetrics.calculate(session: session, stages: stages);
      final report = data.morning[session.id];
      final score = data.scoreCache.putIfAbsent(session.id, () =>
        SleepScoreCalculator.calculateForSession(
          session: session,
          historySessions: data.sessions,
          morningReports: data.morning,
          stagesBySession: data.stages,
        )).score;
      final duration = calculated.sleepDurationMinutes ?? session.duration!.inMinutes.toDouble();
      final date = DateFormat('dd.MM.yyyy', 'ru').format(session.startedAt);
      // These columns are labelled as actual sleep onset/wake, so do not
      // substitute time-in-bed boundaries when measured sleep boundaries are absent.
      final bedtime = session.actualSleepStartedAt == null
        ? '—' : DateFormat('HH:mm').format(session.actualSleepStartedAt!);
      final wake = session.actualSleepEndedAt == null
        ? '—' : DateFormat('HH:mm').format(session.actualSleepEndedAt!);
      final rawQuality = report?['sleep_quality'];
      final rawWellbeing = report?['wellbeing'];
      nights.add({
        'date': date,
        'bedtime': bedtime,
        'wake': wake,
        'duration': _duration(duration.toDouble()),
        'score': score == null ? '—' : score.toStringAsFixed(0),
        'efficiency': calculated.sleepEfficiencyPercent == null ? '—' : calculated.sleepEfficiencyPercent!.toStringAsFixed(1) + '%',
        'awakenings': stages.isEmpty || calculated.stageCoveragePercent == null ? '—' : calculated.awakeningCount.toString(),
        'quality': rawQuality is num ? rawQuality.toString() : '—',
        'wellbeing': rawWellbeing is num ? rawWellbeing.toString() : '—',
      });
    }

    final groupLabel = switch (_metricGroup) {
      'sleep' => 'Сон',
      'routine' => 'Режим',
      'wellbeing' => 'Самочувствие',
      _ => 'Все показатели',
    };
    await PdfReportService.exportSleepDynamics(
      title: 'Аналитика сна',
      category: groupLabel,
      dateRange: _dateRange(start, end),
      previousRange: _dateRange(previous.start, previous.endExclusive),
      sessionsCount: current.sessionsCount,
      completedCount: current.completedCount,
      previousCompletedCount: previous.completedCount,
      metrics: metrics,
      trend: trend,
      nights: nights,
    );
  }

  Future<void> _showBucketDetails(
    _DynamicsData data,
    DateTime periodStart,
    DateTime previousPeriodStart,
    int index,
    String metricKey,
    String metricTitle,
  ) async {
    List<({SleepSession session, double value})> observations(DateTime start) {
      final range = SleepDynamicsAnalysis.bucketRange(start, _period, index);
      final selected = data.sessions.where((session) =>
        !session.startedAt.isBefore(range.start) &&
        session.startedAt.isBefore(range.endExclusive) &&
        session.endedAt != null && session.duration != null &&
        session.duration!.inMinutes > 0).toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      final result = <({SleepSession session, double value})>[];
      for (final session in selected) {
        final stages = data.stages[session.id] ?? const <Map<String, Object?>>[];
        final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
        double? value;
        switch (metricKey) {
          case 'duration':
            final minutes = metrics.sleepDurationMinutes ?? session.duration!.inMinutes;
            if (minutes > 0) value = minutes.toDouble();
            break;
          case 'score':
            value = data.scoreCache.putIfAbsent(session.id, () =>
              SleepScoreCalculator.calculateForSession(
                session: session,
                historySessions: data.sessions,
                morningReports: data.morning,
                stagesBySession: data.stages,
              ),
            ).score;
            break;
          case 'efficiency':
            value = metrics.sleepEfficiencyPercent;
            break;
          case 'awakenings':
            if (stages.isNotEmpty && metrics.stageCoveragePercent != null) {
              value = metrics.awakeningCount.toDouble();
            }
            break;
          case 'quality':
            final raw = data.morning[session.id]?['sleep_quality'];
            if (raw is num && raw.toDouble().isFinite) value = raw.toDouble();
            break;
          case 'wellbeing':
            final raw = data.morning[session.id]?['wellbeing'];
            if (raw is num && raw.toDouble().isFinite) value = raw.toDouble();
            break;
        }
        if (value != null && value.isFinite) result.add((session: session, value: value));
      }
      return result;
    }

    final current = observations(periodStart);
    final previous = observations(previousPeriodStart);
    double? average(List<({SleepSession session, double value})> values) =>
      values.isEmpty ? null : values.fold<double>(0, (sum, item) => sum + item.value) / values.length;
    String shown(double? value) {
      if (value == null) return 'Нет данных';
      if (metricKey == 'duration') return _duration(value);
      if (metricKey == 'efficiency') return value.toStringAsFixed(1) + '%';
      if (metricKey == 'score') return value.toStringAsFixed(0) + ' / 100';
      if (metricKey == 'quality' || metricKey == 'wellbeing') return value.toStringAsFixed(1) + ' / 5';
      return value.toStringAsFixed(1);
    }
    String periodLabel(DateTime start) {
      final range = SleepDynamicsAnalysis.bucketRange(start, _period, index);
      return _dateRange(range.start, range.endExclusive);
    }
    Widget list(List<({SleepSession session, double value})> values) {
      if (values.isEmpty) return const Text('Нет доступных измерений', style: TextStyle(color: AppTheme.muted));
      return Column(children: values.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(DateFormat('dd.MM.yyyy · HH:mm', 'ru').format(item.session.startedAt))),
          Text(shown(item.value), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      )).toList());
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(metricTitle),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Текущий срез · ${periodLabel(periodStart)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Среднее: ${shown(average(current))} · n=${current.length}'),
            list(current),
            const Divider(height: 22),
            Text('Предыдущий срез · ${periodLabel(previousPeriodStart)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Среднее: ${shown(average(previous))} · n=${previous.length}'),
            list(previous),
            const SizedBox(height: 8),
            const Text('Показываются только фактические измерения. Отсутствующие значения не заменяются нулями.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          ],
        ))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
      ),
    );
  }

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
        final rolling = SleepDynamicsAnalysis.rollingRanges(today, _rollingDays);
        final rollingCurrent = _summarize(data, rolling.currentStart, rolling.currentEndExclusive, SleepDynamicsPeriod.month);
        final rollingPrevious = _summarize(data, rolling.previousStart, rolling.previousEndExclusive, SleepDynamicsPeriod.month);

        final start = SleepDynamicsAnalysis.periodStart(_anchor, _period);
        final end = SleepDynamicsAnalysis.nextPeriodStart(start, _period);
        final previousStart = SleepDynamicsAnalysis.previousPeriodStart(start, _period);
        final current = _summarize(data, start, end, _period);
        final previous = _summarize(data, previousStart, start, _period);
        final currentPeriodStart = SleepDynamicsAnalysis.periodStart(DateTime(today.year, today.month, today.day), _period);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const ScreenHeader(
              title: 'Моя динамика сна',
              subtitle: 'Долгосрочные изменения по сохранённым ночам',
              icon: Icons.show_chart_rounded,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _exportDynamics(data, current, previous, start, end),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Экспортировать аналитику в PDF'),
            ),
            const SizedBox(height: 10),
            const Text('Сравнение равных скользящих периодов', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 дн.')),
                ButtonSegment(value: 30, label: Text('30 дн.')),
                ButtonSegment(value: 90, label: Text('90 дн.')),
                ButtonSegment(value: 365, label: Text('365 дн.')),
              ],
              selected: {_rollingDays},
              onSelectionChanged: (value) => setState(() => _rollingDays = value.first),
            ),
            const SizedBox(height: 8),
            _RollingComparisonCard(
              days: _rollingDays,
              current: rollingCurrent,
              previous: rollingPrevious,
              dateRange: _dateRange,
              duration: _duration,
              number: _number,
              signed: _signed,
            ),
            const SizedBox(height: 18),
            const Text('Показатели аналитики', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Все')),
                ButtonSegment(value: 'sleep', label: Text('Сон')),
                ButtonSegment(value: 'routine', label: Text('Режим')),
                ButtonSegment(value: 'wellbeing', label: Text('Самочувствие')),
              ],
              selected: {_metricGroup},
              onSelectionChanged: (value) => setState(() => _metricGroup = value.first),
            ),
            const SizedBox(height: 10),
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
            if (_showGroup('sleep')) SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                onTap: (index) => _showBucketDetails(data, start, previousStart, index, 'duration', 'Продолжительность сна'),
              )),
            ])),
            if (_showGroup('sleep') && _hasData(current.chartScoreValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Оценка качества сна 0–100',
                values: current.chartScoreValues,
                period: _period,
                maxValue: 100,
                formatValue: (value) => value.toStringAsFixed(0) + ' / 100',
                onBucketTap: (index) => _showBucketDetails(data, start, previousStart, index, 'score', 'Оценка качества сна'),
              ),
            ],
            if (_showGroup('sleep') && _hasData(current.chartEfficiencyValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Эффективность по периодам',
                values: current.chartEfficiencyValues,
                period: _period,
                maxValue: 100,
                formatValue: (value) => value.toStringAsFixed(0) + '%',
                onBucketTap: (index) => _showBucketDetails(data, start, previousStart, index, 'efficiency', 'Эффективность сна'),
              ),
            ],
            if (_showGroup('sleep') && _hasData(current.chartAwakeningValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Пробуждения по периодам',
                values: current.chartAwakeningValues,
                period: _period,
                maxValue: 10,
                formatValue: (value) => value.toStringAsFixed(1),
                onBucketTap: (index) => _showBucketDetails(data, start, previousStart, index, 'awakenings', 'Пробуждения'),
              ),
            ],
            if (_showGroup('wellbeing') && _hasData(current.chartQualityValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Субъективное качество по периодам',
                values: current.chartQualityValues,
                period: _period,
                maxValue: 5,
                formatValue: (value) => value.toStringAsFixed(1) + ' / 5',
                onBucketTap: (index) => _showBucketDetails(data, start, previousStart, index, 'quality', 'Субъективное качество'),
              ),
            ],
            if (_showGroup('wellbeing') && _hasData(current.chartWellbeingValues)) ...[
              const SizedBox(height: 10),
              _DynamicsChartCard(
                title: 'Самочувствие по периодам',
                values: current.chartWellbeingValues,
                period: _period,
                maxValue: 5,
                formatValue: (value) => value.toStringAsFixed(1) + ' / 5',
                onBucketTap: (index) => _showBucketDetails(data, start, previousStart, index, 'wellbeing', 'Утреннее самочувствие'),
              ),
            ],
            const SizedBox(height: 12),
            if (_showGroup('sleep')) _DynamicsMetricCard(
              title: 'Средняя продолжительность сна',
              value: _duration(current.averageSleepMinutes),
              samples: current.durationSamples,
              previousValue: _duration(previous.averageSleepMinutes),
              note: 'Завершённых ночей: ' + current.completedCount.toString() + '. Для длительности используются доступные фазы/фактические границы, а при их отсутствии — сохранённый интервал ночной сессии.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('sleep')) _DynamicsMetricCard(
              title: 'Средняя оценка качества сна',
              value: _number(current.averageSleepScore, ' / 100', decimals: 0),
              samples: current.scoreSamples,
              previousValue: _number(previous.averageSleepScore, ' / 100', decimals: 0),
              note: 'Веса 40/30/20/10. В расчёт каждой ночи входят только доступные компоненты; личный диапазон длительности использует предшествующие 90 дней. При недостатке данных оценка не рассчитывается.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('sleep')) _DynamicsMetricCard(
              title: 'Эффективность сна',
              value: _number(current.averageEfficiency, '%'),
              samples: current.efficiencySamples,
              previousValue: _number(previous.averageEfficiency, '%'),
              note: 'Учитываются только ночи с достаточным покрытием фаз сна.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('sleep')) _DynamicsMetricCard(
              title: 'Зарегистрированные пробуждения',
              value: _number(current.averageAwakenings, ''),
              samples: current.awakeningSamples,
              previousValue: _number(previous.averageAwakenings, ''),
              note: 'Пробуждения включаются только при наличии стадий сна и достаточного покрытия. Отсутствие данных не считается нулём.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('wellbeing')) _DynamicsMetricCard(
              title: 'Субъективное качество сна',
              value: _number(current.averageQuality, ' / 5'),
              samples: current.qualitySamples,
              previousValue: _number(previous.averageQuality, ' / 5'),
              note: 'Среднее по сохранённым утренним оценкам качества.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('wellbeing')) _DynamicsMetricCard(
              title: 'Утреннее самочувствие',
              value: _number(current.averageWellbeing, ' / 5'),
              samples: current.wellbeingSamples,
              previousValue: _number(previous.averageWellbeing, ' / 5'),
              note: 'Среднее по сохранённым ответам о самочувствии.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('routine')) _DynamicsMetricCard(
              title: 'Типичное время засыпания',
              value: _clock(current.typicalBedtimeMinute),
              samples: current.regularitySamples,
              previousValue: _clock(previous.typicalBedtimeMinute),
              note: 'Круговая медиана фактического времени засыпания; ручные и изменённые записи не включаются.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('routine')) _DynamicsMetricCard(
              title: 'Типичное время пробуждения',
              value: _clock(current.typicalWakeMinute),
              samples: current.regularitySamples,
              previousValue: _clock(previous.typicalWakeMinute),
              note: 'Круговая медиана фактического времени пробуждения; ручные и изменённые записи не включаются.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('routine')) _DynamicsMetricCard(
              title: 'Разброс времени засыпания',
              value: _number(current.bedtimeDeviationMinutes, ' мин', decimals: 0),
              samples: current.regularitySamples,
              previousValue: _number(previous.bedtimeDeviationMinutes, ' мин', decimals: 0),
              note: 'Медианное абсолютное отклонение фактического времени засыпания; ручные и изменённые записи не включаются.',
            ),
            const SizedBox(height: 10),
            if (_showGroup('routine')) _DynamicsMetricCard(
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
    required this.days,
    required this.current,
    required this.previous,
    required this.dateRange,
    required this.duration,
    required this.number,
    required this.signed,
  });
  final int days;
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
      Text('Скользящее сравнение $days + $days дней', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 5),
      Text('Последние $days календарных дней сопоставляются с непосредственно предшествующими $days днями.',
        style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
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
        label: 'Оценка качества сна',
        currentValue: number(current.averageSleepScore, ' / 100', decimals: 0),
        previousValue: number(previous.averageSleepScore, ' / 100', decimals: 0),
        change: current.averageSleepScore == null || previous.averageSleepScore == null
          ? 'Недостаточно данных'
          : signed(current.averageSleepScore! - previous.averageSleepScore!, ' балла', decimals: 0),
        currentSamples: current.scoreSamples,
        previousSamples: previous.scoreSamples,
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
        'Последние $days дней: ' + dateRange(current.start, current.endExclusive) +
        ' · предыдущие $days дней: ' + dateRange(previous.start, previous.endExclusive) + '.',
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
    required this.maxValue, required this.formatValue, required this.onBucketTap,
  });
  final String title;
  final List<double?> values;
  final SleepDynamicsPeriod period;
  final double maxValue;
  final String Function(double) formatValue;
  final ValueChanged<int> onBucketTap;

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 14),
      SizedBox(height: 150, child: _DynamicsChart(
        values: values, period: period, maxValue: maxValue, formatValue: formatValue, onTap: onBucketTap,
      )),
    ],
  ));
}

class _DynamicsChart extends StatelessWidget {
  const _DynamicsChart({
    required this.values, required this.period, required this.maxValue, required this.formatValue,
    required this.onTap,
  });
  final List<double?> values;
  final SleepDynamicsPeriod period;
  final double maxValue;
  final String Function(double) formatValue;
  final ValueChanged<int> onTap;

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
      return Expanded(child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
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
          ]),
        ),
      ));
    }));
  }
}
