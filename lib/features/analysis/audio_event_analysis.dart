class AudioEventPeriodSummary {
  const AudioEventPeriodSummary({
    required this.eventCount,
    required this.nightsWithEvents,
    required this.savedDurationMs,
    required this.categoryCounts,
  });

  final int eventCount;
  final int nightsWithEvents;
  final int savedDurationMs;
  final Map<String, int> categoryCounts;

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
      );
    }
    final nights = <String>{};
    final categories = <String, int>{};
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
      final rawDuration = row['duration_ms'];
      if (rawDuration is int && rawDuration > 0) duration += rawDuration;
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
    );
  }
}
