import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_session_metrics.dart';

class ReferenceNightComparisonScreen extends StatefulWidget {
  const ReferenceNightComparisonScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<ReferenceNightComparisonScreen> createState() => _ReferenceNightComparisonScreenState();
}

class _ReferenceNightComparisonScreenState extends State<ReferenceNightComparisonScreen> {
  late Future<List<SleepSession>> _sessionsFuture;
  String? _referenceId;
  @override
  void initState() {
    super.initState();
    _sessionsFuture = widget.database.getSessions(limit: 10000);
  }
  Future<void> _reload() async {
    setState(() => _sessionsFuture = widget.database.getSessions(limit: 10000));
    await _sessionsFuture;
  }
  String _date(SleepSession s) => DateFormat('d MMM yyyy, HH:mm', 'ru').format(s.startedAt);
  String _duration(int? m) => m == null ? 'Нет данных' : '${m ~/ 60} ч ${m % 60} мин';
  String _delta(int? value, int? reference, {String unit = 'мин'}) {
    if (value == null || reference == null) return 'Недостаточно сопоставимых данных';
    final d = value - reference;
    if (d == 0) return 'Без изменений';
    final n = d.abs();
    final hours = n ~/ 60;
    final minutes = n % 60;
    final amount = unit == 'мин' ? (hours > 0 ? '$hours ч $minutes мин' : '$minutes мин') : '$n $unit';
    return d > 0 ? 'На $amount больше эталона' : 'На $amount меньше эталона';
  }
  SleepSessionMetrics _metrics(SleepSession s, Map<String, List<Map<String, Object?>>> stages) =>
      SleepSessionMetrics.calculate(session: s, stages: stages[s.id] ?? const []);
  Widget _metric(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
    ]),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _sessionsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (snapshot.hasError) return Scaffold(appBar: AppBar(title: const Text('Эталонная ночь')), body: Center(child: Text('Не удалось загрузить дневник: ${snapshot.error}')));
      final sessions = (snapshot.data ?? const <SleepSession>[])
          .where((s) => !s.isOpen && s.duration != null && !s.duration!.isNegative).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (_referenceId == null || !sessions.any((s) => s.id == _referenceId)) {
        _referenceId = sessions.isEmpty ? null : sessions.first.id;
      }
      SleepSession? reference;
      for (final s in sessions) { if (s.id == _referenceId) { reference = s; break; } }
      return Scaffold(
        appBar: AppBar(title: const Text('Сравнение с эталонной ночью')),
        body: RefreshIndicator(onRefresh: _reload, child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Выберите эталонную ночь', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('Остальные завершённые ночи будут сопоставлены с выбранной записью. Эталон можно менять в любой момент.', style: TextStyle(color: AppTheme.muted, height: 1.4)),
          const SizedBox(height: 14),
          if (sessions.isEmpty) const SectionCard(child: Text('Для сравнения пока нет завершённых ночей.'))
          else ...[
            SectionCard(child: DropdownButtonFormField<String>(
              value: _referenceId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Эталонная ночь'),
              items: sessions.map((s) => DropdownMenuItem(value: s.id, child: Text(_date(s), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _referenceId = v),
            )),
            const SizedBox(height: 14),
            if (reference != null)
              FutureBuilder<Map<String, List<Map<String, Object?>>>>(
                future: widget.database.getStagesForSessions(sessions.map((s) => s.id).toList()),
                builder: (context, stageSnapshot) {
                  if (stageSnapshot.connectionState == ConnectionState.waiting) return const SectionCard(child: LinearProgressIndicator());
                  if (stageSnapshot.hasError) return SectionCard(child: Text('Не удалось загрузить фазы сна: ${stageSnapshot.error}'));
                  final stages = stageSnapshot.data ?? const <String, List<Map<String, Object?>>>{};
                  final baseline = _metrics(reference!, stages);
                  final others = sessions.where((s) => s.id != reference!.id).toList();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Эталонные показатели', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(_date(reference!), style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      _metric('Длительность сна', _duration(baseline.sleepDurationMinutes)),
                      _metric('Время в постели', _duration(baseline.timeInBedMinutes)),
                      _metric('Эффективность', baseline.sleepEfficiencyPercent == null ? 'Нет данных' : '${baseline.sleepEfficiencyPercent!.toStringAsFixed(1)}%'),
                      _metric('Пробуждения', '${baseline.awakeningCount}'),
                      _metric('Бодрствование', _duration(baseline.awakeStageMinutes)),
                      _metric('Самочувствие', reference!.morningRating == null ? 'Не оценено' : '${reference.morningRating} из 5'),
                    ])),
                    const SizedBox(height: 14),
                    Text('Другие ночи · ${others.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 8),
                    if (others.isEmpty) const SectionCard(child: Text('Выберите эталонную ночь, чтобы сравнить её с другими записями.'))
                    else for (final night in others) Builder(builder: (context) {
                      final metric = _metrics(night, stages);
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_date(night), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _metric('Длительность сна', _duration(metric.sleepDurationMinutes)),
                        Text(_delta(metric.sleepDurationMinutes, baseline.sleepDurationMinutes), style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
                        const Divider(height: 16),
                        _metric('Эффективность', metric.sleepEfficiencyPercent == null ? 'Нет данных' : '${metric.sleepEfficiencyPercent!.toStringAsFixed(1)}%'),
                        final awakeningDelta = _delta(metric.awakeningCount, baseline.awakeningCount, unit: 'эп.');
                        _metric('Пробуждения', '${metric.awakeningCount} · $awakeningDelta'),
                        _metric('Бодрствование', _duration(metric.awakeStageMinutes)),
                        _metric('Самочувствие', night.morningRating == null ? 'Не оценено' : '${night.morningRating} из 5'),
                        if (night.note?.trim().isNotEmpty == true) ...[const Divider(height: 16), Text(night.note!, style: const TextStyle(color: AppTheme.muted, fontSize: 12))],
                      ])));
                    }),
                    const SizedBox(height: 8),
                    const Text('Сравнение описывает различия, но не устанавливает их причины. Если у ночи нет фаз или оценки, показатель остаётся без данных и не заменяется нулём.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
                  ]);
                },
              ),
          ],
        ])),
      );
    },
  );
}
