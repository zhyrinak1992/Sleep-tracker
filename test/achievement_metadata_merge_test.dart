import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/achievement_metadata_merge.dart';

void main() {
  group('achievement metadata restore merge', () {
    test('keeps earliest achievement date without dropping other achievements', () {
      final merged = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_achievements_history_v1',
        localRaw: jsonEncode({'first_night': '2026-11-20T08:00:00Z'}),
        importedRaw: jsonEncode({
          'first_night': '2026-11-22T08:00:00Z',
          'seven_nights': '2026-11-21T08:00:00Z',
        }),
      )) as Map<String, dynamic>;

      expect(merged['first_night'], '2026-11-20T08:00:00.000Z');
      expect(merged['seven_nights'], '2026-11-21T08:00:00.000Z');
    });

    test('keeps the best value and its source metadata for each personal record', () {
      final merged = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_personal_records_v1',
        localRaw: jsonEncode({
          'longestSleepMinutes': 500,
          'longestSleepSessionId': 'local',
          'longestSleepAt': '2026-11-20T00:00:00Z',
          'bestSleepScore': 90,
          'bestSleepScoreSessionId': 'local-score',
          'bestSleepScoreAt': '2026-11-19T00:00:00Z',
          'bestEfficiencyPercent': 92,
          'bestEfficiencySessionId': 'local-eff',
          'fewestAwakenings': 3,
          'fewestAwakeningsSessionId': 'local-awake',
          'fewestAwakeningsAt': '2026-11-18T00:00:00Z',
          'shortestLatencyMinutes': 5,
          'shortestLatencySessionId': 'local-latency',
          'longestStreakDays': 8,
          'longestStreakAt': '2026-11-10T00:00:00Z',
        }),
        importedRaw: jsonEncode({
          'longestSleepMinutes': 480,
          'longestSleepSessionId': 'archive',
          'bestSleepScore': 96,
          'bestSleepScoreSessionId': 'archive-score',
          'bestSleepScoreAt': '2026-11-22T00:00:00Z',
          'bestEfficiencyPercent': 97,
          'bestEfficiencySessionId': 'archive-eff',
          'bestEfficiencyAt': '2026-11-21T00:00:00Z',
          'fewestAwakenings': 1,
          'fewestAwakeningsSessionId': 'archive-awake',
          'fewestAwakeningsAt': '2026-11-23T00:00:00Z',
          'shortestLatencyMinutes': 2,
          'shortestLatencySessionId': 'archive-latency',
          'longestStreakDays': 14,
          'longestStreakAt': '2026-11-24T00:00:00Z',
        }),
      )) as Map<String, dynamic>;

      expect(merged['longestSleepMinutes'], 500);
      expect(merged['longestSleepSessionId'], 'local');
      expect(merged['bestSleepScore'], 96);
      expect(merged['bestSleepScoreSessionId'], 'archive-score');
      expect(merged['fewestAwakenings'], 1);
      expect(merged['fewestAwakeningsSessionId'], 'archive-awake');
      expect(merged['bestEfficiencyPercent'], 97);
      expect(merged['bestEfficiencySessionId'], 'archive-eff');
      expect(merged['shortestLatencyMinutes'], 2);
      expect(merged['shortestLatencySessionId'], 'archive-latency');
      expect(merged['longestStreakDays'], 14);
      expect(merged['longestStreakAt'], '2026-11-24T00:00:00Z');
      expect(merged['bestEfficiencyAt'], '2026-11-21T00:00:00Z');
    });

    test('ignores invalid imported best values rather than erasing valid local values', () {
      final merged = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_personal_records_v1',
        localRaw: jsonEncode({
          'bestEfficiencyPercent': 94,
          'bestEfficiencySessionId': 'valid-local',
        }),
        importedRaw: jsonEncode({
          'bestEfficiencyPercent': 150,
          'bestEfficiencySessionId': 'invalid-archive',
        }),
      )) as Map<String, dynamic>;

      expect(merged['bestEfficiencyPercent'], 94);
      expect(merged['bestEfficiencySessionId'], 'valid-local');
    });

    test('unions dated history for the four approved personal records', () {
      final local = {
        'id': 'longestSleepMinutes|night-1|480.0|2026-11-20T00:00:00.000Z',
        'metric': 'longestSleepMinutes',
        'value': 480,
        'achievedAt': '2026-11-20T00:00:00Z',
        'sessionId': 'night-1',
      };
      final imported = {
        'id': 'longestSleepMinutes|night-2|510.0|2026-11-22T00:00:00.000Z',
        'metric': 'longestSleepMinutes',
        'value': 510,
        'achievedAt': '2026-11-22T00:00:00Z',
        'sessionId': 'night-2',
      };
      final score = {
        'id': 'bestSleepScore|night-3|98.0|2026-11-23T00:00:00.000Z',
        'metric': 'bestSleepScore',
        'value': 98,
        'achievedAt': '2026-11-23T00:00:00Z',
        'sessionId': 'night-3',
      };
      final awakenings = {
        'id': 'fewestAwakenings|night-4|0.0|2026-11-24T00:00:00.000Z',
        'metric': 'fewestAwakenings',
        'value': 0,
        'achievedAt': '2026-11-24T00:00:00Z',
        'sessionId': 'night-4',
      };
      final merged = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_personal_records_history_v1',
        localRaw: jsonEncode([local]),
        importedRaw: jsonEncode([local, imported, score, awakenings, {
          'id': 'sleep_score|night-5',
          'metric': 'sleepScore',
          'value': 99,
          'achievedAt': '2026-11-25T00:00:00Z',
          'sessionId': 'night-5',
        }]),
      )) as List;

      expect(merged, hasLength(4));
      final durationValues = merged
          .where((event) => event['metric'] == 'longestSleepMinutes')
          .map((event) => event['value'])
          .toList();
      expect(durationValues, [480, 510]);
      expect(merged.singleWhere(
        (event) => event['metric'] == 'bestSleepScore',
      )['value'], 98);
      expect(merged.singleWhere(
        (event) => event['metric'] == 'fewestAwakenings',
      )['value'], 0);
    });

    test('unions record events by metric and session and unions celebrations', () {
      final local = {
        'type': 'sleep_score',
        'sessionId': 'night-1',
        'value': 90,
        'achievedAt': '2026-11-20T07:00:00Z',
      };
      final imported = {
        'type': 'sleep_score',
        'sessionId': 'night-2',
        'value': 96,
        'achievedAt': '2026-11-21T07:00:00Z',
      };
      final history = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_records_history_v1',
        localRaw: jsonEncode([local]),
        importedRaw: jsonEncode([local, imported]),
      )) as List;
      final celebrated = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_records_celebrated_v1',
        localRaw: jsonEncode(['a']),
        importedRaw: jsonEncode(['a', 'b']),
      )) as List;

      expect(history, hasLength(2));
      expect(celebrated.toSet(), {'a', 'b'});

      final localWins = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_records_history_v1',
        localRaw: jsonEncode([local]),
        importedRaw: jsonEncode([{
          ...local,
          'value': 88,
          'achievedAt': '2026-11-19T07:00:00Z',
        }]),
      )) as List;
      expect(localWins.single['value'], 90);
    });

    test('repairs a missing local metadata entry from the archive', () {
      final merged = jsonDecode(mergeAchievementMetadata(
        key: 'sleep_records_celebrated_v1',
        localRaw: null,
        importedRaw: jsonEncode(['record-key']),
      )) as List;

      expect(merged, ['record-key']);
    });
  });
}
