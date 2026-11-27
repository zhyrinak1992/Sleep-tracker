import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/tag_insight_preferences.dart';

void main() {
  late Map<String, String> metadata;
  late TagInsightPreferenceStore store;
  setUp(() {
    metadata = {};
    store = TagInsightPreferenceStore(
      (key) async => metadata[key],
      (key, value) async => metadata[key] = value,
    );
  });

  test('hide and pin are stored independently and survive reload', () async {
    final id = TagInsightPreferenceStore.identity('coffee', 'duration');
    await store.pin(tagKey: 'coffee', metricKey: 'duration', tagLabel: 'Кофе', metricLabel: 'Продолжительность сна');
    await store.hide(tagKey: 'coffee', metricKey: 'duration', tagLabel: 'Кофе', metricLabel: 'Продолжительность сна');
    final loaded = await store.load();
    expect(loaded.isHidden(id), isTrue);
    expect(loaded.isPinned(id), isTrue);
    expect(loaded.hidden[id]?.tagLabel, 'Кофе');
  });

  test('restoring a hidden insight preserves its pinned position', () async {
    final id = TagInsightPreferenceStore.identity('stress', 'score');
    await store.pin(tagKey: 'stress', metricKey: 'score', tagLabel: 'Стресс', metricLabel: 'Оценка сна');
    await store.hide(tagKey: 'stress', metricKey: 'score', tagLabel: 'Стресс', metricLabel: 'Оценка сна');
    final restored = await store.restore(id);
    expect(restored.isHidden(id), isFalse);
    expect(restored.isPinned(id), isTrue);
  });

  test('pinned order is stable and duplicate pin actions do not reorder', () async {
    await store.pin(tagKey: 'coffee', metricKey: 'duration', tagLabel: 'Кофе', metricLabel: 'Сон');
    await store.pin(tagKey: 'stress', metricKey: 'score', tagLabel: 'Стресс', metricLabel: 'Оценка');
    final before = await store.load();
    await store.pin(tagKey: 'coffee', metricKey: 'duration', tagLabel: 'Кофе', metricLabel: 'Сон');
    final after = await store.load();
    expect(after.pinned, before.pinned);
    expect(after.pinned, [
      TagInsightPreferenceStore.identity('coffee', 'duration'),
      TagInsightPreferenceStore.identity('stress', 'score'),
    ]);
  });

  test('unpinning does not remove hidden state', () async {
    final id = TagInsightPreferenceStore.identity('late_meal', 'efficiency');
    await store.pin(tagKey: 'late_meal', metricKey: 'efficiency', tagLabel: 'Поздний ужин', metricLabel: 'Эффективность');
    await store.hide(tagKey: 'late_meal', metricKey: 'efficiency', tagLabel: 'Поздний ужин', metricLabel: 'Эффективность');
    final updated = await store.unpin(tagKey: 'late_meal', metricKey: 'efficiency');
    expect(updated.isHidden(id), isTrue);
    expect(updated.isPinned(id), isFalse);
  });

  test('corrupted preference metadata is not silently overwritten', () async {
    metadata[TagInsightPreferenceStore.metadataKey] = '{broken';
    await expectLater(store.load(), throwsFormatException);
    expect(metadata[TagInsightPreferenceStore.metadataKey], '{broken');
  });

  test('rejects malformed pinned identities without rewriting metadata', () async {
    metadata[TagInsightPreferenceStore.metadataKey] =
        '{"schemaVersion":1,"hidden":{},"pinned":["not-json"]}';
    await expectLater(store.load(), throwsFormatException);
    expect(metadata[TagInsightPreferenceStore.metadataKey],
        '{"schemaVersion":1,"hidden":{},"pinned":["not-json"]}');
  });
}