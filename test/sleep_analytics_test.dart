import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_analytics.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  final monday = DateTime(2026, 11, 16);

  test('week starts on Monday and next period is seven days later', () {
    final start = SleepAnalytics.periodStart(DateTime(2026, 11, 18), AnalysisPeriod.week);
    expect(start, monday);
    expect(SleepAnalytics.nextPeriodStart(start, AnalysisPeriod.week), DateTime(2026, 11, 23));
  });

  test('monthly period uses calendar month boundaries', () {
    final start = SleepAnalytics.periodStart(DateTime(2026, 11, 21), AnalysisPeriod.month);
    expect(start, DateTime(2026, 11));
    expect(SleepAnalytics.nextPeriodStart(start, AnalysisPeriod.month), DateTime(2026, 12));
    expect(SleepAnalytics.previousPeriodStart(start, AnalysisPeriod.month), DateTime(2026, 10));
  });


  test('weekly analysis boundaries remain at local midnight across DST', () {
    final start = SleepAnalytics.periodStart(DateTime(2026, 3, 29, 12), AnalysisPeriod.week);
    expect(start, DateTime(2026, 3, 23));
    expect(start.hour, 0);

    final next = SleepAnalytics.nextPeriodStart(start, AnalysisPeriod.week);
    expect(next, DateTime(2026, 3, 30));
    expect(next.hour, 0);

    final previous = SleepAnalytics.previousPeriodStart(next, AnalysisPeriod.week);
    expect(previous, DateTime(2026, 3, 23));
    expect(previous.hour, 0);

    final transitionDay = SleepAnalytics.addCalendarDays(DateTime(2026, 3, 29), 1);
    expect(transitionDay, DateTime(2026, 3, 30));
    expect(transitionDay.hour, 0);
  });

  test('summary excludes open sessions from duration but keeps real ratings', () {
    final sessions = [
      SleepSession(id: 'a', startedAt: DateTime(2026, 11, 17, 22), endedAt: DateTime(2026, 11, 18, 6), morningRating: 4),
      SleepSession(id: 'b', startedAt: DateTime(2026, 11, 18, 22), morningRating: 2),
      SleepSession(id: 'c', startedAt: DateTime(2026, 11, 19, 22), endedAt: DateTime(2026, 11, 20, 5), morningRating: null),
    ];
    final summary = SleepAnalytics.summarize(sessions, monday, AnalysisPeriod.week);
    expect(summary.sessions.length, 3);
    expect(summary.completed, 2);
    expect(summary.rated, 2);
    expect(summary.averageDurationMinutes, 450);
    expect(summary.averageRating, 3);
  });

  test('chart leaves days without completed sessions empty', () {
    final sessions = [
      SleepSession(id: 'a', startedAt: DateTime(2026, 11, 17, 22), endedAt: DateTime(2026, 11, 18, 6)),
      SleepSession(id: 'b', startedAt: DateTime(2026, 11, 19, 22)),
    ];
    final summary = SleepAnalytics.summarize(sessions, monday, AnalysisPeriod.week);
    final values = SleepAnalytics.chartValues(summary, AnalysisPeriod.week);
    expect(values[1], 480);
    expect(values[3], isNull);
  });

  test('regularity handles bedtimes across midnight using circular distance', () {
    final sessions = [
      SleepSession(id: 'late', startedAt: DateTime(2026, 11, 17, 23, 50), endedAt: DateTime(2026, 11, 18, 7, 0)),
      SleepSession(id: 'early', startedAt: DateTime(2026, 11, 18, 0, 10), endedAt: DateTime(2026, 11, 18, 7, 10)),
    ];
    final result = SleepAnalytics.regularity(sessions);
    expect(result.sampleCount, 2);
    expect(result.bedtimeDeviationMinutes, closeTo(10, 0.01));
    expect(result.wakeTimeDeviationMinutes, closeTo(5, 0.01));
  });

  test('regularity excludes open and zero-duration sessions and needs two samples', () {
    final result = SleepAnalytics.regularity([
      SleepSession(id: 'open', startedAt: DateTime(2026, 11, 17, 23)),
      SleepSession(id: 'zero', startedAt: DateTime(2026, 11, 18, 7), endedAt: DateTime(2026, 11, 18, 7)),
      SleepSession(id: 'valid', startedAt: DateTime(2026, 11, 19, 23), endedAt: DateTime(2026, 11, 20, 7)),
    ]);
    expect(result.sampleCount, 1);
    expect(result.bedtimeDeviationMinutes, isNull);
    expect(result.wakeTimeDeviationMinutes, isNull);
  });
}
