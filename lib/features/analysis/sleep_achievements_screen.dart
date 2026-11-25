import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_achievement_service.dart';
import 'sleep_personal_records.dart';

class _RecordRow {
  const _RecordRow(this.title, this.value, this.date, this.icon);
  final String title;
  final String value;
  final String date;
  final IconData icon;
}

class _TimelineEntry {
  const _TimelineEntry(this.date, this.title, this.detail, this.icon);
  final DateTime date;
  final String title;
  final String detail;
  final IconData icon;
}

class SleepAchievementsScreen extends StatefulWidget {
  const SleepAchievementsScreen({super.key, required this.sessions});

  final List<SleepSession> sessions;

  @override
  State<SleepAchievementsScreen> createState() => _SleepAchievementsScreenState();
}

class _SleepAchievementsScreenState extends State<SleepAchievementsScreen> {
  late Future<SleepAchievementState> _state;

  @override
  void initState() {
    super.initState();
    _state = SleepAchievementService.instance.load(widget.sessions);
  }

  @override
  void didUpdateWidget(covariant SleepAchievementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _state = SleepAchievementService.instance.load(widget.sessions);
    }
  }

  Future<void> _setDisplay(bool value) async {
    await SleepAchievementService.instance.setDisplayEnabled(value);
    if (!mounted) return;
    setState(() {
      _state = SleepAchievementService.instance.load(widget.sessions);
    });
  }

  String _duration(int? minutes) {
    if (minutes == null) return 'Ещё не установлен';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return remainder.toString() + ' мин';
    if (remainder == 0) return hours.toString() + ' ч';
    return hours.toString() + ' ч ' + remainder.toString() + ' мин';
  }

  String _recordTitle(String metric) => switch (metric) {
    'longestSleepMinutes' => 'Продолжительность сна',
    'bestSleepScore' => 'SleepScore',
    'bestEfficiencyPercent' => 'Эффективность сна',
    'fewestAwakenings' => 'Ночные пробуждения',
    _ => 'Личный рекорд',
  };

  String _recordValue(SleepPersonalRecordEvent event) => switch (event.metric) {
    'longestSleepMinutes' => _duration(event.value.round()),
    'bestSleepScore' => event.value.round().toString() + ' из 100',
    'bestEfficiencyPercent' => event.value.toStringAsFixed(1) + '%',
    'fewestAwakenings' => event.value.round().toString() + ' за ночь',
    _ => event.value.toString(),
  };

  String _recordChange(
    SleepPersonalRecordEvent event,
    SleepPersonalRecordEvent? previous,
  ) {
    if (previous == null) return 'Первый подтверждённый рекорд';
    final difference = event.metric == 'fewestAwakenings'
        ? previous.value - event.value
        : event.value - previous.value;
    if (difference <= 0) return 'Сохранено в истории';
    return switch (event.metric) {
      'longestSleepMinutes' => 'Улучшение на ' + _duration(difference.round()),
      'bestSleepScore' => '+' + difference.round().toString() + ' балл.',
      'bestEfficiencyPercent' => '+' + difference.toStringAsFixed(1) + ' п.п.',
      'fewestAwakenings' => 'На ' + difference.round().toString() + ' пробуждений меньше',
      _ => 'Рекорд улучшен',
    };
  }

  List<_RecordRow> _currentRecords(SleepPersonalRecords records) => [
    _RecordRow(
      'Самая продолжительная ночь',
      _duration(records.longestSleepMinutes),
      records.longestSleepAt == null
          ? ''
          : DateFormat('d MMM yyyy', 'ru').format(records.longestSleepAt!),
      Icons.bedtime_outlined,
    ),
    _RecordRow(
      'Лучшая оценка сна (SleepScore)',
      records.bestSleepScore == null
          ? 'Ещё не установлен'
          : records.bestSleepScore.toString() + ' из 100',
      records.bestSleepScoreAt == null
          ? ''
          : DateFormat('d MMM yyyy', 'ru').format(records.bestSleepScoreAt!),
      Icons.stars_rounded,
    ),
    _RecordRow(
      'Лучшая эффективность',
      records.bestEfficiencyPercent == null
          ? 'Ещё не установлен'
          : records.bestEfficiencyPercent!.toStringAsFixed(1) + '%',
      records.bestEfficiencyAt == null
          ? ''
          : DateFormat('d MMM yyyy', 'ru').format(records.bestEfficiencyAt!),
      Icons.trending_up_rounded,
    ),
    _RecordRow(
      'Минимум подтверждённых пробуждений',
      records.fewestAwakenings == null
          ? 'Ещё не установлен'
          : records.fewestAwakenings.toString() + ' за ночь',
      records.fewestAwakeningsAt == null
          ? ''
          : DateFormat('d MMM yyyy', 'ru').format(records.fewestAwakeningsAt!),
      Icons.nightlight_outlined,
    ),
  ];

  List<Widget> _categoryTiles(SleepAchievementState state) {
    final groups = <String, List<SleepAchievementDefinition>>{
      'История наблюдений': SleepAchievementCatalog.achievements
          .where((item) => item.completedNights > 0).toList(),
      'Утренние оценки': SleepAchievementCatalog.achievements
          .where((item) => item.morningRatings > 0).toList(),
      'Регулярность': SleepAchievementCatalog.achievements
          .where((item) => item.streakDays > 0).toList(),
    };
    return groups.entries.map((entry) {
      final earnedCount = entry.value
          .where((item) => state.earnedAt.containsKey(item.id)).length;
      return Card(
        color: AppTheme.surface,
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            'Получено ' + earnedCount.toString() + ' из ' + entry.value.length.toString(),
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          children: entry.value.map((achievement) {
            final date = state.earnedAt[achievement.id];
            final unlocked = date != null;
            return ListTile(
              dense: true,
              leading: Icon(
                unlocked ? Icons.check_circle : Icons.lock_outline,
                color: unlocked ? AppTheme.teal : AppTheme.muted,
              ),
              title: Text(
                achievement.title,
                style: TextStyle(
                  color: unlocked ? Colors.white : AppTheme.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                unlocked
                    ? achievement.description + ' Получено ' +
                        DateFormat('d MMM yyyy', 'ru').format(date) + '.'
                    : achievement.description,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  List<Widget> _chronologicalHistory(SleepAchievementState state) {
    final timeline = <_TimelineEntry>[];
    for (final entry in state.earnedAt.entries) {
      SleepAchievementDefinition? definition;
      for (final item in SleepAchievementCatalog.achievements) {
        if (item.id == entry.key) {
          definition = item;
          break;
        }
      }
      if (definition == null) continue;
      timeline.add(_TimelineEntry(
        entry.value,
        definition.title,
        definition.description,
        Icons.emoji_events_outlined,
      ));
    }

    final previousByMetric = <String, SleepPersonalRecordEvent>{};
    for (final event in state.recordHistory.where((event) => const {
      'longestSleepMinutes',
      'bestSleepScore',
      'bestEfficiencyPercent',
      'fewestAwakenings',
    }.contains(event.metric))) {
      final previous = previousByMetric[event.metric];
      timeline.add(_TimelineEntry(
        event.achievedAt,
        _recordTitle(event.metric),
        _recordValue(event) + ' · ' + _recordChange(event, previous),
        Icons.stars_rounded,
      ));
      previousByMetric[event.metric] = event;
    }
    timeline.sort((a, b) => b.date.compareTo(a.date));

    if (timeline.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'История пока пуста. Подтверждённые достижения и улучшения появятся здесь.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ),
      ];
    }

    return timeline.map((item) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: AppTheme.teal, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(item.detail,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
                Text(
                  DateFormat('d MMMM yyyy', 'ru').format(item.date),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    )).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мои достижения')),
    body: SafeArea(
      child: FutureBuilder<SleepAchievementState>(
        future: _state,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = snapshot.data!;
          final records = _currentRecords(state.records);
          final total = SleepAchievementCatalog.achievements.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Здесь собраны личные рекорды, полученные награды и хронология изменений. Учитываются только подтверждённые данные.',
                style: TextStyle(color: AppTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Личные рекорды',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        ),
                        Text(
                          state.earnedAt.length.toString() + ' / ' + total.toString(),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...records.map((record) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Icon(record.icon, color: AppTheme.teal, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(record.value,
                                    style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                                if (record.date.isNotEmpty)
                                  Text(record.date,
                                      style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: state.displayEnabled,
                      onChanged: _setDisplay,
                      title: const Text('Показывать достижения',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (state.displayEnabled) ...[
                      Text(
                        'Получено ' + state.earnedAt.length.toString() +
                            ' из ' + total.toString() + ' достижений',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      ..._categoryTiles(state),
                    ] else
                      const Text(
                        'Отображение достижений выключено. История получения сохраняется.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Хронологическая история',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ..._chronologicalHistory(state),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
