import 'dart:convert';

import '../../models/sleep_note.dart';
import '../../models/sleep_tag.dart';

class NoteTagSuggestion {
  const NoteTagSuggestion({required this.phrase, required this.nightCount});

  final String phrase;
  final int nightCount;
}

class NoteTagSuggestionAnalyzer {
  static const minimumNights = 3;
  static const _stopWords = <String>{
    'это', 'как', 'что', 'для', 'или', 'при', 'после', 'перед', 'очень',
    'было', 'была', 'были', 'есть', 'нет', 'мне', 'меня', 'мной', 'моя',
    'мой', 'мои', 'его', 'ее', 'они', 'она', 'оно', 'так', 'там', 'тут',
    'уже', 'еще', 'ещё', 'весь', 'все', 'всё', 'этот', 'эта', 'эти',
    'день', 'ночь', 'сегодня', 'вчера', 'завтра', 'утром', 'вечером',
    'ночью', 'спала', 'спал', 'спать', 'сон', 'сна', 'сном',
    'хорошо', 'плохо', 'нормально', 'просто', 'сильно', 'немного',
    'снова', 'каждый', 'каждая', 'каждое', 'каждые', 'обычно', 'вроде',
    'может', 'можно', 'нужно', 'стало', 'стала', 'стали', 'бывает',
  };

  static List<NoteTagSuggestion> analyze({
    required Iterable<SleepNote> notes,
    required Iterable<SleepTag> existingTags,
    Set<String> dismissedPhrases = const {},
    int limit = 5,
  }) {
    final existing = existingTags.map((tag) => _normalize(tag.label)).toSet();
    final dismissed = dismissedPhrases.map(_normalize).toSet();
    final usage = <String, Set<String>>{};

    for (final note in notes) {
      final tokens = RegExp(r'[a-zа-яё0-9]+', caseSensitive: false)
          .allMatches(note.text.toLowerCase())
          .map((match) => match.group(0)!)
          .toList();
      final candidates = <String>{};
      for (var i = 0; i < tokens.length; i++) {
        final first = tokens[i];
        if (first.length >= 3 && !_stopWords.contains(first)) candidates.add(first);
        if (i + 1 < tokens.length) {
          final pair = [tokens[i], tokens[i + 1]];
          if (pair.every((token) => token.length >= 3 && !_stopWords.contains(token))) {
            candidates.add(pair.join(' '));
          }
        }
        if (i + 2 < tokens.length) {
          final phrase = [tokens[i], tokens[i + 1], tokens[i + 2]];
          if (phrase.every((token) => token.length >= 3 && !_stopWords.contains(token))) {
            candidates.add(phrase.join(' '));
          }
        }
      }
      for (final phrase in candidates) {
        final normalized = _normalize(phrase);
        if (normalized.length < 5 || existing.contains(normalized) || dismissed.contains(normalized)) {
          continue;
        }
        usage.putIfAbsent(normalized, () => <String>{}).add(note.sessionId);
      }
    }

    final suggestions = usage.entries
        .where((entry) => entry.value.length >= minimumNights)
        .map((entry) => NoteTagSuggestion(phrase: entry.key, nightCount: entry.value.length))
        .toList()
      ..sort((a, b) {
        final byNights = b.nightCount.compareTo(a.nightCount);
        if (byNights != 0) return byNights;
        final byPhraseWords = b.phrase.split(' ').length.compareTo(a.phrase.split(' ').length);
        return byPhraseWords != 0 ? byPhraseWords : b.phrase.length.compareTo(a.phrase.length);
      });

    // Keep one concise phrase when it is contained in a longer candidate
    // with the same coverage, avoiding a wall of near-duplicate suggestions.
    final selected = <NoteTagSuggestion>[];
    for (final candidate in suggestions) {
      final redundant = selected.any((item) =>
          item.nightCount == candidate.nightCount &&
          (' ${item.phrase} ').contains(' ${candidate.phrase} '));
      if (!redundant) selected.add(candidate);
      if (selected.length >= limit) break;
    }
    return selected;
  }

  static String _normalize(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

class DismissedNoteTagSuggestionStore {
  DismissedNoteTagSuggestionStore(this._read, this._write);

  static const metadataKey = 'dismissed_note_tag_suggestions_v1';
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  Future<Set<String>> load() async {
    final raw = await _read(metadataKey);
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw const FormatException('Список отклонённых предложений повреждён.');
    }
    return decoded.cast<String>().toSet();
  }

  Future<void> dismiss(String phrase) async {
    final phrases = await load();
    phrases.add(NoteTagSuggestionAnalyzer._normalize(phrase));
    await _write(metadataKey, jsonEncode(phrases.toList()..sort()));
  }
}
