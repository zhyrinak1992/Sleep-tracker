import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_analytics.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  group('SleepAnalytics period boundaries', () {
    test('week starts on Monday and advances by seven days', () {
      final start = SleepAnalytics.periodStart(DateTime(2026, 11, 22), AnalysisPeriod.week);
      expect(start, DateTime(2026, 11, 16));
      expect(SleepAnalytics.nextPeriodStart(start, AnalysisPeriod.week), DateTime(2026, 11, 23));
      expect(SleepAnalytics.previousPeriodStart(start, AnalysisPeriod.week), DateTime(2026, 11, 9));
    });

    test('month boundaries handle year changes', () {
      final december = SleepAnalytics.periodStart(DateTime(2026, 12, 31), AnalysisPeriod.month);
      expect(december, DateTime(2026, 12));
      expect(SleepAnalytics.nextPeriodStart(december, AnalysisPeriod.month), DateTime(2027, 1));
      expect(SleepAnalytics.previousPeriodStart(december, AnalysisPeriod.month), DateTime(2026, 11));
    });
  });

  group('SleepAnalytics summaries', () {
    test('counts completed sessions and ratings independently', () {
      final sessions = [
        SleepSession(id: 'a', startedAt: DateTime(2026, 11, 16, 22), endedAt: DateTime(2026, 11, 17, 6), morningRating: 4),
        SleepSession(id: 'b', startedAt: DateTime(2026, 11, 17, 23), endedAt: DateTime(2026, 11, 18, 5)),
        SleepSession(id: 'c', startedAt: DateTime(2026, 11, 18, 23), morningRating: 5),
        SleepSession(id: 'outside', startedAt: DateTime(2026, 11, 23, 22), endedAt: DateTime(2026, 11, 24, 6), morningRating: 3),
      ];
      final summary = SleepAnalytics.summarize(sessions, DateTime(2026, 11, 16), AnalysisPeriod.week);
      expect(summary.sessions.length, 3);
      expect(summary.completed, 2);
      expect(summary.rated, 2);
      expect(summary.averageDurationMinutes, 420);
      expect(summary.averageRating, 4.5);
    });

    test('chart averages sessions by weekday and leaves missing days empty', () {
      final sessions = [
        SleepSession(id: 'a', startedAt: DateTime(2026, 11, 16, 22), endedAt: DateTime(2026, 11, 17, 6)),
        SleepSession(id: 'b', startedAt: DateTime(2026, 11, 16, 23), endedAt: DateTime(2026, 11, 17, 5)),
        SleepSession(id: 'c', startedAt: DateTime(2026, 11, 18, 22), endedAt: DateTime(2026, 11, 19, 6)),
      ];
      final summary = SleepAnalytics.summarize(sessions, DateTime(2026, 11, 16), AnalysisPeriod.week);
      final values = SleepAnalytics.chartValues(summary, AnalysisPeriod.week);
      expect(values.length, 7);
      expect(values[0], 420);
      expect(values[1], isNull);
      expect(values[2], 480);
      expect(values.skip(3).every((value) => value == null), isTrue);
    });

    test('monthly chart assigns days 1–7, 8–14, 15–21, 22–28 and 29+', () {
      final sessions = [
        for (var day in [1, 8, 15, 22, 29])
          SleepSession(id: 'd$day', startedAt: DateTime(2026, 11, day, 22), endedAt: DateTime(2026, 11, day + 1, 6)),
      ];
      final summary = SleepAnalytics.summarize(sessions, DateTime(2026, 11), AnalysisPeriod.month);
      final values = SleepAnalytics.chartValues(summary, AnalysisPeriod.month);
      expect(values, [480, 480, 480, 480, 480]);
    });

    test('open sessions and zero-length sessions do not affect duration chart', () {
      final sessions = [
        SleepSession(id: 'open', startedAt: DateTime(2026, 11, 16, 22)),
        SleepSession(id: 'zero', startedAt: DateTime(2026, 11, 17, 22), endedAt: DateTime(2026, 11, 17, 22)),
      ];
      final summary = SleepAnalytics.summarize(sessions, DateTime(2026, 11, 16), AnalysisPeriod.week);
      expect(summary.completed, 0);
      expect(SleepAnalytics.chartValues(summary, AnalysisPeriod.week), everyElement(isNull));
    });
  });
}
