import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sleep_tracker/data/sleep_database.dart';
import 'package:sleep_tracker/features/analysis/periodic_report_service.dart';
import 'package:sleep_tracker/features/analysis/tag_insight_history.dart';

Map<String, Object?> _patterns(
  double? difference, {
  bool sufficient = true,
  int withSamples = 4,
  int withoutSamples = 4,
}) => {
  'current': [
    {
      'tagKey': 'caffeine',
      'label': 'Кофеин',
      'metrics': {
        'duration': {
          'isSufficient': sufficient,
          'withTagAverage': difference == null ? null : 450.0,
          'withoutTagAverage': difference == null ? null : 450.0 - difference,
          'difference': difference,
          'withTagSamples': withSamples,
          'withoutTagSamples': withoutSamples,
        },
      },
    },
  ],
  'previous': const [],
};

void main() {
  group('TagInsightHistoryStore', () {
    test('compares updates only with the previous snapshot for the same calendar period', () async {
      String? stored;
      final store = TagInsightHistoryStore(
        (key) async => key == TagInsightHistoryStore.metadataKey ? stored : null,
        (key, value) async {
          if (key == TagInsightHistoryStore.metadataKey) stored = value;
        },
      );
      final novemberStart = DateTime(2026, 11);
      final novemberEnd = DateTime(2026, 12);
      final decemberStart = DateTime(2026, 12);
      final decemberEnd = DateTime(2027, 1);

      await store.record(
        fingerprint: 'november-first',
        generatedAt: DateTime(2026, 11, 10),
        periodStart: novemberStart,
        periodEndExclusive: novemberEnd,
        tagPatterns: _patterns(60),
      );
      final december = await store.record(
        fingerprint: 'december-first',
        generatedAt: DateTime(2026, 12, 10),
        periodStart: decemberStart,
        periodEndExclusive: decemberEnd,
        tagPatterns: _patterns(20),
      );
      expect(
        ((december!['insights'] as List).single as Map)['status'],
        'new',
      );

      final november = await store.record(
        fingerprint: 'november-second',
        generatedAt: DateTime(2026, 12, 11),
        periodStart: novemberStart,
        periodEndExclusive: novemberEnd,
        tagPatterns: _patterns(45),
      );
      expect(
        ((november!['insights'] as List).single as Map)['status'],
        'weakened',
      );
      expect(await store.loadHistory(), hasLength(3));
    });

    test('records new, weakened, no-longer-observed and insufficient statuses', () async {
      String? stored;
      final store = TagInsightHistoryStore(
        (key) async => key == TagInsightHistoryStore.metadataKey ? stored : null,
        (key, value) async {
          if (key == TagInsightHistoryStore.metadataKey) stored = value;
        },
      );
      final start = DateTime(2026, 11);
      final end = DateTime(2026, 12);

      final first = await store.record(
        fingerprint: 'one',
        generatedAt: DateTime(2026, 11, 10),
        periodStart: start,
        periodEndExclusive: end,
        tagPatterns: _patterns(60),
      );
      expect(first!['insights'], hasLength(1));
      var insight = (first['insights'] as List).single as Map;
      expect(insight['status'], 'new');

      final duplicate = await store.record(
        fingerprint: 'one',
        generatedAt: DateTime(2026, 11, 11),
        periodStart: start,
        periodEndExclusive: end,
        tagPatterns: _patterns(60),
      );
      expect(duplicate, isNull);
      expect(await store.loadHistory(), hasLength(1));

      final weaker = await store.record(
        fingerprint: 'two',
        generatedAt: DateTime(2026, 11, 12),
        periodStart: start,
        periodEndExclusive: end,
        tagPatterns: _patterns(45),
      );
      insight = (weaker!['insights'] as List).single as Map;
      expect(insight['status'], 'weakened');
      expect((insight['lastComparable'] as Map)['difference'], 45);

      final insufficient = await store.record(
        fingerprint: 'three',
        generatedAt: DateTime(2026, 11, 13),
        periodStart: start,
        periodEndExclusive: end,
        tagPatterns: _patterns(null, sufficient: false, withSamples: 3),
      );
      insight = (insufficient!['insights'] as List).single as Map;
      expect(insight['status'], 'insufficientData');
      // Insufficient data must not overwrite the last comparable value.
      expect((insight['lastComparable'] as Map)['difference'], 45);

      final noLongerObserved = await store.record(
        fingerprint: 'four',
        generatedAt: DateTime(2026, 11, 14),
        periodStart: start,
        periodEndExclusive: end,
        tagPatterns: _patterns(0),
      );
      insight = (noLongerObserved!['insights'] as List).single as Map;
      expect(insight['status'], 'noLongerObserved');
      expect(
        (insight['statusEvents'] as List).map((event) => (event as Map)['status']),
        ['new', 'weakened', 'insufficientData', 'noLongerObserved'],
      );
      expect(await store.loadHistory(), hasLength(4));
    });
  });

  test('refreshes current calendar-month insight history after a morning report and skips unchanged data', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('tag-insight-history-');
    Database? openedDatabase;
    addTearDown(() async {
      await openedDatabase?.close();
      SleepDatabase.instance.setDatabaseForTesting(null);
      SleepDatabase.instance.setDatabasePathForTesting(null);
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    SleepDatabase.instance.setDatabasePathForTesting(
      '${directory.path}/sleep.sqlite',
    );
    final db = await SleepDatabase.instance.database;
    openedDatabase = db;

    Future<void> addNight({
      required String id,
      required DateTime start,
      required int sleepMinutes,
      bool withCaffeine = false,
    }) async {
      final actualStart = start.add(const Duration(minutes: 5));
      final actualEnd = actualStart.add(Duration(minutes: sleepMinutes));
      await db.insert('sleep_sessions', {
        'id': id,
        'started_at': start.toIso8601String(),
        'ended_at': start.add(const Duration(hours: 8)).toIso8601String(),
        'source': 'manual',
        'created_at': start.toIso8601String(),
        'updated_at': actualEnd.toIso8601String(),
        'actual_sleep_started_at': actualStart.toIso8601String(),
        'actual_sleep_ended_at': actualEnd.toIso8601String(),
        'user_edited': 1,
      });
      if (withCaffeine) {
        await db.insert('sleep_session_tags', {
          'session_id': id,
          'tag_key': 'caffeine',
          'label': 'Кофеин',
          'created_at': actualEnd.toIso8601String(),
        });
      }
    }

    for (var i = 0; i < 4; i++) {
      await addNight(
        id: 'oct-tag-$i',
        start: DateTime(2026, 10, i + 1, 22),
        sleepMinutes: 450,
        withCaffeine: true,
      );
      await addNight(
        id: 'oct-plain-$i',
        start: DateTime(2026, 10, i + 8, 22),
        sleepMinutes: 390,
      );
      await addNight(
        id: 'nov-tag-$i',
        start: DateTime(2026, 11, i + 1, 22),
        sleepMinutes: 450,
        withCaffeine: true,
      );
      await addNight(
        id: 'nov-plain-$i',
        start: DateTime(2026, 11, i + 8, 22),
        sleepMinutes: 390,
      );
    }

    final service = PeriodicReportService(SleepDatabase.instance);
    final first = await service.refreshCurrentTagInsightHistory(
      sessionId: 'nov-tag-0',
      now: DateTime(2026, 11, 20),
    );
    expect(first, isNotNull);
    expect(first!['periodStart'], DateTime(2026, 11).toIso8601String());
    var insights = first['insights'] as List;
    expect(insights, isNotEmpty);
    final firstDuration = insights.cast<Map>().singleWhere(
      (item) => item['metricKey'] == 'duration',
    );
    expect(firstDuration['status'], 'new');

    final unchanged = await service.refreshCurrentTagInsightHistory(
      sessionId: 'nov-tag-0',
      now: DateTime(2026, 11, 20),
    );
    expect(unchanged, isNull);
    expect(
      await TagInsightHistoryStore(
        SleepDatabase.instance.getAppMetadata,
        SleepDatabase.instance.setAppMetadata,
      ).loadHistory(),
      hasLength(1),
    );

    await addNight(
      id: 'nov-tag-new',
      start: DateTime(2026, 11, 18, 22),
      sleepMinutes: 420,
      withCaffeine: true,
    );
    final updated = await service.refreshCurrentTagInsightHistory(
      sessionId: 'nov-tag-0',
      now: DateTime(2026, 11, 21),
    );
    expect(updated, isNotNull);
    insights = updated!['insights'] as List;
    final updatedDuration = insights.cast<Map>().singleWhere(
      (item) => item['metricKey'] == 'duration',
    );
    expect(updatedDuration['status'], 'weakened');
    expect((updatedDuration['current'] as Map)['withTagSamples'], 5);

    await addNight(
      id: 'oct-tag-new',
      start: DateTime(2026, 10, 15, 22),
      sleepMinutes: 420,
      withCaffeine: true,
    );
    final octoberSnapshot = await service.refreshCurrentTagInsightHistory(
      sessionId: 'oct-tag-new',
      now: DateTime(2026, 11, 22),
    );
    expect(octoberSnapshot, isNotNull);
    expect(
      octoberSnapshot!['periodStart'],
      DateTime(2026, 10).toIso8601String(),
    );
    final octoberDuration = (octoberSnapshot['insights'] as List)
        .cast<Map>()
        .singleWhere((item) => item['metricKey'] == 'duration');
    expect(octoberDuration['status'], 'new');
  });
}
