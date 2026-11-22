import '../../models/sleep_session.dart';

class SleepSessionMetrics {
  const SleepSessionMetrics({
    required this.timeInBedMinutes,
    required this.sleepDurationMinutes,
    required this.durationFromStages,
    required this.sleepLatencyMinutes,
    required this.firstAwakeningAt,
    required this.finalWakeAt,
    required this.sleepEfficiencyPercent,
    required this.stageCoveragePercent,
    required this.awakeStageMinutes,
  });

  final int? timeInBedMinutes;
  final int? sleepDurationMinutes;
  final bool durationFromStages;
  final int? sleepLatencyMinutes;
  final DateTime? firstAwakeningAt;
  final DateTime? finalWakeAt;
  final double? sleepEfficiencyPercent;
  final double? stageCoveragePercent;
  final int awakeStageMinutes;

  static SleepSessionMetrics calculate({
    required SleepSession session,
    required List<Map<String, Object?>> stages,
  }) {
    final bedStart = session.startedAt;
    final bedEnd = session.endedAt;
    final inBed = bedEnd != null && bedEnd.isAfter(bedStart)
        ? bedEnd.difference(bedStart).inMinutes
        : null;

    final asleep = <_SleepInterval>[];
    final awake = <_SleepInterval>[];
    for (final row in stages) {
      final stage = (row['stage'] as String? ?? '').toLowerCase();
      final startRaw = row['started_at'];
      final endRaw = row['ended_at'];
      if (startRaw is! String || endRaw is! String) continue;
      final start = DateTime.tryParse(startRaw)?.toLocal();
      final end = DateTime.tryParse(endRaw)?.toLocal();
      if (start == null || end == null || !end.isAfter(start)) continue;
      if (bedEnd != null) {
        final clippedStart = start.isBefore(bedStart) ? bedStart : start;
        final clippedEnd = end.isAfter(bedEnd) ? bedEnd : end;
        if (!clippedEnd.isAfter(clippedStart)) continue;
        final interval = _SleepInterval(clippedStart, clippedEnd);
        if (_isAwake(stage)) awake.add(interval);
        if (_isAsleep(stage)) asleep.add(interval);
      } else {
        if (_isAwake(stage)) awake.add(_SleepInterval(start, end));
        if (_isAsleep(stage)) asleep.add(_SleepInterval(start, end));
      }
    }

    final asleepMinutes = _mergedMinutes(asleep);
    final awakeMinutes = _mergedMinutes(awake);
    final coverageMinutes = _mergedMinutes([...asleep, ...awake]);
    final stageStart = asleep.isEmpty
        ? null
        : asleep.map((x) => x.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final stageEnd = asleep.isEmpty
        ? null
        : asleep.map((x) => x.end).reduce((a, b) => a.isAfter(b) ? a : b);
    final actualStart = session.actualSleepStartedAt ?? stageStart;
    final actualEnd = session.actualSleepEndedAt ?? stageEnd;
    final intervalDuration = actualStart != null && actualEnd != null &&
        actualEnd.isAfter(actualStart)
        ? actualEnd.difference(actualStart).inMinutes
        : null;
    final durationFromStages = asleepMinutes > 0;
    final sleepDuration = durationFromStages ? asleepMinutes : intervalDuration;
    final latency = actualStart != null && actualStart.isAfter(bedStart) &&
        (bedEnd == null || !actualStart.isAfter(bedEnd))
        ? actualStart.difference(bedStart).inMinutes
        : null;
    final awakeningCandidates = actualStart == null
        ? <DateTime>[]
        : awake.map((x) => x.start)
            .where((x) => !x.isBefore(actualStart))
            .toList()
          ..sort();
    final firstAwakening = awakeningCandidates.isEmpty
        ? null
        : awakeningCandidates.first;
    final finalWake = actualEnd ?? bedEnd;
    final coverage = inBed == null || inBed <= 0
        ? null
        : (coverageMinutes / inBed * 100).clamp(0, 100).toDouble();
    final efficiency = inBed != null && inBed > 0 &&
        awakeMinutes > 0 && coverage != null && coverage >= 80 &&
        asleepMinutes > 0 && asleepMinutes <= inBed
        ? asleepMinutes / inBed * 100
        : null;

    return SleepSessionMetrics(
      timeInBedMinutes: inBed,
      sleepDurationMinutes: sleepDuration,
      durationFromStages: durationFromStages,
      sleepLatencyMinutes: latency,
      firstAwakeningAt: firstAwakening,
      finalWakeAt: finalWake,
      sleepEfficiencyPercent: efficiency,
      stageCoveragePercent: coverage,
      awakeStageMinutes: awakeMinutes,
    );
  }

  static bool _isAwake(String stage) =>
      stage.contains('бодрств') || stage == 'awake' || stage.contains('awake');

  static bool _isAsleep(String stage) {
    if (_isAwake(stage)) return false;
    return stage.contains('сон') || stage.contains('asleep') ||
        stage.contains('core') || stage.contains('deep') ||
        stage.contains('light') || stage.contains('rem');
  }

  static int _mergedMinutes(List<_SleepInterval> intervals) {
    if (intervals.isEmpty) return 0;
    final sorted = intervals.toList()..sort((a, b) => a.start.compareTo(b.start));
    var start = sorted.first.start;
    var end = sorted.first.end;
    var total = 0;
    for (final interval in sorted.skip(1)) {
      if (!interval.start.isAfter(end)) {
        if (interval.end.isAfter(end)) end = interval.end;
      } else {
        total += end.difference(start).inMinutes;
        start = interval.start;
        end = interval.end;
      }
    }
    total += end.difference(start).inMinutes;
    return total;
  }
}

class _SleepInterval {
  const _SleepInterval(this.start, this.end);
  final DateTime start;
  final DateTime end;
}
