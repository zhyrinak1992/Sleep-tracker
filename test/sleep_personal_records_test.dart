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
    test('calculates duration, covered efficiency and confirmed latency', () {
      final start = DateTime(2026, 11, 20, 22);
      final night = session(
        'night-1',
        start,
        end: start.add(const Duration(hours: 8)),
        actualStart: start.add(const Duration(minutes: 20)),
      );
      final records = SleepPersonalRecords.calculate(
        sessions: [night],
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
      expect(records.shortestLatencyMinutes, 20);
      expect(records.longestSleepSessionId, 'night-1');
    });

    test('does not invent efficiency or latency when coverage/boundaries are absent', () {
      final start = DateTime(2026, 11, 20, 22);
      final records = SleepPersonalRecords.calculate(
        sessions: [session('night-1', start)],
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

    test('round-trips the version-independent metadata payload', () {
      final original = SleepPersonalRecords(
        longestSleepMinutes: 480,
        longestSleepAt: DateTime.utc(2026, 11, 20),
        bestEfficiencyPercent: 92.5,
        shortestLatencyMinutes: 7,
        longestStreakDays: 5,
      );
      final restored = SleepPersonalRecords.fromMap(original.toMap());

      expect(restored.longestSleepMinutes, 480);
      expect(restored.bestEfficiencyPercent, 92.5);
      expect(restored.shortestLatencyMinutes, 7);
      expect(restored.longestStreakDays, 5);
    });
  });
}
