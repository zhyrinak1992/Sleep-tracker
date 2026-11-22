import 'dart:math' as math;
import '../../models/sleep_session.dart';

class MoonPhasePoint {
  const MoonPhasePoint({required this.phase, required this.illumination, required this.label});
  final double phase;
  final double illumination;
  final String label;
}

class MoonPhaseGroup {
  const MoonPhaseGroup({required this.index, required this.label, required this.count,
    required this.averageDurationMinutes, required this.averageRating, required this.averageIllumination});
  final int index;
  final String label;
  final int count;
  final double? averageDurationMinutes;
  final double? averageRating;
  final double? averageIllumination;
}

class MoonPhaseAnalytics {
  static const synodicMonthDays = 29.530588853;
  static final DateTime _knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
  static const labels = <String>[
    'Новолуние', 'Растущий серп', 'Первая четверть', 'Растущая Луна',
    'Полнолуние', 'Убывающая Луна', 'Последняя четверть', 'Убывающий серп',
  ];

  static MoonPhasePoint at(DateTime dateTime) {
    final utc = dateTime.toUtc();
    final days = utc.difference(_knownNewMoon).inMicroseconds /
        Duration.microsecondsPerDay;
    final phase = (days / synodicMonthDays) % 1.0;
    final normalized = phase < 0 ? phase + 1 : phase;
    final illumination = (1 - math.cos(2 * math.pi * normalized)) / 2;
    final index = ((normalized * 8 + 0.5).floor()) % 8;
    return MoonPhasePoint(phase: normalized, illumination: illumination, label: labels[index]);
  }

  static int indexAt(DateTime dateTime) => labels.indexOf(at(dateTime).label);

  static List<MoonPhaseGroup> summarize(Iterable<SleepSession> sessions) {
    final buckets = List<List<SleepSession>>.generate(8, (_) => <SleepSession>[]);
    for (final session in sessions) {
      final end = session.actualSleepEndedAt ?? session.endedAt;
      if (end == null || !end.isAfter(session.startedAt)) continue;
      final midpoint = session.startedAt.add(end.difference(session.startedAt) ~/ 2);
      buckets[indexAt(midpoint)].add(session);
    }
    return List.generate(8, (i) {
      final bucket = buckets[i];
      final durations = bucket.map((s)=>s.duration?.inMinutes).whereType<int>().where((v)=>v>0).toList();
      final ratings = bucket.map((s)=>s.morningRating).whereType<int>().toList();
      final illumination = bucket.map((s) {
        final end = s.actualSleepEndedAt ?? s.endedAt!;
        final midpoint = s.startedAt.add(end.difference(s.startedAt) ~/ 2);
        return at(midpoint).illumination;
      }).toList();
      return MoonPhaseGroup(
        index:i, label:labels[i], count:bucket.length,
        averageDurationMinutes:durations.isEmpty?null:durations.reduce((a,b)=>a+b)/durations.length,
        averageRating:ratings.isEmpty?null:ratings.reduce((a,b)=>a+b)/ratings.length,
        averageIllumination:illumination.isEmpty?null:illumination.reduce((a,b)=>a+b)/illumination.length,
      );
    });
  }

  static bool phaseChangedDuring(SleepSession session) {
    final end = session.actualSleepEndedAt ?? session.endedAt;
    if (end == null || !end.isAfter(session.startedAt)) return false;
    return indexAt(session.startedAt) != indexAt(end);
  }

  static String percent(double? value) => value == null ? 'Нет данных' : '${(value*100).round()}%';
  static String duration(double? value) {
    if (value == null) return 'Нет данных';
    final m=value.round();
    return '${m~/60} ч ${m%60} мин';
  }
}
