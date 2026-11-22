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

    test('does not unlock anything for an empty history', () {
      expect(SleepAchievementCatalog.evaluate(const []), isEmpty);
    });
  });
}
