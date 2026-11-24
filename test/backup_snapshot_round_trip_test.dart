import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

Future<Database> _openDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    source = await _openDatabase();
    destination = await _openDatabase();
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    await source.close();
    await destination.close();
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
}
