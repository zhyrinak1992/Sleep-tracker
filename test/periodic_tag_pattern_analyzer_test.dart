import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/periodic_tag_pattern_analyzer.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession _session(String id, DateTime start) => SleepSession(
  id: id,
  startedAt: start,
  endedAt: start.add(const Duration(hours: 7)),
  source: 'apple_health:test',
  createdAt: start,
  updatedAt: start,
);

void main() {
  group('PeriodicTagPatternAnalyzer', () {
    final start = DateTime(2026, 1, 1);

    test('compares tagged and untagged nights with independent metric samples', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++) _session('tag-$i', start.add(Duration(days: i))),
        for (var i = 0; i < 4; i++) _session('plain-$i', start.add(Duration(days: i + 5))),
      ];
      final result = PeriodicTagPatternAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: {
          for (var i = 0; i < 4; i++) 'tag-$i': {'caffeine'},
        },
        durationBySession: {
          for (var i = 0; i < 4; i++) 'tag-$i': 360,
          for (var i = 0; i < 4; i++) 'plain-$i': 420,
        },
        scoreBySession: {
          for (var i = 0; i < 4; i++) 'tag-$i': 65,
          for (var i = 0; i < 4; i++) 'plain-$i': 80,
        },
        awakeningsBySession: {
          for (var i = 0; i < 4; i++) 'tag-$i': 3,
          for (var i = 0; i < 4; i++) 'plain-$i': 1,
        },
        additionalMetrics: {
          'efficiency': {
            for (var i = 0; i < 4; i++) 'tag-$i': 80,
            for (var i = 0; i < 4; i++) 'plain-$i': 90,
          },
          'subjectiveQuality': {
            for (var i = 0; i < 4; i++) 'tag-$i': 2,
            for (var i = 0; i < 4; i++) 'plain-$i': 4,
          },
        },
        tagLabels: {'caffeine': 'Кофеин'},
      );

      expect(result, hasLength(1));
      final pattern = result.single;
      expect(pattern['label'], 'Кофеин');
      expect(pattern['withTagNights'], 4);
      expect(pattern['withoutTagNights'], 4);
      final metrics = Map<String, Object?>.from(pattern['metrics'] as Map);
      final duration = Map<String, Object?>.from(metrics['duration'] as Map);
      expect(duration['withTagAverage'], 360);
      expect(duration['withoutTagAverage'], 420);
      expect(duration['difference'], -60);
      expect(duration['isSufficient'], isTrue);
      final efficiency = Map<String, Object?>.from(metrics['efficiency'] as Map);
      expect(efficiency['withTagAverage'], 80);
      expect(efficiency['difference'], -10);
      final quality = Map<String, Object?>.from(metrics['subjectiveQuality'] as Map);
      expect(quality['withTagAverage'], 2);
      expect(quality['withoutTagAverage'], 4);
    });

    test('uses circular medians for bedtime values across midnight', () {
      final taggedTimes = [1435, 5, 1438, 2];
      final plainTimes = [15, 20, 25, 30];
      DateTime clockDate(int day, int minute) {
        final date = start.add(Duration(days: day));
        return DateTime(date.year, date.month, date.day, minute ~/ 60, minute % 60);
      }
      DateTime wakeDate(int day, int minute) {
        final date = start.add(Duration(days: day + (minute >= 20 * 60 ? 1 : 0)));
        return DateTime(date.year, date.month, date.day, 8);
      }
      final sessions = <SleepSession>[
        for (var i = 0; i < 4; i++)
          SleepSession(
            id: 'tag-$i',
            startedAt: clockDate(i, taggedTimes[i]),
            endedAt: wakeDate(i, taggedTimes[i]),
            actualSleepStartedAt: clockDate(i, taggedTimes[i]),
            actualSleepEndedAt: wakeDate(i, taggedTimes[i]),
            source: 'apple_health',
          ),
        for (var i = 0; i < 4; i++)
          SleepSession(
            id: 'plain-$i',
            startedAt: clockDate(i + 5, plainTimes[i]),
            endedAt: wakeDate(i + 5, plainTimes[i]),
            actualSleepStartedAt: clockDate(i + 5, plainTimes[i]),
            actualSleepEndedAt: wakeDate(i + 5, plainTimes[i]),
            source: 'apple_health',
          ),
      ];
      final result = PeriodicTagPatternAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: {for (var i = 0; i < 4; i++) 'tag-$i': {'late_meal'}},
        durationBySession: const {},
        scoreBySession: const {},
        awakeningsBySession: const {},
        additionalMetrics: {
          'bedtime': {
            for (var i = 0; i < 4; i++) 'tag-$i': taggedTimes[i].toDouble(),
            for (var i = 0; i < 4; i++) 'plain-$i': plainTimes[i].toDouble(),
          },
        },
        circularMetricKeys: const {'bedtime'},
        tagLabels: const {},
      );
      final metrics = Map<String, Object?>.from(result.single['metrics'] as Map);
      final bedtime = Map<String, Object?>.from(metrics['bedtime'] as Map);
      expect(bedtime['withTagAverage'], 1438);
      expect(bedtime['withoutTagAverage'], 20);
      expect(bedtime['difference'], -22);
      expect(bedtime['isSufficient'], isTrue);
    });

    test('does not convert missing values to zero or publish weak comparisons', () {
      final sessions = <SleepSession>[
        for (var i = 0; i < 3; i++) _session('tag-$i', start.add(Duration(days: i))),
        for (var i = 0; i < 5; i++) _session('plain-$i', start.add(Duration(days: i + 5))),
      ];
      final result = PeriodicTagPatternAnalyzer.analyze(
        sessions: sessions,
        tagsBySession: {
          for (var i = 0; i < 3; i++) 'tag-$i': {'stress'},
        },
        durationBySession: {
          'tag-0': 400,
          'tag-1': 410,
          'plain-0': 420,
          'plain-1': 430,
          'plain-2': 440,
          'plain-3': 450,
        },
        scoreBySession: const {},
        awakeningsBySession: const {},
        tagLabels: const {},
      );

      final metrics = Map<String, Object?>.from(result.single['metrics'] as Map);
      final duration = Map<String, Object?>.from(metrics['duration'] as Map);
      expect(duration['withTagSamples'], 2);
      expect(duration['withoutTagSamples'], 4);
      expect(duration['withTagAverage'], 405);
      expect(duration['difference'], isNull);
      expect(duration['isSufficient'], isFalse);
      final score = Map<String, Object?>.from(metrics['score'] as Map);
      expect(score['withTagAverage'], isNull);
      expect(score['withoutTagAverage'], isNull);
    });
  });
}
