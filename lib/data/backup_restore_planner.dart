import 'dart:convert';

class BackupRestorePlan {
  const BackupRestorePlan({
    required this.archiveRecordCount,
    required this.currentRecordCount,
    required this.recordsToAdd,
    required this.duplicatesToSkip,
    required this.currentRecordsToReplace,
    required this.historyEntriesToMerge,
    required this.audioFilesToRestore,
    required this.missingAudioFiles,
    required this.audioBytesToRestore,
    required this.requiredBytesEstimate,
    required this.availableBytes,
    required this.stateFingerprint,
    this.blockedReason,
  });

  final int archiveRecordCount;
  final int currentRecordCount;
  final int recordsToAdd;
  final int duplicatesToSkip;
  final int currentRecordsToReplace;
  final int historyEntriesToMerge;
  final int audioFilesToRestore;
  final int missingAudioFiles;
  final int audioBytesToRestore;
  final int requiredBytesEstimate;
  final int? availableBytes;
  final String stateFingerprint;
  final String? blockedReason;

  bool get spaceCheckKnown => availableBytes != null;
  bool get hasEnoughSpace => availableBytes == null || availableBytes! >= requiredBytesEstimate;
  bool get canProceed => blockedReason == null && hasEnoughSpace;
}

class BackupRestoreImpact {
  const BackupRestoreImpact({required this.replace, required this.merge});
  final BackupRestorePlan replace;
  final BackupRestorePlan merge;
}

class BackupRestorePlanner {
  BackupRestorePlanner._();

  static const tableKeys = <String, List<String>>{
    'sleep_sessions': ['id'],
    'sleep_session_tags': ['session_id', 'tag_key'],
    'sleep_notes': ['id'],
    'app_metadata': ['key'],
    'sleep_stages': ['id'],
    'sleep_metrics': ['id'],
    'audio_events': ['id'],
    'morning_reports': ['session_id'],
    'climate_samples': ['id'],
  };

  static String _key(Map<String, Object?> row, List<String> columns) =>
      jsonEncode(columns.map((column) => row[column]).toList());

  static Set<String> _keys(
    List<Map<String, Object?>> rows,
    List<String> columns,
  ) => rows.map((row) => _key(row, columns)).toSet();

  static List<Map<String, Object?>> _historyRows(
    List<Map<String, Object?>> metadata,
    String key,
  ) {
    Map<String, Object?>? row;
    for (final item in metadata) {
      if (item['key'] == key) { row = item; break; }
    }
    if (row == null) return [];
    if (row['value'] is! String) throw FormatException('Повреждено значение истории $key.');
    final decoded = jsonDecode(row['value'] as String);
    if (decoded is! List || decoded.any((item) => item is! Map)) {
      throw FormatException('Повреждён раздел истории $key в резервной копии.');
    }
    return decoded.map((item) => Map<String, Object?>.from(item as Map)).toList();
  }

  static Set<String> _historyIdentities(
    List<Map<String, Object?>> rows,
    String key,
  ) {
    if (key == 'sleep_change_history_v1') {
      return rows.map((row) => '${row['periodKey']}|${row['fingerprint']}').toSet();
    }
    return rows.map((row) => row['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
  }

  static int _rowBytes(Map<String, Object?> row) {
    final copy = Map<String, Object?>.from(row)..remove('audioDataB64');
    return utf8.encode(jsonEncode(copy)).length;
  }

  static int _achievementMetadataMergeCount(
    String key,
    Object? localRaw,
    Object? importedRaw,
  ) {
    Object? decode(Object? raw) {
      if (raw is! String || raw.isEmpty) return null;
      try {
        return jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }

    final local = decode(localRaw);
    final imported = decode(importedRaw);
    switch (key) {
      case 'sleep_achievements_history_v1':
        if (imported is! Map) return 0;
        final localMap = local is Map ? local : const <Object?, Object?>{};
        return imported.entries.where((entry) {
          final previous = localMap[entry.key];
          final incomingDate = entry.value is String
              ? DateTime.tryParse(entry.value as String)
              : null;
          final previousDate = previous is String
              ? DateTime.tryParse(previous)
              : null;
          return incomingDate != null &&
              (previousDate == null || incomingDate.isBefore(previousDate));
        }).length;
      case 'sleep_personal_records_v1':
        if (imported is! Map) return 0;
        final localMap = local is Map ? local : const <Object?, Object?>{};
        bool valid(Object? value, {bool percent = false}) =>
            value is num && value.isFinite && value >= 0 &&
            (!percent || value <= 100) &&
            (percent || value % 1 == 0);
        var count = 0;
        for (final field in [
          'longestSleepMinutes',
          'bestEfficiencyPercent',
          'shortestLatencyMinutes',
          'longestStreakDays',
        ]) {
          final incoming = imported[field];
          final previous = localMap[field];
          if (!valid(incoming, percent: field == 'bestEfficiencyPercent') ||
              (field == 'shortestLatencyMinutes' && incoming > 1440)) continue;
          if (!valid(previous, percent: field == 'bestEfficiencyPercent') ||
              (field == 'shortestLatencyMinutes' && (previous as num) > 1440)) {
            count++;
          } else {
            final incomingNumber = incoming as num;
            final previousNumber = previous as num;
            final improves = field == 'shortestLatencyMinutes'
                ? incomingNumber < previousNumber
                : incomingNumber > previousNumber;
            if (improves) count++;
          }
        }
        return count;
      case 'sleep_personal_records_history_v1':
        if (imported is! List) return 0;
        bool validEvent(Object? item) {
          if (item is! Map || item['id'] is! String ||
              (item['id'] as String).isEmpty ||
              item['metric'] is! String ||
              !const {
                'longestSleepMinutes',
                'bestEfficiencyPercent',
                'shortestLatencyMinutes',
                'longestStreakDays',
              }.contains(item['metric']) ||
              item['value'] is! num ||
              !(item['value'] as num).toDouble().isFinite ||
              item['achievedAt'] is! String ||
              DateTime.tryParse(item['achievedAt'] as String) == null ||
              (item['sessionId'] != null && item['sessionId'] is! String)) {
            return false;
          }
          final value = (item['value'] as num).toDouble();
          return switch (item['metric']) {
            'longestSleepMinutes' => value > 0 && value % 1 == 0,
            'bestEfficiencyPercent' => value >= 0 && value <= 100,
            'shortestLatencyMinutes' =>
              value >= 0 && value <= 1440 && value % 1 == 0,
            'longestStreakDays' => value >= 1 && value % 1 == 0,
            _ => false,
          };
        }

        final identities = <String>{};
        if (local is List) {
          for (final item in local) {
            if (validEvent(item)) identities.add(item['id'] as String);
          }
        }
        var count = 0;
        for (final item in imported) {
          if (validEvent(item) && identities.add(item['id'] as String)) {
            count++;
          }
        }
        return count;
      case 'sleep_records_history_v1':
        if (imported is! List) return 0;
        final identities = <String>{};
        if (local is List) {
          for (final item in local) {
            if (item is Map && item['type'] is String && item['sessionId'] is String) {
              identities.add('${item['type']}|${item['sessionId']}');
            }
          }
        }
        var count = 0;
        for (final item in imported) {
          if (item is! Map || item['type'] is! String || item['sessionId'] is! String) continue;
          if (identities.add('${item['type']}|${item['sessionId']}')) count++;
        }
        return count;
      case 'sleep_records_celebrated_v1':
        final localSet = local is List ? local.whereType<String>().toSet() : <String>{};
        final importedSet = imported is List ? imported.whereType<String>().toSet() : <String>{};
        return importedSet.difference(localSet).length;
      default:
        return 0;
    }
  }

  static int _audioBytes(Map<String, Object?> row) {
    final encoded = row['audioDataB64'];
    if (encoded is! String || encoded.isEmpty) return 0;
    return base64Decode(encoded).length;
  }

  static BackupRestoreImpact calculate({
    required Map<String, List<Map<String, Object?>>> archiveRows,
    required Map<String, List<Map<String, Object?>>> currentRows,
    required int? availableBytes,
  }) {
    final archiveRecordCount = archiveRows.values.fold<int>(0, (sum, rows) => sum + rows.length);
    final currentRecordCount = currentRows.values.fold<int>(0, (sum, rows) => sum + rows.length);

    final archiveAudio = archiveRows['audio_events'] ?? const <Map<String, Object?>>[];
    final currentAudioIds = _keys(
      currentRows['audio_events'] ?? const [],
      const ['id'],
    );

    final replaceAudioRows = archiveAudio;
    final mergeAudioRows = archiveAudio.where((row) =>
      !currentAudioIds.contains(_key(row, const ['id']))).toList();

    final replaceMissingAudio = replaceAudioRows.where((row) =>
      row['file_path'] != null && row['audioDataB64'] == null).length;
    final mergeMissingAudio = mergeAudioRows.where((row) =>
      row['file_path'] != null && row['audioDataB64'] == null).length;

    final replaceAudioBytes = replaceAudioRows.fold<int>(0, (sum, row) => sum + _audioBytes(row));
    final mergeAudioBytes = mergeAudioRows.fold<int>(0, (sum, row) => sum + _audioBytes(row));

    var recordsToAdd = 0;
    var duplicatesToSkip = 0;
    var historyEntriesToMerge = 0;
    var mergeDatabaseBytes = 0;
    String? mergeBlockedReason;

    final fingerprintBasis = <String, Object?>{
      'archive': <String, Object?>{},
      'current': <String, Object?>{},
    };

    for (final table in tableKeys.keys) {
      final archive = archiveRows[table] ?? const <Map<String, Object?>>[];
      final current = currentRows[table] ?? const <Map<String, Object?>>[];
      final keys = tableKeys[table]!;
      final currentKeys = _keys(current, keys);
      if (table == 'app_metadata') {
        Map<String, Object?> metadataFingerprint(Map<String, Object?> row) {
          final key = row['key'];
          return {
            'key': key,
            'value': row['value'],
          };
        }
        final archiveState = archive.map(metadataFingerprint).toList()
          ..sort((a, b) => (a['key'] as String).compareTo(b['key'] as String));
        final currentState = current.map(metadataFingerprint).toList()
          ..sort((a, b) => (a['key'] as String).compareTo(b['key'] as String));
        (fingerprintBasis['archive'] as Map<String, Object?>)[table] = archiveState;
        (fingerprintBasis['current'] as Map<String, Object?>)[table] = currentState;
      } else {
        final archiveKeys = archive.map((row) => _key(row, keys)).toList()..sort();
        final currentKeysList = current.map((row) => _key(row, keys)).toList()..sort();
        (fingerprintBasis['archive'] as Map<String, Object?>)[table] = archiveKeys;
        (fingerprintBasis['current'] as Map<String, Object?>)[table] = currentKeysList;
      }

      if (table == 'app_metadata') {
        final currentByKey = {
          for (final row in current)
            if (row['key'] is String) row['key'] as String: row,
        };
        for (final row in archive) {
          final metadataKey = row['key'];
          if (metadataKey == 'sleep_change_history_v1' ||
              metadataKey == 'comparison_suggestion_history_v1') {
            final historyKey = metadataKey as String;
            final importedHistory = _historyRows(archive, historyKey);
            List<Map<String, Object?>> localHistory;
            try {
              localHistory = _historyRows(current, historyKey);
            } catch (_) {
              mergeBlockedReason ??= 'Локальная история $historyKey повреждена. Для безопасного восстановления выберите полную замену.';
              localHistory = [];
            }
            final localIds = _historyIdentities(localHistory, historyKey);
            final importedIds = _historyIdentities(importedHistory, historyKey);
            final newCount = importedIds.difference(localIds).length;
            historyEntriesToMerge += newCount;
            duplicatesToSkip += importedIds.length - newCount;
            mergeDatabaseBytes += importedHistory
              .where((item) => !localIds.contains(
                historyKey == 'sleep_change_history_v1'
                  ? '${item['periodKey']}|${item['fingerprint']}'
                  : item['id'] as String? ?? '',
              ))
              .fold<int>(0, (sum, item) => sum + _rowBytes(item));
            continue;
          }
          if (metadataKey is String && currentByKey.containsKey(metadataKey)) {
            const mergeableAchievementKeys = {
              'sleep_achievements_history_v1',
              'sleep_personal_records_v1',
              'sleep_personal_records_history_v1',
              'sleep_records_history_v1',
              'sleep_records_celebrated_v1',
            };
            if (mergeableAchievementKeys.contains(metadataKey) &&
                currentByKey[metadataKey]!['value'] != row['value']) {
              historyEntriesToMerge += _achievementMetadataMergeCount(
                metadataKey,
                currentByKey[metadataKey]!['value'],
                row['value'],
              );
              mergeDatabaseBytes += _rowBytes(row);
            } else {
              duplicatesToSkip++;
            }
          } else {
            recordsToAdd++;
            mergeDatabaseBytes += _rowBytes(row);
          }
        }
        continue;
      }

      for (final row in archive) {
        if (currentKeys.contains(_key(row, keys))) {
          duplicatesToSkip++;
        } else {
          recordsToAdd++;
          mergeDatabaseBytes += _rowBytes(row);
        }
      }
    }

    final replaceDatabaseBytes = archiveRows.values
      .expand((rows) => rows)
      .fold<int>(0, (sum, row) => sum + _rowBytes(row));
    final replaceRequired = _withSafetyReserve(replaceDatabaseBytes + replaceAudioBytes);
    final mergeRequired = _withSafetyReserve(mergeDatabaseBytes + mergeAudioBytes);

    final replaceFingerprint = jsonEncode({
      'mode': 'replace',
      'archive': fingerprintBasis['archive'],
      'current': fingerprintBasis['current'],
    });
    final mergeFingerprint = jsonEncode({
      'mode': 'merge',
      'archive': fingerprintBasis['archive'],
      'current': fingerprintBasis['current'],
    });

    return BackupRestoreImpact(
      replace: BackupRestorePlan(
        archiveRecordCount: archiveRecordCount,
        currentRecordCount: currentRecordCount,
        recordsToAdd: archiveRecordCount,
        duplicatesToSkip: 0,
        currentRecordsToReplace: currentRecordCount,
        historyEntriesToMerge: 0,
        audioFilesToRestore: replaceAudioRows.where((row) => row['audioDataB64'] is String).length,
        missingAudioFiles: replaceMissingAudio,
        audioBytesToRestore: replaceAudioBytes,
        requiredBytesEstimate: replaceRequired,
        availableBytes: availableBytes,
        stateFingerprint: replaceFingerprint,
        blockedReason: null,
      ),
      merge: BackupRestorePlan(
        archiveRecordCount: archiveRecordCount,
        currentRecordCount: currentRecordCount,
        recordsToAdd: recordsToAdd,
        duplicatesToSkip: duplicatesToSkip,
        currentRecordsToReplace: 0,
        historyEntriesToMerge: historyEntriesToMerge,
        audioFilesToRestore: mergeAudioRows.where((row) => row['audioDataB64'] is String).length,
        missingAudioFiles: mergeMissingAudio,
        audioBytesToRestore: mergeAudioBytes,
        requiredBytesEstimate: mergeRequired,
        availableBytes: availableBytes,
        stateFingerprint: mergeFingerprint,
        blockedReason: mergeBlockedReason,
      ),
    );
  }

  static int _withSafetyReserve(int estimatedBytes) {
    final reserve = (estimatedBytes * 0.15).ceil();
    return estimatedBytes + (reserve > 10 * 1024 * 1024 ? reserve : 10 * 1024 * 1024);
  }
}
