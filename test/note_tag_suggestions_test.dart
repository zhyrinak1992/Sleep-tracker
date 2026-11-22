import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/notes/note_tag_suggestions.dart';
import 'package:sleep_tracker/models/sleep_note.dart';
import 'package:sleep_tracker/models/sleep_tag.dart';

SleepNote _note(String id, String sessionId, String text) => SleepNote(
  id: id,
  sessionId: sessionId,
  text: text,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  sessionStartedAt: DateTime(2026, 11, 1),
);

void main() {
  group('NoteTagSuggestionAnalyzer', () {
    test('suggests repeated meaningful phrases across distinct nights', () {
      final notes = [
        _note('1', 'night-1', 'Вечером была головная боль после работы.'),
        _note('2', 'night-2', 'Снова головная боль вечером.'),
        _note('3', 'night-3', 'Головная боль мешала уснуть.'),
        _note('4', 'night-3', 'Ещё одна заметка: головная боль.'),
      ];

      final suggestions = NoteTagSuggestionAnalyzer.analyze(
        notes: notes,
        existingTags: SleepTag.catalog,
      );

      final phrase = suggestions.where((item) => item.phrase == 'головная боль');
      expect(phrase, hasLength(1));
      expect(phrase.single.nightCount, 3);
    });

    test('does not count repeated notes from one night as separate evidence', () {
      final notes = [
        _note('1', 'night-1', 'головная боль'),
        _note('2', 'night-1', 'головная боль'),
        _note('3', 'night-1', 'головная боль'),
      ];
      final suggestions = NoteTagSuggestionAnalyzer.analyze(
        notes: notes,
        existingTags: SleepTag.catalog,
      );
      expect(suggestions, isEmpty);
    });

    test('does not suggest existing or dismissed categories', () {
      final notes = [
        _note('1', 'night-1', 'Кофеин и поздний ужин'),
        _note('2', 'night-2', 'Кофеин снова, поздний ужин'),
        _note('3', 'night-3', 'Поздний ужин и кофеин'),
      ];
      final suggestions = NoteTagSuggestionAnalyzer.analyze(
        notes: notes,
        existingTags: [
          ...SleepTag.catalog,
          const SleepTag('custom-coffee', 'кофеин', 'custom'),
        ],
        dismissedPhrases: {'поздний ужин'},
      );
      expect(suggestions.any((item) => item.phrase == 'кофеин'), isFalse);
      expect(suggestions.any((item) => item.phrase == 'поздний ужин'), isFalse);
    });

    test('ignores common filler words', () {
      final notes = [
        _note('1', 'night-1', 'Сегодня было очень хорошо'),
        _note('2', 'night-2', 'Сегодня было очень хорошо'),
        _note('3', 'night-3', 'Сегодня было очень хорошо'),
      ];
      final suggestions = NoteTagSuggestionAnalyzer.analyze(
        notes: notes,
        existingTags: SleepTag.catalog,
      );
      expect(suggestions, isEmpty);
    });
  });

  group('CustomSleepTagStore', () {
    test('persists a user-confirmed category without changing built-in tags', () async {
      final values = <String, String>{};
      final store = CustomSleepTagStore(
        (key) async => values[key],
        (key, value) async => values[key] = value,
      );

      final saved = await store.add('Головная боль');
      final loaded = await store.load();

      expect(saved, hasLength(1));
      expect(loaded, hasLength(1));
      expect(loaded.single.label, 'Головная боль');
      expect(loaded.single.description, 'Пользовательская категория');
      expect(loaded.single.key, startsWith('custom_'));
      expect(SleepTag.catalog.any((tag) => tag.label == 'Головная боль'), isFalse);
    });

    test('rejects duplicate category names', () async {
      final values = <String, String>{};
      final store = CustomSleepTagStore(
        (key) async => values[key],
        (key, value) async => values[key] = value,
      );
      await store.add('Головная боль');
      await expectLater(store.add('головная боль'), throwsA(isA<StateError>()));
    });
  });

  group('DismissedNoteTagSuggestionStore', () {
    test('remembers dismissed suggestions', () async {
      final values = <String, String>{};
      final store = DismissedNoteTagSuggestionStore(
        (key) async => values[key],
        (key, value) async => values[key] = value,
      );
      await store.dismiss('Поздний ужин');
      expect(await store.load(), contains('поздний ужин'));
    });
  });
}
