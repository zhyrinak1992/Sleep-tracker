import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/individual_sleep_need.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  List<SleepSession> makeSessions(int count, {bool addOutlier = false}) {
    return List.generate(count, (index) {
      final start = DateTime(2026, 1, 1 + index * 2, 23);
      final duration = addOutlier && index == count - 1
          ? 960
          : 420 + (index % 5) * 15;
      return SleepSession(
        id: 'night-$index',
        startedAt: start,
        endedAt: start.add(Duration(minutes: duration)),
      );
    });
  }

  Map<String, Map<String, Object?>> makeReports(
    List<SleepSession> sessions, {
    int skipped = 0,
  }) {
    return {
      for (var i = 0; i < sessions.length; i++)
        sessions[i].id: {
          'session_id': sessions[i].id,
          'wellbeing': i % 2 == 0 ? 5 : 4,
          'sleep_quality': 4,
          'answers_json': jsonEncode({'skipped': i < skipped}),
        },
    };
  }

  test('estimates a personal range only with several weeks and enough rated nights', () {
    final sessions = makeSessions(28);
    final result = IndividualSleepNeedAnalysis.evaluate(
      sessions: sessions,
      morningReports: makeReports(sessions),
      stagesBySession: const {},
      calculatedAt: DateTime(2026, 3, 1),
    );

    expect(result.isSufficient, isTrue);
    expect(result.validNightCount, 28);
    expect(result.ratedNightCount, 28);
    expect(result.basisNightCount, greaterThanOrEqualTo(6));
    expect(result.lowerMinutes, isNotNull);
    expect(result.upperMinutes, isNotNull);
    expect(result.lowerMinutes, lessThanOrEqualTo(result.upperMinutes!));
    expect(result.withinRangeCount + result.belowRangeCount + result.aboveRangeCount, 28);
    expect(result.distribution.fold<int>(0, (sum, bin) => sum + bin.count), 28);
  });

  test('does not estimate from fewer than 21 completed nights', () {
    final sessions = makeSessions(20);
    final result = IndividualSleepNeedAnalysis.evaluate(
      sessions: sessions,
      morningReports: makeReports(sessions),
      stagesBySession: const {},
      calculatedAt: DateTime(2026, 3, 1),
    );

    expect(result.isSufficient, isFalse);
    expect(result.lowerMinutes, isNull);
    expect(result.validNightCount, 20);
  });

  test('skipped morning reports are not treated as poor ratings', () {
    final sessions = makeSessions(28);
    final result = IndividualSleepNeedAnalysis.evaluate(
      sessions: sessions,
      morningReports: makeReports(sessions, skipped: 15),
      stagesBySession: const {},
      calculatedAt: DateTime(2026, 3, 1),
    );

    expect(result.isSufficient, isFalse);
    expect(result.ratedNightCount, 13);
    expect(result.reason, contains('утренние оценки'));
  });

  test('excludes implausible duration outliers and calculates efficiency only from covered awake stages', () {
    final sessions = makeSessions(28, addOutlier: true);
    final stages = <String, List<Map<String, Object?>>>{};
    for (final session in sessions.take(4)) {
      final start = session.startedAt;
      stages[session.id] = [
        {
          'stage': 'Сон без уточнённой фазы',
          'started_at': start.toIso8601String(),
          'ended_at': start.add(const Duration(hours: 4)).toIso8601String(),
        },
        {
          'stage': 'Бодрствование',
          'started_at': start.add(const Duration(hours: 4)).toIso8601String(),
          'ended_at': start.add(const Duration(hours: 4, minutes: 30)).toIso8601String(),
        },
        {
          'stage': 'Сон без уточнённой фазы',
          'started_at': start.add(const Duration(hours: 4, minutes: 30)).toIso8601String(),
          'ended_at': start.add(const Duration(hours: 7)).toIso8601String(),
        },
      ];
    }
    final result = IndividualSleepNeedAnalysis.evaluate(
      sessions: sessions,
      morningReports: makeReports(sessions),
      stagesBySession: stages,
      calculatedAt: DateTime(2026, 3, 1),
    );

    expect(result.validNightCount, 27);
    expect(result.efficiencySampleCount, 4);
    expect(result.averageSleepEfficiencyPercent, closeTo(92.86, 0.1));
  });
}
