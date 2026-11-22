import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/security/app_lock_policy.dart';

void main() {
  group('shouldLockAfterBackground', () {
    test('does not require authentication before 60 seconds', () {
      expect(
        shouldLockAfterBackground(elapsed: const Duration(seconds: 59)),
        isFalse,
      );
    });

    test('requires authentication at exactly 60 seconds', () {
      expect(
        shouldLockAfterBackground(elapsed: const Duration(seconds: 60)),
        isTrue,
      );
    });

    test('requires authentication after more than 60 seconds', () {
      expect(
        shouldLockAfterBackground(elapsed: const Duration(minutes: 2)),
        isTrue,
      );
    });

    test('supports the configured timeout boundary', () {
      expect(
        shouldLockAfterBackground(
          elapsed: const Duration(seconds: 29),
          timeout: const Duration(seconds: 30),
        ),
        isFalse,
      );
      expect(
        shouldLockAfterBackground(
          elapsed: const Duration(seconds: 30),
          timeout: const Duration(seconds: 30),
        ),
        isTrue,
      );
    });
  });
}
