class DaytimeSleepEntry {
  const DaytimeSleepEntry({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    this.note = '',
  }) : assert(endedAt.isAfter(startedAt));

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String note;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'note': note,
  };

  static DaytimeSleepEntry? tryParse(Object? value) {
    if (value is! Map) return null;
    try {
      final id = value['id'];
      final started = value['startedAt'];
      final ended = value['endedAt'];
      if (id is! String || id.isEmpty || started is! String || ended is! String) return null;
      final start = DateTime.parse(started);
      final end = DateTime.parse(ended);
      if (!end.isAfter(start)) return null;
      return DaytimeSleepEntry(
        id: id,
        startedAt: start,
        endedAt: end,
        note: value['note'] is String ? value['note'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }
}
