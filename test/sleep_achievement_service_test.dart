import 'dart:convert';
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
      CREATE TABLE morning_reports (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        report_date TEXT NOT NULL,
        wellbeing INTEGER,
        sleep_quality INTEGER,
        answers_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');
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
    expect(initial.earnedAt['first_night'], DateTime(2026, 11, 20));
    expect(initial.recordHistory, hasLength(1));
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
    expect(improved.recordHistory, hasLength(2));
    expect(
      improved.recordHistory
          .lastWhere((event) => event.metric == 'longestSleepMinutes')
          .value,
      540,
    );

    final unchanged = await SleepAchievementService.instance.load([
      first,
      better,
    ]);
    expect(unchanged.newRecordKeys, isEmpty);
    expect(unchanged.recordHistory, hasLength(2));

    final afterDeletion = await SleepAchievementService.instance.load([first]);
    expect(afterDeletion.records.longestSleepMinutes, 540);
    expect(afterDeletion.recordHistory, hasLength(2));
    expect(
      afterDeletion.recordHistory
          .lastWhere((event) => event.metric == 'longestSleepMinutes')
          .value,
      540,
    );
  });

  test('migrates legacy SleepScore and awakening record history', () async {
    await database.insert('app_metadata', {
      'key': 'sleep_records_history_v1',
      'value': jsonEncode([
        {
          'type': 'sleep_score',
          'sessionId': 'legacy-score-night',
          'value': 96,
          'achievedAt': '2026-11-19T07:00:00Z',
        },
        {
          'type': 'awakening_count',
          'sessionId': 'legacy-awakening-night',
          'value': 1,
          'achievedAt': '2026-11-19T07:00:00Z',
        },
      ]),
    });

    final first = night(
      id: 'current-night',
      start: DateTime(2026, 11, 20, 22),
      actualMinutes: 480,
    );
    final state = await SleepAchievementService.instance.load([first]);

    expect(state.records.bestSleepScore, 96);
    expect(state.records.fewestAwakenings, 1);
    expect(state.recordHistory.any(
      (event) => event.metric == 'bestSleepScore' && event.value == 96,
    ), isTrue);
    expect(state.recordHistory.any(
      (event) => event.metric == 'fewestAwakenings' && event.value == 1,
    ), isTrue);
  });
}
