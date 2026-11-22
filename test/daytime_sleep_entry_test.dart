import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/daytime_sleep_entry.dart';

void main() {
  test('daytime sleep entry preserves interval and note through JSON', () {
    final entry = DaytimeSleepEntry(
      id: 'nap-1',
      startedAt: DateTime.utc(2026, 11, 22, 12, 15),
      endedAt: DateTime.utc(2026, 11, 22, 13, 5),
      note: 'После обеда',
    );
    final restored = DaytimeSleepEntry.tryParse(entry.toJson());
    expect(restored, isNotNull);
    expect(restored!.id, 'nap-1');
    expect(restored.duration.inMinutes, 50);
    expect(restored.note, 'После обеда');
    expect(restored.startedAt, entry.startedAt);
    expect(restored.endedAt, entry.endedAt);
  });

  test('daytime sleep parser rejects malformed or non-positive intervals', () {
    expect(DaytimeSleepEntry.tryParse(null), isNull);
    expect(DaytimeSleepEntry.tryParse({'id': 'x'}), isNull);
    expect(DaytimeSleepEntry.tryParse({
      'id': 'zero',
      'startedAt': '2026-11-22T12:00:00.000Z',
      'endedAt': '2026-11-22T12:00:00.000Z',
    }), isNull);
    expect(DaytimeSleepEntry.tryParse({
      'id': 'negative',
      'startedAt': '2026-11-22T13:00:00.000Z',
      'endedAt': '2026-11-22T12:00:00.000Z',
    }), isNull);
  });
}
