import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/comparison_suggestion_store.dart';
import 'package:sleep_tracker/features/home/comparison_suggestion_analyzer.dart';
import 'package:sleep_tracker/models/sleep_session.dart';
import 'package:sleep_tracker/features/analysis/tag_sleep_comparison.dart';

ComparisonSuggestionCandidate candidate({
  int withNights = 5,
  int withoutNights = 8,
  double difference = 1.5,
  String fingerprint = '5|8|4.5|3.0|1.5',
  double priority = 3,
}) => ComparisonSuggestionCandidate(
  signature: '["stress","caffeine"]',
  tagKeys: const ['stress', 'caffeine'],
  metric: TagSleepMetric.morningRating,
  start: DateTime(2026, 8, 1),
  endExclusive: DateTime(2026, 11, 1),
  withNights: withNights,
  withoutNights: withoutNights,
  withAverage: 4.5,
  withoutAverage: 4.5 - difference,
  difference: difference,
  threshold: 0.5,
  priority: priority,
  fingerprint: fingerprint,
  withSessionIds: List.generate(withNights, (i) => 'with-$i'),
  withoutSessionIds: List.generate(withoutNights, (i) => 'without-$i'),
);

void main() {
  group('ComparisonSuggestionAnalyzer', () {
    test('proposes only when both groups have enough nights and the difference passes its metric threshold', () {
      final now = DateTime(2026, 11, 23, 12);
      final sessions = <SleepSession>[];
      final tags = <String, Set<String>>{};
      for (var i = 0; i < 8; i++) {
        final id = 'night-$i';
        final date = now.subtract(Duration(days: i + 1));
        sessions.add(SleepSession(
          id: id,
          startedAt: date,
          endedAt: date.add(const Duration(hours: 8)),
          source: 'manual',
          morningRating: i < 4 ? 5 : 3,
        ));
        if (i < 4) tags[id] = {'stress', 'caffeine'};
      }

      final result = ComparisonSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        awakeningCountsBySession: const {},
        now: now,
      );

      expect(result, hasLength(1));
      expect(result.single.tagKeys, ['caffeine', 'stress']);
      expect(result.single.metric, TagSleepMetric.morningRating);
      expect(result.single.withNights, 4);
      expect(result.single.withoutNights, 4);
      expect(result.single.difference, 2);
    });

    test('does not propose when one comparison group is below minimum sample size', () {
      final now = DateTime(2026, 11, 23, 12);
      final sessions = List.generate(7, (i) {
        final date = now.subtract(Duration(days: i + 1));
        return SleepSession(
          id: 'night-$i',
          startedAt: date,
          endedAt: date.add(const Duration(hours: 8)),
          source: 'manual',
          morningRating: i < 3 ? 5 : 3,
        );
      });
      final tags = {
        for (var i = 0; i < 3; i++) 'night-$i': <String>{'stress', 'caffeine'},
      };
      final result = ComparisonSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        awakeningCountsBySession: const {},
        now: now,
      );
      expect(result, isEmpty);
    });

    test('does not propose a category combination already saved as a template', () {
      final now = DateTime(2026, 11, 23, 12);
      final sessions = List.generate(8, (i) {
        final date = now.subtract(Duration(days: i + 1));
        return SleepSession(
          id: 'night-$i',
          startedAt: date,
          endedAt: date.add(const Duration(hours: 8)),
          source: 'manual',
          morningRating: i < 4 ? 5 : 3,
        );
      });
      final tags = {
        for (var i = 0; i < 4; i++) 'night-$i': <String>{'stress', 'caffeine'},
      };
      final result = ComparisonSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        awakeningCountsBySession: const {},
        now: now,
        existingCombinations: const [['stress', 'caffeine']],
      );
      expect(result, isEmpty);
    });
  });

  group('ComparisonSuggestionStore', () {
    late Map<String, String> metadata;
    late ComparisonSuggestionStore store;

    setUp(() {
      metadata = {};
      store = ComparisonSuggestionStore(
        (key) async => metadata[key],
        (key, value) async => metadata[key] = value,
      );
    });

    test('keeps only one pending suggestion and respects frequency interval', () async {
      final now = DateTime(2026, 11, 23, 19);
      final first = await store.currentOrCreate(
        candidates: [candidate(priority: 4), candidate(fingerprint: 'second', priority: 2)],
        now: now,
      );
      expect(first, isNotNull);
      expect(first!.status, ComparisonSuggestionStatus.pending);

      final samePending = await store.currentOrCreate(
        candidates: [candidate(fingerprint: 'changed')],
        now: now.add(const Duration(hours: 1)),
      );
      expect(samePending?.id, first.id);

      await store.updateStatus(
        id: first.id,
        status: ComparisonSuggestionStatus.opened,
        now: now.add(const Duration(hours: 2)),
      );
      final blocked = await store.currentOrCreate(
        candidates: [candidate(fingerprint: 'changed')],
        now: now.add(const Duration(days: 2)),
      );
      expect(blocked, isNull);
    });

    test('allows the same category pair again only after sufficient new observations', () async {
      final now = DateTime(2026, 11, 1, 10);
      final first = await store.currentOrCreate(
        candidates: [candidate()],
        now: now,
      );
      await store.updateStatus(
        id: first!.id,
        status: ComparisonSuggestionStatus.rejected,
        now: now,
      );

      final tooSoon = await store.currentOrCreate(
        candidates: [candidate(withNights: 6, fingerprint: '6|8|4.5|3.0|1.5')],
        now: now.add(const Duration(days: 15)),
      );
      expect(tooSoon, isNull);

      final enoughNewData = await store.currentOrCreate(
        candidates: [candidate(withNights: 8, fingerprint: '8|8|4.5|3.0|1.5')],
        now: now.add(const Duration(days: 16)),
      );
      expect(enoughNewData, isNotNull);
      expect(enoughNewData?.status, ComparisonSuggestionStatus.pending);
    });

    test('automatically marks an unattended card as not viewed next morning', () async {
      final createdAt = DateTime(2026, 11, 23, 22);
      final record = await store.currentOrCreate(
        candidates: [candidate()],
        now: createdAt,
      );
      expect(record?.expiresAt, DateTime(2026, 11, 24, 8));

      final nextMorning = await store.currentOrCreate(
        candidates: [candidate()],
        now: DateTime(2026, 11, 24, 9),
      );
      expect(nextMorning, isNull);
      final history = await store.loadHistory();
      expect(history, hasLength(1));
      expect(history.single.status, ComparisonSuggestionStatus.notViewed);
      expect(history.single.statusEvents.last['status'], 'notViewed');
    });

    test('records status transitions and frequency choices', () async {
      expect(ComparisonSuggestionFrequency.rare.interval, const Duration(days: 30));
      expect(ComparisonSuggestionFrequency.moderate.interval, const Duration(days: 14));
      expect(ComparisonSuggestionFrequency.often.interval, const Duration(days: 7));

      final now = DateTime(2026, 11, 23, 10);
      final record = await store.currentOrCreate(candidates: [candidate()], now: now);
      await store.updateStatus(
        id: record!.id,
        status: ComparisonSuggestionStatus.saved,
        now: now.add(const Duration(minutes: 1)),
      );
      final history = await store.loadHistory();
      expect(history.single.status, ComparisonSuggestionStatus.saved);
      expect(history.single.statusEvents, hasLength(2));
    });
  });
}
