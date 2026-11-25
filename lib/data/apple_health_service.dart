import 'dart:convert';

import 'package:health/health.dart';

import 'sleep_database.dart';


/// Merges a fresh HealthKit result into the existing night record.
/// Values absent from the latest query remain intact; current values win.
String mergeNightActivityMetadata({
  required String? previousRaw,
  required Map<String, Object?> current,
}) {
  final merged = <String, Object?>{};
  if (previousRaw != null && previousRaw.isNotEmpty) {
    final decoded = jsonDecode(previousRaw);
    if (decoded is! Map) {
      throw const FormatException('Архив активности повреждён.');
    }
    if (decoded['sessionId'] == current['sessionId']) {
      merged.addAll(Map<String, Object?>.from(decoded));
    }
  }
  merged.addAll(current);
  return jsonEncode(merged);
}

class AppleHealthSyncResult {
  const AppleHealthSyncResult({required this.imported, required this.found});
  final int imported;
  final int found;
}

/// Read-only import of sleep intervals supplied by Apple Health / Apple Watch.
/// No synthetic phases or sleep metrics are generated when HealthKit has none.
class AppleHealthService {
  AppleHealthService._();
  static final AppleHealthService instance = AppleHealthService._();

  final Health _health = Health();
  bool _configured = false;

  static const List<HealthDataType> _sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
  ];

  static const List<HealthDataType> _metricTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.WRIST_TEMPERATURE,
  ];

  static const List<HealthDataType> _activityTypes = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
    HealthDataType.WORKOUT,
  ];

  Future<AppleHealthSyncResult> syncRecentSleep({int days = 30}) async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    // Capture the HealthKit request state before asking. On iOS a true
    // requestAuthorization result means the request was handled, not that
    // read access was granted; HealthKit intentionally hides read grants.
    final availability = _sleepTypes
        .map((type) => '${type.name}=${_health.isDataTypeAvailable(type)}')
        .join(', ');
    String requestStatus;
    try {
      final status = await _health.getRequestStatusForAuthorization(
        _sleepTypes,
        permissions: List.filled(_sleepTypes.length, HealthDataAccess.READ),
      );
      requestStatus = status?.toString() ?? 'null (platform did not return a status)';
    } catch (error) {
      throw StateError(
        'Диагностика HealthKit: не удалось определить статус запроса. '
        'Доступность типов: $availability. Ошибка: $error',
      );
    }

    bool sleepAuthorized;
    try {
      sleepAuthorized = await _health.requestAuthorization(
        _sleepTypes,
        permissions: List.filled(_sleepTypes.length, HealthDataAccess.READ),
      );
    } catch (error) {
      throw StateError(
        'Диагностика HealthKit: статус запроса — $requestStatus. '
        'Доступность типов: $availability. Ошибка запроса: $error',
      );
    }
    if (!sleepAuthorized) {
      throw StateError(
        'Диагностика HealthKit: requestAuthorization вернул false. '
        'Статус до запроса: $requestStatus. '
        'Доступность типов: $availability. '
        'Это не позволяет определить, отказал ли пользователь в чтении данных.',
      );
    }

    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));

    // Keep optional physiological metrics separate: a problem with one
    // metric type must not block importing sleep intervals.
    final sleepData = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: start,
      endTime: end,
    );
    var metricData = <HealthDataPoint>[];
    try {
      final metricsAuthorized = await _health.requestAuthorization(
        _metricTypes,
        permissions: List.filled(_metricTypes.length, HealthDataAccess.READ),
      );
      if (metricsAuthorized) {
        metricData = await _health.getHealthDataFromTypes(
          types: _metricTypes,
          startTime: start,
          endTime: end,
        );
      }
    } catch (_) {
      // Sleep remains useful on its own; optional metrics can be retried later.
    }

    final unique = _health.removeDuplicates([...sleepData, ...metricData]);
    final sleepPoints = unique.where((point) => _stageName(point.type) != null && point.dateTo.isAfter(point.dateFrom)).toList();
    final metricPoints = unique.where((point) => _metricName(point.type) != null).toList();
    if (sleepPoints.isEmpty && metricPoints.isEmpty) return const AppleHealthSyncResult(imported: 0, found: 0);

    // Only sleep-stage samples define nights; daytime heart-rate samples must
    // never create artificial sleep sessions.
    sleepPoints.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final groups = <List<HealthDataPoint>>[];
    for (final point in sleepPoints) {
      if (groups.isEmpty) {
        groups.add([point]);
        continue;
      }
      final current = groups.last;
      final latestEnd = current
          .map((item) => item.dateTo)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (point.dateFrom.difference(latestEnd) <= const Duration(minutes: 90)) {
        current.add(point);
      } else {
        groups.add([point]);
      }
    }

    var imported = 0;
    final sessionIdsByGroup = <String, String>{};
    for (final group in groups) {
      final sorted = [...group]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      final first = sorted.first;
      final startedAt = sorted
          .map((item) => item.dateFrom)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final endedAt = sorted
          .map((item) => item.dateTo)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final safeId = 'health_${first.uuid.replaceAll('-', '_')}';
      final sourceName = sorted.map((item) => item.sourceName).where((s) => s.isNotEmpty).toSet().join(', ');
      final resolved = await SleepDatabase.instance.upsertHealthSession(
        id: safeId,
        startedAt: startedAt,
        endedAt: endedAt,
        sourceName: sourceName.isEmpty ? 'Apple Health' : sourceName,
      );
      final sessionId = resolved.$1;
      if (sessionId == null) continue;
      sessionIdsByGroup[first.uuid] = sessionId;
      if (resolved.$2) imported++;

      // Deterministic sample IDs make this safe to run repeatedly. Existing
      // samples are ignored; newly available stages are added to the same night.
      for (final point in sorted) {
        final stage = _stageName(point.type);
        if (stage == null) continue;
        await SleepDatabase.instance.addSleepStage(
          id: 'health_stage_${point.uuid.replaceAll('-', '_')}',
          sessionId: sessionId, stage: stage, startedAt: point.dateFrom,
          endedAt: point.dateTo, source: 'Apple Health: ${point.sourceName}',
        );
      }
    }
    for (final point in metricPoints) {
      if (point.value is! NumericHealthValue) continue;
      final metric = _metricName(point.type);
      if (metric == null) continue;
      for (final group in groups) {
        final from = group.map((x) => x.dateFrom).reduce((a,b) => a.isBefore(b) ? a : b);
        final to = group.map((x) => x.dateTo).reduce((a,b) => a.isAfter(b) ? a : b);
        if (!point.dateTo.isBefore(from.subtract(const Duration(hours: 1))) && !point.dateTo.isAfter(to.add(const Duration(hours: 1)))) {
          final first = group.first;
          final sessionId = sessionIdsByGroup[first.uuid];
          if (sessionId == null) continue;
          await SleepDatabase.instance.addSleepMetric(id: 'health_metric_${point.uuid.replaceAll('-', '_')}', sessionId: sessionId, type: metric.$1, value: (point.value as NumericHealthValue).numericValue.toDouble(), unit: metric.$2, measuredAt: point.dateTo, source: 'Apple Health: ${point.sourceName}');
          break;
        }
      }
    }
    // Optional pre-sleep activity is stored separately from sleep physiology.
    // The interval is the preceding waking period, capped at 24 hours and
    // shortened to the end of the previous imported night when available.
    var activityAuthorized = false;
    try {
      activityAuthorized = await _health.requestAuthorization(
        _activityTypes,
        permissions: List.filled(_activityTypes.length, HealthDataAccess.READ),
      );
    } catch (_) {
      // Activity permissions are optional and must never block sleep import.
    }
    if (activityAuthorized) {
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index];
        final nightStart = group
            .map((point) => point.dateFrom)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        var wakingStart = nightStart.subtract(const Duration(hours: 24));
        if (index > 0) {
          final previousEnd = groups[index - 1]
              .map((point) => point.dateTo)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          if (previousEnd.isAfter(wakingStart) && previousEnd.isBefore(nightStart)) {
            wakingStart = previousEnd;
          }
        }
        final intervalSeconds = nightStart.difference(wakingStart).inSeconds;
        if (intervalSeconds <= 0) continue;
        final first = group.first;
        final sessionId = sessionIdsByGroup[first.uuid];
        if (sessionId == null) continue;

        final activity = <String, Object?>{
          'schemaVersion': 1,
          'sessionId': sessionId,
          'windowStart': wakingStart.toUtc().toIso8601String(),
          'windowEnd': nightStart.toUtc().toIso8601String(),
          'syncedAt': DateTime.now().toUtc().toIso8601String(),
        };
        try {
          final aggregates = await _health.getHealthIntervalDataFromTypes(
            types: const [
              HealthDataType.STEPS,
              HealthDataType.ACTIVE_ENERGY_BURNED,
              HealthDataType.EXERCISE_TIME,
            ],
            startDate: wakingStart,
            endDate: nightStart,
            interval: intervalSeconds,
          );
          for (final point in aggregates) {
            if (point.value is! NumericHealthValue) continue;
            final value = (point.value as NumericHealthValue).numericValue.toDouble();
            if (!value.isFinite) continue;
            switch (point.type) {
              case HealthDataType.STEPS:
                activity['steps'] = value.round();
                break;
              case HealthDataType.ACTIVE_ENERGY_BURNED:
                activity['activeEnergyKcal'] = value;
                break;
              case HealthDataType.EXERCISE_TIME:
                activity['exerciseMinutes'] = value;
                break;
              default:
                break;
            }
          }
        } catch (_) {
          // One unavailable aggregate does not invalidate the other activity types.
        }
        try {
          final workouts = await _health.getHealthDataFromTypes(
            types: const [HealthDataType.WORKOUT],
            startTime: wakingStart,
            endTime: nightStart,
          );
          final uniqueWorkouts = _health.removeDuplicates(workouts);
          if (uniqueWorkouts.isNotEmpty) {
            activity['workoutCount'] = uniqueWorkouts.length;
            activity['workoutDurationMinutes'] = uniqueWorkouts.fold<int>(
              0,
              (sum, point) => sum + point.dateTo.difference(point.dateFrom).inMinutes,
            );
            activity['workouts'] = uniqueWorkouts.map((point) => <String, Object?>{
              'type': point.workoutSummary?.workoutType.toString() ?? 'Тренировка',
              'startedAt': point.dateFrom.toUtc().toIso8601String(),
              'endedAt': point.dateTo.toUtc().toIso8601String(),
              'source': point.sourceName,
            }).toList();
          }
        } catch (_) {
          // Workout detail is optional; keep any successfully read aggregates.
        }
        if (activity.keys.any((key) =>
            key == 'steps' || key == 'activeEnergyKcal' ||
            key == 'exerciseMinutes' || key == 'workoutCount' ||
            key == 'workoutDurationMinutes')) {
          final metadataKey = 'sleep_tracker_activity_v1_$sessionId';
          final previousRaw = await SleepDatabase.instance.getAppMetadata(metadataKey);
          String merged;
          try {
            merged = mergeNightActivityMetadata(
              previousRaw: previousRaw,
              current: activity,
            );
          } on FormatException {
            // Never replace an existing activity record that cannot be read.
            continue;
          }
          await SleepDatabase.instance.setAppMetadata(metadataKey, merged);
        }
      }
    }

    return AppleHealthSyncResult(imported: imported, found: groups.length);
  }

  String? _stageName(HealthDataType type) => switch (type) {
    HealthDataType.SLEEP_AWAKE => 'Бодрствование',
    HealthDataType.SLEEP_ASLEEP => 'Сон без уточнённой фазы',
    HealthDataType.SLEEP_LIGHT => 'Лёгкий сон',
    HealthDataType.SLEEP_DEEP => 'Глубокий сон',
    HealthDataType.SLEEP_REM => 'REM-сон',
    _ => null,
  };

  (String, String)? _metricName(HealthDataType type) => switch (type) {
    HealthDataType.HEART_RATE => ('Пульс', 'уд/мин'),
    HealthDataType.RESPIRATORY_RATE => ('Частота дыхания', 'вдох/мин'),
    HealthDataType.BLOOD_OXYGEN => ('Насыщение кислородом', '%'),
    HealthDataType.HEART_RATE_VARIABILITY_SDNN => ('Вариабельность пульса SDNN', 'мс'),
    HealthDataType.WRIST_TEMPERATURE => ('Температура запястья', '°C'),
    _ => null,
  };

}
