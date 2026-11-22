import 'dart:math' as math;
import '../../models/sleep_session.dart';

enum ComparisonRange { days30, days90, year, all }

class WeekdayGroupSummary {
  const WeekdayGroupSummary({
    required this.sessions,
    required this.completed,
    required this.rated,
    required this.averageDurationMinutes,
    required this.medianDurationMinutes,
    required this.averageRating,
    required this.averageBedtimeMinutes,
    required this.averageWakeTimeMinutes,
  });

  final List<SleepSession> sessions;
  final int completed;
  final int rated;
  final double? averageDurationMinutes;
  final double? medianDurationMinutes;
  final double? averageRating;
  final double? averageBedtimeMinutes;
  final double? averageWakeTimeMinutes;
}

class WeekdayComparison {
  static const weekdayLabels = <String>['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  static WeekdayGroupSummary summarize(
    Iterable<SleepSession> source, {
    required Set<int> weekdays,
    required DateTime now,
    required ComparisonRange range,
  }) {
    final cutoff = switch (range) {
      ComparisonRange.days30 => now.subtract(const Duration(days: 30)),
      ComparisonRange.days90 => now.subtract(const Duration(days: 90)),
      ComparisonRange.year => DateTime(now.year - 1, now.month, now.day),
      ComparisonRange.all => DateTime(2000),
    };
    final selected = source.where((s) =>
      weekdays.contains(s.startedAt.weekday) &&
      !s.startedAt.isBefore(cutoff) &&
      !s.startedAt.isAfter(now) &&
      !s.startedAt.isAfter(s.endedAt ?? now.add(const Duration(days: 1)))
    ).toList()..sort((a,b)=>a.startedAt.compareTo(b.startedAt));
    final completed = selected.where((s)=>s.duration != null && s.duration!.inMinutes > 0).toList();
    final durations = completed.map((s)=>s.duration!.inMinutes.toDouble()).toList()..sort();
    final ratings = selected.map((s)=>s.morningRating).whereType<int>().toList();
    return WeekdayGroupSummary(
      sessions: selected,
      completed: completed.length,
      rated: ratings.length,
      averageDurationMinutes: durations.isEmpty ? null : durations.reduce((a,b)=>a+b)/durations.length,
      medianDurationMinutes: _median(durations),
      averageRating: ratings.isEmpty ? null : ratings.reduce((a,b)=>a+b)/ratings.length,
      averageBedtimeMinutes: _circularMean(completed.map((s)=>s.actualSleepStartedAt ?? s.startedAt)),
      averageWakeTimeMinutes: _circularMean(completed.map((s)=>s.actualSleepEndedAt ?? s.endedAt).whereType<DateTime>()),
    );
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    return values.length.isOdd ? values[middle] : (values[middle-1] + values[middle]) / 2;
  }

  static double? _circularMean(Iterable<DateTime> values) {
    final items = values.toList();
    if (items.isEmpty) return null;
    var sinSum = 0.0, cosSum = 0.0;
    for (final item in items) {
      final angle = item.hour * 60 + item.minute;
      final radians = angle / 1440 * 2 * math.pi;
      sinSum += math.sin(radians);
      cosSum += math.cos(radians);
    }
    if (sinSum.abs() < 1e-9 && cosSum.abs() < 1e-9) return null;
    var result = math.atan2(sinSum, cosSum) / (2 * math.pi) * 1440;
    if (result < 0) result += 1440;
    return result;
  }

  static String formatMinutes(double? value) {
    if (value == null) return 'Нет данных';
    final rounded = value.round() % 1440;
    return '${(rounded ~/ 60).toString().padLeft(2,'0')}:${(rounded % 60).toString().padLeft(2,'0')}';
  }

  static String formatDuration(double? value) {
    if (value == null) return 'Нет данных';
    final minutes = value.round();
    return '${minutes ~/ 60} ч ${minutes % 60} мин';
  }
}
