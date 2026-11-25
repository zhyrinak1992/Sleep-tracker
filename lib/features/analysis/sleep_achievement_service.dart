import 'dart:convert';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import 'sleep_personal_records.dart';

class SleepAchievementDefinition {
  const SleepAchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.completedNights = 0,
    this.morningRatings = 0,
    this.streakDays = 0,
  });

  final String id;
  final String title;
  final String description;
  final int completedNights;
  final int morningRatings;
  final int streakDays;
}

class SleepAchievementCatalog {
  static const achievements = <SleepAchievementDefinition>[
    SleepAchievementDefinition(id: 'first_night', title: 'Первая ночь', description: 'В истории появилась первая завершённая ночь.', completedNights: 1),
    SleepAchievementDefinition(id: 'seven_nights', title: 'Семь ночей', description: 'Сохранено семь завершённых ночей.', completedNights: 7),
    SleepAchievementDefinition(id: 'thirty_nights', title: 'Месяц истории', description: 'В истории накоплено 30 завершённых ночей.', completedNights: 30),
    SleepAchievementDefinition(id: 'hundred_nights', title: '100 ночей', description: 'В истории накоплено 100 завершённых ночей.', completedNights: 100),
    SleepAchievementDefinition(id: 'three_hundred_sixty_five_nights', title: '365 ночей', description: 'В истории накоплено 365 завершённых ночей.', completedNights: 365),
    SleepAchievementDefinition(id: 'first_rating', title: 'Первая оценка', description: 'Сохранена первая утренняя оценка.', morningRatings: 1),
    SleepAchievementDefinition(id: 'ten_ratings', title: 'Десять оценок', description: 'Сохранено десять утренних оценок.', morningRatings: 10),
    SleepAchievementDefinition(id: 'streak_three', title: 'Три дня подряд', description: 'В дневнике есть записи за три календарных дня подряд.', streakDays: 3),
    SleepAchievementDefinition(id: 'streak_seven', title: 'Неделя регулярности', description: 'В дневнике есть записи за семь календарных дней подряд.', streakDays: 7),
    SleepAchievementDefinition(id: 'streak_fourteen', title: 'Две недели регулярности', description: 'В дневнике есть записи за 14 календарных дней подряд.', streakDays: 14),
    SleepAchievementDefinition(id: 'streak_thirty', title: 'Месяц регулярности', description: 'В дневнике есть записи за 30 календарных дней подряд.', streakDays: 30),
  ];

  static Set<String> evaluate(Iterable<SleepSession> sessions) =>
      evaluateDates(sessions).keys.toSet();

  /// Returns the calendar date on which each achievement was first reached.
  /// Existing history is retained by the service, so later deletion of a
  /// source night cannot revoke an already earned achievement.
  static Map<String, DateTime> evaluateDates(
    Iterable<SleepSession> sessions,
  ) {
    final valid = sessions.where((session) {
      final duration = session.duration;
      return session.deletedAt == null &&
          session.endedAt != null &&
          duration != null &&
          duration.inMinutes > 0;
    }).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final rated = valid
        .where((session) => session.morningRating != null)
        .toList(growable: false);
    final nightDates = valid.map((session) {
      final date = session.startedAt.toLocal();
      return DateTime(date.year, date.month, date.day);
    }).toSet().toList()
      ..sort();
    final days = nightDates;

    DateTime? firstStreakDate(int target) {
      if (days.length < target) return null;
      var streak = 1;
      for (var i = 1; i < days.length; i++) {
        final previous = DateTime.utc(
          days[i - 1].year, days[i - 1].month, days[i - 1].day,
        );
        final current = DateTime.utc(
          days[i].year, days[i].month, days[i].day,
        );
        if (current.difference(previous).inDays == 1) {
          streak++;
        } else {
          streak = 1;
        }
        if (streak >= target) return days[i];
      }
      return null;
    }

    final result = <String, DateTime>{};
    for (final achievement in achievements) {
      final earnedDates = <DateTime>[];
      if (achievement.completedNights > 0) {
        if (nightDates.length < achievement.completedNights) continue;
        earnedDates.add(nightDates[achievement.completedNights - 1]);
      }
      if (achievement.morningRatings > 0) {
        if (rated.length < achievement.morningRatings) continue;
        earnedDates.add(
          rated[achievement.morningRatings - 1].startedAt.toLocal(),
        );
      }
      if (achievement.streakDays > 0) {
        final date = firstStreakDate(achievement.streakDays);
        if (date == null) continue;
        earnedDates.add(date);
      }
      if (earnedDates.isEmpty) continue;
      result[achievement.id] = earnedDates.reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );
    }
    return result;
  }
}

class SleepAchievementState {
  const SleepAchievementState({
    required this.earnedAt,
    required this.displayEnabled,
    required this.records,
    required this.newRecordKeys,
    required this.recordHistory,
    required this.pendingRecordEvents,
  });

  final Map<String, DateTime> earnedAt;
  final bool displayEnabled;
  final SleepPersonalRecords records;
  final Set<String> newRecordKeys;
  final List<SleepPersonalRecordEvent> recordHistory;
  final List<SleepPersonalRecordEvent> pendingRecordEvents;
}

class SleepAchievementService {
  SleepAchievementService._();

  static final instance = SleepAchievementService._();
  static const _historyKey = 'sleep_achievements_history_v1';
  static const _displayKey = 'sleep_achievements_display_enabled';
  static const _recordsKey = 'sleep_personal_records_v1';
  static const _recordHistoryKey = SleepPersonalRecordHistory.metadataKey;
  static const _recordCelebratedKey = 'sleep_personal_records_celebrated_v1';
  static String? _activeRecordCelebrationId;

  Future<SleepAchievementState> load(Iterable<SleepSession> sessions) async {
    final database = SleepDatabase.instance;
    final sessionList = sessions.toList(growable: false);
    final raw = await database.getAppMetadata(_historyKey);
    final history = <String, String>{};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            if (entry.value is String &&
                DateTime.tryParse(entry.value as String) != null) {
              history[entry.key] = entry.value as String;
            }
          }
        }
      } on FormatException {
        // Damaged metadata must not affect sleep records or app startup.
      }
    }
    // A structurally valid but empty/fully-invalid map is not evidence that
    // achievements were previously initialized. Treat it as a baseline so
    // restoring or repairing partial metadata cannot replay old celebrations.

    var changed = false;
    final earnedDates = SleepAchievementCatalog.evaluateDates(sessionList);
    for (final entry in earnedDates.entries) {
      final previous = DateTime.tryParse(history[entry.key] ?? '');
      if (previous == null || entry.value.isBefore(previous.toLocal())) {
        history[entry.key] = entry.value.toUtc().toIso8601String();
        changed = true;
      }
    }
    if (changed || (raw != null && history.isEmpty)) {
      await database.setAppMetadata(_historyKey, jsonEncode(history));
    }

    final validSessions = sessionList.where((session) =>
        session.deletedAt == null &&
        session.endedAt != null &&
        session.duration != null &&
        session.duration!.inMinutes > 0).toList(growable: false);
    final stages = await database.getStagesForSessions(
      validSessions.map((session) => session.id).toList(),
    );
    final morningReports = await database.getMorningReportsForSessions(
      validSessions.map((session) => session.id).toList(),
    );
    final calculatedRecords = SleepPersonalRecords.calculate(
      sessions: validSessions,
      stagesBySession: stages,
      morningReports: morningReports,
    );

    final recordsRaw = await database.getAppMetadata(_recordsKey);
    SleepPersonalRecords? previousRecords;
    var previousRecordSchemaVersion = 0;
    if (recordsRaw != null) {
      try {
        final decoded = jsonDecode(recordsRaw);
        if (decoded is Map) {
          final rawVersion = decoded['recordSchemaVersion'];
          if (rawVersion is int) previousRecordSchemaVersion = rawVersion;
          previousRecords = SleepPersonalRecords.fromMap(
            Map<String, Object?>.from(decoded),
          );
        }
      } on FormatException {
        // Rebuild damaged derived metadata from source sleep records.
      } on TypeError {
        // Rebuild malformed derived metadata without touching sleep records.
      }
    }
    final recordHistoryRaw = await database.getAppMetadata(_recordHistoryKey);
    var recordHistory = <SleepPersonalRecordEvent>[];
    if (recordHistoryRaw != null) {
      try {
        recordHistory = SleepPersonalRecordHistory.decode(recordHistoryRaw);
      } on FormatException {
        // Rebuild damaged history from the persisted bests/source records.
      }
    }
    // Migrate the earlier SleepScore/awakening record stream into the unified
    // dated history. The legacy key remains supported by backup merging.
    final legacyRecordHistoryRaw = await database.getAppMetadata('sleep_records_history_v1');
    final isFirstRecordInitialization = recordsRaw == null &&
        recordHistoryRaw == null && legacyRecordHistoryRaw == null;
    if (legacyRecordHistoryRaw != null && legacyRecordHistoryRaw.isNotEmpty) {
      try {
        final decodedLegacy = jsonDecode(legacyRecordHistoryRaw);
        if (decodedLegacy is List) {
          final migrated = <SleepPersonalRecordEvent>[];
          for (final item in decodedLegacy) {
            if (item is! Map) continue;
            final type = item['type'];
            final metric = type == 'sleep_score'
                ? 'bestSleepScore'
                : type == 'awakening_count'
                    ? 'fewestAwakenings'
                    : null;
            final sessionId = item['sessionId'];
            final value = item['value'];
            final rawDate = item['achievedAt'];
            final date = rawDate is String ? DateTime.tryParse(rawDate) : null;
            if (metric == null || sessionId is! String || sessionId.isEmpty ||
                value is! num || date == null) continue;
            final normalized = value.toDouble();
            final id = SleepPersonalRecordEvent.createId(
              metric: metric,
              value: normalized,
              achievedAt: date,
              sessionId: sessionId,
            );
            try {
              migrated.add(SleepPersonalRecordEvent.fromMap({
                'id': id,
                'metric': metric,
                'value': normalized,
                'achievedAt': date.toUtc().toIso8601String(),
                'sessionId': sessionId,
              }));
            } on FormatException {
              // Ignore malformed legacy record events without losing other data.
            }
          }
          recordHistory = SleepPersonalRecordHistory.merge(recordHistory, migrated);
        }
      } on FormatException {
        // A damaged legacy history must not affect sleep records or startup.
      }
    }
    final hasApprovedHistory = recordHistory.any((event) =>
        event.metric == 'bestSleepScore' || event.metric == 'fewestAwakenings');
    final needsRecordBaselineMigration =
        (previousRecords != null && previousRecordSchemaVersion < 2) ||
        (previousRecords == null && recordHistoryRaw != null && !hasApprovedHistory) ||
        (previousRecords == null && legacyRecordHistoryRaw != null);
    final historyBest = SleepPersonalRecordHistory.bestRecords(recordHistory);
    final recordBaseline = previousRecords == null
        ? historyBest
        : historyBest == null
            ? previousRecords
            : historyBest.preserveBest(previousRecords);

    final newRecordKeys = <String>{};
    if (recordBaseline != null && !needsRecordBaselineMigration) {
      if (calculatedRecords.longestSleepMinutes != null &&
          (recordBaseline.longestSleepMinutes == null ||
              calculatedRecords.longestSleepMinutes! >
                  recordBaseline.longestSleepMinutes!)) {
        newRecordKeys.add('longestSleep');
      }
      if (!needsRecordBaselineMigration && calculatedRecords.bestSleepScore != null &&
          (recordBaseline.bestSleepScore == null ||
              calculatedRecords.bestSleepScore! > recordBaseline.bestSleepScore!)) {
        newRecordKeys.add('bestSleepScore');
      }
      if (calculatedRecords.bestEfficiencyPercent != null &&
          (recordBaseline.bestEfficiencyPercent == null ||
              calculatedRecords.bestEfficiencyPercent! >
                  recordBaseline.bestEfficiencyPercent!)) {
        newRecordKeys.add('bestEfficiency');
      }
      if (!needsRecordBaselineMigration && calculatedRecords.fewestAwakenings != null &&
          (recordBaseline.fewestAwakenings == null ||
              calculatedRecords.fewestAwakenings! < recordBaseline.fewestAwakenings!)) {
        newRecordKeys.add('fewestAwakenings');
      }
    }

    // Seed a baseline once, then append only genuine improvements for the
    // four approved records: duration, SleepScore, efficiency and awakenings.
    if (recordBaseline == null) {
      recordHistory = SleepPersonalRecordHistory.merge(
        recordHistory,
        SleepPersonalRecordHistory.fromRecords(calculatedRecords),
      );
    } else {
      recordHistory = SleepPersonalRecordHistory.merge(
        recordHistory,
        SleepPersonalRecordHistory.fromRecords(recordBaseline),
      );
      recordHistory = SleepPersonalRecordHistory.merge(
        recordHistory,
        SleepPersonalRecordHistory.improvements(
          current: calculatedRecords,
          previous: recordBaseline,
        ),
      );
    }
    final encodedRecordHistory = SleepPersonalRecordHistory.encode(recordHistory);
    if (recordHistoryRaw != encodedRecordHistory) {
      await database.setAppMetadata(_recordHistoryKey, encodedRecordHistory);
    }

    final records = recordBaseline == null
        ? calculatedRecords
        : calculatedRecords.preserveBest(recordBaseline);
    final encodedRecords = jsonEncode(records.toMap());
    if (recordsRaw != encodedRecords) {
      await database.setAppMetadata(_recordsKey, encodedRecords);
    }

    final enabled = await database.getAppMetadata(_displayKey) != 'false';
    final celebratedRaw = await database.getAppMetadata(_recordCelebratedKey);
    final celebratedIds = <String>{};
    if (celebratedRaw != null) {
      try {
        final decoded = jsonDecode(celebratedRaw);
        if (decoded is List) {
          celebratedIds.addAll(decoded.whereType<String>());
        }
      } on FormatException {
        // A malformed acknowledgement list must not affect record history.
      }
    }
    if (isFirstRecordInitialization || needsRecordBaselineMigration || !enabled || celebratedRaw == null) {
      celebratedIds.addAll(recordHistory.map((event) => event.id));
    }
    final encodedCelebrated = jsonEncode(celebratedIds.toList()..sort());
    if (celebratedRaw != encodedCelebrated) {
      await database.setAppMetadata(_recordCelebratedKey, encodedCelebrated);
    }
    final pendingRecordEvents = enabled
        ? recordHistory.where((event) =>
            const {
              'longestSleepMinutes',
              'bestSleepScore',
              'bestEfficiencyPercent',
              'fewestAwakenings',
            }.contains(event.metric) && !celebratedIds.contains(event.id)).toList()
        : const <SleepPersonalRecordEvent>[];
    return SleepAchievementState(
      earnedAt: {
        for (final entry in history.entries)
          entry.key: DateTime.parse(entry.value).toLocal(),
      },
      displayEnabled: enabled,
      records: records,
      newRecordKeys: newRecordKeys,
      recordHistory: recordHistory,
      pendingRecordEvents: pendingRecordEvents,
    );
  }

  Future<bool> isRecordCelebrated(SleepPersonalRecordEvent event) async {
    final raw = await SleepDatabase.instance.getAppMetadata(_recordCelebratedKey);
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List && decoded.whereType<String>().contains(event.id);
    } on FormatException {
      return false;
    }
  }

  Future<void> markRecordCelebrated(SleepPersonalRecordEvent event) async {
    final database = SleepDatabase.instance;
    final raw = await database.getAppMetadata(_recordCelebratedKey);
    final ids = <String>{};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) ids.addAll(decoded.whereType<String>());
      } on FormatException {
        // Replace malformed acknowledgement metadata with the current event.
      }
    }
    ids.add(event.id);
    await database.setAppMetadata(_recordCelebratedKey, jsonEncode(ids.toList()..sort()));
  }

  bool tryClaimRecordCelebration(SleepPersonalRecordEvent event) {
    if (_activeRecordCelebrationId != null) return false;
    _activeRecordCelebrationId = event.id;
    return true;
  }

  void releaseRecordCelebration(SleepPersonalRecordEvent event) {
    if (_activeRecordCelebrationId == event.id) _activeRecordCelebrationId = null;
  }

  Future<void> setDisplayEnabled(bool enabled) =>
      SleepDatabase.instance.setAppMetadata(_displayKey, enabled.toString());
}
