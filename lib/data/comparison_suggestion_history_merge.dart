class ComparisonSuggestionHistoryMerge {
  ComparisonSuggestionHistoryMerge._();

  /// Merges backup history by stable suggestion ID. Local record fields take
  /// precedence, while distinct status events from both devices are retained.
  static List<Map<String, Object?>> merge({
    required List<Map<String, Object?>> local,
    required List<Map<String, Object?>> imported,
  }) {
    final merged = <String, Map<String, Object?>>{};
    for (final item in local) {
      final id = item['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('Локальная история предложений содержит запись без ID.');
      }
      merged[id] = Map<String, Object?>.from(item);
    }
    for (final item in imported) {
      final id = item['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('История предложений из резервной копии содержит запись без ID.');
      }
      final incoming = Map<String, Object?>.from(item);
      final existing = merged[id];
      if (existing == null) {
        merged[id] = incoming;
        continue;
      }
      final events = <String, Map<String, Object?>>{};
      for (final event in [
        ...((existing['statusEvents'] as List?) ?? const []),
        ...((incoming['statusEvents'] as List?) ?? const []),
      ]) {
        if (event is! Map || event['status'] is! String || event['at'] is! String) continue;
        final normalized = Map<String, Object?>.from(event);
        events['${normalized['status']}|${normalized['at']}'] = normalized;
      }
      final sortedEvents = events.values.toList()
        ..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
      if (sortedEvents.isNotEmpty) {
        existing['statusEvents'] = sortedEvents;
        existing['status'] = sortedEvents.last['status'];
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => (a['createdAt'] as String? ?? '').compareTo(b['createdAt'] as String? ?? ''));
    return List.unmodifiable(result);
  }
}
