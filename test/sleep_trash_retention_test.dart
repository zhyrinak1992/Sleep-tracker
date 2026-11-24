import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

void main() {
  late Database database;
  late Directory temporaryDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE sleep_sessions (
        id TEXT PRIMARY KEY,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE audio_events (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        file_path TEXT
      )
    ''');
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sleep-tracker-trash-retention-',
    );
    SleepDatabase.instance.setDatabaseForTesting(database);
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('purges at exactly 30 days and retains newer and active sessions', () async {
    final now = DateTime.utc(2026, 11, 24, 12);
    final cutoff = now.subtract(const Duration(days: 30));
    final expiredAudio = File('${temporaryDirectory.path}/expired.m4a');
    final recentAudio = File('${temporaryDirectory.path}/recent.m4a');
    await expiredAudio.writeAsBytes([1, 2, 3]);
    await recentAudio.writeAsBytes([4, 5, 6]);

    await database.insert('sleep_sessions', {
      'id': 'expired-at-boundary',
      'deleted_at': cutoff.toIso8601String(),
    });
    await database.insert('sleep_sessions', {
      'id': 'still-in-trash',
      'deleted_at': cutoff.add(const Duration(microseconds: 1)).toIso8601String(),
    });
    await database.insert('sleep_sessions', {
      'id': 'active-session',
      'deleted_at': null,
    });
    await database.insert('audio_events', {
      'id': 'expired-audio',
      'session_id': 'expired-at-boundary',
      'file_path': expiredAudio.path,
    });
    await database.insert('audio_events', {
      'id': 'recent-audio',
      'session_id': 'still-in-trash',
      'file_path': recentAudio.path,
    });

    final deleted = await SleepDatabase.instance.purgeExpiredTrash(now: now);

    expect(deleted, 1);
    final remaining = await database.query('sleep_sessions');
    expect(
      remaining.map((row) => row['id']).toSet(),
      {'still-in-trash', 'active-session'},
    );
    expect(await expiredAudio.exists(), isFalse);
    expect(await recentAudio.exists(), isTrue);
  });
}
