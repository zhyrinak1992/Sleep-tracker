enum HealthDayTagHistoryPeriod { week, month, halfYear, allTime }

extension HealthDayTagHistoryPeriodLabel on HealthDayTagHistoryPeriod {
  String get label => switch (this) {
    HealthDayTagHistoryPeriod.week => 'Неделя',
    HealthDayTagHistoryPeriod.month => 'Месяц',
    HealthDayTagHistoryPeriod.halfYear => 'Полгода',
    HealthDayTagHistoryPeriod.allTime => 'Всё время',
  };
}

class HealthDayTagHistoryRange {
  const HealthDayTagHistoryRange({
    required this.start,
    required this.endExclusive,
  });

  final DateTime start;
  final DateTime endExclusive;

  String get description =>
      _formatDate(start) + ' — ' +
      _formatDate(DateTime(endExclusive.year, endExclusive.month, endExclusive.day - 1));

  static String _formatDate(DateTime date) =>
      date.day.toString().padLeft(2, '0') + '.' +
      date.month.toString().padLeft(2, '0') + '.' +
      date.year.toString();
}

class HealthDayTagHistoryBucket {
  const HealthDayTagHistoryBucket({
    required this.start,
    required this.endExclusive,
    required this.label,
  });

  final DateTime start;
  final DateTime endExclusive;
  final String label;
}

class HealthDayTagHistoryPeriodCalculator {
  const HealthDayTagHistoryPeriodCalculator._();

  static HealthDayTagHistoryRange range({
    required HealthDayTagHistoryPeriod period,
    required DateTime now,
    DateTime? earliestEntry,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final endExclusive = DateTime(today.year, today.month, today.day + 1);
    final start = switch (period) {
      HealthDayTagHistoryPeriod.week =>
        DateTime(today.year, today.month, today.day - 6),
      HealthDayTagHistoryPeriod.month => DateTime(today.year, today.month),
      HealthDayTagHistoryPeriod.halfYear =>
        DateTime(today.year, today.month - 5),
      HealthDayTagHistoryPeriod.allTime => earliestEntry == null
          ? today
          : DateTime(earliestEntry.year, earliestEntry.month, earliestEntry.day),
    };
    return HealthDayTagHistoryRange(
      start: start,
      endExclusive: endExclusive,
    );
  }

  static List<HealthDayTagHistoryBucket> buckets({
    required HealthDayTagHistoryPeriod period,
    required HealthDayTagHistoryRange range,
  }) {
    final daily = period == HealthDayTagHistoryPeriod.week ||
        period == HealthDayTagHistoryPeriod.month;
    final result = <HealthDayTagHistoryBucket>[];
    var cursor = daily
        ? range.start
        : DateTime(range.start.year, range.start.month);
    while (cursor.isBefore(range.endExclusive)) {
      final next = daily
          ? DateTime(cursor.year, cursor.month, cursor.day + 1)
          : DateTime(cursor.year, cursor.month + 1);
      final end = next.isAfter(range.endExclusive)
          ? range.endExclusive
          : next;
      final label = daily
          ? cursor.day.toString().padLeft(2, '0') + '.' +
              cursor.month.toString().padLeft(2, '0')
          : cursor.month.toString().padLeft(2, '0') + '.' + cursor.year.toString();
      result.add(HealthDayTagHistoryBucket(
        start: cursor,
        endExclusive: end,
        label: label,
      ));
      cursor = next;
    }
    return result;
  }
}
