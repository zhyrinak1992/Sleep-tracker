class HealthDayTagPeriodStats {
  const HealthDayTagPeriodStats({
    required this.start,
    required this.end,
    required this.recordedDays,
    required this.taggedDays,
    required this.percentage,
  });

  final DateTime start;
  final DateTime end;
  final int recordedDays;
  final int taggedDays;
  final double? percentage;
}

class HealthDayTagPeriodComparison {
  const HealthDayTagPeriodComparison._();

  static HealthDayTagPeriodStats calculate({
    required Map<DateTime, List<String>> entries,
    required String tag,
    required DateTime start,
    required DateTime end,
  }) {
    final first = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    if (last.isBefore(first)) {
      throw ArgumentError('Конец периода не может быть раньше начала.');
    }
    final days = entries.entries.where((entry) {
      final day = DateTime(entry.key.year, entry.key.month, entry.key.day);
      return !day.isBefore(first) && !day.isAfter(last);
    }).toList();
    final tagged = days.where((entry) => entry.value.contains(tag)).length;
    return HealthDayTagPeriodStats(
      start: first,
      end: last,
      recordedDays: days.length,
      taggedDays: tagged,
      percentage: days.isEmpty ? null : tagged / days.length * 100,
    );
  }

  static double? differencePercentagePoints({
    required HealthDayTagPeriodStats first,
    required HealthDayTagPeriodStats second,
  }) {
    if (first.percentage == null || second.percentage == null) return null;
    return second.percentage! - first.percentage!;
  }
}
