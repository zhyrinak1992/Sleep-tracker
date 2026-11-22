import '../../models/sleep_session.dart';

class SleepRangeSummary {
  const SleepRangeSummary({
    required this.start,
    required this.endExclusive,
    required this.sessions,
    required this.completed,
    required this.rated,
    required this.averageDurationMinutes,
    required this.averageRating,
  });

  final DateTime start;
  final DateTime endExclusive;
  final List<SleepSession> sessions;
  final int completed;
  final int rated;
  final double? averageDurationMinutes;
  final double? averageRating;
}

class SleepPeriodComparison {
  static SleepRangeSummary summarize(
    Iterable<SleepSession> source,
    DateTime start,
    DateTime endInclusive,
  ) {
    final from = DateTime(start.year, start.month, start.day);
    final until = DateTime(endInclusive.year, endInclusive.month, endInclusive.day)
        .add(const Duration(days: 1));
    if (!until.isAfter(from)) {
      throw ArgumentError('Конец периода должен быть не раньше начала.');
    }
    final selected = source.where((session) =>
      !session.startedAt.isBefore(from) && session.startedAt.isBefore(until))
      .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed = selected.where((session) =>
      session.duration != null && session.duration!.inMinutes > 0).toList();
    final rated = selected.where((session) => session.morningRating != null).toList();
    return SleepRangeSummary(
      start: from,
      endExclusive: until,
      sessions: selected,
      completed: completed.length,
      rated: rated.length,
      averageDurationMinutes: completed.isEmpty ? null :
        completed.fold<int>(0, (sum, item) => sum + item.duration!.inMinutes) / completed.length,
      averageRating: rated.isEmpty ? null :
        rated.fold<int>(0, (sum, item) => sum + item.morningRating!) / rated.length,
    );
  }

  static double? percentageChange(double? current, double? previous) {
    if (current == null || previous == null || previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}
