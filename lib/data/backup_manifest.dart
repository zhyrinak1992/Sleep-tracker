import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class BackupManifest {
  BackupManifest._();

  static Future<String> _sha256Hex(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Map<String, Object?>> create(Map<String, dynamic> data) async {
    final tableCounts = <String, int>{};
    for (final entry in data.entries) {
      if (entry.value is List) tableCounts[entry.key] = (entry.value as List).length;
    }
    final audioFiles = <Map<String, Object?>>[];
    for (final raw in (data['audio_events'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final encoded = raw['audioDataB64'];
      if (encoded is! String || encoded.isEmpty) continue;
      final bytes = base64Decode(encoded);
      audioFiles.add({
        'eventId': raw['id'],
        'sizeBytes': bytes.length,
        'sha256': await _sha256Hex(bytes),
      });
    }
    return {
      'manifestVersion': 1,
      'payloadSha256': await _sha256Hex(utf8.encode(jsonEncode(data))),
      'tableCounts': tableCounts,
      'audioFiles': audioFiles,
    };
  }

  static Future<void> validate({
    required Map<String, dynamic> document,
    required Map<String, dynamic> data,
    required int formatVersion,
  }) async {
    if (formatVersion < 5) return;
    final manifest = document['manifest'];
    if (manifest is! Map<String, dynamic> ||
        manifest['manifestVersion'] != 1 ||
        manifest['payloadSha256'] is! String ||
        manifest['tableCounts'] is! Map ||
        manifest['audioFiles'] is! List) {
      throw const FormatException('В резервной копии отсутствует корректный манифест целостности.');
    }
    final expectedPayloadHash = await _sha256Hex(utf8.encode(jsonEncode(data)));
    if (manifest['payloadSha256'] != expectedPayloadHash) {
      throw const FormatException('Контрольная сумма данных не совпадает. Архив повреждён или изменён; восстановление отменено.');
    }
    final tableCounts = Map<String, dynamic>.from(manifest['tableCounts'] as Map);
    for (final entry in data.entries) {
      if (entry.value is! List) continue;
      if (tableCounts[entry.key] != (entry.value as List).length) {
        throw FormatException('Количество записей в разделе «${entry.key}» не совпадает с манифестом.');
      }
    }
    final audioManifest = <String, Map<String, dynamic>>{};
    for (final raw in manifest['audioFiles'] as List) {
      if (raw is! Map || raw['eventId'] is! String ||
          raw['sizeBytes'] is! int || raw['sha256'] is! String) {
        throw const FormatException('Список контрольных сумм аудиофайлов повреждён.');
      }
      final id = raw['eventId'] as String;
      if (audioManifest.containsKey(id)) {
        throw const FormatException('В манифесте повторяется ID аудиофайла.');
      }
      audioManifest[id] = Map<String, dynamic>.from(raw);
    }
    var embeddedAudioCount = 0;
    for (final raw in (data['audio_events'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final encoded = raw['audioDataB64'];
      if (encoded == null) continue;
      if (encoded is! String || raw['id'] is! String) {
        throw const FormatException('Вложение аудиособытия имеет неверный формат.');
      }
      final bytes = base64Decode(encoded);
      final entry = audioManifest[raw['id'] as String];
      if (entry == null ||
          entry['sizeBytes'] != bytes.length ||
          entry['sha256'] != await _sha256Hex(bytes)) {
        throw const FormatException('Контрольная сумма аудиофайла не совпадает. Восстановление отменено.');
      }
      embeddedAudioCount++;
    }
    if (audioManifest.length != embeddedAudioCount) {
      throw const FormatException('Количество вложенных аудиофайлов не совпадает с манифестом.');
    }
  }
}
