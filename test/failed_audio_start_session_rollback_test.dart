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
    directory = await Directory.systemTemp.createTemp('sleep-start-rollback-');
    SleepDatabase.instance.setDatabasePathForTesting(
      '${directory.path}/sleep.sqlite',
    );
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    SleepDatabase.instance.setDatabasePathForTesting(null);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('discards only an unfinished session after audio startup failure',
      () async {
    final failedAttempt = await SleepDatabase.instance.startSession();
    await SleepDatabase.instance.discardUnstartedSession(failedAttempt.id);

    expect(await SleepDatabase.instance.getOpenSession(), isNull);
    expect(await SleepDatabase.instance.getSessionById(failedAttempt.id), isNull);

    final completed = await SleepDatabase.instance.startSession();
    await SleepDatabase.instance.finishSession(completed.id);

    await expectLater(
      SleepDatabase.instance.discardUnstartedSession(completed.id),
      throwsA(isA<StateError>()),
    );
    expect(
      await SleepDatabase.instance.getSessionById(completed.id),
      isNotNull,
    );
  });
}
