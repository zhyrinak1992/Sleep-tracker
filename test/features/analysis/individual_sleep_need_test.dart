import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/individual_sleep_need.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  final calculatedAt = DateTime(2026, 11, 23, 12);

  List<SleepSession> nights({
    int count = 22,
    int Function(int index)? startMinute,
    int Function(int index)? duration,
    int? rating = 4,
  }) => List.generate(count, (index) {
    final minute = startMinute?.call(index) ?? 0;
    final start = DateTime(2026, 10, 1 + index, 23, minute);
    final end = start.add(Duration(minutes: duration?.call(index) ?? 480));
    return SleepSession(
      id: 'night-$index',
      startedAt: start,
      endedAt: end,
      morningRating: rating,
    );
  });

  group('IndividualSleepNeedAnalysis', () {
    test('does not estimate a personal range before 21 nights over three weeks', () {
      final result = IndividualSleepNeedAnalysis.evaluate(
        sessions: nights(count: 20),
        morningReports: const {},
        stagesBySession: const {},
        calculatedAt: calculatedAt,
      );

      expect(result.isSufficient, isFalse);
      expect(result.lowerMinutes, isNull);
      expect(result.upperMinutes, isNull);
      expect(result.validNightCount, 20);
    });

    test('derives a range from rated, regular completed nights', () {
      final result = IndividualSleepNeedAnalysis.evaluate(
        sessions: nights(),
        morningReports: const {},
        stagesBySession: const {},
        calculatedAt: calculatedAt,
      );

      expect(result.isSufficient, isTrue);
      expect(result.validNightCount, 22);
      expect(result.ratedNightCount, 22);
      expect(result.basisNightCount, greaterThanOrEqualTo(6));
      expect(result.lowerMinutes, 480);
      expect(result.upperMinutes, 480);
      expect(result.withinRangeCount, 22);
      expect(result.belowRangeCount, 0);
      expect(result.aboveRangeCount, 0);
    });

    test('treats an explicitly skipped morning report as missing, not as a rating', () {
      final sessions = nights();
      final reports = {
        for (final session in sessions)
          session.id: <String, Object?>{'answers_json': '{"skipped":true}'},
      };
      final result = IndividualSleepNeedAnalysis.evaluate(
        sessions: sessions,
        morningReports: reports,
        stagesBySession: const {},
        calculatedAt: calculatedAt,
      );

      expect(result.isSufficient, isFalse);
      expect(result.ratedNightCount, 0);
      expect(result.lowerMinutes, isNull);
    });

    test('handles bedtime observations straddling midnight as nearby times', () {
      final result = IndividualSleepNeedAnalysis.evaluate(
        sessions: nights(
          startMinute: (index) => index.isEven ? 55 : 5,
        ),
        morningReports: const {},
        stagesBySession: const {},
        calculatedAt: calculatedAt,
      );

      expect(result.isSufficient, isTrue);
      expect(result.averageBedtimeDeviationMinutes, lessThan(15));
    });

    test('ignores open, reversed, and implausibly long sessions', () {
      final valid = nights();
      final invalid = [
        SleepSession(id: 'open', startedAt: DateTime(2026, 10, 23, 23)),
        SleepSession(
          id: 'reversed',
          startedAt: DateTime(2026, 10, 24, 23),
          endedAt: DateTime(2026, 10, 24, 22),
        ),
        SleepSession(
          id: 'too-long',
          startedAt: DateTime(2026, 10, 25, 8),
          endedAt: DateTime(2026, 10, 26, 2),
          morningRating: 4,
        ),
      ];
      final result = IndividualSleepNeedAnalysis.evaluate(
        sessions: [...valid, ...invalid],
        morningReports: const {},
        stagesBySession: const {},
        calculatedAt: calculatedAt,
      );

      expect(result.validNightCount, 22);
      expect(result.ratedNightCount, 22);
    });
  });
}
