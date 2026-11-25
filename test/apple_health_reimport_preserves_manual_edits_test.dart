import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('apple-health-reimport-');
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    SleepDatabase.instance.setDatabasePathForTesting(null);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('repeat import with the same HealthKit ID preserves manual correction',
      () async {
    final path = '${directory.path}/sleep.sqlite';
    SleepDatabase.instance.setDatabasePathForTesting(path);

    final originalStart = DateTime.utc(2026, 11, 20, 22);
    final originalEnd = DateTime.utc(2026, 11, 21, 7);
    final imported = await SleepDatabase.instance.upsertHealthSession(
      id: 'health_sample_123',
      startedAt: originalStart,
      endedAt: originalEnd,
      sourceName: 'Apple Watch',
    );
    expect(imported, ('health_sample_123', true));

    final correctedStart = DateTime.utc(2026, 11, 20, 22, 30);
    final correctedEnd = DateTime.utc(2026, 11, 21, 6, 45);
    await SleepDatabase.instance.saveSessionRecord(
      id: imported.$1,
      startedAt: correctedStart,
      endedAt: correctedEnd,
      note: 'Исправлено вручную',
    );

    final repeatedImport = await SleepDatabase.instance.upsertHealthSession(
      id: 'health_sample_123',
      startedAt: originalStart,
      endedAt: originalEnd,
      sourceName: 'Apple Watch',
    );

    expect(repeatedImport, ('health_sample_123', false));
    final rows = await (await SleepDatabase.instance.database).query(
      'sleep_sessions',
      where: 'id = ?',
      whereArgs: ['health_sample_123'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['started_at'], correctedStart.toIso8601String());
    expect(rows.single['ended_at'], correctedEnd.toIso8601String());
    expect(rows.single['actual_sleep_started_at'], correctedStart.toIso8601String());
    expect(rows.single['actual_sleep_ended_at'], correctedEnd.toIso8601String());
    expect(rows.single['note'], 'Исправлено вручную');
    expect(rows.single['user_edited'], 1);
  });
}
