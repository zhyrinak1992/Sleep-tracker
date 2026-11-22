import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/weekday_comparison.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  final now = DateTime(2026, 11, 22, 12);

  test('assigns a night only by its start weekday and excludes missing durations', () {
    final sessions = [
      SleepSession(id:'mon', startedAt:DateTime(2026,11,16,23), endedAt:DateTime(2026,11,17,7), morningRating:4),
      SleepSession(id:'sat', startedAt:DateTime(2026,11,21,23), endedAt:DateTime(2026,11,22,7), morningRating:3),
      SleepSession(id:'open', startedAt:DateTime(2026,11,22,23)),
    ];
    final weekdays = WeekdayComparison.summarize(sessions, weekdays:{1,2,3,4,5}, now:now, range:ComparisonRange.all);
    final weekend = WeekdayComparison.summarize(sessions, weekdays:{6,7}, now:now, range:ComparisonRange.all);
    expect(weekdays.sessions.map((s)=>s.id), ['mon']);
    expect(weekend.sessions.map((s)=>s.id), ['sat']);
    expect(weekdays.averageDurationMinutes, 480);
    expect(weekend.completed, 1);
  });

  test('median duration is robust to one long night', () {
    final sessions = [
      SleepSession(id:'a',startedAt:DateTime(2026,11,16,22),endedAt:DateTime(2026,11,17,6)),
      SleepSession(id:'b',startedAt:DateTime(2026,11,17,22),endedAt:DateTime(2026,11,18,6)),
      SleepSession(id:'c',startedAt:DateTime(2026,11,18,22),endedAt:DateTime(2026,11,19,10)),
    ];
    final summary = WeekdayComparison.summarize(sessions, weekdays:{1,2,3,4,5,6,7}, now:now, range:ComparisonRange.all);
    expect(summary.medianDurationMinutes, 480);
    expect(summary.averageDurationMinutes, 560);
  });

  test('circular average bedtime treats 23:50 and 00:10 as close', () {
    final sessions = [
      SleepSession(id:'a',startedAt:DateTime(2026,11,16,23,50),endedAt:DateTime(2026,11,17,7)),
      SleepSession(id:'b',startedAt:DateTime(2026,11,17,0,10),endedAt:DateTime(2026,11,17,7)),
    ];
    final summary = WeekdayComparison.summarize(sessions, weekdays:{1,2,3,4,5,6,7}, now:now, range:ComparisonRange.all);
    expect(summary.averageBedtimeMinutes, closeTo(0, 1e-6));
  });
}
