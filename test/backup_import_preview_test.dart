import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_service.dart';
import 'package:sleep_tracker/data/sleep_database.dart';

void main() {
  group('BackupImportPreview', () {
    test('counts records from archive tables, not the stored summary', () {
      final data = <String, dynamic>{
        'schemaVersion': 8,
        'sleep_sessions': [<String, Object?>{}, <String, Object?>{}],
        'morning_reports': [<String, Object?>{}],
        'sleep_notes': [<String, Object?>{}, <String, Object?>{}, <String, Object?>{}],
        'audio_events': [
          <String, Object?>{'audioDataB64': 'AQID'},
          <String, Object?>{'file_path': null},
        ],
        'climate_samples': [<String, Object?>{}],
        'sleep_stages': [<String, Object?>{}, <String, Object?>{}],
        'sleep_metrics': [<String, Object?>{}],
        'sleep_session_tags': [<String, Object?>{}],
        'app_metadata': [<String, Object?>{'key': 'sleep_change_history_v1', 'value': '[{"periodKey":"2026-10","fingerprint":"f","version":1}]'}, <String, Object?>{'key': 'comparison_suggestion_history_v1', 'value': '[{"id":"suggestion-1"}]'}],
      };
      final preview = BackupImportPreview.fromDocument({
        'formatVersion': 4,
        'createdAt': '2026-11-23T10:00:00Z',
        'summary': {'sleepSessions': 999},
      }, data);

      expect(preview.sessions, 2);
      expect(preview.reports, 1);
      expect(preview.notes, 3);
      expect(preview.audioEvents, 2);
      expect(preview.audioFiles, 1);
      expect(preview.climateSamples, 1);
      expect(preview.stages, 2);
      expect(preview.metrics, 1);
      expect(preview.tags, 1);
      expect(preview.changeHistorySnapshots, 1);
      expect(preview.suggestionHistoryEntries, 1);
      expect(preview.formatVersion, 4);
      expect(preview.createdAt, DateTime.parse('2026-11-23T10:00:00Z'));
    });
  });

  group('SleepDatabase.validateSnapshot', () {
    test('accepts a structurally valid empty current archive without opening SQLite', () {
      final snapshot = <String, dynamic>{
        'schemaVersion': 8,
        'sleep_sessions': [],
        'sleep_session_tags': [],
        'sleep_notes': [],
        'app_metadata': [],
        'sleep_stages': [],
        'sleep_metrics': [],
        'audio_events': [],
        'morning_reports': [],
        'climate_samples': [],
      };

      final rows = SleepDatabase.instance.validateSnapshot(snapshot);
      expect(rows.keys, containsAll(snapshot.keys.where((key) => key != 'schemaVersion')));
      expect(rows.values.every((value) => value.isEmpty), isTrue);
    });

    test('rejects unsupported schema versions before restore', () {
      expect(
        () => SleepDatabase.instance.validateSnapshot({'schemaVersion': 99}),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects archives with missing required sections before restore', () {
      expect(
        () => SleepDatabase.instance.validateSnapshot({
          'schemaVersion': 8,
          'sleep_sessions': [],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
