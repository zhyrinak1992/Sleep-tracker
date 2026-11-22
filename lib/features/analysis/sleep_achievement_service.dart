import 'dart:convert';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';

class SleepAchievementDefinition {
  const SleepAchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.completedNights = 0,
    this.morningRatings = 0,
  });

  final String id;
  final String title;
  final String description;
  final int completedNights;
  final int morningRatings;
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

    return achievements.where((achievement) {
      final nightReached = achievement.completedNights == 0 ||
          valid.length >= achievement.completedNights;
      final ratingReached = achievement.morningRatings == 0 ||
          rated >= achievement.morningRatings;
      return nightReached && ratingReached;
    }).map((achievement) => achievement.id).toSet();
  }
}

class SleepAchievementState {
  const SleepAchievementState({
    required this.earnedAt,
    required this.displayEnabled,
  });

  final Map<String, DateTime> earnedAt;
  final bool displayEnabled;
}

class SleepAchievementService {
  SleepAchievementService._();

  static final instance = SleepAchievementService._();
  static const _historyKey = 'sleep_achievements_history_v1';
  static const _displayKey = 'sleep_achievements_display_enabled';

  Future<SleepAchievementState> load(Iterable<SleepSession> sessions) async {
    final database = SleepDatabase.instance;
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

    var changed = false;
    final earnedNow = SleepAchievementCatalog.evaluate(sessions);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final id in earnedNow) {
      if (!history.containsKey(id)) {
        history[id] = now;
        changed = true;
      }
    }
    if (changed || (raw != null && history.isEmpty)) {
      await database.setAppMetadata(_historyKey, jsonEncode(history));
    }

    final enabled = await database.getAppMetadata(_displayKey) != 'false';
    return SleepAchievementState(
      earnedAt: {
        for (final entry in history.entries)
          entry.key: DateTime.parse(entry.value).toLocal(),
      },
      displayEnabled: enabled,
    );
  }

  Future<void> setDisplayEnabled(bool enabled) =>
      SleepDatabase.instance.setAppMetadata(_displayKey, enabled.toString());
}
