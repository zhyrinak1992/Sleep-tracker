import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/tag_combination_suggestions.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession _session(String id, DateTime start, {bool completed = true}) => SleepSession(
  id: id,
  startedAt: start,
  endedAt: completed ? start.add(const Duration(hours: 7)) : null,
  source: 'manual',
);

void main() {
  group('TagCombinationSuggestionAnalyzer', () {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 12, 1);

    test('suggests pairs used together across distinct completed nights', () {
      final sessions = [
        for (var i = 0; i < 3; i++) _session('both-$i', start.add(Duration(days: i))),
        _session('one-tag', start.add(const Duration(days: 5))),
        _session('open', start.add(const Duration(days: 6)), completed: false),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 3; i++) 'both-$i': {'caffeine', 'stress'},
        'one-tag': {'caffeine'},
        'open': {'caffeine', 'stress'},
      };

      final suggestions = TagCombinationSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        start: start,
        endExclusive: end,
      );

      expect(suggestions, hasLength(1));
      expect(suggestions.single.tagKeys, ['caffeine', 'stress']);
      expect(suggestions.single.nightCount, 3);
    });

    test('does not count repeated records from the same night or sessions outside period', () {
      final sessions = [
        _session('night-1', start),
        _session('night-2', start.add(const Duration(days: 1))),
        _session('outside', end),
      ];
      final tags = <String, Set<String>>{
        'night-1': {'caffeine', 'stress'},
        'night-2': {'caffeine', 'stress'},
        'outside': {'caffeine', 'stress'},
      };
      final suggestions = TagCombinationSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        start: start,
        endExclusive: end,
      );
      expect(suggestions, isEmpty);
    });

    test('does not repeat saved or dismissed combinations', () {
      final sessions = [
        for (var i = 0; i < 4; i++) _session('night-$i', start.add(Duration(days: i))),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'night-$i': {'caffeine', 'stress'},
      };
      final signature = TagCombinationSuggestionStore.signature(['stress', 'caffeine']);

      final saved = TagCombinationSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        start: start,
        endExclusive: end,
        existingCombinations: const [['caffeine', 'stress']],
      );
      final dismissed = TagCombinationSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        start: start,
        endExclusive: end,
        dismissedSignatures: {signature},
      );

      expect(saved, isEmpty);
      expect(dismissed, isEmpty);
    });

    test('sorts by number of nights and respects result limit', () {
      final sessions = [
        for (var i = 0; i < 5; i++) _session('a-$i', start.add(Duration(days: i))),
        for (var i = 0; i < 3; i++) _session('b-$i', start.add(Duration(days: i + 7))),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 5; i++) 'a-$i': {'caffeine', 'stress'},
        for (var i = 0; i < 3; i++) 'b-$i': {'activity', 'nutrition'},
      };
      final suggestions = TagCombinationSuggestionAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: tags,
        start: start,
        endExclusive: end,
        limit: 1,
      );
      expect(suggestions, hasLength(1));
      expect(suggestions.single.tagKeys, ['caffeine', 'stress']);
      expect(suggestions.single.nightCount, 5);
    });
  });

  test('TagCombinationSuggestionStore remembers dismissed combinations order-independently', () async {
    final values = <String, String>{};
    final store = TagCombinationSuggestionStore(
      (key) async => values[key],
      (key, value) async => values[key] = value,
    );
    await store.dismiss(['stress', 'caffeine']);
    final dismissed = await store.loadDismissed();
    expect(dismissed, contains(TagCombinationSuggestionStore.signature(['caffeine', 'stress'])));
  });
}
