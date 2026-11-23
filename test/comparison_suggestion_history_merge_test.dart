import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/comparison_suggestion_history_merge.dart';

void main() {
  group('ComparisonSuggestionHistoryMerge', () {
    test('merges new records and combines status events for the same suggestion ID', () {
      final local = <Map<String, Object?>>[
        {
          'id': 'same',
          'createdAt': '2026-11-01T10:00:00',
          'status': 'pending',
          'candidate': {'signature': 'local'},
          'statusEvents': [
            {'status': 'pending', 'at': '2026-11-01T10:00:00'},
          ],
        },
      ];
      final imported = <Map<String, Object?>>[
        {
          'id': 'same',
          'createdAt': '2026-11-01T10:00:00',
          'status': 'opened',
          'candidate': {'signature': 'remote'},
          'statusEvents': [
            {'status': 'pending', 'at': '2026-11-01T10:00:00'},
            {'status': 'opened', 'at': '2026-11-01T11:00:00'},
          ],
        },
        {
          'id': 'new',
          'createdAt': '2026-11-02T10:00:00',
          'status': 'notViewed',
          'statusEvents': [],
        },
      ];

      final merged = ComparisonSuggestionHistoryMerge.merge(
        local: local,
        imported: imported,
      );

      expect(merged, hasLength(2));
      expect(merged.first['id'], 'same');
      expect(merged.first['candidate'], {'signature': 'local'});
      expect(merged.first['status'], 'opened');
      expect(merged.first['statusEvents'], hasLength(2));
      expect(merged.last['id'], 'new');
    });

    test('deduplicates identical status events and rejects missing IDs', () {
      final record = <String, Object?>{
        'id': 'same',
        'createdAt': '2026-11-01T10:00:00',
        'status': 'pending',
        'statusEvents': [
          {'status': 'pending', 'at': '2026-11-01T10:00:00'},
        ],
      };
      final merged = ComparisonSuggestionHistoryMerge.merge(
        local: [record],
        imported: [record],
      );
      expect(merged, hasLength(1));
      expect(merged.single['statusEvents'], hasLength(1));
      expect(
        () => ComparisonSuggestionHistoryMerge.merge(
          local: [{'createdAt': '2026-11-01'}],
          imported: [],
        ),
        throwsFormatException,
      );
    });
  });
}
