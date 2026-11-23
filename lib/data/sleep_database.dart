import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import '../models/sleep_session.dart';
import '../models/sleep_tag.dart';
import '../models/sleep_note.dart';

class SleepDatabase {
  SleepDatabase._();
  static final SleepDatabase instance = SleepDatabase._();
  static const _uuid = Uuid();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, 'sleep_tracker.sqlite');
    _db = await openDatabase(
      dbPath,
      version: 8,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sleep_sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            source TEXT NOT NULL,
            note TEXT,
            morning_rating INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_sleep_sessions_started_at ON sleep_sessions(started_at)',
        );
        await db.execute('''
          CREATE TABLE app_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.insert('app_metadata', {
          'key': 'schema_created_at',
          'value': DateTime.now().toUtc().toIso8601String(),
        });
        await db.execute("""
          CREATE TABLE sleep_session_tags (
            session_id TEXT NOT NULL,
            tag_key TEXT NOT NULL,
            label TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (session_id, tag_key),
            FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
          )
        """);
        await db.execute('CREATE INDEX idx_session_tags_session ON sleep_session_tags(session_id)');
        await db.execute('CREATE INDEX idx_session_tags_key ON sleep_session_tags(tag_key)');
        await db.execute("""
          CREATE TABLE sleep_notes (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
          )
        """);
        await db.execute('CREATE INDEX idx_sleep_notes_session ON sleep_notes(session_id)');
        await db.execute('CREATE INDEX idx_sleep_notes_updated ON sleep_notes(updated_at)');
        await _createV4Tables(db);
        await _createV5Columns(db);
        await _createV6Tables(db);
        await _createV7Columns(db);
        await _createV8AudioRetention(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Добавочная миграция: существующие ночи и их ID не изменяются.
        if (oldVersion < 2) {
          await db.execute("""
            CREATE TABLE sleep_session_tags (
              session_id TEXT NOT NULL,
              tag_key TEXT NOT NULL,
              label TEXT NOT NULL,
              created_at TEXT NOT NULL,
              PRIMARY KEY (session_id, tag_key),
              FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
            )
          """);
          await db.execute('CREATE INDEX idx_session_tags_session ON sleep_session_tags(session_id)');
          await db.execute('CREATE INDEX idx_session_tags_key ON sleep_session_tags(tag_key)');
        }
        if (oldVersion < 3) {
          await db.execute("""
            CREATE TABLE sleep_notes (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              body TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE
            )
          """);
          await db.execute('CREATE INDEX idx_sleep_notes_session ON sleep_notes(session_id)');
          await db.execute('CREATE INDEX idx_sleep_notes_updated ON sleep_notes(updated_at)');
          final legacyNotes = await db.query('sleep_sessions',
              columns: ['id', 'note', 'created_at', 'updated_at'],
              where: 'note IS NOT NULL AND TRIM(note) <> ""');
          for (final row in legacyNotes) {
            final now = DateTime.now().toUtc().toIso8601String();
            await db.insert('sleep_notes', {
              'id': _uuid.v4(),
              'session_id': row['id'],
              'body': (row['note'] as String).trim(),
              'created_at': row['created_at'] ?? now,
              'updated_at': row['updated_at'] ?? now,
            });
          }
        }
        if (oldVersion < 4) await _createV4Tables(db);
        if (oldVersion < 5) await _createV5Columns(db);
        if (oldVersion < 6) await _createV6Tables(db);
        if (oldVersion < 7) await _createV7Columns(db);
        if (oldVersion < 8) await _createV8AudioRetention(db);
      },
    );
    return _db!;
  }


  /// Экспортирует все существующие таблицы приложения в переносимую структуру.
  Future<Map<String, Object?>> exportSnapshot() async {
    final db = await database;
    // Читаем все таблицы в одной транзакции: параллельные изменения приложения
    // не смогут сформировать резервную копию из разных временных состояний БД.
    return db.transaction((txn) async {
      return {
        'schemaVersion': 8,
        'sleep_sessions': await txn.query('sleep_sessions', orderBy: 'started_at ASC'),
        'sleep_session_tags': await txn.query('sleep_session_tags', orderBy: 'session_id ASC, tag_key ASC'),
        'sleep_notes': await txn.query('sleep_notes', orderBy: 'created_at ASC'),
        'app_metadata': await txn.query('app_metadata', orderBy: 'key ASC'),
        'sleep_stages': await txn.query('sleep_stages', orderBy: 'started_at ASC'),
        'sleep_metrics': await txn.query('sleep_metrics', orderBy: 'measured_at ASC'),
        'audio_events': await txn.query('audio_events', orderBy: 'captured_at ASC'),
        'morning_reports': await txn.query('morning_reports', orderBy: 'report_date ASC'),
        'climate_samples': await txn.query('climate_samples', orderBy: 'measured_at ASC'),
      };
    });
  }

  /// Полное восстановление с проверкой структуры и атомарной заменой данных.
  /// При любой ошибке SQLite откатывает транзакцию и оставляет исходную базу.
  /// Проверяет структуру архива без записи в SQLite. Используется перед показом предпросмотра.
  Map<String, List<Map<String, Object?>>> validateSnapshot(Map<String, dynamic> snapshot) {
    if (snapshot['schemaVersion'] != 3 && snapshot['schemaVersion'] != 4 && snapshot['schemaVersion'] != 5 && snapshot['schemaVersion'] != 6 && snapshot['schemaVersion'] != 7 && snapshot['schemaVersion'] != 8) {
      throw const FormatException('Версия структуры резервной копии не поддерживается.');
    }
    const tables = ['sleep_sessions', 'sleep_session_tags', 'sleep_notes', 'app_metadata', 'sleep_stages', 'sleep_metrics', 'audio_events', 'morning_reports', 'climate_samples'];
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final value = snapshot[table];
      if (value == null && snapshot['schemaVersion'] < 6 && table == 'climate_samples') { rowsByTable[table] = []; continue; }
      if (value == null && snapshot['schemaVersion'] == 3 && tables.indexOf(table) >= 4) { rowsByTable[table] = []; continue; }
      if (value is! List) { throw FormatException('В резервной копии отсутствует раздел $table.'); }
      rowsByTable[table] = value.map((row) {
        if (row is! Map) throw FormatException('Некорректная запись в разделе $table.');
        return Map<String, Object?>.from(row);
      }).toList();
    }
    final sessionIds = <String>{};
    for (final row in rowsByTable['sleep_sessions']!) {
      if (row['id'] is! String || row['started_at'] is! String ||
          row['source'] is! String || row['created_at'] is! String ||
          row['updated_at'] is! String) {
        throw const FormatException('В резервной копии обнаружена неполная запись сна.');
      }
      if (!sessionIds.add(row['id']! as String)) {
        throw const FormatException('В резервной копии обнаружены повторяющиеся ID ночей.');
      }
      final rating = row['morning_rating'];
      if (rating != null && (rating is! int || rating < 1 || rating > 5)) {
        throw const FormatException('В резервной копии обнаружена некорректная оценка самочувствия.');
      }
    }
    // Проверяем обязательные поля и уникальность до начала транзакции.
    // Это даёт понятную ошибку архива вместо частичного импорта или ошибки SQLite.
    const requiredFields = <String, List<String>>{
      'sleep_session_tags': ['session_id', 'tag_key', 'label', 'created_at'],
      'sleep_notes': ['id', 'session_id', 'body', 'created_at', 'updated_at'],
      'app_metadata': ['key', 'value'],
      'sleep_stages': ['id', 'session_id', 'stage', 'started_at', 'ended_at', 'source'],
      'sleep_metrics': ['id', 'session_id', 'metric_type', 'value', 'unit', 'measured_at', 'source'],
      'audio_events': ['id', 'category', 'captured_at', 'expires_at', 'duration_ms', 'user_corrected'],
      'morning_reports': ['id', 'session_id', 'report_date', 'created_at'],
      'climate_samples': ['id', 'device_id', 'metric_type', 'value', 'unit', 'source', 'measured_at', 'received_at', 'quality'],
    };
    for (final entry in requiredFields.entries) {
      for (final row in rowsByTable[entry.key]!) {
        for (final field in entry.value) {
          if (!row.containsKey(field) || row[field] == null) {
            throw FormatException('В разделе ${entry.key} отсутствует обязательное поле $field.');
          }
        }
      }
    }

    for (final table in ['sleep_session_tags', 'sleep_notes', 'sleep_stages', 'sleep_metrics', 'morning_reports']) {
      for (final row in rowsByTable[table]!) {
        final sessionId = row['session_id'];
        if (sessionId is! String || !sessionIds.contains(sessionId)) {
          throw FormatException('В разделе $table есть пустая или недействительная ссылка на ночь.');
        }
      }
    }
    for (final table in ['audio_events', 'climate_samples']) {
      for (final row in rowsByTable[table]!) {
        final sessionId = row['session_id'];
        if (sessionId != null && (sessionId is! String || !sessionIds.contains(sessionId))) {
          throw FormatException('В разделе $table есть ссылка на отсутствующую ночь.');
        }
      }
    }

    void ensureUnique(String table, String field) {
      final seen = <Object?>{};
      for (final row in rowsByTable[table]!) {
        if (!seen.add(row[field])) {
          throw FormatException('В разделе $table обнаружены повторяющиеся значения $field.');
        }
      }
    }
    for (final table in ['sleep_notes', 'sleep_stages', 'sleep_metrics', 'audio_events', 'morning_reports']) {
      ensureUnique(table, 'id');
    }
    ensureUnique('app_metadata', 'key');
    final tagKeys = <String>{};
    for (final row in rowsByTable['sleep_session_tags']!) {
      final key = '${row['session_id']}::${row['tag_key']}';
      if (!tagKeys.add(key)) throw const FormatException('В резервной копии обнаружены повторяющиеся теги ночи.');
    }
    final reportSessions = <String>{};
    for (final row in rowsByTable['morning_reports']!) {
      if (!reportSessions.add(row['session_id']! as String)) {
        throw const FormatException('В резервной копии обнаружено несколько утренних отчётов для одной ночи.');
      }
    }
    return rowsByTable;
  }

  /// Полное восстановление с проверкой структуры и атомарной заменой данных.
  /// При любой ошибке SQLite откатывает транзакцию и оставляет исходную базу.
  Future<void> restoreSnapshot(Map<String, dynamic> snapshot, {bool merge = false}) async {
    final rowsByTable = validateSnapshot(snapshot);
    const tables = ['sleep_sessions', 'sleep_session_tags', 'sleep_notes', 'app_metadata', 'sleep_stages', 'sleep_metrics', 'audio_events', 'morning_reports', 'climate_samples'];
    final db = await database;
    await db.transaction((txn) async {
      if (!merge) {
        // Удаляем все дочерние разделы явно до родительских записей.
        // audio_events использует ON DELETE SET NULL, поэтому одного удаления
        // sleep_sessions недостаточно: старые события иначе останутся в базе.
        await txn.delete('sleep_notes');
        await txn.delete('sleep_session_tags');
        await txn.delete('audio_events');
        await txn.delete('morning_reports');
        await txn.delete('sleep_stages');
        await txn.delete('sleep_metrics');
        await txn.delete('climate_samples');
        await txn.delete('sleep_sessions');
        await txn.delete('app_metadata');
        for (final table in tables) {
          for (final row in rowsByTable[table]!) {
            await txn.insert(table, row);
          }
        }
        return;
      }

      // Безопасное объединение: локальные записи с совпадающими ID имеют приоритет.
      for (final row in rowsByTable['sleep_sessions']!) {
        final id = row['id']! as String;
        final exists = await txn.query('sleep_sessions', columns: ['id'],
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (exists.isEmpty) await txn.insert('sleep_sessions', row);
      }
      for (final row in rowsByTable['sleep_session_tags']!) {
        final exists = await txn.query('sleep_session_tags', columns: ['session_id'],
            where: 'session_id = ? AND tag_key = ?',
            whereArgs: [row['session_id'], row['tag_key']], limit: 1);
        if (exists.isEmpty) await txn.insert('sleep_session_tags', row);
      }
      for (final row in rowsByTable['sleep_notes']!) {
        final exists = await txn.query('sleep_notes', columns: ['id'],
            where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (exists.isEmpty) await txn.insert('sleep_notes', row);
      }
      for (final row in rowsByTable['app_metadata']!) {
        final exists = await txn.query('app_metadata', columns: ['key'],
            where: 'key = ?', whereArgs: [row['key']], limit: 1);
        if (exists.isEmpty) await txn.insert('app_metadata', row);
      }
      for (final table in ['sleep_stages', 'sleep_metrics', 'audio_events', 'climate_samples']) {
        for (final row in rowsByTable[table]!) {
          final exists = await txn.query(table, columns: ['id'], where: 'id = ?', whereArgs: [row['id']], limit: 1);
          if (exists.isEmpty) await txn.insert(table, row);
        }
      }
      for (final row in rowsByTable['morning_reports']!) {
        final exists = await txn.query('morning_reports', columns: ['session_id'], where: 'session_id = ?', whereArgs: [row['session_id']], limit: 1);
        if (exists.isEmpty) await txn.insert('morning_reports', row);
      }
    });
  }

  /// Сохраняет импортированную ночь из Apple Health, не затрагивая ручные записи.
  /// ID привязан к первому HealthKit sample, поэтому повторная синхронизация
  /// не создаёт копии уже импортированной ночи.
  /// Возвращает ID существующей или вновь созданной ночи Apple Health.
  /// Повторная синхронизация может безопасно дополнять стадии и метрики.
  Future<(String?, bool)> upsertHealthSession({
    required String id,
    required DateTime startedAt,
    required DateTime endedAt,
    required String sourceName,
  }) async {
    if (!endedAt.isAfter(startedAt)) return (null, false);
    final db = await database;
    return db.transaction((txn) async {
      final existingById = await txn.query(
        'sleep_sessions', columns: ['id'],
        where: 'id = ?', whereArgs: [id], limit: 1,
      );
      if (existingById.isNotEmpty) {
        return (existingById.first['id']! as String, false);
      }

      final existingHealthNights = await txn.query(
        'sleep_sessions',
        columns: ['id', 'started_at', 'ended_at'],
        where: 'source LIKE ? AND ended_at IS NOT NULL',
        whereArgs: ['apple_health:%'],
      );
      for (final row in existingHealthNights) {
        final storedStart = DateTime.tryParse(row['started_at']! as String);
        final storedEnd = DateTime.tryParse(row['ended_at']! as String);
        if (storedStart != null && storedEnd != null &&
            storedStart.isAtSameMomentAs(startedAt) &&
            storedEnd.isAtSameMomentAs(endedAt)) {
          return (row['id']! as String, false);
        }
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final inserted = await txn.insert('sleep_sessions', {
        'id': id,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'source': 'apple_health:$sourceName',
        'note': null,
        'morning_rating': null,
        'created_at': now,
        'updated_at': now,
        'actual_sleep_started_at': startedAt.toUtc().toIso8601String(),
        'actual_sleep_ended_at': endedAt.toUtc().toIso8601String(),
        'user_edited': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (inserted == 0) {
        final raced = await txn.query('sleep_sessions', columns: ['id'],
            where: 'id = ?', whereArgs: [id], limit: 1);
        return (raced.isEmpty ? null : raced.first['id']! as String, false);
      }
      return (id, true);
    });
  }

  /// Совместимый API для старого импортёра Apple Health из XML/ZIP.
  Future<bool> insertHealthSession({
    required String id,
    required DateTime startedAt,
    required DateTime endedAt,
    required String sourceName,
  }) async {
    final result = await upsertHealthSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      sourceName: sourceName,
    );
    return result.$2;
  }

  Future<void> _createV4Tables(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS sleep_stages (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, stage TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, source TEXT NOT NULL, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE IF NOT EXISTS sleep_metrics (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, metric_type TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL, measured_at TEXT NOT NULL, source TEXT NOT NULL, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE)');
    await db.execute("CREATE TABLE IF NOT EXISTS audio_events (id TEXT PRIMARY KEY, session_id TEXT, file_path TEXT, category TEXT NOT NULL DEFAULT 'unknown', confidence REAL, captured_at TEXT NOT NULL, expires_at TEXT NOT NULL, duration_ms INTEGER NOT NULL, user_corrected INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL)");
    await db.execute('CREATE TABLE IF NOT EXISTS morning_reports (id TEXT PRIMARY KEY, session_id TEXT NOT NULL UNIQUE, report_date TEXT NOT NULL, wellbeing INTEGER, sleep_quality INTEGER, answers_json TEXT, created_at TEXT NOT NULL, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stages_session ON sleep_stages(session_id, started_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_metrics_session ON sleep_metrics(session_id, measured_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audio_expiry ON audio_events(expires_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reports_date ON morning_reports(report_date)');
  }

  Future<void> _createV6Tables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS climate_samples (
      id TEXT PRIMARY KEY,
      session_id TEXT,
      device_id TEXT NOT NULL,
      device_name TEXT,
      room_name TEXT,
      metric_type TEXT NOT NULL,
      value REAL NOT NULL,
      unit TEXT NOT NULL,
      source TEXT NOT NULL,
      measured_at TEXT NOT NULL,
      received_at TEXT NOT NULL,
      quality TEXT NOT NULL DEFAULT 'actual',
      FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_climate_samples_time ON climate_samples(measured_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_climate_samples_session ON climate_samples(session_id, metric_type, measured_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_climate_samples_device ON climate_samples(device_id, metric_type, measured_at)');
  }

  /// Schema v8: сохраняем метаданные события после удаления аудиофайла.
  /// file_path становится nullable; сама строка события остаётся в истории.
  Future<void> _createV8AudioRetention(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE audio_events_v8 (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        file_path TEXT,
        category TEXT NOT NULL DEFAULT 'unknown',
        confidence REAL,
        captured_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        user_corrected INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      INSERT INTO audio_events_v8
      (id, session_id, file_path, category, confidence, captured_at, expires_at, duration_ms, user_corrected)
      SELECT id, session_id, file_path, category, confidence, captured_at, expires_at, duration_ms, user_corrected
      FROM audio_events
    ''');
    await db.execute('DROP TABLE audio_events');
    await db.execute('ALTER TABLE audio_events_v8 RENAME TO audio_events');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audio_expiry ON audio_events(expires_at)');
  }

  Future<void> _createV7Columns(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(sleep_sessions)'))
        .map((row) => row['name'] as String).toSet();
    if (!columns.contains('deleted_at')) {
      await db.execute('ALTER TABLE sleep_sessions ADD COLUMN deleted_at TEXT');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sleep_sessions_deleted_at ON sleep_sessions(deleted_at)');
  }

  /// Перемещает одну завершённую ночь в корзину.
  Future<void> moveSessionToTrash(String sessionId) => moveSessionsToTrash([sessionId]);

  /// Перемещает выбранные завершённые ночи в корзину одной транзакцией.
  Future<void> moveSessionsToTrash(Iterable<String> sessionIds) async {
    final ids = sessionIds.toSet().toList();
    if (ids.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query('sleep_sessions', columns: ['id', 'ended_at', 'deleted_at'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) throw StateError('Ночная запись не найдена.');
        if (rows.single['ended_at'] == null) throw StateError('Нельзя переместить активную сессию в корзину.');
        if (rows.single['deleted_at'] == null) {
          await txn.update('sleep_sessions', {'deleted_at': now, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }

  Future<void> restoreSessionFromTrash(String sessionId) async {
    final count = await (await database).update('sleep_sessions', {'deleted_at': null, 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'id = ? AND deleted_at IS NOT NULL', whereArgs: [sessionId]);
    if (count == 0) throw StateError('Запись не найдена в корзине.');
  }

  Future<int> restoreAllTrashedSessions() async {
    final now = DateTime.now().toUtc().toIso8601String();
    return (await database).update('sleep_sessions', {'deleted_at': null, 'updated_at': now}, where: 'deleted_at IS NOT NULL');
  }

  Future<void> permanentlyDeleteSession(String sessionId) => permanentlyDeleteSessions([sessionId]);

  Future<void> permanentlyDeleteSessions(Iterable<String> sessionIds) async {
    final ids = sessionIds.toSet().toList();
    if (ids.isEmpty) return;
    final db = await database;
    final audioPaths = <String>[];
    await db.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query('sleep_sessions', columns: ['id', 'deleted_at'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) continue;
        if (rows.single['deleted_at'] == null) throw StateError('Сначала переместите запись в корзину.');
        final audio = await txn.query('audio_events', columns: ['file_path'], where: 'session_id = ?', whereArgs: [id]);
        audioPaths.addAll(audio.map((row) => row['file_path']).whereType<String>());
        await txn.delete('sleep_sessions', where: 'id = ?', whereArgs: [id]);
      }
    });
    for (final path in audioPaths) { try { await File(path).delete(); } catch (_) {} }
  }

  Future<void> permanentlyDeleteAllTrashedSessions() async {
    final rows = await (await database).query('sleep_sessions', columns: ['id'], where: 'deleted_at IS NOT NULL');
    await permanentlyDeleteSessions(rows.map((row) => row['id']! as String));
  }

  Future<int> purgeExpiredTrash({DateTime? now}) async {
    final db = await database;
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final audioPaths = <String>[];
    var deletedCount = 0;
    await db.transaction((txn) async {
      final expired = await txn.query('sleep_sessions', columns: ['id'], where: 'deleted_at IS NOT NULL AND deleted_at <= ?', whereArgs: [cutoff]);
      for (final row in expired) {
        final id = row['id']! as String;
        final audio = await txn.query('audio_events', columns: ['file_path'], where: 'session_id = ?', whereArgs: [id]);
        audioPaths.addAll(audio.map((item) => item['file_path']).whereType<String>());
        deletedCount += await txn.delete('sleep_sessions', where: 'id = ? AND deleted_at IS NOT NULL', whereArgs: [id]);
      }
    });
    for (final path in audioPaths) { try { await File(path).delete(); } catch (_) {} }
    return deletedCount;
  }

  Future<List<DateTime>> getTrashExpiryDates() async {
    final rows = await (await database).query('sleep_sessions', columns: ['deleted_at'], where: 'deleted_at IS NOT NULL');
    return rows.map((row) => DateTime.parse(row['deleted_at']! as String).toLocal().add(const Duration(days: 30))).toList();
  }

  Future<List<SleepSession>> getTrashedSessions() async {
    final rows = await (await database).query('sleep_sessions', where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
    return rows.map(SleepSession.fromMap).toList();
  }

  /// Записывает только фактически полученное измерение; одинаковые ID не дублируются.
  Future<bool> saveClimateSample({
    required String id,
    String? sessionId,
    required String deviceId,
    String? deviceName,
    String? roomName,
    required String metricType,
    required double value,
    required String unit,
    required String source,
    required DateTime measuredAt,
    String quality = 'actual',
  }) async {
    if (!value.isFinite) throw ArgumentError('Значение климатического датчика должно быть конечным числом.');
    if (metricType != 'temperature' && metricType != 'humidity') {
      throw ArgumentError.value(metricType, 'metricType', 'Поддерживаются только температура и влажность.');
    }
    if (metricType == 'temperature' && unit != '°C') throw ArgumentError('Температура должна быть сохранена в °C.');
    if (metricType == 'humidity' && unit != '%') throw ArgumentError('Влажность должна быть сохранена в процентах.');
    if (metricType == 'humidity' && (value < 0 || value > 100)) throw ArgumentError('Влажность должна быть в диапазоне от 0 до 100%.');
    final db = await database;
    final inserted = await db.insert('climate_samples', {
      'id': id, 'session_id': sessionId, 'device_id': deviceId,
      'device_name': deviceName, 'room_name': roomName,
      'metric_type': metricType, 'value': value, 'unit': unit,
      'source': source, 'measured_at': measuredAt.toUtc().toIso8601String(),
      'received_at': DateTime.now().toUtc().toIso8601String(), 'quality': quality,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return inserted > 0;
  }

  Future<List<Map<String, Object?>>> getClimateSamples({
    String? sessionId, String? deviceId, DateTime? from, DateTime? to,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (sessionId != null) { clauses.add('session_id = ?'); args.add(sessionId); }
    if (deviceId != null) { clauses.add('device_id = ?'); args.add(deviceId); }
    if (from != null) { clauses.add('measured_at >= ?'); args.add(from.toUtc().toIso8601String()); }
    if (to != null) { clauses.add('measured_at <= ?'); args.add(to.toUtc().toIso8601String()); }
    return (await database).query('climate_samples',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: clauses.isEmpty ? null : args,
      orderBy: 'measured_at ASC');
  }

  Future<void> _createV5Columns(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(sleep_sessions)'))
        .map((row) => row['name'] as String).toSet();
    if (!columns.contains('button_started_at')) await db.execute('ALTER TABLE sleep_sessions ADD COLUMN button_started_at TEXT');
    if (!columns.contains('button_ended_at')) await db.execute('ALTER TABLE sleep_sessions ADD COLUMN button_ended_at TEXT');
    if (!columns.contains('actual_sleep_started_at')) await db.execute('ALTER TABLE sleep_sessions ADD COLUMN actual_sleep_started_at TEXT');
    if (!columns.contains('actual_sleep_ended_at')) await db.execute('ALTER TABLE sleep_sessions ADD COLUMN actual_sleep_ended_at TEXT');
    if (!columns.contains('user_edited')) await db.execute('ALTER TABLE sleep_sessions ADD COLUMN user_edited INTEGER NOT NULL DEFAULT 0');
    await db.execute('UPDATE sleep_sessions SET button_started_at = started_at WHERE source = \'manual\' AND button_started_at IS NULL');
    await db.execute('UPDATE sleep_sessions SET button_ended_at = ended_at WHERE source = \'manual\' AND ended_at IS NOT NULL AND button_ended_at IS NULL');
    await db.execute('UPDATE sleep_sessions SET actual_sleep_started_at = started_at, actual_sleep_ended_at = ended_at WHERE source LIKE \'apple_health:%\' AND actual_sleep_started_at IS NULL');
  }

  Future<void> saveSessionRecord({String? id, required DateTime startedAt, required DateTime endedAt, String? note}) async {
    if (!endedAt.isAfter(startedAt)) throw ArgumentError('Время пробуждения должно быть позже времени засыпания.');
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    if (id == null) {
      final session = SleepSession(
        id: _uuid.v4(), startedAt: startedAt, endedAt: endedAt,
        source: 'manual_entry', note: note?.trim().isEmpty == true ? null : note?.trim(),
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
        actualSleepStartedAt: startedAt, actualSleepEndedAt: endedAt, userEdited: true,
      );
      await db.insert('sleep_sessions', session.toMap());
      return;
    }
    final rows = await db.query('sleep_sessions', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('Ночная запись не найдена.');
    await db.update('sleep_sessions', {
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt.toUtc().toIso8601String(),
      'actual_sleep_started_at': startedAt.toUtc().toIso8601String(),
      'actual_sleep_ended_at': endedAt.toUtc().toIso8601String(),
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'user_edited': 1,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addSleepStage({String? id, required String sessionId, required String stage, required DateTime startedAt, required DateTime endedAt, required String source}) async {
    if (!endedAt.isAfter(startedAt)) throw ArgumentError('Некорректный интервал фазы сна.');
    await (await database).insert('sleep_stages', {'id': id ?? _uuid.v4(), 'session_id': sessionId, 'stage': stage, 'started_at': startedAt.toUtc().toIso8601String(), 'ended_at': endedAt.toUtc().toIso8601String(), 'source': source}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  Future<void> addSleepMetric({String? id, required String sessionId, required String type, required double value, required String unit, required DateTime measuredAt, required String source}) async {
    if (!value.isFinite) throw ArgumentError('Значение показателя должно быть числом.');
    await (await database).insert('sleep_metrics', {'id': id ?? _uuid.v4(), 'session_id': sessionId, 'metric_type': type, 'value': value, 'unit': unit, 'measured_at': measuredAt.toUtc().toIso8601String(), 'source': source}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  Future<List<Map<String, Object?>>> getStages(String sessionId) async => (await database).query('sleep_stages', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'started_at');

  /// Loads stages for many sessions in bounded SQLite IN queries.
  Future<Map<String, List<Map<String, Object?>>>> getStagesForSessions(
    List<String> sessionIds,
  ) async {
    final ids = sessionIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final db = await database;
    final result = <String, List<Map<String, Object?>>>{};
    for (var offset = 0; offset < ids.length; offset += 900) {
      final chunk = ids.skip(offset).take(900).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'sleep_stages',
        where: 'session_id IN ($placeholders)',
        whereArgs: chunk,
        orderBy: 'session_id, started_at',
      );
      for (final row in rows) {
        final sessionId = row['session_id']! as String;
        (result[sessionId] ??= <Map<String, Object?>>[]).add(row);
      }
    }
    return result;
  }
  Future<List<Map<String, Object?>>> getMetrics(String sessionId) async => (await database).query('sleep_metrics', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'measured_at');
  Future<List<Map<String, Object?>>> getAllMetrics() async => (await database).query('sleep_metrics', orderBy: 'measured_at');
  Future<List<Map<String, Object?>>> getAudioEvents({String? sessionId}) async { final db = await database; return db.query('audio_events', where: sessionId == null ? null : 'session_id = ?', whereArgs: sessionId == null ? null : [sessionId], orderBy: 'captured_at DESC'); }
  Future<void> saveAudioEvent({required String id, required String? sessionId, required String filePath, required String category, required DateTime capturedAt, required int durationMs}) async {
    await (await database).insert('audio_events', {'id': id, 'session_id': sessionId, 'file_path': filePath, 'category': category, 'confidence': null, 'captured_at': capturedAt.toUtc().toIso8601String(), 'expires_at': capturedAt.toUtc().add(const Duration(days: 7)).toIso8601String(), 'duration_ms': durationMs, 'user_corrected': 0});
  }
  Future<void> deleteAudioEvent(String id) async {
    final db = await database;
    final rows = await db.query('audio_events', columns: ['file_path'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final path = rows.first['file_path'];
    if (path is String && path.isNotEmpty) { try { await File(path).delete(); } catch (_) {} }
    await db.delete('audio_events', where: 'id = ?', whereArgs: [id]);
  }
  Future<void> updateAudioClassification(String id, String category, double confidence) async => (await database).update('audio_events', {'category': category, 'confidence': confidence, 'user_corrected': 0}, where: 'id = ?', whereArgs: [id]);
  Future<void> updateAudioCategory(String id, String category) async => (await database).update('audio_events', {'category': category, 'user_corrected': 1}, where: 'id = ?', whereArgs: [id]);
  /// Удаляет только аудиофайлы старше срока хранения; карточки событий
  /// остаются в БД для истории, статистики и резервного копирования.
  Future<int> deleteExpiredAudioEvents(DateTime now) async {
    final db = await database;
    final expired = await db.query('audio_events',
      columns: ['id', 'file_path'],
      where: 'expires_at <= ? AND file_path IS NOT NULL',
      whereArgs: [now.toUtc().toIso8601String()]);
    if (expired.isEmpty) return 0;
    await db.transaction((txn) async {
      for (final row in expired) {
        await txn.update('audio_events', {'file_path': null},
          where: 'id = ?', whereArgs: [row['id']]);
      }
    });
    for (final row in expired) {
      final path = row['file_path'];
      if (path is String && path.isNotEmpty) {
        try { await File(path).delete(); } catch (_) {}
      }
    }
    return expired.length;
  }
  Future<Map<String, Object?>?> getMorningReport(String sessionId) async { final rows = await (await database).query('morning_reports', where: 'session_id = ?', whereArgs: [sessionId], limit: 1); return rows.isEmpty ? null : rows.first; }

  /// Loads morning reports keyed by session ID with bounded SQLite IN queries.
  Future<Map<String, Map<String, Object?>>> getMorningReportsForSessions(
    List<String> sessionIds,
  ) async {
    final ids = sessionIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final db = await database;
    final result = <String, Map<String, Object?>>{};
    for (var offset = 0; offset < ids.length; offset += 900) {
      final chunk = ids.skip(offset).take(900).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'morning_reports',
        where: 'session_id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        result[row['session_id']! as String] = row;
      }
    }
    return result;
  }
  Future<void> saveMorningReport({required String sessionId, required int? wellbeing, required int? quality, required String answersJson}) async {
    await (await database).insert('morning_reports', {'id': _uuid.v4(), 'session_id': sessionId, 'report_date': DateTime.now().toIso8601String().substring(0, 10), 'wellbeing': wellbeing, 'sleep_quality': quality, 'answers_json': answersJson, 'created_at': DateTime.now().toUtc().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SleepSession?> getSessionById(String id) async {
    final db = await database;
    final rows = await db.query(
      'sleep_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepSession.fromMap(rows.first);
  }

  Future<SleepSession?> getOpenSession() async {
    final db = await database;
    final rows = await db.query(
      'sleep_sessions',
      where: 'ended_at IS NULL AND deleted_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SleepSession.fromMap(rows.first);
  }

  Future<List<SleepSession>> getSessions({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'sleep_sessions',
      where: 'deleted_at IS NULL',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(SleepSession.fromMap).toList();
  }

  Future<SleepSession> startSession() async {
    final db = await database;
    final existing = await getOpenSession();
    if (existing != null) return existing;
    final now = DateTime.now();
    final session = SleepSession(
      id: _uuid.v4(),
      startedAt: now,
      source: 'manual',
      createdAt: now,
      updatedAt: now,
    );
    final values = session.toMap()..['button_started_at'] = now.toUtc().toIso8601String();
    await db.insert('sleep_sessions', values);
    return session;
  }

  Future<SleepSession> finishSession(String id) async {
    final db = await database;
    final now = DateTime.now();
    final count = await db.update(
      'sleep_sessions',
      {
        'ended_at': now.toUtc().toIso8601String(),
        'button_ended_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      },
      where: 'id = ? AND ended_at IS NULL',
      whereArgs: [id],
    );
    if (count == 0) {
      throw StateError('Активная сессия не найдена или уже завершена.');
    }
    final rows = await db.query('sleep_sessions', where: 'id = ?', whereArgs: [id]);
    return SleepSession.fromMap(rows.single);
  }

  Future<void> updateMorningRating(String id, int? rating) async {
    if (rating != null && (rating < 1 || rating > 5)) {
      throw ArgumentError.value(rating, 'rating', 'Оценка должна быть от 1 до 5');
    }
    final db = await database;
    await db.update(
      'sleep_sessions',
      {
        'morning_rating': rating,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getTagsForSession(String sessionId) async {
    final db = await database;
    final rows = await db.query('sleep_session_tags', columns: ['tag_key'],
      where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'label COLLATE NOCASE');
    return rows.map((row) => row['tag_key']! as String).toList();
  }

  /// Loads tag keys for many sessions in bounded SQL batches.
  Future<Map<String, Set<String>>> getTagsForSessions(List<String> sessionIds) async {
    final ids = sessionIds.toSet().where((id) => id.trim().isNotEmpty).toList();
    final result = <String, Set<String>>{for (final id in ids) id: <String>{}};
    if (ids.isEmpty) return result;
    final db = await database;
    for (var offset = 0; offset < ids.length; offset += 900) {
      final batch = ids.skip(offset).take(900).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');
      final rows = await db.rawQuery(
        'SELECT session_id, tag_key FROM sleep_session_tags WHERE session_id IN ($placeholders)',
        batch,
      );
      for (final row in rows) {
        final sessionId = row['session_id'] as String;
        final tagKey = row['tag_key'] as String;
        result.putIfAbsent(sessionId, () => <String>{}).add(tagKey);
      }
    }
    return result;
  }

  Future<void> setTagsForSession(String sessionId, List<SleepTag> tags) async {
    final db = await database;
    await db.transaction((txn) async {
      final exists = await txn.query('sleep_sessions', columns: ['id'],
        where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (exists.isEmpty) throw StateError('Ночная сессия не найдена.');
      await txn.delete('sleep_session_tags', where: 'session_id = ?', whereArgs: [sessionId]);
      final now = DateTime.now().toUtc().toIso8601String();
      for (final tag in tags) {
        await txn.insert('sleep_session_tags', {
          'session_id': sessionId, 'tag_key': tag.key, 'label': tag.label, 'created_at': now,
        });
      }
      await txn.update('sleep_sessions', {'updated_at': now}, where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  Future<String?> getAppMetadata(String key) async {
    final rows = await (await database).query('app_metadata', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setAppMetadata(String key, String value) async {
    await (await database).insert('app_metadata', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns immutable snapshots of automatically generated rolling sleep-change comparisons.
  /// The metadata row is part of exportSnapshot(), so history is included in manual backups.
  Future<List<Map<String, Object?>>> getSleepChangeHistory() async {
    final raw = await getAppMetadata('sleep_change_history_v1');
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('История изменений сна повреждена.');
    }
    return decoded.whereType<Map>().map((row) => Map<String, Object?>.from(row)).toList();
  }

  /// Appends a new monthly snapshot or a transparent revision when source data changed.
  /// Previous revisions are retained; identical fingerprints are never duplicated.
  Future<bool> saveSleepChangeHistorySnapshot(Map<String, Object?> snapshot) async {
    final periodKey = snapshot['periodKey'];
    final fingerprint = snapshot['fingerprint'];
    if (periodKey is! String || periodKey.isEmpty ||
        fingerprint is! String || fingerprint.isEmpty) {
      throw ArgumentError('У снимка истории отсутствует ключ периода или отпечаток данных.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('app_metadata', columns: ['value'],
        where: 'key = ?', whereArgs: ['sleep_change_history_v1'], limit: 1);
      final raw = rows.isEmpty ? null : rows.first['value'] as String?;
      final history = <Map<String, Object?>>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) throw const FormatException('История изменений сна повреждена; запись отменена без перезаписи.');
        for (final row in decoded) {
          if (row is! Map) throw const FormatException('Некорректная запись истории; запись отменена без перезаписи.');
          history.add(Map<String, Object?>.from(row));
        }
      }
      final samePeriod = history.where((item) => item['periodKey'] == periodKey).toList();
      if (samePeriod.any((item) => item['fingerprint'] == fingerprint)) return false;
      final latestVersion = samePeriod.fold<int>(0, (value, item) {
        final version = item['version'];
        return version is int && version > value ? version : value;
      });
      final stored = Map<String, Object?>.from(snapshot)
        ..['version'] = latestVersion + 1
        ..['supersedesVersion'] = latestVersion == 0 ? null : latestVersion
        ..['revisionReason'] = latestVersion == 0 ? 'Первичный снимок месяца' : 'Изменились исходные данные или состав сопоставимых наблюдений';
      history.add(stored);
      await txn.insert('app_metadata', {
        'key': 'sleep_change_history_v1',
        'value': jsonEncode(history),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  /// Returns namespaced metadata entries without exposing unrelated app settings.
  Future<Map<String, String>> getAppMetadataByPrefix(String prefix) async {
    if (prefix.isEmpty) throw ArgumentError.value(prefix, 'prefix', 'Prefix cannot be empty.');
    final rows = await (await database).query(
      'app_metadata',
      columns: ['key', 'value'],
      where: 'substr(key, 1, ?) = ?',
      whereArgs: [prefix.length, prefix],
      orderBy: 'key ASC',
    );
    return {for (final row in rows) row['key']! as String: row['value']! as String};
  }

  Future<Map<String, int>> getTagUsageCounts() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT tag_key, COUNT(*) AS total FROM sleep_session_tags GROUP BY tag_key ORDER BY total DESC, tag_key ASC');
    return {for (final row in rows) row['tag_key']! as String: row['total']! as int};
  }

  /// Returns night session IDs carrying any of the selected tags.
  /// An empty selection returns an empty set and does not scan the table.
  Future<Set<String>> getSessionIdsWithTags(List<String> tagKeys) async {
    final keys = tagKeys.toSet().where((key) => key.trim().isNotEmpty).toList();
    if (keys.isEmpty) return <String>{};
    final db = await database;
    final placeholders = List.filled(keys.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT DISTINCT session_id FROM sleep_session_tags WHERE tag_key IN ($placeholders)',
      keys,
    );
    return rows.map((row) => row['session_id']! as String).toSet();
  }

  Future<List<SleepNote>> getNotes({String? search, DateTime? month, String? sessionId}) async {
    final db = await database;
    final clauses = <String>[];
    final args = <Object?>[];
    final query = search?.trim() ?? '';
    if (query.isNotEmpty) {
      clauses.add('LOWER(n.body) LIKE ?');
      args.add('%${query.toLowerCase()}%');
    }
    if (month != null) {
      final start = DateTime(month.year, month.month).toUtc().toIso8601String();
      final end = DateTime(month.year, month.month + 1).toUtc().toIso8601String();
      clauses.add('s.started_at >= ? AND s.started_at < ?');
      args..add(start)..add(end);
    }
    if (sessionId != null) {
      clauses.add('n.session_id = ?');
      args.add(sessionId);
    }
    final rows = await db.rawQuery("""
      SELECT n.id, n.session_id, n.body, n.created_at, n.updated_at,
             s.started_at AS session_started_at
      FROM sleep_notes n
      INNER JOIN sleep_sessions s ON s.id = n.session_id
      ${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}'}
      ORDER BY s.started_at DESC, n.created_at DESC
    """, args);
    return rows.map(SleepNote.fromMap).toList();
  }

  Future<void> addNote(String sessionId, String text) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError('Текст заметки не может быть пустым.');
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final session = await txn.query('sleep_sessions', columns: ['id'],
          where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (session.isEmpty) throw StateError('Ночная сессия не найдена.');
      await txn.insert('sleep_notes', {
        'id': _uuid.v4(), 'session_id': sessionId, 'body': body,
        'created_at': now, 'updated_at': now,
      });
      await txn.update('sleep_sessions', {'updated_at': now},
          where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  Future<void> editNote(String noteId, String text) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError('Текст заметки не может быть пустым.');
    final db = await database;
    final count = await db.update('sleep_notes', {
      'body': body, 'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ?', whereArgs: [noteId]);
    if (count == 0) throw StateError('Заметка не найдена.');
  }

  Future<void> deleteNote(String noteId) async {
    final db = await database;
    await db.delete('sleep_notes', where: 'id = ?', whereArgs: [noteId]);
  }

  Future<void> updateNote(String id, String note) async {
    final db = await database;
    await db.update(
      'sleep_sessions',
      {
        'note': note.trim().isEmpty ? null : note.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
