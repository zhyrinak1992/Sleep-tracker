import '../../models/sleep_session.dart';
import 'tag_sleep_comparison.dart';

class TagSleepTrendPoint {
  const TagSleepTrendPoint({required this.month, required this.comparison});

  final DateTime month;
  final TagSleepComparisonResult comparison;
}

class TagSleepTrendSeries {
  const TagSleepTrendSeries({required this.tagKey, required this.points});

  final String tagKey;
  final List<TagSleepTrendPoint> points;
}

/// Builds independent monthly comparisons for each tag.
/// A night may participate in more than one tag series by design.
class TagSleepTrendAnalysis {
  static List<DateTime> monthsBetween(DateTime start, DateTime endExclusive) {
    final first = DateTime(start.year, start.month);
    final end = DateTime(endExclusive.year, endExclusive.month);
    final months = <DateTime>[];
    for (var month = first; month.isBefore(end); month = DateTime(month.year, month.month + 1)) {
      months.add(month);
    }
    return List.unmodifiable(months);
  }

  static List<TagSleepTrendSeries> calculate({
    required Iterable<SleepSession> sessions,
    required Map<String, Set<String>> tagsBySession,
    required Iterable<String> tagKeys,
    required DateTime startMonth,
    required DateTime endMonthExclusive,
    required TagSleepMetric metric,
    Map<String, int> awakeningCountsBySession = const {},
    Map<String, double> efficiencyBySession = const {},
    Map<String, int> sleepLatencyBySession = const {},
  }) {
    if (!endMonthExclusive.isAfter(startMonth)) {
      throw ArgumentError('Конец периода должен быть позже начала.');
    }
    final selectedKeys = tagKeys.toSet().toList()..sort();
    if (selectedKeys.isEmpty || selectedKeys.any((key) => key.trim().isEmpty)) {
      throw ArgumentError('Выберите хотя бы одну отметку.');
    }
    final source = sessions.toList(growable: false);
    final months = monthsBetween(startMonth, endMonthExclusive);
    return List.unmodifiable(selectedKeys.map((tagKey) {
      final points = months.map((month) {
        final nextMonth = DateTime(month.year, month.month + 1);
        final result = TagSleepComparison.calculate(
          sessions: source,
          tagsBySession: tagsBySession,
          tagKeys: {tagKey},
          start: month,
          endExclusive: nextMonth,
          metric: metric,
          awakeningCountsBySession: awakeningCountsBySession,
          efficiencyBySession: efficiencyBySession,
          sleepLatencyBySession: sleepLatencyBySession,
        );
        return TagSleepTrendPoint(month: month, comparison: result);
      }).toList(growable: false);
      return TagSleepTrendSeries(tagKey: tagKey, points: points);
    }));
  }
}
