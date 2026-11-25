import 'dart:math' as math;

import '../../models/sleep_session.dart';

enum AnalysisPeriod { week, month, year }

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

class SleepRegularitySummary {
  const SleepRegularitySummary({
    required this.sampleCount,
    required this.bedtimeDeviationMinutes,
    required this.wakeTimeDeviationMinutes,
  });

  final int sampleCount;
  final double? bedtimeDeviationMinutes;
  final double? wakeTimeDeviationMinutes;
}

class SleepAnalytics {
  static DateTime addCalendarDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static DateTime periodStart(DateTime date, AnalysisPeriod period) {
    final day = DateTime(date.year, date.month, date.day);
    if (period == AnalysisPeriod.week) {
      return addCalendarDays(day, -(day.weekday - DateTime.monday));
    }
    if (period == AnalysisPeriod.month) return DateTime(date.year, date.month);
    return DateTime(date.year);
  }

  static DateTime nextPeriodStart(DateTime start, AnalysisPeriod period) {
    if (period == AnalysisPeriod.week) return addCalendarDays(start, 7);
    if (period == AnalysisPeriod.month) return DateTime(start.year, start.month + 1);
    return DateTime(start.year + 1);
  }

  static DateTime previousPeriodStart(DateTime start, AnalysisPeriod period) {
    if (period == AnalysisPeriod.week) return addCalendarDays(start, -7);
    if (period == AnalysisPeriod.month) return DateTime(start.year, start.month - 1);
    return DateTime(start.year - 1);
  }

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

  static SleepRegularitySummary regularity(Iterable<SleepSession> sessions) {
    final completed = sessions.where((session) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      return end != null && end.isAfter(start);
    }).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final bedtimes = <int>[];
    final wakeTimes = <int>[];
    for (final session in completed) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt!;
      bedtimes.add(start.hour * 60 + start.minute);
      wakeTimes.add(end.hour * 60 + end.minute);
    }
    return SleepRegularitySummary(
      sampleCount: completed.length,
      bedtimeDeviationMinutes: _circularMeanAbsoluteDeviation(bedtimes),
      wakeTimeDeviationMinutes: _circularMeanAbsoluteDeviation(wakeTimes),
    );
  }

  // Circular statistics keep 23:55 and 00:05 close rather than a day apart.
  static double? _circularMeanAbsoluteDeviation(List<int> minutes) {
    if (minutes.length < 2) return null;
    const dayMinutes = 24 * 60;
    final sine = minutes.fold<double>(0, (sum, value) =>
      sum + math.sin(value * 2 * math.pi / dayMinutes));
    final cosine = minutes.fold<double>(0, (sum, value) =>
      sum + math.cos(value * 2 * math.pi / dayMinutes));
    if (sine.abs() < 1e-9 && cosine.abs() < 1e-9) return null;
    var mean = math.atan2(sine, cosine) * dayMinutes / (2 * math.pi);
    if (mean < 0) mean += dayMinutes;
    final deviations = minutes.map((value) {
      final raw = (value - mean).abs();
      return math.min(raw, dayMinutes - raw);
    });
    return deviations.reduce((x, y) => x + y) / deviations.length;
  }

  static List<double?> chartValues(SleepPeriodSummary summary, AnalysisPeriod period) {
    final count = switch (period) { AnalysisPeriod.week => 7, AnalysisPeriod.month => 5, AnalysisPeriod.year => 12 };
    final values = List<double?>.filled(count, null);
    final totals = List<int>.filled(count, 0);
    final samples = List<int>.filled(count, 0);
    for (final session in summary.sessions) {
      final duration = session.duration;
      if (duration == null || duration.inMinutes <= 0) continue;
      final index = switch (period) {
        AnalysisPeriod.week => session.startedAt.weekday - 1,
        AnalysisPeriod.month => ((session.startedAt.day - 1) ~/ 7).clamp(0, 4),
        AnalysisPeriod.year => session.startedAt.month - 1,
      };
      totals[index] += duration.inMinutes;
      samples[index]++;
    }
    for (var i = 0; i < count; i++) {
      if (samples[i] > 0) values[i] = totals[i] / samples[i];
    }
    return values;
  }
}
