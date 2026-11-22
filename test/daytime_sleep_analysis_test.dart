import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/daytime_sleep_analysis.dart';
import 'package:sleep_tracker/models/daytime_sleep_entry.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  test('associates a recorded nap with the following night only', () {
    final sessions = [
      SleepSession(
        id: 'night-1',
        startedAt: DateTime(2026, 11, 21, 23),
        endedAt: DateTime(2026, 11, 22, 6, 30),
      ),
      SleepSession(
        id: 'night-2',
        startedAt: DateTime(2026, 11, 22, 23),
        endedAt: DateTime(2026, 11, 23, 7),
      ),
    ];
    final naps = [
      DaytimeSleepEntry(
        id: 'nap-1',
        startedAt: DateTime(2026, 11, 22, 14),
        endedAt: DateTime(2026, 11, 22, 14, 30),
      ),
    ];

    final result = DaytimeSleepAnalysis.compareWithFollowingNights(
      sessions: sessions,
      naps: naps,
    );
    expect(result.nightsWithNap, 1);
    expect(result.nightsWithoutNap, 1);
    expect(result.averageSleepWithNapMinutes, 480);
    expect(result.averageSleepWithoutNapMinutes, 450);
    expect(result.differenceMinutes, 30);
  });

  test('ignores naps older than the prior 24 hours and unfinished nights', () {
    final result = DaytimeSleepAnalysis.compareWithFollowingNights(
      sessions: [
        SleepSession(
          id: 'old',
          startedAt: DateTime(2026, 11, 20, 23),
          endedAt: DateTime(2026, 11, 21, 7),
        ),
        SleepSession(
          id: 'current',
          startedAt: DateTime(2026, 11, 22, 23),
          endedAt: DateTime(2026, 11, 23, 7),
        ),
        SleepSession(id: 'open', startedAt: DateTime(2026, 11, 23, 23)),
      ],
      naps: [
        DaytimeSleepEntry(
          id: 'old-nap',
          startedAt: DateTime(2026, 11, 21, 8),
          endedAt: DateTime(2026, 11, 21, 9),
        ),
      ],
    );
    expect(result.nightsWithNap, 0);
    expect(result.nightsWithoutNap, 2);
    expect(result.averageSleepWithNapMinutes, isNull);
    expect(result.averageSleepWithoutNapMinutes, 480);
    expect(result.differenceMinutes, isNull);
  });
}
