import '../../models/sleep_session.dart';

class SleepAwakening {
  const SleepAwakening({required this.startedAt, required this.endedAt});

  final DateTime startedAt;
  final DateTime endedAt;

  int get durationMinutes => endedAt.difference(startedAt).inMinutes;
}

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
    required this.awakeningIntervals,
    required this.stageMinutes,
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
  final List<SleepAwakening> awakeningIntervals;
  /// Disjoint durations, so overlapping HealthKit samples are never counted twice.
  final Map<String, int> stageMinutes;

  int get awakeningCount => awakeningIntervals.length;

  static const _categories = ['awake', 'deep', 'rem', 'light', 'unspecified'];

  static SleepSessionMetrics calculate({
    required SleepSession session,
    required List<Map<String, Object?>> stages,
  }) {
    final bedStart = session.startedAt;
    final bedEnd = session.endedAt;
    final inBed = bedEnd != null && bedEnd.isAfter(bedStart)
        ? bedEnd.difference(bedStart).inMinutes
        : null;

    final raw = <_SleepInterval>[];
    for (final row in stages) {
      final category = _stageCategory((row['stage'] as String? ?? '').toLowerCase());
      final startRaw = row['started_at'];
      final endRaw = row['ended_at'];
      if (category == null || startRaw is! String || endRaw is! String) continue;
      final start = DateTime.tryParse(startRaw)?.toLocal();
      final end = DateTime.tryParse(endRaw)?.toLocal();
      if (start == null || end == null || !end.isAfter(start)) continue;
      final clippedStart = start.isBefore(bedStart) ? bedStart : start;
      final clippedEnd = bedEnd != null && end.isAfter(bedEnd) ? bedEnd : end;
      if (!clippedEnd.isAfter(clippedStart)) continue;
      raw.add(_SleepInterval(clippedStart, clippedEnd, category));
    }

    // Split at every sample boundary and assign each instant to one category.
    // This prevents duplicate HealthKit sources or overlapping phase samples
    // from inflating sleep duration, awakenings, or the phase chart.
    final boundaries = raw
        .expand((interval) => [interval.start, interval.end])
        .toSet()
        .toList()
      ..sort();
    final disjoint = <String, List<_SleepInterval>>{
      for (final category in _categories) category: <_SleepInterval>[],
    };
    for (var i = 0; i + 1 < boundaries.length; i++) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      if (!end.isAfter(start)) continue;
      final active = raw.where((interval) =>
          !interval.start.isAfter(start) && !interval.end.isBefore(end));
      if (active.isEmpty) continue;
      final category = active
          .map((interval) => interval.category)
          .reduce((a, b) => _priority(a) <= _priority(b) ? a : b);
      disjoint[category]!.add(_SleepInterval(start, end, category));
    }

    final stageMinutes = <String, int>{
      for (final category in _categories)
        category: _mergedMinutes(disjoint[category]!),
    };
    final asleepMinutes = stageMinutes['deep']! +
        stageMinutes['rem']! +
        stageMinutes['light']! +
        stageMinutes['unspecified']!;
    final awakeMinutes = stageMinutes['awake']!;
    final coverageMinutes = stageMinutes.values.fold<int>(0, (a, b) => a + b);
    final asleepIntervals = _categories
        .where((category) => category != 'awake')
        .expand((category) => disjoint[category]!)
        .toList();
    final stageStart = asleepIntervals.isEmpty
        ? null
        : asleepIntervals.map((x) => x.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final stageEnd = asleepIntervals.isEmpty
        ? null
        : asleepIntervals.map((x) => x.end).reduce((a, b) => a.isAfter(b) ? a : b);
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
    final finalWake = actualEnd ?? bedEnd;
    final awakenings = <SleepAwakening>[];
    if (actualStart != null) {
      for (final interval in disjoint['awake']!) {
        // The terminal wake-up is not counted as a night awakening.
        if (!interval.start.isBefore(actualStart) &&
            (finalWake == null || interval.end.isBefore(finalWake))) {
          awakenings.add(SleepAwakening(
            startedAt: interval.start,
            endedAt: interval.end,
          ));
        }
      }
    }
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
      firstAwakeningAt: awakenings.isEmpty ? null : awakenings.first.startedAt,
      finalWakeAt: finalWake,
      sleepEfficiencyPercent: efficiency,
      stageCoveragePercent: coverage,
      awakeStageMinutes: awakeMinutes,
      awakeningIntervals: List.unmodifiable(awakenings),
      stageMinutes: Map.unmodifiable(stageMinutes),
    );
  }

  static String? _stageCategory(String stage) {
    if (stage.contains('бодрств') || stage == 'awake' || stage.contains('awake')) {
      return 'awake';
    }
    if (stage.contains('deep') || stage.contains('глубок')) return 'deep';
    if (stage.contains('rem') || stage.contains('быстр')) return 'rem';
    if (stage.contains('light') || stage.contains('core') || stage.contains('лёгк') || stage.contains('легк')) {
      return 'light';
    }
    if (stage.contains('сон') || stage.contains('asleep')) return 'unspecified';
    return null;
  }

  static int _priority(String category) => switch (category) {
    'awake' => 0,
    'deep' => 1,
    'rem' => 2,
    'light' => 3,
    _ => 4,
  };

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
  const _SleepInterval(this.start, this.end, this.category);
  final DateTime start;
  final DateTime end;
  final String category;
}
