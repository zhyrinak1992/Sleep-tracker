import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'sleep_database.dart';

/// Ручной перенос локальной базы Sleep Tracker в переносимый JSON-файл.
/// Восстановление полностью заменяет текущие данные и выполняется транзакционно.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const format = 'sleep_tracker_backup';
  static const formatVersion = 4;

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
    final document = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'app': 'Sleep Tracker',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'summary': <String, Object?>{'sleepSessions': (snapshot['sleep_sessions'] as List).length, 'notes': (snapshot['sleep_notes'] as List).length, 'audioEvents': audioRows.length, 'audioBytes': audioBytesTotal, 'climateSamples': (snapshot['climate_samples'] as List).length},
      'data': snapshot,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(document);
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File(p.join(temp.path, 'SleepTracker-backup-$stamp.json'));
    await file.writeAsString(encoded, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json', name: p.basename(file.path))],
      subject: 'Резервная копия Sleep Tracker',
      text: 'Резервная копия истории сна. Сохраните файл в приложении «Файлы».',
    );
  }

  Future<BackupImportResult> importFromFiles({required bool merge}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return BackupImportResult.cancelled;
    final selected = picked.files.single;
    final bytes = selected.bytes ??
        (selected.path == null ? null : await File(selected.path!).readAsBytes());
    if (bytes == null) throw const FormatException('Не удалось прочитать выбранный файл.');

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        (decoded['formatVersion'] != 1 && decoded['formatVersion'] != 2 && decoded['formatVersion'] != 3 && decoded['formatVersion'] != formatVersion) ||
        decoded['data'] is! Map<String, dynamic>) {
      throw const FormatException('Файл не является поддерживаемой резервной копией Sleep Tracker.');
    }

    final data = Map<String, dynamic>.from(decoded['data'] as Map<String, dynamic>);
    final previousAudio = await SleepDatabase.instance.getAudioEvents();
    final existingAudioIds = previousAudio.map((row) => row['id'] as String).toSet();
    final rawAudioRows = data['audio_events'];
    if (rawAudioRows != null && rawAudioRows is! List) {
      throw const FormatException('Раздел аудиозаписей в резервной копии повреждён.');
    }
    final audioRows = (rawAudioRows as List?)
            ?.map((row) {
              if (row is! Map) throw const FormatException('Некорректная запись аудио в резервной копии.');
              return Map<String, dynamic>.from(row);
            }).toList() ??
        <Map<String, dynamic>>[];

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
        // Format v3 promises a complete audio archive; reject damaged archives.
        if (encoded == null) {
          if (decoded['formatVersion'] == 3 && row['file_path'] != null) throw const FormatException('В резервной копии отсутствует аудиофайл, который должен быть в архиве. Импорт отменён без изменения текущих данных.');
          // Legacy archives may contain metadata without original audio bytes.
          continue;
        }
        if (encoded is! String) {
          throw const FormatException('Повреждён аудиофайл в резервной копии.');
        }
        late final List<int> audioBytes;
        try {
          audioBytes = base64Decode(encoded);
        } on FormatException {
          throw const FormatException('Не удалось декодировать аудиофайл из резервной копии.');
        }
        final originalPath = row['file_path'];
        final extension = originalPath is String ? p.extension(originalPath) : '';
        final safeExtension = RegExp(r'^\\.[a-zA-Z0-9]{1,8}$').hasMatch(extension)
            ? extension
            : '.audio';
        final id = row['id'];
        if (id is! String || id.isEmpty) {
          throw const FormatException('У аудиозаписи в резервной копии отсутствует ID.');
        }
        final restored = File(p.join(
          audioDir.path,
          'restored_${DateTime.now().microsecondsSinceEpoch}_${i}_${id.hashCode.abs()}$safeExtension',
        ));
        await restored.writeAsBytes(audioBytes, flush: true);
        createdFiles.add(restored);
        row['file_path'] = restored.path;
        restoredRows.add(row);
      }

      data['audio_events'] = restoredRows;
      // Database replacement is atomic. If validation or SQLite fails, newly
      // written audio files are removed and the current installation is untouched.
      await SleepDatabase.instance.restoreSnapshot(data, merge: merge);

      if (!merge) {
        for (final row in previousAudio) {
          final oldPath = row['file_path'];
          if (oldPath is String) {
            try {
              final oldFile = File(oldPath);
              if (!createdFiles.any((file) => file.path == oldFile.path)) {
                await oldFile.delete();
              }
            } catch (_) {}
          }
        }
      }
      return BackupImportResult.imported;
    } catch (_) {
      for (final file in createdFiles) {
        try { await file.delete(); } catch (_) {}
      }
      rethrow;
    }
  }
}

enum BackupImportResult { cancelled, imported }
