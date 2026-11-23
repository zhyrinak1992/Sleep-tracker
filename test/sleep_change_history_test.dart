import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/sleep_change_history.dart';

void main() {
  group('SleepChangeHistoryRecords', () {
    test('does not duplicate an identical monthly source fingerprint', () {
      final snapshot = <String, Object?>{
        'periodKey': '2026-11',
        'fingerprint': 'same-data',
        'mainChangeStatus': 'no_clear_change',
      };
      final first = SleepChangeHistoryRecords.append([], snapshot);
      expect(first.changed, isTrue);
      expect(first.records.single['version'], 1);

      final duplicate = SleepChangeHistoryRecords.append(
        first.records, Map<String, Object?>.from(snapshot),
      );
      expect(duplicate.changed, isFalse);
      expect(duplicate.records, hasLength(1));
    });

    test('preserves previous monthly snapshots when source data changes', () {
      final first = SleepChangeHistoryRecords.append([], {
        'periodKey': '2026-11',
        'fingerprint': 'v1',
        'mainChangeStatus': 'selected',
      });
      final second = SleepChangeHistoryRecords.append(first.records, {
        'periodKey': '2026-11',
        'fingerprint': 'v2',
        'mainChangeStatus': 'no_clear_change',
      });

      expect(second.changed, isTrue);
      expect(second.records, hasLength(2));
      expect(second.records[0]['version'], 1);
      expect(second.records[1]['version'], 2);
      expect(second.records[1]['supersedesVersion'], 1);
      expect(second.records[0]['fingerprint'], 'v1');
      expect(second.records[1]['fingerprint'], 'v2');
      expect(second.records[1]['revisionReason'], contains('Изменились'));
    });

    test('returns only the latest revision per month in chronological order', () {
      final history = <Map<String, Object?>>[
        {'periodKey': '2026-11', 'version': 1, 'fingerprint': 'a'},
        {'periodKey': '2026-10', 'version': 1, 'fingerprint': 'b'},
        {'periodKey': '2026-11', 'version': 2, 'fingerprint': 'c'},
        {'periodKey': '2026-09', 'version': 1, 'fingerprint': 'd'},
      ];
      final latest = SleepChangeHistoryRecords.latestPerMonth(history);

      expect(latest.map((row) => row['periodKey']).toList(),
        ['2026-09', '2026-10', '2026-11']);
      expect(latest.last['version'], 2);
      expect(latest.last['fingerprint'], 'c');
    });

    test('rejects malformed snapshots without altering history', () {
      expect(
        () => SleepChangeHistoryRecords.append([], {'periodKey': '2026-11'}),
        throwsArgumentError,
      );
    });
  });
}
