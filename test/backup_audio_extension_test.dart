import 'dart:io';

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

  test('writes restored audio bytes unchanged to the destination file', () async {
    final directory = await Directory.systemTemp.createTemp('sleep-backup-audio-');
    try {
      final expected = <int>[0, 1, 2, 127, 128, 254, 255];
      final destination = '${directory.path}/restored_clip.m4a';

      final restored = await BackupService.writeAudioBytesForRestore(
        destinationPath: destination,
        bytes: expected,
      );

      expect(await restored.exists(), isTrue);
      expect(await restored.readAsBytes(), expected);
      expect(restored.path, destination);
    } finally {
      await directory.delete(recursive: true);
    }
  });
  });
}
