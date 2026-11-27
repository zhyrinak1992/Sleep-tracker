import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

void main() {
  late Database database;
  late Directory temporaryDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sleep-tracker-audio-retention-',
    );
    database = await databaseFactoryFfi.openDatabase(
      '${temporaryDirectory.path}/test.db',
    );
    await database.execute('''
      CREATE TABLE sleep_sessions (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE audio_events (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        file_path TEXT,
        category TEXT NOT NULL,
        confidence REAL,
        captured_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        user_corrected INTEGER NOT NULL DEFAULT 0
      )
    ''');
    SleepDatabase.instance.setDatabaseForTesting(database);
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('audio event is linked only to the night interval containing its capture time', () async {
    await database.insert('sleep_sessions', {
      'id': 'night-before',
      'started_at': DateTime.utc(2026, 11, 21, 21).toIso8601String(),
      'ended_at': DateTime.utc(2026, 11, 22, 6).toIso8601String(),
      'deleted_at': null,
    });
    await database.insert('sleep_sessions', {
      'id': 'night-after',
      'started_at': DateTime.utc(2026, 11, 22, 22).toIso8601String(),
      'ended_at': null,
      'deleted_at': null,
    });
    await database.insert('sleep_sessions', {
      'id': 'deleted-night',
      'started_at': DateTime.utc(2026, 11, 22, 12).toIso8601String(),
      'ended_at': DateTime.utc(2026, 11, 22, 13).toIso8601String(),
      'deleted_at': DateTime.utc(2026, 11, 23).toIso8601String(),
    });

    expect(
      await SleepDatabase.instance.getSessionIdForTimestamp(DateTime.utc(2026, 11, 22, 2)),
      'night-before',
    );
    expect(
      await SleepDatabase.instance.getSessionIdForTimestamp(DateTime.utc(2026, 11, 23, 1)),
      'night-after',
    );
    expect(
      await SleepDatabase.instance.getSessionIdForTimestamp(DateTime.utc(2026, 11, 22, 15)),
      isNull,
    );
  });

  test('automatic classification never overwrites a manual correction', () async {
    final now = DateTime.utc(2026, 11, 24, 12);
    await database.insert('audio_events', {
      'id': 'manually-corrected',
      'file_path': null,
      'category': 'cough',
      'confidence': null,
      'captured_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(days: 7)).toIso8601String(),
      'duration_ms': 1200,
      'user_corrected': 0,
    });
    await database.insert('audio_events', {
      'id': 'not-yet-corrected',
      'file_path': null,
      'category': 'unknown',
      'confidence': null,
      'captured_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(days: 7)).toIso8601String(),
      'duration_ms': 1200,
      'user_corrected': 0,
    });

    await SleepDatabase.instance.updateAudioCategory(
      'manually-corrected',
      'snore',
    );
    await SleepDatabase.instance.updateAudioClassification(
      'manually-corrected',
      'cough',
      0.97,
    );
    await SleepDatabase.instance.updateAudioClassification(
      'not-yet-corrected',
      'snore',
      0.91,
    );

    final corrected = (await database.query(
      'audio_events',
      where: 'id = ?',
      whereArgs: ['manually-corrected'],
    )).single;
    expect(corrected['category'], 'snore');
    expect(corrected['confidence'], isNull);
    expect(corrected['user_corrected'], 1);

    final automatic = (await database.query(
      'audio_events',
      where: 'id = ?',
      whereArgs: ['not-yet-corrected'],
    )).single;
    expect(automatic['category'], 'snore');
    expect(automatic['confidence'], 0.91);
    expect(automatic['user_corrected'], 0);
  });

  test('removes expired audio files but retains event history', () async {
    final now = DateTime.utc(2026, 11, 24, 12);
    final expiredFile = File('${temporaryDirectory.path}/expired.wav');
    final recentFile = File('${temporaryDirectory.path}/recent.wav');
    await expiredFile.writeAsBytes([1, 2, 3]);
    await recentFile.writeAsBytes([4, 5, 6]);

    await database.insert('audio_events', {
      'id': 'expired-event',
      'file_path': expiredFile.path,
      'category': 'snore',
      'confidence': 0.9,
      'captured_at': now.subtract(const Duration(days: 8)).toIso8601String(),
      'expires_at': now.toIso8601String(),
      'duration_ms': 1200,
      'user_corrected': 1,
    });
    await database.insert('audio_events', {
      'id': 'recent-event',
      'file_path': recentFile.path,
      'category': 'cough',
      'confidence': 0.8,
      'captured_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      'expires_at': now.add(const Duration(days: 5)).toIso8601String(),
      'duration_ms': 900,
      'user_corrected': 0,
    });

    final removed = await SleepDatabase.instance.deleteExpiredAudioEvents(now);

    expect(removed, 1);
    expect(await expiredFile.exists(), isFalse);
    expect(await recentFile.exists(), isTrue);

    final expiredRows = await database.query(
      'audio_events',
      where: 'id = ?',
      whereArgs: ['expired-event'],
    );
    expect(expiredRows, hasLength(1));
    expect(expiredRows.single['file_path'], isNull);
    expect(expiredRows.single['category'], 'snore');
    expect(expiredRows.single['confidence'], 0.9);
    expect(expiredRows.single['duration_ms'], 1200);
    expect(expiredRows.single['user_corrected'], 1);

    final recentRows = await database.query(
      'audio_events',
      where: 'id = ?',
      whereArgs: ['recent-event'],
    );
    expect(recentRows, hasLength(1));
    expect(recentRows.single['file_path'], recentFile.path);
  });
}
