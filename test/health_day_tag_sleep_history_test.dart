import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/health/health_day_tag_sleep_history.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  final start = DateTime(2026, 11, 24, 21, 30);
  final end = DateTime(2026, 11, 25, 6);

  SleepSession session(String id, {
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? deletedAt,
    int? rating,
  }) {
    final actualStart = startedAt ?? start;
    final actualEnd = endedAt ?? end;
    return SleepSession(
      id: id,
      startedAt: actualStart,
      endedAt: actualEnd,
      duration: actualEnd.difference(actualStart),
      deletedAt: deletedAt,
      morningRating: rating,
    );
  }

  Map<String, Object?> stage(String id, String name, DateTime from, DateTime to) => {
    'id': id,
    'stage': name,
    'started_at': from.toIso8601String(),
    'ended_at': to.toIso8601String(),
  };

  final completeStages = [
    stage('1', 'Основной', DateTime(2026, 11, 24, 22), DateTime(2026, 11, 25, 1)),
    stage('2', 'Бодрствование', DateTime(2026, 11, 25, 1), DateTime(2026, 11, 25, 1, 15)),
    stage('3', 'REM', DateTime(2026, 11, 25, 1, 15), DateTime(2026, 11, 25, 4)),
    stage('4', 'Бодрствование', DateTime(2026, 11, 25, 4), DateTime(2026, 11, 25, 4, 15)),
    stage('5', 'Глубокий', DateTime(2026, 11, 25, 4, 15), DateTime(2026, 11, 25, 6)),
  ];

  final tags = {
    DateTime(2026, 11, 25): ['Кофеин'],
    DateTime(2026, 11, 24): ['Поздний ужин'],
  };

  test('builds tagged nightly duration, efficiency, latency and rating points', () {
    final night = session('complete', rating: 4);
    List<HealthDayTagNightMetricPoint> calculate(HealthDayTagNightMetric metric) =>
        HealthDayTagNightHistory.calculate(
          sessions: [night],
          tagsByDay: tags,
          stagesBySession: {'complete': completeStages},
          tag: 'Кофеин',
          start: DateTime(2026, 11, 24),
          endExclusive: DateTime(2026, 11, 26),
          metric: metric,
        );

    final duration = calculate(HealthDayTagNightMetric.sleepDuration);
    final efficiency = calculate(HealthDayTagNightMetric.sleepEfficiency);
    final latency = calculate(HealthDayTagNightMetric.sleepLatency);
    final rating = calculate(HealthDayTagNightMetric.morningRating);
    final awakenings = calculate(HealthDayTagNightMetric.awakenings);

    expect(duration, hasLength(1));
    expect(duration.single.value, 7.5);
    expect(efficiency.single.value, closeTo(7.5 / 8.5 * 100, 0.001));
    expect(latency.single.value, 30);
    expect(awakenings.single.value, 2);
    expect(rating.single.value, 4);
  });

  test('does not publish efficiency or awakening count below 80 percent coverage', () {
    final night = session('partial');
    final partialStages = [
      stage('1', 'Основной', DateTime(2026, 11, 24, 22), DateTime(2026, 11, 25, 2)),
    ];
    List<HealthDayTagNightMetricPoint> calculate(HealthDayTagNightMetric metric) =>
        HealthDayTagNightHistory.calculate(
          sessions: [night],
          tagsByDay: tags,
          stagesBySession: {'partial': partialStages},
          tag: 'Кофеин',
          start: DateTime(2026, 11, 24),
          endExclusive: DateTime(2026, 11, 26),
          metric: metric,
        );

    final efficiency = calculate(HealthDayTagNightMetric.sleepEfficiency);
    final awakenings = calculate(HealthDayTagNightMetric.awakenings);

    expect(efficiency.single.value, isNull);
    expect(awakenings.single.value, isNull);
  });

  test('does not turn missing awake-stage samples into zero awakenings', () {
    final night = session('no-awake');
    final sleepOnlyStages = [
      stage('1', 'Основной', DateTime(2026, 11, 24, 22), DateTime(2026, 11, 25, 1)),
      stage('2', 'REM', DateTime(2026, 11, 25, 1), DateTime(2026, 11, 25, 4)),
      stage('3', 'Глубокий', DateTime(2026, 11, 25, 4), DateTime(2026, 11, 25, 6)),
    ];
    final result = HealthDayTagNightHistory.calculate(
      sessions: [night],
      tagsByDay: tags,
      stagesBySession: {'no-awake': sleepOnlyStages},
      tag: 'Кофеин',
      start: DateTime(2026, 11, 24),
      endExclusive: DateTime(2026, 11, 26),
      metric: HealthDayTagNightMetric.awakenings,
    );

    expect(result.single.value, isNull);
  });

  test('filters untagged, out-of-period and deleted nights and sorts chronologically', () {
    final older = session(
      'older',
      startedAt: DateTime(2026, 11, 23, 21),
      endedAt: DateTime(2026, 11, 24, 6),
    );
    final newer = session('newer');
    final deleted = session('deleted', deletedAt: DateTime(2026, 11, 25, 7));
    final untagged = session(
      'untagged',
      startedAt: DateTime(2026, 11, 22, 21),
      endedAt: DateTime(2026, 11, 23, 6),
    );
    final result = HealthDayTagNightHistory.calculate(
      sessions: [newer, deleted, untagged, older],
      tagsByDay: {
        DateTime(2026, 11, 24): ['Кофеин'],
        DateTime(2026, 11, 25): ['Кофеин'],
      },
      stagesBySession: const {},
      tag: 'Кофеин',
      start: DateTime(2026, 11, 24),
      endExclusive: DateTime(2026, 11, 26),
      metric: HealthDayTagNightMetric.morningRating,
    );

    expect(result.map((point) => point.sessionId), ['older', 'newer']);
  });
}
