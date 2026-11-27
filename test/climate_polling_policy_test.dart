import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/climate_polling_policy.dart';

void main() {
  group('shouldKeepClimatePollingInBackground', () {
    test('keeps sampling while night audio observation is active', () {
      expect(
        shouldKeepClimatePollingInBackground(
          audioObservationActive: true,
          audioObservationPaused: false,
        ),
        isTrue,
      );
    });

    test('stops sampling when the user pauses audio observation', () {
      expect(
        shouldKeepClimatePollingInBackground(
          audioObservationActive: true,
          audioObservationPaused: true,
        ),
        isFalse,
      );
    });

    test('stops sampling when no night audio observation is active', () {
      expect(
        shouldKeepClimatePollingInBackground(
          audioObservationActive: false,
          audioObservationPaused: false,
        ),
        isFalse,
      );
    });
  });
}
