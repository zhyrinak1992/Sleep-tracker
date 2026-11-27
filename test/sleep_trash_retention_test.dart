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
    await database.execute('PRAGMA foreign_keys = ON');
    await database.execute('''
      CREATE TABLE sleep_sessions (
        id TEXT PRIMARY KEY,
        ended_at TEXT,
        deleted_at TEXT,
        updated_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE audio_events (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        file_path TEXT,
        FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
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

  test('moving several sessions to trash is atomic and rejects active sessions', () async {
    final now = DateTime.now().toUtc();
    await database.insert('sleep_sessions', {
      'id': 'finished',
      'ended_at': now.toIso8601String(),
      'deleted_at': null,
      'updated_at': now.toIso8601String(),
    });
    await database.insert('sleep_sessions', {
      'id': 'active',
      'ended_at': null,
      'deleted_at': null,
      'updated_at': now.toIso8601String(),
    });

    await expectLater(
      SleepDatabase.instance.moveSessionsToTrash(['finished', 'active']),
      throwsStateError,
    );
    var rows = await database.query('sleep_sessions', orderBy: 'id');
    expect(rows.every((row) => row['deleted_at'] == null), isTrue);

    await SleepDatabase.instance.moveSessionsToTrash(['finished', 'finished']);
    rows = await database.query('sleep_sessions', where: 'id = ?', whereArgs: ['finished']);
    expect(rows.single['deleted_at'], isNotNull);
  });

  test('selective permanent deletion removes only selected trash and its audio files', () async {
    final now = DateTime.now().toUtc();
    final selectedAudio = File('${temporaryDirectory.path}/selected.m4a');
    final retainedAudio = File('${temporaryDirectory.path}/retained.m4a');
    await selectedAudio.writeAsBytes([1, 2, 3]);
    await retainedAudio.writeAsBytes([4, 5, 6]);
    for (final id in ['selected', 'retained', 'active']) {
      await database.insert('sleep_sessions', {
        'id': id,
        'ended_at': now.toIso8601String(),
        'deleted_at': id == 'active' ? null : now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }
    await database.insert('audio_events', {
      'id': 'selected-event',
      'session_id': 'selected',
      'file_path': selectedAudio.path,
    });
    await database.insert('audio_events', {
      'id': 'retained-event',
      'session_id': 'retained',
      'file_path': retainedAudio.path,
    });

    await SleepDatabase.instance.permanentlyDeleteSessions(['selected']);

    final sessions = await database.query('sleep_sessions');
    expect(sessions.map((row) => row['id']).toSet(), {'retained', 'active'});
    final events = await database.query('audio_events');
    expect(events.map((row) => row['id']).toSet(), {'retained-event'});
    expect(await selectedAudio.exists(), isFalse);
    expect(await retainedAudio.exists(), isTrue);
  });

  test('restoring one item leaves other trashed items untouched', () async {
    final now = DateTime.now().toUtc();
    for (final id in ['restore-me', 'leave-in-trash']) {
      await database.insert('sleep_sessions', {
        'id': id,
        'deleted_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }

    await SleepDatabase.instance.restoreSessionFromTrash('restore-me');

    final rows = await database.query('sleep_sessions', orderBy: 'id');
    expect(rows.firstWhere((row) => row['id'] == 'restore-me')['deleted_at'], isNull);
    expect(rows.firstWhere((row) => row['id'] == 'leave-in-trash')['deleted_at'], isNotNull);
  });

  test('clearing the trash permanently removes trashed rows but keeps active sessions', () async {
    final now = DateTime.now().toUtc();
    for (final id in ['trashed-a', 'trashed-b', 'active']) {
      await database.insert('sleep_sessions', {
        'id': id,
        'deleted_at': id == 'active' ? null : now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }

    await SleepDatabase.instance.permanentlyDeleteAllTrashedSessions();

    final rows = await database.query('sleep_sessions');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'active');
  });

  test('single restore cannot revive a record after the 30-day retention period', () async {
    final expiredAt = DateTime.now().toUtc().subtract(
      const Duration(days: 30, seconds: 2),
    );
    await database.insert('sleep_sessions', {
      'id': 'expired',
      'deleted_at': expiredAt.toIso8601String(),
      'updated_at': expiredAt.toIso8601String(),
    });

    await expectLater(
      SleepDatabase.instance.restoreSessionFromTrash('expired'),
      throwsStateError,
    );
    expect(await database.query('sleep_sessions'), isEmpty);
  });

  test('restore all purges expired records and restores only records still within retention', () async {
    final now = DateTime.now().toUtc();
    final expiredAt = now.subtract(const Duration(days: 31));
    final recentAt = now.subtract(const Duration(days: 29));
    await database.insert('sleep_sessions', {
      'id': 'expired',
      'deleted_at': expiredAt.toIso8601String(),
      'updated_at': expiredAt.toIso8601String(),
    });
    await database.insert('sleep_sessions', {
      'id': 'recent',
      'deleted_at': recentAt.toIso8601String(),
      'updated_at': recentAt.toIso8601String(),
    });

    final restored = await SleepDatabase.instance.restoreAllTrashedSessions();

    expect(restored, 1);
    final rows = await database.query('sleep_sessions');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'recent');
    expect(rows.single['deleted_at'], isNull);
  });

  test('trash listing purges expired records before returning items', () async {
    final expiredAt = DateTime.now().toUtc().subtract(
      const Duration(days: 31),
    );
    await database.insert('sleep_sessions', {
      'id': 'expired',
      'deleted_at': expiredAt.toIso8601String(),
      'updated_at': expiredAt.toIso8601String(),
    });

    final items = await SleepDatabase.instance.getTrashedSessions();

    expect(items, isEmpty);
    expect(await database.query('sleep_sessions'), isEmpty);
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
