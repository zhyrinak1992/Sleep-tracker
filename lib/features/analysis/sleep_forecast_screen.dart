import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'sleep_forecast_analysis.dart';

class SleepForecastScreen extends StatefulWidget {
  const SleepForecastScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<SleepForecastScreen> createState() => _SleepForecastScreenState();
}

class _SleepForecastScreenState extends State<SleepForecastScreen> {
  late Future<List<SleepSession>> _future;
  TimeOfDay _wake = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _bedtime = const TimeOfDay(hour: 23, minute: 0);
  int _targetMinutes = 480;

  @override
  void initState() {
    super.initState();
    _future = widget.database.getSessions(limit: 365);
  }

  int _minute(TimeOfDay value) => value.hour * 60 + value.minute;

  String _clock(int minute) {
    final normalized = minute % 1440;
    return '${(normalized ~/ 60).toString().padLeft(2, '0')}:${(normalized % 60).toString().padLeft(2, '0')}';
  }

  String _duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h ч' : '$h ч $m мин';
  }

  Future<void> _chooseTime({required bool wake}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: wake ? _wake : _bedtime,
      helpText: wake ? 'Планируемое пробуждение' : 'Предполагаемое укладывание',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (wake) {
        _wake = selected;
      } else {
        _bedtime = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _future,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (state.hasError) {
        return Scaffold(body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Не удалось загрузить историю сна: ${state.error}'),
        )));
      }
      final result = SleepForecastAnalysis.calculate(
        sessions: state.data ?? const [],
        now: DateTime.now(),
        plannedWakeMinute: _minute(_wake),
        plannedBedtimeMinute: _minute(_bedtime),
        targetSleepMinutes: _targetMinutes,
      );
      return Scaffold(
        appBar: AppBar(title: const Text('Персональный прогноз сна')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const ScreenHeader(
              title: 'Планирование сна',
              subtitle: 'Ориентир по выбранному времени и личной истории',
              icon: Icons.schedule_rounded,
            ),
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ваш план', style: TextStyle(fontWeight: FontWeight.w700)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Планируемое пробуждение'),
                  trailing: TextButton(
                    onPressed: () => _chooseTime(wake: true),
                    child: Text(_wake.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Предполагаемое укладывание'),
                  trailing: TextButton(
                    onPressed: () => _chooseTime(wake: false),
                    child: Text(_bedtime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Целевая продолжительность сна: ${_duration(_targetMinutes)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  min: 360, max: 600, divisions: 16,
                  value: _targetMinutes.toDouble(),
                  label: _duration(_targetMinutes),
                  onChanged: (value) => setState(() => _targetMinutes = value.round()),
                ),
                const Text('Это выбранная вами цель для расчёта, а не медицинская норма.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11)),
              ],
            )),
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Расчёт по вашему плану', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Между укладыванием ${_bedtime.format(context)} и пробуждением ${_wake.format(context)}: ${_duration(result.availableWindowMinutes)}.',
                  style: const TextStyle(fontSize: 13, height: 1.45)),
                const SizedBox(height: 10),
                if (result.personalLatencyAvailable) ...[
                  Text('Личный диапазон времени укладывания: ${_clock(result.recommendedBedtimeStartMinute!)}–${_clock(result.recommendedBedtimeEndMinute!)}',
                    style: const TextStyle(color: AppTheme.teal, fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('По выбранной цели и медианной задержке засыпания ${result.medianLatencyMinutes} мин. Учтено наблюдений с обеими временными отметками: ${result.latencySamples}.',
                    style: const TextStyle(fontSize: 12, height: 1.45)),
                  Text('При текущем плане ориентировочная продолжительность сна после вычета личной задержки засыпания: ${_duration(result.estimatedSleepMinutes!)}.',
                    style: const TextStyle(fontSize: 12, height: 1.45)),
                ] else ...[
                  const Text('Персональный прогноз пока недоступен: недостаточно ночей с достоверными отметками начала наблюдения и фактического засыпания.',
                    style: TextStyle(fontSize: 12, height: 1.45)),
                  const Text('Пока показан только нейтральный расчёт времени между выбранными часами — без предположения о том, сколько времени потребуется на засыпание.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45)),
                ],
                const Divider(height: 20, color: AppTheme.surfaceLight),
                const Text('Недавний дефицит относительно выбранной цели',
                  style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (result.accumulatedShortfallMinutes == null)
                  Text('Для оценки нужны как минимум 5 ночей с фактическими временными границами за последние 7 календарных дней. Сейчас таких ночей: ${result.recentSleepSamples}.',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45))
                else if (result.accumulatedShortfallMinutes == 0)
                  const Text('По доступным ночам дефицит относительно выбранной цели не рассчитан.',
                    style: TextStyle(fontSize: 12))
                else
                  Text('Расчётная разница: ${_duration(result.accumulatedShortfallMinutes!)} за ${result.recentSleepSamples} ночей. В условном сценарии с дополнительными 30 минутами сна за ночь это заняло бы около ${result.recoveryNightsAtThirtyMinutes} ночей. Это арифметический сценарий, а не рекомендация резко увеличивать сон.',
                    style: const TextStyle(fontSize: 12, height: 1.45)),
              ],
            )),
            const SizedBox(height: 12),
            const Text('Прогноз ориентировочный и не гарантирует фактическое засыпание или пробуждение. Он не является медицинской рекомендацией, не ставит диагнозов и не меняет будильники, уведомления или расписание.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.5)),
          ],
        ),
      );
    },
  );
}
