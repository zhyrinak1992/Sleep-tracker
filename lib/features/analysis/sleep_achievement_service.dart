import 'dart:convert';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import 'sleep_personal_records.dart';
import 'sleep_record_service.dart';

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

  static Set<String> evaluate(Iterable<SleepSession> sessions) {
    final valid = sessions.where((session) {
      final duration = session.duration;
      return session.deletedAt == null &&
          session.endedAt != null &&
          duration != null &&
          duration.inMinutes > 0;
    }).toList(growable: false);
    final rated = valid.where((session) => session.morningRating != null).length;
    final streak = SleepPersonalRecords.longestStreak(valid);

    return achievements.where((achievement) {
      final nightReached = achievement.completedNights == 0 ||
          valid.length >= achievement.completedNights;
      final ratingReached = achievement.morningRatings == 0 ||
          rated >= achievement.morningRatings;
      final streakReached = achievement.streakDays == 0 ||
          streak >= achievement.streakDays;
      return nightReached && ratingReached && streakReached;
    }).map((achievement) => achievement.id).toSet();
  }
}

class SleepAchievementState {
  const SleepAchievementState({
    required this.earnedAt,
    required this.displayEnabled,
    required this.records,
    required this.newlyEarnedAchievementIds,
    required this.newRecordKeys,
    required this.recordHistory,
  });

  final Map<String, DateTime> earnedAt;
  final bool displayEnabled;
  final SleepPersonalRecords records;
  final Set<String> newlyEarnedAchievementIds;
  final Set<String> newRecordKeys;
  final SleepRecordState recordHistory;
}

class SleepAchievementService {
  SleepAchievementService._();

  static final instance = SleepAchievementService._();
  static const _historyKey = 'sleep_achievements_history_v1';
  static const _displayKey = 'sleep_achievements_display_enabled';
  static const _recordsKey = 'sleep_personal_records_v1';

  Future<SleepAchievementState> load(Iterable<SleepSession> sessions) async {
    final database = SleepDatabase.instance;
    final sessionList = sessions.toList(growable: false);
    final raw = await database.getAppMetadata(_historyKey);
    final history = <String, String>{};
    var hasValidHistory = false;
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          hasValidHistory = true;
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

    final newlyEarned = <String>{};
    var changed = false;
    final earnedNow = SleepAchievementCatalog.evaluate(sessionList);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final id in earnedNow) {
      if (!history.containsKey(id)) {
        history[id] = now;
        if (hasValidHistory) newlyEarned.add(id);
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
    final newRecordKeys = <String>{};
    if (previousRecords != null) {
      if (calculatedRecords.longestSleepMinutes != null &&
          (previousRecords.longestSleepMinutes == null ||
              calculatedRecords.longestSleepMinutes! >
                  previousRecords.longestSleepMinutes!)) {
        newRecordKeys.add('longestSleep');
      }
      if (calculatedRecords.bestEfficiencyPercent != null &&
          (previousRecords.bestEfficiencyPercent == null ||
              calculatedRecords.bestEfficiencyPercent! >
                  previousRecords.bestEfficiencyPercent!)) {
        newRecordKeys.add('bestEfficiency');
      }
      if (calculatedRecords.shortestLatencyMinutes != null &&
          (previousRecords.shortestLatencyMinutes == null ||
              calculatedRecords.shortestLatencyMinutes! <
                  previousRecords.shortestLatencyMinutes!)) {
        newRecordKeys.add('shortestLatency');
      }
      if (calculatedRecords.longestStreakDays >
          previousRecords.longestStreakDays) {
        newRecordKeys.add('longestStreak');
      }
    }
    final records = previousRecords == null
        ? calculatedRecords
        : calculatedRecords.preserveBest(previousRecords);
    final encodedRecords = jsonEncode(records.toMap());
    if (recordsRaw != encodedRecords) {
      await database.setAppMetadata(_recordsKey, encodedRecords);
    }

    final enabled = await database.getAppMetadata(_displayKey) != 'false';
    // One screen load now coordinates achievements, four personal bests,
    // SleepScore/awakening history, and pending record celebrations.
    final recordHistory = await SleepRecordService.instance.load();
    return SleepAchievementState(
      earnedAt: {
        for (final entry in history.entries)
          entry.key: DateTime.parse(entry.value).toLocal(),
      },
      displayEnabled: enabled,
      records: records,
      newlyEarnedAchievementIds: newlyEarned,
      newRecordKeys: newRecordKeys,
      recordHistory: recordHistory,
    );
  }

  Future<void> setDisplayEnabled(bool enabled) =>
      SleepDatabase.instance.setAppMetadata(_displayKey, enabled.toString());
}
