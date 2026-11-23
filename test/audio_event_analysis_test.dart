import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/audio_event_analysis.dart';

void main() {
  test('counts only events linked to selected nights and groups categories', () {
    final summary = AudioEventPeriodSummary.summarize(
      sessionIds: {'night-1', 'night-2'},
      events: [
        {'session_id': 'night-1', 'category': 'snoring', 'duration_ms': 1200},
        {'session_id': 'night-1', 'category': 'snoring', 'duration_ms': 800},
        {'session_id': 'night-2', 'category': 'unknown', 'duration_ms': 500},
        {'session_id': 'other-night', 'category': 'cough', 'duration_ms': 900},
        {'session_id': null, 'category': 'speech', 'duration_ms': 1000},
      ],
    );
    expect(summary.eventCount, 3);
    expect(summary.nightsWithEvents, 2);
    expect(summary.savedDurationMs, 2500);
    expect(summary.categoryCounts, {'snoring': 2, 'unknown': 1});
  });

  test('handles missing categories and invalid durations without inventing events', () {
    final summary = AudioEventPeriodSummary.summarize(
      sessionIds: {'night-1'},
      events: [
        {'session_id': 'night-1', 'category': '', 'duration_ms': -100},
        {'session_id': 'night-1', 'duration_ms': 400},
      ],
    );
    expect(summary.eventCount, 2);
    expect(summary.nightsWithEvents, 1);
    expect(summary.savedDurationMs, 400);
    expect(summary.categoryCounts, {'unknown': 2});
  });

  test('returns empty summary when no selected nights exist', () {
    final summary = AudioEventPeriodSummary.summarize(
      sessionIds: {},
      events: [{'session_id': 'night-1', 'category': 'snoring', 'duration_ms': 1}],
    );
    expect(summary.eventCount, 0);
    expect(summary.nightsWithEvents, 0);
    expect(summary.savedDurationMs, 0);
    expect(summary.categoryCounts, isEmpty);
  });
}
