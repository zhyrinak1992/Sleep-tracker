import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/screen_time_sleep_analysis.dart';
import 'package:sleep_tracker/models/screen_time_entry.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  test('groups nights by time since last screen use before sleep', () {
    final sessions = <SleepSession>[];
    final entries = <String, ScreenTimeEntry>{};
    final gaps = [30, 31, 60, 61, 120, 121];
    for (var i = 0; i < gaps.length; i++) {
      final start = DateTime(2026, 11, 20 + i, 23);
      final session = SleepSession(
        id: 'night-$i',
        startedAt: start,
        endedAt: start.add(Duration(minutes: 420 + i * 10)),
      );
      sessions.add(session);
      entries[session.id] = ScreenTimeEntry(
        sessionId: session.id,
        durationMinutes: 15 + i * 10,
        lastUseAt: start.subtract(Duration(minutes: gaps[i])),
        updatedAt: start,
      );
    }

    final groups = ScreenTimeSleepAnalysis.summarize(
      sessions: sessions,
      entries: entries,
    );
    expect(groups.map((group) => group.label).toList(),
      ['До 30 минут', '31–60 минут', '61–120 минут', 'Более 120 минут']);
    expect(groups.map((group) => group.nights).toList(), [1, 2, 2, 1]);
    expect(groups.first.averageSleepMinutes, 420);
  });

  test('ignores open nights, invalid links, and last-use times outside 24 hours', () {
    final start = DateTime(2026, 11, 22, 23);
    final sessions = [
      SleepSession(id: 'valid', startedAt: start, endedAt: start.add(const Duration(hours: 7))),
      SleepSession(id: 'open', startedAt: start),
    ];
    final entries = {
      'valid': ScreenTimeEntry(
        sessionId: 'wrong-session',
        durationMinutes: 30,
        lastUseAt: start.subtract(const Duration(minutes: 20)),
        updatedAt: start,
      ),
      'open': ScreenTimeEntry(
        sessionId: 'open',
        durationMinutes: 30,
        lastUseAt: start.subtract(const Duration(minutes: 20)),
        updatedAt: start,
      ),
    };
    expect(ScreenTimeSleepAnalysis.summarize(
      sessions: sessions,
      entries: entries,
    ), isEmpty);
  });
}
