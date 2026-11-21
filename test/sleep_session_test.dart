import 'package:flutter_test/flutter_test.dart';
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
