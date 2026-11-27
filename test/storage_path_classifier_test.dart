import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sleep_tracker/data/storage_path_classifier.dart';
import 'package:sleep_tracker/data/storage_service.dart';

void main() {
  group('StoragePathClassifier', () {
    const documents = '/app/Documents';
    const cache = '/app/Library/Caches';
    const temporary = '/app/tmp';

    StorageFileCategory classify(String path) => StoragePathClassifier.classify(
      filePath: path,
      documentsPath: documents,
      cachePath: cache,
      temporaryPath: temporary,
    );

    test('warning threshold choices are exactly 500 MB, 1 GB and 2 GB', () {
      expect(StorageService.defaultWarningThreshold, 1024 * 1024 * 1024);
      expect(StorageService.allowedWarningThresholds, {
        500 * 1024 * 1024,
        1024 * 1024 * 1024,
        2 * 1024 * 1024 * 1024,
      });
    });

    test('counts SQLite database and sidecar files as database storage', () {
      expect(classify(p.join(documents, 'sleep_tracker.sqlite')), StorageFileCategory.database);
      expect(classify(p.join(documents, 'sleep_tracker.sqlite-wal')), StorageFileCategory.database);
      expect(classify(p.join(documents, 'sleep_tracker.sqlite-shm')), StorageFileCategory.database);
    });

    test('counts current and legacy audio directories', () {
      expect(classify(p.join(documents, 'audio_events', 'event.wav')), StorageFileCategory.audio);
      expect(classify(p.join(documents, 'sleep_audio', 'legacy.wav')), StorageFileCategory.audio);
    });

    test('counts new and legacy backup formats in temporary storage', () {
      expect(classify(p.join(temporary, 'SleepTracker-backup-1.sleepbackup')), StorageFileCategory.backup);
      expect(classify(p.join(temporary, 'SleepTracker-backup-2.stbackup')), StorageFileCategory.backup);
      expect(classify(p.join(temporary, 'SleepTracker-backup-3.json')), StorageFileCategory.backup);
    });

    test('separates PDF reports and cache without double categorizing', () {
      expect(classify(p.join(temporary, 'report.pdf')), StorageFileCategory.report);
      expect(classify(p.join(cache, 'image-cache.bin')), StorageFileCategory.cache);
      expect(classify(p.join(documents, 'preferences.json')), StorageFileCategory.other);
    });
  });
}
