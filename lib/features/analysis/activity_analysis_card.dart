import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class _ActivityNight {
  const _ActivityNight({
    required this.sessionId,
    required this.sleepMinutes,
    this.steps,
    this.energyKcal,
    this.exerciseMinutes,
    this.workoutCount,
  });

  final String sessionId;
  final double sleepMinutes;
  final double? steps;
  final double? energyKcal;
  final double? exerciseMinutes;
  final double? workoutCount;
}

class ActivityAnalysisCard extends StatelessWidget {
  const ActivityAnalysisCard({
    super.key,
    required this.database,
    required this.sessions,
  });

  final SleepDatabase database;
  final List<SleepSession> sessions;

  Future<List<_ActivityNight>> _load() async {
    final metadata = await database.getAppMetadataByPrefix('sleep_tracker_activity_v1_');
    final result = <_ActivityNight>[];
    for (final session in sessions) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      if (end == null || !end.isAfter(start)) continue;
      final raw = metadata['sleep_tracker_activity_v1_${session.id}'];
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map || decoded['sessionId'] != session.id) continue;
        double? number(String key) {
          final value = decoded[key];
          if (value is! num) return null;
          final parsed = value.toDouble();
          return parsed.isFinite ? parsed : null;
        }
        result.add(_ActivityNight(
          sessionId: session.id,
          sleepMinutes: end.difference(start).inMinutes.toDouble(),
          steps: number('steps'),
          energyKcal: number('activeEnergyKcal'),
          exerciseMinutes: number('exerciseMinutes'),
          workoutCount: number('workoutCount'),
        ));
      } catch (_) {
        // Ignore malformed optional activity metadata without affecting sleep history.
      }
    }
    return result;
  }

  String _average(List<double> values, {required String unit, int decimals = 0}) {
    if (values.isEmpty) return 'Нет данных';
    final average = values.reduce((a, b) => a + b) / values.length;
    return '${average.toStringAsFixed(decimals)} $unit · ${values.length} ноч.';
  }

  String _duration(double minutes) {
    final rounded = minutes.round();
    return '${rounded ~/ 60} ч ${rounded % 60} мин';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_ActivityNight>>(
    future: _load(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: LinearProgressIndicator());
      }
      if (snapshot.hasError) {
        return SectionCard(child: Text('Не удалось загрузить активность: ${snapshot.error}'));
      }
      final nights = snapshot.data ?? const <_ActivityNight>[];
      final stepNights = nights.where((night) => night.steps != null).toList()
        ..sort((a, b) => a.steps!.compareTo(b.steps!));
      final lower = <_ActivityNight>[];
      final upper = <_ActivityNight>[];
      if (stepNights.length >= 4) {
        final midpoint = stepNights.length ~/ 2;
        lower.addAll(stepNights.take(midpoint));
        upper.addAll(stepNights.skip(midpoint));
      }
      final lowerSleep = lower.map((night) => night.sleepMinutes).toList();
      final upperSleep = upper.map((night) => night.sleepMinutes).toList();
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Физическая активность перед сном',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Используются только разрешённые фактические данные Apple Health за предшествующий период бодрствования (не более 24 часов).',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text('Ночей с доступными данными: ${nights.length} из ${sessions.length}',
            style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600)),
          const Divider(height: 20, color: AppTheme.surfaceLight),
          _ActivityMetricRow(
            label: 'Шаги',
            value: _average(nights.where((n) => n.steps != null).map((n) => n.steps!).toList(), unit: 'шагов'),
          ),
          const SizedBox(height: 8),
          _ActivityMetricRow(
            label: 'Активная энергия',
            value: _average(nights.where((n) => n.energyKcal != null).map((n) => n.energyKcal!).toList(), unit: 'ккал', decimals: 1),
          ),
          const SizedBox(height: 8),
          _ActivityMetricRow(
            label: 'Минуты упражнений',
            value: _average(nights.where((n) => n.exerciseMinutes != null).map((n) => n.exerciseMinutes!).toList(), unit: 'мин', decimals: 1),
          ),
          const SizedBox(height: 8),
          _ActivityMetricRow(
            label: 'Тренировки',
            value: _average(nights.where((n) => n.workoutCount != null).map((n) => n.workoutCount!).toList(), unit: 'за период'),
          ),
          const Divider(height: 20, color: AppTheme.surfaceLight),
          const Text('Шаги и продолжительность последующего сна',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 8),
          if (stepNights.length < 4)
            const Text('Для сопоставления групп нужны минимум 4 ночи, в которых одновременно доступны шаги и длительность сна.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4))
          else ...[
            _ActivityMetricRow(
              label: 'Ниже медианы шагов (${lower.length} ноч.)',
              value: _duration(lowerSleep.reduce((a, b) => a + b) / lowerSleep.length),
            ),
            const SizedBox(height: 6),
            _ActivityMetricRow(
              label: 'Не ниже медианы (${upper.length} ноч.)',
              value: _duration(upperSleep.reduce((a, b) => a + b) / upperSleep.length),
            ),
            const SizedBox(height: 8),
            const Text(
              'Группы делятся по медиане шагов внутри выбранного периода. Сравнение описывает наблюдаемую связь и не доказывает причинное влияние активности на сон. Пустые значения не считаются нулём.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ));
    },
  );
}

class _ActivityMetricRow extends StatelessWidget {
  const _ActivityMetricRow({required this.label, required this.value, this.decimals = 0});
  final String label;
  final String value;
  final int decimals;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Text(value, textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );
}
