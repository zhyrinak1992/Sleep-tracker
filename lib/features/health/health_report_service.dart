import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';

enum HealthReportKind { week, month, year }

class HealthReportSnapshot {
  const HealthReportSnapshot(this.data);

  final Map<String, Object?> data;

  factory HealthReportSnapshot.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('Некорректный физиологический отчёт.');
    final data = Map<String, Object?>.from(decoded);
    if (data['id'] is! String ||
        data['kind'] is! String ||
        data['start'] is! String ||
        data['endExclusive'] is! String ||
        data['metrics'] is! List) {
      throw const FormatException('В физиологическом отчёте отсутствуют обязательные поля.');
    }
    return HealthReportSnapshot(data);
  }

  String get id => data['id'] as String;
  String get kind => data['kind'] as String;
  DateTime get start => DateTime.parse(data['start'] as String);
  DateTime get endExclusive => DateTime.parse(data['endExclusive'] as String);
  DateTime get endInclusive => DateTime(endExclusive.year, endExclusive.month, endExclusive.day - 1);
  int get nights => data['nights'] as int? ?? 0;
  List<Map<String, Object?>> get metrics => (data['metrics'] as List)
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList();

  String get title {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return switch (kind) {
      'week' => 'Физиологический отчёт — неделя с ${start.day} ${months[start.month - 1]}',
      'month' => 'Физиологический отчёт — ${months[start.month - 1]} ${start.year}',
      'year' => 'Физиологический отчёт — ${start.year}',
      _ => 'Физиологический отчёт',
    };
  }
}

class HealthReportService {
  HealthReportService(this.database);

  static const storagePrefix = 'sleep_tracker_health_report_v1_';
  final SleepDatabase database;

  /// Calendar-date arithmetic stays at local midnight across DST transitions.
  static DateTime calendarDayAfter(DateTime value) =>
      DateTime(value.year, value.month, value.day + 1);

  static DateTime shiftCalendarDays(DateTime value, int days) =>
      DateTime(value.year, value.month, value.day + days);

  static DateTime lastDaysStart(DateTime now, int days) {
    if (days < 1) throw ArgumentError.value(days, 'days', 'Must be positive.');
    return DateTime(now.year, now.month, now.day - (days - 1));
  }

  static int inclusiveCalendarDays(DateTime start, DateTime end) {
    final first = DateTime.utc(start.year, start.month, start.day);
    final last = DateTime.utc(end.year, end.month, end.day);
    return last.difference(first).inDays + 1;
  }

  Future<List<HealthReportSnapshot>> generateClosedReports({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final sessions = (await database.getSessions(limit: null))
        .where((session) => session.endedAt != null && session.deletedAt == null)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (sessions.isEmpty) return loadArchive();

    final sessionsById = {for (final session in sessions) session.id: session};
    final allRows = await database.getAllMetrics();
    final rowsBySession = <String, List<Map<String, Object?>>>{};
    for (final row in allRows) {
      final sessionId = row['session_id'];
      final value = row['value'];
      final measuredAt = DateTime.tryParse(row['measured_at'] as String? ?? '');
      if (sessionId is! String ||
          !sessionsById.containsKey(sessionId) ||
          value is! num ||
          !value.toDouble().isFinite ||
          measuredAt == null) {
        continue;
      }
      rowsBySession.putIfAbsent(sessionId, () => []).add(row);
    }
    final sessionsWithMetrics = sessions.where((s) => rowsBySession.containsKey(s.id)).toList();
    if (sessionsWithMetrics.isEmpty) return loadArchive();

    for (final kind in HealthReportKind.values) {
      var cursor = _periodStart(sessionsWithMetrics.first.startedAt, kind);
      final lastClosedStart = _previousPeriodStart(_periodStart(currentTime, kind), kind);
      while (!cursor.isAfter(lastClosedStart)) {
        final end = _nextPeriodStart(cursor, kind);
        final periodSessions = sessionsWithMetrics.where((s) =>
          !s.startedAt.isBefore(cursor) && s.startedAt.isBefore(end)).toList();
        final periodRows = _rowsForSessions(periodSessions, rowsBySession);
        if (periodRows.isNotEmpty) {
          final previousStart = _previousPeriodStart(cursor, kind);
          final previousSessions = sessionsWithMetrics.where((s) =>
            !s.startedAt.isBefore(previousStart) && s.startedAt.isBefore(cursor)).toList();
          final previousRows = _rowsForSessions(previousSessions, rowsBySession);
          final snapshot = _buildSnapshot(
            kind: kind,
            start: cursor,
            end: end,
            sessions: periodSessions,
            rows: periodRows,
            previousStart: previousStart,
            previousEnd: cursor,
            previousSessions: previousSessions,
            previousRows: previousRows,
            rowsBySession: rowsBySession,
            sessionsById: sessionsById,
            createdAt: currentTime,
          );
          await database.setAppMetadata(
            '$storagePrefix${snapshot['id']}',
            jsonEncode(snapshot),
          );
        }
        cursor = end;
      }
    }
    return loadArchive();
  }

  Future<List<HealthReportSnapshot>> loadArchive() async {
    final stored = await database.getAppMetadataByPrefix(storagePrefix);
    final reports = <HealthReportSnapshot>[];
    for (final raw in stored.values) {
      try {
        reports.add(HealthReportSnapshot.decode(raw));
      } on FormatException {
        // Preserve a damaged saved snapshot; do not overwrite it here.
      }
    }
    reports.sort((a, b) => b.start.compareTo(a.start));
    return reports;
  }

  static List<Map<String, Object?>> summarizeMetrics({
    required List<Map<String, Object?>> rows,
    required Map<String, SleepSession> sessionsById,
  }) {
    final grouped = <(String, String), Map<String, List<Map<String, Object?>>>>{};
    for (final row in rows) {
      final sessionId = row['session_id'];
      final type = row['metric_type'];
      final unit = row['unit'];
      final value = row['value'];
      if (sessionId is! String ||
          !sessionsById.containsKey(sessionId) ||
          type is! String ||
          type.isEmpty ||
          unit is! String ||
          value is! num ||
          !value.toDouble().isFinite) {
        continue;
      }
      grouped.putIfAbsent((type, unit), () => {})
          .putIfAbsent(sessionId, () => [])
          .add(row);
    }

    final result = <Map<String, Object?>>[];
    for (final entry in grouped.entries) {
      final perNight = <Map<String, Object?>>[];
      final allNightAverages = <double>[];
      final sourceNames = <String>{};
      var measurementCount = 0;
      final nights = entry.value.keys.toList()
        ..sort((a, b) => sessionsById[a]!.startedAt.compareTo(sessionsById[b]!.startedAt));
      for (final sessionId in nights) {
        final samples = entry.value[sessionId]!;
        final values = samples.map((row) => (row['value'] as num).toDouble()).toList();
        final average = values.reduce((a, b) => a + b) / values.length;
        allNightAverages.add(average);
        measurementCount += values.length;
        final sources = samples
            .map((row) => row['source'])
            .whereType<String>()
            .where((source) => source.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        sourceNames.addAll(sources);
        perNight.add({
          'sessionId': sessionId,
          'date': sessionsById[sessionId]!.startedAt.toIso8601String(),
          'average': average,
          'minimum': values.reduce(math.min),
          'maximum': values.reduce(math.max),
          'measurements': values.length,
          'sources': sources,
        });
      }
      final sorted = [...allNightAverages]..sort();
      final median = sorted.isEmpty
          ? null
          : sorted.length.isOdd
              ? sorted[sorted.length ~/ 2]
              : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
      result.add({
        'type': entry.key.$1,
        'unit': entry.key.$2,
        'average': allNightAverages.isEmpty
            ? null
            : allNightAverages.reduce((a, b) => a + b) / allNightAverages.length,
        'median': median,
        'minimum': sorted.isEmpty ? null : sorted.first,
        'maximum': sorted.isEmpty ? null : sorted.last,
        'nightCount': perNight.length,
        'measurementCount': measurementCount,
        'sources': sourceNames.toList()..sort(),
        'nights': perNight,
      });
    }
    result.sort((a, b) => (a['type'] as String).compareTo(b['type'] as String));
    return result;
  }

  Map<String, Object?> _buildSnapshot({
    required HealthReportKind kind,
    required DateTime start,
    required DateTime end,
    required List<SleepSession> sessions,
    required List<Map<String, Object?>> rows,
    required DateTime previousStart,
    required DateTime previousEnd,
    required List<SleepSession> previousSessions,
    required List<Map<String, Object?>> previousRows,
    required Map<String, List<Map<String, Object?>>> rowsBySession,
    required Map<String, SleepSession> sessionsById,
    required DateTime createdAt,
  }) {
    final metrics = summarizeMetrics(rows: rows, sessionsById: sessionsById);
    final previousMetrics = summarizeMetrics(rows: previousRows, sessionsById: sessionsById);
    final trendPoints = _trendIntervals(kind, start, end).map((interval) {
      final pointSessions = sessions.where((s) =>
        !s.startedAt.isBefore(interval.$1) && s.startedAt.isBefore(interval.$2)).toList();
      final pointRows = _rowsForSessions(pointSessions, rowsBySession);
      return <String, Object?>{
        'label': interval.$3,
        'start': interval.$1.toIso8601String(),
        'endExclusive': interval.$2.toIso8601String(),
        'nights': pointSessions.length,
        'metrics': summarizeMetrics(rows: pointRows, sessionsById: sessionsById),
      };
    }).toList();

    return {
      'schemaVersion': 1,
      'id': '${kind.name}_${_dateKey(start)}',
      'kind': kind.name,
      'start': start.toIso8601String(),
      'endExclusive': end.toIso8601String(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'nights': sessions.length,
      'metrics': metrics,
      'previous': {
        'start': previousStart.toIso8601String(),
        'endExclusive': previousEnd.toIso8601String(),
        'nights': previousSessions.length,
        'metrics': previousMetrics,
      },
      'trendPoints': trendPoints,
      'methodologyNotes': [
        'Среднее рассчитывается в два этапа: сначала среднее всех измерений внутри одной ночи, затем среднее ночных значений. Ночи с большим количеством измерений не получают больший вес.',
        'Разные единицы измерения и источники не объединяются. Отсутствующие измерения не заменяются нулями, пропуски не интерполируются.',
        'Оценки восстановления и физиологической нагрузки не рассчитываются: методика, веса, личный базовый уровень и пороги требуют отдельного согласования.',
        'Отчёт описывает доступные физиологические измерения и не является медицинским заключением.',
      ],
    };
  }

  static List<Map<String, Object?>> _rowsForSessions(
    List<SleepSession> sessions,
    Map<String, List<Map<String, Object?>>> rowsBySession,
  ) => [
    for (final session in sessions)
      ...?rowsBySession[session.id],
  ];

  @visibleForTesting
  static DateTime nextPeriodStartForTesting(DateTime value, HealthReportKind kind) =>
      _nextPeriodStart(value, kind);

  @visibleForTesting
  static DateTime previousPeriodStartForTesting(DateTime value, HealthReportKind kind) =>
      _previousPeriodStart(value, kind);

  @visibleForTesting
  static List<(DateTime, DateTime, String)> trendIntervalsForTesting(
    HealthReportKind kind, DateTime start, DateTime end,
  ) => _trendIntervals(kind, start, end);

  static DateTime _periodStart(DateTime value, HealthReportKind kind) => switch (kind) {
    HealthReportKind.week => DateTime(value.year, value.month, value.day - (value.weekday - 1)),
    HealthReportKind.month => DateTime(value.year, value.month),
    HealthReportKind.year => DateTime(value.year),
  };

  static DateTime _nextPeriodStart(DateTime value, HealthReportKind kind) => switch (kind) {
    HealthReportKind.week => DateTime(value.year, value.month, value.day + 7),
    HealthReportKind.month => DateTime(value.year, value.month + 1),
    HealthReportKind.year => DateTime(value.year + 1),
  };

  static DateTime _previousPeriodStart(DateTime value, HealthReportKind kind) => switch (kind) {
    HealthReportKind.week => DateTime(value.year, value.month, value.day - 7),
    HealthReportKind.month => DateTime(value.year, value.month - 1),
    HealthReportKind.year => DateTime(value.year - 1),
  };

  static List<(DateTime, DateTime, String)> _trendIntervals(
    HealthReportKind kind,
    DateTime start,
    DateTime end,
  ) {
    final intervals = <(DateTime, DateTime, String)>[];
    if (kind == HealthReportKind.week) {
      for (var i = 0; i < 7; i++) {
        final from = DateTime(start.year, start.month, start.day + i);
        final to = DateTime(from.year, from.month, from.day + 1);
        intervals.add((from, to, '${from.day.toString().padLeft(2, '0')}.${from.month.toString().padLeft(2, '0')}'));
      }
    } else if (kind == HealthReportKind.month) {
      var from = start;
      var index = 1;
      while (from.isBefore(end)) {
        final toCandidate = DateTime(from.year, from.month, from.day + 7);
        final to = toCandidate.isBefore(end) ? toCandidate : end;
        intervals.add((from, to, 'Неделя $index'));
        from = to;
        index++;
      }
    } else {
      for (var month = 1; month <= 12; month++) {
        final from = DateTime(start.year, month);
        final to = DateTime(start.year, month + 1);
        intervals.add((from, to, '$month месяц'));
      }
    }
    return intervals;
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
