import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/pdf_report_service.dart';
import 'package:sleep_tracker/data/sleep_database.dart';
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
    directory = await Directory.systemTemp.createTemp('single-night-pdf-');
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

  Future<void> insertNight(String id, DateTime start) async {
    final session = SleepSession(
      id: id,
      startedAt: start,
      endedAt: start.add(const Duration(hours: 8)),
      source: 'manual',
      note: null,
    );
    await database.insert('sleep_sessions', session.toMap());
  }

  test('renders a valid PDF using only the selected night data', () async {
    final start = DateTime(2026, 11, 20, 22);
    await insertNight('selected-night', start);
    await insertNight('unrelated-night', DateTime(2026, 11, 21, 22));

    await database.insert('sleep_stages', {
      'id': 'selected-stage',
      'session_id': 'selected-night',
      'stage': 'REM',
      'started_at': start.add(const Duration(hours: 2)).toUtc().toIso8601String(),
      'ended_at': start.add(const Duration(hours: 3)).toUtc().toIso8601String(),
      'source': 'apple_health',
    });
    await database.insert('sleep_metrics', {
      'id': 'selected-metric',
      'session_id': 'selected-night',
      'metric_type': 'heart_rate',
      'value': 58.0,
      'unit': 'bpm',
      'measured_at': start.add(const Duration(hours: 2)).toUtc().toIso8601String(),
      'source': 'apple_health',
    });
    await database.insert('morning_reports', {
      'id': 'selected-morning',
      'session_id': 'selected-night',
      'report_date': '2026-11-21',
      'wellbeing': 4,
      'sleep_quality': 5,
      'answers_json': '{}',
      'created_at': DateTime.utc(2026, 11, 21).toIso8601String(),
    });
    await database.insert('sleep_notes', {
      'id': 'selected-note',
      'session_id': 'selected-night',
      'body': 'Заметка выбранной ночи',
      'created_at': DateTime.utc(2026, 11, 21).toIso8601String(),
      'updated_at': DateTime.utc(2026, 11, 21).toIso8601String(),
    });

    final selected = SleepSession(
      id: 'selected-night',
      startedAt: start,
      endedAt: start.add(const Duration(hours: 8)),
      source: 'manual',
    );
    final baseline = await PdfReportService.buildSingleNightPdfBytes(
      database: SleepDatabase.instance,
      session: selected,
      generatedAt: DateTime(2026, 11, 26, 12),
    );
    expect(_isPdf(baseline), isTrue);
    expect(baseline.length, greaterThan(1500));

    // A large note and several measurements attached to another night must
    // not leak into the selected night's report.
    await database.insert('sleep_notes', {
      'id': 'unrelated-large-note',
      'session_id': 'unrelated-night',
      'body': List.filled(3000, 'ДРУГАЯ НОЧЬ ').join(),
      'created_at': DateTime.utc(2026, 11, 22).toIso8601String(),
      'updated_at': DateTime.utc(2026, 11, 22).toIso8601String(),
    });
    await database.insert('sleep_stages', {
      'id': 'unrelated-stage',
      'session_id': 'unrelated-night',
      'stage': 'Deep',
      'started_at': DateTime.utc(2026, 11, 22, 1).toIso8601String(),
      'ended_at': DateTime.utc(2026, 11, 22, 2).toIso8601String(),
      'source': 'apple_health',
    });
    final afterUnrelatedData = await PdfReportService.buildSingleNightPdfBytes(
      database: SleepDatabase.instance,
      session: selected,
      generatedAt: DateTime(2026, 11, 26, 12),
    );
    expect(_isPdf(afterUnrelatedData), isTrue);
    expect(
      afterUnrelatedData.length,
      baseline.length,
      reason: 'The report must query only the selected session ID.',
    );
  });

  test('renders a valid PDF when optional observations are absent', () async {
    final start = DateTime(2026, 11, 22, 23);
    await insertNight('night-with-gaps', start);
    final bytes = await PdfReportService.buildSingleNightPdfBytes(
      database: SleepDatabase.instance,
      session: SleepSession(
        id: 'night-with-gaps',
        startedAt: start,
        endedAt: start.add(const Duration(hours: 7)),
      ),
      generatedAt: DateTime(2026, 11, 26, 12),
    );

    expect(_isPdf(bytes), isTrue);
    expect(bytes.length, greaterThan(1000));
  });

  test('rejects an unfinished night before attempting PDF generation', () async {
    final start = DateTime(2026, 11, 23, 22);
    final openSession = SleepSession(
      id: 'unfinished',
      startedAt: start,
    );

    await expectLater(
      PdfReportService.buildSingleNightPdfBytes(
        database: SleepDatabase.instance,
        session: openSession,
        generatedAt: DateTime(2026, 11, 26, 12),
      ),
      throwsStateError,
    );
  });
}

bool _isPdf(Uint8List bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2D;
