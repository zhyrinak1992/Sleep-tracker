import 'package:path/path.dart' as p;

enum StorageFileCategory {
  database,
  audio,
  report,
  backup,
  cache,
  other,
}

class StoragePathClassifier {
  StoragePathClassifier._();

  static StorageFileCategory classify({
    required String filePath,
    required String documentsPath,
    required String cachePath,
    required String temporaryPath,
  }) {
    final file = p.normalize(p.absolute(filePath));
    final documents = p.normalize(p.absolute(documentsPath));
    final cache = p.normalize(p.absolute(cachePath));
    final temporary = p.normalize(p.absolute(temporaryPath));
    final name = p.basename(file);
    final extension = p.extension(file).toLowerCase();

    final isDatabase = p.dirname(file) == documents &&
        (name == 'sleep_tracker.sqlite' ||
         name.startsWith('sleep_tracker.sqlite-') ||
         name.startsWith('sleep_tracker.sqlite.'));
    if (isDatabase) return StorageFileCategory.database;

    final audioDirectories = [
      p.join(documents, 'audio_events'),
      p.join(documents, 'sleep_audio'),
    ];
    if (audioDirectories.any((directory) => p.isWithin(directory, file))) {
      return StorageFileCategory.audio;
    }

    if (p.isWithin(temporary, file) && extension == '.pdf') {
      return StorageFileCategory.report;
    }

    final isBackupExtension = extension == '.sleepbackup' || extension == '.stbackup';
    final isLegacyBackupName = name.startsWith('SleepTracker-backup-') && extension == '.json';
    if (p.isWithin(temporary, file) && (isBackupExtension || isLegacyBackupName)) {
      return StorageFileCategory.backup;
    }

    if (p.isWithin(cache, file)) return StorageFileCategory.cache;
    return StorageFileCategory.other;
  }
}
