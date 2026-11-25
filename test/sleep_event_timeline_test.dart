import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/diary/sleep_event_timeline.dart';

void main() {
  group('SleepEventTimeline', () {
    test('merges overlapping awake intervals and combines audio and pulse chronologically', () {
      final events = SleepEventTimeline.build(
        stages: [
          {
            'stage': 'Бодрствование',
            'started_at': '2026-11-24T22:00:00.000Z',
            'ended_at': '2026-11-24T22:10:00.000Z',
          },
          {
            'stage': 'awake',
            'started_at': '2026-11-24T22:05:00.000Z',
            'ended_at': '2026-11-24T22:15:00.000Z',
          },
          {
            'stage': 'Глубокий сон',
            'started_at': '2026-11-24T22:15:00.000Z',
            'ended_at': '2026-11-24T23:00:00.000Z',
          },
        ],
        metrics: [
          for (var i = 0; i < 5; i++)
            {
              'metric_type': 'Пульс',
              'value': [60, 61, 62, 63, 110][i],
              'unit': 'уд/мин',
              'measured_at': DateTime.utc(2026, 11, 24, 23).add(Duration(minutes: i * 10)).toIso8601String(),
              'source': 'Apple Health: Watch',
            },
        ],
        audioEvents: [
          {
            'id': 'audio-1',
            'category': 'Храп',
            'captured_at': '2026-11-24T23:15:00.000Z',
            'duration_ms': 1800,
            'file_path': '/app/audio_events/audio-1.m4a',
          },
        ],
      );

      final awakenings = events.where((event) => event.kind == SleepTimelineEventKind.awakening).toList();
      final pulse = events.where((event) => event.kind == SleepTimelineEventKind.pulse).toList();
      final audio = events.where((event) => event.kind == SleepTimelineEventKind.audio).toList();

      expect(awakenings, hasLength(1));
      expect(awakenings.single.detail, contains('15 мин'));
      expect(pulse, hasLength(5));
      expect(pulse.where((event) => event.isElevated).map((event) => event.detail).toList(), ['110 уд/мин']);
      expect(audio, hasLength(1));
      expect(audio.single.title, contains('Храп'));
      expect(events.map((event) => event.at), orderedEquals(
        events.map((event) => event.at).toList()..sort(),
      ));
    });

    test('localizes sobbing category while preserving legacy localized categories', () {
      final events = SleepEventTimeline.build(
        stages: const [],
        metrics: const [],
        audioEvents: [
          {
            'category': 'sobbing',
            'captured_at': '2026-11-24T23:15:00.000Z',
          },
          {
            'category': 'Храп',
            'captured_at': '2026-11-24T23:20:00.000Z',
          },
        ],
      );

      expect(events.map((event) => event.title).toList(), [
        'Звуковое событие · Всхлипывания',
        'Звуковое событие · Храп',
      ]);
    });

    test('does not invent events or flag pulse outliers with too few samples', () {
      final events = SleepEventTimeline.build(
        stages: [
          {'stage': 'REM', 'started_at': 'bad', 'ended_at': 'also bad'},
        ],
        metrics: [
          {
            'metric_type': 'Пульс',
            'value': 130,
            'unit': 'уд/мин',
            'measured_at': '2026-11-24T23:00:00.000Z',
          },
        ],
        audioEvents: [
          {'category': 'unknown', 'captured_at': 'not-a-date'},
        ],
      );

      expect(events, hasLength(1));
      expect(events.single.kind, SleepTimelineEventKind.pulse);
      expect(events.single.isElevated, isFalse);
    });
  });
}
