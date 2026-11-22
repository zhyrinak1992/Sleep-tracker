import 'dart:convert';

class ScreenTimeEntry {
  const ScreenTimeEntry({
    required this.sessionId,
    required this.durationMinutes,
    required this.lastUseAt,
    required this.updatedAt,
  });

  final String sessionId;
  final int durationMinutes;
  final DateTime lastUseAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'durationMinutes': durationMinutes,
    'lastUseAt': lastUseAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toMap());

  static DateTime resolveLastUseTime(
    DateTime sleepStart, {
    required int hour,
    required int minute,
  }) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('Некорректное время последнего использования.');
    }
    var value = DateTime(sleepStart.year, sleepStart.month, sleepStart.day, hour, minute);
    if (value.isAfter(sleepStart)) {
      value = value.subtract(const Duration(days: 1));
    }
    final elapsed = sleepStart.difference(value);
    if (elapsed.isNegative || elapsed > const Duration(hours: 24)) {
      throw const FormatException('Время должно находиться в пределах 24 часов до начала сна.');
    }
    return value;
  }

  factory ScreenTimeEntry.decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map) throw const FormatException('Некорректная запись экранного времени.');
    final sessionId = value['sessionId'];
    final duration = value['durationMinutes'];
    final lastUse = value['lastUseAt'];
    final updated = value['updatedAt'];
    if (sessionId is! String || sessionId.isEmpty ||
        duration is! int || duration < 0 || duration > 360 ||
        lastUse is! String || updated is! String) {
      throw const FormatException('Некорректные поля записи экранного времени.');
    }
    final lastUseAt = DateTime.tryParse(lastUse);
    final updatedAt = DateTime.tryParse(updated);
    if (lastUseAt == null || updatedAt == null) {
      throw const FormatException('Некорректная дата записи экранного времени.');
    }
    return ScreenTimeEntry(
      sessionId: sessionId,
      durationMinutes: duration,
      lastUseAt: lastUseAt.toLocal(),
      updatedAt: updatedAt.toLocal(),
    );
  }
}
