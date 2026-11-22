import 'dart:convert';
import 'dart:math' as math;

import '../../models/sleep_session.dart';

enum SleepNeedConfidence { low, moderate, high }

class SleepDurationBin {
  const SleepDurationBin({
    required this.label,
    required this.count,
    required this.total,
  });

  final String label;
  final int count;
  final int total;

  double get fraction => total == 0 ? 0 : count / total;
}

class IndividualSleepNight {
  const IndividualSleepNight({
    required this.session,
    required this.durationMinutes,
    required this.wellbeing,
    required this.sleepQuality,
    required this.regularityDeviationMinutes,
    required this.sleepEfficiencyPercent,
  });

  final SleepSession session;
  final int durationMinutes;
  final int? wellbeing;
  final int? sleepQuality;
  final double regularityDeviationMinutes;
  final double? sleepEfficiencyPercent;

  double get subjectiveScore {
    final values = [wellbeing, sleepQuality].whereType<int>().toList();
    return values.isEmpty
        ? 0
        : values.reduce((a, b) => a + b) / values.length;
  }
}

class IndividualSleepNeedResult {
  const IndividualSleepNeedResult({
    required this.isSufficient,
    required this.reason,
    required this.confidence,
    required this.validNightCount,
    required this.ratedNightCount,
    required this.basisNightCount,
    required this.periodStart,
    required this.periodEnd,
    required this.calculatedAt,
    required this.lowerMinutes,
    required this.upperMinutes,
    required this.belowRangeCount,
    required this.withinRangeCount,
    required this.aboveRangeCount,
    required this.averageBedtimeDeviationMinutes,
    required this.averageWakeTimeDeviationMinutes,
    required this.averageSleepEfficiencyPercent,
    required this.efficiencySampleCount,
    required this.distribution,
    required this.basisNights,
  });

  final bool isSufficient;
  final String? reason;
  final SleepNeedConfidence? confidence;
  final int validNightCount;
  final int ratedNightCount;
  final int basisNightCount;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime calculatedAt;
  final int? lowerMinutes;
  final int? upperMinutes;
  final int belowRangeCount;
  final int withinRangeCount;
  final int aboveRangeCount;
  final double? averageBedtimeDeviationMinutes;
  final double? averageWakeTimeDeviationMinutes;
  final double? averageSleepEfficiencyPercent;
  final int efficiencySampleCount;
  final List<SleepDurationBin> distribution;
  final List<IndividualSleepNight> basisNights;
}

class IndividualSleepNeedAnalysis {
  IndividualSleepNeedAnalysis._();

  static const int minimumNights = 21;
  static const int minimumRatedNights = 14;
  static const int minimumBasisNights = 6;

  static IndividualSleepNeedResult evaluate({
    required Iterable<SleepSession> sessions,
    required Map<String, Map<String, Object?>> morningReports,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required DateTime calculatedAt,
  }) {
    final drafts = <_NightDraft>[];
    for (final session in sessions) {
      final interval = _sleepInterval(session);
      if (interval == null) continue;
      final duration = interval.$2.difference(interval.$1).inMinutes;
      // Exclude obviously incomplete or implausible intervals, without
      // inventing a replacement value for them.
      if (duration < 120 || duration > 960) continue;

      final report = _readSubjectiveReport(
        morningReports[session.id],
        session.morningRating,
      );
      final efficiency = _sleepEfficiency(
        session,
        stagesBySession[session.id] ?? const [],
      );
      drafts.add(_NightDraft(
        session: session,
        start: interval.$1,
        end: interval.$2,
        duration: duration,
        wellbeing: report.$1,
        quality: report.$2,
        efficiency: efficiency,
      ));
    }

    drafts.sort((a, b) => a.start.compareTo(b.start));
    final filtered = _removeDurationOutliers(drafts);
    final rated = filtered.where((night) => night.subjectiveScore != null).toList();
    final bedMean = _circularMean(filtered.map((n) => _minuteOfDay(n.start)).toList());
    final wakeMean = _circularMean(filtered.map((n) => _minuteOfDay(n.end)).toList());

    final nights = filtered.map((night) => IndividualSleepNight(
      session: night.session,
      durationMinutes: night.duration,
      wellbeing: night.wellbeing,
      sleepQuality: night.quality,
      regularityDeviationMinutes: (
        _circularDistance(_minuteOfDay(night.start), bedMean) +
        _circularDistance(_minuteOfDay(night.end), wakeMean)
      ) / 2,
      sleepEfficiencyPercent: night.efficiency,
    )).toList();

    final distribution = _distribution(nights);
    final first = nights.isEmpty ? null : nights.first.session.startedAt;
    final last = nights.isEmpty ? null : nights.last.session.startedAt;
    final averageBedtimeDeviation = nights.isEmpty ? null : _average(
      nights.map((n) => _circularDistance(_minuteOfDay(n.session.actualSleepStartedAt ?? n.session.startedAt), bedMean)).toList(),
    );
    final averageWakeDeviation = nights.isEmpty ? null : _average(
      nights.map((n) => _circularDistance(
        _minuteOfDay(n.session.actualSleepEndedAt ?? n.session.endedAt ?? n.session.startedAt),
        wakeMean,
      )).toList(),
    );
    final efficiencyValues = nights.map((n) => n.sleepEfficiencyPercent).whereType<double>().toList();
    final averageEfficiency = efficiencyValues.isEmpty ? null : _average(efficiencyValues);

    IndividualSleepNeedResult insufficient(String reason) => IndividualSleepNeedResult(
      isSufficient: false,
      reason: reason,
      confidence: null,
      validNightCount: nights.length,
      ratedNightCount: rated.length,
      basisNightCount: 0,
      periodStart: first,
      periodEnd: last,
      calculatedAt: calculatedAt,
      lowerMinutes: null,
      upperMinutes: null,
      belowRangeCount: 0,
      withinRangeCount: 0,
      aboveRangeCount: 0,
      averageBedtimeDeviationMinutes: averageBedtimeDeviation,
      averageWakeTimeDeviationMinutes: averageWakeDeviation,
      averageSleepEfficiencyPercent: averageEfficiency,
      efficiencySampleCount: efficiencyValues.length,
      distribution: distribution,
      basisNights: const [],
    );

    if (nights.length < minimumNights ||
        first == null || last == null ||
        last.difference(first).inDays < 21) {
      return insufficient('Нужно не менее 21 завершённой ночи, распределённой как минимум по трём неделям наблюдений за последние 90 дней.');
    }
    if (rated.length < minimumRatedNights) {
      return insufficient('Для осторожной оценки нужны утренние оценки самочувствия или качества сна хотя бы для 14 ночей. Пропущенные опросы не считаются низкой оценкой.');
    }

    final ratedScores = rated.map((n) => n.subjectiveScore!).toList();
    final medianScore = _percentile(ratedScores, 0.5);
    final regularityValues = nights.map((n) => n.regularityDeviationMinutes).toList();
    final regularityLimit = _percentile(regularityValues, 0.75);
    final efficiencyMedian = efficiencyValues.length >= 4
        ? _percentile(efficiencyValues, 0.5)
        : null;

    final basis = nights.where((night) {
      if (night.wellbeing == null && night.sleepQuality == null) return false;
      if (night.subjectiveScore < medianScore) return false;
      if (night.regularityDeviationMinutes > regularityLimit) return false;
      if (efficiencyMedian != null &&
          night.sleepEfficiencyPercent != null &&
          night.sleepEfficiencyPercent! < efficiencyMedian) {
        return false;
      }
      return true;
    }).toList();

    if (basis.length < minimumBasisNights) {
      return insufficient('Пока недостаточно ночей с одновременно благоприятными утренними оценками и относительно устойчивым режимом. Продолжай вести записи — диапазон появится, когда выборка станет надёжнее.');
    }

    final basisDurations = basis.map((n) => n.durationMinutes.toDouble()).toList();
    final lower = _percentile(basisDurations, 0.25).round();
    final upper = _percentile(basisDurations, 0.75).round();
    final confidence = nights.length >= 60 && rated.length >= 40 && basis.length >= 12
        ? SleepNeedConfidence.high
        : nights.length >= 35 && rated.length >= 25 && basis.length >= 8
            ? SleepNeedConfidence.moderate
            : SleepNeedConfidence.low;

    var below = 0;
    var within = 0;
    var above = 0;
    for (final night in nights) {
      if (night.durationMinutes < lower) {
        below++;
      } else if (night.durationMinutes > upper) {
        above++;
      } else {
        within++;
      }
    }

    return IndividualSleepNeedResult(
      isSufficient: true,
      reason: null,
      confidence: confidence,
      validNightCount: nights.length,
      ratedNightCount: rated.length,
      basisNightCount: basis.length,
      periodStart: first,
      periodEnd: last,
      calculatedAt: calculatedAt,
      lowerMinutes: lower,
      upperMinutes: upper,
      belowRangeCount: below,
      withinRangeCount: within,
      aboveRangeCount: above,
      averageBedtimeDeviationMinutes: averageBedtimeDeviation,
      averageWakeTimeDeviationMinutes: averageWakeDeviation,
      averageSleepEfficiencyPercent: averageEfficiency,
      efficiencySampleCount: efficiencyValues.length,
      distribution: distribution,
      basisNights: basis,
    );
  }

  static (DateTime, DateTime)? _sleepInterval(SleepSession session) {
    final start = session.actualSleepStartedAt ?? session.startedAt;
    final end = session.actualSleepEndedAt ?? session.endedAt;
    if (end == null || !end.isAfter(start)) return null;
    return (start, end);
  }

  static (int?, int?) _readSubjectiveReport(
    Map<String, Object?>? report,
    int? fallbackWellbeing,
  ) {
    if (report == null) {
      return (_validRating(fallbackWellbeing), null);
    }
    Map<String, Object?> answers = const {};
    final raw = report['answers_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) answers = Map<String, Object?>.from(decoded);
      } catch (_) {
        // Column values remain usable even if optional JSON is damaged.
      }
    }
    if (answers['skipped'] == true) return (null, null);
    final wellbeing = _validRating(report['wellbeing']) ??
        _validRating(answers['wellbeing']) ??
        _validRating(fallbackWellbeing);
    final quality = _validRating(report['sleep_quality']) ??
        _validRating(answers['sleepQuality']);
    return (wellbeing, quality);
  }

  static int? _validRating(Object? value) {
    if (value is num) {
      final rating = value.round();
      if (rating >= 1 && rating <= 5 && (value - rating).abs() < 0.001) return rating;
    }
    return null;
  }

  static List<_NightDraft> _removeDurationOutliers(List<_NightDraft> values) {
    if (values.length < minimumNights) return values;
    final durations = values.map((n) => n.duration.toDouble()).toList();
    final median = _percentile(durations, 0.5);
    final deviations = durations.map((d) => (d - median).abs()).toList();
    final mad = _percentile(deviations, 0.5);
    if (mad == 0) return values;
    final limit = 3.5 * 1.4826 * mad;
    return values.where((n) => (n.duration - median).abs() <= limit).toList();
  }

  static double? _sleepEfficiency(
    SleepSession session,
    List<Map<String, Object?>> rows,
  ) {
    final inBedStart = session.startedAt;
    final inBedEnd = session.endedAt;
    if (inBedEnd == null || !inBedEnd.isAfter(inBedStart) || rows.isEmpty) return null;
    final intervals = <_StageInterval>[];
    for (final row in rows) {
      final stage = (row['stage'] as String? ?? '').toLowerCase();
      final isAwake = stage.contains('бодрств') || stage.contains('awake');
      final isSleep = !isAwake && (stage.contains('сон') || stage.contains('sleep'));
      if (!isAwake && !isSleep) continue;
      try {
        var start = DateTime.parse(row['started_at']! as String).toLocal();
        var end = DateTime.parse(row['ended_at']! as String).toLocal();
        if (start.isBefore(inBedStart)) start = inBedStart;
        if (end.isAfter(inBedEnd)) end = inBedEnd;
        if (end.isAfter(start)) intervals.add(_StageInterval(start, end, isAwake));
      } catch (_) {
        continue;
      }
    }
    if (!intervals.any((i) => i.awake)) return null;
    final boundaries = <DateTime>{
      for (final interval in intervals) interval.start,
      for (final interval in intervals) interval.end,
    }.toList()..sort();
    var sleepMinutes = 0.0;
    var awakeMinutes = 0.0;
    for (var i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      final midpoint = start.add(Duration(milliseconds: end.difference(start).inMilliseconds ~/ 2));
      final awake = intervals.any((v) => v.awake && !midpoint.isBefore(v.start) && midpoint.isBefore(v.end));
      final asleep = intervals.any((v) => !v.awake && !midpoint.isBefore(v.start) && midpoint.isBefore(v.end));
      if (awake) {
        awakeMinutes += end.difference(start).inSeconds / 60;
      } else if (asleep) {
        sleepMinutes += end.difference(start).inSeconds / 60;
      }
    }
    final covered = sleepMinutes + awakeMinutes;
    final inBedMinutes = inBedEnd.difference(inBedStart).inMinutes.toDouble();
    if (covered < inBedMinutes * 0.8 || covered <= 0 || awakeMinutes <= 0) return null;
    return (sleepMinutes / covered) * 100;
  }

  static List<SleepDurationBin> _distribution(List<IndividualSleepNight> nights) {
    final bins = <SleepDurationBin>[];
    final total = nights.length;
    for (var hour = 2; hour < 16; hour++) {
      final lower = hour * 60;
      final upper = (hour + 1) * 60;
      final count = nights.where((n) =>
        n.durationMinutes >= lower &&
        (hour == 15 ? n.durationMinutes <= upper : n.durationMinutes < upper)
      ).length;
      if (count > 0) {
        bins.add(SleepDurationBin(
          label: '$hour–${hour + 1} ч',
          count: count,
          total: total,
        ));
      }
    }
    return bins;
  }

  static double _minuteOfDay(DateTime value) => (value.hour * 60 + value.minute).toDouble();

  static double _circularMean(List<double> values) {
    if (values.isEmpty) return 0;
    final sine = values.fold<double>(0, (sum, value) =>
      sum + math.sin(value * 2 * math.pi / 1440));
    final cosine = values.fold<double>(0, (sum, value) =>
      sum + math.cos(value * 2 * math.pi / 1440));
    var mean = math.atan2(sine, cosine) * 1440 / (2 * math.pi);
    if (mean < 0) mean += 1440;
    return mean;
  }

  static double _circularDistance(double a, double b) {
    final raw = (a - b).abs() % 1440;
    return math.min(raw, 1440 - raw);
  }

  static double _average(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static double _percentile(List<double> values, double fraction) {
    if (values.isEmpty) return 0;
    final sorted = values.toList()..sort();
    final position = (sorted.length - 1) * fraction;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}

class _NightDraft {
  const _NightDraft({
    required this.session,
    required this.start,
    required this.end,
    required this.duration,
    required this.wellbeing,
    required this.quality,
    required this.efficiency,
  });

  final SleepSession session;
  final DateTime start;
  final DateTime end;
  final int duration;
  final int? wellbeing;
  final int? quality;
  final double? efficiency;

  double? get subjectiveScore {
    final values = [wellbeing, quality].whereType<int>().toList();
    return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  }
}

class _StageInterval {
  const _StageInterval(this.start, this.end, this.awake);
  final DateTime start;
  final DateTime end;
  final bool awake;
}
