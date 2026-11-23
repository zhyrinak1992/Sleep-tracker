import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../data/pdf_report_service.dart';
import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_period_comparison.dart';

class _PeriodComparisonData {
  const _PeriodComparisonData({required this.sessions, required this.stages, required this.morning, required this.audio});
  final List<SleepSession> sessions;
  final Map<String, List<Map<String, Object?>>> stages;
  final Map<String, Map<String, Object?>> morning;
  final List<Map<String, Object?>> audio;
}

class SleepPeriodComparisonScreen extends StatefulWidget {
  const SleepPeriodComparisonScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<SleepPeriodComparisonScreen> createState() => _SleepPeriodComparisonScreenState();
}

class _SleepPeriodComparisonScreenState extends State<SleepPeriodComparisonScreen> {
  late Future<_PeriodComparisonData> _future;
  late DateTime _currentStart;
  late DateTime _currentEnd;
  late DateTime _previousStart;
  late DateTime _previousEnd;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _currentEnd = DateTime(today.year, today.month, today.day);
    _currentStart = _currentEnd.subtract(const Duration(days: 29));
    _previousEnd = _currentStart.subtract(const Duration(days: 1));
    _previousStart = _previousEnd.subtract(const Duration(days: 29));
    _future = _load();
  }

  Future<_PeriodComparisonData> _load() async {
    final sessions = await widget.database.getSessions(limit: 10000);
    final ids = sessions.where((s) => s.endedAt != null && s.duration != null && s.duration!.inMinutes > 0)
      .map((s) => s.id).toList();
    final stages = await widget.database.getStagesForSessions(ids);
    final morning = await widget.database.getMorningReportsForSessions(ids);
    final audio = await widget.database.getAudioEvents();
    return _PeriodComparisonData(sessions: sessions, stages: stages, morning: morning, audio: audio);
  }

  Future<void> _chooseRange(bool current) async {
    final start = current ? _currentStart : _previousStart;
    final end = current ? _currentEnd : _previousEnd;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: current ? 'Выберите текущий период' : 'Выберите предыдущий период',
      saveText: 'Применить',
      cancelText: 'Отмена',
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (current) {
        _currentStart = selected.start;
        _currentEnd = selected.end;
      } else {
        _previousStart = selected.start;
        _previousEnd = selected.end;
      }
    });
  }

  String _range(DateTime start, DateTime end) =>
      '${DateFormat('d MMM yyyy', 'ru').format(start)} — ${DateFormat('d MMM yyyy', 'ru').format(end)}';

  String _duration(double? minutes) {
    if (minutes == null) return 'Нет данных';
    final value = minutes.round();
    return '${value ~/ 60} ч ${value % 60} мин';
  }

  String _minutes(double? value) {
    if (value == null) return 'Недостаточно данных';
    return '${value.round()} мин';
  }

  String _variabilityChange(double? a, double? b) {
    if (a == null || b == null) return 'Недостаточно данных для сравнения';
    final delta = a - b;
    if (delta.abs() < 0.5) return 'Разброс практически не изменился';
    final amount = delta.abs().round();
    return delta < 0
        ? 'В периоде A разброс меньше на $amount мин'
        : 'В периоде B разброс меньше на $amount мин';
  }

  String _clock(int? minute) {
    if (minute == null) return 'Нет данных';
    return (minute ~/ 60).toString().padLeft(2, '0') + ':' + (minute % 60).toString().padLeft(2, '0');
  }

  String _clockChange(int? a, int? b) {
    if (a == null || b == null) return 'Недостаточно данных';
    var delta = a - b;
    if (delta > 720) delta -= 1440;
    if (delta < -720) delta += 1440;
    if (delta == 0) return 'Без изменения';
    return delta > 0 ? delta.toString() + ' мин позже' : delta.abs().toString() + ' мин раньше';
  }

  String _metric(double? value, String suffix, int samples, {int decimals = 1}) =>
    value == null ? 'Нет данных' : value.toStringAsFixed(decimals) + suffix + ' · n=' + samples.toString();

  String _delta(double? value, String suffix, {int decimals = 1}) {
    if (value == null) return 'Недостаточно данных';
    final sign = value > 0 ? '+' : '';
    return sign + value.toStringAsFixed(decimals) + suffix;
  }

  String _categories(Map<String, int> values) => values.isEmpty
    ? 'Нет событий'
    : values.entries.map((entry) => entry.key + ': ' + entry.value.toString()).join(' · ');

  String _change(double? value, {bool percentage = false}) {
    if (value == null) return 'Недостаточно данных для сравнения';
    final sign = value > 0 ? '+' : '';
    return percentage
      ? '$sign${value.toStringAsFixed(1)}%'
      : '$sign${value.toStringAsFixed(1)} балла';
  }

  Future<void> _exportComparison(
    _PeriodComparisonData data,
    SleepRangeSummary current,
    SleepRangeSummary previous,
    SleepPeriodDetailSummary currentDetails,
    SleepPeriodDetailSummary previousDetails,
  ) async {
    String clockDelta(int? a, int? b) => _clockChange(a, b);
    final durationDelta = current.averageDurationMinutes == null || previous.averageDurationMinutes == null
      ? null : current.averageDurationMinutes! - previous.averageDurationMinutes!;
    final durationPercent = SleepPeriodComparison.percentageChange(
      current.averageDurationMinutes, previous.averageDurationMinutes);
    final ratingDelta = current.averageRating == null || previous.averageRating == null
      ? null : current.averageRating! - previous.averageRating!;
    final metrics = <Map<String, Object?>>[
      {
        'label': 'Средняя длительность',
        'a': _duration(current.averageDurationMinutes) + ' · n=${current.completed}',
        'b': _duration(previous.averageDurationMinutes) + ' · n=${previous.completed}',
        'change': durationDelta == null ? 'Недостаточно данных' :
          '${durationDelta > 0 ? '+' : ''}${_duration(durationDelta.abs())} · ${_change(durationPercent, percentage: true)}',
      },
      {
        'label': 'Оценка самочувствия',
        'a': current.averageRating == null ? 'Нет данных' : '${current.averageRating!.toStringAsFixed(1)} / 5 · n=${current.rated}',
        'b': previous.averageRating == null ? 'Нет данных' : '${previous.averageRating!.toStringAsFixed(1)} / 5 · n=${previous.rated}',
        'change': _change(ratingDelta),
      },
      {
        'label': 'Эффективность сна',
        'a': _metric(currentDetails.averageEfficiency, '%', currentDetails.efficiencySamples),
        'b': _metric(previousDetails.averageEfficiency, '%', previousDetails.efficiencySamples),
        'change': currentDetails.averageEfficiency == null || previousDetails.averageEfficiency == null ? 'Недостаточно данных' :
          _delta(currentDetails.averageEfficiency! - previousDetails.averageEfficiency!, ' п. п.'),
      },
      {
        'label': 'Пробуждения',
        'a': _metric(currentDetails.averageAwakenings, '', currentDetails.awakeningSamples),
        'b': _metric(previousDetails.averageAwakenings, '', previousDetails.awakeningSamples),
        'change': currentDetails.averageAwakenings == null || previousDetails.averageAwakenings == null ? 'Недостаточно данных' :
          _delta(currentDetails.averageAwakenings! - previousDetails.averageAwakenings!, ''),
      },
      {
        'label': 'Субъективное качество сна',
        'a': _metric(currentDetails.averageQuality, ' / 5', currentDetails.qualitySamples),
        'b': _metric(previousDetails.averageQuality, ' / 5', previousDetails.qualitySamples),
        'change': currentDetails.averageQuality == null || previousDetails.averageQuality == null ? 'Недостаточно данных' :
          _delta(currentDetails.averageQuality! - previousDetails.averageQuality!, ' балла'),
      },
      {
        'label': 'Утреннее самочувствие',
        'a': _metric(currentDetails.averageWellbeing, ' / 5', currentDetails.wellbeingSamples),
        'b': _metric(previousDetails.averageWellbeing, ' / 5', previousDetails.wellbeingSamples),
        'change': currentDetails.averageWellbeing == null || previousDetails.averageWellbeing == null ? 'Недостаточно данных' :
          _delta(currentDetails.averageWellbeing! - previousDetails.averageWellbeing!, ' балла'),
      },
      {
        'label': 'Типичное время засыпания',
        'a': _clock(currentDetails.typicalBedtimeMinute),
        'b': _clock(previousDetails.typicalBedtimeMinute),
        'change': clockDelta(currentDetails.typicalBedtimeMinute, previousDetails.typicalBedtimeMinute),
      },
      {
        'label': 'Типичное время пробуждения',
        'a': _clock(currentDetails.typicalWakeMinute),
        'b': _clock(previousDetails.typicalWakeMinute),
        'change': clockDelta(currentDetails.typicalWakeMinute, previousDetails.typicalWakeMinute),
      },
      {
        'label': 'Стабильность засыпания',
        'a': _minutes(current.bedtimeDeviationMinutes) + ' · n=${current.regularitySampleCount}',
        'b': _minutes(previous.bedtimeDeviationMinutes) + ' · n=${previous.regularitySampleCount}',
        'change': _variabilityChange(current.bedtimeDeviationMinutes, previous.bedtimeDeviationMinutes),
      },
      {
        'label': 'Стабильность пробуждения',
        'a': _minutes(current.wakeTimeDeviationMinutes) + ' · n=${current.regularitySampleCount}',
        'b': _minutes(previous.wakeTimeDeviationMinutes) + ' · n=${previous.regularitySampleCount}',
        'change': _variabilityChange(current.wakeTimeDeviationMinutes, previous.wakeTimeDeviationMinutes),
      },
      {
        'label': 'Звуковые события',
        'a': '${currentDetails.audio.eventCount} событий · ${currentDetails.audio.nightsWithEvents} ночей',
        'b': '${previousDetails.audio.eventCount} событий · ${previousDetails.audio.nightsWithEvents} ночей',
        'change': 'События учитываются по завершённым ночным сессиям',
      },
    ];

    List<Map<String, Object?>> nightly(SleepRangeSummary range) =>
      range.sessions.where((session) => session.endedAt != null &&
        session.duration != null && session.duration!.inMinutes > 0).map((session) {
          final stages = data.stages[session.id] ?? const <Map<String, Object?>>[];
          final calculated = SleepSessionMetrics.calculate(session: session, stages: stages);
          final report = data.morning[session.id];
          String shown(Object? value, {String suffix = ''}) =>
            value is num && value.toDouble().isFinite ? value.toStringAsFixed(1) + suffix : '—';
          return <String, Object?>{
            'date': DateFormat('dd.MM.yyyy', 'ru').format(session.startedAt),
            'start': DateFormat('HH:mm', 'ru').format(session.startedAt),
            'end': DateFormat('HH:mm', 'ru').format(session.endedAt!),
            'duration': _duration(calculated.sleepDurationMinutes?.toDouble() ?? session.duration!.inMinutes.toDouble()),
            'efficiency': shown(calculated.sleepEfficiencyPercent, suffix: '%'),
            'awakenings': stages.isNotEmpty && calculated.stageCoveragePercent != null
              ? calculated.awakeningCount.toString() : '—',
            'quality': shown(report?['sleep_quality'], suffix: ' / 5'),
            'wellbeing': shown(report?['wellbeing'], suffix: ' / 5'),
          };
        }).toList();

    await PdfReportService.exportPeriodComparison(
      title: 'Сравнение произвольных периодов',
      periodALabel: _range(current.start, current.endExclusive.subtract(const Duration(days: 1))),
      periodBLabel: _range(previous.start, previous.endExclusive.subtract(const Duration(days: 1))),
      metrics: metrics,
      nightsA: nightly(current),
      nightsB: nightly(previous),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PeriodComparisonData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Не удалось загрузить записи сна: ${snapshot.error}'),
        ));
      }
      final data = snapshot.data!;
      final sessions = data.sessions;
      final current = SleepPeriodComparison.summarize(sessions, _currentStart, _currentEnd);
      final previous = SleepPeriodComparison.summarize(sessions, _previousStart, _previousEnd);
      final currentDetails = SleepPeriodDetailSummary.summarize(
        range: current, stagesBySession: data.stages, morningReports: data.morning, audioEvents: data.audio,
      );
      final previousDetails = SleepPeriodDetailSummary.summarize(
        range: previous, stagesBySession: data.stages, morningReports: data.morning, audioEvents: data.audio,
      );
      final durationDelta = current.averageDurationMinutes == null || previous.averageDurationMinutes == null
        ? null : current.averageDurationMinutes! - previous.averageDurationMinutes!;
      final durationPercent = SleepPeriodComparison.percentageChange(
        current.averageDurationMinutes, previous.averageDurationMinutes);
      final ratingDelta = current.averageRating == null || previous.averageRating == null
        ? null : current.averageRating! - previous.averageRating!;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const Text('Сравнение произвольных периодов',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Выберите любые два диапазона дат. Сравниваются длительность, эффективность, пробуждения, утренние оценки, звуковые события и регулярность фактического времени сна. Для каждого показателя отображается собственный размер выборки; время сравнивается с учётом перехода через полночь.',
            style: TextStyle(color: AppTheme.muted, height: 1.4)),
          const SizedBox(height: 18),
          SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Период A', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(_range(_currentStart, _currentEnd)),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: () => _chooseRange(true),
              icon: const Icon(Icons.date_range),
              label: const Text('Изменить даты'),
            )),
            const Divider(color: AppTheme.surfaceLight),
            const Text('Период B', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(_range(_previousStart, _previousEnd)),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: () => _chooseRange(false),
              icon: const Icon(Icons.date_range),
              label: const Text('Изменить даты'),
            )),
          ])),
          const SizedBox(height: 14),
          _ComparisonCard(title: 'Средняя длительность', a: _duration(current.averageDurationMinutes) + ' · n=' + current.completed.toString(),
            b: _duration(previous.averageDurationMinutes) + ' · n=' + previous.completed.toString(),
            change: durationDelta == null ? 'Недостаточно данных' :
              '${durationDelta > 0 ? '+' : ''}${_duration(durationDelta.abs())} · ${_change(durationPercent, percentage: true)}'),
          const SizedBox(height: 10),
          _ComparisonCard(title: 'Средняя оценка самочувствия',
            a: current.averageRating == null ? 'Нет оценок' : '${current.averageRating!.toStringAsFixed(1)} / 5 · n=${current.rated}',
            b: previous.averageRating == null ? 'Нет оценок' : '${previous.averageRating!.toStringAsFixed(1)} / 5 · n=${previous.rated}',
            change: _change(ratingDelta)),
          _ComparisonCard(
            title: 'Эффективность сна',
            a: _metric(currentDetails.averageEfficiency, '%', currentDetails.efficiencySamples),
            b: _metric(previousDetails.averageEfficiency, '%', previousDetails.efficiencySamples),
            change: currentDetails.averageEfficiency == null || previousDetails.averageEfficiency == null
              ? 'Недостаточно сопоставимых данных'
              : _delta(currentDetails.averageEfficiency! - previousDetails.averageEfficiency!, ' п. п.'),
          ),
          const SizedBox(height: 10),
          _ComparisonCard(
            title: 'Среднее число пробуждений',
            a: _metric(currentDetails.averageAwakenings, '', currentDetails.awakeningSamples),
            b: _metric(previousDetails.averageAwakenings, '', previousDetails.awakeningSamples),
            change: currentDetails.averageAwakenings == null || previousDetails.averageAwakenings == null
              ? 'Недостаточно сопоставимых данных'
              : _delta(currentDetails.averageAwakenings! - previousDetails.averageAwakenings!, ''),
          ),
          const SizedBox(height: 10),
          _ComparisonCard(
            title: 'Субъективное качество сна',
            a: _metric(currentDetails.averageQuality, ' / 5', currentDetails.qualitySamples),
            b: _metric(previousDetails.averageQuality, ' / 5', previousDetails.qualitySamples),
            change: currentDetails.averageQuality == null || previousDetails.averageQuality == null
              ? 'Недостаточно сопоставимых данных'
              : _delta(currentDetails.averageQuality! - previousDetails.averageQuality!, ' балла'),
          ),
          const SizedBox(height: 10),
          _ComparisonCard(
            title: 'Утреннее самочувствие',
            a: _metric(currentDetails.averageWellbeing, ' / 5', currentDetails.wellbeingSamples),
            b: _metric(previousDetails.averageWellbeing, ' / 5', previousDetails.wellbeingSamples),
            change: currentDetails.averageWellbeing == null || previousDetails.averageWellbeing == null
              ? 'Недостаточно сопоставимых данных'
              : _delta(currentDetails.averageWellbeing! - previousDetails.averageWellbeing!, ' балла'),
          ),
          const SizedBox(height: 10),
          _ComparisonCard(
            title: 'Типичное время засыпания',
            a: _clock(currentDetails.typicalBedtimeMinute) + ' · n=' + currentDetails.regularitySamples.toString(),
            b: _clock(previousDetails.typicalBedtimeMinute) + ' · n=' + previousDetails.regularitySamples.toString(),
            change: _clockChange(currentDetails.typicalBedtimeMinute, previousDetails.typicalBedtimeMinute),
          ),
          const SizedBox(height: 10),
          _ComparisonCard(
            title: 'Типичное время пробуждения',
            a: _clock(currentDetails.typicalWakeMinute) + ' · n=' + currentDetails.regularitySamples.toString(),
            b: _clock(previousDetails.typicalWakeMinute) + ' · n=' + previousDetails.regularitySamples.toString(),
            change: _clockChange(currentDetails.typicalWakeMinute, previousDetails.typicalWakeMinute),
          ),
          const SizedBox(height: 10),
          _ComparisonCard(
            title: 'Звуковые события',
            a: currentDetails.audio.eventCount.toString() + ' событий · ' + currentDetails.audio.nightsWithEvents.toString() + ' ночей',
            b: previousDetails.audio.eventCount.toString() + ' событий · ' + previousDetails.audio.nightsWithEvents.toString() + ' ночей',
            change: 'События учитываются по завершённым ночным сессиям',
          ),
          if (currentDetails.audio.categoryCounts.isNotEmpty || previousDetails.audio.categoryCounts.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ComparisonCard(
              title: 'Категории звуковых событий',
              a: _categories(currentDetails.audio.categoryCounts),
              b: _categories(previousDetails.audio.categoryCounts),
              change: 'Используется сохранённая классификация событий',
            ),
          ],
          const SizedBox(height: 10),
          _ComparisonCard(title: 'Стабильность времени засыпания',
            a: _minutes(current.bedtimeDeviationMinutes) + ' · n=' + current.regularitySampleCount.toString(),
            b: _minutes(previous.bedtimeDeviationMinutes) + ' · n=' + previous.regularitySampleCount.toString(),
            change: _variabilityChange(current.bedtimeDeviationMinutes, previous.bedtimeDeviationMinutes)),
          const SizedBox(height: 10),
          _ComparisonCard(title: 'Стабильность времени пробуждения',
            a: _minutes(current.wakeTimeDeviationMinutes) + ' · n=' + current.regularitySampleCount.toString(),
            b: _minutes(previous.wakeTimeDeviationMinutes) + ' · n=' + previous.regularitySampleCount.toString(),
            change: _variabilityChange(current.wakeTimeDeviationMinutes, previous.wakeTimeDeviationMinutes)),
          const SizedBox(height: 10),
          _ComparisonCard(title: 'Записи сна',
            a: '${current.sessions.length} всего · ${current.completed} завершено · ${current.rated} с оценкой',
            b: '${previous.sessions.length} всего · ${previous.completed} завершено · ${previous.rated} с оценкой',
            change: 'Количество записей сравнивается напрямую'),
          const SizedBox(height: 12),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _exportComparison(data, current, previous, currentDetails, previousDetails),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Экспортировать сравнение в PDF'),
          ),
          const SizedBox(height: 8),
          const Text('Стабильность — медианное абсолютное отклонение фактического времени засыпания и пробуждения от круговой медианы. В выборку регулярности входят только записи с фактическими границами сна, не отмеченные как ручные или изменённые; нужно не менее двух таких ночей. Длительность в карточке отражает сохранённый интервал ночной сессии. Отсутствующие измерения не заменяются нулями. Сравнение не устанавливает причины изменений, отсутствующие измерения не заменяются нулями.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
        ],
      );
    },
  );
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.title, required this.a, required this.b, required this.change});
  final String title, a, b, change;

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Период A', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(a, style: const TextStyle(fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Период B', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
        ])),
      ]),
      const SizedBox(height: 8),
      Text(change, style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
    ],
  ));
}
