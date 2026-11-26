import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/tag_insight_history_merge.dart';

Map<String, Object?> _snapshot({
  required String fingerprint,
  required String generatedAt,
  required String status,
  required String eventAt,
}) => {
  'schemaVersion': 1,
  'fingerprint': fingerprint,
  'generatedAt': generatedAt,
  'periodStart': '2026-11-01T00:00:00.000',
  'periodEndExclusive': '2026-12-01T00:00:00.000',
  'insights': [
    {
      'id': '["caffeine","duration"]',
      'tagKey': 'caffeine',
      'tagLabel': 'Кофеин',
      'metricKey': 'duration',
      'metricLabel': 'Продолжительность сна',
      'status': status,
      'createdAt': '2026-11-01T00:00:00.000',
      'updatedAt': generatedAt,
      'current': {'difference': 50},
      'lastComparable': {'difference': 50},
      'statusEvents': [
        {'status': status, 'at': eventAt},
      ],
    },
  ],
};

void main() {
  test('merges insight snapshots, deduplicates fingerprints and combines status events', () {
    final local = [
      _snapshot(
        fingerprint: 'one',
        generatedAt: '2026-11-10T08:00:00.000',
        status: 'new',
        eventAt: '2026-11-10T08:00:00.000',
      ),
    ];
    final imported = [
      _snapshot(
        fingerprint: 'one',
        generatedAt: '2026-11-11T08:00:00.000',
        status: 'weakened',
        eventAt: '2026-11-11T08:00:00.000',
      ),
      _snapshot(
        fingerprint: 'two',
        generatedAt: '2026-11-12T08:00:00.000',
        status: 'confirmed',
        eventAt: '2026-11-12T08:00:00.000',
      ),
    ];

    final merged = TagInsightHistoryMerge.merge(
      local: local,
      imported: imported,
    );

    expect(merged, hasLength(2));
    expect(merged.map((item) => item['fingerprint']), ['one', 'two']);
    final firstInsight = (merged.first['insights'] as List).single as Map;
    expect(firstInsight['status'], 'weakened');
    expect(
      (firstInsight['statusEvents'] as List)
          .map((event) => (event as Map)['status']),
      ['new', 'weakened'],
    );
  });

  test('rejects malformed backup history before restore', () {
    expect(
      () => TagInsightHistoryMerge.validateBackupMetadata({
        'app_metadata': [
          {'key': TagInsightHistoryMerge.metadataKey, 'value': 'not-json'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => TagInsightHistoryMerge.validateRaw(
        jsonEncode([{'fingerprint': 'broken'}]),
        'Тест',
      ),
      throwsFormatException,
    );
  });
}
