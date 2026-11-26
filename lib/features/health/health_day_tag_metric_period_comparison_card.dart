import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'health_day_tag_history_period.dart';
import 'health_day_tag_sleep_history.dart';

typedef _TagComparisonData = ({
  Map<String, List<Map<String, Object?>>> stagesBySession,
  Map<String, Map<String, Object?>> morningReportsBySession,
});

class HealthDayTagNightMetricPeriodComparisonCard extends StatefulWidget {
  const HealthDayTagNightMetricPeriodComparisonCard({
    super.key,
    required this.database,
    required this.sessions,
    required this.tagsByDay,
    required this.tag,
    required this.initialRange,
    required this.metric,
  });

  final SleepDatabase database;
  final List<SleepSession> sessions;
  final Map<DateTime, List<String>> tagsByDay;
  final String tag;
  final HealthDayTagHistoryRange initialRange;
  final HealthDayTagNightMetric metric;

  @override
  State<HealthDayTagNightMetricPeriodComparisonCard> createState() =>
      _HealthDayTagNightMetricPeriodComparisonCardState();
}

class _HealthDayTagNightMetricPeriodComparisonCardState
    extends State<HealthDayTagNightMetricPeriodComparisonCard> {
  late DateTimeRange _firstRange;
  late DateTimeRange _secondRange;
  late Future<_TagComparisonData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _secondRange = _inclusiveRange(widget.initialRange);
    _firstRange = _previousEqualRange(_secondRange);
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(
    covariant HealthDayTagNightMetricPeriodComparisonCard oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    final rangeChanged =
        oldWidget.initialRange.start != widget.initialRange.start ||
        oldWidget.initialRange.endExclusive != widget.initialRange.endExclusive;
    if (rangeChanged) {
      _secondRange = _inclusiveRange(widget.initialRange);
      _firstRange = _previousEqualRange(_secondRange);
      _dataFuture = _loadData();
    } else if (!identical(oldWidget.sessions, widget.sessions)) {
      _dataFuture = _loadData();
    }
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTimeRange _inclusiveRange(HealthDayTagHistoryRange range) =>
      DateTimeRange(
        start: _day(range.start),
        end: DateTime(
          range.endExclusive.year,
          range.endExclusive.month,
          range.endExclusive.day - 1,
        ),
      );

  DateTimeRange _previousEqualRange(DateTimeRange current) {
    final start = _day(current.start);
    final end = _day(current.end);
    final days = DateTime.utc(end.year, end.month, end.day)
            .difference(DateTime.utc(start.year, start.month, start.day))
            .inDays +
        1;
    final previousEnd = DateTime(start.year, start.month, start.day - 1);
    final previousStart = DateTime(
      previousEnd.year,
      previousEnd.month,
      previousEnd.day - days + 1,
    );
    return DateTimeRange(start: previousStart, end: previousEnd);
  }

  DateTime _endExclusive(DateTimeRange range) =>
      DateTime(range.end.year, range.end.month, range.end.day + 1);

  bool _containsNight(
    SleepSession session,
    DateTime start,
    DateTime endExclusive,
  ) {
    final endedAt = session.endedAt;
    if (session.deletedAt != null ||
        endedAt == null ||
        !endedAt.isAfter(session.startedAt)) {
      return false;
    }
    final day = _day(endedAt);
    return !day.isBefore(start) && day.isBefore(endExclusive);
  }

  Future<_TagComparisonData> _loadData() async {
    final firstStart = _day(_firstRange.start);
    final firstEnd = _endExclusive(_firstRange);
    final secondStart = _day(_secondRange.start);
    final secondEnd = _endExclusive(_secondRange);
    final relevant = widget.sessions.where((session) =>
        _containsNight(session, firstStart, firstEnd) ||
        _containsNight(session, secondStart, secondEnd));
    final ids = relevant.map((session) => session.id).toList();
    final stages = await widget.database.getStagesForSessions(ids);
    final morningReports =
        await widget.database.getMorningReportsForSessions(ids);
    return (
      stagesBySession: stages,
      morningReportsBySession: morningReports,
    );
  }

  Future<void> _pickRange(bool first) async {
    final initial = first ? _firstRange : _secondRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: _day(DateTime.now()),
      initialDateRange: initial,
      helpText: first ? 'Выберите первый период' : 'Выберите второй период',
    );
    if (picked == null || !mounted) return;
    final normalized = DateTimeRange(
      start: _day(picked.start),
      end: _day(picked.end),
    );
    setState(() {
      if (first) {
        _firstRange = normalized;
      } else {
        _secondRange = normalized;
      }
      _dataFuture = _loadData();
    });
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _rangeLabel(DateTimeRange range) =>
      '${_date(range.start)} — ${_date(range.end)}';

  String _number(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

  String _average(double? value) =>
      value == null ? '—' : '${_number(value)} ${widget.metric.unit}';

  String _signed(double? value) {
    if (value == null) return 'нет данных';
    return '${value > 0 ? '+' : ''}${_number(value)} ${widget.metric.unit}';
  }

  Widget _periodSummary(
    String title,
    DateTimeRange range,
    HealthDayTagNightMetricPeriodSummary summary,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title · ${_rangeLabel(range)}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              'С отметкой «${widget.tag}»: ${_average(summary.withTag.average)} · валидных измерений ${summary.withTag.validSamples} из ${summary.withTag.nights} ночей',
              style: const TextStyle(fontSize: 10, height: 1.4),
            ),
            Text(
              'Без отметки: ${_average(summary.withoutTag.average)} · валидных измерений ${summary.withoutTag.validSamples} из ${summary.withoutTag.nights} ночей',
              style: const TextStyle(
                  color: AppTheme.muted, fontSize: 10, height: 1.4),
            ),
            Text(
              'Разница (с отметкой − без отметки): ${_signed(summary.difference)}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Сравнение разницы между периодами',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Показатель: ${widget.metric.label}. В каждом периоде отдельно сравниваются ночи с выбранной отметкой и без неё. Показываются фактические средние и размеры выборок.',
              style: const TextStyle(
                  color: AppTheme.muted, fontSize: 10, height: 1.4),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickRange(true),
              icon: const Icon(Icons.date_range_outlined, size: 16),
              label: Text('Период 1: ${_rangeLabel(_firstRange)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickRange(false),
              icon: const Icon(Icons.date_range_outlined, size: 16),
              label: Text('Период 2: ${_rangeLabel(_secondRange)}'),
            ),
            const SizedBox(height: 5),
            FutureBuilder<_TagComparisonData>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return const Text(
                    'Не удалось загрузить данные сна для сравнения периодов.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11),
                  );
                }
                final comparison = HealthDayTagNightHistory.comparePeriods(
                  sessions: widget.sessions,
                  tagsByDay: widget.tagsByDay,
                  stagesBySession: snapshot.data?.stagesBySession ?? const {},
                  morningReportsBySession:
                      snapshot.data?.morningReportsBySession ?? const {},
                  tag: widget.tag,
                  firstStart: _firstRange.start,
                  firstEndExclusive: _endExclusive(_firstRange),
                  secondStart: _secondRange.start,
                  secondEndExclusive: _endExclusive(_secondRange),
                  metric: widget.metric,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _periodSummary('Период 1', _firstRange, comparison.first),
                    _periodSummary('Период 2', _secondRange, comparison.second),
                    const SizedBox(height: 8),
                    Text(
                      'Изменение разницы (период 2 − период 1): ${_signed(comparison.differenceChange)}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Сравнение описательное: оно показывает изменение разницы между группами, но не доказывает влияние отметки на сон. Отсутствующие измерения не заменяются нулями.',
                      style: TextStyle(
                          color: AppTheme.muted, fontSize: 10, height: 1.4),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
}
