import 'dart:convert';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_note.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_score.dart';

enum PeriodicReportKind { week, month, year }

class PeriodicReportSnapshot {
  const PeriodicReportSnapshot(this.data);
  final Map<String, Object?> data;
  String get id => data['id'] as String;
  String get kind => data['kind'] as String;
  DateTime get start => DateTime.parse(data['start'] as String);
  DateTime get endExclusive => DateTime.parse(data['endExclusive'] as String);
  int get nights => data['nights'] as int;
  double? get averageSleepMinutes => (data['averageSleepMinutes'] as num?)?.toDouble();
  int? get totalSleepMinutes => (data['totalSleepMinutes'] as num?)?.round();
  double? get averageTimeInBedMinutes => (data['averageTimeInBedMinutes'] as num?)?.toDouble();
  double? get averageEfficiency => (data['averageEfficiency'] as num?)?.toDouble();
  double? get averageAwakenings => (data['averageAwakenings'] as num?)?.toDouble();
  double? get averageQuality => (data['averageQuality'] as num?)?.toDouble();
  double? get averageWellbeing => (data['averageWellbeing'] as num?)?.toDouble();

  static const _monthNames = [
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];
  static const _monthGenitive = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  static String monthName(int month) => _monthNames[month - 1];

  String get title {
    if (kind == 'week') {
      final last = endExclusive.subtract(const Duration(days: 1));
      return 'Неделя ' + start.day.toString() + ' ' + _monthGenitive[start.month - 1] +
        ' — ' + last.day.toString() + ' ' + _monthGenitive[last.month - 1] + ' ' + last.year.toString();
    }
    if (kind == 'month') return _monthNames[start.month - 1] + ' ' + start.year.toString();
    return 'Год ' + start.year.toString();
  }

  factory PeriodicReportSnapshot.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('Некорректный сохранённый отчёт.');
    return PeriodicReportSnapshot(Map<String, Object?>.from(decoded));
  }
}

class PeriodicReportService {
  PeriodicReportService(this.database);
  final SleepDatabase database;
  static const metadataPrefix = 'periodic_report_v4_';
  static const previousMetadataPrefix = 'periodic_report_v3_';
  static const olderMetadataPrefix = 'periodic_report_v2_';
  static const legacyMetadataPrefix = 'periodic_report_v1_';

  Future<List<PeriodicReportSnapshot>> generateClosedReports({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final sessions = await database.getSessions(limit: 10000);
    final completed = sessions.where((s) => s.endedAt != null && s.duration != null && s.duration!.inMinutes > 0).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (completed.isEmpty) return loadArchive();

    final stages = await database.getStagesForSessions(completed.map((s) => s.id).toList());
    final morning = await database.getMorningReportsForSessions(completed.map((s) => s.id).toList());
    final audio = await database.getAudioEvents();
    final notes = await database.getNotes();
    final scoreCache = <String, SleepScoreResult>{};

    for (final kind in PeriodicReportKind.values) {
      final first = _periodStart(completed.first.startedAt, kind);
      final lastClosed = _previousPeriodStart(_periodStart(current, kind), kind);
      var cursor = first;
      while (!cursor.isAfter(lastClosed)) {
        final end = _nextPeriodStart(cursor, kind);
        final id = _id(kind, cursor);
        final existing = await database.getAppMetadata(metadataPrefix + id);
        if (existing == null) {
          final selected = completed.where((s) => !s.startedAt.isBefore(cursor) && s.startedAt.isBefore(end)).toList();
          if (selected.isNotEmpty) {
            final previousStart = _previousPeriodStart(cursor, kind);
            final previous = completed.where((s) => !s.startedAt.isBefore(previousStart) && s.startedAt.isBefore(cursor)).toList();
            final snapshot = _buildSnapshot(
              kind: kind, start: cursor, end: end, sessions: selected,
              previousSessions: previous, stages: stages, morning: morning,
              audio: audio, notes: notes, allSessions: completed,
              scoreCache: scoreCache,
            );
            await database.setAppMetadata(metadataPrefix + id, jsonEncode(snapshot));
          }
        }
        cursor = end;
      }
    }
    return loadArchive();
  }

  Future<List<PeriodicReportSnapshot>> loadArchive() async {
    final legacy = await database.getAppMetadataByPrefix(legacyMetadataPrefix);
    final previous = await database.getAppMetadataByPrefix(previousMetadataPrefix);
    final older = await database.getAppMetadataByPrefix(olderMetadataPrefix);
    final current = await database.getAppMetadataByPrefix(metadataPrefix);
    final byId = <String, PeriodicReportSnapshot>{};
    for (final value in legacy.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    // New v4 snapshots win; older v1/v2/v3 snapshots remain readable and intact.
    for (final value in older.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    for (final value in previous.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    for (final value in current.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    final reports = byId.values.toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    return reports;
  }

  static Map<String, Object?> _buildSnapshot({
    required PeriodicReportKind kind, required DateTime start, required DateTime end,
    required List<SleepSession> sessions, required List<SleepSession> previousSessions,
    required Map<String, List<Map<String, Object?>>> stages,
    required Map<String, Map<String, Object?>> morning,
    required List<Map<String, Object?>> audio, required List<SleepNote> notes,
    required List<SleepSession> allSessions,
    required Map<String, SleepScoreResult> scoreCache,
  }) {
    Map<String, Object?> summarize(List<SleepSession> selected) {
      final metrics = selected.map((s) => SleepSessionMetrics.calculate(session: s, stages: stages[s.id] ?? const [])).toList();
      double? avg(Iterable<num> values) {
        final list = values.map((v) => v.toDouble()).where((v) => v.isFinite).toList();
        return list.isEmpty ? null : list.reduce((a, b) => a + b) / list.length;
      }
      final durations = <int>[];
      final timeInBed = <int>[];
      for (final metric in metrics) {
        final measuredSleep = metric.sleepDurationMinutes;
        if (measuredSleep != null && measuredSleep > 0) durations.add(measuredSleep);
        final measuredTimeInBed = metric.timeInBedMinutes;
        if (measuredTimeInBed != null && measuredTimeInBed > 0) timeInBed.add(measuredTimeInBed);
      }
      final nightlyScores = selected.map((session) =>
        scoreCache.putIfAbsent(session.id, () =>
          SleepScoreCalculator.calculateForSession(
            session: session,
            historySessions: allSessions,
            morningReports: morning,
            stagesBySession: stages,
          ),
        ),
      ).toList();
      final scoreValues = nightlyScores.map((item) => item.score).whereType<double>().toList();
      final scoreComponents = <String, Map<String, Object?>>{};
      for (final key in ['duration', 'efficiency', 'awakenings', 'subjectiveQuality']) {
        final componentValues = <double>[];
        String? label;
        double? weight;
        for (final score in nightlyScores) {
          for (final component in score.components.where((item) => item.key == key)) {
            label = component.label;
            weight = component.weight;
            if (component.score != null) componentValues.add(component.score!);
          }
        }
        scoreComponents[key] = {
          'label': label,
          'weight': weight,
          'average': avg(componentValues),
          'samples': componentValues.length,
        };
      }
      final efficiencies = metrics.map((m) => m.sleepEfficiencyPercent).whereType<double>().toList();
      final awakenings = <int>[];
      for (var i = 0; i < selected.length; i++) {
        if ((stages[selected[i].id] ?? const []).isNotEmpty && metrics[i].stageCoveragePercent != null) {
          awakenings.add(metrics[i].awakeningCount);
        }
      }
      final qualities = <num>[], wellbeing = <num>[];
      for (final session in selected) {
        final report = morning[session.id];
        if (report == null) continue;
        if (report['sleep_quality'] is num) qualities.add(report['sleep_quality'] as num);
        if (report['wellbeing'] is num) wellbeing.add(report['wellbeing'] as num);
      }
      return {
        'nights': selected.length,
        'averageSleepMinutes': avg(durations), 'totalSleepMinutes': durations.isEmpty ? null : durations.fold<int>(0, (sum, value) => sum + value), 'sleepDurationSamples': durations.length,
        'averageTimeInBedMinutes': avg(timeInBed), 'timeInBedSamples': timeInBed.length,
        'averageEfficiency': avg(efficiencies), 'efficiencySamples': efficiencies.length,
        'averageAwakenings': avg(awakenings), 'awakeningSamples': awakenings.length,
        'averageQuality': avg(qualities), 'qualitySamples': qualities.length,
        'averageWellbeing': avg(wellbeing), 'wellbeingSamples': wellbeing.length,
        'score': {
          'average': avg(scoreValues),
          'samples': scoreValues.length,
          'components': scoreComponents,
          'availableWeightAverage': avg(nightlyScores.map((item) => item.availableWeight)),
        },
      };
    }

    final current = summarize(sessions);
    final previous = summarize(previousSessions);
    final ids = sessions.map((s) => s.id).toSet();
    final events = audio.where((event) {
      final sessionId = event['session_id'];
      final captured = DateTime.tryParse(event['captured_at'] as String? ?? '');
      return sessionId is String && ids.contains(sessionId) && captured != null &&
        !captured.isBefore(start) && captured.isBefore(end);
    }).toList();
    final categories = <String, int>{};
    for (final event in events) {
      final category = event['category'] as String? ?? 'unknown';
      categories[category] = (categories[category] ?? 0) + 1;
    }

    final periodNotes = notes.where((note) => ids.contains(note.sessionId)).map((note) => <String, Object?>{
      'sessionStartedAt': note.sessionStartedAt.toIso8601String(),
      'text': note.text,
    }).toList();

    final data = <String, Object?>{
      'schemaVersion': 4, 'id': _id(kind, start), 'kind': kind.name,
      'start': start.toIso8601String(), 'endExclusive': end.toIso8601String(),
      'generatedAt': DateTime.now().toIso8601String(),
      ...current, 'audioEventCount': events.length, 'audioCategories': categories,
      'notes': periodNotes, 'noteCount': periodNotes.length,
      'previous': previous, 'score': current['score'],
    };

    List<Map<String, Object?>> weekdayPatterns(List<SleepSession> selected) {
      const names = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
      final patterns = <Map<String, Object?>>[];
      for (var weekday = 1; weekday <= 7; weekday++) {
        final values = <int>[];
        for (final session in selected.where((s) => s.startedAt.weekday == weekday)) {
          final metric = SleepSessionMetrics.calculate(
            session: session,
            stages: stages[session.id] ?? const [],
          );
          final value = metric.sleepDurationMinutes;
          if (value != null && value > 0) values.add(value);
        }
        if (values.length >= 3) {
          patterns.add({
            'weekday': weekday,
            'label': names[weekday - 1],
            'samples': values.length,
            'averageSleepMinutes': values.reduce((a, b) => a + b) / values.length,
          });
        }
      }
      return patterns;
    }

    if (kind == PeriodicReportKind.month) {
      final trend = <Map<String, Object?>>[];
      for (var bucket = 0; bucket < 5; bucket++) {
        final bucketStart = start.add(Duration(days: bucket * 7));
        if (!bucketStart.isBefore(end)) break;
        final candidateEnd = bucketStart.add(const Duration(days: 7));
        final bucketEnd = candidateEnd.isBefore(end) ? candidateEnd : end;
        final bucketSessions = sessions.where((s) =>
          !s.startedAt.isBefore(bucketStart) && s.startedAt.isBefore(bucketEnd)).toList();
        if (bucketSessions.isNotEmpty) {
          trend.add({
            'bucket': bucket + 1,
            'dayFrom': bucketStart.day,
            'dayTo': bucketEnd.subtract(const Duration(days: 1)).day,
            ...summarize(bucketSessions),
          });
        }
      }
      data['weeklyTrend'] = trend;
      data['weekdayPatterns'] = weekdayPatterns(sessions);
    }

    if (kind == PeriodicReportKind.year) {
      final months = <Map<String, Object?>>[];
      for (var month = 1; month <= 12; month++) {
        final monthStart = DateTime(start.year, month);
        final monthEnd = DateTime(start.year, month + 1);
        final monthSessions = allSessions.where((s) => !s.startedAt.isBefore(monthStart) && s.startedAt.isBefore(monthEnd)).toList();
        if (monthSessions.isNotEmpty) months.add({'month': month, ...summarize(monthSessions)});
      }
      data['months'] = months;
      data['weekdayPatterns'] = weekdayPatterns(sessions);
      const minimumMonthNightsForRanking = 3;
      final measurable = months.where((m) => m['averageSleepMinutes'] is num &&
        (m['nights'] as int? ?? 0) >= minimumMonthNightsForRanking).toList();
      if (measurable.isNotEmpty) {
        final sorted = measurable.toList()..sort((a, b) =>
          (a['averageSleepMinutes'] as num).compareTo(b['averageSleepMinutes'] as num));
        data['shortestAverageMonth'] = sorted.first['month'];
        data['longestAverageMonth'] = sorted.last['month'];
        data['monthRankingCriterion'] = 'Средняя продолжительность сна; не менее 3 завершённых ночей в месяце.';
        data['monthRankingMinimumNights'] = minimumMonthNightsForRanking;
      }
    }
    return PeriodicReportSnapshot(data).data;
  }

  static DateTime _periodStart(DateTime value, PeriodicReportKind kind) {
    if (kind == PeriodicReportKind.week) {
      final day = DateTime(value.year, value.month, value.day);
      return day.subtract(Duration(days: day.weekday - DateTime.monday));
    }
    if (kind == PeriodicReportKind.month) return DateTime(value.year, value.month);
    return DateTime(value.year);
  }
  static DateTime _nextPeriodStart(DateTime value, PeriodicReportKind kind) {
    if (kind == PeriodicReportKind.week) return value.add(const Duration(days: 7));
    if (kind == PeriodicReportKind.month) return DateTime(value.year, value.month + 1);
    return DateTime(value.year + 1);
  }
  static DateTime _previousPeriodStart(DateTime value, PeriodicReportKind kind) {
    if (kind == PeriodicReportKind.week) return value.subtract(const Duration(days: 7));
    if (kind == PeriodicReportKind.month) return DateTime(value.year, value.month - 1);
    return DateTime(value.year - 1);
  }
  static String _id(PeriodicReportKind kind, DateTime start) =>
    kind.name + '_' + start.year.toString().padLeft(4, '0') + '-' + start.month.toString().padLeft(2, '0') + '-' + start.day.toString().padLeft(2, '0');
}
