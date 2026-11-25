import 'dart:convert';

/// Persistent library of user-created labels for the health day calendar.
/// Historical day entries keep their own text labels when the library changes.
class HealthDayTagLibrary {
  const HealthDayTagLibrary._();

  static const storageKey = 'health_custom_day_tags_v1';

  static List<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw const FormatException('Список пользовательских отметок повреждён.');
    }
    return decoded
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  static String encode(Iterable<String> tags) {
    final normalized = tags
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return jsonEncode(normalized);
  }

  static List<String> add(Iterable<String> existing, String label) {
    final value = label.trim();
    if (value.isEmpty) return existing.toSet().toList()..sort();
    return {...existing, value}.toList()..sort();
  }

  static List<String> rename(
    Iterable<String> existing,
    String oldLabel,
    String newLabel,
  ) {
    final current = existing.toSet();
    final next = newLabel.trim();
    if (!current.contains(oldLabel)) {
      throw ArgumentError.value(oldLabel, 'oldLabel', 'Отметка не найдена.');
    }
    if (next.isEmpty) {
      throw ArgumentError.value(newLabel, 'newLabel', 'Название не может быть пустым.');
    }
    if (next != oldLabel && current.contains(next)) {
      throw ArgumentError.value(newLabel, 'newLabel', 'Такая отметка уже существует.');
    }
    current.remove(oldLabel);
    current.add(next);
    return current.toList()..sort();
  }

  static List<String> remove(Iterable<String> existing, String label) =>
      existing.where((value) => value != label).toSet().toList()..sort();
}
