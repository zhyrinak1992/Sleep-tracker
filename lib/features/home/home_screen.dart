import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../data/notification_service.dart';
import '../../data/audio_observation_service.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SleepSession? _open;
  SleepSession? _latest;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final open = await widget.database.getOpenSession();
    final sessions = await widget.database.getSessions(limit: 1);
    if (!mounted) return;
    setState(() {
      _open = open;
      _latest = sessions.isEmpty ? null : sessions.first;
      _loading = false;
    });
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
          await _refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Не удалось включить аудионаблюдение. Ночная запись не начата. Проверь разрешение на микрофон. $audioError'),
              duration: const Duration(seconds: 6),
            ));
          }
          return;
        }
      } else {
        await AudioObservationService.instance.stopObservation();
        await widget.database.finishSession(_open!.id);
        await NotificationService.instance.reportReady();
        await NotificationService.instance.scheduleNightReminders();
      }
      await _refresh();
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


  Future<void> _createMorningReport() async {
    final session = _latest;
    if (session == null || session.isOpen) return;
    var wellbeing = 3;
    var quality = 3;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Утренний отчёт'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Как вы себя чувствуете?'),
          DropdownButton<int>(value: wellbeing, isExpanded: true, items: List.generate(5, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} из 5'))), onChanged: (v) => setDialogState(() => wellbeing = v ?? 3)),
          const SizedBox(height: 12),
          const Text('Как оцениваете качество сна?'),
          DropdownButton<int>(value: quality, isExpanded: true, items: List.generate(5, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} из 5'))), onChanged: (v) => setDialogState(() => quality = v ?? 3)),
          const SizedBox(height: 8),
          const Text('Оценки сохраняются в истории. Они не являются медицинской оценкой.', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить'))],
      ),
    ));
    if (saved != true) return;
    await widget.database.saveMorningReport(sessionId: session.id, wellbeing: wellbeing, quality: quality,
      answersJson: jsonEncode({'wellbeing': wellbeing, 'sleepQuality': quality}));
    await widget.database.updateMorningRating(session.id, wellbeing);
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          const Text('ТРЕКЕР СНА', style: TextStyle(
            color: AppTheme.teal, letterSpacing: 2.4, fontSize: 12, fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 8),
          Text('Добрый вечер', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: 4),
          Text(DateFormat('EEEE, d MMMM', 'ru').format(now),
            style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 26),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(120),
              onTap: _loading ? null : _toggleSession,
              child: Container(
                width: 218, height: 218,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B526B), Color(0xFF10243B), Color(0xFF0A1A2D)],
                  ),
                  border: Border.all(color: AppTheme.teal.withValues(alpha: .55), width: 1.5),
                  boxShadow: [BoxShadow(
                    color: AppTheme.teal.withValues(alpha: .12),
                    blurRadius: 38, spreadRadius: 4,
                  )],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_open == null ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                      size: 38, color: AppTheme.teal),
                    const SizedBox(height: 12),
                    Text(_open == null ? 'ЛОЖУСЬ СПАТЬ' : 'ЗАВЕРШИТЬ',
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(_open == null ? 'Начать запись' : 'Сохранить сессию',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
                ),
              ),
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
                      if (observing) ...[
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
