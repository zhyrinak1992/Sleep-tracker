import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../features/home/comparison_suggestion_analyzer.dart';

enum ComparisonSuggestionFrequency {
  rare,
  moderate,
  often,
}

extension ComparisonSuggestionFrequencyDetails on ComparisonSuggestionFrequency {
  String get label => switch (this) {
    ComparisonSuggestionFrequency.rare => 'Редко',
    ComparisonSuggestionFrequency.moderate => 'Умеренно',
    ComparisonSuggestionFrequency.often => 'Чаще',
  };

  Duration get interval => switch (this) {
    ComparisonSuggestionFrequency.rare => const Duration(days: 30),
    ComparisonSuggestionFrequency.moderate => const Duration(days: 14),
    ComparisonSuggestionFrequency.often => const Duration(days: 7),
  };

  String get description => switch (this) {
    ComparisonSuggestionFrequency.rare => 'Не чаще одного предложения за 30 дней',
    ComparisonSuggestionFrequency.moderate => 'Не чаще одного предложения за 14 дней',
    ComparisonSuggestionFrequency.often => 'Не чаще одного предложения за 7 дней',
  };
}

enum ComparisonSuggestionStatus {
  pending,
  opened,
  saved,
  postponed,
  rejected,
  closed,
  notViewed,
}

class ComparisonSuggestionRecord {
  const ComparisonSuggestionRecord({
    required this.id,
    required this.candidate,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.statusEvents,
  });

  final String id;
  final ComparisonSuggestionCandidate candidate;
  final DateTime createdAt;
  final DateTime expiresAt;
  final ComparisonSuggestionStatus status;
  final List<Map<String, Object?>> statusEvents;

  ComparisonSuggestionRecord copyWith({
    ComparisonSuggestionStatus? status,
    List<Map<String, Object?>>? statusEvents,
  }) => ComparisonSuggestionRecord(
    id: id,
    candidate: candidate,
    createdAt: createdAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    statusEvents: statusEvents ?? this.statusEvents,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'candidate': candidate.toMap(),
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'status': status.name,
    'statusEvents': statusEvents,
  };

  factory ComparisonSuggestionRecord.fromMap(Map<String, dynamic> map) {
    final candidate = map['candidate'];
    final createdAt = DateTime.tryParse(map['createdAt'] as String? ?? '');
    final expiresAt = DateTime.tryParse(map['expiresAt'] as String? ?? '');
    final statusName = map['status'];
    final status = ComparisonSuggestionStatus.values.where((item) => item.name == statusName);
    final rawEvents = map['statusEvents'];
    if (map['id'] is! String || candidate is! Map<String, dynamic> ||
        createdAt == null || expiresAt == null || status.isEmpty ||
        rawEvents is! List || rawEvents.any((item) => item is! Map)) {
      throw const FormatException('Запись истории предложений сравнений повреждена.');
    }
    return ComparisonSuggestionRecord(
      id: map['id'] as String,
      candidate: ComparisonSuggestionCandidate.fromMap(candidate),
      createdAt: createdAt,
      expiresAt: expiresAt,
      status: status.first,
      statusEvents: rawEvents.map((item) => Map<String, Object?>.from(item as Map)).toList(),
    );
  }
}

class ComparisonSuggestionStore {
  ComparisonSuggestionStore(this._read, this._write);

  static const frequencyKey = 'comparison_suggestion_frequency_v1';
  static const historyKey = 'comparison_suggestion_history_v1';
  static const _uuid = Uuid();

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  Future<ComparisonSuggestionFrequency> loadFrequency() async {
    final raw = await _read(frequencyKey);
    for (final item in ComparisonSuggestionFrequency.values) {
      if (item.name == raw) return item;
    }
    return ComparisonSuggestionFrequency.moderate;
  }

  Future<void> saveFrequency(ComparisonSuggestionFrequency frequency) =>
      _write(frequencyKey, frequency.name);

  Future<List<ComparisonSuggestionRecord>> loadHistory() async {
    final raw = await _read(historyKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('История предложений сравнений повреждена.');
    }
    return decoded.map((item) => ComparisonSuggestionRecord.fromMap(item as Map<String, dynamic>)).toList();
  }

  Future<void> _saveHistory(List<ComparisonSuggestionRecord> history) =>
      _write(historyKey, jsonEncode(history.map((item) => item.toMap()).toList()));

  DateTime _nextMorning(DateTime now) => DateTime(now.year, now.month, now.day + 1, 8);

  Future<List<ComparisonSuggestionRecord>> _expireUnviewed(
    List<ComparisonSuggestionRecord> history,
    DateTime now,
  ) async {
    var changed = false;
    final updated = history.map((record) {
      if (record.status != ComparisonSuggestionStatus.pending ||
          now.isBefore(record.expiresAt)) return record;
      changed = true;
      return record.copyWith(
        status: ComparisonSuggestionStatus.notViewed,
        statusEvents: [
          ...record.statusEvents,
          {'status': ComparisonSuggestionStatus.notViewed.name, 'at': now.toIso8601String()},
        ],
      );
    }).toList();
    if (changed) await _saveHistory(updated);
    return updated;
  }

  bool _hasNewBasis(
    ComparisonSuggestionCandidate candidate,
    ComparisonSuggestionRecord previous,
  ) {
    if (candidate.fingerprint == previous.candidate.fingerprint) return false;
    final old = previous.candidate;
    final added = math.max(0, candidate.withNights - old.withNights) +
        math.max(0, candidate.withoutNights - old.withoutNights);
    final requiredGrowth = math.max(3, (old.withNights + old.withoutNights) * 0.2).ceil();
    final materialDifference = (candidate.difference - old.difference).abs() >=
        candidate.threshold * 0.5;
    return added >= requiredGrowth || materialDifference;
  }

  /// Returns the current pending card or creates one new, highest-priority card.
  /// A processed category pair cannot reappear until enough new observations or a
  /// material change in its measured difference has accumulated.
  Future<ComparisonSuggestionRecord?> currentOrCreate({
    required List<ComparisonSuggestionCandidate> candidates,
    required DateTime now,
  }) async {
    var history = await loadHistory();
    history = await _expireUnviewed(history, now);

    final pending = history.where((item) =>
      item.status == ComparisonSuggestionStatus.pending &&
      now.isBefore(item.expiresAt)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (pending.isNotEmpty) return pending.first;

    final frequency = await loadFrequency();
    if (history.isNotEmpty) {
      final latest = history.map((item) => item.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (now.difference(latest) < frequency.interval) return null;
    }

    for (final candidate in candidates) {
      final previous = history.where((item) =>
        item.candidate.signature == candidate.signature).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (previous.isNotEmpty && !_hasNewBasis(candidate, previous.first)) continue;

      final record = ComparisonSuggestionRecord(
        id: _uuid.v4(),
        candidate: candidate,
        createdAt: now,
        expiresAt: _nextMorning(now),
        status: ComparisonSuggestionStatus.pending,
        statusEvents: [
          {'status': ComparisonSuggestionStatus.pending.name, 'at': now.toIso8601String()},
        ],
      );
      await _saveHistory([...history, record]);
      return record;
    }
    return null;
  }

  Future<void> updateStatus({
    required String id,
    required ComparisonSuggestionStatus status,
    required DateTime now,
  }) async {
    if (status == ComparisonSuggestionStatus.pending ||
        status == ComparisonSuggestionStatus.notViewed) {
      throw ArgumentError('Недопустимый статус для ручного действия.');
    }
    final history = await loadHistory();
    final index = history.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Предложение больше не найдено в истории.');
    final old = history[index];
    if (old.status != ComparisonSuggestionStatus.pending) return;
    final updated = [...history];
    updated[index] = old.copyWith(
      status: status,
      statusEvents: [
        ...old.statusEvents,
        {'status': status.name, 'at': now.toIso8601String()},
      ],
    );
    await _saveHistory(updated);
  }
}
