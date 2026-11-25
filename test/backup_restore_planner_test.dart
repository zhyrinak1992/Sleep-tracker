import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_restore_planner.dart';

void main() {
  group('BackupRestorePlanner', () {
    test('counts individual achievement metadata entries that will actually be merged', () {
      final archive = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      final current = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      current['app_metadata'] = [
        {'key': 'sleep_achievements_history_v1', 'value': jsonEncode({
          'first_night': '2026-11-20T00:00:00Z',
        })},
        {'key': 'sleep_personal_records_v1', 'value': jsonEncode({
          'longestSleepMinutes': 500,
          'bestEfficiencyPercent': 90,
          'shortestLatencyMinutes': 10,
          'longestStreakDays': 3,
        })},
        {'key': 'sleep_records_history_v1', 'value': jsonEncode([
          {'type': 'sleep_score', 'sessionId': 'night-1', 'value': 90,
           'achievedAt': '2026-11-20T07:00:00Z'},
        ])},
        {'key': 'sleep_records_celebrated_v1', 'value': jsonEncode(['x'])},
        {'key': 'sleep_personal_records_history_v1', 'value': jsonEncode([
          {'id': 'record-1', 'metric': 'longestSleepMinutes', 'value': 480,
           'achievedAt': '2026-11-20T00:00:00Z', 'sessionId': 'night-1'},
          // A malformed local event must not hide a valid imported event
          // with the same ID from the merge preview.
          {'id': 'record-2', 'metric': 'sleepScore', 'value': 99,
           'achievedAt': '2026-11-22T00:00:00Z', 'sessionId': 'night-2'},
        ])},
      ];
      archive['app_metadata'] = [
        {'key': 'sleep_achievements_history_v1', 'value': jsonEncode({
          'first_night': '2026-11-22T00:00:00Z',
          'seven_nights': '2026-11-21T00:00:00Z',
        })},
        {'key': 'sleep_personal_records_v1', 'value': jsonEncode({
          'longestSleepMinutes': 550,
          'bestEfficiencyPercent': 88,
          'shortestLatencyMinutes': 5,
          'longestStreakDays': 7,
        })},
        {'key': 'sleep_records_history_v1', 'value': jsonEncode([
          {'type': 'sleep_score', 'sessionId': 'night-1', 'value': 88,
           'achievedAt': '2026-11-19T07:00:00Z'},
          {'type': 'sleep_score', 'sessionId': 'night-2', 'value': 96,
           'achievedAt': '2026-11-21T07:00:00Z'},
        ])},
        {'key': 'sleep_records_celebrated_v1', 'value': jsonEncode(['x', 'y', 'z'])},
        {'key': 'sleep_personal_records_history_v1', 'value': jsonEncode([
          {'id': 'record-1', 'metric': 'longestSleepMinutes', 'value': 480,
           'achievedAt': '2026-11-20T00:00:00Z', 'sessionId': 'night-1'},
          {'id': 'record-2', 'metric': 'longestSleepMinutes', 'value': 510,
           'achievedAt': '2026-11-22T00:00:00Z', 'sessionId': 'night-2'},
          {'id': '', 'metric': 'longestSleepMinutes', 'value': 600,
           'achievedAt': '2026-11-23T00:00:00Z', 'sessionId': 'night-empty-id'},
          {'id': 'bad-zero', 'metric': 'longestSleepMinutes', 'value': 0,
           'achievedAt': '2026-11-23T00:00:00Z', 'sessionId': 'night-zero'},
          {'id': 'bad-efficiency', 'metric': 'bestEfficiencyPercent', 'value': 101,
           'achievedAt': '2026-11-23T00:00:00Z', 'sessionId': 'night-efficiency'},
          {'id': 'bad-latency', 'metric': 'shortestLatencyMinutes', 'value': 1441,
           'achievedAt': '2026-11-23T00:00:00Z', 'sessionId': 'night-latency'},
          {'id': 'bad-streak', 'metric': 'longestStreakDays', 'value': 0,
           'achievedAt': '2026-11-23T00:00:00Z'},
          {'id': 'bad-session', 'metric': 'longestSleepMinutes', 'value': 600,
           'achievedAt': '2026-11-23T00:00:00Z', 'sessionId': 42},
        ])},
      ];

      final impact = BackupRestorePlanner.calculate(
        archiveRows: archive,
        currentRows: current,
        availableBytes: 100 * 1024 * 1024,
      );

      expect(impact.merge.historyEntriesToMerge, 8);
    });


    test('counts new rows, duplicate rows, merged history and only new audio files', () {
      final archive = <String, List<Map<String, Object?>>>{
        'sleep_sessions': [
          {'id': 's1'}, {'id': 's2'},
        ],
        'sleep_session_tags': [
          {'session_id': 's1', 'tag_key': 'stress'},
          {'session_id': 's2', 'tag_key': 'caffeine'},
        ],
        'sleep_notes': [
          {'id': 'n1'}, {'id': 'n2'},
        ],
        'app_metadata': [
          {'key': 'theme', 'value': 'dark'},
          {'key': 'sleep_change_history_v1', 'value': jsonEncode([
            {'periodKey': '2026-11', 'fingerprint': 'a'},
            {'periodKey': '2026-11', 'fingerprint': 'b'},
          ])},
          {'key': 'comparison_suggestion_history_v1', 'value': jsonEncode([
            {'id': 'suggestion-1'}, {'id': 'suggestion-2'},
          ])},
        ],
        'sleep_stages': [],
        'sleep_metrics': [],
        'audio_events': [
          {'id': 'a1', 'file_path': 'old.m4a', 'audioDataB64': base64Encode([1, 2])},
          {'id': 'a2', 'file_path': 'new.m4a', 'audioDataB64': base64Encode([3, 4, 5])},
          {'id': 'a3', 'file_path': null},
        ],
        'morning_reports': [
          {'id': 'r1', 'session_id': 's1'},
        ],
        'climate_samples': [],
      };
      final current = <String, List<Map<String, Object?>>>{
        'sleep_sessions': [{'id': 's1'}],
        'sleep_session_tags': [{'session_id': 's1', 'tag_key': 'stress'}],
        'sleep_notes': [{'id': 'n1'}],
        'app_metadata': [
          {'key': 'theme', 'value': 'light'},
          {'key': 'sleep_change_history_v1', 'value': jsonEncode([
            {'periodKey': '2026-11', 'fingerprint': 'a'},
          ])},
          {'key': 'comparison_suggestion_history_v1', 'value': jsonEncode([
            {'id': 'suggestion-1'},
          ])},
        ],
        'sleep_stages': [],
        'sleep_metrics': [],
        'audio_events': [{'id': 'a1'}],
        'morning_reports': [{'session_id': 's1'}],
        'climate_samples': [],
      };

      final impact = BackupRestorePlanner.calculate(
        archiveRows: archive,
        currentRows: current,
        availableBytes: 100 * 1024 * 1024,
      );

      expect(impact.merge.recordsToAdd, 5);
      expect(impact.merge.duplicatesToSkip, 8);
      expect(impact.merge.historyEntriesToMerge, 2);
      expect(impact.merge.audioFilesToRestore, 1);
      expect(impact.merge.audioBytesToRestore, 3);
      expect(impact.merge.missingAudioFiles, 0);
      expect(impact.merge.hasEnoughSpace, isTrue);

      expect(impact.replace.archiveRecordCount, 13);
      expect(impact.replace.currentRecordsToReplace, 8);
      expect(impact.replace.recordsToAdd, 13);
      expect(impact.replace.audioFilesToRestore, 2);
      expect(impact.replace.audioBytesToRestore, 5);
    });

    test('reports missing legacy attachments and blocks a plan without enough space', () {
      final archive = <String, List<Map<String, Object?>>>{
        'sleep_sessions': [],
        'sleep_session_tags': [],
        'sleep_notes': [],
        'app_metadata': [],
        'sleep_stages': [],
        'sleep_metrics': [],
        'audio_events': [
          {'id': 'legacy-audio', 'file_path': 'missing.m4a'},
        ],
        'morning_reports': [],
        'climate_samples': [],
      };
      final current = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      final impact = BackupRestorePlanner.calculate(
        archiveRows: archive,
        currentRows: current,
        availableBytes: 1024,
      );

      expect(impact.replace.missingAudioFiles, 1);
      expect(impact.merge.missingAudioFiles, 1);
      expect(impact.replace.hasEnoughSpace, isFalse);
      expect(impact.merge.hasEnoughSpace, isFalse);
    });

    test('blocks merge when local history is corrupt but keeps full replacement available', () {
      final archive = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      archive['app_metadata'] = [
        {'key': 'sleep_change_history_v1', 'value': '[]'},
      ];
      final current = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      current['app_metadata'] = [
        {'key': 'sleep_change_history_v1', 'value': '{broken'},
      ];

      final impact = BackupRestorePlanner.calculate(
        archiveRows: archive,
        currentRows: current,
        availableBytes: 100 * 1024 * 1024,
      );

      expect(impact.merge.canProceed, isFalse);
      expect(impact.merge.blockedReason, contains('повреждена'));
      expect(impact.replace.canProceed, isTrue);
    });

    test('changes the state fingerprint when current record IDs change after preview', () {
      final archive = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      final currentA = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      final currentB = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      currentA['sleep_sessions'] = [{'id': 'night-a'}];
      currentB['sleep_sessions'] = [{'id': 'night-b'}];

      final planA = BackupRestorePlanner.calculate(
        archiveRows: archive, currentRows: currentA, availableBytes: null,
      );
      final planB = BackupRestorePlanner.calculate(
        archiveRows: archive, currentRows: currentB, availableBytes: null,
      );

      expect(planA.merge.stateFingerprint, isNot(planB.merge.stateFingerprint));
    });

    test('allows unknown free-space state but reports it as unknown', () {
      final empty = {
        for (final table in BackupRestorePlanner.tableKeys.keys)
          table: <Map<String, Object?>>[],
      };
      final impact = BackupRestorePlanner.calculate(
        archiveRows: empty,
        currentRows: empty,
        availableBytes: null,
      );
      expect(impact.replace.spaceCheckKnown, isFalse);
      expect(impact.replace.hasEnoughSpace, isTrue);
    });
  });
}
