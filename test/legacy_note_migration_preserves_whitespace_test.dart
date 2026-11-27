import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory, openDatabase;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

void main() {
  late Directory directory;
  Database? migratedDatabase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('legacy-note-whitespace-');
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

  test('preserves whitespace and line breaks when migrating a legacy note', () async {
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

    const originalNote = '  Старая заметка\n ';
    const timestamp = '2026-11-20T22:00:00.000Z';
    await legacy.insert('sleep_sessions', {
      'id': 'legacy-note',
      'started_at': timestamp,
      'ended_at': null,
      'source': 'manual',
      'note': originalNote,
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await legacy.close();

    SleepDatabase.instance.setDatabasePathForTesting(path);
    migratedDatabase = await SleepDatabase.instance.database;

    final notes = await migratedDatabase!.query('sleep_notes');
    expect(notes, hasLength(1));
    expect(notes.single['body'], originalNote);
  });
}
