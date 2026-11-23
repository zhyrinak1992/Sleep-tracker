import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_period_comparison.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession session(String id, DateTime start, {DateTime? end, int? rating}) =>
    SleepSession(id: id, startedAt: start, endedAt: end, morningRating: rating);

void main() {
  group('SleepPeriodComparison', () {
    test('uses inclusive calendar dates and excludes the following day', () {
      final data = [
        session('a', DateTime(2026, 11, 1, 23), end: DateTime(2026, 11, 2, 6), rating: 4),
        session('b', DateTime(2026, 11, 2, 23), end: DateTime(2026, 11, 3, 5), rating: 3),
        session('c', DateTime(2026, 11, 3, 0), end: DateTime(2026, 11, 3, 7)),
      ];
      final result = SleepPeriodComparison.summarize(
        data, DateTime(2026, 11, 1), DateTime(2026, 11, 2));
      expect(result.sessions.map((item) => item.id), ['a', 'b']);
      expect(result.completed, 2);
      expect(result.rated, 2);
      expect(result.averageDurationMinutes, 390);
      expect(result.averageRating, 3.5);
    });

    test('does not count open or zero-length sessions in duration average', () {
      final data = [
        session('completed', DateTime(2026, 11, 1), end: DateTime(2026, 11, 1, 6)),
        session('open', DateTime(2026, 11, 1, 8), rating: 5),
        session('zero', DateTime(2026, 11, 1, 10), end: DateTime(2026, 11, 1, 10)),
      ];
      final result = SleepPeriodComparison.summarize(
        data, DateTime(2026, 11, 1), DateTime(2026, 11, 1));
      expect(result.sessions, hasLength(3));
      expect(result.completed, 1);
      expect(result.averageDurationMinutes, 360);
      expect(result.rated, 1);
      expect(result.averageRating, 5);
    });

    test('compares bedtime and wake-time regularity across midnight', () {
      final data = [
        session('a', DateTime(2026, 11, 1, 22), end: DateTime(2026, 11, 2, 6)),
        session('b', DateTime(2026, 11, 2, 22, 10), end: DateTime(2026, 11, 3, 6, 10)),
        session('open', DateTime(2026, 11, 3, 22)),
      ];
      final result = SleepPeriodComparison.summarize(
        data, DateTime(2026, 11, 1), DateTime(2026, 11, 3));
      expect(result.regularitySampleCount, 2);
      expect(result.bedtimeDeviationMinutes, closeTo(5, 0.01));
      expect(result.wakeTimeDeviationMinutes, closeTo(5, 0.01));
    });

    test('does not invent regularity with fewer than two completed nights', () {
      final result = SleepPeriodComparison.summarize(
        [session('only', DateTime(2026, 11, 1, 23), end: DateTime(2026, 11, 2, 7))],
        DateTime(2026, 11, 1), DateTime(2026, 11, 1));
      expect(result.regularitySampleCount, 1);
      expect(result.bedtimeDeviationMinutes, isNull);
      expect(result.wakeTimeDeviationMinutes, isNull);
    });


    test('compares efficiency, awakenings, morning answers and audio events by selected sessions', () {
      final night = SleepSession(
        id: 'night-a',
        startedAt: DateTime(2026, 11, 1, 23),
        endedAt: DateTime(2026, 11, 2, 7),
        source: 'health',
        actualSleepStartedAt: DateTime(2026, 11, 1, 23, 10),
        actualSleepEndedAt: DateTime(2026, 11, 2, 6, 10),
      );
      final range = SleepPeriodComparison.summarize(
        [night], DateTime(2026, 11, 1), DateTime(2026, 11, 1));
      final details = SleepPeriodDetailSummary.summarize(
        range: range,
        stagesBySession: {
          'night-a': [
            {
              'stage': 'core',
              'started_at': DateTime(2026, 11, 1, 23, 10).toIso8601String(),
              'ended_at': DateTime(2026, 11, 2, 6).toIso8601String(),
            },
            {
              'stage': 'awake',
              'started_at': DateTime(2026, 11, 2, 6).toIso8601String(),
              'ended_at': DateTime(2026, 11, 2, 6, 10).toIso8601String(),
            },
          ],
        },
        morningReports: {
          'night-a': {'sleep_quality': 4, 'wellbeing': 5},
        },
        audioEvents: [
          {'session_id': 'night-a', 'category': 'snore', 'duration_ms': 1200},
          {'session_id': 'not-selected', 'category': 'noise', 'duration_ms': 800},
        ],
      );
      expect(details.efficiencySamples, 1);
      expect(details.averageEfficiency, closeTo(85.4, 0.2));
      expect(details.awakeningSamples, 1);
      expect(details.averageAwakenings, 1);
      expect(details.averageQuality, 4);
      expect(details.averageWellbeing, 5);
      expect(details.typicalBedtimeMinute, 23 * 60 + 10);
      expect(details.typicalWakeMinute, 6 * 60 + 10);
      expect(details.audio.eventCount, 1);
      expect(details.audio.nightsWithEvents, 1);
      expect(details.audio.categoryCounts, {'snore': 1});
    });

    test('keeps unavailable period metrics null when there is no stage or morning data', () {
      final night = session(
        'night-no-data', DateTime(2026, 11, 1, 23), end: DateTime(2026, 11, 2, 7));
      final range = SleepPeriodComparison.summarize(
        [night], DateTime(2026, 11, 1), DateTime(2026, 11, 1));
      final details = SleepPeriodDetailSummary.summarize(
        range: range,
        stagesBySession: const {},
        morningReports: const {},
        audioEvents: const [],
      );
      expect(details.averageEfficiency, isNull);
      expect(details.efficiencySamples, 0);
      expect(details.averageAwakenings, isNull);
      expect(details.awakeningSamples, 0);
      expect(details.averageQuality, isNull);
      expect(details.averageWellbeing, isNull);
      expect(details.audio.eventCount, 0);
    });

    test('rejects reversed ranges', () {
      expect(
        () => SleepPeriodComparison.summarize(
          [], DateTime(2026, 11, 2), DateTime(2026, 11, 1)),
        throwsArgumentError,
      );
    });

    test('percentage change requires two real non-zero comparable values', () {
      expect(SleepPeriodComparison.percentageChange(120, 100), 20);
      expect(SleepPeriodComparison.percentageChange(80, 100), -20);
      expect(SleepPeriodComparison.percentageChange(null, 100), isNull);
      expect(SleepPeriodComparison.percentageChange(100, null), isNull);
      expect(SleepPeriodComparison.percentageChange(100, 0), isNull);
    });
  });
}
