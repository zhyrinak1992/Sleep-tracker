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
    final quality = HealthDayTagNightHistory.calculate(
      sessions: [night],
      tagsByDay: tags,
      stagesBySession: {'complete': completeStages},
      morningReportsBySession: {
        'complete': {'sleep_quality': 5, 'wellbeing': 3},
      },
      tag: 'Кофеин',
      start: DateTime(2026, 11, 24),
      endExclusive: DateTime(2026, 11, 26),
      metric: HealthDayTagNightMetric.sleepQuality,
    );
    final wellbeing = HealthDayTagNightHistory.calculate(
      sessions: [night],
      tagsByDay: tags,
      stagesBySession: {'complete': completeStages},
      morningReportsBySession: {
        'complete': {'sleep_quality': 5, 'wellbeing': 3},
      },
      tag: 'Кофеин',
      start: DateTime(2026, 11, 24),
      endExclusive: DateTime(2026, 11, 26),
      metric: HealthDayTagNightMetric.wellbeing,
    );
    expect(quality.single.value, 5);
    expect(wellbeing.single.value, 3);
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


  test('does not classify nights without a saved diary entry as untagged', () {
    final tagged = session(
      'tagged',
      startedAt: DateTime(2026, 10, 1, 21),
      endedAt: DateTime(2026, 10, 2, 6),
      rating: 4,
    );
    final recordedWithoutTag = session(
      'recorded-without-tag',
      startedAt: DateTime(2026, 10, 2, 21),
      endedAt: DateTime(2026, 10, 3, 6),
      rating: 2,
    );
    final noDiaryEntry = session(
      'no-diary-entry',
      startedAt: DateTime(2026, 10, 3, 21),
      endedAt: DateTime(2026, 10, 4, 6),
      rating: 1,
    );
    final tagsByDay = {
      DateTime(2026, 10, 2): ['Кофеин'],
      DateTime(2026, 10, 3): <String>[],
    };

    final withTag = HealthDayTagNightHistory.calculate(
      sessions: [tagged, recordedWithoutTag, noDiaryEntry],
      tagsByDay: tagsByDay,
      stagesBySession: const {},
      tag: 'Кофеин',
      start: DateTime(2026, 10, 2),
      endExclusive: DateTime(2026, 10, 5),
      metric: HealthDayTagNightMetric.morningRating,
      withTag: true,
    );
    final withoutTag = HealthDayTagNightHistory.calculate(
      sessions: [tagged, recordedWithoutTag, noDiaryEntry],
      tagsByDay: tagsByDay,
      stagesBySession: const {},
      tag: 'Кофеин',
      start: DateTime(2026, 10, 2),
      endExclusive: DateTime(2026, 10, 5),
      metric: HealthDayTagNightMetric.morningRating,
      withTag: false,
    );

    expect(withTag.map((point) => point.sessionId), ['tagged']);
    expect(withoutTag.map((point) => point.sessionId), ['recorded-without-tag']);
  });

  test('does not report a tagged-vs-untagged difference below the minimum sample size', () {
    final taggedFirst = session(
      'tagged-first',
      startedAt: DateTime(2026, 10, 1, 21),
      endedAt: DateTime(2026, 10, 2, 6),
      rating: 4,
    );
    final untaggedFirst = session(
      'untagged-first',
      startedAt: DateTime(2026, 10, 2, 21),
      endedAt: DateTime(2026, 10, 3, 6),
      rating: 2,
    );
    final taggedSecond = session(
      'tagged-second',
      startedAt: DateTime(2026, 10, 3, 21),
      endedAt: DateTime(2026, 10, 4, 6),
      rating: 3,
    );
    final untaggedSecond = session(
      'untagged-second',
      startedAt: DateTime(2026, 10, 4, 21),
      endedAt: DateTime(2026, 10, 5, 6),
      rating: 2,
    );

    final result = HealthDayTagNightHistory.comparePeriods(
      sessions: [
        taggedFirst,
        untaggedFirst,
        taggedSecond,
        untaggedSecond,
      ],
      tagsByDay: {
        DateTime(2026, 10, 2): ['Кофеин'],
        DateTime(2026, 10, 3): ['Поздний ужин'],
        DateTime(2026, 10, 4): ['Кофеин'],
        DateTime(2026, 10, 5): ['Стресс'],
      },
      stagesBySession: const {},
      tag: 'Кофеин',
      firstStart: DateTime(2026, 10, 2),
      firstEndExclusive: DateTime(2026, 10, 4),
      secondStart: DateTime(2026, 10, 4),
      secondEndExclusive: DateTime(2026, 10, 6),
      metric: HealthDayTagNightMetric.morningRating,
    );

    expect(result.first.withTag.nights, 1);
    expect(result.first.withTag.validSamples, 1);
    expect(result.first.withTag.average, 4);
    expect(result.first.withoutTag.average, 2);
    expect(result.first.hasSufficientSamples, isFalse);
    expect(result.first.difference, isNull);
    expect(result.second.hasSufficientSamples, isFalse);
    expect(result.second.difference, isNull);
    expect(result.differenceChange, isNull);
  });

  test('reports a difference only after four valid values in each group', () {
    final sessions = <SleepSession>[];
    final tagsByDay = <DateTime, List<String>>{};
    void addNight({required int endDay, required bool tagged, required int rating, required String id}) {
      final endedAt = DateTime(2026, 10, endDay, 6);
      sessions.add(session(id, startedAt: endedAt.subtract(const Duration(hours: 9)), endedAt: endedAt, rating: rating));
      if (tagged) tagsByDay[DateTime(2026, 10, endDay)] = ['Кофеин'];
      else tagsByDay[DateTime(2026, 10, endDay)] = <String>[];
    }
    for (var i = 0; i < 4; i++) {
      addNight(endDay: 2 + i * 2, tagged: true, rating: 4, id: 'first-tagged-$i');
      addNight(endDay: 3 + i * 2, tagged: false, rating: 2, id: 'first-untagged-$i');
      addNight(endDay: 10 + i * 2, tagged: true, rating: 3, id: 'second-tagged-$i');
      addNight(endDay: 11 + i * 2, tagged: false, rating: 2, id: 'second-untagged-$i');
    }
    final result = HealthDayTagNightHistory.comparePeriods(
      sessions: sessions, tagsByDay: tagsByDay, stagesBySession: const {},
      tag: 'Кофеин',
      firstStart: DateTime(2026, 10, 2), firstEndExclusive: DateTime(2026, 10, 10),
      secondStart: DateTime(2026, 10, 10), secondEndExclusive: DateTime(2026, 10, 18),
      metric: HealthDayTagNightMetric.morningRating,
    );
    expect(result.first.hasSufficientSamples, isTrue);
    expect(result.first.withTag.validSamples, 4);
    expect(result.first.withoutTag.validSamples, 4);
    expect(result.first.difference, 2);
    expect(result.second.difference, 1);
    expect(result.differenceChange, -1);
  });
  test('keeps missing metric values out of averages and reports their sample count', () {
    final tagged = session(
      'tagged-missing',
      startedAt: DateTime(2026, 10, 1, 21),
      endedAt: DateTime(2026, 10, 2, 6),
    );
    final untagged = session(
      'untagged-rated',
      startedAt: DateTime(2026, 10, 2, 21),
      endedAt: DateTime(2026, 10, 3, 6),
      rating: 3,
    );

    final result = HealthDayTagNightHistory.comparePeriods(
      sessions: [tagged, untagged],
      tagsByDay: {
        DateTime(2026, 10, 2): ['Кофеин'],
        DateTime(2026, 10, 3): ['Стресс'],
      },
      stagesBySession: const {},
      tag: 'Кофеин',
      firstStart: DateTime(2026, 10, 2),
      firstEndExclusive: DateTime(2026, 10, 4),
      secondStart: DateTime(2026, 10, 2),
      secondEndExclusive: DateTime(2026, 10, 4),
      metric: HealthDayTagNightMetric.morningRating,
    );

    expect(result.first.withTag.nights, 1);
    expect(result.first.withTag.validSamples, 0);
    expect(result.first.withTag.average, isNull);
    expect(result.first.withoutTag.validSamples, 1);
    expect(result.first.difference, isNull);
    expect(result.differenceChange, isNull);
  });

  test('filters untagged, out-of-period and deleted nights and sorts chronologically', () {
    final older = session(
      'older',
      startedAt: DateTime(2026, 11, 23, 21),
      endedAt: DateTime(2026, 11, 24, 6),
    );
    final newer = session(
      'newer',
      startedAt: DateTime(2026, 11, 25, 21),
      endedAt: DateTime(2026, 11, 26, 6),
    );
    final deleted = session(
      'deleted',
      startedAt: DateTime(2026, 11, 25, 21),
      endedAt: DateTime(2026, 11, 26, 6),
      deletedAt: DateTime(2026, 11, 26, 7),
    );
    final untagged = session(
      'untagged',
      startedAt: DateTime(2026, 11, 24, 21),
      endedAt: DateTime(2026, 11, 25, 6),
    );
    final result = HealthDayTagNightHistory.calculate(
      sessions: [newer, deleted, untagged, older],
      tagsByDay: {
        DateTime(2026, 11, 24): ['Кофеин'],
        DateTime(2026, 11, 25): ['Поздний ужин'],
        DateTime(2026, 11, 26): ['Кофеин'],
      },
      stagesBySession: const {},
      tag: 'Кофеин',
      start: DateTime(2026, 11, 24),
      endExclusive: DateTime(2026, 11, 27),
      metric: HealthDayTagNightMetric.morningRating,
    );

    expect(result.map((point) => point.sessionId), ['older', 'newer']);
  });
}
