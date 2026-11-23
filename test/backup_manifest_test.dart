import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_manifest.dart';

void main() {
  group('BackupManifest', () {
    Map<String, dynamic> sampleData() => {
      'schemaVersion': 8,
      'sleep_sessions': [
        {'id': 'night-1', 'started_at': '2026-11-20T22:00:00'},
      ],
      'audio_events': [
        {'id': 'audio-1', 'file_path': 'sleep_audio/a1.m4a', 'audioDataB64': base64Encode([1, 2, 3, 4])},
        {'id': 'audio-2', 'file_path': null},
      ],
      'app_metadata': [],
      'sleep_notes': [],
    };

    test('creates a manifest with table counts and audio checksums', () async {
      final data = sampleData();
      final manifest = await BackupManifest.create(data);

      expect(manifest['manifestVersion'], 1);
      expect((manifest['tableCounts'] as Map)['sleep_sessions'], 1);
      expect((manifest['tableCounts'] as Map)['audio_events'], 2);
      final audio = manifest['audioFiles'] as List;
      expect(audio, hasLength(1));
      expect(audio.single['eventId'], 'audio-1');
      expect(audio.single['sizeBytes'], 4);
      expect((audio.single['sha256'] as String).length, 64);
    });

    test('accepts an intact v5 payload and its audio attachments', () async {
      final data = sampleData();
      final manifest = await BackupManifest.create(data);
      await expectLater(
        BackupManifest.validate(
          document: {'formatVersion': 5, 'manifest': manifest},
          data: data,
          formatVersion: 5,
        ),
        completes,
      );
    });

    test('rejects payload changes after manifest creation', () async {
      final data = sampleData();
      final manifest = await BackupManifest.create(data);
      data['sleep_sessions'] = [
        ...data['sleep_sessions'] as List,
        {'id': 'night-2'},
      ];
      await expectLater(
        BackupManifest.validate(
          document: {'formatVersion': 5, 'manifest': manifest},
          data: data,
          formatVersion: 5,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing or altered audio checksum entries', () async {
      final data = sampleData();
      final manifest = await BackupManifest.create(data);
      manifest['audioFiles'] = [];
      await expectLater(
        BackupManifest.validate(
          document: {'formatVersion': 5, 'manifest': manifest},
          data: data,
          formatVersion: 5,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('keeps legacy v4 archives readable without a manifest', () async {
      await expectLater(
        BackupManifest.validate(
          document: {'formatVersion': 4},
          data: sampleData(),
          formatVersion: 4,
        ),
        completes,
      );
    });
  });
}
