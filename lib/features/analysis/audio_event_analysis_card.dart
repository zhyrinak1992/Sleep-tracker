import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  String _categoryLabel(String value) => switch (value) {
    'snore' || 'snoring' => 'Храп',
    'speech' || 'talking' => 'Разговоры во сне',
    'cough' => 'Кашель',
    'laugh' || 'laughter' => 'Смех',
    'groan' || 'moan' => 'Стоны',
    'sobbing' || 'crying' => 'Всхлипывания',
    'noise' => 'Другие звуки',
    'unknown' => 'Неопределённый звук',
    _ => value,
  };

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
      final sessionsById = {for (final session in widget.currentSessions) session.id: session};
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
          const Text('Зарегистрированные звуковые события по ночам выбранного периода', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
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
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
              title: Text(_categoryLabel(category), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Сейчас: ${current.categoryCounts[category] ?? 0} · ${_duration(current.categoryDurationMs[category] ?? 0)}'
                '   Пред.: ${previous.categoryCounts[category] ?? 0} · ${_duration(previous.categoryDurationMs[category] ?? 0)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
              children: [
                if ((current.categoryEvents[category] ?? const []).isEmpty)
                  const ListTile(
                    dense: true,
                    title: Text('В выбранном периоде событий этой категории нет.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  )
                else
                  ...(current.categoryEvents[category] ?? const []).map((event) {
                    final captured = DateTime.tryParse(event['captured_at'] as String? ?? '');
                    final sessionId = event['session_id'] as String?;
                    final session = sessionId == null ? null : sessionsById[sessionId];
                    final rawDuration = event['duration_ms'];
                    final duration = rawDuration is int && rawDuration > 0 ? rawDuration : 0;
                    final confidence = event['confidence'];
                    final corrected = event['user_corrected'] == 1;
                    final details = <String>[
                      if (session != null) 'Ночь ${DateFormat('dd.MM.yyyy').format(session.startedAt)}',
                      _duration(duration),
                      if (confidence is num && confidence.isFinite && !corrected)
                        'уверенность ${(confidence * 100).round()}%',
                      if (corrected) 'категория исправлена вручную',
                    ];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        captured == null ? 'Время события не указано' : DateFormat('dd.MM.yyyy · HH:mm').format(captured.toLocal()),
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(details.join(' · '),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    );
                  }),
              ],
            ),
          const SizedBox(height: 8),
          const Text('Длительность рассчитывается по метаданным зарегистрированных коротких сегментов, а не по общему времени работы микрофона. Сами аудиофайлы хранятся 7 дней; статистика событий остаётся в истории. Категории берутся из фактических меток классификатора.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
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
