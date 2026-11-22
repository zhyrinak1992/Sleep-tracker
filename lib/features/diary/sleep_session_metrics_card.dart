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
          _row('Окончательное пробуждение', _time(metrics.finalWakeAt)),
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
              ? 'Длительность сна рассчитана объединением интервалов фаз без двойного учёта перекрытий.'
              : 'Фазы сна отсутствуют или неполны; показан только сохранённый интервал между фактическим засыпанием и пробуждением.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4),
          ),
        ],
      ));
    },
  );
}
