import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/screen_time_entry.dart';

void main() {
  final sleepStart = DateTime(2026, 11, 26, 0, 30);

  test('supports optional duration and optional last-use time', () {
    final durationOnly = ScreenTimeEntry(
      sessionId: 'night-1', windowMinutes: 30, screenMinutes: 12,
      updatedAt: DateTime(2026, 11, 26),
    );
    final lastUseOnly = ScreenTimeEntry(
      sessionId: 'night-2', windowMinutes: 60,
      lastUseAt: DateTime(2026, 11, 25, 23, 55),
      updatedAt: DateTime(2026, 11, 26),
    );
    expect(ScreenTimeEntry.decode(durationOnly.encode()).screenMinutes, 12);
    expect(ScreenTimeEntry.decode(lastUseOnly.encode()).screenMinutes, isNull);
    expect(ScreenTimeEntry.decode(lastUseOnly.encode()).lastUseAt, DateTime(2026, 11, 25, 23, 55));
  });

  test('stores separate values for each supported pre-sleep window', () {
    expect(ScreenTimeEntry.keyFor('night-1', 30), isNot(ScreenTimeEntry.keyFor('night-1', 60)));
    expect(ScreenTimeEntry.supportedWindowMinutes, [30, 60, 120]);
  });

  test('resolves a last-use time across midnight before sleep onset', () {
    final value = ScreenTimeEntry.resolveLastUseTime(sleepStart, hour: 23, minute: 50);
    expect(value, DateTime(2026, 11, 25, 23, 50));
    expect(sleepStart.difference(value), const Duration(minutes: 40));
  });

  test('rejects a last-use time outside the previous 24 hours', () {
    final value = ScreenTimeEntry(
      sessionId: 'night-1', windowMinutes: 30,
      lastUseAt: DateTime(2026, 11, 24, 23, 0),
      updatedAt: DateTime(2026, 11, 26),
    );
    expect(() => value.validateForSleepStart(sleepStart), throwsFormatException);
  });

  test('rejects invalid windows, excessive minutes, and empty entries', () {
    expect(() => ScreenTimeEntry.decode('{"schemaVersion":2,"sessionId":"x","windowMinutes":45,"screenMinutes":5,"updatedAt":"2026-11-26T00:00:00Z","source":"manual"}'), throwsFormatException);
    expect(() => ScreenTimeEntry.decode('{"schemaVersion":2,"sessionId":"x","windowMinutes":30,"screenMinutes":31,"updatedAt":"2026-11-26T00:00:00Z","source":"manual"}'), throwsFormatException);
    expect(() => ScreenTimeEntry.decode('{"schemaVersion":2,"sessionId":"x","windowMinutes":30,"screenMinutes":null,"lastUseAt":null,"updatedAt":"2026-11-26T00:00:00Z","source":"manual"}'), throwsFormatException);
  });
}