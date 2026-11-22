import 'dart:convert';

import 'package:health/health.dart';

import 'sleep_database.dart';

class AppleHealthActivitySyncResult {
  const AppleHealthActivitySyncResult({required this.daysUpdated, required this.samplesRead});
  final int daysUpdated;
  final int samplesRead;
}

/// Read-only daily activity import. Missing HealthKit data is left absent;
/// an empty query never overwrites previously imported days.
class AppleHealthActivityService {
  AppleHealthActivityService._();
  static final AppleHealthActivityService instance = AppleHealthActivityService._();

  static const storageKey = 'apple_health_daily_activity_v1';
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
  ];

  final Health _health = Health();
  bool _configured = false;

  Future<AppleHealthActivitySyncResult> syncRecentActivity({
    int days = 30,
    SleepDatabase? database,
  }) async {
    final db = database ?? SleepDatabase.instance;
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    final authorized = await _health.requestAuthorization(
      _types,
      permissions: List.filled(_types.length, HealthDataAccess.READ),
    );
    if (!authorized) {
      throw StateError('HealthKit не подтвердил запрос чтения активности. Проверь разрешения приложения в «Здоровье».');
    }

    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    final raw = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: start,
      endTime: end,
    );
    final points = _health.removeDuplicates(raw);
    if (points.isEmpty) {
      return const AppleHealthActivitySyncResult(daysUpdated: 0, samplesRead: 0);
    }

    final byDay = <String, _DailyAccumulator>{};
    for (final point in points) {
      if (point.value is! NumericHealthValue) continue;
      final date = point.dateFrom.toLocal();
      final key = _dateKey(date);
      final accumulator = byDay.putIfAbsent(key, () => _DailyAccumulator());
      final value = (point.value as NumericHealthValue).numericValue.toDouble();
      switch (point.type) {
        case HealthDataType.STEPS:
          accumulator.steps += value;
          accumulator.hasSteps = true;
          break;
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          accumulator.activeEnergyKcal += value;
          accumulator.hasActiveEnergy = true;
          break;
        case HealthDataType.EXERCISE_TIME:
          accumulator.exerciseMinutes += value;
          accumulator.hasExerciseTime = true;
          break;
        default:
          break;
      }
      if (point.sourceName.isNotEmpty) accumulator.sources.add(point.sourceName);
    }

    final existingRaw = await db.getAppMetadata(storageKey);
    final Map<String, dynamic> stored;
    if (existingRaw == null || existingRaw.isEmpty) {
      stored = {};
    } else {
      final decoded = jsonDecode(existingRaw);
      if (decoded is! Map) {
        throw const FormatException('Архив активности повреждён. Сохранённые данные не перезаписаны.');
      }
      stored = Map<String, dynamic>.from(decoded);
    }

    final updatedAt = DateTime.now().toUtc().toIso8601String();
    for (final entry in byDay.entries) {
      final value = entry.value;
      final previous = stored[entry.key] is Map
          ? Map<String, dynamic>.from(stored[entry.key] as Map)
          : <String, dynamic>{};
      stored[entry.key] = {
        if (value.hasSteps) 'steps': value.steps,
        if (value.hasActiveEnergy) 'activeEnergyKcal': value.activeEnergyKcal,
        if (value.hasExerciseTime) 'exerciseMinutes': value.exerciseMinutes,
        'sources': value.sources.toList()..sort(),
        'updatedAt': updatedAt,
        // Preserve previously known values when this query returned only a
        // subset of the permitted HealthKit data types for the day.
        if (!value.hasSteps && previous.containsKey('steps')) 'steps': previous['steps'],
        if (!value.hasActiveEnergy && previous.containsKey('activeEnergyKcal')) 'activeEnergyKcal': previous['activeEnergyKcal'],
        if (!value.hasExerciseTime && previous.containsKey('exerciseMinutes')) 'exerciseMinutes': previous['exerciseMinutes'],
      };
    }

    await db.setAppMetadata(storageKey, jsonEncode(stored));
    return AppleHealthActivitySyncResult(daysUpdated: byDay.length, samplesRead: points.length);
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _DailyAccumulator {
  double steps = 0;
  double activeEnergyKcal = 0;
  double exerciseMinutes = 0;
  bool hasSteps = false;
  bool hasActiveEnergy = false;
  bool hasExerciseTime = false;
  final Set<String> sources = {};
}
