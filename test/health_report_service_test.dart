import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/features/health/health_report_service.dart';
import 'package:sleep_tracker/models/sleep_session.dart';

void main() {
  late Directory directory;
  Database? database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('health-reports-');
    SleepDatabase.instance.setDatabasePathForTesting('${directory.path}/health.sqlite');
    database = await SleepDatabase.instance.database;
  });

  tearDown(() async {
    SleepDatabase.instance.setDatabaseForTesting(null);
    SleepDatabase.instance.setDatabasePathForTesting(null);
    if (database != null && database!.isOpen) await database!.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  group('HealthReportService', () {
    final sessions = {
      'night-a': SleepSession(
        id: 'night-a',
        startedAt: DateTime(2026, 10, 1, 22),
        endedAt: DateTime(2026, 10, 2, 6),
      ),
      'night-b': SleepSession(
        id: 'night-b',
        startedAt: DateTime(2026, 10, 2, 22),
        endedAt: DateTime(2026, 10, 3, 6),
      ),
    };

    test('averages samples within each night before averaging nights', () {
      final summaries = HealthReportService.summarizeMetrics(
        sessionsById: sessions,
        rows: [
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 60, 'source': 'Apple Watch'},
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 80, 'source': 'Apple Watch'},
          {'session_id': 'night-b', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 90, 'source': 'Apple Watch'},
        ],
      );

      expect(summaries, hasLength(1));
      final pulse = summaries.single;
      expect(pulse['average'], 80);
      expect(pulse['median'], 80);
      expect(pulse['minimum'], 70);
      expect(pulse['maximum'], 90);
      expect(pulse['nightCount'], 2);
      expect(pulse['measurementCount'], 3);
      expect(pulse['sources'], ['Apple Watch']);
    });

    test('keeps different units separate and ignores invalid or unrelated rows', () {
      final summaries = HealthReportService.summarizeMetrics(
        sessionsById: sessions,
        rows: [
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 60},
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'bpm', 'value': 62},
          {'session_id': 'missing-night', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': 70},
          {'session_id': 'night-a', 'metric_type': 'Пульс', 'unit': 'уд/мин', 'value': double.nan},
        ],
      );

      expect(summaries, hasLength(2));
      expect(summaries.map((item) => item['unit']).toSet(), {'bpm', 'уд/мин'});
      expect(summaries.every((item) => item['nightCount'] == 1), isTrue);
    });

    test('decodes saved report and formats weekly monthly and annual titles', () {
      final report = HealthReportSnapshot.decode('''
        {
          "id": "month_2026-10-01",
          "kind": "month",
          "start": "2026-10-01T00:00:00.000",
          "endExclusive": "2026-11-01T00:00:00.000",
          "nights": 5,
          "metrics": []
        }
      ''');
      expect(report.nights, 5);
      expect(report.title, 'Физиологический отчёт — октября 2026');
    });


    test('keeps selected health ranges on local calendar dates across DST', () {
      final start = HealthReportService.lastDaysStart(
        DateTime(2026, 3, 30, 12),
        7,
      );
      expect(start, DateTime(2026, 3, 24));
      expect(start.hour, 0);

      final shifted = HealthReportService.shiftCalendarDays(
        DateTime(2026, 3, 30),
        -7,
      );
      expect(shifted, DateTime(2026, 3, 23));
      expect(shifted.hour, 0);

      final exclusiveEnd = HealthReportService.calendarDayAfter(
        DateTime(2026, 3, 29),
      );
      expect(exclusiveEnd, DateTime(2026, 3, 30));
      expect(exclusiveEnd.hour, 0);

      expect(
        HealthReportService.inclusiveCalendarDays(
          DateTime(2026, 3, 28),
          DateTime(2026, 3, 30),
        ),
        3,
      );
    });

    test('keeps weekly and monthly trend boundaries at local midnight across DST', () {
      final nextWeek = HealthReportService.nextPeriodStartForTesting(
        DateTime(2026, 3, 23),
        HealthReportKind.week,
      );
      expect(nextWeek, DateTime(2026, 3, 30));
      expect(nextWeek.hour, 0);

      final previousWeek = HealthReportService.previousPeriodStartForTesting(
        DateTime(2026, 3, 30),
        HealthReportKind.week,
      );
      expect(previousWeek, DateTime(2026, 3, 23));
      expect(previousWeek.hour, 0);

      final week = HealthReportService.trendIntervalsForTesting(
        HealthReportKind.week,
        DateTime(2026, 3, 23),
        DateTime(2026, 3, 30),
      );
      expect(week.last.$1, DateTime(2026, 3, 29));
      expect(week.last.$2, DateTime(2026, 3, 30));
      expect(week.every((interval) => interval.$1.hour == 0 && interval.$2.hour == 0), isTrue);

      final month = HealthReportService.trendIntervalsForTesting(
        HealthReportKind.month,
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
      );
      expect(month.map((interval) => interval.$1.day).toList(), [1, 8, 15, 22, 29]);
      expect(month.last.$2, DateTime(2026, 4, 1));
      expect(month.every((interval) => interval.$1.hour == 0 && interval.$2.hour == 0), isTrue);
    });


    test('derives the inclusive report end from the calendar date across DST', () {
      final report = HealthReportSnapshot.decode('''
        {
          "id": "week_2026-03-23",
          "kind": "week",
          "start": "2026-03-23T00:00:00.000",
          "endExclusive": "2026-03-30T00:00:00.000",
          "nights": 1,
          "metrics": []
        }
      ''');
      expect(report.endInclusive, DateTime(2026, 3, 29));
      expect(report.endInclusive.hour, 0);
    });


    test('generates and persists closed weekly monthly and annual health reports', () async {
      Future<void> addNight({
        required String id,
        required DateTime start,
      }) async {
        final end = start.add(const Duration(hours: 8));
        await database!.insert('sleep_sessions', {
          'id': id,
          'started_at': start.toIso8601String(),
          'ended_at': end.toIso8601String(),
          'source': 'apple_health:Apple Watch',
          'created_at': start.toIso8601String(),
          'updated_at': end.toIso8601String(),
          'actual_sleep_started_at': start.toIso8601String(),
          'actual_sleep_ended_at': end.toIso8601String(),
          'user_edited': 0,
        });
        await database!.insert('sleep_metrics', {
          'id': 'metric-$id',
          'session_id': id,
          'metric_type': 'HEART_RATE',
          'value': 61.0,
          'unit': 'bpm',
          'measured_at': start.add(const Duration(hours: 2)).toIso8601String(),
          'source': 'Apple Watch',
        });
      }

      await addNight(id: 'night-2025', start: DateTime.utc(2025, 10, 1, 22));
      await addNight(id: 'night-2026', start: DateTime.utc(2026, 10, 1, 22));

      final service = HealthReportService(SleepDatabase.instance);
      final reports = await service.generateClosedReports(now: DateTime(2026, 11, 25));
      expect(reports.where((report) => report.kind == 'week'), hasLength(2));
      expect(reports.where((report) => report.kind == 'month'), hasLength(2));
      expect(reports.where((report) => report.kind == 'year'), hasLength(1));
      expect(reports.every((report) => report.metrics.isNotEmpty), isTrue);

      final stored = await SleepDatabase.instance.getAppMetadataByPrefix(
        HealthReportService.storagePrefix,
      );
      expect(stored, hasLength(5));
      final repeated = await service.generateClosedReports(now: DateTime(2026, 11, 25));
      expect(repeated, hasLength(5));
      expect(
        await SleepDatabase.instance.getAppMetadataByPrefix(HealthReportService.storagePrefix),
        hasLength(5),
      );
    });

    test('does not create metric summaries for absent data', () {
      expect(
        HealthReportService.summarizeMetrics(rows: [], sessionsById: sessions),
        isEmpty,
      );
    });
  });
}
