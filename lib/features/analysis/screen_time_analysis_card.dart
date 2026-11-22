import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../models/screen_time_entry.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'screen_time_sleep_analysis.dart';

class ScreenTimeAnalysisCard extends StatelessWidget {
  const ScreenTimeAnalysisCard({
    super.key,
    required this.database,
    required this.sessions,
  });

  final SleepDatabase database;
  final List<SleepSession> sessions;

  Future<List<ScreenTimeSleepGroup>> _load() async {
    final metadata = await database.getAppMetadataByPrefix('sleep_tracker_screen_time_v1_');
    final entries = <String, ScreenTimeEntry>{};
    for (final session in sessions) {
      final raw = metadata['sleep_tracker_screen_time_v1_${session.id}'];
      if (raw == null || raw.isEmpty) continue;
      try {
        final entry = ScreenTimeEntry.decode(raw);
        if (entry.sessionId == session.id) entries[session.id] = entry;
      } catch (_) {
        // A damaged optional note must not affect other sleep records.
      }
    }
    return ScreenTimeSleepAnalysis.summarize(
      sessions: sessions,
      entries: entries,
    );
  }

  String _duration(double minutes) {
    final value = minutes.round();
    return '${value ~/ 60} ч ${value % 60} мин';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ScreenTimeSleepGroup>>(
    future: _load(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: LinearProgressIndicator());
      }
      if (snapshot.hasError) {
        return SectionCard(child: Text('Не удалось загрузить отметки экранного времени: ${snapshot.error}'));
      }
      final groups = snapshot.data ?? const <ScreenTimeSleepGroup>[];
      final total = groups.fold<int>(0, (sum, group) => sum + group.nights);
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Экранное время и сон', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Сопоставление по ручным отметкам времени последнего использования экрана перед началом сна. Автоматическая история приложений не собирается.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (groups.isEmpty)
            const Text('Пока недостаточно ручных отметок для сопоставления.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12))
          else ...[
            Text('Ночей с корректными отметками: $total',
              style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600)),
            const Divider(height: 18, color: AppTheme.surfaceLight),
            ...groups.map((group) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${group.label} до сна · ${group.nights} ноч.',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text('Средняя длительность сна: ${_duration(group.averageSleepMinutes)}',
                    style: const TextStyle(fontSize: 12)),
                  Text('Среднее экранное время: ${group.averageScreenMinutes.round()} мин',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                ],
              ),
            )),
            const SizedBox(height: 7),
            const Text(
              'Это описательное сопоставление небольших групп, а не доказательство причинного влияния экранов на сон. Группы без записей не отображаются; отсутствующие значения не заменяются нулями.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ));
    },
  );
}
