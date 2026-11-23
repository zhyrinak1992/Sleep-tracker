import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import '../../data/notification_service.dart';
import '../../data/audio_observation_service.dart';
import '../../data/sleep_database.dart';
import '../../data/comparison_suggestion_store.dart';
import '../../models/sleep_tag.dart';
import '../analysis/tag_sleep_comparison.dart';
import '../diary/sleep_session_metrics.dart';
import 'comparison_suggestion_analyzer.dart';
import 'comparison_suggestion_card.dart';
import '../../models/sleep_session.dart';
import '../diary/sleep_session_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/storage_warning_banner.dart';

class NightSessionScreen extends StatefulWidget {
  const NightSessionScreen({super.key, required this.database, required this.session});
  final SleepDatabase database;
  final SleepSession session;
  @override
  State<NightSessionScreen> createState() => _NightSessionScreenState();
}

class _NightSessionScreenState extends State<NightSessionScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  int _eventCount = 0;
  int _audioSeconds = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadStats();
  }

  Future<void> _loadStats() async {
    final rows = await widget.database.getAudioEvents(sessionId: widget.session.id);
    if (!mounted) return;
    setState(() {
      _eventCount = rows.length;
      _audioSeconds = rows.fold<int>(0, (sum, row) => sum + (((row['duration_ms'] as int?) ?? 0) ~/ 1000));
    });
  }

  String _elapsed(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String _audioDuration() {
    final m = _audioSeconds ~/ 60;
    final s = _audioSeconds % 60;
    return m == 0 ? '$s с' : '$m мин ${s.toString().padLeft(2, '0')} с';
  }

  Future<void> _pause(bool paused) async {
    try {
      if (paused) {
        await AudioObservationService.instance.resumeObservation();
      } else {
        await AudioObservationService.instance.pauseObservation();
      }
      await _loadStats();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось изменить аудио: $e')));
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Завершить эту ночь?'),
      content: const Text('Аудионаблюдение остановится, а сессия сохранится в дневнике.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Продолжить ночь')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Завершить')),
      ],
    ));
    if (yes != true || !mounted) return;
    setState(() => _finishing = true);
    try {
      await AudioObservationService.instance.stopObservation();
      await widget.database.finishSession(widget.session.id);
      await NotificationService.instance.reportReady();
      await NotificationService.instance.scheduleNightReminders();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось завершить сессию: $e')));
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _now.difference(widget.session.startedAt);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF121E3C), Color(0xFF091528), Color(0xFF071222)],
        )),
        child: SafeArea(child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
          children: [
            Align(alignment: Alignment.centerLeft, child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              tooltip: 'Свернуть ночной экран',
            )),
            const SizedBox(height: 10),
            const Icon(Icons.nights_stay_rounded, size: 68, color: Color(0xFFC3B5FF)),
            const SizedBox(height: 16),
            const Center(child: Text('ДОБРОЙ НОЧИ', style: TextStyle(
              letterSpacing: 4, fontSize: 12, color: Color(0xFFB9B0E9), fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            const Center(child: Text('Пусть эта ночь будет\nспокойной', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, height: 1.25, fontWeight: FontWeight.w600))),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF1D3457), Color(0xFF10243D), Color(0xFF17213D)]),
                border: Border.all(color: const Color(0xFF9B8DE0).withValues(alpha: .45)),
                boxShadow: [BoxShadow(color: const Color(0xFF8D83D5).withValues(alpha: .16), blurRadius: 38, spreadRadius: 2)],
              ),
              child: Column(children: [
                const Text('ВРЕМЯ НАБЛЮДЕНИЯ', style: TextStyle(letterSpacing: 2, fontSize: 11, color: Color(0xFFAABBD5))),
                const SizedBox(height: 10),
                Text(_elapsed(elapsed), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w300, letterSpacing: 2)),
                const SizedBox(height: 8),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.circle, color: AppTheme.teal, size: 8),
                  SizedBox(width: 8),
                  Text('Ночная сессия продолжается', style: TextStyle(color: AppTheme.teal, fontSize: 12)),
                ]),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(25, (i) =>
                  Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 3, height: 10 + ((i * 17) % 25).toDouble(),
                    decoration: BoxDecoration(color: i % 3 == 0 ? const Color(0xFFB5A4F5) : AppTheme.teal, borderRadius: BorderRadius.circular(4))))),
                const SizedBox(height: 22),
                Divider(color: Colors.white.withValues(alpha: .12)),
                Row(children: [
                  Expanded(child: _NightMetric(label: 'Начало', value: DateFormat('HH:mm').format(widget.session.startedAt))),
                  Expanded(child: _NightMetric(label: 'События', value: '$_eventCount')),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: _NightMetric(label: 'Длительность фрагментов', value: _audioDuration())),
                  Expanded(child: _NightMetric(label: 'Дата', value: DateFormat('d MMM', 'ru').format(widget.session.startedAt))),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: AudioObservationService.instance.observing,
              builder: (context, observing, _) => ValueListenableBuilder<bool>(
                valueListenable: AudioObservationService.instance.paused,
                builder: (context, paused, _) => Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: .09))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(observing && !paused ? Icons.graphic_eq_rounded : Icons.mic_off_rounded, color: AppTheme.teal),
                      const SizedBox(width: 10),
                      Expanded(child: Text(!observing ? 'Аудио не активно' : paused ? 'Аудио на паузе' : 'Аудионаблюдение активно',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Сохраняются отдельные звуковые события. Тихие промежутки не записываются.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                    if (observing) ...[
                      const SizedBox(height: 14),
                      SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        onPressed: () => _pause(paused),
                        icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                        label: Text(paused ? 'Возобновить аудио' : 'Пауза аудио'),
                      )),
                    ],
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _finishing ? null : _finish,
              icon: const Icon(Icons.wb_sunny_outlined),
              label: Text(_finishing ? 'Сохраняем ночь…' : 'Я проснулась'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF59D8C5), foregroundColor: const Color(0xFF082033),
                padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            )),
            const SizedBox(height: 12),
            const Text('Фазы сна и физиологические показатели появятся при наличии данных Apple Health.',
              textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
          ],
        )),
      ),
    );
  }
}

class _NightMetric extends StatelessWidget {
  const _NightMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
    const SizedBox(height: 5),
    Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
  ]);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  SleepSession? _open;
  SleepSession? _latest;
  bool _loading = true;
  bool _refreshing = false;
  bool _refreshRequested = false;
  ComparisonSuggestionRecord? _comparisonSuggestion;
  Map<String, String> _suggestionTagLabels = const {};
  Timer? _suggestionExpiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.sleepStartRequested.addListener(_onSleepStartRequested);
    _refresh();
    if (NotificationService.instance.sleepStartRequested.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSleepStartPrompt());
    }
  }

  void _onSleepStartRequested() {
    if (!mounted || !NotificationService.instance.sleepStartRequested.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showSleepStartPrompt());
  }

  Future<void> _showSleepStartPrompt() async {
    if (!mounted || !NotificationService.instance.sleepStartRequested.value) return;
    NotificationService.instance.sleepStartRequested.value = false;
    if (_open != null) return;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Начинаем ночное наблюдение?'),
        content: const Text(
          'Пора подготовиться ко сну. Включить наблюдение сейчас или отложить напоминание?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'later'),
            child: const Text('Отложить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'start'),
            child: const Text('Включаем'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == 'start') {
      await _toggleSession();
    } else if (choice == 'later') {
      await NotificationService.instance.deferSleepStart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Напомним ещё раз через 30 минут.')),
        );
      }
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshRequested = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshRequested = false;
        await _refreshInternal();
      } while (_refreshRequested && mounted);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshInternal() async {
    final open = await widget.database.getOpenSession();
    final sessions = await widget.database.getSessions(limit: 10000);
    ComparisonSuggestionRecord? suggestion;
    Map<String, String> labels = const {};
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final start = dayStart.subtract(const Duration(days: 90));
      final end = dayStart.add(const Duration(days: 1));
      final relevant = sessions.where((session) =>
        !session.startedAt.isBefore(start) && session.startedAt.isBefore(end) &&
        session.endedAt != null && session.endedAt!.isAfter(session.startedAt)).toList();
      final ids = relevant.map((session) => session.id).toList();
      final tags = await widget.database.getTagsForSessions(ids);
      final stages = await widget.database.getStagesForSessions(ids);
      final awakenings = <String, int>{};
      for (final session in relevant) {
        final rows = stages[session.id] ?? const <Map<String, Object?>>[];
        final hasAwakeSamples = rows.any((row) {
          final stage = (row['stage'] as String? ?? '').toLowerCase();
          return stage.contains('бодрств') || stage == 'awake' || stage.contains('awake');
        });
        if (hasAwakeSamples) {
          awakenings[session.id] = SleepSessionMetrics.calculate(
            session: session,
            stages: rows,
          ).awakeningCount;
        }
      }
      final customTags = await CustomSleepTagStore(
        widget.database.getAppMetadata,
        widget.database.setAppMetadata,
      ).load();
      labels = {
        for (final tag in [...SleepTag.catalog, ...customTags]) tag.key: tag.label,
      };
      final templates = await TagComparisonTemplateStore(
        widget.database.getAppMetadata,
        widget.database.setAppMetadata,
      ).load();
      final candidates = ComparisonSuggestionAnalyzer.analyze(
        sessions: relevant,
        tagsBySession: tags,
        awakeningCountsBySession: awakenings,
        now: now,
        existingCombinations: templates.map((item) => item.tagKeys),
      );
      suggestion = await ComparisonSuggestionStore(
        widget.database.getAppMetadata,
        widget.database.setAppMetadata,
      ).currentOrCreate(candidates: candidates, now: now);
    } catch (_) {
      // Suggestion generation is optional; failures never block the sleep tracker home.
      suggestion = null;
    }
    if (!mounted) return;
    setState(() {
      _open = open;
      _latest = sessions.isEmpty ? null : sessions.first;
      _comparisonSuggestion = suggestion;
      _suggestionTagLabels = labels;
      _loading = false;
    });
    _scheduleSuggestionExpiryRefresh();
  }

  void _scheduleSuggestionExpiryRefresh() {
    _suggestionExpiryTimer?.cancel();
    final now = DateTime.now();
    DateTime due;
    if (_comparisonSuggestion != null) {
      due = _comparisonSuggestion!.expiresAt;
    } else {
      due = DateTime(now.year, now.month, now.day, 8);
      if (!due.isAfter(now)) due = due.add(const Duration(days: 1));
    }
    final delay = due.difference(now);
    _suggestionExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () async {
        if (!mounted) return;
        await _refresh();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _toggleSession() async {
    try {
      if (_open == null) {
        await NotificationService.instance.cancelNightReminders();
        final session = await widget.database.startSession();
        try {
          // Audio must be active for a manual night session. If iOS denies
          // microphone access or stream startup fails, do not leave a false
          // "recording" session in the diary.
          await AudioObservationService.instance.startObservation();
        } catch (audioError) {
          await widget.database.finishSession(session.id);
          // Starting the night cancels queued reminders. If microphone
          // permission or recorder startup fails, restore the reminder queue.
          await NotificationService.instance.scheduleNightReminders();
          await _refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Не удалось включить аудионаблюдение. Ночная запись не начата. Проверь разрешение на микрофон. $audioError'),
              duration: const Duration(seconds: 6),
            ));
          }
          return;
        }
        await _refresh();
        if (!mounted) return;
        final completed = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => NightSessionScreen(database: widget.database, session: session),
          fullscreenDialog: true,
        ));
        await _refresh();
        if (completed == true) {
          await _offerMorningReport(session.id);
        }
        return;
      } else {
        final completedSessionId = _open!.id;
        await AudioObservationService.instance.stopObservation();
        await widget.database.finishSession(completedSessionId);
        await NotificationService.instance.reportReady();
        await NotificationService.instance.scheduleNightReminders();
        await _refresh();
        await _offerMorningReport(completedSessionId);
        return;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить ночную сессию: $error')),
      );
    }
  }

  Future<void> _toggleAudioPause(bool isPaused) async {
    try {
      if (isPaused) {
        await AudioObservationService.instance.resumeObservation();
      } else {
        await AudioObservationService.instance.pauseObservation();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось изменить состояние аудио: $error')),
        );
      }
    }
  }


  Future<void> _offerMorningReport(String sessionId) async {
    if (!mounted) return;
    final existing = await widget.database.getMorningReport(sessionId);
    if (existing != null || !mounted) return;

    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ночь завершена'),
        content: const Text(
          'Ночная запись сохранена. Можно сразу открыть подробный отчёт по этой ночи и заполнить утреннюю оценку самочувствия.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Позже'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('Сформировать утренний отчёт'),
          ),
        ],
      ),
    );

    if (choice != true || !mounted) return;
    final session = await widget.database.getSessionById(sessionId);
    if (session == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SleepSessionDetailScreen(
        database: widget.database,
        session: session,
      ),
    ));
    await _refresh();
  }

  Future<void> _createMorningReport() async {
    final session = _latest;
    if (session == null || session.isOpen) return;
    var wellbeing = 3;
    var quality = 3;
    var sleepiness = 3;
    final comment = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Утренний отчёт'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Насколько хорошо вы спали?'),
              Text('$quality из 5', style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
              Slider(min: 1, max: 5, divisions: 4, value: quality.toDouble(), onChanged: (v) => setDialogState(() => quality = v.round())),
              const Text('1 — очень плохо · 5 — отлично', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 14),
              const Text('Насколько вы чувствуете себя отдохнувшей?'),
              Text('$wellbeing из 5', style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
              Slider(min: 1, max: 5, divisions: 4, value: wellbeing.toDouble(), onChanged: (v) => setDialogState(() => wellbeing = v.round())),
              const Text('1 — совсем не отдохнула · 5 — полностью отдохнула', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 14),
              const Text('Насколько сильно хочется спать сейчас?'),
              Text('$sleepiness из 5', style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
              Slider(min: 1, max: 5, divisions: 4, value: sleepiness.toDouble(), onChanged: (v) => setDialogState(() => sleepiness = v.round())),
              const Text('1 — совсем не хочется · 5 — очень сильная сонливость', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(controller: comment, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Комментарий (необязательно)')),
              const SizedBox(height: 8),
              const Text('Оценки субъективные и сохраняются отдельно для этой ночи.', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'skip'), child: const Text('Пропустить')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, 'save'), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (!mounted) { comment.dispose(); return; }
    if (result == 'skip') {
      await widget.database.saveMorningReport(sessionId: session.id, wellbeing: null, quality: null, answersJson: jsonEncode({'skipped': true}));
      comment.dispose();
      await _refresh();
      return;
    }
    if (result != 'save') { comment.dispose(); return; }
    await widget.database.saveMorningReport(
      sessionId: session.id, wellbeing: wellbeing, quality: quality,
      answersJson: jsonEncode({'wellbeing': wellbeing, 'sleepQuality': quality, 'sleepiness': sleepiness, 'comment': comment.text.trim(), 'skipped': false}),
    );
    await widget.database.updateMorningRating(session.id, wellbeing);
    comment.dispose();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Утренний отчёт сохранён.')));
    await _refresh();
  }

  String _duration(Duration? duration) {
    if (duration == null || duration.isNegative) return '—';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours ч ${minutes.toString().padLeft(2, '0')} мин';
  }

  @override
  void dispose() {
    _suggestionExpiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.sleepStartRequested.removeListener(_onSleepStartRequested);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFFE8C7F6), size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, d MMMM', 'ru').format(now),
                    style: const TextStyle(color: Color(0xFFE9E0F7), fontSize: 13,
                      letterSpacing: .7, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF211B43),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF9F80C8).withValues(alpha: .75)),
                    boxShadow: [BoxShadow(color: const Color(0xFFB98CEB).withValues(alpha: .12), blurRadius: 18)],
                  ),
                  child: const Row(children: [
                    Icon(Icons.nightlight_round, color: Color(0xFFFFD8A8), size: 15),
                    SizedBox(width: 7),
                    Text('РЕЖИМ СНА', style: TextStyle(color: Colors.white, fontSize: 10,
                      letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
            ),
          ),
          const StorageWarningBanner(),
          if (_comparisonSuggestion != null) ...[
            const SizedBox(height: 12),
            ComparisonSuggestionCard(
              database: widget.database,
              record: _comparisonSuggestion!,
              tagLabels: _suggestionTagLabels,
              onProcessed: () {
                if (mounted) setState(() => _comparisonSuggestion = null);
                _refresh();
              },
            ),
          ],
          Container(
            height: 390,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF19183F), Color(0xFF111532), Color(0xFF0A102A)]),
              border: Border.all(color: const Color(0xFF8170B5).withValues(alpha: .28)),
              boxShadow: [BoxShadow(color: const Color(0xFF8E67C9).withValues(alpha: .13), blurRadius: 32, spreadRadius: 1)],
            ),
            child: Stack(
              children: [
                Positioned.fill(child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: CustomPaint(painter: _PremiumSleepPainter()),
                )),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 2),
                        Container(
                          width: 66, height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFB58DEB).withValues(alpha: .12),
                            border: Border.all(color: const Color(0xFFE6C8FF).withValues(alpha: .4)),
                            boxShadow: [BoxShadow(color: const Color(0xFFB78BF3).withValues(alpha: .18), blurRadius: 22)],
                          ),
                          child: const Icon(Icons.bedtime_rounded, size: 31, color: Color(0xFFE8C7FF)),
                        ),
                        const SizedBox(height: 15),
                        Text(_open == null ? 'Готовы ко сну?' : 'Ночная запись идёт',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700,
                            letterSpacing: .1, color: Colors.white)),
                        const SizedBox(height: 8),
                        Text(_open == null
                            ? 'Запустите наблюдение, чтобы отслеживать ваш сон'
                            : 'Начало: ${DateFormat('HH:mm').format(_open!.startedAt)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFC8BEDF), fontSize: 13, height: 1.45)),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
                                colors: [Color(0xFFE6B9F5), Color(0xFFB78AF0), Color(0xFF8E82E9)]),
                              boxShadow: [BoxShadow(color: const Color(0xFFC18CF3).withValues(alpha: .32),
                                blurRadius: 24, offset: const Offset(0, 7))],
                            ),
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _toggleSession,
                              icon: Icon(_open == null ? Icons.play_arrow_rounded : Icons.stop_rounded, size: 24),
                              label: Text(_open == null ? 'Начать сон' : 'Завершить запись'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: const Color(0xFF211638),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_open == null && (now.hour == 23 && now.minute >= 55 || now.hour >= 0 && now.hour < 6)) ...[
            const SizedBox(height: 10),
            Center(child: TextButton(
              onPressed: () async { await NotificationService.instance.cancelNextMidnightAttempt(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ближайшая проверка отменена. Последующие проверки останутся активными.'))); },
              child: const Text('Я ещё не сплю — пропустить ближайший запуск'),
            )),
          ],
          const SizedBox(height: 16),
          Center(
            child: Text(
              _open == null ? 'Ночная сессия не начата' :
                'Начало: ${DateFormat('HH:mm').format(_open!.startedAt)}',
              style: const TextStyle(color: AppTheme.muted),
            ),
          ),
          if (_open != null) ...[
            const SizedBox(height: 18),
            ValueListenableBuilder<bool>(
              valueListenable: AudioObservationService.instance.observing,
              builder: (context, observing, _) => ValueListenableBuilder<bool>(
                valueListenable: AudioObservationService.instance.paused,
                builder: (context, paused, _) => Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF163B52), Color(0xFF0D2036)],
                    ),
                    border: Border.all(color: AppTheme.teal.withValues(alpha: .35)),
                    boxShadow: [BoxShadow(
                      color: AppTheme.teal.withValues(alpha: .08),
                      blurRadius: 24,
                      spreadRadius: 1,
                    )],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.teal.withValues(alpha: .12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            observing && !paused ? Icons.graphic_eq_rounded : Icons.mic_off_outlined,
                            color: AppTheme.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('НОЧНОЕ НАБЛЮДЕНИЕ',
                              style: TextStyle(fontSize: 11, letterSpacing: 1.5,
                                color: AppTheme.muted, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(
                              !observing ? 'Аудио не активно' : paused ? 'Аудио на паузе' : 'Аудионаблюдение активно',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ],
                        )),
                        if (observing && !paused)
                          const Icon(Icons.circle, size: 10, color: AppTheme.teal),
                      ]),
                      const SizedBox(height: 14),
                      Text(
                        observing
                          ? (paused ? 'Микрофон временно приостановлен.' : 'Сохраняются отдельные звуковые события. Тихие промежутки не записываются.')
                          : 'Проверь разрешение на микрофон. Ночная сессия остаётся активной.',
                        style: const TextStyle(color: AppTheme.muted, height: 1.4, fontSize: 12),
                      ),
                      if (observing || paused) ...[
                        const SizedBox(height: 14),
                        SizedBox(width: double.infinity, child: OutlinedButton.icon(
                          onPressed: () => _toggleAudioPause(paused),
                          icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          label: Text(paused ? 'Возобновить аудио' : 'Приостановить аудио'),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          const Text('Последняя запись', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SectionCard(
            child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _latest == null
                ? const Text('Здесь появится первая сохранённая ночь. Пока данных нет.',
                    style: TextStyle(color: AppTheme.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('d MMMM yyyy, HH:mm').format(_latest!.startedAt),
                        style: const TextStyle(color: AppTheme.muted)),
                      const SizedBox(height: 10),
                      Text(_latest!.isOpen ? 'Наблюдение продолжается' : _duration(_latest!.duration),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_latest!.morningRating == null
                        ? 'Утренняя оценка ещё не добавлена'
                        : 'Самочувствие: ${_latest!.morningRating}/5',
                        style: const TextStyle(color: AppTheme.muted)),
                    ],
                  ),
          ),
          if (_latest != null && !_latest!.isOpen) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _createMorningReport,
              icon: const Icon(Icons.wb_sunny_outlined),
              label: const Text('Заполнить утренний отчёт'),
            )),
          ],
          const SizedBox(height: 14),
          const SectionCard(
            child: Row(children: [
              Icon(Icons.info_outline, color: AppTheme.teal),
              SizedBox(width: 12),
              Expanded(child: Text(
                'Сон и доступные фазы импортируются из Apple Health. При начале ночной сессии запускается событийное аудионаблюдение: сохраняются только отдельные звуковые фрагменты. Фоновую работу микрофона нужно проверить на iPhone; запуск из полностью закрытого приложения не гарантируется.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PremiumSleepPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .49);
    final radius = size.width * .39;

    // Subtle star field.
    final stars = <Offset>[
      Offset(size.width * .10, size.height * .12), Offset(size.width * .82, size.height * .13),
      Offset(size.width * .91, size.height * .31), Offset(size.width * .13, size.height * .42),
      Offset(size.width * .76, size.height * .56), Offset(size.width * .23, size.height * .68),
      Offset(size.width * .88, size.height * .79), Offset(size.width * .54, size.height * .09),
    ];
    for (var i = 0; i < stars.length; i++) {
      final p = stars[i];
      canvas.drawCircle(p, i % 3 == 0 ? 2.0 : 1.2,
        Paint()..color = const Color(0xFFDCC8FF).withValues(alpha: i % 2 == 0 ? .8 : .45));
    }

    // Large soft halo and refined circular arc.
    final circleRect = Rect.fromCircle(center: center, radius: radius);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = const Color(0xFFB88AF0).withValues(alpha: .12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 17);
    canvas.drawCircle(center, radius, halo);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF8873B8).withValues(alpha: .36);
    canvas.drawArc(circleRect, -2.25, 4.95, false, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: -1.1,
        endAngle: 5.1,
        colors: [Color(0xFF9B7AF0), Color(0xFFE5B6F4), Color(0xFFFFD0C2), Color(0xFF9B7AF0)],
      ).createShader(circleRect);
    canvas.drawArc(circleRect, -2.15, 3.25, false, arc);

    // Crescent moon in the upper-right corner.
    final moon = Offset(size.width * .79, size.height * .19);
    canvas.drawCircle(moon, 23, Paint()
      ..color = const Color(0xFFFFCFAE).withValues(alpha: .22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    canvas.drawCircle(moon, 17, Paint()..color = const Color(0xFFFFD9AE));
    canvas.drawCircle(moon.translate(8, -5), 16, Paint()..color = const Color(0xFF19183F));

    // Low, layered cloud silhouettes keep the composition quiet.
    final cloudPaint = Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF8E79B4), Color(0xFF3B365F), Color(0x00171638)],
    ).createShader(Rect.fromLTWH(0, size.height * .70, size.width, size.height * .30));
    final path = Path()
      ..moveTo(0, size.height * .82)
      ..cubicTo(size.width * .10, size.height * .70, size.width * .18, size.height * .74, size.width * .28, size.height * .82)
      ..cubicTo(size.width * .38, size.height * .69, size.width * .49, size.height * .73, size.width * .57, size.height * .82)
      ..cubicTo(size.width * .68, size.height * .69, size.width * .83, size.height * .72, size.width, size.height * .81)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, cloudPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

