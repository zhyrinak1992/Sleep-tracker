import 'dart:convert';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_note.dart';
import '../../models/sleep_tag.dart';
import '../diary/sleep_session_metrics.dart';
import 'sleep_score.dart';
import 'periodic_tag_pattern_analyzer.dart';
import 'sleep_regularity_analysis.dart';

enum PeriodicReportKind { week, month, quarter, halfYear, year }

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
    if (kind == 'quarter') return (((start.month - 1) ~/ 3) + 1).toString() + ' квартал ' + start.year.toString();
    if (kind == 'halfYear') return (start.month <= 6 ? 'I' : 'II') + ' полугодие ' + start.year.toString();
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
  static const metadataPrefix = 'periodic_report_v9_';
  static const previousMetadataPrefix = 'periodic_report_v8_';
  static const olderMetadataPrefix = 'periodic_report_v7_';
  static const olderMetadataPrefixV2 = 'periodic_report_v6_';
  static const olderMetadataPrefixV3 = 'periodic_report_v5_';
  static const olderMetadataPrefixV4 = 'periodic_report_v4_';
  static const olderMetadataPrefixV5 = 'periodic_report_v3_';
  static const olderMetadataPrefixV6 = 'periodic_report_v2_';
  static const legacyMetadataPrefix = 'periodic_report_v1_';

  static Future<List<PeriodicReportSnapshot>>? _generationInFlight;

  Future<List<PeriodicReportSnapshot>> generateClosedReports({DateTime? now}) {
    final inFlight = _generationInFlight;
    if (inFlight != null) return inFlight;
    final future = _generateClosedReports(now: now);
    _generationInFlight = future;
    return future.whenComplete(() {
      if (identical(_generationInFlight, future)) {
        _generationInFlight = null;
      }
    });
  }

  Future<List<PeriodicReportSnapshot>> _generateClosedReports({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final checkedDate = '${current.year.toString().padLeft(4, '0')}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
    const checkedDateKey = 'periodic_report_last_checked_local_date';
    if (await database.getAppMetadata(checkedDateKey) == checkedDate) {
      return loadArchive();
    }
    final sessions = await database.getSessions(limit: null);
    final completed = sessions.where((s) => s.endedAt != null && s.duration != null && s.duration!.inMinutes > 0).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (completed.isEmpty) return loadArchive();

    final stages = await database.getStagesForSessions(completed.map((s) => s.id).toList());
    final morning = await database.getMorningReportsForSessions(completed.map((s) => s.id).toList());
    final audio = await database.getAudioEvents();
    final notes = await database.getNotes();
    final tagsBySession = await database.getTagsForSessions(completed.map((s) => s.id).toList());
    final allSleepMetrics = await database.getAllMetrics();
    final allClimateSamples = await database.getClimateSamples();
    final tagLabels = <String, String>{
      for (final tag in SleepTag.catalog) tag.key: tag.label,
    };
    try {
      final customTags = await CustomSleepTagStore(
        database.getAppMetadata,
        database.setAppMetadata,
      ).load();
      for (final tag in customTags) {
        tagLabels[tag.key] = tag.label;
      }
    } catch (_) {
      // Corrupt optional custom-tag metadata must not prevent report generation.
    }
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
              allSleepMetrics: allSleepMetrics, allClimateSamples: allClimateSamples,
              scoreCache: scoreCache, tagsBySession: tagsBySession, tagLabels: tagLabels,
            );
            await database.setAppMetadata(metadataPrefix + id, jsonEncode(snapshot));
          }
        }
        cursor = end;
      }
    }
    await database.setAppMetadata(checkedDateKey, checkedDate);
    return loadArchive();
  }

  Future<List<PeriodicReportSnapshot>> loadArchive() async {
    final legacy = await database.getAppMetadataByPrefix(legacyMetadataPrefix);
    final previous = await database.getAppMetadataByPrefix(previousMetadataPrefix);
    final older = await database.getAppMetadataByPrefix(olderMetadataPrefix);
    final olderV2 = await database.getAppMetadataByPrefix(olderMetadataPrefixV2);
    final olderV3 = await database.getAppMetadataByPrefix(olderMetadataPrefixV3);
    final olderV4 = await database.getAppMetadataByPrefix(olderMetadataPrefixV4);
    final olderV5 = await database.getAppMetadataByPrefix(olderMetadataPrefixV5);
    final olderV6 = await database.getAppMetadataByPrefix(olderMetadataPrefixV6);
    final current = await database.getAppMetadataByPrefix(metadataPrefix);
    final byId = <String, PeriodicReportSnapshot>{};
    for (final value in legacy.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    // New v9 snapshots win; older v1-v8 snapshots remain readable and intact.
    for (final value in olderV6.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    for (final value in olderV5.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    for (final value in olderV4.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    for (final value in olderV3.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
    for (final value in olderV2.values) {
      try {
        final report = PeriodicReportSnapshot.decode(value);
        byId[report.id] = report;
      } catch (_) {}
    }
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
    required List<Map<String, Object?>> allSleepMetrics,
    required List<Map<String, Object?>> allClimateSamples,
    required Map<String, SleepScoreResult> scoreCache,
    required Map<String, Set<String>> tagsBySession,
    required Map<String, String> tagLabels,
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

    List<Map<String, Object?>> tagPatternsFor(List<SleepSession> selected) {
      final durations = <String, double>{};
      final scores = <String, double>{};
      final awakeningsBySession = <String, double>{};
      final efficiencyBySession = <String, double>{};
      final latencyBySession = <String, double>{};
      final qualityBySession = <String, double>{};
      final wellbeingBySession = <String, double>{};
      final bedtimeBySession = <String, double>{};
      final wakeTimeBySession = <String, double>{};
      final physiology = <String, Map<String, List<double>>>{
        'heartRate': <String, List<double>>{},
        'respiratoryRate': <String, List<double>>{},
        'bloodOxygen': <String, List<double>>{},
        'hrv': <String, List<double>>{},
      };
      final climate = <String, Map<String, List<double>>>{
        'roomTemperature': <String, List<double>>{},
        'roomHumidity': <String, List<double>>{},
      };
      final selectedIds = selected.map((session) => session.id).toSet();
      for (final session in selected) {
        final metric = SleepSessionMetrics.calculate(
          session: session,
          stages: stages[session.id] ?? const [],
        );
        final duration = metric.sleepDurationMinutes;
        if (duration != null && duration > 0) durations[session.id] = duration.toDouble();
        final efficiency = metric.sleepEfficiencyPercent;
        if (efficiency != null && efficiency.isFinite) efficiencyBySession[session.id] = efficiency;
        final latency = metric.sleepLatencyMinutes;
        if (latency != null && latency >= 0) latencyBySession[session.id] = latency.toDouble();
        final report = morning[session.id];
        if (report?['sleep_quality'] is num) qualityBySession[session.id] = (report!['sleep_quality'] as num).toDouble();
        if (report?['wellbeing'] is num) wellbeingBySession[session.id] = (report!['wellbeing'] as num).toDouble();
        final score = scoreCache.putIfAbsent(session.id, () =>
          SleepScoreCalculator.calculateForSession(
            session: session,
            historySessions: allSessions,
            morningReports: morning,
            stagesBySession: stages,
          ),
        ).score;
        if (score != null && score.isFinite) scores[session.id] = score;
        final sessionStages = stages[session.id] ?? const <Map<String, Object?>>[];
        if (sessionStages.isNotEmpty && metric.stageCoveragePercent != null) {
          awakeningsBySession[session.id] = metric.awakeningCount.toDouble();
        }
      }
      final regularity = SleepRegularityAnalysis.calculate(selected);
      for (final night in regularity.nights) {
        bedtimeBySession[night.session.id] = night.bedtimeMinute.toDouble();
        wakeTimeBySession[night.session.id] = night.wakeMinute.toDouble();
      }
      final metricTypeToPattern = <String, String>{
        'Пульс': 'heartRate',
        'Частота дыхания': 'respiratoryRate',
        'Насыщение кислородом': 'bloodOxygen',
        'Вариабельность пульса SDNN': 'hrv',
      };
      for (final row in allSleepMetrics) {
        final sessionId = row['session_id'];
        final patternKey = metricTypeToPattern[row['metric_type']];
        final value = row['value'];
        if (sessionId is String && selectedIds.contains(sessionId) &&
            patternKey != null && value is num && value.toDouble().isFinite) {
          physiology[patternKey]!.putIfAbsent(sessionId, () => <double>[]).add(value.toDouble());
        }
      }
      for (final row in allClimateSamples) {
        final sessionId = row['session_id'];
        final metricType = row['metric_type'];
        final value = row['value'];
        final patternKey = metricType == 'temperature' ? 'roomTemperature'
          : metricType == 'humidity' ? 'roomHumidity' : null;
        if (sessionId is String && selectedIds.contains(sessionId) &&
            patternKey != null && value is num && value.toDouble().isFinite) {
          climate[patternKey]!.putIfAbsent(sessionId, () => <double>[]).add(value.toDouble());
        }
      }
      Map<String, double> perNightAverage(Map<String, List<double>> values) => {
        for (final entry in values.entries)
          if (entry.value.isNotEmpty)
            entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
      };
      final additionalMetrics = <String, Map<String, double>>{};
      if (efficiencyBySession.isNotEmpty) additionalMetrics['efficiency'] = efficiencyBySession;
      if (latencyBySession.isNotEmpty) additionalMetrics['sleepLatency'] = latencyBySession;
      if (qualityBySession.isNotEmpty) additionalMetrics['subjectiveQuality'] = qualityBySession;
      if (wellbeingBySession.isNotEmpty) additionalMetrics['wellbeing'] = wellbeingBySession;
      if (bedtimeBySession.isNotEmpty) additionalMetrics['bedtime'] = bedtimeBySession;
      if (wakeTimeBySession.isNotEmpty) additionalMetrics['wakeTime'] = wakeTimeBySession;
      for (final entry in physiology.entries) {
        final values = perNightAverage(entry.value);
        if (values.isNotEmpty) additionalMetrics[entry.key] = values;
      }
      for (final entry in climate.entries) {
        final values = perNightAverage(entry.value);
        if (values.isNotEmpty) additionalMetrics[entry.key] = values;
      }
      return PeriodicTagPatternAnalyzer.analyze(
        sessions: selected,
        tagsBySession: tagsBySession,
        durationBySession: durations,
        scoreBySession: scores,
        awakeningsBySession: awakeningsBySession,
        additionalMetrics: additionalMetrics,
        circularMetricKeys: const {'bedtime', 'wakeTime'},
        tagLabels: tagLabels,
      );
    }

    final current = summarize(sessions);
    final previous = summarize(previousSessions);
    final currentTagPatterns = tagPatternsFor(sessions);
    final previousTagPatterns = tagPatternsFor(previousSessions);
    final rankedInsights = <Map<String, Object?>>[];
    const insightMetricLabels = <String, String>{
      'duration': 'Продолжительность сна',
      'score': 'Оценка сна',
      'awakenings': 'Пробуждения',
      'efficiency': 'Эффективность сна',
      'sleepLatency': 'Задержка засыпания',
      'subjectiveQuality': 'Субъективное качество',
      'wellbeing': 'Утреннее самочувствие',
      'bedtime': 'Время засыпания',
      'wakeTime': 'Время пробуждения',
      'heartRate': 'Пульс',
      'respiratoryRate': 'Частота дыхания',
      'bloodOxygen': 'Насыщение кислородом',
      'hrv': 'Вариабельность пульса SDNN',
      'roomTemperature': 'Температура датчика',
      'roomHumidity': 'Влажность датчика',
    };
    for (final rawPattern in currentTagPatterns) {
      final pattern = Map<String, Object?>.from(rawPattern);
      final tagKey = pattern['tagKey'];
      final currentMetrics = pattern['metrics'] is Map
        ? Map<String, Object?>.from(pattern['metrics'] as Map) : <String, Object?>{};
      final oldMatches = previousTagPatterns.where((item) => item['tagKey'] == tagKey).toList();
      final oldMetrics = oldMatches.isNotEmpty && oldMatches.first['metrics'] is Map
        ? Map<String, Object?>.from(oldMatches.first['metrics'] as Map) : <String, Object?>{};
      for (final entry in currentMetrics.entries) {
        if (entry.value is! Map || !insightMetricLabels.containsKey(entry.key)) continue;
        final metric = Map<String, Object?>.from(entry.value as Map);
        final difference = metric['difference'];
        if (metric['isSufficient'] != true || difference is! num || difference == 0) continue;
        final old = oldMetrics[entry.key] is Map
          ? Map<String, Object?>.from(oldMetrics[entry.key] as Map) : <String, Object?>{};
        final oldDifference = old['difference'];
        final repeated = old['isSufficient'] == true && oldDifference is num &&
          oldDifference != 0 && (oldDifference > 0) == (difference > 0);
        final withAverage = metric['withTagAverage'];
        final withoutAverage = metric['withoutTagAverage'];
        final baseline = withoutAverage is num ? withoutAverage.abs() : 0.0;
        final relativeDifference = baseline > 0
          ? difference.abs() / baseline * 100 : null;
        final withSamples = metric['withTagSamples'] as int? ?? 0;
        final withoutSamples = metric['withoutTagSamples'] as int? ?? 0;
        rankedInsights.add({
          'tagKey': tagKey,
          'tagLabel': pattern['label'] ?? tagKey,
          'metricKey': entry.key,
          'metricLabel': insightMetricLabels[entry.key],
          'withTagAverage': withAverage,
          'withoutTagAverage': withoutAverage,
          'difference': difference,
          'withTagSamples': withSamples,
          'withoutTagSamples': withoutSamples,
          'evidenceNights': withSamples < withoutSamples ? withSamples : withoutSamples,
          'relativeDifferencePercent': relativeDifference,
          'previousDifference': oldDifference,
          'repeatsPreviousPeriod': repeated,
          'withTagObservations': metric['withTagObservations'] ?? const [],
          'withoutTagObservations': metric['withoutTagObservations'] ?? const [],
        });
      }
    }
    rankedInsights.sort((a, b) {
      final repeatOrder = ((b['repeatsPreviousPeriod'] == true) ? 1 : 0)
        .compareTo((a['repeatsPreviousPeriod'] == true) ? 1 : 0);
      if (repeatOrder != 0) return repeatOrder;
      final evidenceOrder = (b['evidenceNights'] as int).compareTo(a['evidenceNights'] as int);
      if (evidenceOrder != 0) return evidenceOrder;
      final aMagnitude = (a['relativeDifferencePercent'] as num?)?.toDouble() ?? 0;
      final bMagnitude = (b['relativeDifferencePercent'] as num?)?.toDouble() ?? 0;
      return bMagnitude.compareTo(aMagnitude);
    });
    for (var i = 0; i < rankedInsights.length; i++) {
      rankedInsights[i]['rank'] = i + 1;
    }
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
      'schemaVersion': 9, 'id': _id(kind, start), 'kind': kind.name,
      'start': start.toIso8601String(), 'endExclusive': end.toIso8601String(),
      'generatedAt': DateTime.now().toIso8601String(),
      ...current, 'audioEventCount': events.length, 'audioCategories': categories,
      'notes': periodNotes, 'noteCount': periodNotes.length,
      'previous': previous, 'score': current['score'],
      'tagPatterns': {
        'current': currentTagPatterns,
        'previous': previousTagPatterns,
      },
      'rankedInsights': rankedInsights,
    };

    List<Map<String, Object?>> nightlyDetails(List<SleepSession> selected) {
      final details = <Map<String, Object?>>[];
      for (final session in selected) {
        final metric = SleepSessionMetrics.calculate(
          session: session,
          stages: stages[session.id] ?? const [],
        );
        final score = scoreCache.putIfAbsent(session.id, () =>
          SleepScoreCalculator.calculateForSession(
            session: session,
            historySessions: allSessions,
            morningReports: morning,
            stagesBySession: stages,
          ),
        ).score;
        final report = morning[session.id];
        details.add({
          'sessionId': session.id,
          'startedAt': session.startedAt.toIso8601String(),
          'sleepMinutes': metric.sleepDurationMinutes,
          'score': score,
          'efficiency': metric.sleepEfficiencyPercent,
          'quality': report?['sleep_quality'],
          'wellbeing': report?['wellbeing'],
          'awakenings': (stages[session.id] ?? const []).isNotEmpty &&
              metric.stageCoveragePercent != null ? metric.awakeningCount : null,
        });
      }
      details.sort((a, b) => (a['startedAt'] as String).compareTo(b['startedAt'] as String));
      return details;
    }

    List<Map<String, Object?>> weekdayTrend(List<SleepSession> selected) {
      const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
      final result = <Map<String, Object?>>[];
      for (var weekday = 1; weekday <= 7; weekday++) {
        final bucket = selected.where((s) => s.startedAt.weekday == weekday).toList();
        if (bucket.isEmpty) continue;
        final summary = summarize(bucket);
        result.add({
          'label': names[weekday - 1],
          'sleepMinutes': summary['averageSleepMinutes'],
          'samples': summary['sleepDurationSamples'],
          'nights': nightlyDetails(bucket),
        });
      }
      return result;
    }

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

    if (kind == PeriodicReportKind.week) {
      final days = <Map<String, Object?>>[];
      for (var day = 0; day < 7; day++) {
        final dayStart = start.add(Duration(days: day));
        final dayEnd = dayStart.add(const Duration(days: 1));
        final daySessions = sessions.where((s) =>
          !s.startedAt.isBefore(dayStart) && s.startedAt.isBefore(dayEnd)).toList();
        if (daySessions.isEmpty) continue;
        final summary = summarize(daySessions);
        days.add({
          'label': '${dayStart.day}.${dayStart.month.toString().padLeft(2, '0')}',
          'sleepMinutes': summary['averageSleepMinutes'],
          'samples': summary['sleepDurationSamples'],
          'nights': nightlyDetails(daySessions),
        });
      }
      data['trendPoints'] = days;
      data['weekdayTrend'] = weekdayTrend(sessions);
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
            'label': 'Дни ${bucketStart.day}–${bucketEnd.subtract(const Duration(days: 1)).day}',
            'sleepMinutes': summarize(bucketSessions)['averageSleepMinutes'],
            'samples': summarize(bucketSessions)['sleepDurationSamples'],
            'nights': nightlyDetails(bucketSessions),
          });
        }
      }
      data['weeklyTrend'] = trend;
      data['trendPoints'] = trend;
      data['weekdayPatterns'] = weekdayPatterns(sessions);
      data['weekdayTrend'] = weekdayTrend(sessions);
    }

    if (kind == PeriodicReportKind.quarter ||
        kind == PeriodicReportKind.halfYear ||
        kind == PeriodicReportKind.year) {
      final months = <Map<String, Object?>>[];
      var monthStart = DateTime(start.year, start.month);
      while (monthStart.isBefore(end)) {
        final monthEnd = DateTime(monthStart.year, monthStart.month + 1);
        final monthSessions = sessions.where((s) =>
          !s.startedAt.isBefore(monthStart) && s.startedAt.isBefore(monthEnd)).toList();
        if (monthSessions.isNotEmpty) {
          final summary = summarize(monthSessions);
          months.add({
            'month': monthStart.month,
            'label': PeriodicReportSnapshot.monthName(monthStart.month),
            ...summary,
            'sleepMinutes': summary['averageSleepMinutes'],
            'samples': summary['sleepDurationSamples'],
            'nights': nightlyDetails(monthSessions),
          });
        }
        monthStart = monthEnd;
      }
      data['months'] = months;
      data['trendPoints'] = months;
      data['weekdayPatterns'] = weekdayPatterns(sessions);
      data['weekdayTrend'] = weekdayTrend(sessions);
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
    if (kind == PeriodicReportKind.quarter) return DateTime(value.year, ((value.month - 1) ~/ 3) * 3 + 1);
    if (kind == PeriodicReportKind.halfYear) return DateTime(value.year, value.month <= 6 ? 1 : 7);
    return DateTime(value.year);
  }
  static DateTime _nextPeriodStart(DateTime value, PeriodicReportKind kind) {
    if (kind == PeriodicReportKind.week) return value.add(const Duration(days: 7));
    if (kind == PeriodicReportKind.month) return DateTime(value.year, value.month + 1);
    if (kind == PeriodicReportKind.quarter) return DateTime(value.year, value.month + 3);
    if (kind == PeriodicReportKind.halfYear) return DateTime(value.year, value.month + 6);
    return DateTime(value.year + 1);
  }
  static DateTime _previousPeriodStart(DateTime value, PeriodicReportKind kind) {
    if (kind == PeriodicReportKind.week) return value.subtract(const Duration(days: 7));
    if (kind == PeriodicReportKind.month) return DateTime(value.year, value.month - 1);
    if (kind == PeriodicReportKind.quarter) return DateTime(value.year, value.month - 3);
    if (kind == PeriodicReportKind.halfYear) return DateTime(value.year, value.month - 6);
    return DateTime(value.year - 1);
  }
  static String _id(PeriodicReportKind kind, DateTime start) =>
    kind.name + '_' + start.year.toString().padLeft(4, '0') + '-' + start.month.toString().padLeft(2, '0') + '-' + start.day.toString().padLeft(2, '0');
}
