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
      version: 4,
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
      },
    );
    return _db!;
  }


  /// Экспортирует все существующие таблицы приложения в переносимую структуру.
  Future<Map<String, Object?>> exportSnapshot() async {
    final db = await database;
    return {
      'schemaVersion': 4,
      'sleep_sessions': await db.query('sleep_sessions', orderBy: 'started_at ASC'),
      'sleep_session_tags': await db.query('sleep_session_tags', orderBy: 'session_id ASC, tag_key ASC'),
      'sleep_notes': await db.query('sleep_notes', orderBy: 'created_at ASC'),
      'app_metadata': await db.query('app_metadata', orderBy: 'key ASC'),
      'sleep_stages': await db.query('sleep_stages', orderBy: 'started_at ASC'),
      'sleep_metrics': await db.query('sleep_metrics', orderBy: 'measured_at ASC'),
      'audio_events': await db.query('audio_events', orderBy: 'captured_at ASC'),
      'morning_reports': await db.query('morning_reports', orderBy: 'report_date ASC'),
    };
  }

  /// Полное восстановление с проверкой структуры и атомарной заменой данных.
  /// При любой ошибке SQLite откатывает транзакцию и оставляет исходную базу.
  Future<void> restoreSnapshot(Map<String, dynamic> snapshot, {bool merge = false}) async {
    if (snapshot['schemaVersion'] != 3 && snapshot['schemaVersion'] != 4) {
      throw const FormatException('Версия структуры резервной копии не поддерживается.');
    }
    const tables = ['sleep_sessions', 'sleep_session_tags', 'sleep_notes', 'app_metadata', 'sleep_stages', 'sleep_metrics', 'audio_events', 'morning_reports'];
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final value = snapshot[table];
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
    for (final table in ['sleep_session_tags', 'sleep_notes', 'sleep_stages', 'sleep_metrics', 'audio_events', 'morning_reports']) {
      for (final row in rowsByTable[table]!) {
        if (row['session_id'] != null && (row['session_id'] is! String || !sessionIds.contains(row['session_id']))) {
          throw FormatException('В разделе $table есть ссылка на отсутствующую ночь.');
        }
      }
    }

    final db = await database;
    await db.transaction((txn) async {
      if (!merge) {
        await txn.delete('sleep_notes');
        await txn.delete('sleep_session_tags');
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
      for (final table in ['sleep_stages', 'sleep_metrics', 'audio_events']) {
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
  Future<bool> insertHealthSession({
    required String id,
    required DateTime startedAt,
    required DateTime endedAt,
    required String sourceName,
  }) async {
    if (!endedAt.isAfter(startedAt)) return false;
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final inserted = await db.insert('sleep_sessions', {
      'id': id,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'source': 'apple_health:$sourceName',
      'note': null,
      'morning_rating': null,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return inserted > 0;
  }


  Future<void> _createV4Tables(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS sleep_stages (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, stage TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, source TEXT NOT NULL, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE IF NOT EXISTS sleep_metrics (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, metric_type TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL, measured_at TEXT NOT NULL, source TEXT NOT NULL, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE)');
    await db.execute("CREATE TABLE IF NOT EXISTS audio_events (id TEXT PRIMARY KEY, session_id TEXT, file_path TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'unknown', confidence REAL, captured_at TEXT NOT NULL, expires_at TEXT NOT NULL, duration_ms INTEGER NOT NULL, user_corrected INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE SET NULL)");
    await db.execute('CREATE TABLE IF NOT EXISTS morning_reports (id TEXT PRIMARY KEY, session_id TEXT NOT NULL UNIQUE, report_date TEXT NOT NULL, wellbeing INTEGER, sleep_quality INTEGER, answers_json TEXT, created_at TEXT NOT NULL, FOREIGN KEY (session_id) REFERENCES sleep_sessions(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stages_session ON sleep_stages(session_id, started_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_metrics_session ON sleep_metrics(session_id, measured_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audio_expiry ON audio_events(expires_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reports_date ON morning_reports(report_date)');
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
  Future<List<Map<String, Object?>>> getMetrics(String sessionId) async => (await database).query('sleep_metrics', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'measured_at');
  Future<List<Map<String, Object?>>> getAudioEvents({String? sessionId}) async { final db = await database; return db.query('audio_events', where: sessionId == null ? null : 'session_id = ?', whereArgs: sessionId == null ? null : [sessionId], orderBy: 'captured_at DESC'); }
  Future<void> saveAudioEvent({required String id, required String? sessionId, required String filePath, required String category, required DateTime capturedAt, required int durationMs}) async {
    await (await database).insert('audio_events', {'id': id, 'session_id': sessionId, 'file_path': filePath, 'category': category, 'confidence': null, 'captured_at': capturedAt.toUtc().toIso8601String(), 'expires_at': capturedAt.toUtc().add(const Duration(days: 7)).toIso8601String(), 'duration_ms': durationMs, 'user_corrected': 0});
  }
  Future<void> deleteAudioEvent(String id) async { final db = await database; final rows = await db.query('audio_events', where: 'id = ?', whereArgs: [id]); if (rows.isEmpty) return; try { await File(rows.first['file_path']! as String).delete(); } catch (_) {} await db.delete('audio_events', where: 'id = ?', whereArgs: [id]); }
  Future<void> updateAudioClassification(String id, String category, double confidence) async => (await database).update('audio_events', {'category': category, 'confidence': confidence, 'user_corrected': 0}, where: 'id = ?', whereArgs: [id]);
  Future<void> updateAudioCategory(String id, String category) async => (await database).update('audio_events', {'category': category, 'user_corrected': 1}, where: 'id = ?', whereArgs: [id]);
  Future<int> deleteExpiredAudioEvents(DateTime now) async {
    final db = await database; final expired = await db.query('audio_events', where: 'expires_at <= ?', whereArgs: [now.toUtc().toIso8601String()]);
    for (final row in expired) { try { await File(row['file_path']! as String).delete(); } catch (_) {} }
    return db.delete('audio_events', where: 'expires_at <= ?', whereArgs: [now.toUtc().toIso8601String()]);
  }
  Future<Map<String, Object?>?> getMorningReport(String sessionId) async { final rows = await (await database).query('morning_reports', where: 'session_id = ?', whereArgs: [sessionId], limit: 1); return rows.isEmpty ? null : rows.first; }
  Future<void> saveMorningReport({required String sessionId, required int wellbeing, required int quality, required String answersJson}) async {
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
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SleepSession.fromMap(rows.first);
  }

  Future<List<SleepSession>> getSessions({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'sleep_sessions',
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
    await db.insert('sleep_sessions', session.toMap());
    return session;
  }

  Future<SleepSession> finishSession(String id) async {
    final db = await database;
    final now = DateTime.now();
    final count = await db.update(
      'sleep_sessions',
      {
        'ended_at': now.toUtc().toIso8601String(),
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

  Future<Map<String, int>> getTagUsageCounts() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT tag_key, COUNT(*) AS total FROM sleep_session_tags GROUP BY tag_key ORDER BY total DESC, tag_key ASC');
    return {for (final row in rows) row['tag_key']! as String: row['total']! as int};
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
