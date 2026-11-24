import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

const _tables = [
  'sleep_sessions',
  'sleep_session_tags',
  'sleep_notes',
  'app_metadata',
  'sleep_stages',
  'sleep_metrics',
  'audio_events',
  'morning_reports',
  'climate_samples',
];

Map<String, dynamic> _snapshot(
  List<Map<String, Object?>> metadata, {
  List<Map<String, Object?>> sessions = const [],
}) => {
  'schemaVersion': 8,
  for (final table in _tables)
    table: switch (table) {
      'app_metadata' => metadata,
      'sleep_sessions' => sessions,
      _ => <Map<String, Object?>>[],
    },
};

Future<void> _createMinimalRestoreSchema(Database db) async {
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
      deleted_at TEXT,
      button_started_at TEXT,
      button_ended_at TEXT,
      actual_sleep_started_at TEXT,
      actual_sleep_ended_at TEXT,
      user_edited INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('CREATE TABLE sleep_session_tags (session_id TEXT, tag_key TEXT)');
  await db.execute('CREATE TABLE sleep_notes (id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute('CREATE TABLE sleep_stages (id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE sleep_metrics (id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE audio_events (id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE morning_reports (session_id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE climate_samples (id TEXT PRIMARY KEY)');
}

void main() {
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createMinimalRestoreSchema(database);
    SleepDatabase.instance.setDatabaseForTesting(database);
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    await database.close();
  });

  test('trash, restore from trash, merge backup and full backup restore preserve record history', () async {
    const sessionId = 'night-cycle';
    final start = DateTime.utc(2026, 11, 20, 22);
    final end = DateTime.utc(2026, 11, 21, 7);
    final archiveSession = <String, Object?>{
      'id': sessionId,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'source': 'manual',
      'note': null,
      'morning_rating': 4,
      'created_at': start.toIso8601String(),
      'updated_at': end.toIso8601String(),
      'deleted_at': null,
      'button_started_at': null,
      'button_ended_at': null,
      'actual_sleep_started_at': null,
      'actual_sleep_ended_at': null,
      'user_edited': 0,
    };
    final recordEvent = {
      'type': 'sleep_score',
      'sessionId': sessionId,
      'value': 94,
      'achievedAt': end.toIso8601String(),
    };
    final archiveMetadata = <Map<String, Object?>>[
      {
        'key': 'sleep_records_history_v1',
        'value': jsonEncode([recordEvent]),
      },
      {
        'key': 'sleep_records_celebrated_v1',
        'value': jsonEncode(['sleep_score|$sessionId|94']),
      },
      {
        'key': 'sleep_personal_records_v1',
        'value': jsonEncode({
          'bestSleepScore': 94,
          'bestSleepScoreSessionId': sessionId,
        }),
      },
    ];

    await database.insert('sleep_sessions', archiveSession);
    for (final row in archiveMetadata) {
      await database.insert('app_metadata', row);
    }

    // Moving a night to trash hides it from normal history but does not erase
    // the original session or the already-earned record metadata.
    await SleepDatabase.instance.moveSessionToTrash(sessionId);
    expect(await SleepDatabase.instance.getSessions(), isEmpty);
    final trashed = await SleepDatabase.instance.getSessionById(sessionId);
    expect(trashed, isNotNull);
    expect(trashed!.deletedAt, isNotNull);
    expect(
      await SleepDatabase.instance.getAppMetadata('sleep_records_history_v1'),
      jsonEncode([recordEvent]),
    );

    // Restoring from the trash makes the original night visible again.
    await SleepDatabase.instance.restoreSessionFromTrash(sessionId);
    expect(await SleepDatabase.instance.getSessions(), hasLength(1));
    expect(
      (await SleepDatabase.instance.getSessionById(sessionId))!.deletedAt,
      isNull,
    );

    // A merge restore must not silently undelete a locally trashed night:
    // existing local session rows keep priority over archive rows.
    await SleepDatabase.instance.moveSessionToTrash(sessionId);
    await SleepDatabase.instance.restoreSnapshot(
      _snapshot(archiveMetadata, sessions: [archiveSession]),
      merge: true,
    );
    final afterMerge = await SleepDatabase.instance.getSessionById(sessionId);
    expect(afterMerge, isNotNull);
    expect(afterMerge!.deletedAt, isNotNull);

    // A full restore replaces local state with the archive state, including
    // the archive's active session and the record/celebration metadata.
    await SleepDatabase.instance.restoreSnapshot(
      _snapshot(archiveMetadata, sessions: [archiveSession]),
    );
    final afterFullRestore = await SleepDatabase.instance.getSessionById(sessionId);
    expect(afterFullRestore, isNotNull);
    expect(afterFullRestore!.deletedAt, isNull);
    expect(await SleepDatabase.instance.getSessions(), hasLength(1));
    expect(
      await SleepDatabase.instance.getAppMetadata('sleep_records_history_v1'),
      jsonEncode([recordEvent]),
    );
    expect(
      await SleepDatabase.instance.getAppMetadata('sleep_records_celebrated_v1'),
      jsonEncode(['sleep_score|$sessionId|94']),
    );
  });

  test('merge restore persists unified achievement metadata in a real SQLite transaction', () async {
    final localScore = {
      'type': 'sleep_score',
      'sessionId': 'night-local',
      'value': 91,
      'achievedAt': '2026-11-20T07:00:00Z',
    };
    final archiveScoreForSameNight = {
      ...localScore,
      'value': 84,
      'achievedAt': '2026-11-19T07:00:00Z',
    };
    final archiveScoreForNewNight = {
      'type': 'sleep_score',
      'sessionId': 'night-archive',
      'value': 97,
      'achievedAt': '2026-11-21T07:00:00Z',
    };

    final localMetadata = <String, String>{
      'theme': 'dark',
      'sleep_achievements_history_v1': jsonEncode({
        'first_night': '2026-11-20T08:00:00Z',
      }),
      'sleep_personal_records_v1': jsonEncode({
        'longestSleepMinutes': 500,
        'longestSleepSessionId': 'local-longest',
        'bestEfficiencyPercent': 90,
        'bestEfficiencySessionId': 'local-efficiency',
        'shortestLatencyMinutes': 10,
        'shortestLatencySessionId': 'local-latency',
        'longestStreakDays': 8,
      }),
      'sleep_records_history_v1': jsonEncode([localScore]),
      'sleep_records_celebrated_v1': jsonEncode(['already-celebrated']),
    };
    for (final entry in localMetadata.entries) {
      await database.insert('app_metadata', {
        'key': entry.key,
        'value': entry.value,
      });
    }

    final archiveMetadata = <Map<String, Object?>>[
      {
        'key': 'theme',
        'value': 'light',
      },
      {
        'key': 'sleep_achievements_history_v1',
        'value': jsonEncode({
          'first_night': '2026-11-22T08:00:00Z',
          'seven_nights': '2026-11-21T08:00:00Z',
        }),
      },
      {
        'key': 'sleep_personal_records_v1',
        'value': jsonEncode({
          'longestSleepMinutes': 550,
          'longestSleepSessionId': 'archive-longest',
          'bestEfficiencyPercent': 96,
          'bestEfficiencySessionId': 'archive-efficiency',
          'shortestLatencyMinutes': 4,
          'shortestLatencySessionId': 'archive-latency',
          'longestStreakDays': 12,
        }),
      },
      {
        'key': 'sleep_records_history_v1',
        'value': jsonEncode([archiveScoreForSameNight, archiveScoreForNewNight]),
      },
      {
        'key': 'sleep_records_celebrated_v1',
        'value': jsonEncode(['already-celebrated', 'new-celebration']),
      },
    ];

    await SleepDatabase.instance.restoreSnapshot(
      _snapshot(archiveMetadata),
      merge: true,
    );

    final rows = await database.query('app_metadata');
    final metadata = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };

    expect(metadata['theme'], 'dark');

    final achievements = jsonDecode(
      metadata['sleep_achievements_history_v1']!,
    ) as Map<String, dynamic>;
    expect(achievements['first_night'], '2026-11-20T08:00:00.000Z');
    expect(achievements['seven_nights'], '2026-11-21T08:00:00.000Z');

    final records = jsonDecode(
      metadata['sleep_personal_records_v1']!,
    ) as Map<String, dynamic>;
    expect(records['longestSleepMinutes'], 550);
    expect(records['longestSleepSessionId'], 'archive-longest');
    expect(records['bestEfficiencyPercent'], 96);
    expect(records['bestEfficiencySessionId'], 'archive-efficiency');
    expect(records['shortestLatencyMinutes'], 4);
    expect(records['shortestLatencySessionId'], 'archive-latency');
    expect(records['longestStreakDays'], 12);

    final history = jsonDecode(
      metadata['sleep_records_history_v1']!,
    ) as List<dynamic>;
    expect(history, hasLength(2));
    expect(
      history.singleWhere((event) => event['sessionId'] == 'night-local')['value'],
      91,
    );
    expect(
      history.singleWhere((event) => event['sessionId'] == 'night-archive')['value'],
      97,
    );

    final celebrated = (jsonDecode(
      metadata['sleep_records_celebrated_v1']!,
    ) as List<dynamic>).toSet();
    expect(celebrated, {'already-celebrated', 'new-celebration'});

    // Restoring the same archive again must be idempotent: no duplicate
    // record events, achievement dates, or celebration acknowledgements.
    final metadataAfterFirstRestore = Map<String, String>.from(metadata);
    await SleepDatabase.instance.restoreSnapshot(
      _snapshot(archiveMetadata),
      merge: true,
    );
    final rowsAfterSecondRestore = await database.query('app_metadata');
    final metadataAfterSecondRestore = {
      for (final row in rowsAfterSecondRestore)
        row['key'] as String: row['value'] as String,
    };
    expect(metadataAfterSecondRestore, metadataAfterFirstRestore);
  });
}
