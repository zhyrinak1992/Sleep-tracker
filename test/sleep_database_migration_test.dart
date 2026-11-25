import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart'
    show Database, databaseFactory, openDatabase;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

void main() {
  late Directory directory;
  Database? migratedDatabase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sleep-db-migrations-');
    migratedDatabase = null;
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    SleepDatabase.instance.setDatabasePathForTesting(null);
    if (migratedDatabase != null && migratedDatabase!.isOpen) {
      await migratedDatabase!.close();
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('unlimited history query returns records beyond the default page', () async {
    final path = '${directory.path}/complete-history.sqlite';
    SleepDatabase.instance.setDatabasePathForTesting(path);
    migratedDatabase = await SleepDatabase.instance.database;

    for (var index = 0; index < 125; index++) {
      final startedAt = DateTime.utc(2026, 1, 1).add(Duration(days: index));
      final endedAt = startedAt.add(const Duration(hours: 8));
      await migratedDatabase!.insert('sleep_sessions', {
        'id': 'night-$index',
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'source': 'manual',
        'created_at': startedAt.toIso8601String(),
        'updated_at': endedAt.toIso8601String(),
        'user_edited': 1,
      });
    }

    expect(await SleepDatabase.instance.getSessions(), hasLength(100));
    final completeHistory = await SleepDatabase.instance.getSessions(limit: null);
    expect(completeHistory, hasLength(125));
    expect(completeHistory.first.id, 'night-124');
    expect(completeHistory.last.id, 'night-0');
  });

  test('upgrades a v1 database to v8 without losing sleep history or notes',
      () async {
    final path = '${directory.path}/legacy-v1.sqlite';
    final legacy = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sleep_sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            source TEXT NOT NULL,
            note TEXT,
            morning_rating INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_sleep_sessions_started_at ON sleep_sessions(started_at)');
        await db.execute('CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );

    const manualStart = '2026-11-20T22:00:00.000Z';
    const manualEnd = '2026-11-21T07:00:00.000Z';
    const healthStart = '2026-11-21T22:15:00.000Z';
    const healthEnd = '2026-11-22T06:45:00.000Z';
    await legacy.insert('sleep_sessions', {
      'id': 'legacy-manual',
      'started_at': manualStart,
      'ended_at': manualEnd,
      'source': 'manual',
      'note': 'Старая заметка',
      'morning_rating': 4,
      'created_at': manualStart,
      'updated_at': manualEnd,
    });
    await legacy.insert('sleep_sessions', {
      'id': 'legacy-health',
      'started_at': healthStart,
      'ended_at': healthEnd,
      'source': 'apple_health:Apple Watch',
      'note': null,
      'morning_rating': null,
      'created_at': healthStart,
      'updated_at': healthEnd,
    });
    await legacy.insert('app_metadata', {
      'key': 'user_preference',
      'value': 'preserve-me',
    });
    await legacy.close();

    SleepDatabase.instance.setDatabasePathForTesting(path);
    migratedDatabase = await SleepDatabase.instance.database;

    final sessions = await migratedDatabase!.query(
      'sleep_sessions',
      orderBy: 'id',
    );
    expect(sessions, hasLength(2));
    final manual = sessions.singleWhere((row) => row['id'] == 'legacy-manual');
    expect(manual['started_at'], manualStart);
    expect(manual['ended_at'], manualEnd);
    expect(manual['morning_rating'], 4);
    expect(manual['note'], 'Старая заметка');
    expect(manual['button_started_at'], manualStart);
    expect(manual['button_ended_at'], manualEnd);
    expect(manual['actual_sleep_started_at'], isNull);
    expect(manual['actual_sleep_ended_at'], isNull);

    final health = sessions.singleWhere((row) => row['id'] == 'legacy-health');
    expect(health['started_at'], healthStart);
    expect(health['ended_at'], healthEnd);
    expect(health['actual_sleep_started_at'], healthStart);
    expect(health['actual_sleep_ended_at'], healthEnd);
    expect(health['user_edited'], 0);

    final notes = await migratedDatabase!.query('sleep_notes');
    expect(notes, hasLength(1));
    expect(notes.single['session_id'], 'legacy-manual');
    expect(notes.single['body'], 'Старая заметка');
    expect(
      (await migratedDatabase!.query('app_metadata')).single['value'],
      'preserve-me',
    );

    final tables = (await migratedDatabase!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).toSet();
    expect(tables, containsAll([
      'sleep_sessions',
      'sleep_session_tags',
      'sleep_notes',
      'app_metadata',
      'sleep_stages',
      'sleep_metrics',
      'audio_events',
      'morning_reports',
      'climate_samples',
    ]));
    expect(
      (await migratedDatabase!.rawQuery('PRAGMA user_version')).single['user_version'],
      8,
    );
  });

  test('v7 to v8 migration preserves audio event cards and nullable file paths',
      () async {
    final path = '${directory.path}/legacy-v7.sqlite';
    final legacy = await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sleep_sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            source TEXT NOT NULL,
            note TEXT,
            morning_rating INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            button_started_at TEXT,
            button_ended_at TEXT,
            actual_sleep_started_at TEXT,
            actual_sleep_ended_at TEXT,
            user_edited INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE audio_events (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            file_path TEXT,
            category TEXT NOT NULL DEFAULT 'unknown',
            confidence REAL,
            captured_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            user_corrected INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL
          )
        ''');
      },
    );
    const timestamp = '2026-11-22T07:00:00.000Z';
    await legacy.insert('sleep_sessions', {
      'id': 'v7-night',
      'started_at': '2026-11-21T22:00:00.000Z',
      'ended_at': timestamp,
      'source': 'manual',
      'created_at': timestamp,
      'updated_at': timestamp,
      'user_edited': 1,
    });
    await legacy.insert('audio_events', {
      'id': 'audio-with-file',
      'session_id': 'v7-night',
      'file_path': '/tmp/retained-audio.m4a',
      'category': 'snoring',
      'confidence': 0.93,
      'captured_at': timestamp,
      'expires_at': '2026-11-29T07:00:00.000Z',
      'duration_ms': 3400,
      'user_corrected': 1,
    });
    await legacy.insert('audio_events', {
      'id': 'audio-card-only',
      'session_id': 'v7-night',
      'file_path': null,
      'category': 'cough',
      'confidence': 0.72,
      'captured_at': timestamp,
      'expires_at': '2026-11-15T07:00:00.000Z',
      'duration_ms': 800,
      'user_corrected': 0,
    });
    await legacy.close();

    SleepDatabase.instance.setDatabasePathForTesting(path);
    migratedDatabase = await SleepDatabase.instance.database;

    final events = await migratedDatabase!.query('audio_events', orderBy: 'id');
    expect(events, hasLength(2));
    expect(events[0]['id'], 'audio-card-only');
    expect(events[0]['file_path'], isNull);
    expect(events[0]['category'], 'cough');
    expect(events[0]['confidence'], 0.72);
    expect(events[0]['duration_ms'], 800);
    expect(events[0]['user_corrected'], 0);
    expect(events[1]['id'], 'audio-with-file');
    expect(events[1]['file_path'], '/tmp/retained-audio.m4a');
    expect(events[1]['category'], 'snoring');
    expect(events[1]['confidence'], 0.93);
    expect(events[1]['duration_ms'], 3400);
    expect(events[1]['user_corrected'], 1);
    expect(
      (await migratedDatabase!.rawQuery('PRAGMA user_version')).single['user_version'],
      8,
    );
  });
}
