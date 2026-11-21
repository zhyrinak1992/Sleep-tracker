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
  static const formatVersion = 2;

  Future<void> exportToFiles() async {
    final snapshot = await SleepDatabase.instance.exportSnapshot();
    final audioRows = (snapshot['audio_events'] as List).cast<Map<String, Object?>>();
    for (final row in audioRows) {
      final source = File(row['file_path']! as String);
      if (await source.exists()) row['audioDataB64'] = base64Encode(await source.readAsBytes());
    }
    final document = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'app': 'Sleep Tracker',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
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
        (decoded['formatVersion'] != 1 && decoded['formatVersion'] != formatVersion) ||
        decoded['data'] is! Map<String, dynamic>) {
      throw const FormatException('Файл не является поддерживаемой резервной копией Sleep Tracker.');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map<String, dynamic>);
    final previousAudio = await SleepDatabase.instance.getAudioEvents();
    final existingAudioIds = previousAudio.map((row) => row['id'] as String).toSet();
    final audioRows = (data['audio_events'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
    if (audioRows.isNotEmpty) {
      final docs = await getApplicationDocumentsDirectory();
      final audioDir = Directory(p.join(docs.path, 'audio_events'));
      await audioDir.create(recursive: true);
      final restoredRows = <Map<String, dynamic>>[];
      for (var i = 0; i < audioRows.length; i++) {
        final row = audioRows[i];
        if (merge && existingAudioIds.contains(row['id'])) continue;
        final encoded = row.remove('audioDataB64');
        if (encoded is! String) continue; // Never restore a broken path from another iPhone.
        final bytes = base64Decode(encoded);
        final extension = p.extension(row['file_path'] as String? ?? '.wav');
        final restored = File(p.join(audioDir.path, 'restored_${DateTime.now().microsecondsSinceEpoch}_$i$extension'));
        await restored.writeAsBytes(bytes, flush: true);
        row['file_path'] = restored.path;
        restoredRows.add(row);
      }
      data['audio_events'] = restoredRows;
    }
    await SleepDatabase.instance.restoreSnapshot(data, merge: merge);
    if (!merge) {
      for (final row in previousAudio) { try { await File(row['file_path']! as String).delete(); } catch (_) {} }
    }
    return BackupImportResult.imported;
  }
}

enum BackupImportResult { cancelled, imported }
