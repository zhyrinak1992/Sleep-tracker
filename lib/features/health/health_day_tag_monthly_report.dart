import 'dart:convert';

import '../../data/notification_service.dart';
import '../../data/sleep_database.dart';

class HealthDayTagMonthlyReport {
  const HealthDayTagMonthlyReport({
    required this.monthKey,
    required this.generatedAt,
    required this.recordedDays,
    required this.daysInMonth,
    required this.previousRecordedDays,
    required this.previousDaysInMonth,
    required this.tags,
  });

  final String monthKey;
  final DateTime generatedAt;
  final int recordedDays;
  final int daysInMonth;
  final int previousRecordedDays;
  final int previousDaysInMonth;
  final List<HealthDayTagMonthlyReportEntry> tags;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'monthKey': monthKey,
    'generatedAt': generatedAt.toIso8601String(),
    'recordedDays': recordedDays,
    'daysInMonth': daysInMonth,
    'previousRecordedDays': previousRecordedDays,
    'previousDaysInMonth': previousDaysInMonth,
    'tags': tags.map((entry) => entry.toJson()).toList(),
  };

  factory HealthDayTagMonthlyReport.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['monthKey'] is! String ||
        json['generatedAt'] is! String ||
        json['recordedDays'] is! int ||
        json['daysInMonth'] is! int ||
        json['previousRecordedDays'] is! int ||
        json['previousDaysInMonth'] is! int ||
        json['tags'] is! List) {
      throw const FormatException('Некорректный месячный отчёт по дневным отметкам.');
    }
    final generatedAt = DateTime.tryParse(json['generatedAt'] as String);
    if (generatedAt == null) {
      throw const FormatException('В отчёте указана некорректная дата формирования.');
    }
    return HealthDayTagMonthlyReport(
      monthKey: json['monthKey'] as String,
      generatedAt: generatedAt,
      recordedDays: json['recordedDays'] as int,
      daysInMonth: json['daysInMonth'] as int,
      previousRecordedDays: json['previousRecordedDays'] as int,
      previousDaysInMonth: json['previousDaysInMonth'] as int,
      tags: (json['tags'] as List).map((item) {
        if (item is! Map) {
          throw const FormatException('Некорректная строка отметки в месячном отчёте.');
        }
        return HealthDayTagMonthlyReportEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
      }).toList(),
    );
  }
}

class HealthDayTagMonthlyReportEntry {
  const HealthDayTagMonthlyReportEntry({
    required this.tag,
    required this.days,
    required this.share,
    required this.previousDays,
    required this.previousShare,
    required this.differencePercentagePoints,
  });

  final String tag;
  final int days;
  final double? share;
  final int previousDays;
  final double? previousShare;
  final double? differencePercentagePoints;

  Map<String, Object?> toJson() => {
    'tag': tag,
    'days': days,
    'share': share,
    'previousDays': previousDays,
    'previousShare': previousShare,
    'differencePercentagePoints': differencePercentagePoints,
  };

  factory HealthDayTagMonthlyReportEntry.fromJson(Map<String, dynamic> json) {
    if (json['tag'] is! String ||
        json['days'] is! int ||
        json['previousDays'] is! int ||
        (json['share'] != null && json['share'] is! num) ||
        (json['previousShare'] != null && json['previousShare'] is! num) ||
        (json['differencePercentagePoints'] != null &&
            json['differencePercentagePoints'] is! num)) {
      throw const FormatException('Некорректные данные отметки в месячном отчёте.');
    }
    return HealthDayTagMonthlyReportEntry(
      tag: json['tag'] as String,
      days: json['days'] as int,
      share: (json['share'] as num?)?.toDouble(),
      previousDays: json['previousDays'] as int,
      previousShare: (json['previousShare'] as num?)?.toDouble(),
      differencePercentagePoints:
          (json['differencePercentagePoints'] as num?)?.toDouble(),
    );
  }
}

class HealthDayTagMonthlyReportService {
  HealthDayTagMonthlyReportService(this.database);

  static const reportPrefix = 'health_day_monthly_report_';
  final SleepDatabase database;

  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static int daysInMonth(DateTime month) =>
      DateTime(month.year, month.month + 1, 0).day;

  static HealthDayTagMonthlyReport buildReport({
    required String monthKey,
    required Map<DateTime, List<String>> entries,
    required DateTime generatedAt,
  }) {
    final parts = monthKey.split('-');
    if (parts.length != 2) throw const FormatException('Некорректный месяц отчёта.');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      throw const FormatException('Некорректный месяц отчёта.');
    }
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final previousStart = DateTime(year, month - 1);
    final previousEnd = start;

    Map<String, int> countRange(DateTime from, DateTime until) {
      final counts = <String, int>{};
      for (final entry in entries.entries) {
        final day = DateTime(entry.key.year, entry.key.month, entry.key.day);
        if (day.isBefore(from) || !day.isBefore(until)) continue;
        for (final tag in entry.value.toSet()) {
          counts.update(tag, (value) => value + 1, ifAbsent: () => 1);
        }
      }
      return counts;
    }

    int recordedRange(DateTime from, DateTime until) => entries.keys.where((key) {
      final day = DateTime(key.year, key.month, key.day);
      return !day.isBefore(from) && day.isBefore(until);
    }).length;

    final currentCounts = countRange(start, end);
    final previousCounts = countRange(previousStart, previousEnd);
    final currentRecorded = recordedRange(start, end);
    final previousRecorded = recordedRange(previousStart, previousEnd);
    final tags = {...currentCounts.keys, ...previousCounts.keys}.toList()..sort();
    final reportTags = tags.map((tag) {
      final currentDays = currentCounts[tag] ?? 0;
      final previousDays = previousCounts[tag] ?? 0;
      final currentShare = currentRecorded == 0
          ? null : currentDays / currentRecorded * 100;
      final previousShare = previousRecorded == 0
          ? null : previousDays / previousRecorded * 100;
      return HealthDayTagMonthlyReportEntry(
        tag: tag,
        days: currentDays,
        share: currentShare,
        previousDays: previousDays,
        previousShare: previousShare,
        differencePercentagePoints: currentShare == null || previousShare == null
            ? null : currentShare - previousShare,
      );
    }).toList()
      ..sort((a, b) => b.days.compareTo(a.days));

    return HealthDayTagMonthlyReport(
      monthKey: monthKey,
      generatedAt: generatedAt,
      recordedDays: currentRecorded,
      daysInMonth: daysInMonth(start),
      previousRecordedDays: previousRecorded,
      previousDaysInMonth: daysInMonth(previousStart),
      tags: reportTags,
    );
  }

  Future<Map<DateTime, List<String>>> _loadEntries() async {
    final rows = await database.getAppMetadataByPrefix('health_day_');
    final result = <DateTime, List<String>>{};
    for (final entry in rows.entries) {
      final dateText = entry.key.substring('health_day_'.length);
      final day = DateTime.tryParse(dateText);
      if (day == null) continue;
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is! Map || decoded['tags'] is! List) continue;
        final tags = (decoded['tags'] as List)
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        result[DateTime(day.year, day.month, day.day)] = tags;
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  Future<List<HealthDayTagMonthlyReport>> loadReports() async {
    final rows = await database.getAppMetadataByPrefix(reportPrefix);
    final reports = <HealthDayTagMonthlyReport>[];
    for (final value in rows.values) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          reports.add(HealthDayTagMonthlyReport.fromJson(
            Map<String, dynamic>.from(decoded),
          ));
        }
      } catch (_) {
        continue;
      }
    }
    reports.sort((a, b) => b.monthKey.compareTo(a.monthKey));
    return reports;
  }

  static Future<List<HealthDayTagMonthlyReport>>? _generationInFlight;

  Future<List<HealthDayTagMonthlyReport>> generateClosedReports({
    DateTime? now,
  }) {
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

  Future<List<HealthDayTagMonthlyReport>> _generateClosedReports({
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final currentMonth = DateTime(current.year, current.month);
    final lastClosedMonth = DateTime(currentMonth.year, currentMonth.month - 1);
    final entries = await _loadEntries();
    if (entries.isEmpty) return loadReports();

    final firstEntry = entries.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    var month = DateTime(firstEntry.year, firstEntry.month);
    final stored = await database.getAppMetadataByPrefix(reportPrefix);
    while (!month.isAfter(lastClosedMonth)) {
      final key = monthKey(month);
      final metadataKey = '$reportPrefix$key';
      if (!stored.containsKey(metadataKey)) {
        final report = buildReport(
          monthKey: key,
          entries: entries,
          generatedAt: current,
        );
        await database.setAppMetadata(metadataKey, jsonEncode(report.toJson()));
        if (month.year == lastClosedMonth.year && month.month == lastClosedMonth.month) {
          await NotificationService.instance.healthDayTagMonthlyReportReady(key);
        }
      }
      month = DateTime(month.year, month.month + 1);
    }
    return loadReports();
  }
}
