import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_service.dart';

void main() {
  group('BackupService.audioExtensionForRestore', () {
    test('preserves supported original audio extensions', () {
      expect(BackupService.audioExtensionForRestore('/audio/night.m4a'), '.m4a');
      expect(BackupService.audioExtensionForRestore('/audio/night.wav'), '.wav');
    });

    test('uses a safe fallback when the original extension is missing or invalid', () {
      expect(BackupService.audioExtensionForRestore('/audio/night'), '.audio');
      expect(BackupService.audioExtensionForRestore('/audio/night.bad-extension'), '.audio');
      expect(BackupService.audioExtensionForRestore(null), '.audio');
    });
  });
}
