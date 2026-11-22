import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/tag_sleep_comparison.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession _session({
  required String id,
  required DateTime start,
  int durationMinutes = 420,
  int? rating = 4,
}) => SleepSession(
  id: id,
  startedAt: start,
  endedAt: start.add(Duration(minutes: durationMinutes)),
  source: 'health',
  morningRating: rating,
  createdAt: start,
  updatedAt: start,
);

void main() {
  group('TagSleepComparison', () {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 12, 1);

    test('compares only completed nights with available metric values', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          _session(id: 'tag-$i', start: start.add(Duration(days: i)), durationMinutes: 450),
        for (var i = 0; i < 4; i++)
          _session(id: 'plain-$i', start: start.add(Duration(days: i + 5)), durationMinutes: 390),
        SleepSession(id: 'open', startedAt: start, source: 'manual'),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'tag-$i': {'caffeine'},
      };

      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKey: 'caffeine',
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.sleepDuration,
      );

      expect(result.isSufficient, isTrue);
      expect(result.withTag.nights, 4);
      expect(result.withoutTag.nights, 4);
      expect(result.withTag.average, 450);
      expect(result.withoutTag.average, 390);
      expect(result.difference, 60);
    });

    test('does not calculate a difference when either group is too small', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 3; i++)
          _session(id: 'tag-$i', start: start.add(Duration(days: i))),
        for (var i = 0; i < 6; i++)
          _session(id: 'plain-$i', start: start.add(Duration(days: i + 4))),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 3; i++) 'tag-$i': {'stress'},
      };

      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKey: 'stress',
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.sleepDuration,
      );

      expect(result.isSufficient, isFalse);
      expect(result.withTag.nights, 3);
      expect(result.withoutTag.nights, 6);
      expect(result.difference, isNull);
    });

    test('uses only nights with a saved morning rating for rating comparisons', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          _session(id: 'tag-$i', start: start.add(Duration(days: i)), rating: 3),
        for (var i = 0; i < 4; i++)
          _session(id: 'plain-$i', start: start.add(Duration(days: i + 5)), rating: 5),
        _session(id: 'untagged-no-rating', start: start.add(const Duration(days: 12)), rating: null),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'tag-$i': {'stress'},
      };

      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKey: 'stress',
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.morningRating,
      );

      expect(result.isSufficient, isTrue);
      expect(result.withTag.average, 3);
      expect(result.withoutTag.average, 5);
      expect(result.withoutTag.nights, 4);
      expect(result.difference, -2);
    });

    test('excludes sessions outside the selected period', () {
      final sessions = [
        for (var i = 0; i < 4; i++)
          _session(id: 'tag-$i', start: start.add(Duration(days: i))),
        for (var i = 0; i < 4; i++)
          _session(id: 'plain-$i', start: end.add(Duration(days: i))),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'tag-$i': {'caffeine'},
      };
      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKey: 'caffeine',
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.sleepDuration,
      );
      expect(result.withTag.nights, 4);
      expect(result.withoutTag.nights, 0);
      expect(result.isSufficient, isFalse);
    });
  });

  group('TagComparisonTemplateStore', () {
    test('saves and reloads comparison settings', () async {
      final metadata = <String, String>{};
      final store = TagComparisonTemplateStore(
        (key) async => metadata[key],
        (key, value) async => metadata[key] = value,
      );
      const template = TagComparisonTemplate(
        id: 'template-1',
        name: 'Кофе и сон',
        tagKey: 'caffeine',
        metric: TagSleepMetric.sleepDuration,
      );

      await store.save([template]);
      final loaded = await store.load();

      expect(loaded, [template]);
      expect(metadata.keys, [TagComparisonTemplateStore.metadataKey]);
    });

    test('rejects malformed stored template data without silently replacing it', () async {
      const broken = '{"not":"a list"}';
      final store = TagComparisonTemplateStore(
        (_) async => broken,
        (_, __) async {},
      );
      await expectLater(store.load(), throwsA(isA<FormatException>()));
    });
  });
}
