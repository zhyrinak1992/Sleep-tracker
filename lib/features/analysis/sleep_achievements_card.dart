import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_achievement_service.dart';
import 'sleep_personal_records.dart';

class SleepAchievementsCard extends StatefulWidget {
  const SleepAchievementsCard({super.key, required this.sessions});

  final List<SleepSession> sessions;

  @override
  State<SleepAchievementsCard> createState() => _SleepAchievementsCardState();
}

class _SleepAchievementsCardState extends State<SleepAchievementsCard> {
  late Future<SleepAchievementState> _state;

  @override
  void initState() {
    super.initState();
    _state = SleepAchievementService.instance.load(widget.sessions);
  }

  @override
  void didUpdateWidget(covariant SleepAchievementsCard oldWidget) {
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

  IconData _icon(String id) {
    switch (id) {
      case 'first_night':
        return Icons.nightlight_round;
      case 'seven_nights':
        return Icons.calendar_view_week;
      case 'thirty_nights':
        return Icons.calendar_month;
      case 'hundred_nights':
        return Icons.auto_awesome;
      case 'three_hundred_sixty_five_nights':
        return Icons.stars_rounded;
      case 'first_rating':
        return Icons.rate_review_outlined;
      case 'ten_ratings':
        return Icons.reviews_outlined;
      case 'streak_three':
      case 'streak_fourteen':
        return Icons.local_fire_department_outlined;
      case 'streak_seven':
        return Icons.calendar_view_week;
      case 'streak_thirty':
        return Icons.calendar_month;
      default:
        return Icons.emoji_events_outlined;
    }
  }

  String _duration(int? minutes) {
    if (minutes == null) return 'Пока нет достоверных данных';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return remainder.toString() + ' мин';
    if (remainder == 0) return hours.toString() + ' ч';
    return hours.toString() + ' ч ' + remainder.toString() + ' мин';
  }

  String _dayWord(int value) {
    final lastTwo = value % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'дней';
    switch (value % 10) {
      case 1: return 'день';
      case 2:
      case 3:
      case 4: return 'дня';
      default: return 'дней';
    }
  }

  String _recordSourceLabel(DateTime? achievedAt, String? sessionId) {
    if (achievedAt == null) return '';
    final date = DateFormat('d MMM yyyy', 'ru').format(achievedAt);
    final sourceExists = sessionId != null &&
        widget.sessions.any((session) => session.id == sessionId);
    return sourceExists ? date : date + ' · ночь удалена, рекорд сохранён';
  }

  Widget _personalRecordRow({
    required IconData icon,
    required String title,
    required String value,
    required String sourceLabel,
    required bool isNew,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(icon, color: AppTheme.teal, size: 20),
      const SizedBox(width: 9),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          if (sourceLabel.isNotEmpty)
            Text(sourceLabel, style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
        ],
      )),
      if (isNew) const Text('НОВЫЙ', style: TextStyle(
        color: AppTheme.teal, fontSize: 9, fontWeight: FontWeight.bold,
      )),
    ]),
  );

  String _recordTitle(String key) {
    switch (key) {
      case 'longestSleep': return 'самая продолжительная ночь';
      case 'bestEfficiency': return 'лучшая эффективность';
      case 'shortestLatency': return 'минимальная задержка засыпания';
      case 'longestStreak': return 'самая длинная серия';
      default: return 'личный рекорд';
    }
  }

  String _recordHistoryMetricLabel(String metric) => switch (metric) {
    'longestSleepMinutes' => 'Самая продолжительная ночь',
    'bestEfficiencyPercent' => 'Лучшая эффективность сна',
    'shortestLatencyMinutes' => 'Минимальная задержка засыпания',
    'longestStreakDays' => 'Самая длинная серия',
    _ => 'Личный рекорд',
  };

  String _recordHistoryValue(SleepPersonalRecordEvent event) =>
      switch (event.metric) {
        'longestSleepMinutes' => _duration(event.value.round()),
        'bestEfficiencyPercent' => '${event.value.toStringAsFixed(1)}%',
        'shortestLatencyMinutes' => _duration(event.value.round()),
        'longestStreakDays' =>
          '${event.value.round()} ${_dayWord(event.value.round())}',
        _ => event.value.toString(),
      };

  String _recordHistoryChange(
    SleepPersonalRecordEvent event,
    SleepPersonalRecordEvent? previous,
  ) {
    if (previous == null) return 'Первый зафиксированный рекорд';
    final improvement = event.metric == 'shortestLatencyMinutes'
        ? previous.value - event.value
        : event.value - previous.value;
    if (improvement <= 0) return 'Значение сохранено в истории';
    return switch (event.metric) {
      'longestSleepMinutes' => 'Улучшение на ${_duration(improvement.round())}',
      'bestEfficiencyPercent' =>
        'Улучшение на ${improvement.toStringAsFixed(1)} п.п.',
      'shortestLatencyMinutes' =>
        'Быстрее на ${_duration(improvement.round())}',
      'longestStreakDays' =>
        'Увеличение на ${improvement.round()} ${_dayWord(improvement.round())}',
      _ => 'Рекорд улучшен',
    };
  }

  Widget _recordHistorySection(List<SleepPersonalRecordEvent> events) {
    if (events.isEmpty) return const SizedBox.shrink();
    final previousByMetric = <String, SleepPersonalRecordEvent>{};
    final rows = <Widget>[];
    for (final event in events) {
      final previous = previousByMetric[event.metric];
      final sourceDeleted = event.sessionId != null &&
          !widget.sessions.any((session) => session.id == event.sessionId);
      final date = DateFormat('d MMM yyyy', 'ru').format(event.achievedAt);
      final details = [
        date,
        _recordHistoryChange(event, previous),
        if (sourceDeleted) 'исходная ночь удалена, рекорд сохранён',
      ].join(' · ');
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.emoji_events_outlined,
                color: AppTheme.teal, size: 18),
            const SizedBox(width: 9),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_recordHistoryMetricLabel(event.metric),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(details, style: const TextStyle(
                    color: AppTheme.muted, fontSize: 10, height: 1.35)),
              ],
            )),
            const SizedBox(width: 8),
            Text(_recordHistoryValue(event),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ));
      previousByMetric[event.metric] = event;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text('История личных рекордов (${events.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        children: rows,
      ),
    );
  }

  Widget _newRecordCelebration(Set<String> newKeys) {
    final titles = newKeys.map(_recordTitle).toList()..sort();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.88, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF214B59), Color(0xFF20264D)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.teal.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: [
            const Icon(Icons.celebration_rounded, color: AppTheme.teal, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Новый личный рекорд!',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    titles.join(' · '),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personalRecordsSection(SleepPersonalRecords records, Set<String> newKeys) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      const Divider(color: AppTheme.surfaceLight),
      const SizedBox(height: 8),
      const Text('Личные рекорды', style: TextStyle(
        fontWeight: FontWeight.bold, fontSize: 15,
      )),
      const SizedBox(height: 6),
      _personalRecordRow(
        icon: Icons.bedtime_outlined,
        title: 'Самая продолжительная ночь',
        value: _duration(records.longestSleepMinutes),
        sourceLabel: _recordSourceLabel(records.longestSleepAt, records.longestSleepSessionId),
        isNew: newKeys.contains('longestSleep'),
      ),
      _personalRecordRow(
        icon: Icons.trending_up_rounded,
        title: 'Лучшая эффективность сна',
        value: records.bestEfficiencyPercent == null
            ? 'Пока нет достоверных измерений'
            : records.bestEfficiencyPercent!.toStringAsFixed(1) + '%',
        sourceLabel: _recordSourceLabel(records.bestEfficiencyAt, records.bestEfficiencySessionId),
        isNew: newKeys.contains('bestEfficiency'),
      ),
      _personalRecordRow(
        icon: Icons.timer_outlined,
        title: 'Минимальная задержка засыпания',
        value: records.shortestLatencyMinutes == null
            ? 'Пока нет подтверждённого времени засыпания'
            : _duration(records.shortestLatencyMinutes),
        sourceLabel: _recordSourceLabel(records.shortestLatencyAt, records.shortestLatencySessionId),
        isNew: newKeys.contains('shortestLatency'),
      ),
      _personalRecordRow(
        icon: Icons.local_fire_department_outlined,
        title: 'Самая длинная серия записей',
        value: records.longestStreakDays == 0
            ? 'Пока нет завершённых ночей'
            : records.longestStreakDays.toString() + ' ' + _dayWord(records.longestStreakDays) + ' подряд',
        sourceLabel: '',
        isNew: newKeys.contains('longestStreak'),
      ),
    ]);

  @override
  Widget build(BuildContext context) => FutureBuilder<SleepAchievementState>(
    future: _state,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SectionCard(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      final state = snapshot.data!;
      final earned = state.earnedAt;
      final total = SleepAchievementCatalog.achievements.length;
      final count = earned.length;
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text(
                  'Достижения и вехи',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              Switch.adaptive(
                value: state.displayEnabled,
                onChanged: _setDisplay,
              ),
            ]),
            const Text(
              'Небольшая история накопленных данных — без целей, соревнований и оценки качества сна.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
            ),
            _personalRecordsSection(state.records, state.newRecordKeys),
            _recordHistorySection(state.recordHistory),
            if (state.displayEnabled && state.newRecordKeys.isNotEmpty)
              _newRecordCelebration(state.newRecordKeys),
            if (state.displayEnabled) ...[
              const SizedBox(height: 12),
              Text(
                'Получено: $count из $total',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...SleepAchievementCatalog.achievements.map((achievement) {
                final date = earned[achievement.id];
                final unlocked = date != null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _icon(achievement.id),
                        size: 22,
                        color: unlocked ? AppTheme.teal : AppTheme.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              achievement.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: unlocked ? Colors.white : AppTheme.muted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              unlocked
                                  ? '${achievement.description} Получено ${DateFormat('d MMM yyyy', 'ru').format(date)}.'
                                  : achievement.description,
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (unlocked)
                        const Icon(Icons.check_circle, color: AppTheme.teal, size: 17),
                    ],
                  ),
                );
              }),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Отображение достижений выключено. История получения сохраняется.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    },
  );
}
