import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/data/backup_service.dart';

Future<Database> _openDatabase(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE sleep_sessions (
      id TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT,
      source TEXT NOT NULL, note TEXT, morning_rating INTEGER,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      button_started_at TEXT, button_ended_at TEXT,
      actual_sleep_started_at TEXT, actual_sleep_ended_at TEXT,
      user_edited INTEGER NOT NULL DEFAULT 0, deleted_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE sleep_session_tags (
      session_id TEXT NOT NULL, tag_key TEXT NOT NULL, label TEXT NOT NULL,
      created_at TEXT NOT NULL, PRIMARY KEY (session_id, tag_key),
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE sleep_notes (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, body TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute('''
    CREATE TABLE sleep_stages (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, stage TEXT NOT NULL,
      started_at TEXT NOT NULL, ended_at TEXT NOT NULL, source TEXT NOT NULL,
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE sleep_metrics (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, metric_type TEXT NOT NULL,
      value REAL NOT NULL, unit TEXT NOT NULL, measured_at TEXT NOT NULL,
      source TEXT NOT NULL,
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE audio_events (
      id TEXT PRIMARY KEY, session_id TEXT, file_path TEXT,
      category TEXT NOT NULL DEFAULT 'unknown', confidence REAL,
      captured_at TEXT NOT NULL, expires_at TEXT NOT NULL,
      duration_ms INTEGER NOT NULL, user_corrected INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE morning_reports (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL UNIQUE,
      report_date TEXT NOT NULL, wellbeing INTEGER, sleep_quality INTEGER,
      answers_json TEXT, created_at TEXT NOT NULL,
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE climate_samples (
      id TEXT PRIMARY KEY, session_id TEXT, device_id TEXT NOT NULL,
      device_name TEXT, room_name TEXT, metric_type TEXT NOT NULL,
      value REAL NOT NULL, unit TEXT NOT NULL, source TEXT NOT NULL,
      measured_at TEXT NOT NULL, received_at TEXT NOT NULL,
      quality TEXT NOT NULL DEFAULT 'actual',
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL
    )
  ''');
  return db;
}

void main() {
  late Database source;
  late Database destination;
  late Directory tempDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('sleep_backup_round_trip_');
    source = await _openDatabase('${tempDirectory.path}/source.db');
    destination = await _openDatabase('${tempDirectory.path}/destination.db');
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    await source.close();
    await destination.close();
    await tempDirectory.delete(recursive: true);
  });

  test('full snapshot restore preserves every exported table and field', () async {
    const sessionId = 'round-trip-night';
    const timestamp = '2026-11-20T22:15:00.000Z';
    await source.insert('sleep_sessions', {
      'id': sessionId,
      'started_at': timestamp,
      'ended_at': '2026-11-21T07:10:00.000Z',
      'source': 'manual',
      'note': 'session note',
      'morning_rating': 4,
      'created_at': timestamp,
      'updated_at': '2026-11-21T07:11:00.000Z',
      'button_started_at': timestamp,
      'button_ended_at': '2026-11-21T07:10:00.000Z',
      'actual_sleep_started_at': '2026-11-20T22:30:00.000Z',
      'actual_sleep_ended_at': '2026-11-21T06:55:00.000Z',
      'user_edited': 1,
      'deleted_at': null,
    });
    await source.insert('sleep_session_tags', {
      'session_id': sessionId, 'tag_key': 'stress', 'label': 'Stress',
      'created_at': timestamp,
    });
    await source.insert('sleep_notes', {
      'id': 'note-1', 'session_id': sessionId, 'body': 'note body',
      'created_at': timestamp, 'updated_at': timestamp,
    });
    await source.insert('app_metadata', {
      'key': 'sleep_change_history_v1',
      'value': '[{"periodKey":"2026-11","fingerprint":"abc","version":1}]',
    });
    await source.insert('sleep_stages', {
      'id': 'stage-1', 'session_id': sessionId, 'stage': 'deep',
      'started_at': '2026-11-20T23:00:00.000Z',
      'ended_at': '2026-11-21T00:00:00.000Z', 'source': 'device',
    });
    await source.insert('sleep_metrics', {
      'id': 'metric-1', 'session_id': sessionId, 'metric_type': 'heart_rate',
      'value': 58.5, 'unit': 'bpm',
      'measured_at': '2026-11-21T01:00:00.000Z', 'source': 'device',
    });
    await source.insert('audio_events', {
      'id': 'audio-1', 'session_id': sessionId, 'file_path': null,
      'category': 'snoring', 'confidence': 0.91,
      'captured_at': '2026-11-21T02:00:00.000Z',
      'expires_at': '2026-11-28T02:00:00.000Z',
      'duration_ms': 4200, 'user_corrected': 1,
    });
    await source.insert('morning_reports', {
      'id': 'report-1', 'session_id': sessionId, 'report_date': '2026-11-21',
      'wellbeing': 4, 'sleep_quality': 5, 'answers_json': '{"energy":"good"}',
      'created_at': '2026-11-21T07:15:00.000Z',
    });
    await source.insert('climate_samples', {
      'id': 'climate-1', 'session_id': sessionId, 'device_id': 'sensor-1',
      'device_name': 'Bedroom sensor', 'room_name': 'Bedroom',
      'metric_type': 'temperature', 'value': 19.5, 'unit': '°C',
      'source': 'sensor', 'measured_at': '2026-11-21T03:00:00.000Z',
      'received_at': '2026-11-21T03:00:01.000Z', 'quality': 'actual',
    });

    SleepDatabase.instance.setDatabaseForTesting(source);
    final exported = await SleepDatabase.instance.exportSnapshot();

    // A full restore must replace unrelated local rows as well as import the archive.
    await destination.insert('app_metadata', {'key': 'local-only', 'value': 'must disappear'});
    SleepDatabase.instance.setDatabaseForTesting(destination);
    await SleepDatabase.instance.restoreSnapshot(exported);

    final restored = await SleepDatabase.instance.exportSnapshot();
    expect(restored, equals(exported));
  });

  test('failed full restore rolls back and preserves all existing local data', () async {
    const sessionId = 'local-night-to-protect';
    const timestamp = '2026-11-24T22:00:00.000Z';
    await destination.insert('sleep_sessions', {
      'id': sessionId,
      'started_at': timestamp,
      'ended_at': '2026-11-25T07:00:00.000Z',
      'source': 'manual',
      'created_at': timestamp,
      'updated_at': timestamp,
      'user_edited': 1,
    });
    await destination.insert('sleep_notes', {
      'id': 'local-note-to-protect',
      'session_id': sessionId,
      'body': 'Эта заметка должна сохраниться',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await destination.insert('app_metadata', {
      'key': 'local-setting-to-protect',
      'value': 'keep-me',
    });

    SleepDatabase.instance.setDatabaseForTesting(destination);
    final before = await SleepDatabase.instance.exportSnapshot();
    final invalidSnapshot = Map<String, dynamic>.from(before);
    final sessions = (invalidSnapshot['sleep_sessions'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    // This field is rejected by SQLite's NOT NULL constraint during insertion,
    // after the replacement transaction has already begun deleting old rows.
    sessions.single['user_edited'] = null;
    invalidSnapshot['sleep_sessions'] = sessions;

    await expectLater(
      SleepDatabase.instance.restoreSnapshot(invalidSnapshot),
      throwsA(anything),
    );

    final after = await SleepDatabase.instance.exportSnapshot();
    expect(after, equals(before));
    expect(after['sleep_notes'], hasLength(1));
    expect((after['app_metadata'] as List).any(
      (row) => row['key'] == 'local-setting-to-protect',
    ), isTrue);
  });

  test('merge restore keeps local conflicts and adds archive-only records', () async {
    const timestamp = '2026-11-24T22:00:00.000Z';
    Map<String, Object?> session(String id, String note) => {
      'id': id,
      'started_at': timestamp,
      'ended_at': '2026-11-25T07:00:00.000Z',
      'source': 'manual',
      'note': note,
      'created_at': timestamp,
      'updated_at': timestamp,
      'user_edited': 1,
    };

    await destination.insert('sleep_sessions', session('same-night', 'local session'));
    await destination.insert('sleep_sessions', session('local-only-night', 'local only'));
    await destination.insert('sleep_session_tags', {
      'session_id': 'same-night', 'tag_key': 'stress',
      'label': 'Local label', 'created_at': timestamp,
    });
    await destination.insert('sleep_notes', {
      'id': 'same-note', 'session_id': 'same-night',
      'body': 'Local note', 'created_at': timestamp, 'updated_at': timestamp,
    });
    await destination.insert('app_metadata', {'key': 'theme', 'value': 'local'});
    await destination.insert('audio_events', {
      'id': 'same-audio', 'session_id': 'same-night',
      'file_path': 'local-audio.m4a', 'category': 'user-category',
      'captured_at': timestamp, 'expires_at': '2026-12-01T22:00:00.000Z',
      'duration_ms': 3000, 'user_corrected': 1,
    });

    final archive = <String, dynamic>{
      'schemaVersion': 8,
      'sleep_sessions': [
        session('same-night', 'archive session'),
        session('archive-only-night', 'archive only'),
      ],
      'sleep_session_tags': [
        {
          'session_id': 'same-night', 'tag_key': 'stress',
          'label': 'Archive label', 'created_at': timestamp,
        },
        {
          'session_id': 'archive-only-night', 'tag_key': 'caffeine',
          'label': 'Caffeine', 'created_at': timestamp,
        },
      ],
      'sleep_notes': [
        {
          'id': 'same-note', 'session_id': 'same-night',
          'body': 'Archive note', 'created_at': timestamp, 'updated_at': timestamp,
        },
        {
          'id': 'archive-note', 'session_id': 'archive-only-night',
          'body': 'New archive note', 'created_at': timestamp, 'updated_at': timestamp,
        },
      ],
      'app_metadata': [
        {'key': 'theme', 'value': 'archive'},
        {'key': 'archive-only-setting', 'value': 'imported'},
      ],
      'sleep_stages': [
        {
          'id': 'archive-stage', 'session_id': 'archive-only-night',
          'stage': 'deep', 'started_at': timestamp,
          'ended_at': '2026-11-24T23:00:00.000Z', 'source': 'device',
        },
      ],
      'sleep_metrics': [
        {
          'id': 'archive-metric', 'session_id': 'archive-only-night',
          'metric_type': 'heart_rate', 'value': 57.0, 'unit': 'bpm',
          'measured_at': timestamp, 'source': 'device',
        },
      ],
      'audio_events': [
        {
          'id': 'same-audio', 'session_id': 'same-night',
          'file_path': 'archive-audio.m4a', 'category': 'archive-category',
          'captured_at': timestamp, 'expires_at': '2026-12-01T22:00:00.000Z',
          'duration_ms': 9999, 'user_corrected': 0,
        },
        {
          'id': 'archive-audio', 'session_id': 'archive-only-night',
          'file_path': null, 'category': 'snoring', 'captured_at': timestamp,
          'expires_at': '2026-12-01T22:00:00.000Z',
          'duration_ms': 1200, 'user_corrected': 0,
        },
      ],
      'morning_reports': [
        {
          'id': 'archive-report', 'session_id': 'archive-only-night',
          'report_date': '2026-11-25', 'created_at': timestamp,
        },
      ],
      'climate_samples': [
        {
          'id': 'archive-climate', 'session_id': 'archive-only-night',
          'device_id': 'sensor-1', 'metric_type': 'temperature',
          'value': 19.0, 'unit': '°C', 'source': 'sensor',
          'measured_at': timestamp, 'received_at': timestamp, 'quality': 'actual',
        },
      ],
    };

    SleepDatabase.instance.setDatabaseForTesting(destination);
    await SleepDatabase.instance.restoreSnapshot(archive, merge: true);

    final sessions = await destination.query('sleep_sessions', orderBy: 'id');
    expect(sessions.map((row) => row['id']).toSet(), {
      'same-night', 'local-only-night', 'archive-only-night',
    });
    expect(
      (await destination.query('sleep_sessions',
          where: 'id = ?', whereArgs: ['same-night'])).single['note'],
      'local session',
    );
    expect(
      (await destination.query('sleep_session_tags',
          where: 'session_id = ? AND tag_key = ?',
          whereArgs: ['same-night', 'stress'])).single['label'],
      'Local label',
    );
    expect(
      (await destination.query('sleep_notes',
          where: 'id = ?', whereArgs: ['same-note'])).single['body'],
      'Local note',
    );
    expect(
      (await destination.query('sleep_notes',
          where: 'id = ?', whereArgs: ['archive-note'])).single['body'],
      'New archive note',
    );
    expect(
      (await destination.query('app_metadata',
          where: 'key = ?', whereArgs: ['theme'])).single['value'],
      'local',
    );
    expect(
      (await destination.query('app_metadata',
          where: 'key = ?', whereArgs: ['archive-only-setting'])).single['value'],
      'imported',
    );
    expect(await destination.query('sleep_stages'), hasLength(1));
    expect(await destination.query('sleep_metrics'), hasLength(1));
    final audioRows = await destination.query('audio_events', orderBy: 'id');
    expect(audioRows, hasLength(2));
    final preservedAudio = audioRows.singleWhere((row) => row['id'] == 'same-audio');
    expect(preservedAudio['file_path'], 'local-audio.m4a');
    expect(preservedAudio['category'], 'user-category');
    expect(preservedAudio['duration_ms'], 3000);
    expect(audioRows.any((row) => row['id'] == 'archive-audio'), isTrue);
    expect(await destination.query('morning_reports'), hasLength(1));
    expect(await destination.query('climate_samples'), hasLength(1));
  });


  test('merge restore writes archive-only audio bytes and preserves local conflict files', () async {
    const timestamp = '2026-11-24T22:00:00.000Z';
    Map<String, Object?> session(String id) => {
      'id': id,
      'started_at': timestamp,
      'ended_at': '2026-11-25T07:00:00.000Z',
      'source': 'manual',
      'created_at': timestamp,
      'updated_at': timestamp,
      'user_edited': 1,
    };

    final localAudioPath = '${tempDirectory.path}/local-conflict.m4a';
    final localAudioBytes = [21, 22, 23, 24];
    await File(localAudioPath).writeAsBytes(localAudioBytes, flush: true);
    await destination.insert('sleep_sessions', session('same-night'));
    await destination.insert('audio_events', {
      'id': 'same-audio',
      'session_id': 'same-night',
      'file_path': localAudioPath,
      'category': 'local-category',
      'captured_at': timestamp,
      'expires_at': '2026-12-01T22:00:00.000Z',
      'duration_ms': 3000,
      'user_corrected': 1,
    });

    final archiveAudioBytes = [0, 1, 2, 127, 128, 254, 255];
    final archive = <String, dynamic>{
      'schemaVersion': 8,
      'sleep_sessions': [session('same-night'), session('archive-night')],
      'sleep_session_tags': <Map<String, Object?>>[],
      'sleep_notes': <Map<String, Object?>>[],
      'app_metadata': <Map<String, Object?>>[],
      'sleep_stages': <Map<String, Object?>>[],
      'sleep_metrics': <Map<String, Object?>>[],
      'audio_events': [
        {
          'id': 'same-audio',
          'session_id': 'same-night',
          'file_path': 'archive-conflict.m4a',
          'category': 'archive-category',
          'captured_at': timestamp,
          'expires_at': '2026-12-01T22:00:00.000Z',
          'duration_ms': 9999,
          'user_corrected': 0,
          'audioDataB64': base64Encode([99, 98, 97]),
        },
        {
          'id': 'archive-audio',
          'session_id': 'archive-night',
          'file_path': 'recording.m4a',
          'category': 'snoring',
          'captured_at': timestamp,
          'expires_at': '2026-12-01T22:00:00.000Z',
          'duration_ms': 1200,
          'user_corrected': 0,
          'audioDataB64': base64Encode(archiveAudioBytes),
        },
      ],
      'morning_reports': <Map<String, Object?>>[],
      'climate_samples': <Map<String, Object?>>[],
    };

    SleepDatabase.instance.setDatabaseForTesting(destination);
    final impact = await SleepDatabase.instance.previewRestoreImpact(
      archive,
      availableBytes: null,
    );
    final document = <String, dynamic>{
      'format': BackupService.format,
      'formatVersion': BackupService.formatVersion,
      'createdAt': timestamp,
      'data': archive,
    };
    final draft = BackupImportDraft.forTesting(
      document: document,
      data: archive,
      preview: BackupImportPreview.fromDocument(document, archive),
      impact: impact,
    );

    final result = await BackupService.instance.restorePreparedBackup(
      draft: draft,
      merge: true,
      documentsDirectoryForTesting: tempDirectory,
    );
    expect(result.isCancelled, isFalse);

    final audioRows = await destination.query('audio_events', orderBy: 'id');
    expect(audioRows, hasLength(2));
    final preserved = audioRows.singleWhere((row) => row['id'] == 'same-audio');
    expect(preserved['file_path'], localAudioPath);
    expect(preserved['category'], 'local-category');
    expect(await File(localAudioPath).readAsBytes(), localAudioBytes);

    final restored = audioRows.singleWhere((row) => row['id'] == 'archive-audio');
    final restoredPath = restored['file_path'] as String;
    expect(restoredPath, contains('audio_events'));
    expect(restoredPath.endsWith('.m4a'), isTrue);
    expect(await File(restoredPath).readAsBytes(), archiveAudioBytes);
  });

}
