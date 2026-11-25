import 'dart:io';
import 'package:disk_usage/disk_usage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'sleep_database.dart';

class StorageSnapshot {
  const StorageSnapshot({
    required this.appBytes,
    required this.databaseBytes,
    required this.audioBytes,
    required this.reportBytes,
    required this.backupBytes,
    required this.cacheBytes,
    required this.temporaryBytes,
    required this.otherBytes,
    required this.freeBytes,
    required this.totalDiskBytes,
  });

  final int appBytes;
  final int databaseBytes;
  final int audioBytes;
  final int reportBytes;
  final int backupBytes;
  final int cacheBytes;
  final int temporaryBytes;
  final int otherBytes;
  final int? freeBytes;
  final int? totalDiskBytes;
}

class StorageService {
  StorageService._();
  static final instance = StorageService._();

  static const defaultWarningThreshold = 1024 * 1024 * 1024;
  static const thresholdMetadataKey = 'storage_warning_threshold_bytes';

  static bool isBackupFile(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.stbackup' || extension == '.sleepbackup';
  }

  Future<StorageSnapshot> measure() async {
    final documents = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final temporary = await getTemporaryDirectory();

    final cacheBytes = await _directoryBytes(cache);
    final temporaryBytes = await _directoryBytes(temporary);
    final databaseBytes = await _databaseBytes(documents);
    final audioBytes = await _directoryBytes(Directory(p.join(documents.path, 'audio_events')));
    final reportBytes = await _extensionBytes(temporary, '.pdf');
    final backupBytes = await _matchingFileBytes(temporary, isBackupFile);

    final uniqueDirectories = <String>[];
    final candidates = [documents.path, support.path, cache.path, temporary.path]
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final candidate in candidates) {
      final normalized = p.normalize(p.absolute(candidate));
      if (!uniqueDirectories.any((parent) => normalized == parent || p.isWithin(parent, normalized))) {
        uniqueDirectories.add(normalized);
      }
    }
    var appBytes = 0;
    for (final path in uniqueDirectories) {
      appBytes += await _directoryBytes(Directory(path));
    }

    final freeBytes = await _safeDiskValue(() => DiskUsage.freeSpace());
    final totalDiskBytes = await _safeDiskValue(() => DiskUsage.totalSpace());
    final otherBytes = (appBytes - databaseBytes - audioBytes - reportBytes - backupBytes - cacheBytes).clamp(0, appBytes).toInt();

    return StorageSnapshot(
      appBytes: appBytes,
      databaseBytes: databaseBytes,
      audioBytes: audioBytes,
      reportBytes: reportBytes,
      backupBytes: backupBytes,
      cacheBytes: cacheBytes,
      temporaryBytes: temporaryBytes,
      otherBytes: otherBytes,
      freeBytes: freeBytes,
      totalDiskBytes: totalDiskBytes,
    );
  }

  Future<int> getWarningThreshold() async {
    final stored = await SleepDatabase.instance.getAppMetadata(thresholdMetadataKey);
    final value = int.tryParse(stored ?? '');
    if (value == 500 * 1024 * 1024 ||
        value == 1024 * 1024 * 1024 ||
        value == 2 * 1024 * 1024 * 1024) {
      return value!;
    }
    return defaultWarningThreshold;
  }

  Future<void> setWarningThreshold(int bytes) async {
    const allowed = {
      500 * 1024 * 1024,
      1024 * 1024 * 1024,
      2 * 1024 * 1024 * 1024,
    };
    if (!allowed.contains(bytes)) {
      throw ArgumentError.value(bytes, 'bytes', 'Недопустимый порог предупреждения.');
    }
    await SleepDatabase.instance.setAppMetadata(thresholdMetadataKey, bytes.toString());
  }

  /// Удаляет только содержимое Caches. Documents и Temporary не затрагиваются:
  /// там могут находиться аудиофайлы, PDF-отчёты и временные копии резервных архивов.
  Future<int> clearCache() async {
    final cache = await getApplicationCacheDirectory();
    if (!await cache.exists()) return 0;
    var removedBytes = 0;
    await for (final entity in cache.list(followLinks: false)) {
      removedBytes += entity is Directory
          ? await _directoryBytes(entity)
          : await _entityBytes(entity);
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // One locked cache item must not prevent the rest from being cleared.
      }
    }
    return removedBytes;
  }

  Future<int> _databaseBytes(Directory documents) async {
    if (!await documents.exists()) return 0;
    var total = 0;
    await for (final entity in documents.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name == 'sleep_tracker.sqlite' ||
          name.startsWith('sleep_tracker.sqlite-') ||
          name.startsWith('sleep_tracker.sqlite.')) {
        total += await _entityBytes(entity);
      }
    }
    return total;
  }

  Future<int> _extensionBytes(Directory directory, String extension) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == extension) {
        total += await _entityBytes(entity);
      }
    }
    return total;
  }

  Future<int> _matchingFileBytes(
    Directory directory,
    bool Function(String path) matches,
  ) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && matches(entity.path)) {
        total += await _entityBytes(entity);
      }
    }
    return total;
  }

  Future<int> _directoryBytes(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      total += await _entityBytes(entity);
    }
    return total;
  }

  Future<int> _entityBytes(FileSystemEntity entity) async {
    if (entity is! File) return 0;
    try {
      return await entity.length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<int?> _safeDiskValue(Future<int?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }
}
