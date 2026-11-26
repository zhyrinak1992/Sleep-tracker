import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/tag_sleep_comparison.dart';
import 'package:sleep_tracker/features/analysis/tag_sleep_trend_analysis.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession _night(String id, DateTime start, {int minutes = 420}) => SleepSession(
  id: id,
  startedAt: start,
  endedAt: start.add(Duration(minutes: minutes)),
  source: 'apple_health:Apple Watch',
);

void main() {
  group('TagSleepTrendAnalysis', () {
    test('builds independent monthly series and retains sample counts', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          _night('coffee-$i', DateTime(2026, 1, i + 1), minutes: 450),
        for (var i = 0; i < 4; i++)
          _night('plain-$i', DateTime(2026, 1, i + 8), minutes: 390),
        for (var i = 0; i < 4; i++)
          _night('stress-$i', DateTime(2026, 2, i + 1), minutes: 480),
        for (var i = 0; i < 4; i++)
          _night('other-$i', DateTime(2026, 2, i + 8), minutes: 420),
      ];
      final tags = <String, Set<String>>{
        for (var i = 0; i < 4; i++) 'coffee-$i': {'caffeine'},
        for (var i = 0; i < 4; i++) 'stress-$i': {'stress', 'caffeine'},
      };

      final result = TagSleepTrendAnalysis.calculate(
        sessions: sessions,
        tagsBySession: tags,
        tagKeys: const ['caffeine', 'stress'],
        startMonth: DateTime(2026, 1),
        endMonthExclusive: DateTime(2026, 3),
        metric: TagSleepMetric.sleepDuration,
      );

      expect(result, hasLength(2));
      final caffeine = result.firstWhere((line) => line.tagKey == 'caffeine');
      final stress = result.firstWhere((line) => line.tagKey == 'stress');
      expect(caffeine.points, hasLength(2));
      expect(caffeine.points[0].comparison.isSufficient, isTrue);
      expect(caffeine.points[0].comparison.difference, 60);
      expect(caffeine.points[0].comparison.withTag.nights, 4);
      expect(caffeine.points[0].comparison.withoutTag.nights, 4);
      expect(caffeine.points[1].comparison.isSufficient, isTrue);
      expect(stress.points[0].comparison.difference, isNull);
      expect(stress.points[1].comparison.difference, 60);
    });

    test('keeps insufficient months as gaps rather than zero differences', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 3; i++)
          _night('tag-$i', DateTime(2026, 4, i + 1), minutes: 450),
        for (var i = 0; i < 5; i++)
          _night('plain-$i', DateTime(2026, 4, i + 8), minutes: 390),
      ];
      final result = TagSleepTrendAnalysis.calculate(
        sessions: sessions,
        tagsBySession: {
          for (var i = 0; i < 3; i++) 'tag-$i': {'caffeine'},
        },
        tagKeys: const ['caffeine'],
        startMonth: DateTime(2026, 4),
        endMonthExclusive: DateTime(2026, 5),
        metric: TagSleepMetric.sleepDuration,
      );

      expect(result.single.points.single.comparison.withTag.nights, 3);
      expect(result.single.points.single.comparison.withoutTag.nights, 5);
      expect(result.single.points.single.comparison.difference, isNull);
      expect(result.single.points.single.comparison.isSufficient, isFalse);
    });

    test('creates a continuous month axis across empty months', () {
      final months = TagSleepTrendAnalysis.monthsBetween(
        DateTime(2026, 1, 20),
        DateTime(2026, 4, 1),
      );
      expect(months, [
        DateTime(2026, 1),
        DateTime(2026, 2),
        DateTime(2026, 3),
      ]);
    });

    test('rejects empty tag selection and invalid month range', () {
      expect(
        () => TagSleepTrendAnalysis.calculate(
          sessions: const [],
          tagsBySession: const {},
          tagKeys: const [],
          startMonth: DateTime(2026, 1),
          endMonthExclusive: DateTime(2026, 2),
          metric: TagSleepMetric.sleepDuration,
        ),
        throwsArgumentError,
      );
      expect(
        () => TagSleepTrendAnalysis.monthsBetween(
          DateTime(2026, 2),
          DateTime(2026, 1),
        ),
        returnsNormally,
      );
    });
  });
}
