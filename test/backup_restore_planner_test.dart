import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_restore_planner.dart';

void main() {
  group('BackupRestorePlanner', () {
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
