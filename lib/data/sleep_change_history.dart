class SleepChangeHistoryRecords {
  SleepChangeHistoryRecords._();

  /// Adds a new immutable monthly version only when the source fingerprint changed.
  static ({List<Map<String, Object?>> records, bool changed}) append(
    List<Map<String, Object?>> existing,
    Map<String, Object?> snapshot,
  ) {
    final key = snapshot['periodKey'];
    final fingerprint = snapshot['fingerprint'];
    if (key is! String || key.isEmpty || fingerprint is! String || fingerprint.isEmpty) {
      throw ArgumentError('У снимка истории отсутствует ключ периода или отпечаток данных.');
    }
    final samePeriod = existing.where((item) => item['periodKey'] == key).toList();
    if (samePeriod.any((item) => item['fingerprint'] == fingerprint)) {
      return (records: List.unmodifiable(existing), changed: false);
    }
    final latestVersion = samePeriod.fold<int>(0, (value, item) {
      final version = item['version'];
      return version is int && version > value ? version : value;
    });
    final stored = Map<String, Object?>.from(snapshot)
      ..['version'] = latestVersion + 1
      ..['supersedesVersion'] = latestVersion == 0 ? null : latestVersion
      ..['revisionReason'] = latestVersion == 0
          ? 'Первичный снимок месяца'
          : 'Изменились исходные данные или состав сопоставимых наблюдений';
    return (records: List.unmodifiable([...existing, stored]), changed: true);
  }

  /// Returns one latest revision per calendar month, preserving chronological order.
  static List<Map<String, Object?>> latestPerMonth(
    Iterable<Map<String, Object?>> history,
  ) {
    final byMonth = <String, Map<String, Object?>>{};
    for (final item in history) {
      final key = item['periodKey'];
      if (key is! String) continue;
      final existing = byMonth[key];
      final version = item['version'] is int ? item['version'] as int : 1;
      final existingVersion = existing?['version'] is int ? existing!['version'] as int : 0;
      if (existing == null || version > existingVersion) byMonth[key] = item;
    }
    final result = byMonth.values.toList()
      ..sort((a, b) => (a['periodKey'] as String).compareTo(b['periodKey'] as String));
    return result;
  }
}
