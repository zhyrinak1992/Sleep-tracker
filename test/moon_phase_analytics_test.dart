import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/moon_phase_analytics.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  test('known new moon has near-zero illumination', () {
    final point=MoonPhaseAnalytics.at(DateTime.utc(2000,1,6,18,14));
    expect(point.illumination,closeTo(0,0.002));
    expect(point.label,'Новолуние');
  });

  test('approximately half a synodic month later is full moon', () {
    final full=DateTime.utc(2000,1,6,18,14).add(Duration(microseconds:(MoonPhaseAnalytics.synodicMonthDays*0.5*Duration.microsecondsPerDay).round()));
    final point=MoonPhaseAnalytics.at(full);
    expect(point.illumination,closeTo(1,0.002));
    expect(point.label,'Полнолуние');
  });

  test('groups completed nights by phase at interval midpoint', () {
    final sessions=[
      SleepSession(id:'new',startedAt:DateTime.utc(2000,1,6,17),endedAt:DateTime.utc(2000,1,6,20),actualSleepStartedAt:DateTime.utc(2000,1,6,17),actualSleepEndedAt:DateTime.utc(2000,1,6,20),morningRating:4),
      SleepSession(id:'full',startedAt:DateTime.utc(2000,1,21,17),endedAt:DateTime.utc(2000,1,21,20),actualSleepStartedAt:DateTime.utc(2000,1,21,17),actualSleepEndedAt:DateTime.utc(2000,1,21,20),morningRating:2),
      SleepSession(id:'open',startedAt:DateTime.utc(2000,1,6,17)),
    ];
    final groups=MoonPhaseAnalytics.summarize(sessions);
    expect(groups.first.count,1);
    expect(groups[4].count,1);
    expect(groups.fold<int>(0,(sum,g)=>sum+g.count),2);
  });
  test('detects a phase boundary crossed during a night', () {
    final start = DateTime.utc(2000, 1, 6, 18, 14);
    final end = start.add(Duration(microseconds: (MoonPhaseAnalytics.synodicMonthDays / 8 * Duration.microsecondsPerDay).round()));
    final session = SleepSession(id:'crossing', startedAt:start, endedAt:end, actualSleepStartedAt:start, actualSleepEndedAt:end);
    expect(MoonPhaseAnalytics.phaseChangedDuring(session), isTrue);
  });

  test('does not use session button times when actual sleep bounds are absent', () {
    final session = SleepSession(
      id: 'manual',
      startedAt: DateTime(2026, 11, 21, 23),
      endedAt: DateTime(2026, 11, 22, 7),
    );
    expect(MoonPhaseAnalytics.phaseChangedDuring(session), isFalse);
    final groups = MoonPhaseAnalytics.summarize([session]);
    expect(groups.fold<int>(0, (sum, group) => sum + group.count), 0);
  });

}
