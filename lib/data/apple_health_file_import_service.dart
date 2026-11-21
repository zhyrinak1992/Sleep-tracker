import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';

import 'sleep_database.dart';

class AppleHealthFilePreview {
  AppleHealthFilePreview({
    required this.nights,
    required this.stages,
    required this.metrics,
    required List<_ImportedNight> sessions,
  }) : _sessions = sessions;

  final int nights;
  final int stages;
  final int metrics;
  final List<_ImportedNight> _sessions;

  Future<AppleHealthFileImportResult> importIntoDatabase() async {
    var importedNights = 0;
    var importedStages = 0;
    var importedMetrics = 0;
    final db = SleepDatabase.instance;

    for (final night in _sessions) {
      final inserted = await db.insertHealthSession(
        id: night.id,
        startedAt: night.startedAt,
        endedAt: night.endedAt,
        sourceName: night.sourceName.isEmpty
            ? 'Apple Health (импорт из файла)'
            : '${night.sourceName} · импорт из файла',
      );
      if (!inserted) continue;
      importedNights++;

      for (final stage in night.stages) {
        await db.addSleepStage(
          id: stage.id,
          sessionId: night.id,
          stage: stage.name,
          startedAt: stage.from,
          endedAt: stage.to,
          source: 'Apple Health · ручной импорт',
        );
        importedStages++;
      }
      for (final metric in night.metrics) {
        await db.addSleepMetric(
          id: metric.id,
          sessionId: night.id,
          type: metric.name,
          value: metric.value,
          unit: metric.unit,
          measuredAt: metric.at,
          source: 'Apple Health · ручной импорт',
        );
        importedMetrics++;
      }
    }
    return AppleHealthFileImportResult(
      nights: importedNights,
      stages: importedStages,
      metrics: importedMetrics,
    );
  }
}

class AppleHealthFileImportResult {
  const AppleHealthFileImportResult({
    required this.nights,
    required this.stages,
    required this.metrics,
  });
  final int nights;
  final int stages;
  final int metrics;
}

class _ImportedNight {
  _ImportedNight({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.sourceName,
    required this.stages,
    required this.metrics,
  });
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String sourceName;
  final List<_ImportedStage> stages;
  final List<_ImportedMetric> metrics;
}

class _ImportedStage {
  _ImportedStage(this.id, this.name, this.from, this.to);
  final String id;
  final String name;
  final DateTime from;
  final DateTime to;
}

class _ImportedMetric {
  _ImportedMetric(this.id, this.name, this.value, this.unit, this.at);
  final String id;
  final String name;
  final double value;
  final String unit;
  final DateTime at;
}

class AppleHealthFileImportService {
  AppleHealthFileImportService._();
  static final instance = AppleHealthFileImportService._();

  Future<AppleHealthFilePreview?> chooseAndPreview() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      throw const FormatException('Не удалось прочитать ZIP-файл. Попробуйте сохранить его в «Файлы» и выбрать снова.');
    }
    return parseExport(bytes);
  }

  AppleHealthFilePreview parseExport(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? exportFile;
    for (final file in archive.files) {
      if (file.isFile && file.name.split('/').last.toLowerCase() == 'export.xml') {
        exportFile = file;
        break;
      }
    }
    if (exportFile == null) {
      throw const FormatException('В ZIP-архиве не найден export.xml. Выберите архив «Экспорт всех данных о здоровье» из Apple Health.');
    }
    final content = exportFile.content;
    if (content is! List<int>) {
      throw const FormatException('Не удалось прочитать export.xml из архива.');
    }
    final document = XmlDocument.parse(utf8.decode(content));
    final records = <_HealthRecord>[];
    for (final element in document.findAllElements('Record')) {
      final type = element.getAttribute('type') ?? '';
      final start = DateTime.tryParse(element.getAttribute('startDate') ?? '');
      final end = DateTime.tryParse(element.getAttribute('endDate') ?? '');
      if (start == null || end == null || !end.isAfter(start)) continue;
      final value = element.getAttribute('value') ?? '';
      final source = element.getAttribute('sourceName') ?? '';
      final unit = element.getAttribute('unit') ?? '';
      final sleep = _sleepStage(value);
      final metric = _metric(type);
      if (type == 'HKCategoryTypeIdentifierSleepAnalysis' && sleep != null) {
        records.add(_HealthRecord(type, value, start, end, source, unit, null, sleep));
      } else if (metric != null) {
        final parsed = double.tryParse(value);
        if (parsed != null && parsed.isFinite) {
          final number = type == 'HKQuantityTypeIdentifierOxygenSaturation' && parsed <= 1
              ? parsed * 100
              : parsed;
          records.add(_HealthRecord(type, value, start, end, source, unit, number, metric.$1));
        }
      }
    }

    final sleepRecords = records.where((r) => r.stage != null).toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    final metricRecords = records.where((r) => r.metricValue != null).toList();
    if (sleepRecords.isEmpty) {
      throw const FormatException('В архиве не найдены интервалы сна с распознаваемыми фазами.');
    }

    final groups = <List<_HealthRecord>>[];
    for (final record in sleepRecords) {
      if (groups.isEmpty) {
        groups.add([record]);
        continue;
      }
      final current = groups.last;
      final latest = current.map((r) => r.to).reduce((a, b) => a.isAfter(b) ? a : b);
      if (record.from.difference(latest) <= const Duration(minutes: 90)) {
        current.add(record);
      } else {
        groups.add([record]);
      }
    }

    final nights = <_ImportedNight>[];
    for (final group in groups) {
      final from = group.map((r) => r.from).reduce((a, b) => a.isBefore(b) ? a : b);
      final to = group.map((r) => r.to).reduce((a, b) => a.isAfter(b) ? a : b);
      final source = group.map((r) => r.source).where((s) => s.isNotEmpty).toSet().join(', ');
      final id = 'apple_file_night_${_stableHash(group.map((r) => '${r.type}|${r.value}|${r.from.toUtc().toIso8601String()}|${r.to.toUtc().toIso8601String()}|${r.source}').join(';'))}';
      final stages = group.map((r) => _ImportedStage(
        'apple_file_stage_${_stableHash('${r.type}|${r.value}|${r.from.toUtc().toIso8601String()}|${r.to.toUtc().toIso8601String()}|${r.source}')}',
        r.stage!, r.from, r.to,
      )).toList();

      final linkedMetrics = <_ImportedMetric>[];
      for (final metric in metricRecords) {
        if (metric.from.isBefore(to.add(const Duration(hours: 1))) &&
            metric.to.isAfter(from.subtract(const Duration(hours: 1)))) {
          linkedMetrics.add(_ImportedMetric(
            'apple_file_metric_${_stableHash('${metric.type}|${metric.value}|${metric.from.toUtc().toIso8601String()}|${metric.to.toUtc().toIso8601String()}|${metric.source}')}',
            metric.stage!,
            metric.metricValue!,
            metric.unit,
            metric.to,
          ));
        }
      }
      nights.add(_ImportedNight(
        id: id, startedAt: from, endedAt: to, sourceName: source,
        stages: stages, metrics: linkedMetrics,
      ));
    }
    return AppleHealthFilePreview(
      nights: nights.length,
      stages: nights.fold(0, (sum, n) => sum + n.stages.length),
      metrics: nights.fold(0, (sum, n) => sum + n.metrics.length),
      sessions: nights,
    );
  }

  static String? _sleepStage(String value) => switch (value) {
    'HKCategoryValueSleepAnalysisAwake' => 'Бодрствование',
    'HKCategoryValueSleepAnalysisAsleep' ||
    'HKCategoryValueSleepAnalysisAsleepUnspecified' => 'Сон без уточнённой фазы',
    'HKCategoryValueSleepAnalysisAsleepCore' => 'Лёгкий сон',
    'HKCategoryValueSleepAnalysisAsleepDeep' => 'Глубокий сон',
    'HKCategoryValueSleepAnalysisAsleepREM' => 'REM-сон',
    _ => null,
  };

  static (String, String)? _metric(String type) => switch (type) {
    'HKQuantityTypeIdentifierHeartRate' => ('Пульс', 'уд/мин'),
    'HKQuantityTypeIdentifierRespiratoryRate' => ('Частота дыхания', 'вдох/мин'),
    'HKQuantityTypeIdentifierOxygenSaturation' => ('Насыщение кислородом', '%'),
    'HKQuantityTypeIdentifierHeartRateVariabilitySDNN' => ('Вариабельность пульса SDNN', 'мс'),
    _ => null,
  };

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

class _HealthRecord {
  _HealthRecord(this.type, this.value, this.from, this.to, this.source,
      this.unit, this.metricValue, this.stage);
  final String type;
  final String value;
  final DateTime from;
  final DateTime to;
  final String source;
  final String unit;
  final double? metricValue;
  final String? stage;
}
