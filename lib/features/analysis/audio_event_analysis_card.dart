import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'audio_event_analysis.dart';

class AudioEventAnalysisCard extends StatefulWidget {
  const AudioEventAnalysisCard({
    super.key,
    required this.database,
    required this.currentSessions,
    required this.previousSessions,
  });

  final SleepDatabase database;
  final List<SleepSession> currentSessions;
  final List<SleepSession> previousSessions;

  @override
  State<AudioEventAnalysisCard> createState() => _AudioEventAnalysisCardState();
}

class _AudioEventAnalysisCardState extends State<AudioEventAnalysisCard> {
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.database.getAudioEvents();
  }

  @override
  void didUpdateWidget(covariant AudioEventAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.database != widget.database ||
        !identical(oldWidget.currentSessions, widget.currentSessions) ||
        !identical(oldWidget.previousSessions, widget.previousSessions)) {
      _future = widget.database.getAudioEvents();
    }
  }

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes == 0) return '$remainder с';
    return '$minutes мин ${remainder.toString().padLeft(2, '0')} с';
  }

  String _categoryLabel(String value) =>
      value == 'unknown' ? 'Неопределённый звук' : value;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return SectionCard(child: Text('Не удалось загрузить звуковые события: ${snapshot.error}'));
      }
      final events = snapshot.data ?? const <Map<String, Object?>>[];
      final currentIds = widget.currentSessions.map((item) => item.id).toSet();
      final previousIds = widget.previousSessions.map((item) => item.id).toSet();
      final current = AudioEventPeriodSummary.summarize(events: events, sessionIds: currentIds);
      final previous = AudioEventPeriodSummary.summarize(events: events, sessionIds: previousIds);
      if (current.eventCount == 0 && previous.eventCount == 0) {
        return const SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Звуковые события', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('В выбранном и предыдущем периодах зарегистрированных событий нет. Это не означает, что наблюдение не велось.', style: TextStyle(color: AppTheme.muted, height: 1.4)),
          ],
        ));
      }
      final categories = current.categoryCounts.keys.toSet().union(previous.categoryCounts.keys.toSet()).toList()
        ..sort((a, b) {
          final byCount = (current.categoryCounts[b] ?? 0).compareTo(current.categoryCounts[a] ?? 0);
          if (byCount != 0) return byCount;
          return a.compareTo(b);
        });
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Звуковые события', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Сохранённые и классифицированные фрагменты по ночам выбранного периода', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat(label: 'Событий', value: '${current.eventCount}', previous: previous.eventCount)),
            const SizedBox(width: 12),
            Expanded(child: _Stat(label: 'Ночей с событиями', value: '${current.nightsWithEvents}', previous: previous.nightsWithEvents)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Фрагменты: ${_duration(current.savedDurationMs)}', style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('Пред.: ${_duration(previous.savedDurationMs)}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(_categoryLabel(category), style: const TextStyle(color: AppTheme.muted))),
                Text('${current.categoryCounts[category] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(width: 66, child: Text('пред. ${previous.categoryCounts[category] ?? 0}', textAlign: TextAlign.end, style: const TextStyle(color: AppTheme.muted, fontSize: 11))),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('Длительность — только сохранённые короткие аудиофрагменты, не общее время работы микрофона. Категории показываются по фактическим меткам классификатора; неопределённые события не исключаются.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
        ],
      ));
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.previous});
  final String label;
  final String value;
  final int previous;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      const SizedBox(height: 3),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Flexible(child: Text('пред. $previous', style: const TextStyle(color: AppTheme.muted, fontSize: 11))),
      ]),
    ],
  );
}
