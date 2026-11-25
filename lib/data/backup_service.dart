import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:disk_usage/disk_usage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'sleep_database.dart';
import 'backup_crypto.dart';
import 'backup_manifest.dart';
import 'backup_restore_planner.dart';

/// Ручной перенос локальной базы Sleep Tracker в переносимый JSON-файл.
/// Восстановление полностью заменяет текущие данные и выполняется транзакционно.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static String audioExtensionForRestore(String? originalPath) {
    final extension = originalPath == null ? '' : p.extension(originalPath);
    if (extension.length < 2 || extension.length > 9) return '.audio';
    final valid = extension.substring(1).codeUnits.every((unit) =>
        (unit >= 48 && unit <= 57) ||
        (unit >= 65 && unit <= 90) ||
        (unit >= 97 && unit <= 122));
    return valid ? extension : '.audio';
  }

  static Future<File> writeAudioBytesForRestore({
    required String destinationPath,
    required List<int> bytes,
  }) async {
    final file = File(destinationPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static const format = 'sleep_tracker_backup';
  static const formatVersion = 5;

  static List<int> encodeExportDocument(Map<String, Object?> document) =>
      utf8.encode(const JsonEncoder.withIndent('  ').convert(document));

  Future<void> exportToFiles() async {
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
    final manifest = await BackupManifest.create(snapshot);
    final document = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'app': 'Sleep Tracker',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'summary': <String, Object?>{'sleepSessions': (snapshot['sleep_sessions'] as List).length, 'notes': (snapshot['sleep_notes'] as List).length, 'audioEvents': audioRows.length, 'audioBytes': audioBytesTotal, 'climateSamples': (snapshot['climate_samples'] as List).length},
      'manifest': manifest,
      'data': snapshot,
    };
    // ТЗ v191: отдельный пароль архива не используется.
    // Целостность проверяется манифестом и SHA-256 каждого вложения.
    final outputBytes = encodeExportDocument(document);
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    const extension = 'stbackup';
    final file = File(p.join(temp.path, 'SleepTracker-backup-$stamp.$extension'));
    await file.writeAsBytes(outputBytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream', name: p.basename(file.path))],
      subject: 'Резервная копия Sleep Tracker',
      text: 'Переносимая резервная копия Sleep Tracker. Отдельный пароль не требуется.',
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
    await BackupManifest.validate(document: decoded, data: data, formatVersion: decoded['formatVersion'] as int);
    _validateAudioArchive(data, decoded['formatVersion'] as int);
    _validateSleepChangeHistory(data);
    _validateComparisonSuggestionHistory(data);
    final availableBytes = await _availableStorageBytes();
    final impact = await SleepDatabase.instance.previewRestoreImpact(
      data,
      availableBytes: availableBytes,
    );
    return BackupImportDraft._(
      document: Map<String, dynamic>.from(decoded),
      data: data,
      preview: BackupImportPreview.fromDocument(decoded, data),
      impact: impact,
    );
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
  Future<int?> _availableStorageBytes() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return await DiskUsage.freeSpace(docs.path);
    } catch (_) {
      return null;
    }
  }

  Future<BackupImportResult> restorePreparedBackup({required BackupImportDraft draft, required bool merge, Directory? documentsDirectoryForTesting}) async {
    final data = jsonDecode(jsonEncode(draft.data)) as Map<String, dynamic>;
    final freshImpact = await SleepDatabase.instance.previewRestoreImpact(
      data,
      availableBytes: await _availableStorageBytes(),
    );
    final selectedPlan = merge ? freshImpact.merge : freshImpact.replace;
    final previewPlan = merge ? draft.impact.merge : draft.impact.replace;
    if (selectedPlan.stateFingerprint != previewPlan.stateFingerprint) {
      throw StateError('Данные приложения изменились после предпросмотра. Выберите резервную копию ещё раз, чтобы пересчитать последствия восстановления.');
    }
    if (selectedPlan.blockedReason != null) {
      throw StateError(selectedPlan.blockedReason!);
    }
    if (!selectedPlan.hasEnoughSpace) {
      throw StateError('Недостаточно свободного места для безопасного восстановления. Освободите место и повторите предпросмотр.');
    }
    final previousAudio = await SleepDatabase.instance.getAudioEvents();
    final existingAudioIds = previousAudio.map((row) => row['id'] as String).toSet();
    final audioRows = ((data['audio_events'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map)).toList();

    final docs = documentsDirectoryForTesting ?? await getApplicationDocumentsDirectory();
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
        final safeExtension = audioExtensionForRestore(
          originalPath is String ? originalPath : null,
        );
        final id = row['id'] as String;
        final restored = File(p.join(audioDir.path,
          'restored_${DateTime.now().microsecondsSinceEpoch}_${i}_${id.hashCode.abs()}$safeExtension'));
        // Track the destination before writing so a partial write is also cleaned up.
        createdFiles.add(restored);
        await writeAudioBytesForRestore(
          destinationPath: restored.path,
          bytes: audioBytes,
        );
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
      return BackupImportResult.completed(merge: merge, plan: selectedPlan);
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
  BackupImportDraft._({required this.document, required this.data, required this.preview, required this.impact});

  factory BackupImportDraft.forTesting({
    required Map<String, dynamic> document,
    required Map<String, dynamic> data,
    required BackupImportPreview preview,
    required BackupRestoreImpact impact,
  }) => BackupImportDraft._(
    document: document,
    data: data,
    preview: preview,
    impact: impact,
  );
  final Map<String, dynamic> document;
  final Map<String, dynamic> data;
  final BackupImportPreview preview;
  final BackupRestoreImpact impact;
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

class BackupImportResult {
  const BackupImportResult._({required this.isCancelled, this.merge, this.plan});

  static const cancelled = BackupImportResult._(isCancelled: true);

  factory BackupImportResult.completed({required bool merge, required BackupRestorePlan plan}) =>
      BackupImportResult._(isCancelled: false, merge: merge, plan: plan);

  final bool isCancelled;
  final bool? merge;
  final BackupRestorePlan? plan;
}
