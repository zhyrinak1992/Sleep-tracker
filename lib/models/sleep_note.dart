class SleepNote {
  const SleepNote({
    required this.id,
    required this.sessionId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.sessionStartedAt,
  });

  final String id;
  final String sessionId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime sessionStartedAt;

  factory SleepNote.fromMap(Map<String, Object?> map) => SleepNote(
        id: map['id']! as String,
        sessionId: map['session_id']! as String,
        text: map['body']! as String,
        createdAt: DateTime.parse(map['created_at']! as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at']! as String).toLocal(),
        sessionStartedAt:
            DateTime.parse(map['session_started_at']! as String).toLocal(),
      );
}
