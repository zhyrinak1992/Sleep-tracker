import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/daytime_sleep_analytics.dart';
import 'package:sleep_tracker/models/daytime_sleep_entry.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  test('matches a daytime rest to the next completed night within 18 hours', () {
    final nap = DaytimeSleepEntry(
      id: 'nap-1',
      startedAt: DateTime(2026, 11, 20, 14),
      endedAt: DateTime(2026, 11, 20, 14, 45),
    );
    final night = SleepSession(
      id: 'night-1',
      startedAt: DateTime(2026, 11, 20, 23),
      endedAt: DateTime(2026, 11, 21, 7),
      actualSleepStartedAt: DateTime(2026, 11, 20, 23, 15),
      actualSleepEndedAt: DateTime(2026, 11, 21, 6, 45),
    );

    final result = DaytimeSleepAnalytics.summarizeFollowingNights(
      entries: [nap],
      sessions: [night],
    );

    expect(result.followingNightCount, 1);
    expect(result.averageFollowingNightMinutes, 450);
  });

  test('does not match open sessions or nights outside the 18-hour window', () {
    final nap = DaytimeSleepEntry(
      id: 'nap-1',
      startedAt: DateTime(2026, 11, 20, 13),
      endedAt: DateTime(2026, 11, 20, 14),
    );
    final open = SleepSession(
      id: 'open',
      startedAt: DateTime(2026, 11, 20, 23),
    );
    final tooLate = SleepSession(
      id: 'late',
      startedAt: DateTime(2026, 11, 21, 12, 1),
      endedAt: DateTime(2026, 11, 21, 20),
    );

    final result = DaytimeSleepAnalytics.summarizeFollowingNights(
      entries: [nap],
      sessions: [open, tooLate],
    );

    expect(result.followingNightCount, 0);
    expect(result.averageFollowingNightMinutes, isNull);
  });

  test('does not count the same night twice for multiple rest entries', () {
    final entries = [
      DaytimeSleepEntry(
        id: 'nap-early',
        startedAt: DateTime(2026, 11, 20, 12),
        endedAt: DateTime(2026, 11, 20, 12, 30),
      ),
      DaytimeSleepEntry(
        id: 'nap-late',
        startedAt: DateTime(2026, 11, 20, 15),
        endedAt: DateTime(2026, 11, 20, 15, 30),
      ),
    ];
    final night = SleepSession(
      id: 'night-1',
      startedAt: DateTime(2026, 11, 20, 23),
      endedAt: DateTime(2026, 11, 21, 7),
    );

    final result = DaytimeSleepAnalytics.summarizeFollowingNights(
      entries: entries,
      sessions: [night],
    );

    expect(result.followingNightCount, 1);
    expect(result.averageFollowingNightMinutes, 480);
  });
}
