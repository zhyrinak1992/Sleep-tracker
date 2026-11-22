import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_session_metrics.dart';

class SleepSessionMetricsCard extends StatelessWidget {
  const SleepSessionMetricsCard({
    super.key,
    required this.session,
    required this.stagesFuture,
  });

  final SleepSession session;
  final Future<List<Map<String, Object?>>> stagesFuture;

  String _duration(int? minutes) {
    if (minutes == null) return 'Нет данных';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
  }

  String _time(DateTime? value) =>
      value == null ? 'Нет данных' : DateFormat('HH:mm').format(value);

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
    ]),
  );

  Widget _phaseRow(BuildContext context, String label, int minutes, int total, Color color) {
    if (minutes <= 0 || total <= 0) return const SizedBox.shrink();
    final percent = minutes / total * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text('${_duration(minutes)} · ${percent.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 7,
            color: color,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: stagesFuture,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: LinearProgressIndicator());
      }
      if (state.hasError) {
        return SectionCard(child: Text('Не удалось рассчитать показатели сна: ${state.error}'));
      }
      final metrics = SleepSessionMetrics.calculate(
        session: session,
        stages: state.data ?? const [],
      );
      final totalRecorded = metrics.stageMinutes.values.fold<int>(0, (a, b) => a + b);
      final colors = Theme.of(context).colorScheme;
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Время в постели и фактический сон',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _row('Время в постели', _duration(metrics.timeInBedMinutes)),
          _row(
            metrics.durationFromStages ? 'Сон по данным фаз' : 'Фактический интервал сна',
            _duration(metrics.sleepDurationMinutes),
          ),
          _row('Время засыпания', _duration(metrics.sleepLatencyMinutes)),
          _row('Первое зарегистрированное пробуждение', _time(metrics.firstAwakeningAt)),
          _row('Количество ночных пробуждений', metrics.awakeningCount.toString()),
          _row('Время бодрствования по фазам', _duration(metrics.awakeStageMinutes)),
          _row('Окончательное пробуждение', _time(metrics.finalWakeAt)),
          if (metrics.awakeningIntervals.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Зарегистрированные пробуждения',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            for (var i = 0; i < metrics.awakeningIntervals.length; i++)
              _row(
                'Пробуждение ${i + 1} · ${_time(metrics.awakeningIntervals[i].startedAt)}',
                _duration(metrics.awakeningIntervals[i].durationMinutes),
              ),
          ],
          const Divider(height: 18, color: AppTheme.surfaceLight),
          const Text('Распределение фаз сна',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (totalRecorded == 0)
            const Text('Нет данных о фазах сна для построения распределения.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11))
          else ...[
            _phaseRow(context, 'Глубокий сон', metrics.stageMinutes['deep'] ?? 0, totalRecorded, colors.primary),
            _phaseRow(context, 'REM-сон', metrics.stageMinutes['rem'] ?? 0, totalRecorded, colors.tertiary),
            _phaseRow(context, 'Лёгкий сон', metrics.stageMinutes['light'] ?? 0, totalRecorded, colors.secondary),
            _phaseRow(context, 'Сон без уточнения фазы', metrics.stageMinutes['unspecified'] ?? 0, totalRecorded, colors.outline),
            _phaseRow(context, 'Бодрствование', metrics.stageMinutes['awake'] ?? 0, totalRecorded, colors.error),
            Text(
              'Доли рассчитаны от всего времени с зарегистрированными фазами; перекрывающиеся записи не учитываются повторно.',
              style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4),
            ),
          ],
          const Divider(height: 18, color: AppTheme.surfaceLight),
          if (metrics.sleepEfficiencyPercent != null) ...[
            _row('Эффективность сна',
              '${metrics.sleepEfficiencyPercent!.toStringAsFixed(1)}%'),
            _row('Покрытие фаз сна',
              '${metrics.stageCoveragePercent!.toStringAsFixed(0)}%'),
          ] else
            const Text(
              'Эффективность не рассчитана: нужны зарегистрированные интервалы сна и бодрствования с покрытием не менее 80% времени в постели. Отсутствующие периоды не считаются сном.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
          const SizedBox(height: 6),
          Text(
            metrics.durationFromStages
              ? 'Длительность сна рассчитана по неперекрывающимся интервалам фаз.'
              : 'Фазы сна отсутствуют или неполны; показан только сохранённый интервал между фактическим засыпанием и пробуждением.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4),
          ),
        ],
      ));
    },
  );
}
