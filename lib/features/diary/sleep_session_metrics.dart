import '../../models/sleep_session.dart';

class SleepSessionMetrics {
  const SleepSessionMetrics({
    required this.timeInBedMinutes,
    required this.sleepDurationMinutes,
    required this.durationFromStages,
    required this.sleepLatencyMinutes,
    required this.firstAwakeningAt,
    required this.finalWakeAt,
    required this.sleepOnsetAt,
    required this.sleepEndAt,
    required this.sleepEfficiencyPercent,
    required this.stageCoveragePercent,
    required this.awakeStageMinutes,
    required this.awakeningCount,
    required this.stageBreakdownMinutes,
  });

  final int? timeInBedMinutes;
  final int? sleepDurationMinutes;
  final bool durationFromStages;
  final int? sleepLatencyMinutes;
  final DateTime? firstAwakeningAt;
  final DateTime? finalWakeAt;
  /// Actual sleep onset from explicit boundaries or the first asleep stage.
  final DateTime? sleepOnsetAt;
  /// Actual sleep end from explicit boundaries or the last asleep stage.
  final DateTime? sleepEndAt;
  final double? sleepEfficiencyPercent;
  final double? stageCoveragePercent;
  final int awakeStageMinutes;
  final int awakeningCount;
  final Map<String, int> stageBreakdownMinutes;

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

    final mergedAwake = _mergeIntervals(awake);
    final awakeMinutes = _durationMinutes(mergedAwake);
    final stageBreakdown = _stageBreakdown(stages, bedStart, bedEnd);
    // Subtract awake samples even when a broad asleep sample overlaps them.
    final asleepMinutes = stageBreakdown.entries
        .where((entry) => entry.key != 'Бодрствование')
        .fold<int>(0, (sum, entry) => sum + entry.value);
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
    final hasConfirmedSleepBoundaries =
        session.actualSleepStartedAt != null &&
        session.actualSleepEndedAt != null;
    final efficiency = inBed != null && inBed > 0 &&
        (awakeMinutes > 0 || hasConfirmedSleepBoundaries) &&
        coverage != null && coverage >= 80 &&
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
      sleepOnsetAt: actualStart,
      sleepEndAt: actualEnd,
      sleepEfficiencyPercent: efficiency,
      stageCoveragePercent: coverage,
      awakeStageMinutes: awakeMinutes,
      awakeningCount: mergedAwake.length,
      stageBreakdownMinutes: stageBreakdown,
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

  static int _mergedMinutes(List<_SleepInterval> intervals) =>
      _durationMinutes(_mergeIntervals(intervals));

  static int _durationMinutes(List<_SleepInterval> intervals) =>
      intervals.fold<int>(0, (sum, interval) =>
          sum + interval.end.difference(interval.start).inMinutes);

  static List<_SleepInterval> _mergeIntervals(List<_SleepInterval> intervals) {
    if (intervals.isEmpty) return const [];
    final sorted = intervals.toList()..sort((a, b) => a.start.compareTo(b.start));
    var start = sorted.first.start;
    var end = sorted.first.end;
    final result = <_SleepInterval>[];
    for (final interval in sorted.skip(1)) {
      if (!interval.start.isAfter(end)) {
        if (interval.end.isAfter(end)) end = interval.end;
      } else {
        result.add(_SleepInterval(start, end));
        start = interval.start;
        end = interval.end;
      }
    }
    result.add(_SleepInterval(start, end));
    return result;
  }

  /// Creates a non-overlapping phase distribution; generic asleep samples
  /// do not double-count more specific stage intervals.
  static Map<String, int> _stageBreakdown(List<Map<String, Object?>> stages, DateTime bedStart, DateTime? bedEnd) {
    final intervals = <({String category, DateTime start, DateTime end})>[];
    for (final row in stages) {
      final category = _stageCategory((row['stage'] as String? ?? '').toLowerCase());
      final startRaw = row['started_at'], endRaw = row['ended_at'];
      if (category == null || startRaw is! String || endRaw is! String) continue;
      var start = DateTime.tryParse(startRaw)?.toLocal();
      var end = DateTime.tryParse(endRaw)?.toLocal();
      if (start == null || end == null || !end.isAfter(start)) continue;
      if (start.isBefore(bedStart)) start = bedStart;
      if (bedEnd != null && end.isAfter(bedEnd)) end = bedEnd;
      if (end.isAfter(start)) intervals.add((category: category, start: start, end: end));
    }
    if (intervals.isEmpty) return const {};
    final boundaries = intervals.expand((x) => [x.start, x.end]).toSet().toList()..sort();
    const priority = ['Бодрствование', 'REM', 'Глубокий', 'Основной', 'Лёгкий', 'Сон без уточнения'];
    final totals = <String, int>{};
    for (var i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i], end = boundaries[i + 1];
      final active = intervals.where((x) => !x.start.isAfter(start) && !x.end.isBefore(end));
      if (active.isEmpty) continue;
      final categories = active.map((x) => x.category).toSet();
      final selected = priority.firstWhere(categories.contains, orElse: () => categories.first);
      totals[selected] = (totals[selected] ?? 0) + end.difference(start).inMinutes;
    }
    return Map.unmodifiable(totals);
  }

  static String? _stageCategory(String stage) {
    if (_isAwake(stage)) return 'Бодрствование';
    if (stage.contains('rem') || stage.contains('быстр')) return 'REM';
    if (stage.contains('deep') || stage.contains('глубок')) return 'Глубокий';
    if (stage.contains('core') || stage.contains('основн')) return 'Основной';
    if (stage.contains('light') || stage.contains('лёгк') || stage.contains('легк')) return 'Лёгкий';
    if (_isAsleep(stage)) return 'Сон без уточнения';
    return null;
  }
}

class _SleepInterval {
  const _SleepInterval(this.start, this.end);
  final DateTime start;
  final DateTime end;
}
