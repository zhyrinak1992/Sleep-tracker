import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/yandex_smart_home_service.dart';

void main() {
  test('discards only an invalid_grant refresh token response', () {
    expect(
      shouldDiscardYandexRefreshToken(statusCode: 400, errorCode: 'invalid_grant'),
      isTrue,
    );
  });

  test('preserves credentials for client and request configuration errors', () {
    for (final error in ['invalid_client', 'invalid_request', 'unauthorized_client']) {
      expect(
        shouldDiscardYandexRefreshToken(statusCode: 400, errorCode: error),
        isFalse,
      );
    }
  });

  test('preserves credentials for rate limits and server failures', () {
    expect(shouldDiscardYandexRefreshToken(statusCode: 429, errorCode: 'rate_limit'), isFalse);
    expect(shouldDiscardYandexRefreshToken(statusCode: 500, errorCode: 'server_error'), isFalse);
    expect(shouldDiscardYandexRefreshToken(statusCode: 503, errorCode: null), isFalse);
  });
}