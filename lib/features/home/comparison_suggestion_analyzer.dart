import 'dart:convert';
import 'dart:math' as math;

import '../../models/sleep_session.dart';
import '../analysis/tag_combination_suggestions.dart';
import '../analysis/tag_sleep_comparison.dart';

class ComparisonSuggestionCandidate {
  const ComparisonSuggestionCandidate({
    required this.signature,
    required this.tagKeys,
    required this.metric,
    required this.start,
    required this.endExclusive,
    required this.withNights,
    required this.withoutNights,
    required this.withAverage,
    required this.withoutAverage,
    required this.difference,
    required this.threshold,
    required this.priority,
    required this.fingerprint,
    required this.withSessionIds,
    required this.withoutSessionIds,
  });

  final String signature;
  final List<String> tagKeys;
  final TagSleepMetric metric;
  final DateTime start;
  final DateTime endExclusive;
  final int withNights;
  final int withoutNights;
  final double withAverage;
  final double withoutAverage;
  final double difference;
  final double threshold;
  final double priority;
  final String fingerprint;
  final List<String> withSessionIds;
  final List<String> withoutSessionIds;

  Map<String, Object?> toMap() => {
    'signature': signature,
    'tagKeys': tagKeys,
    'metric': metric.name,
    'start': start.toIso8601String(),
    'endExclusive': endExclusive.toIso8601String(),
    'withNights': withNights,
    'withoutNights': withoutNights,
    'withAverage': withAverage,
    'withoutAverage': withoutAverage,
    'difference': difference,
    'threshold': threshold,
    'priority': priority,
    'fingerprint': fingerprint,
    'withSessionIds': withSessionIds,
    'withoutSessionIds': withoutSessionIds,
  };

  factory ComparisonSuggestionCandidate.fromMap(Map<String, dynamic> map) {
    TagSleepMetric? metric;
    for (final value in TagSleepMetric.values) {
      if (value.name == map['metric']) metric = value;
    }
    final keys = map['tagKeys'];
    final start = DateTime.tryParse(map['start'] as String? ?? '');
    final end = DateTime.tryParse(map['endExclusive'] as String? ?? '');
    if (map['signature'] is! String || keys is! List ||
        !keys.every((item) => item is String) || metric == null ||
        start == null || end == null ||
        map['withNights'] is! int || map['withoutNights'] is! int ||
        map['withAverage'] is! num || map['withoutAverage'] is! num ||
        map['difference'] is! num || map['threshold'] is! num ||
        map['priority'] is! num || map['fingerprint'] is! String ||
        map['withSessionIds'] is! List || map['withoutSessionIds'] is! List ||
        (map['withSessionIds'] as List).any((item) => item is! String) ||
        (map['withoutSessionIds'] as List).any((item) => item is! String)) {
      throw const FormatException('Предложение сравнения повреждено.');
    }
    return ComparisonSuggestionCandidate(
      signature: map['signature'] as String,
      tagKeys: keys.cast<String>(),
      metric: metric,
      start: start,
      endExclusive: end,
      withNights: map['withNights'] as int,
      withoutNights: map['withoutNights'] as int,
      withAverage: (map['withAverage'] as num).toDouble(),
      withoutAverage: (map['withoutAverage'] as num).toDouble(),
      difference: (map['difference'] as num).toDouble(),
      threshold: (map['threshold'] as num).toDouble(),
      priority: (map['priority'] as num).toDouble(),
      fingerprint: map['fingerprint'] as String,
      withSessionIds: (map['withSessionIds'] as List).cast<String>(),
      withoutSessionIds: (map['withoutSessionIds'] as List).cast<String>(),
    );
  }

  String get metricLabel => metric.label;
}

class ComparisonSuggestionAnalyzer {
  static const minimumNightsPerGroup = 4;

  static double thresholdFor(TagSleepMetric metric) => switch (metric) {
    TagSleepMetric.sleepDuration => 20,
    TagSleepMetric.morningRating => 0.5,
    TagSleepMetric.awakeningCount => 0.5,
  };

  static List<ComparisonSuggestionCandidate> analyze({
    required Iterable<SleepSession> sessions,
    required Map<String, Set<String>> tagsBySession,
    required Map<String, int> awakeningCountsBySession,
    required DateTime now,
    Iterable<Iterable<String>> existingCombinations = const [],
  }) {
    final start = DateTime(now.year, now.month, now.day - 89);
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final existing = existingCombinations
      .map(TagCombinationSuggestionStore.signature).toSet();
    final pairs = <String, List<String>>{};
    final counts = <String, Set<String>>{};

    for (final session in sessions) {
      if (session.startedAt.isBefore(start) || !session.startedAt.isBefore(end) ||
          session.endedAt == null || !session.endedAt!.isAfter(session.startedAt)) continue;
      final keys = (tagsBySession[session.id] ?? const <String>{}).toList()..sort();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final pair = [keys[i], keys[j]];
          final signature = TagCombinationSuggestionStore.signature(pair);
          pairs[signature] = pair;
          counts.putIfAbsent(signature, () => <String>{}).add(session.id);
        }
      }
    }

    final candidates = <ComparisonSuggestionCandidate>[];
    for (final entry in counts.entries) {
      if (entry.value.length < minimumNightsPerGroup || existing.contains(entry.key)) continue;
      final keys = pairs[entry.key]!;
      for (final metric in TagSleepMetric.values) {
        final result = TagSleepComparison.calculate(
          sessions: sessions,
          tagsBySession: tagsBySession,
          tagKeys: keys.toSet(),
          start: start,
          endExclusive: end,
          metric: metric,
          awakeningCountsBySession: awakeningCountsBySession,
        );
        if (!result.isSufficient ||
            result.withTag.average == null ||
            result.withoutTag.average == null ||
            result.difference == null) continue;
        final threshold = thresholdFor(metric);
        final magnitude = result.difference!.abs();
        if (magnitude < threshold) continue;

        final minGroup = math.min(result.withTag.nights, result.withoutTag.nights).toInt();
        final normalized = magnitude / threshold;
        final priority = normalized * (1 + math.min(minGroup, 20).toDouble() / 40);
        final withIds = result.withTag.sessionIds.toList()..sort();
        final withoutIds = result.withoutTag.sessionIds.toList()..sort();
        final fingerprint = jsonEncode({
          'withSessionIds': withIds,
          'withoutSessionIds': withoutIds,
          'withAverage': result.withTag.average!.toStringAsFixed(2),
          'withoutAverage': result.withoutTag.average!.toStringAsFixed(2),
          'difference': result.difference!.toStringAsFixed(2),
        });
        final signature = TagCombinationSuggestionStore.signature(keys);
        candidates.add(ComparisonSuggestionCandidate(
          signature: signature,
          tagKeys: keys,
          metric: metric,
          start: start,
          endExclusive: end,
          withNights: result.withTag.nights,
          withoutNights: result.withoutTag.nights,
          withAverage: result.withTag.average!,
          withoutAverage: result.withoutTag.average!,
          difference: result.difference!,
          threshold: threshold,
          priority: priority,
          fingerprint: fingerprint,
          withSessionIds: List.unmodifiable(withIds),
          withoutSessionIds: List.unmodifiable(withoutIds),
        ));
      }
    }
    candidates.sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      if (priority != 0) return priority;
      return a.signature.compareTo(b.signature);
    });
    return List.unmodifiable(candidates);
  }
}
