import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_record_service.dart';

void main() {
  group('SleepRecordEvent', () {
    test('round-trips a valid persisted event', () {
      final event = SleepRecordEvent(
        type: 'sleep_score',
        sessionId: 'night-1',
        value: 92,
        achievedAt: DateTime.utc(2026, 11, 20, 7),
      );

      final restored = SleepRecordEvent.fromMap(event.toMap());

      expect(restored, isNotNull);
      expect(restored!.type, 'sleep_score');
      expect(restored.sessionId, 'night-1');
      expect(restored.value, 92);
      expect(restored.achievedAt.toUtc(), event.achievedAt);
    });

    test('rejects unknown record types and malformed values', () {
      expect(SleepRecordEvent.fromMap({
        'type': 'unknown',
        'sessionId': 'night-1',
        'value': 3,
        'achievedAt': '2026-11-20T07:00:00Z',
      }), isNull);
      expect(SleepRecordEvent.fromMap({
        'type': 'sleep_score',
        'sessionId': 'night-1',
        'value': double.nan,
        'achievedAt': '2026-11-20T07:00:00Z',
      }), isNull);
    });
  });

  group('SleepRecordService celebration claims', () {
    test('allows only one mounted card to claim the same celebration', () {
      final service = SleepRecordService.instance;
      final event = SleepRecordEvent(
        type: 'sleep_score',
        sessionId: 'claim-test',
        value: 95,
        achievedAt: DateTime.utc(2026, 11, 23),
      );
      final otherEvent = SleepRecordEvent(
        type: 'awakening_count',
        sessionId: 'claim-test-2',
        value: 0,
        achievedAt: DateTime.utc(2026, 11, 23),
      );

      expect(service.tryClaimCelebration(event), isTrue);
      expect(service.tryClaimCelebration(event), isFalse);
      // A second card must not stack a different celebration dialog either.
      expect(service.tryClaimCelebration(otherEvent), isFalse);

      service.releaseCelebration(event);
      expect(service.tryClaimCelebration(otherEvent), isTrue);
      service.releaseCelebration(otherEvent);
    });
  });

  group('SleepRecordState', () {
    test('returns the highest score and the lowest reliable awakening count', () {
      final state = SleepRecordState(history: [
        SleepRecordEvent(
          type: 'sleep_score', sessionId: 'a', value: 81,
          achievedAt: DateTime(2026, 1, 1),
        ),
        SleepRecordEvent(
          type: 'sleep_score', sessionId: 'b', value: 94,
          achievedAt: DateTime(2026, 1, 2),
        ),
        SleepRecordEvent(
          type: 'awakening_count', sessionId: 'a', value: 3,
          achievedAt: DateTime(2026, 1, 1),
        ),
        SleepRecordEvent(
          type: 'awakening_count', sessionId: 'b', value: 1,
          achievedAt: DateTime(2026, 1, 2),
        ),
      ]);

      expect(state.bestSleepScore!.value, 94);
      expect(state.bestSleepScore!.sessionId, 'b');
      expect(state.fewestAwakenings!.value, 1);
      expect(state.fewestAwakenings!.sessionId, 'b');
    });

    test('returns null when a record has no valid history', () {
      final state = SleepRecordState(history: const []);
      expect(state.bestSleepScore, isNull);
      expect(state.fewestAwakenings, isNull);
    });
  });
}
