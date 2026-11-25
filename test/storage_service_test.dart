import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/storage_service.dart';

void main() {
  group('StorageService backup file accounting', () {
    test('recognizes current and legacy backup extensions case-insensitively', () {
      expect(StorageService.isBackupFile('/tmp/night.sleepbackup'), isTrue);
      expect(StorageService.isBackupFile('/tmp/night.STBACKUP'), isTrue);
    });

    test('does not classify unrelated files as backups', () {
      expect(StorageService.isBackupFile('/tmp/report.pdf'), isFalse);
      expect(StorageService.isBackupFile('/tmp/database.sqlite'), isFalse);
      expect(StorageService.isBackupFile('/tmp/archive.json'), isFalse);
    });
  });
}
