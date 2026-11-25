import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_achievement_service.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

SleepSession _session({
  required int id,
  DateTime? endedAt,
  int? rating,
  DateTime? deletedAt,
}) {
  final start = DateTime(2026, 1, 1, 22).add(Duration(days: id));
  return SleepSession(
    id: '$id',
    startedAt: start,
    endedAt: endedAt ?? start.add(const Duration(hours: 8)),
    morningRating: rating,
    deletedAt: deletedAt,
  );
}

void main() {
  group('SleepAchievementCatalog.evaluate', () {
    test('unlocks night milestones only from completed positive sessions', () {
      final sessions = List.generate(7, (index) => _session(id: index));
      sessions.add(_session(id: 8, endedAt: null));
      sessions.add(_session(id: 9, endedAt: DateTime(2026, 1, 10, 21)));
      sessions.add(_session(id: 10, deletedAt: DateTime(2026, 2, 1)));

      final earned = SleepAchievementCatalog.evaluate(sessions);

      expect(earned, contains('first_night'));
      expect(earned, contains('seven_nights'));
      expect(earned, isNot(contains('thirty_nights')));
      expect(earned, isNot(contains('hundred_nights')));
    });

    test('rating milestones count only completed nights with a rating', () {
      final sessions = [
        _session(id: 1, rating: 4),
        _session(id: 2, rating: 5),
        _session(id: 3, rating: null),
        _session(id: 4, endedAt: null, rating: 5),
      ];

      final earned = SleepAchievementCatalog.evaluate(sessions);

      expect(earned, contains('first_rating'));
      expect(earned, isNot(contains('ten_ratings')));
    });

    test('unlocks regularity milestones using distinct consecutive calendar dates', () {
      final sessions = [
        _session(id: 1),
        _session(id: 2),
        _session(id: 3),
        _session(id: 4),
        _session(id: 5),
        _session(id: 6),
        _session(id: 7),
        _session(id: 8),
      ];

      final earned = SleepAchievementCatalog.evaluate(sessions);

      expect(earned, contains('streak_three'));
      expect(earned, contains('streak_seven'));
      expect(earned, isNot(contains('streak_fourteen')));
    });

    test('does not count multiple sessions on one date as multiple streak days', () {
      final start = DateTime(2026, 1, 2, 22);
      final sessions = [
        _session(id: 1),
        SleepSession(
          id: 'same-day-extra',
          startedAt: start.add(const Duration(minutes: 30)),
          endedAt: start.add(const Duration(hours: 2)),
        ),
      ];

      final earned = SleepAchievementCatalog.evaluate(sessions);

      expect(earned, isNot(contains('streak_three')));
    });

    test('records the actual date each night and streak milestone was reached', () {
      final sessions = List.generate(8, (index) => _session(id: index + 1));
      final earned = SleepAchievementCatalog.evaluateDates(sessions);

      expect(earned['first_night'], DateTime(2026, 1, 2, 22));
      expect(earned['seven_nights'], DateTime(2026, 1, 8, 22));
      expect(earned['streak_three'], DateTime(2026, 1, 4));
      expect(earned['streak_seven'], DateTime(2026, 1, 8));
      expect(earned.containsKey('streak_fourteen'), isFalse);
    });

    test('uses the date of the rated night for rating milestones', () {
      final sessions = List.generate(
        10,
        (index) => _session(id: index + 1, rating: 4),
      );
      final earned = SleepAchievementCatalog.evaluateDates(sessions);

      expect(earned['first_rating'], DateTime(2026, 1, 2, 22));
      expect(earned['ten_ratings'], DateTime(2026, 1, 11, 22));
    });

    test('does not unlock anything for an empty history', () {
      expect(SleepAchievementCatalog.evaluate(const []), isEmpty);
    });
  });
}
