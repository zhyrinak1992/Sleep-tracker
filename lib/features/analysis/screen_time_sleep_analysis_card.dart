import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../models/screen_time_entry.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'screen_time_sleep_analysis.dart';

class ScreenTimeSleepAnalysisCard extends StatefulWidget {
  const ScreenTimeSleepAnalysisCard({
    super.key,
    required this.database,
    required this.sessions,
  });

  final SleepDatabase database;
  final List<SleepSession> sessions;

  @override
  State<ScreenTimeSleepAnalysisCard> createState() => _ScreenTimeSleepAnalysisCardState();
}

class _ScreenTimeSleepAnalysisCardState extends State<ScreenTimeSleepAnalysisCard> {
  late Future<List<ScreenTimeSleepSample>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ScreenTimeSleepAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _future = _load();
    }
  }

  Future<List<ScreenTimeSleepSample>> _load() async {
    final stored = await widget.database.getAppMetadataByPrefix('sleep_tracker_screen_time_v1_');
    final result = <ScreenTimeSleepSample>[];
    for (final session in widget.sessions) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      if (end == null || !end.isAfter(start)) continue;
      final raw = stored['sleep_tracker_screen_time_v1_${session.id}'];
      if (raw == null || raw.isEmpty) continue;
      try {
        final entry = ScreenTimeEntry.decode(raw);
        if (entry.sessionId != session.id || entry.lastUseAt.isAfter(start)) continue;
        final gap = start.difference(entry.lastUseAt).inMinutes;
        if (gap < 0 || gap > 1440) continue;
        result.add(ScreenTimeSleepSample(
          screenMinutes: entry.durationMinutes.toDouble(),
          lastUseGapMinutes: gap.toDouble(),
          sleepMinutes: end.difference(start).inMinutes.toDouble(),
        ));
      } on FormatException {
        // A damaged optional entry is ignored; it is never rewritten here.
      }
    }
    return result;
  }

  String _duration(double minutes) {
    final rounded = minutes.round();
    return '${rounded ~/ 60} ч ${rounded % 60} мин';
  }

  String _minutes(double value) => '${value.round()} мин';

  Widget _group(String title, ScreenTimeSleepGroupSummary summary) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title · ${summary.nights} ноч.',
        style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      _row('Среднее использование экранов', _minutes(summary.averageScreenMinutes)),
      _row('От последнего использования до сна', _minutes(summary.averageLastUseGapMinutes)),
      _row('Средняя продолжительность сна', _duration(summary.averageSleepMinutes)),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ScreenTimeSleepSample>>(
    future: _future,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: LinearProgressIndicator());
      }
      if (state.hasError) {
        return SectionCard(child: Text('Не удалось загрузить отметки экранного времени: ${state.error}'));
      }
      final samples = state.data ?? const <ScreenTimeSleepSample>[];
      final comparison = ScreenTimeSleepComparison.fromSamples(samples);
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Экранное время и сон',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('Ночей с ручными отметками: ${samples.length}',
            style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
          const SizedBox(height: 10),
          if (comparison == null)
            const Text(
              'Для сравнения нужны отметки минимум по четырём завершённым ночам. Заполни длительность использования экранов и время последнего использования в карточках ночей.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
            )
          else ...[
            _group('Меньше экранного времени', comparison.belowMedian),
            const Divider(height: 20, color: AppTheme.surfaceLight),
            _group('Не меньше экранного времени', comparison.atOrAboveMedian),
            const SizedBox(height: 8),
            const Text(
              'Группы разделены по медиане ручных оценок в выбранном периоде. Сравнение описательное и не доказывает причинного влияния экранов на сон.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ));
    },
  );
}
