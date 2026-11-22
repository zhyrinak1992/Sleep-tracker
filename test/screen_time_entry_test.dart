import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/screen_time_entry.dart';

void main() {
  test('screen-time entry round-trips through JSON with local time restored', () {
    final entry = ScreenTimeEntry(
      sessionId: 'night-1',
      durationMinutes: 45,
      lastUseAt: DateTime(2026, 11, 21, 23, 15),
      updatedAt: DateTime(2026, 11, 22, 8),
    );
    final decoded = ScreenTimeEntry.decode(entry.encode());
    expect(decoded.sessionId, 'night-1');
    expect(decoded.durationMinutes, 45);
    expect(decoded.lastUseAt, entry.lastUseAt);
  });

  test('rejects invalid duration and missing identifiers', () {
    expect(
      () => ScreenTimeEntry.decode('{"sessionId":"night-1","durationMinutes":999,"lastUseAt":"2026-11-21T23:15:00","updatedAt":"2026-11-22T08:00:00"}'),
      throwsFormatException,
    );
    expect(
      () => ScreenTimeEntry.decode('{"sessionId":"","durationMinutes":10,"lastUseAt":"2026-11-21T23:15:00","updatedAt":"2026-11-22T08:00:00"}'),
      throwsFormatException,
    );
  });


  test('resolves last-use time across midnight into the preceding day', () {
    final sleepStart = DateTime(2026, 11, 22, 0, 10);
    final lastUse = ScreenTimeEntry.resolveLastUseTime(
      sleepStart,
      hour: 23,
      minute: 50,
    );
    expect(lastUse, DateTime(2026, 11, 21, 23, 50));
    expect(sleepStart.difference(lastUse).inMinutes, 20);
  });

  test('accepts an earlier same-day use and rejects invalid clock values', () {
    final sleepStart = DateTime(2026, 11, 22, 23, 0);
    final lastUse = ScreenTimeEntry.resolveLastUseTime(
      sleepStart,
      hour: 22,
      minute: 30,
    );
    expect(sleepStart.difference(lastUse).inMinutes, 30);
    expect(
      () => ScreenTimeEntry.resolveLastUseTime(sleepStart, hour: 24, minute: 0),
      throwsFormatException,
    );
  });

}
