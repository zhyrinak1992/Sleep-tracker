import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/sleep_note.dart';

void main() {
  test('SleepNote restores stable IDs, text and local timestamps', () {
    final note = SleepNote.fromMap({
      'id': 'note-1',
      'session_id': 'session-1',
      'body': 'Кофе после обеда',
      'created_at': '2026-11-20T18:00:00.000Z',
      'updated_at': '2026-11-20T18:10:00.000Z',
      'session_started_at': '2026-11-20T22:00:00.000Z',
    });

    expect(note.id, 'note-1');
    expect(note.sessionId, 'session-1');
    expect(note.text, 'Кофе после обеда');
    expect(note.createdAt.isUtc, isFalse);
    expect(note.sessionStartedAt.isUtc, isFalse);
  });
}
