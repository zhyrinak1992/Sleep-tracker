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
  source: 'apple_health:Apple Watch',
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
        tagKeys: {'caffeine'},
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

    test('requires every selected tag to be present for a combined comparison', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          _session(id: 'both-$i', start: start.add(Duration(days: i)), durationMinutes: 450),
        for (var i = 0; i < 4; i++)
          _session(id: 'coffee-only-$i', start: start.add(Duration(days: i + 5)), durationMinutes: 420),
        for (var i = 0; i < 4; i++)
          _session(id: 'neither-$i', start: start.add(Duration(days: i + 10)), durationMinutes: 390),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'both-$i': {'caffeine', 'stress'},
        for (var i = 0; i < 4; i++) 'coffee-only-$i': {'caffeine'},
      };

      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKeys: {'caffeine', 'stress'},
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.sleepDuration,
      );

      expect(result.withTag.nights, 4);
      expect(result.withoutTag.nights, 8);
      expect(result.withTag.average, 450);
      expect(result.withoutTag.average, 405);
      expect(result.difference, 45);
    });

    test('does not treat manual button times as actual sleep duration', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          _session(id: 'tag-$i', start: start.add(Duration(days: i))),
        for (var i = 0; i < 4; i++)
          _session(id: 'plain-$i', start: start.add(Duration(days: i + 5))),
      ].map((session) => SleepSession(
        id: session.id,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
        source: 'manual',
      )).toList();
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'tag-$i': {'caffeine'},
      };
      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKeys: {'caffeine'},
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.sleepDuration,
      );
      expect(result.withTag.nights, 0);
      expect(result.withoutTag.nights, 0);
      expect(result.difference, isNull);
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
        tagKeys: {'stress'},
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
        tagKeys: {'stress'},
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
        tagKeys: {'caffeine'},
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.sleepDuration,
      );
      expect(result.withTag.nights, 4);
      expect(result.withoutTag.nights, 0);
      expect(result.isSufficient, isFalse);
    });
  });

    test('compares only nights with registered awake-stage intervals', () {
      final start = DateTime(2026, 11, 1);
      final end = DateTime(2026, 12, 1);
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          _session(id: 'tag-awake-$i', start: start.add(Duration(days: i))),
        for (var i = 0; i < 4; i++)
          _session(id: 'plain-awake-$i', start: start.add(Duration(days: i + 5))),
        _session(id: 'missing-awake', start: start.add(const Duration(days: 10))),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'tag-awake-$i': {'stress'},
      };
      final counts = <String, int>{
        for (var i = 0; i < 4; i++) 'tag-awake-$i': i + 3,
        for (var i = 0; i < 4; i++) 'plain-awake-$i': i + 1,
      };

      final result = TagSleepComparison.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKeys: {'stress'},
        start: start,
        endExclusive: end,
        metric: TagSleepMetric.awakeningCount,
        awakeningCountsBySession: counts,
      );

      expect(result.isSufficient, isTrue);
      expect(result.withTag.nights, 4);
      expect(result.withoutTag.nights, 4);
      expect(result.withTag.average, 4.5);
      expect(result.withoutTag.average, 2.5);
      expect(result.difference, 2);
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
        tagKeys: ['caffeine'],
        metric: TagSleepMetric.sleepDuration,
      );

      await store.save([template]);
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, template.id);
      expect(loaded.single.name, template.name);
      expect(loaded.single.tagKeys, template.tagKeys);
      expect(loaded.single.metric, template.metric);
      expect(metadata.keys, [TagComparisonTemplateStore.metadataKey]);
    });

    test('loads legacy single-tag templates and upgrades them to tagKeys on save', () async {
      final metadata = <String, String>{
        TagComparisonTemplateStore.metadataKey:
            '[{"id":"legacy-1","name":"Кофе","tagKey":"caffeine","metric":"sleepDuration"}]',
      };
      final store = TagComparisonTemplateStore(
        (key) async => metadata[key],
        (key, value) async => metadata[key] = value,
      );

      final loaded = await store.load();
      expect(loaded.single.tagKeys, ['caffeine']);
      await store.save(loaded);
      expect(metadata[TagComparisonTemplateStore.metadataKey], contains('"tagKeys":["caffeine"]'));
      expect(metadata[TagComparisonTemplateStore.metadataKey], isNot(contains('"tagKey"')));
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
