import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../diary/sleep_session_detail_screen.dart';
import 'individual_sleep_need.dart';

class IndividualSleepNeedCard extends StatefulWidget {
  const IndividualSleepNeedCard({super.key, required this.database});

  final SleepDatabase database;

  @override
  State<IndividualSleepNeedCard> createState() => _IndividualSleepNeedCardState();
}

class _IndividualSleepNeedCardState extends State<IndividualSleepNeedCard> {
  late Future<IndividualSleepNeedResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<IndividualSleepNeedResult> _load() async {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 90));
    final all = await widget.database.getSessions(limit: null);
    final sessions = all.where((session) =>
      !session.startedAt.isBefore(cutoff) && !session.startedAt.isAfter(now)
    ).toList();
    final ids = sessions.map((session) => session.id).toList();
    final reportsFuture = widget.database.getMorningReportsForSessions(ids);
    final stagesFuture = widget.database.getStagesForSessions(ids);
    final reports = await reportsFuture;
    final stages = await stagesFuture;
    return IndividualSleepNeedAnalysis.evaluate(
      sessions: sessions,
      morningReports: reports,
      stagesBySession: stages,
      calculatedAt: now,
    );
  }

  String _duration(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
  }

  String _date(DateTime? value) =>
      value == null ? '—' : DateFormat('d MMM yyyy', 'ru').format(value);

  String _confidence(SleepNeedConfidence? value) => switch (value) {
    SleepNeedConfidence.low => 'Низкая',
    SleepNeedConfidence.moderate => 'Средняя',
    SleepNeedConfidence.high => 'Повышенная',
    null => 'Недостаточно данных',
  };

  Widget _distribution(IndividualSleepNeedResult result) {
    if (result.distribution.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Распределение фактической длительности',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      children: result.distribution.map((bin) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 54, child: Text(bin.label,
            style: const TextStyle(fontSize: 11, color: AppTheme.muted))),
          Expanded(child: LinearProgressIndicator(
            value: bin.fraction,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: AppTheme.surfaceLight,
          )),
          const SizedBox(width: 8),
          SizedBox(width: 24, child: Text('${bin.count}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      )).toList(),
    );
  }

  Widget _basisNights(IndividualSleepNeedResult result) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text('Ночи, на которых основан диапазон (${result.basisNights.length})',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    children: result.basisNights.map((night) {
      final date = DateFormat('d MMM', 'ru').format(night.session.startedAt);
      final rating = [
        if (night.wellbeing != null) 'самочувствие ${night.wellbeing}/5',
        if (night.sleepQuality != null) 'качество ${night.sleepQuality}/5',
      ].join(' · ');
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('$date · ${_duration(night.durationMinutes)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        subtitle: Text(rating.isEmpty ? 'Без утренней оценки' : rating,
          style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SleepSessionDetailScreen(
            database: widget.database,
            session: night.session,
          ),
        )),
      );
    }).toList(),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<IndividualSleepNeedResult>(
    future: _future,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Моя индивидуальная продолжительность сна',
              style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            LinearProgressIndicator(),
          ],
        ));
      }
      if (state.hasError) {
        return SectionCard(child: Text(
          'Не удалось рассчитать индивидуальный диапазон сна: ${state.error}',
          style: const TextStyle(color: AppTheme.muted),
        ));
      }
      final result = state.data!;
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Моя индивидуальная продолжительность сна',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Ориентировочная оценка по последним 90 дням. Она не является медицинской нормой и не меняет расписание или будильники.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (!result.isSufficient) ...[
            Text(result.reason ?? 'Пока недостаточно сопоставимых данных.',
              style: const TextStyle(fontSize: 12, height: 1.45)),
            const SizedBox(height: 8),
            Text('Завершённых ночей: ${result.validNightCount} из 21 минимально необходимых · с утренней оценкой: ${result.ratedNightCount} из 14',
              style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            _distribution(result),
          ] else ...[
            Text(
              '${_duration(result.lowerMinutes!)} – ${_duration(result.upperMinutes!)}',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: AppTheme.teal),
            ),
            const SizedBox(height: 4),
            Text('Ориентировочный личный диапазон · уверенность: ${_confidence(result.confidence)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            const SizedBox(height: 8),
            Text('Период: ${_date(result.periodStart)} — ${_date(result.periodEnd)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            Text('Учтено ночей: ${result.validNightCount}; утренние оценки: ${result.ratedNightCount}; благоприятные и относительно регулярные ночи в расчёте: ${result.basisNightCount}.',
              style: const TextStyle(fontSize: 11, color: AppTheme.muted, height: 1.4)),
            const Divider(height: 20, color: AppTheme.surfaceLight),
            Text('Сравнение с личным диапазоном: ниже — ${result.belowRangeCount}, внутри — ${result.withinRangeCount}, выше — ${result.aboveRangeCount}.',
              style: const TextStyle(fontSize: 12, height: 1.4)),
            if (result.averageBedtimeDeviationMinutes != null)
              Text('Среднее отклонение времени засыпания: ±${result.averageBedtimeDeviationMinutes!.round()} мин.',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            if (result.averageWakeTimeDeviationMinutes != null)
              Text('Среднее отклонение времени пробуждения: ±${result.averageWakeTimeDeviationMinutes!.round()} мин.',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            if (result.averageSleepEfficiencyPercent != null)
              Text('Средняя эффективность сна по полным данным фаз: ${result.averageSleepEfficiencyPercent!.toStringAsFixed(0)}% (${result.efficiencySampleCount} ноч.).',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            if (result.averageSleepEfficiencyPercent == null)
              const Text('Эффективность сна не включена: нет достаточного покрытия фаз с отдельными периодами бодрствования.',
                style: TextStyle(fontSize: 11, color: AppTheme.muted)),
            _distribution(result),
            _basisNights(result),
            const SizedBox(height: 6),
            Text('Расчёт обновлён: ${DateFormat('d MMM yyyy, HH:mm', 'ru').format(result.calculatedAt)}. Диапазон формируется по распределению ночей с относительно благоприятными утренними оценками и устойчивым временем сна. При малой выборке он скрывается. Это статистическое наблюдение, а не медицинская рекомендация.',
              style: const TextStyle(fontSize: 10, color: AppTheme.muted, height: 1.4)),
          ],
        ],
      ));
    },
  );
}
