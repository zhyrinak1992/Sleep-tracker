import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../diary/sleep_session_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_achievement_service.dart';
import 'sleep_personal_records.dart';
import 'sleep_record_service.dart';

class SleepAchievementsCard extends StatefulWidget {
  const SleepAchievementsCard({super.key, required this.sessions});

  final List<SleepSession> sessions;

  @override
  State<SleepAchievementsCard> createState() => _SleepAchievementsCardState();
}

class _SleepAchievementsCardState extends State<SleepAchievementsCard> {
  late Future<SleepAchievementState> _state;
  late Future<SleepRecordState> _records;
  bool _celebrationsScheduled = false;

  @override
  void initState() {
    super.initState();
    _state = SleepAchievementService.instance.load(widget.sessions);
    _records = _state.then((state) => state.recordHistory);
  }

  @override
  void didUpdateWidget(covariant SleepAchievementsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _state = SleepAchievementService.instance.load(widget.sessions);
      _records = _state.then((state) => state.recordHistory);
      _celebrationsScheduled = false;
    }
  }

  Future<void> _showRecordCelebration(SleepRecordEvent event) async {
    final recordService = SleepRecordService.instance;
    if (!mounted || await recordService.isCelebrated(event)) return;

    // The analysis page and the dedicated achievements page can both remain
    // mounted. Wait for the active dialog to finish instead of dropping this
    // event when another card temporarily owns the global celebration lock.
    while (!recordService.tryClaimCelebration(event)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || await recordService.isCelebrated(event)) return;
    }

    try {
      // Another mounted card may have completed this same event while this
      // card was waiting for the global dialog slot.
      if (await recordService.isCelebrated(event)) return;
      final isScore = event.type == 'sleep_score';
      final title = isScore ? 'Новый рекорд SleepScore!' : 'Новый рекорд пробуждений!';
      final value = isScore ? '${event.value.toInt()} из 100' : '${event.value.toInt()} за ночь';
      final date = DateFormat('d MMMM yyyy', 'ru').format(event.achievedAt);
      final openNight = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF202746),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.65, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.teal.withOpacity(0.95), const Color(0xFF5368C8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(color: AppTheme.teal.withOpacity(0.25), blurRadius: 24)],
                  ),
                  child: Icon(isScore ? Icons.stars_rounded : Icons.nights_stay_rounded, size: 48, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(value, textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: AppTheme.teal)),
              const SizedBox(height: 8),
              Text(date, style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 12),
              const Text('Отличный результат! Эта ночь теперь отмечена в вашей истории достижений.', textAlign: TextAlign.center, style: TextStyle(height: 1.4)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Позже')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.nightlight_round),
              label: const Text('Открыть эту ночь'),
            ),
          ],
        ),
      );

      // If this card was removed while its dialog was open, do not mark the
      // event as acknowledged. The next mounted card can safely offer it again.
      // Otherwise persist acknowledgement only after the dialog is dismissed.
      if (!mounted) return;
      await recordService.markCelebrated(event);
      if (openNight == true && mounted) {
        final database = SleepDatabase.instance;
        final session = await database.getSessionById(event.sessionId);
        if (!mounted) return;
        if (session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Запись этой ночи больше недоступна.')),
          );
          return;
        }
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SleepSessionDetailScreen(database: database, session: session),
        ));
      }
    } finally {
      recordService.releaseCelebration(event);
    }
  }

  Future<void> _setDisplay(bool value) async {
    await SleepAchievementService.instance.setDisplayEnabled(value);
    if (!mounted) return;
    setState(() {
      _state = SleepAchievementService.instance.load(widget.sessions);
      _records = _state.then((state) => state.recordHistory);
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
            const SizedBox(height: 8),
            const Text(
              'Дополнительные рекорды',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            FutureBuilder<SleepRecordState>(
              future: _records,
              builder: (context, recordSnapshot) {
                if (!recordSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }
                final records = recordSnapshot.data!;
                if (!_celebrationsScheduled && records.newRecords.isNotEmpty) {
                  _celebrationsScheduled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    for (final event in records.newRecords) {
                      if (!mounted) break;
                      await _showRecordCelebration(event);
                    }
                  });
                }
                final score = records.bestSleepScore;
                final awakenings = records.fewestAwakenings;
                final history = records.history.toList()
                  ..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
                Widget recordLine({
                  required IconData icon,
                  required String title,
                  required String value,
                  required SleepRecordEvent? event,
                }) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, color: AppTheme.teal, size: 21),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                event == null
                                    ? 'Пока нет достоверных данных'
                                    : '$value · ${DateFormat('d MMM yyyy', 'ru').format(event.achievedAt)}',
                                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    recordLine(
                      icon: Icons.stars_rounded,
                      title: 'Лучший SleepScore',
                      value: score == null ? '—' : '${score.value.toInt()} из 100',
                      event: score,
                    ),
                    recordLine(
                      icon: Icons.nights_stay_outlined,
                      title: 'Минимум пробуждений',
                      value: awakenings == null
                          ? '—'
                          : '${awakenings.value.toInt()}',
                      event: awakenings,
                    ),
                    Text(
                      'Рекорды учитывают только завершённые ночи и достоверные измерения. История улучшений сохраняется отдельно.',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
                    ),
                    if (history.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      const Text(
                        'История улучшений',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ...history.map((event) {
                        final isScore = event.type == 'sleep_score';
                        final sourceExists = widget.sessions.any(
                          (session) => session.id == event.sessionId,
                        );
                        final label = isScore ? 'SleepScore' : 'Пробуждения';
                        final value = isScore
                            ? '${event.value.toInt()} из 100'
                            : '${event.value.toInt()}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                isScore ? Icons.stars_rounded : Icons.nights_stay_outlined,
                                size: 16,
                                color: AppTheme.teal,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$label: $value',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    DateFormat('d MMM yyyy', 'ru').format(event.achievedAt),
                                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                                  ),
                                  if (!sourceExists)
                                    const Text('ночь удалена', style: TextStyle(color: AppTheme.muted, fontSize: 9)),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
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
