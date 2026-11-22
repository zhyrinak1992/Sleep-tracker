import 'package:flutter/material.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'weekday_comparison.dart';

class WeekdayComparisonScreen extends StatefulWidget {
  const WeekdayComparisonScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<WeekdayComparisonScreen> createState() => _WeekdayComparisonScreenState();
}

class _WeekdayComparisonScreenState extends State<WeekdayComparisonScreen> {
  late Future<List<SleepSession>> _sessions;
  final Set<int> _groupA = {1,2,3,4,5};
  ComparisonRange _range = ComparisonRange.days90;

  @override
  void initState() {
    super.initState();
    _sessions = widget.database.getSessions(limit: 10000);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сон по дням недели')),
    body: FutureBuilder<List<SleepSession>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Не удалось загрузить записи: ${snapshot.error}'));
        final sessions = snapshot.data ?? const <SleepSession>[];
        final allDays = {1,2,3,4,5,6,7};
        final groupB = allDays.difference(_groupA);
        final now = DateTime.now();
        final a = WeekdayComparison.summarize(sessions, weekdays: _groupA, now: now, range: _range);
        final b = WeekdayComparison.summarize(sessions, weekdays: groupB, now: now, range: _range);
        return ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Сравнение групп дней', style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 12),
          DropdownButtonFormField<ComparisonRange>(
            initialValue: _range,
            decoration: const InputDecoration(labelText: 'Период анализа'),
            items: const [
              DropdownMenuItem(value: ComparisonRange.days30, child: Text('Последние 30 дней')),
              DropdownMenuItem(value: ComparisonRange.days90, child: Text('Последние 90 дней')),
              DropdownMenuItem(value: ComparisonRange.year, child: Text('Последний год')),
              DropdownMenuItem(value: ComparisonRange.all, child: Text('Вся история')),
            ],
            onChanged: (value) { if (value != null) setState(()=>_range=value); },
          ),
          const SizedBox(height: 18),
          SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Группа А — выберите дни', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 4, children: List.generate(7, (i) {
              final day = i+1;
              return FilterChip(
                label: Text(WeekdayComparison.weekdayLabels[i]),
                selected: _groupA.contains(day),
                onSelected: (value)=>setState(()=>value ? _groupA.add(day) : _groupA.remove(day)),
              );
            })),
            const SizedBox(height: 8),
            Text('Группа Б автоматически включает остальные дни: ${groupB.map((d)=>WeekdayComparison.weekdayLabels[d-1]).join(', ')}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ])),
          const SizedBox(height: 12),
          if (_groupA.isEmpty || groupB.isEmpty)
            const SectionCard(child: Text('Для сравнения выберите хотя бы один день в обеих группах.'))
          else ...[
            _groupCard('Группа А', _groupA, a),
            const SizedBox(height: 10),
            _groupCard('Группа Б', groupB, b),
            const SizedBox(height: 12),
            SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Сопоставление', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _delta('Средняя длительность', a.averageDurationMinutes, b.averageDurationMinutes, suffix: ' мин'),
              _delta('Медианная длительность', a.medianDurationMinutes, b.medianDurationMinutes, suffix: ' мин'),
              _delta('Оценка самочувствия', a.averageRating, b.averageRating, suffix: ' балла'),
              const SizedBox(height: 8),
              const Text('Ночь относится к группе по дню начала сессии. В расчёт длительности входят только завершённые записи; оценки учитываются только при наличии ответа. Различия описывают личную историю и не доказывают причинно-следственную связь.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
            ])),
          ],
          const SizedBox(height: 10),
          Text('Всего загружено записей: ${sessions.length}. Незавершённые ночи не включаются в расчёт длительности.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]);
      },
    ),
  );

  Widget _groupCard(String title, Set<int> days, WeekdayGroupSummary summary) => SectionCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(days.map((d)=>WeekdayComparison.weekdayLabels[d-1]).join(', '), style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      const SizedBox(height: 12),
      _value('Ночей', '${summary.sessions.length}'),
      _value('Завершено', '${summary.completed}'),
      _value('Средняя длительность', WeekdayComparison.formatDuration(summary.averageDurationMinutes)),
      _value('Медианная длительность', WeekdayComparison.formatDuration(summary.medianDurationMinutes)),
      _value('Среднее засыпание', WeekdayComparison.formatMinutes(summary.averageBedtimeMinutes)),
      _value('Среднее пробуждение', WeekdayComparison.formatMinutes(summary.averageWakeTimeMinutes)),
      _value('Средняя оценка', summary.averageRating == null ? 'Нет оценок' : '${summary.averageRating!.toStringAsFixed(1)} / 5'),
      _value('Ночей с оценкой', '${summary.rated}'),
    ]),
  );

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
  );

  Widget _delta(String label, double? a, double? b, {String suffix = ''}) {
    final value = a == null || b == null ? null : a-b;
    return _value(label, value == null ? 'Нет сопоставимых данных' : '${value>=0?'+':''}${value.toStringAsFixed(1)}$suffix (А − Б)');
  }
}
