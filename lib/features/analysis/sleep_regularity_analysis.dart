import 'dart:math' as math;

import '../../models/sleep_session.dart';

class SleepRegularityNight {
  const SleepRegularityNight({
    required this.session,
    required this.bedtimeMinute,
    required this.wakeMinute,
    required this.durationMinutes,
    required this.bedtimeDeviation,
    required this.wakeDeviation,
    required this.isOutlier,
  });

  final SleepSession session;
  final int bedtimeMinute;
  final int wakeMinute;
  final int durationMinutes;
  final int bedtimeDeviation;
  final int wakeDeviation;
  final bool isOutlier;
}

class SleepRegularityAnalysis {
  const SleepRegularityAnalysis({
    required this.nights,
    required this.excludedCount,
    required this.typicalBedtimeMinute,
    required this.typicalWakeMinute,
    required this.bedtimeMad,
    required this.wakeMad,
    required this.typicalDurationMinutes,
    required this.durationMad,
    required this.isReliable,
  });

  final List<SleepRegularityNight> nights;
  final int excludedCount;
  final int? typicalBedtimeMinute;
  final int? typicalWakeMinute;
  final double? bedtimeMad;
  final double? wakeMad;
  final int? typicalDurationMinutes;
  final double? durationMad;
  final bool isReliable;

  static SleepRegularityAnalysis calculate(Iterable<SleepSession> sessions) {
    final valid = <({SleepSession session, int bed, int wake, int duration})>[];
    var excluded = 0;
    for (final session in sessions) {
      final start = session.actualSleepStartedAt;
      final end = session.actualSleepEndedAt;
      // A session start button or approximate manual entry is not a measured
      // sleep boundary. Keep it visible in the excluded count, never as zero.
      if (start == null ||
          end == null ||
          !end.isAfter(start) ||
          session.source.toLowerCase() == 'manual' ||
          session.userEdited) {
        excluded++;
        continue;
      }
      final duration = end.difference(start).inMinutes;
      if (duration <= 0 || duration > 20 * 60) {
        excluded++;
        continue;
      }
      valid.add((
        session: session,
        bed: start.hour * 60 + start.minute,
        wake: end.hour * 60 + end.minute,
        duration: duration,
      ));
    }
    valid.sort((a, b) => a.session.startedAt.compareTo(b.session.startedAt));

    int? circularMedian(List<int> values) {
      if (values.isEmpty) return null;
      var best = values.first;
      var bestCost = double.infinity;
      for (final candidate in values) {
        final cost = values.fold<double>(0, (sum, value) {
          final raw = (value - candidate).abs().toDouble();
          return sum + math.min(raw, 1440 - raw);
        });
        if (cost < bestCost) {
          best = candidate;
          bestCost = cost;
        }
      }
      return best;
    }

    int circularDistance(int a, int b) {
      final raw = (a - b).abs();
      return math.min(raw, 1440 - raw);
    }

    double? median(List<num> values) {
      if (values.isEmpty) return null;
      final sorted = [...values]..sort();
      final middle = sorted.length ~/ 2;
      return sorted.length.isOdd
          ? sorted[middle].toDouble()
          : (sorted[middle - 1] + sorted[middle]) / 2;
    }

    final bedValues = valid.map((row) => row.bed).toList();
    final wakeValues = valid.map((row) => row.wake).toList();
    final durationValues = valid.map((row) => row.duration).toList();
    final bedMedian = circularMedian(bedValues);
    final wakeMedian = circularMedian(wakeValues);
    final bedDistances = bedMedian == null ? <int>[] : bedValues.map((v) => circularDistance(v, bedMedian)).toList();
    final wakeDistances = wakeMedian == null ? <int>[] : wakeValues.map((v) => circularDistance(v, wakeMedian)).toList();
    final bedMad = median(bedDistances);
    final wakeMad = median(wakeDistances);
    final durationMedian = median(durationValues);
    final durationMad = durationMedian == null ? null : median(durationValues.map((v) => (v - durationMedian).abs()).toList());

    final nights = <SleepRegularityNight>[];
    for (var i = 0; i < valid.length; i++) {
      final row = valid[i];
      final bedDeviation = bedDistances[i];
      final wakeDeviation = wakeDistances[i];
      final isOutlier = valid.length >= 5 &&
          ((bedMad != null && bedDeviation > math.max(60, bedMad * 2.5)) ||
           (wakeMad != null && wakeDeviation > math.max(60, wakeMad * 2.5)));
      nights.add(SleepRegularityNight(
        session: row.session,
        bedtimeMinute: row.bed,
        wakeMinute: row.wake,
        durationMinutes: row.duration,
        bedtimeDeviation: bedDeviation,
        wakeDeviation: wakeDeviation,
        isOutlier: isOutlier,
      ));
    }

    return SleepRegularityAnalysis(
      nights: nights,
      excludedCount: excluded,
      typicalBedtimeMinute: bedMedian,
      typicalWakeMinute: wakeMedian,
      bedtimeMad: bedMad,
      wakeMad: wakeMad,
      typicalDurationMinutes: durationMedian?.round(),
      durationMad: durationMad,
      isReliable: valid.length >= 7,
    );
  }
}
