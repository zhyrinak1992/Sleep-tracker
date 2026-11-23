import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'sleep_database.dart';
import 'backup_crypto.dart';

/// Ручной перенос локальной базы Sleep Tracker в переносимый JSON-файл.
/// Восстановление полностью заменяет текущие данные и выполняется транзакционно.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const format = 'sleep_tracker_backup';
  static const formatVersion = 5;

  Future<void> exportToFiles({String? password}) async {
    final snapshot = await SleepDatabase.instance.exportSnapshot();
    final audioRows = (snapshot['audio_events'] as List).cast<Map<String, Object?>>();
    var audioBytesTotal = 0;
    for (final row in audioRows) {
      final path = row['file_path'];
      // Исторические события старше 7 дней сохраняются без аудиовложения.
      if (path == null || path == '') continue;
      if (path is! String) throw StateError('Некорректный путь к аудиофайлу. Резервная копия не создана.');
      final source = File(path);
      if (!await source.exists()) throw StateError('Не найден аудиофайл события, срок хранения которого ещё не истёк. Резервная копия не создана.');
      final bytes = await source.readAsBytes();
      if (bytes.isEmpty) throw StateError('Обнаружен пустой аудиофайл. Резервная копия не создана.');
      audioBytesTotal += bytes.length;
      row['audioDataB64'] = base64Encode(bytes);
    }
    final manifest = await _buildManifest(snapshot);
    final document = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'app': 'Sleep Tracker',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'summary': <String, Object?>{'sleepSessions': (snapshot['sleep_sessions'] as List).length, 'notes': (snapshot['sleep_notes'] as List).length, 'audioEvents': audioRows.length, 'audioBytes': audioBytesTotal, 'climateSamples': (snapshot['climate_samples'] as List).length},
      'manifest': manifest,
      'data': snapshot,
    };
    final plaintext = const JsonEncoder.withIndent('  ').convert(document);
    final encrypted = password != null && password.isNotEmpty;
    final outputBytes = encrypted
        ? await BackupCrypto.encryptDocument(plaintext: plaintext, password: password)
        : utf8.encode(plaintext);
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final extension = encrypted ? 'stbackup' : 'sleepbackup';
    final file = File(p.join(temp.path, 'SleepTracker-backup-$stamp.$extension'));
    await file.writeAsBytes(outputBytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream', name: p.basename(file.path))],
      subject: 'Резервная копия Sleep Tracker',
      text: encrypted
          ? 'Зашифрованная резервная копия. Для восстановления потребуется заданный пароль.'
          : 'Резервная копия Sleep Tracker. Дополнительный пароль не требуется.',
    );
  }

  /// Выбирает архив, расшифровывает и проверяет его без изменения текущих данных.
  Future<BackupImportDraft?> prepareImportFromFiles({required Future<String?> Function() requestPassword}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'stbackup', 'sleepbackup'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final selected = picked.files.single;
    final bytes = selected.bytes ?? (selected.path == null ? null : await File(selected.path!).readAsBytes());
    if (bytes == null) throw const FormatException('Не удалось прочитать выбранный файл.');

    final initial = jsonDecode(utf8.decode(bytes));
    final String jsonText;
    if (BackupCrypto.isEncryptedEnvelope(initial)) {
      final password = await requestPassword();
      if (password == null) return null;
      jsonText = await BackupCrypto.decryptDocument(bytes: bytes, password: password);
    } else {
      // Legacy plaintext JSON archives remain importable for backward compatibility.
      jsonText = utf8.decode(bytes);
    }

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        ![1, 2, 3, 4, formatVersion].contains(decoded['formatVersion']) ||
        decoded['data'] is! Map<String, dynamic>) {
      throw const FormatException('Файл не является поддерживаемой резервной копией Sleep Tracker.');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map<String, dynamic>);
    // This validation is deliberately read-only and runs before the user sees restore choices.
    SleepDatabase.instance.validateSnapshot(data);
    await _validateManifest(decoded, data, decoded['formatVersion'] as int);
    _validateAudioArchive(data, decoded['formatVersion'] as int);
    _validateSleepChangeHistory(data);
    _validateComparisonSuggestionHistory(data);
    return BackupImportDraft._(
      document: Map<String, dynamic>.from(decoded),
      data: data,
      preview: BackupImportPreview.fromDocument(decoded, data),
    );
  }

  Future<String> _sha256Hex(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, Object?>> _buildManifest(Map<String, dynamic> data) async {
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

  Future<void> _validateManifest(
    Map<String, dynamic> document,
    Map<String, dynamic> data,
    int version,
  ) async {
    if (version < 5) return;
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

  void _validateAudioArchive(Map<String, dynamic> data, int version) {
    final rawRows = data['audio_events'];
    if (rawRows != null && rawRows is! List) {
      throw const FormatException('Раздел аудиозаписей в резервной копии повреждён.');
    }
    for (final raw in (rawRows as List?) ?? const []) {
      if (raw is! Map) throw const FormatException('Некорректная запись аудио в резервной копии.');
      final row = Map<String, dynamic>.from(raw);
      final encoded = row['audioDataB64'];
      if (encoded == null) {
        if (version >= 3 && row['file_path'] != null) {
          throw const FormatException('В резервной копии отсутствует аудиофайл, который должен быть в архиве. Импорт отменён без изменения текущих данных.');
        }
        continue;
      }
      if (encoded is! String) throw const FormatException('Повреждён аудиофайл в резервной копии.');
      late final List<int> audioBytes;
      try { audioBytes = base64Decode(encoded); }
      on FormatException { throw const FormatException('Не удалось декодировать аудиофайл из резервной копии.'); }
      if (audioBytes.isEmpty) throw const FormatException('В резервной копии обнаружен пустой аудиофайл. Импорт отменён.');
      if (row['id'] is! String || (row['id'] as String).isEmpty) {
        throw const FormatException('У аудиозаписи в резервной копии отсутствует ID.');
      }
    }
  }

  void _validateSleepChangeHistory(Map<String, dynamic> data) {
    final metadata = data['app_metadata'];
    if (metadata is! List) return;
    for (final raw in metadata) {
      if (raw is! Map || raw['key'] != 'sleep_change_history_v1') continue;
      final value = raw['value'];
      if (value is! String) {
        throw const FormatException('История главных изменений в резервной копии повреждена.');
      }
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        throw const FormatException('История главных изменений в резервной копии имеет неверный формат.');
      }
      for (final item in decoded) {
        if (item is! Map || item['periodKey'] is! String ||
            item['fingerprint'] is! String || item['version'] is! int) {
          throw const FormatException('В резервной копии обнаружена некорректная запись истории главных изменений.');
        }
      }
    }
  }

  void _validateComparisonSuggestionHistory(Map<String, dynamic> data) {
    final metadata = data['app_metadata'];
    if (metadata is! List) return;
    for (final raw in metadata) {
      if (raw is! Map || raw['key'] != 'comparison_suggestion_history_v1') continue;
      final value = raw['value'];
      if (value is! String) {
        throw const FormatException('История предложений сравнений в резервной копии повреждена.');
      }
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        throw const FormatException('История предложений сравнений имеет неверный формат.');
      }
      for (final item in decoded) {
        if (item is! Map || item['id'] is! String ||
            item['candidate'] is! Map || item['status'] is! String ||
            item['createdAt'] is! String || item['expiresAt'] is! String ||
            item['statusEvents'] is! List) {
          throw const FormatException('В резервной копии обнаружена некорректная запись предложения сравнения.');
        }
      }
    }
  }

  /// Применяет уже проверенный архив. До этого вызова база и аудиофайлы не меняются.
  Future<BackupImportResult> restorePreparedBackup({required BackupImportDraft draft, required bool merge}) async {
    final data = jsonDecode(jsonEncode(draft.data)) as Map<String, dynamic>;
    final previousAudio = await SleepDatabase.instance.getAudioEvents();
    final existingAudioIds = previousAudio.map((row) => row['id'] as String).toSet();
    final audioRows = ((data['audio_events'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map)).toList();

    final docs = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(docs.path, 'audio_events'));
    await audioDir.create(recursive: true);
    final createdFiles = <File>[];
    final restoredRows = <Map<String, dynamic>>[];
    try {
      for (var i = 0; i < audioRows.length; i++) {
        final row = audioRows[i];
        if (merge && existingAudioIds.contains(row['id'])) continue;
        final encoded = row.remove('audioDataB64');
        if (encoded == null) {
          row['file_path'] = null;
          restoredRows.add(row);
          continue;
        }
        final audioBytes = base64Decode(encoded as String);
        final originalPath = row['file_path'];
        final extension = originalPath is String ? p.extension(originalPath) : '';
        final safeExtension = RegExp(r'^\\.[a-zA-Z0-9]{1,8}$').hasMatch(extension) ? extension : '.audio';
        final id = row['id'] as String;
        final restored = File(p.join(audioDir.path,
          'restored_${DateTime.now().microsecondsSinceEpoch}_${i}_${id.hashCode.abs()}$safeExtension'));
        await restored.writeAsBytes(audioBytes, flush: true);
        createdFiles.add(restored);
        row['file_path'] = restored.path;
        restoredRows.add(row);
      }
      data['audio_events'] = restoredRows;
      await SleepDatabase.instance.restoreSnapshot(data, merge: merge);
      if (!merge) {
        for (final row in previousAudio) {
          final oldPath = row['file_path'];
          if (oldPath is String) {
            try {
              final oldFile = File(oldPath);
              if (!createdFiles.any((file) => file.path == oldFile.path)) await oldFile.delete();
            } catch (_) {}
          }
        }
      }
      return BackupImportResult.imported;
    } catch (_) {
      for (final file in createdFiles) { try { await file.delete(); } catch (_) {} }
      rethrow;
    }
  }

  /// Совместимый фасад для старых вызывающих участков.
  Future<BackupImportResult> importFromFiles({required bool merge, required Future<String?> Function() requestPassword}) async {
    final draft = await prepareImportFromFiles(requestPassword: requestPassword);
    if (draft == null) return BackupImportResult.cancelled;
    return restorePreparedBackup(draft: draft, merge: merge);
  }
}

class BackupImportDraft {
  BackupImportDraft._({required this.document, required this.data, required this.preview});
  final Map<String, dynamic> document;
  final Map<String, dynamic> data;
  final BackupImportPreview preview;
}

class BackupImportPreview {
  const BackupImportPreview({
    required this.formatVersion, required this.createdAt, required this.sessions,
    required this.reports, required this.notes, required this.audioEvents,
    required this.audioFiles, required this.climateSamples, required this.stages,
    required this.metrics, required this.tags, required this.changeHistorySnapshots, required this.suggestionHistoryEntries, required this.integrityVerified,
  });
  final int formatVersion;
  final DateTime? createdAt;
  final int sessions, reports, notes, audioEvents, audioFiles, climateSamples, stages, metrics, tags, changeHistorySnapshots, suggestionHistoryEntries;
  final bool integrityVerified;

  static int _count(Map<String, dynamic> data, String key) => data[key] is List ? (data[key] as List).length : 0;
  factory BackupImportPreview.fromDocument(Map<String, dynamic> document, Map<String, dynamic> data) {
    final audio = (data['audio_events'] as List?) ?? const [];
    final files = audio.where((row) => row is Map && row['audioDataB64'] is String && (row['audioDataB64'] as String).isNotEmpty).length;
    var changeHistorySnapshots = 0;
    var suggestionHistoryEntries = 0;
    final metadata = (data['app_metadata'] as List?) ?? const [];
    for (final row in metadata) {
      if (row is! Map || row['value'] is! String) continue;
      if (row['key'] == 'sleep_change_history_v1' ||
          row['key'] == 'comparison_suggestion_history_v1') {
        try {
          final decoded = jsonDecode(row['value'] as String);
          if (decoded is List) {
            if (row['key'] == 'sleep_change_history_v1') changeHistorySnapshots = decoded.length;
            if (row['key'] == 'comparison_suggestion_history_v1') suggestionHistoryEntries = decoded.length;
          }
        } catch (_) {
          // Structural validation reports malformed history before the preview is shown.
        }
      }
    }
    return BackupImportPreview(
      formatVersion: document['formatVersion'] as int,
      createdAt: DateTime.tryParse(document['createdAt'] is String ? document['createdAt'] as String : ''),
      sessions: _count(data, 'sleep_sessions'), reports: _count(data, 'morning_reports'),
      notes: _count(data, 'sleep_notes'), audioEvents: audio.length, audioFiles: files,
      climateSamples: _count(data, 'climate_samples'), stages: _count(data, 'sleep_stages'),
      metrics: _count(data, 'sleep_metrics'), tags: _count(data, 'sleep_session_tags'),
      changeHistorySnapshots: changeHistorySnapshots,
      suggestionHistoryEntries: suggestionHistoryEntries,
      integrityVerified: document['formatVersion'] == 5 && document['manifest'] is Map,
    );
  }
}

enum BackupImportResult { cancelled, imported }
