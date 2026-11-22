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
}
