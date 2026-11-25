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
    final days = valid.map((session) {
      final date = session.startedAt.toLocal();
      return DateTime(date.year, date.month, date.day);
    }).toSet().toList()
      ..sort();

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
        if (valid.length < achievement.completedNights) continue;
        earnedDates.add(
          valid[achievement.completedNights - 1].startedAt.toLocal(),
        );
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
  });

  final Map<String, DateTime> earnedAt;
  final bool displayEnabled;
  final SleepPersonalRecords records;
  final Set<String> newRecordKeys;
  final List<SleepPersonalRecordEvent> recordHistory;
}

class SleepAchievementService {
  SleepAchievementService._();

  static final instance = SleepAchievementService._();
  static const _historyKey = 'sleep_achievements_history_v1';
  static const _displayKey = 'sleep_achievements_display_enabled';
  static const _recordsKey = 'sleep_personal_records_v1';
  static const _recordHistoryKey = SleepPersonalRecordHistory.metadataKey;

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
    final calculatedRecords = SleepPersonalRecords.calculate(
      sessions: validSessions,
      stagesBySession: stages,
    );

    final recordsRaw = await database.getAppMetadata(_recordsKey);
    SleepPersonalRecords? previousRecords;
    if (recordsRaw != null) {
      try {
        final decoded = jsonDecode(recordsRaw);
        if (decoded is Map) {
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
    final historyBest = SleepPersonalRecordHistory.bestRecords(recordHistory);
    final recordBaseline = previousRecords == null
        ? historyBest
        : historyBest == null
            ? previousRecords
            : historyBest.preserveBest(previousRecords);

    final newRecordKeys = <String>{};
    if (recordBaseline != null) {
      if (calculatedRecords.longestSleepMinutes != null &&
          (recordBaseline.longestSleepMinutes == null ||
              calculatedRecords.longestSleepMinutes! >
                  recordBaseline.longestSleepMinutes!)) {
        newRecordKeys.add('longestSleep');
      }
      if (calculatedRecords.bestEfficiencyPercent != null &&
          (recordBaseline.bestEfficiencyPercent == null ||
              calculatedRecords.bestEfficiencyPercent! >
                  recordBaseline.bestEfficiencyPercent!)) {
        newRecordKeys.add('bestEfficiency');
      }
      if (calculatedRecords.shortestLatencyMinutes != null &&
          (recordBaseline.shortestLatencyMinutes == null ||
              calculatedRecords.shortestLatencyMinutes! <
                  recordBaseline.shortestLatencyMinutes!)) {
        newRecordKeys.add('shortestLatency');
      }
      if (calculatedRecords.longestStreakDays >
          recordBaseline.longestStreakDays) {
        newRecordKeys.add('longestStreak');
      }
    }

    // Seed a baseline once, then append only genuine improvements. This keeps
    // the four approved records' history without adding history for excluded
    // SleepScore/awakening metrics.
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
    return SleepAchievementState(
      earnedAt: {
        for (final entry in history.entries)
          entry.key: DateTime.parse(entry.value).toLocal(),
      },
      displayEnabled: enabled,
      records: records,
      newRecordKeys: newRecordKeys,
      recordHistory: recordHistory,
    );
  }

  Future<void> setDisplayEnabled(bool enabled) =>
      SleepDatabase.instance.setAppMetadata(_displayKey, enabled.toString());
}
