import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/features/analysis/sleep_achievement_service.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  late Directory directory;
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sleep_record_history_');
    database = await databaseFactoryFfi.openDatabase(
      '${directory.path}/history.sqlite',
    );
    await database.execute(
      'CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await database.execute('''
      CREATE TABLE sleep_stages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        stage TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    SleepDatabase.instance.setDatabaseForTesting(database);
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    await database.close();
    await directory.delete(recursive: true);
  });

  SleepSession night({
    required String id,
    required DateTime start,
    required int actualMinutes,
  }) {
    final actualStart = start.add(const Duration(minutes: 30));
    return SleepSession(
      id: id,
      startedAt: start,
      endedAt: start.add(const Duration(hours: 9)),
      actualSleepStartedAt: actualStart,
      actualSleepEndedAt: actualStart.add(Duration(minutes: actualMinutes)),
    );
  }

  test('persists only real improvements and keeps history after source deletion',
      () async {
    final first = night(
      id: 'first',
      start: DateTime(2026, 11, 20, 22),
      actualMinutes: 480,
    );
    final better = night(
      id: 'better',
      start: DateTime(2026, 11, 22, 22),
      actualMinutes: 540,
    );

    final initial = await SleepAchievementService.instance.load([first]);
    expect(initial.newRecordKeys, isEmpty);
    expect(initial.recordHistory, hasLength(3));
    expect(
      initial.recordHistory
          .firstWhere((event) => event.metric == 'longestSleepMinutes')
          .value,
      480,
    );

    final improved = await SleepAchievementService.instance.load([
      first,
      better,
    ]);
    expect(improved.newRecordKeys, contains('longestSleep'));
    expect(improved.records.longestSleepMinutes, 540);
    expect(improved.recordHistory, hasLength(4));
    expect(
      improved.recordHistory
          .firstWhere((event) => event.metric == 'longestSleepMinutes')
          .value,
      540,
    );

    final unchanged = await SleepAchievementService.instance.load([
      first,
      better,
    ]);
    expect(unchanged.newRecordKeys, isEmpty);
    expect(unchanged.recordHistory, hasLength(4));

    final afterDeletion = await SleepAchievementService.instance.load([first]);
    expect(afterDeletion.records.longestSleepMinutes, 540);
    expect(afterDeletion.recordHistory, hasLength(4));
    expect(
      afterDeletion.recordHistory
          .firstWhere((event) => event.metric == 'longestSleepMinutes')
          .value,
      540,
    );
  });
}
