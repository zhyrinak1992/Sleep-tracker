import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_period_comparison.dart';

class SleepPeriodComparisonScreen extends StatefulWidget {
  const SleepPeriodComparisonScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<SleepPeriodComparisonScreen> createState() => _SleepPeriodComparisonScreenState();
}

class _SleepPeriodComparisonScreenState extends State<SleepPeriodComparisonScreen> {
  late Future<List<SleepSession>> _future;
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
    _future = widget.database.getSessions(limit: 10000);
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

  String _change(double? value, {bool percentage = false}) {
    if (value == null) return 'Недостаточно данных для сравнения';
    final sign = value > 0 ? '+' : '';
    return percentage
      ? '$sign${value.toStringAsFixed(1)}%'
      : '$sign${value.toStringAsFixed(1)} балла';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
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
      final sessions = snapshot.data ?? const <SleepSession>[];
      final current = SleepPeriodComparison.summarize(sessions, _currentStart, _currentEnd);
      final previous = SleepPeriodComparison.summarize(sessions, _previousStart, _previousEnd);
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
          const Text('Выберите любые два диапазона дат. В расчёт попадают только реальные записи; незавершённые ночи не участвуют в средней длительности.',
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
          _ComparisonCard(title: 'Средняя длительность', a: _duration(current.averageDurationMinutes),
            b: _duration(previous.averageDurationMinutes),
            change: durationDelta == null ? 'Недостаточно данных' :
              '${durationDelta > 0 ? '+' : ''}${_duration(durationDelta.abs())} · ${_change(durationPercent, percentage: true)}'),
          const SizedBox(height: 10),
          _ComparisonCard(title: 'Средняя оценка самочувствия',
            a: current.averageRating == null ? 'Нет оценок' : '${current.averageRating!.toStringAsFixed(1)} / 5',
            b: previous.averageRating == null ? 'Нет оценок' : '${previous.averageRating!.toStringAsFixed(1)} / 5',
            change: _change(ratingDelta)),
          const SizedBox(height: 10),
          _ComparisonCard(title: 'Записи сна',
            a: '${current.sessions.length} всего · ${current.completed} завершено · ${current.rated} с оценкой',
            b: '${previous.sessions.length} всего · ${previous.completed} завершено · ${previous.rated} с оценкой',
            change: 'Количество записей сравнивается напрямую'),
          const SizedBox(height: 12),
          const Text('Сравнение описывает различия между выбранными периодами и само по себе не устанавливает причины изменений. Отсутствующие измерения не заменяются нулями.',
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
