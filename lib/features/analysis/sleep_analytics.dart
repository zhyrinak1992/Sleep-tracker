import '../../models/sleep_session.dart';

enum AnalysisPeriod { week, month }

class SleepPeriodSummary {
  const SleepPeriodSummary({
    required this.sessions,
    required this.completed,
    required this.rated,
    required this.averageDurationMinutes,
    required this.averageRating,
  });

  final List<SleepSession> sessions;
  final int completed;
  final int rated;
  final double? averageDurationMinutes;
  final double? averageRating;
}

class SleepAnalytics {
  static DateTime periodStart(DateTime date, AnalysisPeriod period) {
    final day = DateTime(date.year, date.month, date.day);
    if (period == AnalysisPeriod.week) {
      return day.subtract(Duration(days: day.weekday - DateTime.monday));
    }
    return DateTime(date.year, date.month);
  }

  static DateTime nextPeriodStart(DateTime start, AnalysisPeriod period) =>
      period == AnalysisPeriod.week
          ? start.add(const Duration(days: 7))
          : DateTime(start.year, start.month + 1);

  static DateTime previousPeriodStart(DateTime start, AnalysisPeriod period) =>
      period == AnalysisPeriod.week
          ? start.subtract(const Duration(days: 7))
          : DateTime(start.year, start.month - 1);

  static SleepPeriodSummary summarize(
    Iterable<SleepSession> all,
    DateTime start,
    AnalysisPeriod period,
  ) {
    final end = nextPeriodStart(start, period);
    final selected = all.where((s) =>
        !s.startedAt.isBefore(start) && s.startedAt.isBefore(end)).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed = selected.where((s) => s.duration != null && s.duration!.inMinutes > 0).toList();
    final rated = selected.where((s) => s.morningRating != null).toList();
    final durationAverage = completed.isEmpty
        ? null
        : completed.fold<int>(0, (sum, s) => sum + s.duration!.inMinutes) / completed.length;
    final ratingAverage = rated.isEmpty
        ? null
        : rated.fold<int>(0, (sum, s) => sum + s.morningRating!) / rated.length;
    return SleepPeriodSummary(
      sessions: selected,
      completed: completed.length,
      rated: rated.length,
      averageDurationMinutes: durationAverage,
      averageRating: ratingAverage,
    );
  }

  static List<double?> chartValues(SleepPeriodSummary summary, AnalysisPeriod period) {
    final count = period == AnalysisPeriod.week ? 7 : 5;
    final values = List<double?>.filled(count, null);
    final totals = List<int>.filled(count, 0);
    final samples = List<int>.filled(count, 0);
    for (final session in summary.sessions) {
      final duration = session.duration;
      if (duration == null || duration.inMinutes <= 0) continue;
      final index = period == AnalysisPeriod.week
          ? session.startedAt.weekday - 1
          : ((session.startedAt.day - 1) ~/ 7).clamp(0, 4);
      totals[index] += duration.inMinutes;
      samples[index]++;
    }
    for (var i = 0; i < count; i++) {
      if (samples[i] > 0) values[i] = totals[i] / samples[i];
    }
    return values;
  }
}
