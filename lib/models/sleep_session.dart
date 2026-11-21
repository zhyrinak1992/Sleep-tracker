class SleepSession {
  const SleepSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.source = 'manual',
    this.note,
    this.morningRating,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String source;
  final String? note;
  final int? morningRating;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOpen => endedAt == null;
  Duration? get duration => endedAt?.difference(startedAt);

  Map<String, Object?> toMap() => {
    'id': id,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'source': source,
    'note': note,
    'morning_rating': morningRating,
    'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  factory SleepSession.fromMap(Map<String, Object?> map) => SleepSession(
    id: map['id']! as String,
    startedAt: DateTime.parse(map['started_at']! as String).toLocal(),
    endedAt: map['ended_at'] == null
        ? null
        : DateTime.parse(map['ended_at']! as String).toLocal(),
    source: map['source'] as String? ?? 'manual',
    note: map['note'] as String?,
    morningRating: map['morning_rating'] as int?,
    createdAt: map['created_at'] == null
        ? null
        : DateTime.parse(map['created_at']! as String).toLocal(),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.parse(map['updated_at']! as String).toLocal(),
  );
}
