import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/notes/note_tag_filter.dart';
import 'package:sleep_tracker/models/sleep_note.dart';

SleepNote _note(String id, String sessionId) => SleepNote(
  id: id,
  sessionId: sessionId,
  text: 'Заметка $id',
  createdAt: DateTime(2026, 11, 22),
  updatedAt: DateTime(2026, 11, 22),
  sessionStartedAt: DateTime(2026, 11, 21, 23),
);

void main() {
  group('filterNotesByTaggedSessions', () {
    test('keeps notes from sessions with any selected tag', () {
      final notes = [_note('a', 'night-1'), _note('b', 'night-2'), _note('c', 'night-1')];

      final result = filterNotesByTaggedSessions(notes, {'night-1'});

      expect(result.map((note) => note.id), ['a', 'c']);
    });

    test('combines tag filtering with the already searched note list', () {
      final searchedNotes = [_note('coffee', 'night-1'), _note('stress', 'night-2')];

      final result = filterNotesByTaggedSessions(searchedNotes, {'night-2'});

      expect(result.map((note) => note.id), ['stress']);
    });

    test('preserves all notes when tag filtering is disabled', () {
      final notes = [_note('a', 'night-1'), _note('b', 'night-2')];

      final result = filterNotesByTaggedSessions(notes, const {}, enabled: false);

      expect(result, notes);
    });

    test('returns an empty list when no sessions match selected tags', () {
      final result = filterNotesByTaggedSessions([_note('a', 'night-1')], {'night-2'});

      expect(result, isEmpty);
    });
  });
}
