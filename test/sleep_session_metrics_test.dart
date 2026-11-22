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
    expect(result.finalWakeAt, DateTime(2026, 11, 22, 6, 30));
    expect(result.awakeningCount, 1);
    expect(result.awakeStageMinutes, 10);
    expect(result.stageMinutes['deep'], 120);
    expect(result.stageMinutes['rem'], 320);
    expect(result.stageCoveragePercent, closeTo(450 / 510 * 100, 0.01));
    expect(result.sleepEfficiencyPercent, closeTo(440 / 510 * 100, 0.01));
  });

  test('counts separate night awakenings and excludes the final wake-up', () {
    final start = DateTime(2026, 11, 21, 22);
    final session = SleepSession(
      id: 'night-awakenings',
      startedAt: start,
      endedAt: DateTime(2026, 11, 22, 7),
      actualSleepStartedAt: DateTime(2026, 11, 21, 22, 30),
      actualSleepEndedAt: DateTime(2026, 11, 22, 6, 30),
    );
    final stages = [
      {'stage': 'Лёгкий сон', 'started_at': DateTime(2026, 11, 21, 22, 30).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 0, 30).toUtc().toIso8601String()},
      {'stage': 'Бодрствование', 'started_at': DateTime(2026, 11, 22, 0, 30).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 0, 40).toUtc().toIso8601String()},
      {'stage': 'Глубокий сон', 'started_at': DateTime(2026, 11, 22, 0, 40).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 2).toUtc().toIso8601String()},
      {'stage': 'Бодрствование', 'started_at': DateTime(2026, 11, 22, 2).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 2, 7).toUtc().toIso8601String()},
      {'stage': 'REM-сон', 'started_at': DateTime(2026, 11, 22, 2, 7).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 6, 30).toUtc().toIso8601String()},
      {'stage': 'Бодрствование', 'started_at': DateTime(2026, 11, 22, 6, 30).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 7).toUtc().toIso8601String()},
    ];
    final result = SleepSessionMetrics.calculate(session: session, stages: stages);
    expect(result.awakeningCount, 2);
    expect(result.awakeningIntervals.map((x) => x.durationMinutes).toList(), [10, 7]);
    expect(result.firstAwakeningAt, DateTime(2026, 11, 22, 0, 30));
    expect(result.awakeStageMinutes, 47);
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
    expect(result.stageCoveragePercent, 100);
  });

  test('clips stages to time in bed and merges overlapping intervals', () {
    final start = DateTime(2026, 11, 21, 23);
    final result = SleepSessionMetrics.calculate(
      session: SleepSession(id: 'night-3', startedAt: start, endedAt: DateTime(2026, 11, 22, 7)),
      stages: [
        {'stage': 'Deep', 'started_at': DateTime(2026, 11, 21, 22, 50).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 2).toUtc().toIso8601String()},
        {'stage': 'Core', 'started_at': DateTime(2026, 11, 22, 1).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 4).toUtc().toIso8601String()},
      ],
    );
    expect(result.sleepDurationMinutes, 300);
    expect(result.timeInBedMinutes, 480);
    expect(result.stageMinutes['deep'], 180);
    expect(result.stageMinutes['light'], 120);
  });
  test('merges overlapping awake samples into one awakening event', () {
    final start = DateTime(2026, 11, 21, 22);
    final result = SleepSessionMetrics.calculate(
      session: SleepSession(
        id: 'night-overlap',
        startedAt: start,
        endedAt: DateTime(2026, 11, 22, 7),
        actualSleepStartedAt: DateTime(2026, 11, 21, 22, 30),
        actualSleepEndedAt: DateTime(2026, 11, 22, 6, 30),
      ),
      stages: [
        {'stage': 'Лёгкий сон', 'started_at': DateTime(2026, 11, 21, 22, 30).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 0, 30).toUtc().toIso8601String()},
        {'stage': 'Бодрствование', 'started_at': DateTime(2026, 11, 22, 0, 30).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 0, 45).toUtc().toIso8601String()},
        {'stage': 'Бодрствование', 'started_at': DateTime(2026, 11, 22, 0, 40).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 0, 50).toUtc().toIso8601String()},
        {'stage': 'REM-сон', 'started_at': DateTime(2026, 11, 22, 0, 50).toUtc().toIso8601String(), 'ended_at': DateTime(2026, 11, 22, 6, 30).toUtc().toIso8601String()},
      ],
    );
    expect(result.awakeningCount, 1);
    expect(result.awakeningIntervals.single.durationMinutes, 20);
  });

}
