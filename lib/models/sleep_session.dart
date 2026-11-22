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
    this.deletedAt,
    this.buttonStartedAt,
    this.buttonEndedAt,
    this.actualSleepStartedAt,
    this.actualSleepEndedAt,
    this.userEdited = false,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String source;
  final String? note;
  final int? morningRating;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final DateTime? buttonStartedAt;
  final DateTime? buttonEndedAt;
  final DateTime? actualSleepStartedAt;
  final DateTime? actualSleepEndedAt;
  final bool userEdited;

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
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'button_started_at': buttonStartedAt?.toUtc().toIso8601String(),
    'button_ended_at': buttonEndedAt?.toUtc().toIso8601String(),
    'actual_sleep_started_at': actualSleepStartedAt?.toUtc().toIso8601String(),
    'actual_sleep_ended_at': actualSleepEndedAt?.toUtc().toIso8601String(),
    'user_edited': userEdited ? 1 : 0,
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
    deletedAt: map['deleted_at'] == null
        ? null
        : DateTime.parse(map['deleted_at']! as String).toLocal(),
    buttonStartedAt: map['button_started_at'] == null ? null : DateTime.parse(map['button_started_at']! as String).toLocal(),
    buttonEndedAt: map['button_ended_at'] == null ? null : DateTime.parse(map['button_ended_at']! as String).toLocal(),
    actualSleepStartedAt: map['actual_sleep_started_at'] == null ? null : DateTime.parse(map['actual_sleep_started_at']! as String).toLocal(),
    actualSleepEndedAt: map['actual_sleep_ended_at'] == null ? null : DateTime.parse(map['actual_sleep_ended_at']! as String).toLocal(),
    userEdited: (map['user_edited'] as int? ?? 0) == 1,
  );
}
