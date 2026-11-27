import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/features/diary/sleep_trash_screen.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Database database;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sleep-trash-widget-');
    SleepDatabase.instance.setDatabasePathForTesting(
      '${directory.path}/sleep.sqlite',
    );
    database = await SleepDatabase.instance.database;
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    SleepDatabase.instance.setDatabasePathForTesting(null);
    await database.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<void> insertTrashedNight(String id, DateTime startedAt) async {
    final deletedAt = DateTime.now().subtract(const Duration(days: 1));
    await database.insert(
      'sleep_sessions',
      SleepSession(
        id: id,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(hours: 8)),
        deletedAt: deletedAt,
      ).toMap(),
    );
  }

  Future<void> openTrash(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SleepTrashScreen(database: SleepDatabase.instance),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selecting several trashed nights updates count and supports deselection',
    (tester) async {
      await insertTrashedNight('night-a', DateTime(2026, 11, 20, 22));
      await insertTrashedNight('night-b', DateTime(2026, 11, 21, 22));
      await insertTrashedNight('night-c', DateTime(2026, 11, 22, 22));
      await openTrash(tester);

      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('Выбрать записи'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.text('Удалить выбранные (0)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      expect(find.text('Удалить выбранные (1)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Удалить выбранные (2)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      expect(find.text('Удалить выбранные (1)'), findsOneWidget);
      expect(
        tester.widgetList<Checkbox>(find.byType(Checkbox))
            .where((checkbox) => checkbox.value == true),
        hasLength(1),
      );

      await tester.tap(find.text('Отмена выбора'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Выбрать записи'), findsOneWidget);
    },
  );
}
