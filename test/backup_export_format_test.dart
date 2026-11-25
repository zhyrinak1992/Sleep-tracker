import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_crypto.dart';
import 'package:sleep_tracker/data/backup_manifest.dart';
import 'package:sleep_tracker/data/backup_service.dart';

void main() {
  group('Portable backup export format', () {
    test('creates an encrypted transferable archive with integrity manifest', () async {
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

      const password = 'sleep-tracker-archive-password';
      final plaintext = const JsonEncoder.withIndent('  ').convert(document);
      final encrypted = await BackupCrypto.encryptDocument(
        plaintext: plaintext,
        password: password,
      );
      final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;

      expect(BackupCrypto.isEncryptedEnvelope(envelope), isTrue);
      expect(envelope['algorithm'], 'AES-256-GCM');
      expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');

      final restoredText = await BackupCrypto.decryptDocument(
        bytes: encrypted,
        password: password,
      );
      final decoded = jsonDecode(restoredText) as Map<String, dynamic>;
      expect(decoded['format'], BackupService.format);
      expect(decoded['formatVersion'], BackupService.formatVersion);
      await BackupManifest.validate(
        document: decoded,
        data: Map<String, dynamic>.from(decoded['data'] as Map),
        formatVersion: decoded['formatVersion'] as int,
      );
    });
  });
}
