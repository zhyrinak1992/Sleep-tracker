import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/apple_health_service.dart';

void main() {
  test('nightly HealthKit sync preserves fields missing from a later query', () {
    final previous = jsonEncode({
      'schemaVersion': 1,
      'sessionId': 'night-1',
      'steps': 4200,
      'workoutCount': 2,
      'workoutDurationMinutes': 75,
      'workouts': [
        {'type': 'Running', 'startedAt': '2026-11-20T17:00:00Z'},
      ],
    });

    final merged = jsonDecode(mergeNightActivityMetadata(
      previousRaw: previous,
      current: {
        'schemaVersion': 1,
        'sessionId': 'night-1',
        'steps': 5100,
        'syncedAt': '2026-11-21T08:00:00Z',
      },
    )) as Map<String, dynamic>;

    expect(merged['steps'], 5100);
    expect(merged['workoutCount'], 2);
    expect(merged['workoutDurationMinutes'], 75);
    expect(merged['workouts'], hasLength(1));
  });

  test('new values replace old values for the same night', () {
    final merged = jsonDecode(mergeNightActivityMetadata(
      previousRaw: jsonEncode({
        'sessionId': 'night-1',
        'steps': 4200,
        'workoutCount': 1,
      }),
      current: {
        'sessionId': 'night-1',
        'steps': 5100,
        'workoutCount': 2,
      },
    )) as Map<String, dynamic>;

    expect(merged['steps'], 5100);
    expect(merged['workoutCount'], 2);
  });

  test('activity from another night is never carried into the current night', () {
    final merged = jsonDecode(mergeNightActivityMetadata(
      previousRaw: jsonEncode({
        'sessionId': 'night-old',
        'steps': 4200,
        'workoutCount': 1,
      }),
      current: {
        'sessionId': 'night-new',
        'steps': 1800,
      },
    )) as Map<String, dynamic>;

    expect(merged['sessionId'], 'night-new');
    expect(merged['steps'], 1800);
    expect(merged.containsKey('workoutCount'), isFalse);
  });

  test('malformed previous activity metadata is rejected, not overwritten', () {
    expect(
      () => mergeNightActivityMetadata(
        previousRaw: '{broken',
        current: {'sessionId': 'night-1', 'steps': 100},
      ),
      throwsFormatException,
    );
  });
}
