import 'dart:convert';

class ScreenTimeEntry {
  const ScreenTimeEntry({
    required this.sessionId,
    required this.windowMinutes,
    this.screenMinutes,
    this.lastUseAt,
    required this.updatedAt,
    this.source = 'manual',
  });

  static const supportedWindowMinutes = <int>[30, 60, 120];
  static const storagePrefix = 'sleep_tracker_screen_time_v2_';

  final String sessionId;
  final int windowMinutes;
  final int? screenMinutes;
  final DateTime? lastUseAt;
  final DateTime updatedAt;
  final String source;

  String get storageKey => keyFor(sessionId, windowMinutes);
  bool get hasData => screenMinutes != null || lastUseAt != null;

  static String keyFor(String sessionId, int windowMinutes) =>
      '$storagePrefix${sessionId}_$windowMinutes';

  Map<String, Object?> toMap() => {
    'schemaVersion': 2,
    'sessionId': sessionId,
    'windowMinutes': windowMinutes,
    'screenMinutes': screenMinutes,
    'lastUseAt': lastUseAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'source': source,
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
    if (value.isAfter(sleepStart)) value = value.subtract(const Duration(days: 1));
    final elapsed = sleepStart.difference(value);
    if (elapsed.isNegative || elapsed > const Duration(hours: 24)) {
      throw const FormatException('Время должно находиться в пределах 24 часов до засыпания.');
    }
    return value;
  }

  void validateForSleepStart(DateTime sleepStart) {
    if (lastUseAt == null) return;
    final elapsed = sleepStart.difference(lastUseAt!);
    if (elapsed.isNegative || elapsed > const Duration(hours: 24)) {
      throw const FormatException('Время последнего использования должно быть не позже засыпания и не старше 24 часов.');
    }
  }

  factory ScreenTimeEntry.decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> || value['schemaVersion'] != 2) {
      throw const FormatException('Некорректная запись экранного времени.');
    }
    final sessionId = value['sessionId'];
    final window = value['windowMinutes'];
    final minutes = value['screenMinutes'];
    final lastUse = value['lastUseAt'];
    final updated = value['updatedAt'];
    final sourceType = value['source'];
    if (sessionId is! String || sessionId.trim().isEmpty ||
        window is! int || !supportedWindowMinutes.contains(window) ||
        (minutes != null && (minutes is! int || minutes < 0 || minutes > window)) ||
        (lastUse != null && lastUse is! String) ||
        updated is! String || sourceType != 'manual' ||
        (minutes == null && lastUse == null)) {
      throw const FormatException('Поля ручной отметки экранного времени повреждены.');
    }
    final lastUseAt = lastUse == null ? null : DateTime.tryParse(lastUse);
    final updatedAt = DateTime.tryParse(updated);
    if ((lastUse != null && lastUseAt == null) || updatedAt == null) {
      throw const FormatException('Некорректная дата ручной отметки экранного времени.');
    }
    return ScreenTimeEntry(
      sessionId: sessionId,
      windowMinutes: window,
      screenMinutes: minutes as int?,
      lastUseAt: lastUseAt?.toLocal(),
      updatedAt: updatedAt.toLocal(),
      source: sourceType as String,
    );
  }
}