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
        sessionId is! String || sessionId.isEmpty ||
        recordValue is! num || !recordValue.isFinite ||
        date is! String) return null;
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) return null;
    return SleepRecordEvent(
      type: type,
      sessionId: sessionId,
      value: recordValue,
      achievedAt: parsedDate.toLocal(),
    );
  }
}

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

  String _eventKey(SleepRecordEvent event) =>
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
    final sessions = (await database.getSessions(limit: 10000))
        .where((session) =>
            session.deletedAt == null &&
            session.endedAt != null &&
            session.duration != null &&
            session.duration!.inMinutes > 0)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

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
    final history = <SleepRecordEvent>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final event = SleepRecordEvent.fromMap(item);
            if (event != null) history.add(event);
          }
        }
      } on FormatException {
        // Invalid metadata is ignored; sleep records remain untouched.
      }
    }

    // Recover pending celebrations from persisted history. A process may be
    // closed after saving a record but before its dialog is displayed.
    final newRecords = <SleepRecordEvent>[
      if (!isFirstInitialization)
        ...history.where((event) => !celebratedKeys.contains(_eventKey(event))),
    ];
    final knownEvents = history.map(_eventKey).toSet();
    num? bestScore = history
        .where((item) => item.type == 'sleep_score')
        .fold<num?>(null, (best, item) =>
            best == null || item.value > best ? item.value : best);
    int? fewestAwakenings = history
        .where((item) => item.type == 'awakening_count')
        .fold<int?>(null, (best, item) =>
            best == null || item.value < best ? item.value.toInt() : best);

    for (final session in sessions) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final score = SleepScoreCalculator.calculateForSession(
        session: session,
        historySessions: sessions,
        morningReports: morningReports,
        stagesBySession: stagesBySession,
      ).score;
      if (score != null) {
        final value = score.round();
        final eventKey = 'sleep_score|${session.id}|$value';
        if ((bestScore == null || value > bestScore) &&
            !knownEvents.contains(eventKey)) {
          final event = SleepRecordEvent(
            type: 'sleep_score',
            sessionId: session.id,
            value: value,
            achievedAt: session.endedAt!,
          );
          history.add(event);
          if (!isFirstInitialization && !celebratedKeys.contains(eventKey)) {
            newRecords.add(event);
          }
          knownEvents.add(eventKey);
          bestScore = value;
        }
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
        final value = metrics.awakeningCount;
        final eventKey = 'awakening_count|${session.id}|$value';
        if ((fewestAwakenings == null || value < fewestAwakenings) &&
            !knownEvents.contains(eventKey)) {
          final event = SleepRecordEvent(
            type: 'awakening_count',
            sessionId: session.id,
            value: value,
            achievedAt: session.endedAt!,
          );
          history.add(event);
          if (!isFirstInitialization && !celebratedKeys.contains(eventKey)) {
            newRecords.add(event);
          }
          knownEvents.add(eventKey);
          fewestAwakenings = value;
        }
      }
    }

    if (history.isNotEmpty && history.length !=
        (raw == null || raw.isEmpty ? 0 : _decodedEventCount(raw))) {
      await database.setAppMetadata(
        _historyKey,
        jsonEncode(history.map((item) => item.toMap()).toList()),
      );
    }

    // On the first run, existing sleep history is a baseline, not a stream
    // of new achievements. Mark that baseline as already celebrated.
    if (isFirstInitialization && history.isNotEmpty) {
      celebratedKeys.addAll(history.map(_eventKey));
      await database.setAppMetadata(
        _celebratedKey,
        jsonEncode(celebratedKeys.toList()),
      );
    }

    return SleepRecordState(
      history: List.unmodifiable(history),
      newRecords: List.unmodifiable(newRecords),
    );
  }

  int _decodedEventCount(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.map(SleepRecordEvent.fromMap).whereType<SleepRecordEvent>().length
          : 0;
    } on FormatException {
      return 0;
    }
  }
}
