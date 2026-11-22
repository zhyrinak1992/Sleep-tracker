import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

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
      final resolved = await db.upsertHealthSession(
        id: night.id,
        startedAt: night.startedAt,
        endedAt: night.endedAt,
        sourceName: night.sourceName.isEmpty
            ? 'Apple Health (импорт из файла)'
            : '${night.sourceName} · импорт из файла',
      );
      final sessionId = resolved.$1;
      if (sessionId == null) continue;
      if (resolved.$2) importedNights++;

      // Repeated file imports may discover additional records. Deterministic
      // sample IDs allow safe enrichment without duplicating existing rows.
      for (final stage in night.stages) {
        await db.addSleepStage(
          id: stage.id,
          sessionId: sessionId,
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
          sessionId: sessionId,
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
      allowedExtensions: ['zip', 'xml'],
      withData: false,
      withReadStream: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.single;
    final extension = (file.extension ??
            (file.name.contains('.') ? file.name.split('.').last : ''))
        .toLowerCase();

    final stream = file.readStream ??
        (file.path == null ? null : File(file.path!).openRead());

    if (extension == 'xml') {
      if (stream != null) return parseXmlStream(stream);
      if (file.bytes != null) {
        return parseXmlStream(Stream<List<int>>.value(file.bytes!));
      }
      throw const FormatException(
        'Не удалось открыть XML-файл. Сохраните его локально в «Файлы» и выберите повторно.',
      );
    }

    if (extension == 'zip') {
      // Keep the archive on disk and decode it through archive_io. Reading a
      // 250+ MB export into Uint8List can exhaust iPhone memory.
      String? zipPath = file.path;
      File? temporaryZip;
      if (zipPath == null && stream != null) {
        final tempDir = await getTemporaryDirectory();
        temporaryZip = File('${tempDir.path}/apple_health_${DateTime.now().microsecondsSinceEpoch}.zip');
        final sink = temporaryZip.openWrite();
        try {
          await for (final chunk in stream) {
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        zipPath = temporaryZip.path;
      }
      if (zipPath == null) {
        throw const FormatException(
          'Не удалось получить локальный файл ZIP. Сохраните архив в «Файлы» и выберите повторно.',
        );
      }
      try {
        return await parseExportFile(zipPath);
      } finally {
        if (temporaryZip != null && await temporaryZip.exists()) {
          await temporaryZip.delete();
        }
      }
    }

    throw const FormatException(
      'Поддерживаются ZIP-архив Apple Health и основной файл export.xml.',
    );
  }

  /// Parses an extracted Apple Health export.xml incrementally. This avoids
  /// loading a very large XML document and its complete DOM tree into RAM.
  Future<AppleHealthFilePreview> parseXmlStream(Stream<List<int>> bytes) async {
    final records = <_HealthRecord>[];

    await bytes
        .transform(utf8.decoder)
        .toXmlEvents()
        .normalizeEvents()
        .selectSubtreeEvents((event) => event.name == 'Record')
        .toXmlNodes()
        .expand((nodes) => nodes)
        .forEach((node) {
      if (node is! XmlElement) return;

      final type = node.getAttribute('type') ?? '';
      final start = DateTime.tryParse(node.getAttribute('startDate') ?? '');
      final end = DateTime.tryParse(node.getAttribute('endDate') ?? '');
      if (start == null || end == null || !end.isAfter(start)) return;

      final value = node.getAttribute('value') ?? '';
      final source = node.getAttribute('sourceName') ?? '';
      final unit = node.getAttribute('unit') ?? '';
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
    });

    return _createPreview(records);
  }

  Future<AppleHealthFilePreview> parseExportFile(String zipPath) async {
    final input = InputFileStream(zipPath);
    final tempDir = await getTemporaryDirectory();
    File? extractedXml;
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      final xmlFiles = archive.files
          .where((entry) => entry.isFile && entry.name.toLowerCase().endsWith('.xml'))
          .toList();

      if (xmlFiles.isEmpty) {
        final names = archive.files
            .where((entry) => entry.isFile)
            .take(12)
            .map((entry) => entry.name)
            .join(', ');
        throw FormatException(
          'В ZIP-архиве не найден XML-файл. Внутри обнаружены: ${names.isEmpty ? 'нет доступных файлов' : names}.',
        );
      }

      // Extract XML candidates to disk one at a time. Never materialize the
      // entire ZIP or the decompressed XML in RAM.
      for (final entry in xmlFiles) {
        final safeName = entry.name.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final candidate = File('${tempDir.path}/apple_health_${DateTime.now().microsecondsSinceEpoch}_$safeName');
        final output = OutputFileStream(candidate.path);
        try {
          entry.writeContent(output);
        } finally {
          output.close();
        }

        // Sleep records may occur near the end of a large Apple Health
        // export. Scan the complete XML incrementally, not just its header.
        final containsSleep = await _containsSleepRecords(candidate);
        if (containsSleep) {
          extractedXml = candidate;
          break;
        }
        await candidate.delete();
      }

      if (extractedXml == null) {
        final names = xmlFiles.take(12).map((entry) => entry.name).join(', ');
        throw FormatException(
          'В ZIP найдены XML-файлы, но записи сна Apple Health не обнаружены. Файлы: $names. Проверьте, что выбран основной экспорт, а не export_cda.',
        );
      }
      return await parseXmlStream(extractedXml.openRead());
    } finally {
      await input.close();
      if (extractedXml != null && await extractedXml.exists()) {
        await extractedXml.delete();
      }
    }
  }

  Future<bool> _containsSleepRecords(File file) async {
    const markers = <String>[
      'HKCategoryTypeIdentifierSleepAnalysis',
      'HKCategoryValueSleepAnalysis',
    ];
    var carry = '';
    await for (final chunk in file.openRead().transform(const Utf8Decoder(allowMalformed: true))) {
      final text = carry + chunk;
      if (markers.any(text.contains)) return true;
      // Preserve enough trailing characters to catch a marker split between
      // adjacent UTF-8 stream chunks.
      carry = text.length > 96 ? text.substring(text.length - 96) : text;
    }
    return false;
  }

  AppleHealthFilePreview _createPreview(List<_HealthRecord> records) {
    final sleepRecords = records.where((r) => r.stage != null &&
        r.type == 'HKCategoryTypeIdentifierSleepAnalysis').toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    final metricRecords = records.where((r) => r.metricValue != null).toList();

    if (sleepRecords.isEmpty) {
      throw const FormatException(
        'В выбранном XML не найдены интервалы сна. Выберите основной файл «экспорт» / export.xml, а не export_cda.',
      );
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
