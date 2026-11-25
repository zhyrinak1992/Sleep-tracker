import 'dart:convert';

import '../../models/sleep_session.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_score.dart';

/// Personal bests derived only from completed, non-deleted sessions.
/// Dates are compared as local calendar days (not 24-hour durations), so DST
/// transitions cannot break a streak.
class SleepPersonalRecords {
  const SleepPersonalRecords({
    this.longestSleepMinutes,
    this.longestSleepSessionId,
    this.longestSleepAt,
    this.bestSleepScore,
    this.bestSleepScoreSessionId,
    this.bestSleepScoreAt,
    this.bestEfficiencyPercent,
    this.bestEfficiencySessionId,
    this.bestEfficiencyAt,
    this.fewestAwakenings,
    this.fewestAwakeningsSessionId,
    this.fewestAwakeningsAt,
    this.shortestLatencyMinutes,
    this.shortestLatencySessionId,
    this.shortestLatencyAt,
    this.longestStreakDays = 0,
    this.longestStreakAt,
  });

  final int? longestSleepMinutes;
  final String? longestSleepSessionId;
  final DateTime? longestSleepAt;
  final int? bestSleepScore;
  final String? bestSleepScoreSessionId;
  final DateTime? bestSleepScoreAt;
  final double? bestEfficiencyPercent;
  final String? bestEfficiencySessionId;
  final DateTime? bestEfficiencyAt;
  final int? fewestAwakenings;
  final String? fewestAwakeningsSessionId;
  final DateTime? fewestAwakeningsAt;
  final int? shortestLatencyMinutes;
  final String? shortestLatencySessionId;
  final DateTime? shortestLatencyAt;
  final int longestStreakDays;
  final DateTime? longestStreakAt;

  static SleepPersonalRecords calculate({
    required Iterable<SleepSession> sessions,
    required Map<String, List<Map<String, Object?>>> stagesBySession,
    required Map<String, Map<String, Object?>> morningReports,
  }) {
    final valid = sessions.where((session) {
      final duration = session.duration;
      return session.deletedAt == null &&
          session.endedAt != null &&
          duration != null &&
          duration.inMinutes > 0;
    }).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    var historyStartIndex = 0;
    int? longestSleep;
    String? longestSleepId;
    DateTime? longestSleepAt;
    int? bestSleepScore;
    String? bestSleepScoreId;
    DateTime? bestSleepScoreAt;
    double? bestEfficiency;
    String? bestEfficiencyId;
    DateTime? bestEfficiencyAt;
    int? fewestAwakenings;
    String? fewestAwakeningsId;
    DateTime? fewestAwakeningsAt;

    for (var index = 0; index < valid.length; index++) {
      final session = valid[index];
      final metrics = SleepSessionMetrics.calculate(
        session: session,
        stages: stagesBySession[session.id] ?? const [],
      );
      final sleepMinutes = metrics.sleepDurationMinutes;
      if (sleepMinutes != null && sleepMinutes > 0 &&
          (longestSleep == null || sleepMinutes > longestSleep)) {
        longestSleep = sleepMinutes;
        longestSleepId = session.id;
        longestSleepAt = session.startedAt;
      }

      final historyCutoff = session.startedAt.subtract(const Duration(days: 90));
      while (historyStartIndex < index &&
          valid[historyStartIndex].startedAt.isBefore(historyCutoff)) {
        historyStartIndex++;
      }
      final score = SleepScoreCalculator.calculateForSession(
        session: session,
        historySessions: valid.sublist(historyStartIndex, index),
        morningReports: morningReports,
        stagesBySession: stagesBySession,
      ).score;
      if (score != null && score.isFinite && score >= 0 && score <= 100) {
        final roundedScore = score.round();
        if (bestSleepScore == null || roundedScore > bestSleepScore) {
          bestSleepScore = roundedScore;
          bestSleepScoreId = session.id;
          bestSleepScoreAt = session.startedAt;
        }
      }

      final awakeningsAreReliable = metrics.hasAwakeSamples &&
          metrics.stageCoveragePercent != null &&
          metrics.stageCoveragePercent! >= 80;
      if (awakeningsAreReliable &&
          (fewestAwakenings == null || metrics.awakeningCount < fewestAwakenings)) {
        fewestAwakenings = metrics.awakeningCount;
        fewestAwakeningsId = session.id;
        fewestAwakeningsAt = session.startedAt;
      }

      final efficiency = metrics.sleepEfficiencyPercent;
      if (efficiency != null && efficiency.isFinite &&
          efficiency >= 0 && efficiency <= 100 &&
          (bestEfficiency == null || efficiency > bestEfficiency)) {
        bestEfficiency = efficiency;
        bestEfficiencyId = session.id;
        bestEfficiencyAt = session.startedAt;
      }

    }

    return SleepPersonalRecords(
      longestSleepMinutes: longestSleep,
      longestSleepSessionId: longestSleepId,
      longestSleepAt: longestSleepAt,
      bestSleepScore: bestSleepScore,
      bestSleepScoreSessionId: bestSleepScoreId,
      bestSleepScoreAt: bestSleepScoreAt,
      bestEfficiencyPercent: bestEfficiency,
      bestEfficiencySessionId: bestEfficiencyId,
      bestEfficiencyAt: bestEfficiencyAt,
      fewestAwakenings: fewestAwakenings,
      fewestAwakeningsSessionId: fewestAwakeningsId,
      fewestAwakeningsAt: fewestAwakeningsAt,
    );
  }

  static int longestStreak(Iterable<SleepSession> sessions) =>
      longestStreakDetails(sessions).days;

  static ({int days, DateTime? achievedAt}) longestStreakDetails(
    Iterable<SleepSession> sessions,
  ) {
    final days = sessions
        .where((session) => session.deletedAt == null &&
            session.endedAt != null &&
            session.duration != null &&
            session.duration!.inMinutes > 0)
        .map((session) => DateTime(
              session.startedAt.year,
              session.startedAt.month,
              session.startedAt.day,
            ))
        .toSet()
        .toList()
      ..sort();

    if (days.isEmpty) return (days: 0, achievedAt: null);
    var longest = 1;
    var current = 1;
    var achievedAt = days.first;
    for (var i = 1; i < days.length; i++) {
      final previousDay = DateTime.utc(
        days[i - 1].year, days[i - 1].month, days[i - 1].day,
      );
      final currentDay = DateTime.utc(
        days[i].year, days[i].month, days[i].day,
      );
      final difference = currentDay.difference(previousDay).inDays;
      if (difference == 1) {
        current++;
        if (current > longest) {
          longest = current;
          achievedAt = days[i];
        }
      } else if (difference > 1) {
        current = 1;
      }
    }
    return (days: longest, achievedAt: achievedAt);
  }

  Map<String, Object?> toMap() => {
        'recordSchemaVersion': 2,
        'longestSleepMinutes': longestSleepMinutes,
        'longestSleepSessionId': longestSleepSessionId,
        'longestSleepAt': longestSleepAt?.toUtc().toIso8601String(),
        'bestSleepScore': bestSleepScore,
        'bestSleepScoreSessionId': bestSleepScoreSessionId,
        'bestSleepScoreAt': bestSleepScoreAt?.toUtc().toIso8601String(),
        'bestEfficiencyPercent': bestEfficiencyPercent,
        'bestEfficiencySessionId': bestEfficiencySessionId,
        'bestEfficiencyAt': bestEfficiencyAt?.toUtc().toIso8601String(),
        'fewestAwakenings': fewestAwakenings,
        'fewestAwakeningsSessionId': fewestAwakeningsSessionId,
        'fewestAwakeningsAt': fewestAwakeningsAt?.toUtc().toIso8601String(),
        'shortestLatencyMinutes': shortestLatencyMinutes,
        'shortestLatencySessionId': shortestLatencySessionId,
        'shortestLatencyAt': shortestLatencyAt?.toUtc().toIso8601String(),
        'longestStreakDays': longestStreakDays,
        'longestStreakAt': longestStreakAt?.toIso8601String(),
      };

  factory SleepPersonalRecords.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final value = map[key];
      return value is String ? DateTime.tryParse(value)?.toLocal() : null;
    }

    int? integer(String key) {
      final value = map[key];
      return value is int && value >= 0 ? value : null;
    }

    double? decimal(String key) {
      final value = map[key];
      if (value is! num || !value.toDouble().isFinite) return null;
      final result = value.toDouble();
      return result >= 0 && result <= 100 ? result : null;
    }

    String? string(String key) => map[key] is String ? map[key] as String : null;

    return SleepPersonalRecords(
      longestSleepMinutes: integer('longestSleepMinutes'),
      longestSleepSessionId: string('longestSleepSessionId'),
      longestSleepAt: date('longestSleepAt'),
      bestSleepScore: integer('bestSleepScore') == null || integer('bestSleepScore')! > 100
          ? null : integer('bestSleepScore'),
      bestSleepScoreSessionId: string('bestSleepScoreSessionId'),
      bestSleepScoreAt: date('bestSleepScoreAt'),
      bestEfficiencyPercent: decimal('bestEfficiencyPercent'),
      bestEfficiencySessionId: string('bestEfficiencySessionId'),
      bestEfficiencyAt: date('bestEfficiencyAt'),
      fewestAwakenings: integer('fewestAwakenings'),
      fewestAwakeningsSessionId: string('fewestAwakeningsSessionId'),
      fewestAwakeningsAt: date('fewestAwakeningsAt'),
      shortestLatencyMinutes: integer('shortestLatencyMinutes'),
      shortestLatencySessionId: string('shortestLatencySessionId'),
      shortestLatencyAt: date('shortestLatencyAt'),
      longestStreakDays: integer('longestStreakDays') ?? 0,
      longestStreakAt: date('longestStreakAt'),
    );
  }

  /// Merges a new calculation with the persisted all-time bests. Deleting or
  /// editing an old night therefore cannot silently erase an earned record.
  SleepPersonalRecords preserveBest(SleepPersonalRecords previous) {
    bool keepPrevious({
      required num? currentValue,
      required num? previousValue,
      required DateTime? currentAt,
      required DateTime? previousAt,
      required String? currentSessionId,
      required String? previousSessionId,
      bool lowerIsBetter = false,
    }) {
      if (previousValue == null) return false;
      if (currentValue == null) return true;
      final previousIsBetter = lowerIsBetter
          ? previousValue < currentValue
          : previousValue > currentValue;
      if (previousIsBetter) return true;
      final currentIsBetter = lowerIsBetter
          ? currentValue < previousValue
          : currentValue > previousValue;
      if (currentIsBetter) return false;
      // When values tie, prefer the entry with confirmed source metadata.
      if (previousAt == null && currentAt != null) return false;
      if (previousSessionId == null && currentSessionId != null) return false;
      return true;
    }

    final keepSleep = keepPrevious(
      currentValue: longestSleepMinutes,
      previousValue: previous.longestSleepMinutes,
      currentAt: longestSleepAt,
      previousAt: previous.longestSleepAt,
      currentSessionId: longestSleepSessionId,
      previousSessionId: previous.longestSleepSessionId,
    );
    final keepScore = keepPrevious(
      currentValue: bestSleepScore,
      previousValue: previous.bestSleepScore,
      currentAt: bestSleepScoreAt,
      previousAt: previous.bestSleepScoreAt,
      currentSessionId: bestSleepScoreSessionId,
      previousSessionId: previous.bestSleepScoreSessionId,
    );
    final keepEfficiency = keepPrevious(
      currentValue: bestEfficiencyPercent,
      previousValue: previous.bestEfficiencyPercent,
      currentAt: bestEfficiencyAt,
      previousAt: previous.bestEfficiencyAt,
      currentSessionId: bestEfficiencySessionId,
      previousSessionId: previous.bestEfficiencySessionId,
    );
    final keepAwakenings = keepPrevious(
      currentValue: fewestAwakenings,
      previousValue: previous.fewestAwakenings,
      currentAt: fewestAwakeningsAt,
      previousAt: previous.fewestAwakeningsAt,
      currentSessionId: fewestAwakeningsSessionId,
      previousSessionId: previous.fewestAwakeningsSessionId,
      lowerIsBetter: true,
    );
    final keepLatency = keepPrevious(
      currentValue: shortestLatencyMinutes,
      previousValue: previous.shortestLatencyMinutes,
      currentAt: shortestLatencyAt,
      previousAt: previous.shortestLatencyAt,
      currentSessionId: shortestLatencySessionId,
      previousSessionId: previous.shortestLatencySessionId,
      lowerIsBetter: true,
    );
    final keepStreak = longestStreakDays < previous.longestStreakDays ||
        (longestStreakDays == previous.longestStreakDays &&
            (previous.longestStreakAt != null || longestStreakAt == null));
    return SleepPersonalRecords(
      longestSleepMinutes: keepSleep ? previous.longestSleepMinutes : longestSleepMinutes,
      longestSleepSessionId: keepSleep ? previous.longestSleepSessionId : longestSleepSessionId,
      longestSleepAt: keepSleep ? previous.longestSleepAt : longestSleepAt,
      bestSleepScore: keepScore ? previous.bestSleepScore : bestSleepScore,
      bestSleepScoreSessionId: keepScore ? previous.bestSleepScoreSessionId : bestSleepScoreSessionId,
      bestSleepScoreAt: keepScore ? previous.bestSleepScoreAt : bestSleepScoreAt,
      bestEfficiencyPercent: keepEfficiency ? previous.bestEfficiencyPercent : bestEfficiencyPercent,
      bestEfficiencySessionId: keepEfficiency ? previous.bestEfficiencySessionId : bestEfficiencySessionId,
      bestEfficiencyAt: keepEfficiency ? previous.bestEfficiencyAt : bestEfficiencyAt,
      fewestAwakenings: keepAwakenings ? previous.fewestAwakenings : fewestAwakenings,
      fewestAwakeningsSessionId: keepAwakenings ? previous.fewestAwakeningsSessionId : fewestAwakeningsSessionId,
      fewestAwakeningsAt: keepAwakenings ? previous.fewestAwakeningsAt : fewestAwakeningsAt,
      shortestLatencyMinutes: keepLatency ? previous.shortestLatencyMinutes : shortestLatencyMinutes,
      shortestLatencySessionId: keepLatency ? previous.shortestLatencySessionId : shortestLatencySessionId,
      shortestLatencyAt: keepLatency ? previous.shortestLatencyAt : shortestLatencyAt,
      longestStreakDays: keepStreak ? previous.longestStreakDays : longestStreakDays,
      longestStreakAt: keepStreak ? previous.longestStreakAt : longestStreakAt,
    );
  }
}

/// A confirmed improvement to one of the four approved personal records.
/// Historical events are independent of the source night, so deleting a night
/// never erases a record the user has already earned.
class SleepPersonalRecordEvent {
  const SleepPersonalRecordEvent({
    required this.id,
    required this.metric,
    required this.value,
    required this.achievedAt,
    this.sessionId,
  });

  static const metricKeys = <String>{
    'longestSleepMinutes',
    'bestSleepScore',
    'bestEfficiencyPercent',
    'fewestAwakenings',
    'shortestLatencyMinutes',
    'longestStreakDays',
  };

  final String id;
  final String metric;
  final double value;
  final DateTime achievedAt;
  final String? sessionId;

  Map<String, Object?> toMap() => {
    'id': id,
    'metric': metric,
    'value': value,
    'achievedAt': achievedAt.toUtc().toIso8601String(),
    'sessionId': sessionId,
  };

  factory SleepPersonalRecordEvent.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final metric = map['metric'];
    final rawValue = map['value'];
    final rawDate = map['achievedAt'];
    final date = rawDate is String ? DateTime.tryParse(rawDate) : null;
    final sessionId = map['sessionId'];
    if (id is! String || id.isEmpty ||
        metric is! String || !metricKeys.contains(metric) ||
        rawValue is! num || !rawValue.toDouble().isFinite ||
        date == null || (sessionId != null && sessionId is! String)) {
      throw const FormatException('Запись истории личных рекордов повреждена.');
    }
    final value = rawValue.toDouble();
    final validValue = switch (metric) {
      'longestSleepMinutes' => value > 0 && value % 1 == 0,
      'bestSleepScore' => value >= 0 && value <= 100 && value % 1 == 0,
      'bestEfficiencyPercent' => value >= 0 && value <= 100,
      'fewestAwakenings' => value >= 0 && value % 1 == 0,
      'shortestLatencyMinutes' => value >= 0 && value <= 1440 && value % 1 == 0,
      'longestStreakDays' => value >= 1 && value % 1 == 0,
      _ => false,
    };
    if (!validValue) {
      throw const FormatException('Значение личного рекорда недопустимо.');
    }
    return SleepPersonalRecordEvent(
      id: id,
      metric: metric,
      value: value,
      achievedAt: date.toLocal(),
      sessionId: sessionId as String?,
    );
  }

  static String createId({
    required String metric,
    required double value,
    required DateTime achievedAt,
    String? sessionId,
  }) => '$metric|${sessionId ?? ''}|$value|${achievedAt.toUtc().toIso8601String()}';
}

class SleepPersonalRecordHistory {
  SleepPersonalRecordHistory._();

  static const metadataKey = 'sleep_personal_records_history_v1';

  static List<SleepPersonalRecordEvent> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('История личных рекордов повреждена.');
    }
    final events = <SleepPersonalRecordEvent>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        events.add(SleepPersonalRecordEvent.fromMap(
          Map<String, dynamic>.from(item),
        ));
      } on FormatException {
        // A malformed event must not invalidate other saved records.
      }
    }
    return _sorted(events);
  }

  static String encode(List<SleepPersonalRecordEvent> events) =>
      jsonEncode(_sorted(events).map((event) => event.toMap()).toList());

  static List<SleepPersonalRecordEvent> fromRecords(
    SleepPersonalRecords records,
  ) {
    final events = <SleepPersonalRecordEvent>[];
    void add(String metric, num? rawValue, DateTime? date, String? sessionId) {
      if (rawValue == null || date == null) return;
      final value = rawValue.toDouble();
      final id = SleepPersonalRecordEvent.createId(
        metric: metric,
        value: value,
        achievedAt: date,
        sessionId: sessionId,
      );
      try {
        events.add(SleepPersonalRecordEvent.fromMap({
          'id': id,
          'metric': metric,
          'value': value,
          'achievedAt': date.toUtc().toIso8601String(),
          'sessionId': sessionId,
        }));
      } on FormatException {
        // Do not invent a date or store an invalid best value.
      }
    }

    add('longestSleepMinutes', records.longestSleepMinutes,
        records.longestSleepAt, records.longestSleepSessionId);
    add('bestSleepScore', records.bestSleepScore,
        records.bestSleepScoreAt, records.bestSleepScoreSessionId);
    add('bestEfficiencyPercent', records.bestEfficiencyPercent,
        records.bestEfficiencyAt, records.bestEfficiencySessionId);
    add('fewestAwakenings', records.fewestAwakenings,
        records.fewestAwakeningsAt, records.fewestAwakeningsSessionId);
    return _sorted(events);
  }

  static List<SleepPersonalRecordEvent> improvements({
    required SleepPersonalRecords current,
    required SleepPersonalRecords previous,
  }) {
    final events = <SleepPersonalRecordEvent>[];
    void addIfBetter({
      required String metric,
      required num? currentValue,
      required num? previousValue,
      required DateTime? achievedAt,
      String? sessionId,
      bool lowerIsBetter = false,
    }) {
      if (currentValue == null || achievedAt == null) return;
      final better = previousValue == null ||
          (lowerIsBetter
              ? currentValue < previousValue
              : currentValue > previousValue);
      if (!better) return;
      final value = currentValue.toDouble();
      events.add(SleepPersonalRecordEvent(
        id: SleepPersonalRecordEvent.createId(
          metric: metric,
          value: value,
          achievedAt: achievedAt,
          sessionId: sessionId,
        ),
        metric: metric,
        value: value,
        achievedAt: achievedAt,
        sessionId: sessionId,
      ));
    }

    addIfBetter(
      metric: 'longestSleepMinutes',
      currentValue: current.longestSleepMinutes,
      previousValue: previous.longestSleepMinutes,
      achievedAt: current.longestSleepAt,
      sessionId: current.longestSleepSessionId,
    );
    addIfBetter(
      metric: 'bestSleepScore',
      currentValue: current.bestSleepScore,
      previousValue: previous.bestSleepScore,
      achievedAt: current.bestSleepScoreAt,
      sessionId: current.bestSleepScoreSessionId,
    );
    addIfBetter(
      metric: 'bestEfficiencyPercent',
      currentValue: current.bestEfficiencyPercent,
      previousValue: previous.bestEfficiencyPercent,
      achievedAt: current.bestEfficiencyAt,
      sessionId: current.bestEfficiencySessionId,
    );
    addIfBetter(
      metric: 'fewestAwakenings',
      currentValue: current.fewestAwakenings,
      previousValue: previous.fewestAwakenings,
      achievedAt: current.fewestAwakeningsAt,
      sessionId: current.fewestAwakeningsSessionId,
      lowerIsBetter: true,
    );
    return _sorted(events);
  }

  static SleepPersonalRecords? bestRecords(
    List<SleepPersonalRecordEvent> events,
  ) {
    if (events.isEmpty) return null;
    final best = <String, SleepPersonalRecordEvent>{};
    for (final event in events) {
      final previous = best[event.metric];
      if (previous == null) {
        best[event.metric] = event;
        continue;
      }
      final better = event.metric == 'shortestLatencyMinutes' ||
              event.metric == 'fewestAwakenings'
          ? event.value < previous.value
          : event.value > previous.value;
      if (better) best[event.metric] = event;
    }
    return SleepPersonalRecords(
      longestSleepMinutes: best['longestSleepMinutes']?.value.round(),
      longestSleepSessionId: best['longestSleepMinutes']?.sessionId,
      longestSleepAt: best['longestSleepMinutes']?.achievedAt,
      bestSleepScore: best['bestSleepScore']?.value.round(),
      bestSleepScoreSessionId: best['bestSleepScore']?.sessionId,
      bestSleepScoreAt: best['bestSleepScore']?.achievedAt,
      bestEfficiencyPercent: best['bestEfficiencyPercent']?.value,
      bestEfficiencySessionId: best['bestEfficiencyPercent']?.sessionId,
      bestEfficiencyAt: best['bestEfficiencyPercent']?.achievedAt,
      fewestAwakenings: best['fewestAwakenings']?.value.round(),
      fewestAwakeningsSessionId: best['fewestAwakenings']?.sessionId,
      fewestAwakeningsAt: best['fewestAwakenings']?.achievedAt,
      shortestLatencyMinutes: best['shortestLatencyMinutes']?.value.round(),
      shortestLatencySessionId: best['shortestLatencyMinutes']?.sessionId,
      shortestLatencyAt: best['shortestLatencyMinutes']?.achievedAt,
      longestStreakDays: best['longestStreakDays']?.value.round() ?? 0,
      longestStreakAt: best['longestStreakDays']?.achievedAt,
    );
  }

  static List<SleepPersonalRecordEvent> merge(
    Iterable<SleepPersonalRecordEvent> local,
    Iterable<SleepPersonalRecordEvent> imported,
  ) {
    final byId = <String, SleepPersonalRecordEvent>{};
    for (final event in [...local, ...imported]) {
      byId.putIfAbsent(event.id, () => event);
    }
    return _sorted(byId.values);
  }

  static List<SleepPersonalRecordEvent> _sorted(
    Iterable<SleepPersonalRecordEvent> events,
  ) => events.toList()
    ..sort((a, b) {
      final date = a.achievedAt.compareTo(b.achievedAt);
      if (date != 0) return date;
      return a.metric.compareTo(b.metric);
    });
}
