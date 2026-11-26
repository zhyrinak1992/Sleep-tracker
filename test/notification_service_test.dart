import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/notification_service.dart';

void main() {
  group('NotificationService.hasPendingNightReminderIds', () {
    test('preserves a partially consumed rolling night-reminder queue', () {
      expect(
        NotificationService.hasPendingNightReminderIds([5001, 5020, 5043]),
        isTrue,
      );
    });

    test('preserves a deferred offer while it is pending', () {
      expect(
        NotificationService.hasPendingNightReminderIds([5099]),
        isTrue,
      );
    });

    test('does not treat unrelated or legacy notifications as a current queue', () {
      expect(
        NotificationService.hasPendingNightReminderIds([4101, 4200, 4300, 4301]),
        isFalse,
      );
    });

    test('reports an empty queue when all night reminders have expired', () {
      expect(
        NotificationService.hasPendingNightReminderIds(const []),
        isFalse,
      );
    });
  });
}
