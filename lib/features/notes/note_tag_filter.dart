import '../../models/sleep_note.dart';

/// Filters notes to sessions carrying at least one selected tag.
/// When disabled, preserves the original list and order.
List<SleepNote> filterNotesByTaggedSessions(
  Iterable<SleepNote> notes,
  Set<String> taggedSessionIds, {
  bool enabled = true,
}) {
  if (!enabled) return notes.toList();
  return notes.where((note) => taggedSessionIds.contains(note.sessionId)).toList();
}
