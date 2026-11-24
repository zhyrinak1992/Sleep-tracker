import 'dart:convert';

import '../../data/sleep_database.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_score.dart';

class SleepRecordEvent {
  const SleepRecordEvent({
    required this.type,
    required this.sessionId,
    required this.value,
    required this.achievedAt,
  });

  final String type;
  final String sessionId;
  final num value;
  final DateTime achievedAt;

  Map<String, Object?> toMap() => {
    'type': type,
    'sessionId': sessionId,
    'value': value,
    'achievedAt': achievedAt.toUtc().toIso8601String(),
  };

  static SleepRecordEvent? fromMap(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final type = value['type'];
    final sessionId = value['sessionId'];
    final recordValue = value['value'];
    final date = value['achievedAt'];
    if ((type != 'sleep_score' && type != 'awakening_count') ||
        sessionId is! String || sessionId.trim().isEmpty ||
        recordValue is! num || !recordValue.isFinite ||
        recordValue < 0 || recordValue % 1 != 0 ||
        (type == 'sleep_score' && recordValue > 100) ||
        date is! String) {
      return null;
    }
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) return null;
    return SleepRecordEvent(
      type: type,
      sessionId: sessionId,
      // Both supported record types are integer metrics. Normalizing here
      // keeps event keys stable across JSON encoders (95 and 95.0).
      value: recordValue.toInt(),
      achievedAt: parsedDate.toLocal(),
    );
  }
}


class SleepRecordHistoryDecode {
  const SleepRecordHistoryDecode({
    required this.events,
    required this.needsRewrite,
  });

  final List<SleepRecordEvent> events;
  final bool needsRewrite;
}

int _compareSleepRecordChronology(
  SleepRecordEvent a,
  SleepRecordEvent b,
) {
  final byDate = a.achievedAt.compareTo(b.achievedAt);
  return byDate != 0 ? byDate : a.sessionId.compareTo(b.sessionId);
}

/// Rebuilds the sequence of personal records from the current source data.
/// A session contributes at most one candidate per metric; corrected or
/// deleted sessions therefore cannot leave stale record events behind.
List<SleepRecordEvent> findNewSleepRecordEvents({
  required List<SleepRecordEvent> previousHistory,
  required List<SleepRecordEvent> currentHistory,
  required Set<String> celebratedKeys,
  required bool isFirstInitialization,
}) {
  if (isFirstInitialization) return const [];

  String key(SleepRecordEvent event) =>
      '${event.type}|${event.sessionId}|${event.value}';
  String sessionMetric(SleepRecordEvent event) =>
      '${event.type}|${event.sessionId}';

  final previousKeys = previousHistory.map(key).toSet();
  final previousSessionMetrics = previousHistory.map(sessionMetric).toSet();
  final previousLatestByType = <String, SleepRecordEvent>{};
  for (final event in previousHistory) {
    final current = previousLatestByType[event.type];
    if (current == null || _compareSleepRecordChronology(event, current) > 0) {
      previousLatestByType[event.type] = event;
    }
  }

  final result = <SleepRecordEvent>[];
  for (final event in currentHistory) {
    final eventKey = key(event);
    if (celebratedKeys.contains(eventKey)) continue;

    // A persisted but unacknowledged event is a pending celebration. This
    // recovers correctly after the app closes before its dialog is dismissed.
    final wasPending = previousKeys.contains(eventKey);
    final isNewerRecord = !previousKeys.contains(eventKey) &&
        !previousSessionMetrics.contains(sessionMetric(event)) &&
        (previousLatestByType[event.type] == null ||
            _compareSleepRecordChronology(
              event,
              previousLatestByType[event.type]!,
            ) > 0);

    if (wasPending || isNewerRecord) result.add(event);
  }
  return List.unmodifiable(result);
}

List<SleepRecordEvent> buildSleepRecordHistory(
  Iterable<SleepRecordEvent> candidates,
) {
  final ordered = candidates.toList()
    ..sort(_compareSleepRecordChronology);

  final history = <SleepRecordEvent>[];
  final seenSessions = <String>{};
  num? bestScore;
  int? fewestAwakenings;

  for (final event in ordered) {
    final sessionMetric = '${event.type}|${event.sessionId}';
    if (!seenSessions.add(sessionMetric)) continue;

    if (event.type == 'sleep_score') {
      if (bestScore == null || event.value > bestScore) {
        history.add(event);
        bestScore = event.value;
      }
    } else if (event.type == 'awakening_count') {
      final value = event.value.toInt();
      if (fewestAwakenings == null || value < fewestAwakenings) {
        history.add(event);
        fewestAwakenings = value;
      }
    }
  }

  return List.unmodifiable(history);
}

List<SleepRecordEvent> retainDeletedNightRecordEvents({
  required Iterable<SleepRecordEvent> previousHistory,
  required Set<String> activeSessionIds,
}) => List.unmodifiable(
  previousHistory.where((event) => !activeSessionIds.contains(event.sessionId)),
);

class SleepRecordState {
  const SleepRecordState({required this.history, this.newRecords = const []});

  final List<SleepRecordEvent> history;
  final List<SleepRecordEvent> newRecords;

  SleepRecordEvent? get bestSleepScore {
    final values = history.where((item) => item.type == 'sleep_score');
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a.value >= b.value ? a : b);
  }

  SleepRecordEvent? get fewestAwakenings {
    final values = history.where((item) => item.type == 'awakening_count');
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a.value <= b.value ? a : b);
  }
}

class SleepRecordService {
  SleepRecordService._();

  static final instance = SleepRecordService._();
  static const _historyKey = 'sleep_records_history_v1';
  static const _celebratedKey = 'sleep_records_celebrated_v1';

  // Only one celebration dialog may be visible across mounted cards/screens.
  static String? _activeCelebration;

  bool tryClaimCelebration(SleepRecordEvent event) {
    if (_activeCelebration != null) return false;
    _activeCelebration = _eventKey(event);
    return true;
  }

  void releaseCelebration(SleepRecordEvent event) {
    if (_activeCelebration == _eventKey(event)) _activeCelebration = null;
  }

  String _eventKey(SleepRecordEvent event) =>
      '${event.type}|${event.sessionId}|${event.value}';

  /// Decodes persisted history and reports whether its representation needs
  /// repairing. Invalid entries are discarded without touching source sleep data.
  static SleepRecordHistoryDecode decodePersistedHistory(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const SleepRecordHistoryDecode(events: [], needsRewrite: true);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const SleepRecordHistoryDecode(events: [], needsRewrite: true);
      }

      final events = <SleepRecordEvent>[];
      final seen = <String>{};
      var needsRewrite = false;
      for (final item in decoded) {
        final event = SleepRecordEvent.fromMap(item);
        if (event == null) {
          needsRewrite = true;
          continue;
        }
        final key = '${event.type}|${event.sessionId}|${event.value}';
        if (!seen.add(key)) {
          needsRewrite = true;
          continue;
        }
        events.add(event);
      }
      return SleepRecordHistoryDecode(
        events: List.unmodifiable(events),
        needsRewrite: needsRewrite,
      );
    } on FormatException {
      return const SleepRecordHistoryDecode(events: [], needsRewrite: true);
    }
  }

  Future<bool> isCelebrated(SleepRecordEvent event) async {
    final raw = await SleepDatabase.instance.getAppMetadata(_celebratedKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List && decoded.whereType<String>().contains(_eventKey(event));
    } on FormatException {
      return false;
    }
  }

  static bool _sameHistory(
    List<SleepRecordEvent> previous,
    List<SleepRecordEvent> current,
  ) {
    if (previous.length != current.length) return false;
    final previousByKey = {
      for (final event in previous)
        _eventKeyForComparison(event): event.achievedAt.toUtc().toIso8601String(),
    };
    for (final event in current) {
      if (previousByKey[_eventKeyForComparison(event)] !=
          event.achievedAt.toUtc().toIso8601String()) {
        return false;
      }
    }
    return true;
  }

  static String _eventKeyForComparison(SleepRecordEvent event) =>
      '${event.type}|${event.sessionId}|${event.value}';

  Future<void> markCelebrated(SleepRecordEvent event) async {
    final database = SleepDatabase.instance;
    final raw = await database.getAppMetadata(_celebratedKey);
    final keys = <String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) keys.addAll(decoded.whereType<String>());
      } on FormatException {
        // Rebuild the marker list if metadata is malformed.
      }
    }
    keys.add(_eventKey(event));
    await database.setAppMetadata(_celebratedKey, jsonEncode(keys.toList()));
  }

  /// Calculates records from source sleep data and persists only record events
  /// in app_metadata. Existing sleep tables and backup schema remain unchanged.
  Future<SleepRecordState> load() async {
    final database = SleepDatabase.instance;
    final allSessions = await database.getSessions(limit: 10000);
    final sessions = allSessions
        .where((session) =>
            session.deletedAt == null &&
            session.endedAt != null &&
            session.duration != null &&
            session.duration!.inMinutes > 0)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    // A soft-deleted session is absent from the active source set even though
    // its SQLite row remains in the recycle bin. Keep its earned record event.
    final activeSessionIds = sessions.map((session) => session.id).toSet();

    final ids = sessions.map((item) => item.id).toList(growable: false);
    final stagesBySession = await database.getStagesForSessions(ids);
    final morningReports = await database.getMorningReportsForSessions(ids);

    final raw = await database.getAppMetadata(_historyKey);
    final isFirstInitialization = raw == null || raw.isEmpty;
    final celebratedRaw = await database.getAppMetadata(_celebratedKey);
    final celebratedKeys = <String>{};
    if (celebratedRaw != null && celebratedRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(celebratedRaw);
        if (decoded is List) celebratedKeys.addAll(decoded.whereType<String>());
      } on FormatException {
        // An invalid celebration marker must not affect sleep data.
      }
    }
    final decodedHistory = decodePersistedHistory(raw);
    final previousHistory = decodedHistory.events;
    // If metadata is unreadable and yielded no usable events, treat the
    // reconstructed timeline as a baseline rather than replaying years of
    // historical congratulations after repairing the metadata.
    final isBaselineInitialization = isFirstInitialization ||
        (decodedHistory.needsRewrite && previousHistory.isEmpty);
    final candidates = <SleepRecordEvent>[];
    for (final session in sessions) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final score = SleepScoreCalculator.calculateForSession(
        session: session,
        historySessions: sessions,
        morningReports: morningReports,
        stagesBySession: stagesBySession,
      ).score;
      if (score != null) {
        candidates.add(SleepRecordEvent(
          type: 'sleep_score',
          sessionId: session.id,
          value: score.round(),
          achievedAt: session.endedAt!,
        ));
      }

      final metrics = SleepSessionMetrics.calculate(
        session: session,
        stages: stages,
      );
      final hasAwakeSamples = stages.any((row) {
        final stage = (row['stage'] as String? ?? '').toLowerCase();
        return stage.contains('бодрств') || stage.contains('awake');
      });
      final awakeningsAreReliable = hasAwakeSamples &&
          metrics.stageCoveragePercent != null &&
          metrics.stageCoveragePercent! >= 80;
      if (awakeningsAreReliable) {
        candidates.add(SleepRecordEvent(
          type: 'awakening_count',
          sessionId: session.id,
          value: metrics.awakeningCount,
          achievedAt: session.endedAt!,
        ));
      }
    }

    // Preserve earned events if their source night has been deleted.
    // Existing sessions are still recalculated, so correction behavior is unchanged.
    final deletedNightEvents = retainDeletedNightRecordEvents(
      previousHistory: previousHistory,
      activeSessionIds: activeSessionIds,
    );
    final history = buildSleepRecordHistory([
      ...candidates,
      ...deletedNightEvents,
    ]);
    final historyChanged = decodedHistory.needsRewrite ||
        !_sameHistory(previousHistory, history);

    // Recover unacknowledged persisted events as well as genuinely newer
    // records; corrected or promoted historical nights are not celebrated.
    final newRecords = findNewSleepRecordEvents(
      previousHistory: previousHistory,
      currentHistory: history,
      celebratedKeys: celebratedKeys,
      isFirstInitialization: isBaselineInitialization,
    );

    // On the first run, existing sleep history is a baseline, not a stream
    // of new achievements. Persist its acknowledgement before the history
    // marker so concurrent loads cannot mistake the baseline for new records.
    if (isBaselineInitialization && history.isNotEmpty) {
      celebratedKeys.addAll(history.map(_eventKey));
      await database.setAppMetadata(
        _celebratedKey,
        jsonEncode(celebratedKeys.toList()),
      );
    }

    if (historyChanged) {
      // Persist the rebuilt timeline, including an empty history after all
      // qualifying source sessions have been removed or corrected.
      await database.setAppMetadata(
        _historyKey,
        jsonEncode(history.map((item) => item.toMap()).toList()),
      );
    }

    return SleepRecordState(
      history: List.unmodifiable(history),
      newRecords: List.unmodifiable(newRecords),
    );
  }

}
