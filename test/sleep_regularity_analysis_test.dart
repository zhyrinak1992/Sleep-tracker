import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_regularity_analysis.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession _session(int day, int bedtime, int wake, {String source = 'apple_health', bool edited = false}) {
  final start = DateTime(2026, 11, day, bedtime ~/ 60, bedtime % 60);
  final endDay = wake <= bedtime ? day + 1 : day;
  final end = DateTime(2026, 11, endDay, wake ~/ 60, wake % 60);
  return SleepSession(
    id: 'night-$day-$bedtime',
    startedAt: start,
    endedAt: end,
    source: source,
    actualSleepStartedAt: start,
    actualSleepEndedAt: end,
    userEdited: edited,
  );
}

void main() {
  group('SleepRegularityAnalysis', () {
    test('treats times around midnight as close together', () {
      final result = SleepRegularityAnalysis.calculate([
        _session(1, 23 * 60 + 55, 7 * 60),
        _session(2, 5, 7 * 60 + 5),
        _session(3, 23 * 60 + 58, 7 * 60 + 2),
      ]);
      expect(result.typicalBedtimeMinute, isNotNull);
      expect(result.bedtimeMad, lessThan(10));
      expect(result.wakeMad, lessThan(10));
    });

    test('excludes manual, edited and incomplete records from confident statistics', () {
      final result = SleepRegularityAnalysis.calculate([
        _session(1, 23 * 60, 7 * 60),
        _session(2, 23 * 60, 7 * 60, source: 'manual'),
        _session(3, 23 * 60, 7 * 60, edited: true),
        const SleepSession(id: 'open', startedAt: DateTime(2026, 11, 4)),
      ]);
      expect(result.nights, hasLength(1));
      expect(result.excludedCount, 3);
      expect(result.isReliable, isFalse);
    });

    test('does not report reliable statistics for fewer than seven nights', () {
      final result = SleepRegularityAnalysis.calculate([
        _session(1, 23 * 60, 7 * 60),
        _session(2, 23 * 60, 7 * 60),
      ]);
      expect(result.isReliable, isFalse);
      expect(result.typicalDurationMinutes, 480);
    });

    test('identifies a substantial bedtime deviation with enough samples', () {
      final result = SleepRegularityAnalysis.calculate([
        _session(1, 23 * 60, 7 * 60),
        _session(2, 23 * 60 + 5, 7 * 60 + 5),
        _session(3, 23 * 60 + 10, 7 * 60 + 10),
        _session(4, 23 * 60 + 2, 7 * 60 + 2),
        _session(5, 23 * 60 + 8, 7 * 60 + 8),
        _session(6, 3 * 60, 7 * 60 + 4),
        _session(7, 23 * 60 + 4, 7 * 60 + 4),
      ]);
      expect(result.nights.where((night) => night.isOutlier), isNotEmpty);
    });
  });
}
