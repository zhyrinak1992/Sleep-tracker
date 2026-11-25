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
    directory = await Directory.systemTemp.createTemp('sleep-button-times-');
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    SleepDatabase.instance.setDatabasePathForTesting(null);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('editing actual sleep interval preserves original button timestamps',
      () async {
    SleepDatabase.instance.setDatabasePathForTesting(
      '${directory.path}/sleep.sqlite',
    );

    final initialStart = DateTime.utc(2026, 11, 20, 22);
    final initialEnd = DateTime.utc(2026, 11, 21, 7);
    await SleepDatabase.instance.saveSessionRecord(
      startedAt: initialStart,
      endedAt: initialEnd,
      note: 'Первоначальная запись',
    );

    final db = await SleepDatabase.instance.database;
    final rows = await db.query(
      'sleep_sessions',
      columns: ['id'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    final id = rows.single['id']! as String;
    final buttonStart = DateTime.utc(2026, 11, 20, 21, 50);
    final buttonEnd = DateTime.utc(2026, 11, 21, 7, 10);
    await db.update(
      'sleep_sessions',
      {
        'button_started_at': buttonStart.toIso8601String(),
        'button_ended_at': buttonEnd.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final correctedStart = DateTime.utc(2026, 11, 20, 22, 25);
    final correctedEnd = DateTime.utc(2026, 11, 21, 6, 40);
    await SleepDatabase.instance.saveSessionRecord(
      id: id,
      startedAt: correctedStart,
      endedAt: correctedEnd,
      note: 'Исправлено вручную',
    );

    final updated = await db.query(
      'sleep_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(updated, hasLength(1));
    expect(updated.single['button_started_at'], buttonStart.toIso8601String());
    expect(updated.single['button_ended_at'], buttonEnd.toIso8601String());
    expect(
      updated.single['actual_sleep_started_at'],
      correctedStart.toIso8601String(),
    );
    expect(
      updated.single['actual_sleep_ended_at'],
      correctedEnd.toIso8601String(),
    );
    expect(updated.single['user_edited'], 1);
    expect(updated.single['note'], 'Исправлено вручную');
  });
}
