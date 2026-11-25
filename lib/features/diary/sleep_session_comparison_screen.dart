import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_session_metrics.dart';

class SleepSessionComparisonScreen extends StatefulWidget {
  const SleepSessionComparisonScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<SleepSessionComparisonScreen> createState() => _SleepSessionComparisonScreenState();
}
class _SleepSessionComparisonScreenState extends State<SleepSessionComparisonScreen> {
  late Future<List<SleepSession>> _sessionsFuture;
  String? _firstId, _secondId;
  @override
  void initState() { super.initState(); _sessionsFuture = widget.database.getSessions(limit: 10000); }
  Future<void> _reload() async {
    setState(() => _sessionsFuture = widget.database.getSessions(limit: 10000));
    await _sessionsFuture;
  }
  SleepSession? _byId(List<SleepSession> sessions, String? id) {
    for (final s in sessions) { if (s.id == id) return s; }
    return null;
  }
  String _date(SleepSession s) => DateFormat('d MMM yyyy, HH:mm', 'ru').format(s.startedAt);
  String _duration(int? m) => m == null ? 'Нет данных' : m.toString() + ' мин (' + (m ~/ 60).toString() + ' ч ' + (m % 60).toString() + ' мин)';
  String _percent(double? v) => v == null ? 'Нет данных' : v.toStringAsFixed(1) + '%';
  String _rating(int? v) => v == null ? 'Не оценено' : v.toString() + ' из 5';
  String _delta(int? a, int? b, {String unit = 'мин'}) {
    if (a == null || b == null) return 'Недостаточно сопоставимых данных';
    final d = b - a;
    if (d == 0) return 'Без изменений';
    final amount = unit == 'мин' ? _duration(d.abs()) : d.abs().toString() + ' ' + unit;
    return d > 0 ? 'Во второй ночи больше на ' + amount : 'Во второй ночи меньше на ' + amount;
  }
  String _percentDelta(double? a, double? b) {
    if (a == null || b == null) return 'Недостаточно сопоставимых данных';
    final d = b - a;
    if (d.abs() < 0.05) return 'Без изменений';
    return d > 0 ? 'Во второй ночи выше на ' + d.toStringAsFixed(1) + ' п.п.' : 'Во второй ночи ниже на ' + d.abs().toStringAsFixed(1) + ' п.п.';
  }
  String _ratingDelta(int? a, int? b) {
    if (a == null || b == null) return 'Нет оценки для одной или обеих ночей';
    final d = b - a;
    if (d == 0) return 'Без изменений';
    return d > 0 ? 'Во второй ночи выше на ' + d.toString() + ' балл(а)' : 'Во второй ночи ниже на ' + d.abs().toString() + ' балл(а)';
  }
  Widget _column(String title, String value) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
    const SizedBox(height: 5),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 4, overflow: TextOverflow.ellipsis),
  ]));
  Widget _row(String title, String a, String b, String delta) => Padding(padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_column('Первая ночь', a), const SizedBox(width: 12), _column('Вторая ночь', b)]),
      const SizedBox(height: 6),
      Text(delta, style: const TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.35)),
    ]));
  Widget _picker(String label, String? value, List<SleepSession> sessions, ValueChanged<String?> onChanged) =>
    DropdownButtonFormField<String>(initialValue: value, isExpanded: true, decoration: InputDecoration(labelText: label),
      hint: const Text('Выберите ночь'),
      items: sessions.map((s) => DropdownMenuItem(value: s.id, child: Text(_date(s), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged);
  Widget _comparison(SleepSession first, SleepSession second) => FutureBuilder<Map<String, List<Map<String, Object?>>>>(
    future: widget.database.getStagesForSessions([first.id, second.id]),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const SectionCard(child: LinearProgressIndicator());
      if (snapshot.hasError) return SectionCard(child: Text('Не удалось загрузить фазы сна: ' + snapshot.error.toString()));
      final stages = snapshot.data ?? const <String, List<Map<String, Object?>>>{};
      final a = SleepSessionMetrics.calculate(session: first, stages: stages[first.id] ?? const []);
      final b = SleepSessionMetrics.calculate(session: second, stages: stages[second.id] ?? const []);
      final phases = <String>{...a.stageBreakdownMinutes.keys, ...b.stageBreakdownMinutes.keys}.toList()..sort();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('Фактическая длительность сна', _duration(a.sleepDurationMinutes), _duration(b.sleepDurationMinutes), _delta(a.sleepDurationMinutes, b.sleepDurationMinutes)),
          const Divider(height: 1),
          _row('Время в постели', _duration(a.timeInBedMinutes), _duration(b.timeInBedMinutes), _delta(a.timeInBedMinutes, b.timeInBedMinutes)),
          const Divider(height: 1),
          _row('Латентность засыпания', _duration(a.sleepLatencyMinutes), _duration(b.sleepLatencyMinutes), _delta(a.sleepLatencyMinutes, b.sleepLatencyMinutes)),
          const Divider(height: 1),
          _row('Эффективность сна', _percent(a.sleepEfficiencyPercent), _percent(b.sleepEfficiencyPercent), _percentDelta(a.sleepEfficiencyPercent, b.sleepEfficiencyPercent)),
          const Divider(height: 1),
          _row('Покрытие фаз', _percent(a.stageCoveragePercent), _percent(b.stageCoveragePercent), _percentDelta(a.stageCoveragePercent, b.stageCoveragePercent)),
          const Divider(height: 1),
          _row(
            'Количество пробуждений',
            a.hasAwakeSamples && a.stageCoveragePercent != null && a.stageCoveragePercent! >= 80
                ? a.awakeningCount.toString() : 'Нет данных',
            b.hasAwakeSamples && b.stageCoveragePercent != null && b.stageCoveragePercent! >= 80
                ? b.awakeningCount.toString() : 'Нет данных',
            _delta(
              a.hasAwakeSamples && a.stageCoveragePercent != null && a.stageCoveragePercent! >= 80 ? a.awakeningCount : null,
              b.hasAwakeSamples && b.stageCoveragePercent != null && b.stageCoveragePercent! >= 80 ? b.awakeningCount : null,
              unit: 'эп.',
            ),
          ),
          const Divider(height: 1),
          _row('Суммарное бодрствование', _duration(a.awakeStageMinutes), _duration(b.awakeStageMinutes), _delta(a.awakeStageMinutes, b.awakeStageMinutes)),
          const Divider(height: 1),
          _row('Самочувствие', _rating(first.morningRating), _rating(second.morningRating), _ratingDelta(first.morningRating, second.morningRating)),
        ])),
        if (phases.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Распределение фаз сна', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            for (var i = 0; i < phases.length; i++) ...[
              _row(phases[i], _duration(a.stageBreakdownMinutes[phases[i]]), _duration(b.stageBreakdownMinutes[phases[i]]),
                _delta(a.stageBreakdownMinutes[phases[i]], b.stageBreakdownMinutes[phases[i]])),
              if (i != phases.length - 1) const Divider(height: 1),
            ],
          ])),
        ] else const SectionCard(child: Text('Данные о фазах отсутствуют. Фазы не рассчитываются по предположениям.', style: TextStyle(color: AppTheme.muted))),
        const SizedBox(height: 12),
        SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Дополнительные сведения', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          _row('Начало сессии', _date(first), _date(second), 'Фактически сохранённое время.'),
          const Divider(height: 1),
          _row('Окончание сессии',
            first.endedAt == null ? 'Не завершена' : DateFormat('d MMM yyyy, HH:mm', 'ru').format(first.endedAt!),
            second.endedAt == null ? 'Не завершена' : DateFormat('d MMM yyyy, HH:mm', 'ru').format(second.endedAt!),
            'Незавершённые сессии не участвуют в сравнении длительности.'),
          const Divider(height: 1),
          _row('Источник', first.source == 'manual' ? 'Вручную' : first.source, second.source == 'manual' ? 'Вручную' : second.source, 'Источники отображаются без преобразования.'),
          const Divider(height: 1),
          _row('Заметки', first.note?.trim().isNotEmpty == true ? first.note! : 'Нет заметки', second.note?.trim().isNotEmpty == true ? second.note! : 'Нет заметки', 'Заметки показаны без изменений.'),
        ])),
        const SizedBox(height: 10),
        const Text('Эффективность показывается только при достаточном покрытии фаз. Отсутствующие измерения не заменяются нулями. Различия не доказывают причинно-следственную связь.',
          style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
      ]);
    });
  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _sessionsFuture,
    builder: (context, snapshot) {
      final sessions = snapshot.data ?? const <SleepSession>[];
      final first = _byId(sessions, _firstId), second = _byId(sessions, _secondId);
      return Scaffold(appBar: AppBar(title: const Text('Сравнение ночей')),
        body: snapshot.connectionState == ConnectionState.waiting
          ? const Center(child: CircularProgressIndicator())
          : snapshot.hasError ? Center(child: Text('Не удалось загрузить дневник: ' + snapshot.error.toString()))
          : RefreshIndicator(onRefresh: _reload, child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('Сравните две ночи', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text('Выберите любые две сохранённые ночи. Сравнение включает только фактически доступные данные.', style: TextStyle(color: AppTheme.muted, height: 1.45)),
            const SizedBox(height: 18),
            if (sessions.length < 2) const SectionCard(child: Text('Для сравнения нужны как минимум две сохранённые ночи.', style: TextStyle(color: AppTheme.muted)))
            else ...[
              SectionCard(child: Column(children: [
                _picker('Первая ночь', _firstId, sessions, (v) => setState(() { _firstId = v; if (_secondId == v) _secondId = null; })),
                const SizedBox(height: 14),
                _picker('Вторая ночь', _secondId, sessions, (v) => setState(() => _secondId = v)),
              ])),
              const SizedBox(height: 14),
              if (first != null && second != null)
                if (first.id == second.id) const SectionCard(child: Text('Выберите две разные ночи.', style: TextStyle(color: AppTheme.muted)))
                else _comparison(first, second)
              else const SectionCard(child: Text('Выберите первую и вторую ночь, чтобы увидеть сравнение.', style: TextStyle(color: AppTheme.muted))),
            ],
          ])));
    });
}
