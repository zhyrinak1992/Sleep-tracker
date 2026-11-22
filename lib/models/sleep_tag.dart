import 'dart:convert';

import 'package:uuid/uuid.dart';

class SleepTag {
  const SleepTag(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;
  static const catalog = <SleepTag>[
    SleepTag('stress', 'Стресс', 'Напряжение, тревога, эмоциональная нагрузка'),
    SleepTag('activity', 'Физическая активность', 'Тренировка, прогулка, нагрузка'),
    SleepTag('nutrition', 'Питание', 'Поздний или непривычный приём пищи'),
    SleepTag('caffeine', 'Кофеин', 'Кофе, чай или энергетические напитки'),
    SleepTag('wellbeing', 'Самочувствие', 'Общее состояние в течение дня'),
    SleepTag('illness', 'Недомогание', 'Болезнь или неприятные симптомы'),
    SleepTag('environment', 'Обстановка', 'Шум, свет, температура помещения'),
    SleepTag('schedule', 'Режим дня', 'Смена графика или необычное расписание'),
    SleepTag('travel', 'Поездка', 'Дорога, смена места или часового пояса'),
  ];
  static SleepTag? byKey(String key) {
    for (final tag in catalog) { if (tag.key == key) return tag; }
    return null;
  }
}

/// Stores user-confirmed categories without a SQLite schema migration.
class CustomSleepTagStore {
  CustomSleepTagStore(this._read, this._write);

  static const metadataKey = 'custom_sleep_tags_v1';
  static const _uuid = Uuid();

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  Future<List<SleepTag>> load() async {
    final raw = await _read(metadataKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Список пользовательских категорий повреждён.');
    }
    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Пользовательская категория повреждена.');
      }
      final key = item['key'];
      final label = item['label'];
      if (key is! String || !key.startsWith('custom_') ||
          label is! String || label.trim().isEmpty) {
        throw const FormatException('Пользовательская категория повреждена.');
      }
      return SleepTag(key, label.trim(), 'Пользовательская категория');
    }).toList();
  }

  Future<List<SleepTag>> add(String label) async {
    final normalized = label.trim().toLowerCase();
    if (normalized.isEmpty) throw ArgumentError('Название категории не может быть пустым.');
    final tags = await load();
    if (SleepTag.catalog.any((tag) => tag.label.toLowerCase() == normalized) ||
        tags.any((tag) => tag.label.toLowerCase() == normalized)) {
      throw StateError('Такая категория уже существует.');
    }
    final tag = SleepTag('custom_${_uuid.v4()}', label.trim(), 'Пользовательская категория');
    final updated = [...tags, tag];
    await _write(metadataKey, jsonEncode(updated.map((item) => {
      'key': item.key,
      'label': item.label,
    }).toList()));
    return updated;
  }
}
