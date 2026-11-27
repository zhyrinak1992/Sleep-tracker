import 'dart:convert';

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
      expect(SleepRecordEvent.fromMap({
        'type': 'sleep_score',
        'sessionId': 'night-1',
        'value': 101,
        'achievedAt': '2026-11-20T07:00:00Z',
      }), isNull);
      expect(SleepRecordEvent.fromMap({
        'type': 'awakening_count',
        'sessionId': 'night-1',
        'value': 1.5,
        'achievedAt': '2026-11-20T07:00:00Z',
      }), isNull);
      expect(SleepRecordEvent.fromMap({
        'type': 'awakening_count',
        'sessionId': 'night-1',
        'value': -1,
        'achievedAt': '2026-11-20T07:00:00Z',
      }), isNull);
      final normalized = SleepRecordEvent.fromMap({
        'type': 'sleep_score',
        'sessionId': 'night-1',
        'value': 95.0,
        'achievedAt': '2026-11-20T07:00:00Z',
      });
      expect(normalized!.value, 95);
    });

    test('keeps valid persisted history unchanged', () {
      final event = SleepRecordEvent(
        type: 'sleep_score',
        sessionId: 'night-valid',
        value: 91,
        achievedAt: DateTime.utc(2026, 11, 20, 7),
      ).toMap();
      final decoded = SleepRecordService.decodePersistedHistory(
        jsonEncode([event]),
      );

      expect(decoded.events, hasLength(1));
      expect(decoded.needsRewrite, isFalse);
    });

    test(
      'repairs partially invalid history even when valid count is unchanged',
      () {
        final valid = SleepRecordEvent(
          type: 'sleep_score',
          sessionId: 'night-1',
          value: 92,
          achievedAt: DateTime.utc(2026, 11, 20, 7),
        ).toMap();
        final decoded = SleepRecordService.decodePersistedHistory(
          '[${jsonEncode(valid)},{"type":"unknown"}]',
        );

        expect(decoded.events, hasLength(1));
        expect(decoded.events.single.sessionId, 'night-1');
        expect(decoded.needsRewrite, isTrue);
      },
    );

    test('marks empty first-run history for persistence', () {
      final decoded = SleepRecordService.decodePersistedHistory(null);

      expect(decoded.events, isEmpty);
      expect(decoded.needsRewrite, isTrue);
    });

    test('repairs duplicate records and malformed JSON', () {
      final event = SleepRecordEvent(
        type: 'awakening_count',
        sessionId: 'night-2',
        value: 1,
        achievedAt: DateTime.utc(2026, 11, 21, 7),
      ).toMap();
      final duplicated = SleepRecordService.decodePersistedHistory(
        '[${jsonEncode(event)},${jsonEncode(event)}]',
      );
      final malformed = SleepRecordService.decodePersistedHistory('{broken');

      expect(duplicated.events, hasLength(1));
      expect(duplicated.needsRewrite, isTrue);
      expect(malformed.events, isEmpty);
      expect(malformed.needsRewrite, isTrue);
    });
  });

  group('Sleep record history rebuild', () {
    SleepRecordEvent score(String id, int value, int day) => SleepRecordEvent(
      type: 'sleep_score',
      sessionId: id,
      value: value,
      achievedAt: DateTime.utc(2026, 11, day, 7),
    );

    SleepRecordEvent awakenings(String id, int value, int day) =>
        SleepRecordEvent(
          type: 'awakening_count',
          sessionId: id,
          value: value,
          achievedAt: DateTime.utc(2026, 11, day, 7),
        );

    test('rebuilds only current record-setting sessions', () {
      final history = buildSleepRecordHistory([
        score('night-1', 80, 20),
        score('night-2', 96, 21),
        score('night-3', 90, 22),
        awakenings('night-1', 4, 20),
        awakenings('night-2', 2, 21),
        awakenings('night-3', 3, 22),
      ]);

      expect(
        history.where((event) => event.type == 'sleep_score')
            .map((event) => event.sessionId),
        ['night-1', 'night-2'],
      );
      expect(
        history.where((event) => event.type == 'awakening_count')
            .map((event) => event.sessionId),
        ['night-1', 'night-2'],
      );
    });

    test('corrected and deleted sessions do not leave stale personal records', () {
      final corrected = buildSleepRecordHistory([
        score('night-1', 80, 20),
        score('night-2', 85, 21), // Was previously 96.
      ]);
      final afterDeletion = buildSleepRecordHistory([
        score('night-1', 80, 20),
      ]);

      expect(corrected.last.value, 85);
      expect(corrected.last.sessionId, 'night-2');
      expect(afterDeletion, hasLength(1));
      expect(afterDeletion.single.sessionId, 'night-1');
      expect(afterDeletion.single.value, 80);
    });

    test('does not celebrate corrected or promoted historical records', () {
      final previous = [score('night-newest', 96, 22)];
      final corrected = [score('night-newest', 90, 22)];
      final promotedOlder = [score('night-older', 85, 20)];

      expect(findNewSleepRecordEvents(
        previousHistory: previous,
        currentHistory: corrected,
        celebratedKeys: const {},
        isFirstInitialization: false,
      ), isEmpty);
      expect(findNewSleepRecordEvents(
        previousHistory: previous,
        currentHistory: promotedOlder,
        celebratedKeys: const {},
        isFirstInitialization: false,
      ), isEmpty);
    });

    test('celebrates a genuinely newer record and recovers pending events', () {
      final previous = [score('night-old', 90, 20)];
      final newRecord = score('night-new', 95, 23);
      final pending = score('night-pending', 97, 24);

      expect(findNewSleepRecordEvents(
        previousHistory: previous,
        currentHistory: [previous.single, newRecord],
        celebratedKeys: {'sleep_score|night-old|90'},
        isFirstInitialization: false,
      ), [newRecord]);
      expect(findNewSleepRecordEvents(
        previousHistory: [pending],
        currentHistory: [pending],
        celebratedKeys: const {},
        isFirstInitialization: false,
      ), [pending]);
      expect(findNewSleepRecordEvents(
        previousHistory: [pending],
        currentHistory: [pending],
        celebratedKeys: {'sleep_score|night-pending|97'},
        isFirstInitialization: false,
      ), isEmpty);
    });

    test('restores only remaining events when the app closes mid-queue', () {
      final alreadyCelebrated = score('night-a', 90, 21);
      final pendingAwakenings = awakenings('night-a', 2, 21);
      final pendingScore = score('night-b', 95, 22);
      final persistedHistory = [
        alreadyCelebrated,
        pendingAwakenings,
        pendingScore,
      ];

      final restoredQueue = findNewSleepRecordEvents(
        previousHistory: persistedHistory,
        currentHistory: persistedHistory,
        celebratedKeys: {'sleep_score|night-a|90'},
        isFirstInitialization: false,
      );

      expect(restoredQueue, [pendingAwakenings, pendingScore]);
    });

    test('celebrates record improvements when timestamps are identical', () {
      final previousScore = score('night-a', 90, 23);
      final improvedScore = score('night-b', 95, 23);
      final previousAwakenings = awakenings('night-a', 3, 23);
      final improvedAwakenings = awakenings('night-b', 1, 23);

      final newRecords = findNewSleepRecordEvents(
        previousHistory: [previousScore, previousAwakenings],
        currentHistory: [
          previousScore,
          improvedScore,
          previousAwakenings,
          improvedAwakenings,
        ],
        celebratedKeys: {
          'sleep_score|night-a|90',
          'awakening_count|night-a|3',
        },
        isFirstInitialization: false,
      );

      expect(newRecords, [improvedScore, improvedAwakenings]);
    });

    test('does not celebrate historical baseline on first initialization', () {
      final oldNight = score('night-old', 99, 10);
      expect(findNewSleepRecordEvents(
        previousHistory: const [],
        currentHistory: [oldNight],
        celebratedKeys: const {},
        isFirstInitialization: true,
      ), isEmpty);
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
