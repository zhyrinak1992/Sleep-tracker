import 'package:health/health.dart';

import 'sleep_database.dart';

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
    HealthDataType.HEART_RATE,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  Future<AppleHealthSyncResult> syncRecentSleep({int days = 30}) async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    final authorized = await _health.requestAuthorization(_sleepTypes);
    if (!authorized) {
      throw StateError('iOS не завершила запрос разрешения Apple Health.');
    }

    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    final points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: start,
      endTime: end,
    );
    final unique = _health.removeDuplicates(points);
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
      final inserted = await SleepDatabase.instance.insertHealthSession(
        id: safeId,
        startedAt: startedAt,
        endedAt: endedAt,
        sourceName: sourceName.isEmpty ? 'Apple Health' : sourceName,
      );
      if (inserted) imported++;
      for (final point in sorted) {
        final stage = _stageName(point.type);
        if (stage != null) {
          await SleepDatabase.instance.addSleepStage(
            id: 'health_stage_${point.uuid.replaceAll('-', '_')}',
            sessionId: safeId, stage: stage, startedAt: point.dateFrom,
            endedAt: point.dateTo, source: 'Apple Health: ${point.sourceName}',
          );
          continue;
        }
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
          final sessionId = 'health_${first.uuid.replaceAll('-', '_')}';
          await SleepDatabase.instance.addSleepMetric(id: 'health_metric_${point.uuid.replaceAll('-', '_')}', sessionId: sessionId, type: metric.$1, value: (point.value as NumericHealthValue).numericValue.toDouble(), unit: metric.$2, measuredAt: point.dateTo, source: 'Apple Health: ${point.sourceName}');
          break;
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
    _ => null,
  };

}
