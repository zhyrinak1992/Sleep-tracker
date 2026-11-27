class AudioEventPeriodSummary {
  const AudioEventPeriodSummary({
    required this.eventCount,
    required this.nightsWithEvents,
    required this.savedDurationMs,
    required this.categoryCounts,
    required this.categoryDurationMs,
    required this.categoryEvents,
  });

  final int eventCount;
  final int nightsWithEvents;
  final int savedDurationMs;
  final Map<String, int> categoryCounts;
  final Map<String, int> categoryDurationMs;
  final Map<String, List<Map<String, Object?>>> categoryEvents;

  static AudioEventPeriodSummary summarize({
    required Iterable<Map<String, Object?>> events,
    required Set<String> sessionIds,
  }) {
    if (sessionIds.isEmpty) {
      return const AudioEventPeriodSummary(
        eventCount: 0,
        nightsWithEvents: 0,
        savedDurationMs: 0,
        categoryCounts: {},
        categoryDurationMs: {},
        categoryEvents: {},
      );
    }
    final nights = <String>{};
    final categories = <String, int>{};
    final durations = <String, int>{};
    final eventsByCategory = <String, List<Map<String, Object?>>>{};
    var count = 0;
    var duration = 0;
    for (final row in events) {
      final sessionId = row['session_id'];
      if (sessionId is! String || !sessionIds.contains(sessionId)) continue;
      count++;
      nights.add(sessionId);
      final rawCategory = row['category'];
      final category = rawCategory is String && rawCategory.trim().isNotEmpty
          ? rawCategory.trim()
          : 'unknown';
      categories[category] = (categories[category] ?? 0) + 1;
      eventsByCategory.putIfAbsent(category, () => []).add(Map<String, Object?>.from(row));
      final rawDuration = row['duration_ms'];
      if (rawDuration is int && rawDuration > 0) {
        duration += rawDuration;
        durations[category] = (durations[category] ?? 0) + rawDuration;
      }
    }
    final ordered = categories.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return AudioEventPeriodSummary(
      eventCount: count,
      nightsWithEvents: nights.length,
      savedDurationMs: duration,
      categoryCounts: Map.unmodifiable({
        for (final entry in ordered) entry.key: entry.value,
      }),
      categoryDurationMs: Map.unmodifiable(durations),
      categoryEvents: Map.unmodifiable({
        for (final entry in eventsByCategory.entries)
          entry.key: List<Map<String, Object?>>.unmodifiable(
            entry.value..sort((a, b) =>
              (DateTime.tryParse(a['captured_at'] as String? ?? '') ?? DateTime(1970))
                .compareTo(DateTime.tryParse(b['captured_at'] as String? ?? '') ?? DateTime(1970))),
          ),
      }),
    );
  }
}
