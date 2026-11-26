import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/features/analysis/periodic_report_export.dart';
import 'package:sleep_tracker/features/analysis/periodic_report_service.dart';

void main() {
  test('creates, archives and exports a custom inclusive calendar date range', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('custom-periodic-report-');
    Database? openedDatabase;
    addTearDown(() async {
      await openedDatabase?.close();
      SleepDatabase.instance.setDatabaseForTesting(null);
      SleepDatabase.instance.setDatabasePathForTesting(null);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    SleepDatabase.instance.setDatabasePathForTesting('${directory.path}/sleep.sqlite');
    final db = await SleepDatabase.instance.database;
    openedDatabase = db;

    Future<void> addNight(String id, DateTime start) async {
      await db.insert('sleep_sessions', {
        'id': id,
        'started_at': start.toIso8601String(),
        'ended_at': start.add(const Duration(hours: 8)).toIso8601String(),
        'source': 'manual',
        'created_at': start.toIso8601String(),
        'updated_at': start.toIso8601String(),
        'user_edited': 0,
      });
    }

    await addNight('before-range', DateTime(2026, 3, 9, 22));
    await addNight('in-range-one', DateTime(2026, 3, 10, 22));
    await addNight('in-range-two', DateTime(2026, 3, 12, 22));
    await addNight('after-range', DateTime(2026, 3, 14, 22));

    final service = PeriodicReportService(SleepDatabase.instance);
    final report = await service.generateCustomRangeReport(
      startDate: DateTime(2026, 3, 10, 15),
      endDateInclusive: DateTime(2026, 3, 12, 9),
    );

    expect(report.kind, 'customRange');
    expect(report.id, 'range_20260310_20260312');
    expect(report.start, DateTime(2026, 3, 10));
    expect(report.endExclusive, DateTime(2026, 3, 13));
    expect(report.title, 'Отчёт за 10.03.2026 — 12.03.2026');
    expect(report.nights, 2);
    final trend = (report.data['trendPoints'] as List).whereType<Map>().toList();
    expect(trend, hasLength(2));
    expect((trend.first['nights'] as List).single['sessionId'], 'in-range-one');
    expect((trend.last['nights'] as List).single['sessionId'], 'in-range-two');

    final archive = await service.loadArchive();
    expect(archive.any((item) => item.id == report.id), isTrue);
    final csv = PeriodicReportExport.toCsv(report.data);
    expect(csv, contains('Произвольный период'));
    expect(csv, contains('in-range-one'), isFalse,
        reason: 'CSV includes aggregated values; IDs are retained in the report snapshot, not exported as personal identifiers.');
    expect(csv, contains('Динамика внутри периода'));
  });

  test('rejects reversed custom report date ranges', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('custom-periodic-report-invalid-');
    Database? openedDatabase;
    addTearDown(() async {
      await openedDatabase?.close();
      SleepDatabase.instance.setDatabaseForTesting(null);
      SleepDatabase.instance.setDatabasePathForTesting(null);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    SleepDatabase.instance.setDatabasePathForTesting('${directory.path}/sleep.sqlite');
    openedDatabase = await SleepDatabase.instance.database;
    await expectLater(
      PeriodicReportService(SleepDatabase.instance).generateCustomRangeReport(
        startDate: DateTime(2026, 3, 12),
        endDateInclusive: DateTime(2026, 3, 10),
      ),
      throwsArgumentError,
    );
  });
}
