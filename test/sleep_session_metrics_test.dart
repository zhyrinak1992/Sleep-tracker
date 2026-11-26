import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/sleep_session.dart';
import 'package:sleep_tracker/features/diary/sleep_session_metrics.dart';

void main() {
  test('calculates time in bed, latency, first awakening and conservative efficiency', () {
    final start = DateTime(2026, 11, 21, 22, 30);
    final session = SleepSession(
      id: 'night-1',
      startedAt: start,
      endedAt: DateTime(2026, 11, 22, 7),
      actualSleepStartedAt: DateTime(2026, 11, 21, 23),
      actualSleepEndedAt: DateTime(2026, 11, 22, 6, 30),
    );
    final stages = [
      {'stage': 'Глубокий сон', 'started_at': DateTime(2026, 11, 21, 23).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 1).toUtc().toIso8601String()},
      {'stage': 'Бодрствование', 'started_at': DateTime(2026, 11, 22, 1).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 1, 10).toUtc().toIso8601String()},
      {'stage': 'REM-сон', 'started_at': DateTime(2026, 11, 22, 1, 10).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 6, 30).toUtc().toIso8601String()},
    ];
    final result = SleepSessionMetrics.calculate(session: session, stages: stages);
    expect(result.timeInBedMinutes, 510);
    expect(result.sleepLatencyMinutes, 30);
    expect(result.sleepDurationMinutes, 440);
    expect(result.firstAwakeningAt, DateTime(2026, 11, 22, 1));
    expect(result.awakeningCount, 1);
    expect(result.hasAwakeSamples, isTrue);
    expect(result.awakeStageMinutes, 10);
    expect(result.stageBreakdownMinutes['Глубокий'], 120);
    expect(result.stageBreakdownMinutes['REM'], 320);
    expect(result.stageBreakdownMinutes['Бодрствование'], 10);
    expect(result.finalWakeAt, DateTime(2026, 11, 22, 6, 30));
    expect(result.sleepOnsetAt, DateTime(2026, 11, 21, 23));
    expect(result.sleepEndAt, DateTime(2026, 11, 22, 6, 30));
    expect(result.stageCoveragePercent, closeTo(450 / 510 * 100, 0.01));
    expect(result.sleepEfficiencyPercent, closeTo(440 / 510 * 100, 0.01));
  });

  test('does not report the stop-button time as an actual final wake', () {
    final session = SleepSession(
      id: 'manual-end-only',
      startedAt: DateTime(2026, 11, 24, 22),
      endedAt: DateTime(2026, 11, 25, 7),
    );

    final result = SleepSessionMetrics.calculate(
      session: session,
      stages: const [],
    );

    expect(result.timeInBedMinutes, 540);
    expect(result.finalWakeAt, isNull);
    expect(result.sleepEndAt, isNull);
  });

  test('does not invent efficiency without awake stage coverage', () {
    final start = DateTime(2026, 11, 21, 23);
    final session = SleepSession(
      id: 'night-2',
      startedAt: start,
      endedAt: DateTime(2026, 11, 22, 7),
    );
    final result = SleepSessionMetrics.calculate(session: session, stages: [
      {'stage': 'Лёгкий сон', 'started_at': start.toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 7).toUtc().toIso8601String()},
    ]);
    expect(result.sleepEfficiencyPercent, isNull);
    expect(result.hasAwakeSamples, isFalse);
    expect(result.stageCoveragePercent, 100);
    expect(result.sleepOnsetAt, start);
    expect(result.sleepEndAt, DateTime(2026, 11, 22, 7));
  });

  test('clips stages to time in bed and merges overlapping intervals', () {
    final start = DateTime(2026, 11, 21, 23);
    final session = SleepSession(id: 'night-3', startedAt: start, endedAt: DateTime(2026, 11, 22, 7));
    final result = SleepSessionMetrics.calculate(session: session, stages: [
      {'stage': 'Deep', 'started_at': DateTime(2026, 11, 21, 22, 50).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 2).toUtc().toIso8601String()},
      {'stage': 'Core', 'started_at': DateTime(2026, 11, 22, 1).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 4).toUtc().toIso8601String()},
    ]);
    expect(result.sleepDurationMinutes, 300);
    expect(result.timeInBedMinutes, 480);
  });

  test('counts separate awakenings and avoids generic sleep double counting', () {
    final start = DateTime(2026, 11, 21, 22);
    final end = DateTime(2026, 11, 22, 6);
    final session = SleepSession(id: 'night-awakenings', startedAt: start, endedAt: end);
    Map<String, Object?> stage(String name, DateTime from, DateTime to) => {
      'stage': name,
      'started_at': from.toUtc().toIso8601String(),
      'ended_at': to.toUtc().toIso8601String(),
    };
    final result = SleepSessionMetrics.calculate(session: session, stages: [
      stage('Сон без уточнённой фазы', start, end),
      stage('Лёгкий сон', start, DateTime(2026, 11, 21, 23)),
      stage('Бодрствование', DateTime(2026, 11, 21, 23), DateTime(2026, 11, 21, 23, 5)),
      stage('Бодрствование', DateTime(2026, 11, 22, 2), DateTime(2026, 11, 22, 2, 8)),
      stage('REM-сон', DateTime(2026, 11, 22, 2, 8), DateTime(2026, 11, 22, 3)),
    ]);
    expect(result.awakeningCount, 2);
    expect(result.awakeStageMinutes, 13);
    expect(result.stageBreakdownMinutes.values.fold<int>(0, (a, b) => a + b), 480);
    expect(result.stageBreakdownMinutes['Сон без уточнения'], 355);
    expect(result.sleepDurationMinutes, 467);
  });

}
