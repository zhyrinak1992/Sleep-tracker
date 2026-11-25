import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_personal_records.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession session(
  String id,
  DateTime start, {
  DateTime? end,
  DateTime? actualStart,
  DateTime? deletedAt,
}) => SleepSession(
  id: id,
  startedAt: start,
  endedAt: end ?? start.add(const Duration(hours: 8)),
  actualSleepStartedAt: actualStart,
  deletedAt: deletedAt,
);

Map<String, Object?> stage(String name, DateTime start, DateTime end) => {
  'stage': name,
  'started_at': start.toUtc().toIso8601String(),
  'ended_at': end.toUtc().toIso8601String(),
};

void main() {
  group('SleepPersonalRecords', () {
    test('calculates duration, SleepScore, covered efficiency and awakenings', () {
      final start = DateTime(2026, 11, 20, 22);
      final night = session(
        'night-1',
        start,
        end: start.add(const Duration(hours: 8)),
        actualStart: start.add(const Duration(minutes: 20)),
      );
      final records = SleepPersonalRecords.calculate(
        sessions: [night],
        morningReports: const {
          'night-1': {'sleep_quality': 4},
        },
        stagesBySession: {
          'night-1': [
            stage('Deep', start.add(const Duration(minutes: 20)),
                start.add(const Duration(hours: 3))),
            stage('Awake', start.add(const Duration(hours: 3)),
                start.add(const Duration(hours: 3, minutes: 20))),
            stage('REM', start.add(const Duration(hours: 3, minutes: 20)),
                start.add(const Duration(hours: 8))),
          ],
        },
      );

      expect(records.longestSleepMinutes, 440);
      expect(records.bestEfficiencyPercent, closeTo(440 / 480 * 100, 0.01));
      expect(records.bestSleepScore, isNotNull);
      expect(records.fewestAwakenings, 1);
      expect(records.longestSleepSessionId, 'night-1');
    });

    test('does not invent efficiency or latency when coverage/boundaries are absent', () {
      final start = DateTime(2026, 11, 20, 22);
      final records = SleepPersonalRecords.calculate(
        sessions: [session('night-1', start)],
        morningReports: const {},
        stagesBySession: {
          'night-1': [
            stage('Light', start, start.add(const Duration(hours: 8))),
          ],
        },
      );

      expect(records.bestEfficiencyPercent, isNull);
      expect(records.shortestLatencyMinutes, isNull);
    });

    test('ignores deleted, open and non-positive sessions', () {
      final start = DateTime(2026, 11, 20, 22);
      final records = SleepPersonalRecords.calculate(
        sessions: [
          session('deleted', start, deletedAt: DateTime(2026, 11, 22)),
          SleepSession(id: 'open', startedAt: start),
          session('invalid', start, end: start),
        ],
        morningReports: const {},
        stagesBySession: const {},
      );

      expect(records.longestSleepMinutes, isNull);
      expect(records.longestStreakDays, 0);
    });

    test('counts one calendar date once and handles daylight-saving date changes', () {
      final nights = [
        session('a', DateTime(2026, 3, 28, 22)),
        session('b', DateTime(2026, 3, 28, 23)),
        session('c', DateTime(2026, 3, 29, 22)),
        session('d', DateTime(2026, 3, 30, 22)),
        session('gap', DateTime(2026, 4, 1, 22)),
      ];
      expect(SleepPersonalRecords.longestStreak(nights), 3);
    });

    test('preserves all-time bests if their source night is later removed', () {
      const previous = SleepPersonalRecords(
        longestSleepMinutes: 500,
        longestSleepSessionId: 'old',
        bestEfficiencyPercent: 96,
        bestEfficiencySessionId: 'old',
        shortestLatencyMinutes: 3,
        shortestLatencySessionId: 'old',
        longestStreakDays: 12,
      );
      const current = SleepPersonalRecords(longestStreakDays: 4);
      final merged = current.preserveBest(previous);

      expect(merged.longestSleepMinutes, 500);
      expect(merged.bestEfficiencyPercent, 96);
      expect(merged.shortestLatencyMinutes, 3);
      expect(merged.longestStreakDays, 12);
    });

    test('keeps dated history for the four approved record types', () {
      final previous = SleepPersonalRecords(
        longestSleepMinutes: 480,
        longestSleepSessionId: 'sleep-old',
        longestSleepAt: DateTime(2026, 11, 1),
        bestEfficiencyPercent: 90,
        bestEfficiencySessionId: 'eff-old',
        bestEfficiencyAt: DateTime(2026, 11, 2),
        bestSleepScore: 88,
        bestSleepScoreSessionId: 'score-old',
        bestSleepScoreAt: DateTime(2026, 11, 3),
        fewestAwakenings: 4,
        fewestAwakeningsSessionId: 'awake-old',
        fewestAwakeningsAt: DateTime(2026, 11, 4),
      );
      final current = SleepPersonalRecords(
        longestSleepMinutes: 510,
        longestSleepSessionId: 'sleep-new',
        longestSleepAt: DateTime(2026, 11, 20),
        bestEfficiencyPercent: 94,
        bestEfficiencySessionId: 'eff-new',
        bestEfficiencyAt: DateTime(2026, 11, 21),
        bestSleepScore: 96,
        bestSleepScoreSessionId: 'score-new',
        bestSleepScoreAt: DateTime(2026, 11, 22),
        fewestAwakenings: 1,
        fewestAwakeningsSessionId: 'awake-new',
        fewestAwakeningsAt: DateTime(2026, 11, 24),
      );

      final baseline = SleepPersonalRecordHistory.fromRecords(previous);
      final improvements = SleepPersonalRecordHistory.improvements(
        current: current,
        previous: previous,
      );
      final history = SleepPersonalRecordHistory.merge(baseline, improvements);
      final restored = SleepPersonalRecordHistory.decode(
        SleepPersonalRecordHistory.encode(history),
      );
      final best = SleepPersonalRecordHistory.bestRecords(restored)!;

      expect(baseline, hasLength(4));
      expect(improvements, hasLength(4));
      expect(restored, hasLength(8));
      expect(best.longestSleepMinutes, 510);
      expect(best.bestSleepScore, 96);
      expect(best.bestEfficiencyPercent, 94);
      expect(best.fewestAwakenings, 1);
      expect(best.fewestAwakeningsAt, DateTime(2026, 11, 24));
    });

    test('does not invent history dates when a record has no confirmed date', () {
      const records = SleepPersonalRecords(
        longestSleepMinutes: 480,
        bestSleepScore: 90,
        bestEfficiencyPercent: 90,
        fewestAwakenings: 2,
      );

      expect(SleepPersonalRecordHistory.fromRecords(records), isEmpty);
    });

    test('uses the source session in record-history event identity', () {
      final achievedAt = DateTime.utc(2026, 11, 20, 22);
      final firstId = SleepPersonalRecordEvent.createId(
        metric: 'longestSleepMinutes',
        value: 480,
        achievedAt: achievedAt,
        sessionId: 'night-1',
      );
      final secondId = SleepPersonalRecordEvent.createId(
        metric: 'longestSleepMinutes',
        value: 480,
        achievedAt: achievedAt,
        sessionId: 'night-2',
      );

      expect(firstId, isNot(secondId));

      final first = SleepPersonalRecordEvent(
        id: firstId,
        metric: 'longestSleepMinutes',
        value: 480,
        achievedAt: achievedAt,
        sessionId: 'night-1',
      );
      final second = SleepPersonalRecordEvent(
        id: secondId,
        metric: 'longestSleepMinutes',
        value: 480,
        achievedAt: achievedAt,
        sessionId: 'night-2',
      );
      expect(SleepPersonalRecordHistory.merge([first], [second]), hasLength(2));
    });

    test('recovers source dates when equal restored bests lack metadata', () {
      const previous = SleepPersonalRecords(
        longestSleepMinutes: 500,
        bestSleepScore: 96,
        bestEfficiencyPercent: 96,
        fewestAwakenings: 1,
      );
      final current = SleepPersonalRecords(
        longestSleepMinutes: 500,
        longestSleepSessionId: 'sleep-source',
        longestSleepAt: DateTime(2026, 11, 20),
        bestEfficiencyPercent: 96,
        bestEfficiencySessionId: 'efficiency-source',
        bestEfficiencyAt: DateTime(2026, 11, 21),
        bestSleepScore: 96,
        bestSleepScoreSessionId: 'score-source',
        bestSleepScoreAt: DateTime(2026, 11, 22),
        fewestAwakenings: 1,
        fewestAwakeningsSessionId: 'awake-source',
        fewestAwakeningsAt: DateTime(2026, 11, 24),
      );

      final merged = current.preserveBest(previous);

      expect(merged.longestSleepAt, DateTime(2026, 11, 20));
      expect(merged.longestSleepSessionId, 'sleep-source');
      expect(merged.bestSleepScoreAt, DateTime(2026, 11, 22));
      expect(merged.bestSleepScoreSessionId, 'score-source');
      expect(merged.bestEfficiencyAt, DateTime(2026, 11, 21));
      expect(merged.bestEfficiencySessionId, 'efficiency-source');
      expect(merged.fewestAwakeningsAt, DateTime(2026, 11, 24));
      expect(merged.fewestAwakeningsSessionId, 'awake-source');
    });

    test('round-trips the version-independent metadata payload', () {
      final original = SleepPersonalRecords(
        longestSleepMinutes: 480,
        longestSleepAt: DateTime.utc(2026, 11, 20),
        bestSleepScore: 91,
        bestSleepScoreAt: DateTime.utc(2026, 11, 21),
        bestEfficiencyPercent: 92.5,
        fewestAwakenings: 1,
        fewestAwakeningsAt: DateTime.utc(2026, 11, 22),
      );
      final restored = SleepPersonalRecords.fromMap(original.toMap());

      expect(restored.longestSleepMinutes, 480);
      expect(restored.bestSleepScore, 91);
      expect(restored.bestEfficiencyPercent, 92.5);
      expect(restored.fewestAwakenings, 1);
    });
  });
}
