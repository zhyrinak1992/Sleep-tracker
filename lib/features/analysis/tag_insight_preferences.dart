import 'dart:convert';

class TagInsightLabel {
  const TagInsightLabel({required this.tagLabel, required this.metricLabel});
  final String tagLabel;
  final String metricLabel;

  Map<String, Object?> toMap() => {'tagLabel': tagLabel, 'metricLabel': metricLabel};

  factory TagInsightLabel.fromMap(Map<String, dynamic> map) {
    final tagLabel = map['tagLabel'];
    final metricLabel = map['metricLabel'];
    if (tagLabel is! String || tagLabel.trim().isEmpty ||
        metricLabel is! String || metricLabel.trim().isEmpty) {
      throw const FormatException('Подпись скрытой закономерности повреждена.');
    }
    return TagInsightLabel(tagLabel: tagLabel, metricLabel: metricLabel);
  }
}

class TagInsightPreferences {
  const TagInsightPreferences({this.hidden = const {}, this.pinned = const []});
  final Map<String, TagInsightLabel> hidden;
  final List<String> pinned;
  bool isHidden(String id) => hidden.containsKey(id);
  bool isPinned(String id) => pinned.contains(id);
}

class TagInsightPreferenceStore {
  TagInsightPreferenceStore(this._read, this._write);
  static const metadataKey = 'tag_insight_preferences_v1';
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  static String identity(String tagKey, String metricKey) => jsonEncode([tagKey, metricKey]);

  Future<TagInsightPreferences> load() async {
    final raw = await _read(metadataKey);
    if (raw == null || raw.isEmpty) return const TagInsightPreferences();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1 ||
        decoded['hidden'] is! Map<String, dynamic> || decoded['pinned'] is! List) {
      throw const FormatException('Настройки закономерностей повреждены.');
    }
    final hidden = <String, TagInsightLabel>{};
    for (final entry in (decoded['hidden'] as Map<String, dynamic>).entries) {
      if (!_isValidIdentity(entry.key) || entry.value is! Map<String, dynamic>) {
        throw const FormatException('Список скрытых закономерностей повреждён.');
      }
      hidden[entry.key] = TagInsightLabel.fromMap(entry.value as Map<String, dynamic>);
    }
    final rawPinned = decoded['pinned'] as List;
    if (rawPinned.any((item) => item is! String || item.isEmpty) ||
        rawPinned.toSet().length != rawPinned.length) {
      throw const FormatException('Список закреплённых закономерностей повреждён.');
    }
    return TagInsightPreferences(
      hidden: Map.unmodifiable(hidden),
      pinned: List.unmodifiable(rawPinned.cast<String>()),
    );
  }

  bool _isValidIdentity(String id) {
    try {
      final decoded = jsonDecode(id);
      return decoded is List && decoded.length == 2 &&
          decoded.every((item) => item is String && item.trim().isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<TagInsightPreferences> hide({
    required String tagKey, required String metricKey,
    required String tagLabel, required String metricLabel,
  }) async {
    if (tagKey.trim().isEmpty || metricKey.trim().isEmpty ||
        tagLabel.trim().isEmpty || metricLabel.trim().isEmpty) {
      throw ArgumentError('Для скрытия закономерности нужны категория и показатель.');
    }
    final current = await load();
    final hidden = Map<String, TagInsightLabel>.from(current.hidden)
      ..[identity(tagKey, metricKey)] = TagInsightLabel(tagLabel: tagLabel, metricLabel: metricLabel);
    return _save(TagInsightPreferences(hidden: Map.unmodifiable(hidden), pinned: current.pinned));
  }

  Future<TagInsightPreferences> restore(String id) async {
    final current = await load();
    final hidden = Map<String, TagInsightLabel>.from(current.hidden)..remove(id);
    return _save(TagInsightPreferences(hidden: Map.unmodifiable(hidden), pinned: current.pinned));
  }

  Future<TagInsightPreferences> pin({
    required String tagKey, required String metricKey,
    required String tagLabel, required String metricLabel,
  }) async {
    if (tagKey.trim().isEmpty || metricKey.trim().isEmpty ||
        tagLabel.trim().isEmpty || metricLabel.trim().isEmpty) {
      throw ArgumentError('Для закрепления закономерности нужны категория и показатель.');
    }
    final current = await load();
    final id = identity(tagKey, metricKey);
    if (current.pinned.contains(id)) return current;
    return _save(TagInsightPreferences(
      hidden: current.hidden, pinned: List.unmodifiable([...current.pinned, id]),
    ));
  }

  Future<TagInsightPreferences> unpin({
    required String tagKey, required String metricKey,
  }) async {
    final current = await load();
    final id = identity(tagKey, metricKey);
    return _save(TagInsightPreferences(
      hidden: current.hidden,
      pinned: List.unmodifiable(current.pinned.where((item) => item != id)),
    ));
  }

  Future<TagInsightPreferences> _save(TagInsightPreferences preferences) async {
    await _write(metadataKey, jsonEncode({
      'schemaVersion': 1,
      'hidden': preferences.hidden.map((key, value) => MapEntry(key, value.toMap())),
      'pinned': preferences.pinned,
    }));
    return preferences;
  }
}