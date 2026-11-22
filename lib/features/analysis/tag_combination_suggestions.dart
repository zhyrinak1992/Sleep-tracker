import 'dart:convert';

import '../../models/sleep_session.dart';

class TagCombinationSuggestion {
  const TagCombinationSuggestion({
    required this.tagKeys,
    required this.nightCount,
  });

  final List<String> tagKeys;
  final int nightCount;

  String get signature => TagCombinationSuggestionStore.signature(tagKeys);
}

class TagCombinationSuggestionAnalyzer {
  static const minimumNights = 3;

  static List<TagCombinationSuggestion> analyze({
    required Iterable<SleepSession> sessions,
    required Map<String, Set<String>> tagsBySession,
    required DateTime start,
    required DateTime endExclusive,
    Iterable<Iterable<String>> existingCombinations = const [],
    Set<String> dismissedSignatures = const {},
    int limit = 3,
  }) {
    if (!endExclusive.isAfter(start)) return const [];
    final existing = existingCombinations.map(TagCombinationSuggestionStore.signature).toSet();
    final dismissed = dismissedSignatures.toSet();
    final usage = <String, Set<String>>{};
    final combinations = <String, List<String>>{};

    for (final session in sessions) {
      if (session.startedAt.isBefore(start) || !session.startedAt.isBefore(endExclusive)) continue;
      if (session.endedAt == null || !session.endedAt!.isAfter(session.startedAt)) continue;
      final keys = (tagsBySession[session.id] ?? const <String>{}).toSet().toList()..sort();
      if (keys.length < 2) continue;
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final pair = [keys[i], keys[j]];
          final signature = TagCombinationSuggestionStore.signature(pair);
          combinations[signature] = pair;
          usage.putIfAbsent(signature, () => <String>{}).add(session.id);
        }
      }
    }

    final suggestions = usage.entries
        .where((entry) => entry.value.length >= minimumNights &&
            !existing.contains(entry.key) && !dismissed.contains(entry.key))
        .map((entry) => TagCombinationSuggestion(
          tagKeys: combinations[entry.key]!,
          nightCount: entry.value.length,
        ))
        .toList()
      ..sort((a, b) {
        final byNights = b.nightCount.compareTo(a.nightCount);
        if (byNights != 0) return byNights;
        return a.tagKeys.join('|').compareTo(b.tagKeys.join('|'));
      });
    return suggestions.take(limit).toList();
  }
}

class TagCombinationSuggestionStore {
  TagCombinationSuggestionStore(this._read, this._write);

  static const metadataKey = 'dismissed_tag_combination_suggestions_v1';
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  static String signature(Iterable<String> tagKeys) {
    final keys = tagKeys.toSet().toList()..sort();
    return jsonEncode(keys);
  }

  Future<Set<String>> loadDismissed() async {
    final raw = await _read(metadataKey);
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw const FormatException('Список скрытых сочетаний повреждён.');
    }
    return decoded.cast<String>().toSet();
  }

  Future<void> dismiss(Iterable<String> tagKeys) async {
    final dismissed = await loadDismissed();
    dismissed.add(signature(tagKeys));
    await _write(metadataKey, jsonEncode(dismissed.toList()..sort()));
  }
}
