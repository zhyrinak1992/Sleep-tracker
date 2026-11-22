import 'package:flutter_test/flutter_test.dart';
import '../lib/models/sleep_session.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  test('SleepSession round-trips timestamps and optional values', () {
    final start = DateTime.utc(2026, 11, 21, 21);
    final session = SleepSession(
      id: 'stable-id',
      startedAt: start,
      endedAt: start.add(const Duration(hours: 7, minutes: 30)),
      source: 'manual',
      morningRating: 4,
    );
    final restored = SleepSession.fromMap(session.toMap());
    expect(restored.id, 'stable-id');
    expect(restored.duration, const Duration(hours: 7, minutes: 30));
    expect(restored.morningRating, 4);
  });

  test('completed session exposes the exact recorded interval', () {
    final start = DateTime(2026, 11, 20, 23, 15);
    final end = DateTime(2026, 11, 21, 7, 5);
    final session = SleepSession(id: 'night-2', startedAt: start, endedAt: end);
    expect(session.duration, const Duration(hours: 7, minutes: 50));
  });

  test('open session has no fabricated duration', () {
    final session = SleepSession(
      id: 'open-id',
      startedAt: DateTime.now(),
    );
    expect(session.isOpen, isTrue);
    expect(session.duration, isNull);
  });
}


void mainSleepSessionTimestampTests() {
  // Kept separate from the existing test group to verify schema-v5 fields.
  final started = DateTime(2026, 11, 21, 23, 10);
  final ended = DateTime(2026, 11, 22, 7, 20);
  final buttonStart = DateTime(2026, 11, 21, 22, 55);
  final buttonEnd = DateTime(2026, 11, 22, 7, 25);
  final session = SleepSession(
    id: 'schema-v5',
    startedAt: started,
    endedAt: ended,
    source: 'manual',
    buttonStartedAt: buttonStart,
    buttonEndedAt: buttonEnd,
    actualSleepStartedAt: started,
    actualSleepEndedAt: ended,
    userEdited: true,
  );
  final restored = SleepSession.fromMap(session.toMap());
  assert(restored.buttonStartedAt == buttonStart);
  assert(restored.buttonEndedAt == buttonEnd);
  assert(restored.actualSleepStartedAt == started);
  assert(restored.actualSleepEndedAt == ended);
  assert(restored.userEdited);
}
