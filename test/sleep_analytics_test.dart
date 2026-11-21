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
}
