import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_crypto.dart';
import 'package:sleep_tracker/data/backup_manifest.dart';
import 'package:sleep_tracker/data/backup_service.dart';

void main() {
  group('Portable backup export format', () {
    test('creates a plain transferable JSON archive with integrity manifest and no password envelope', () async {
      final data = <String, dynamic>{
        'schemaVersion': 8,
        'sleep_sessions': <Map<String, Object?>>[],
        'sleep_session_tags': <Map<String, Object?>>[],
        'sleep_notes': <Map<String, Object?>>[],
        'app_metadata': <Map<String, Object?>>[],
        'sleep_stages': <Map<String, Object?>>[],
        'sleep_metrics': <Map<String, Object?>>[],
        'audio_events': <Map<String, Object?>>[],
        'morning_reports': <Map<String, Object?>>[],
        'climate_samples': <Map<String, Object?>>[],
      };
      final document = <String, Object?>{
        'format': BackupService.format,
        'formatVersion': BackupService.formatVersion,
        'app': 'Sleep Tracker',
        'createdAt': '2026-11-25T00:00:00.000Z',
        'summary': <String, Object?>{'sleepSessions': 0, 'notes': 0, 'audioEvents': 0, 'audioBytes': 0, 'climateSamples': 0},
        'manifest': await BackupManifest.create(data),
        'data': data,
      };

      final bytes = BackupService.encodeExportDocument(document);
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      expect(decoded['format'], BackupService.format);
      expect(decoded['formatVersion'], BackupService.formatVersion);
      expect(BackupCrypto.isEncryptedEnvelope(decoded), isFalse);
      await BackupManifest.validate(
        document: decoded,
        data: Map<String, dynamic>.from(decoded['data'] as Map),
        formatVersion: decoded['formatVersion'] as int,
      );
    });
  });
}
