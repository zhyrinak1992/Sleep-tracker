import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/features/analysis/periodic_report_service.dart';

void main() {
  group('PeriodicReportSnapshot', () {
    test('decodes a saved weekly report and exposes its period values', () {
      final report = PeriodicReportSnapshot.decode('''
        {
          "schemaVersion": 2,
          "id": "week_2026-11-16",
          "kind": "week",
          "start": "2026-11-16T00:00:00.000",
          "endExclusive": "2026-11-23T00:00:00.000",
          "nights": 5,
          "averageSleepMinutes": 431.5,
          "totalSleepMinutes": 2157,
          "averageTimeInBedMinutes": 472.0,
          "averageEfficiency": 88.2,
          "averageAwakenings": 2.0,
          "averageQuality": 4.0,
          "averageWellbeing": 3.8
        }
      ''');
      expect(report.id, 'week_2026-11-16');
      expect(report.kind, 'week');
      expect(report.nights, 5);
      expect(report.averageSleepMinutes, 431.5);
      expect(report.totalSleepMinutes, 2157);
      expect(report.averageTimeInBedMinutes, 472.0);
      expect(report.averageEfficiency, 88.2);
      expect(report.averageAwakenings, 2.0);
      expect(report.averageQuality, 4.0);
      expect(report.averageWellbeing, 3.8);
      expect(report.title, contains('Неделя'));
    });

    test('keeps missing measurements unavailable rather than converting them to zero', () {
      final report = PeriodicReportSnapshot.decode('''
        {
          "id": "month_2026-10-01",
          "kind": "month",
          "start": "2026-10-01T00:00:00.000",
          "endExclusive": "2026-11-01T00:00:00.000",
          "nights": 2
        }
      ''');
      expect(report.averageSleepMinutes, isNull);
      expect(report.totalSleepMinutes, isNull);
      expect(report.averageTimeInBedMinutes, isNull);
      expect(report.averageEfficiency, isNull);
      expect(report.averageAwakenings, isNull);
      expect(report.averageQuality, isNull);
      expect(report.averageWellbeing, isNull);
    });

    test('rejects malformed snapshot JSON', () {
      expect(() => PeriodicReportSnapshot.decode('[]'), throwsFormatException);
    });

    test('formats quarterly and half-year report titles', () {
      final quarter = PeriodicReportSnapshot.decode('''
        {
          "id": "quarter_2026-04-01",
          "kind": "quarter",
          "start": "2026-04-01T00:00:00.000",
          "endExclusive": "2026-07-01T00:00:00.000",
          "nights": 12
        }
      ''');
      final halfYear = PeriodicReportSnapshot.decode('''
        {
          "id": "halfYear_2026-07-01",
          "kind": "halfYear",
          "start": "2026-07-01T00:00:00.000",
          "endExclusive": "2027-01-01T00:00:00.000",
          "nights": 20
        }
      ''');

      expect(quarter.title, '2 квартал 2026');
      expect(halfYear.title, 'II полугодие 2026');
    });
  });

  test('generates only closed quarterly and half-year archives with correct date bounds', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('periodic-reports-');
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

    await addNight('jan-night', DateTime(2026, 1, 15, 22));
    await addNight('apr-night', DateTime(2026, 4, 15, 22));
    await addNight('jul-night', DateTime(2026, 7, 15, 22));
    await addNight('oct-night', DateTime(2026, 10, 15, 22));

    final service = PeriodicReportService(SleepDatabase.instance);
    final reports = await service.generateClosedReports(now: DateTime(2026, 11, 25));
    final quarters = reports.where((report) => report.kind == 'quarter').toList();
    final halfYears = reports.where((report) => report.kind == 'halfYear').toList();

    expect(quarters.map((report) => report.id).toSet(), {
      'quarter_2026-01-01',
      'quarter_2026-04-01',
      'quarter_2026-07-01',
    });
    expect(halfYears.map((report) => report.id).toSet(), {'halfYear_2026-01-01'});
    expect(reports.any((report) => report.id == 'quarter_2026-10-01'), isFalse);
    expect(reports.any((report) => report.id == 'halfYear_2026-07-01'), isFalse);

    final q2 = quarters.singleWhere((report) => report.id == 'quarter_2026-04-01');
    expect(q2.start, DateTime(2026, 4, 1));
    expect(q2.endExclusive, DateTime(2026, 7, 1));
    expect(q2.nights, 1);
    expect(q2.data['schemaVersion'], 9);
    expect((q2.data['months'] as List).length, 1);

    final h1 = halfYears.single;
    expect(h1.start, DateTime(2026, 1, 1));
    expect(h1.endExclusive, DateTime(2026, 7, 1));
    expect(h1.nights, 2);
    expect((h1.data['months'] as List).length, 2);
  });

}
