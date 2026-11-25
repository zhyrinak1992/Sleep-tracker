import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../data/notification_service.dart';
import '../analysis/climate_analytics.dart';
import '../analysis/sleep_score.dart';
import 'screen_time_card.dart';
import 'weather_night_detail_card.dart';
import 'sleep_session_metrics_card.dart';
import 'sleep_session_metrics.dart';
import 'sleep_event_timeline.dart';
import 'sleep_metric_summary.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_note.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class SleepSessionDetailScreen extends StatefulWidget {
  const SleepSessionDetailScreen({super.key, required this.database, required this.session});

  final SleepDatabase database;
  final SleepSession session;

  @override
  State<SleepSessionDetailScreen> createState() => _SleepSessionDetailScreenState();
}

class _SleepSessionDetailScreenState extends State<SleepSessionDetailScreen> {
  late Future<SleepSession?> _future;
  late Future<List<SleepNote>> _notesFuture;
  late Future<List<Map<String, Object?>>> _stagesFuture;
  late Future<List<Map<String, Object?>>> _metricsFuture;
  late Future<List<Map<String, Object?>>> _climateFuture;
  late Future<List<SleepTimelineEvent>> _timelineFuture;
  late Future<Map<String, Object?>?> _reportFuture;

  @override
  void initState() {
    super.initState();
    _future = widget.database.getSessionById(widget.session.id);
    _notesFuture = widget.database.getNotes(sessionId: widget.session.id);
    _stagesFuture = widget.database.getStages(widget.session.id);
    _metricsFuture = widget.database.getMetrics(widget.session.id);
    _climateFuture = _loadClimate(widget.session);
    _timelineFuture = _loadTimeline();
    _reportFuture = widget.database.getMorningReport(widget.session.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.database.getSessionById(widget.session.id);
      _notesFuture = widget.database.getNotes(sessionId: widget.session.id);
      _stagesFuture = widget.database.getStages(widget.session.id);
      _metricsFuture = widget.database.getMetrics(widget.session.id);
      _climateFuture = _loadClimate(widget.session);
      _timelineFuture = _loadTimeline();
      _reportFuture = widget.database.getMorningReport(widget.session.id);
    });
    await _future;
  }

  Future<List<SleepTimelineEvent>> _loadTimeline() async {
    final stages = await _stagesFuture;
    final metrics = await _metricsFuture;
    final audioEvents = await widget.database.getAudioEvents(sessionId: widget.session.id);
    return SleepEventTimeline.build(
      stages: stages,
      metrics: metrics,
      audioEvents: audioEvents,
    );
  }

  Future<List<Map<String, Object?>>> _loadClimate(SleepSession session) {
    final end = session.endedAt ?? DateTime.now();
    if (!end.isAfter(session.startedAt)) return Future.value(const []);
    return widget.database.getClimateSamples(
      sessionId: session.id,
      from: session.startedAt,
      to: end,
    );
  }

  String _duration(Duration? duration) {
    if (duration == null) return 'Пока не рассчитана';
    if (duration.isNegative) return 'Некорректный интервал';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours ч ${minutes.toString().padLeft(2, '0')} мин';
  }

  String _dateTime(DateTime? value) => value == null
      ? 'Не указано'
      : DateFormat('d MMMM yyyy, HH:mm', 'ru').format(value);

  Future<void> _editMorningReport(SleepSession session) async {
    final existing = await widget.database.getMorningReport(session.id);
    Map<String, dynamic> answers = {};
    final raw = existing?['answers_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) answers = decoded;
      } catch (_) {}
    }
    var quality = (existing?['sleep_quality'] as int?) ?? 3;
    var wellbeing = (existing?['wellbeing'] as int?) ?? session.morningRating ?? 3;
    var sleepiness = (answers['sleepiness'] as num?)?.toInt() ?? 3;
    final comment = TextEditingController(text: answers['comment'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Утренний отчёт'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Насколько хорошо вы спали?'),
              Text('$quality из 5'),
              Slider(min: 1, max: 5, divisions: 4, value: quality.toDouble(), onChanged: (v) => setDialogState(() => quality = v.round())),
              const SizedBox(height: 8),
              const Text('Насколько вы чувствуете себя отдохнувшей?'),
              Text('$wellbeing из 5'),
              Slider(min: 1, max: 5, divisions: 4, value: wellbeing.toDouble(), onChanged: (v) => setDialogState(() => wellbeing = v.round())),
              const SizedBox(height: 8),
              const Text('Насколько сильно хочется спать сейчас?'),
              Text('$sleepiness из 5'),
              Slider(min: 1, max: 5, divisions: 4, value: sleepiness.toDouble(), onChanged: (v) => setDialogState(() => sleepiness = v.round())),
              TextField(controller: comment, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Комментарий (необязательно)')),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'skip'), child: const Text('Пропустить оценку')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, 'save'), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (!mounted) { comment.dispose(); return; }
    if (result == 'skip') {
      await widget.database.saveMorningReport(sessionId: session.id, wellbeing: null, quality: null, answersJson: jsonEncode({'skipped': true}));
      await widget.database.updateMorningRating(session.id, null);
    } else if (result == 'save') {
      await widget.database.saveMorningReport(
        sessionId: session.id, wellbeing: wellbeing, quality: quality,
        answersJson: jsonEncode({'wellbeing': wellbeing, 'sleepQuality': quality, 'sleepiness': sleepiness, 'comment': comment.text.trim(), 'skipped': false}),
      );
      await widget.database.updateMorningRating(session.id, wellbeing);
    }
    comment.dispose();
    if (result == 'save' || result == 'skip') {
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Утренний отчёт сохранён')));
      final refreshedSession = await widget.database.getSessionById(session.id);
      if (refreshedSession != null && mounted) {
        await _showMorningSummary(refreshedSession);
      }
    }
  }

  Future<void> _showMorningSummary(SleepSession session) async {
    final stages = await widget.database.getStages(session.id);
    final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
    final events = await widget.database.getAudioEvents(sessionId: session.id);
    final report = await widget.database.getMorningReport(session.id);

    final categoryCounts = <String, int>{};
    for (final event in events) {
      final category = (event['category'] as String?)?.trim();
      final label = category == null || category.isEmpty || category == 'unknown'
          ? 'Неопределённый звук'
          : category;
      categoryCounts[label] = (categoryCounts[label] ?? 0) + 1;
    }
    final orderedCategories = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Map<String, dynamic> parseAnswers(Map<String, Object?>? source) {
      final raw = source?['answers_json'];
      if (raw is! String || raw.isEmpty) return {};
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map<String, dynamic> ? decoded : {};
      } catch (_) {
        return {};
      }
    }

    final currentAnswers = parseAnswers(report);
    final scoreCutoff = session.startedAt.subtract(const Duration(days: 100));
    final priorSessions = (await widget.database.getSessions(limit: 365))
        .where((item) => item.id != session.id && !item.isOpen &&
            item.startedAt.isBefore(session.startedAt) &&
            !item.startedAt.isBefore(scoreCutoff))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final historySessions = priorSessions.take(7).toList();
    final historyReports = await widget.database.getMorningReportsForSessions(
      historySessions.map((item) => item.id).toList(),
    );
    final scoreSessionIds = [...priorSessions.map((item) => item.id), session.id];
    final scoreReports = await widget.database.getMorningReportsForSessions(scoreSessionIds);
    final scoreStages = await widget.database.getStagesForSessions(scoreSessionIds);
    if (report != null) scoreReports[session.id] = report;
    scoreStages[session.id] = stages;
    final sleepScore = SleepScoreCalculator.calculateForSession(
      session: session,
      historySessions: priorSessions,
      morningReports: scoreReports,
      stagesBySession: scoreStages,
    );

    final previousSleepScores = historySessions.map((previous) =>
      SleepScoreCalculator.calculateForSession(
        session: previous,
        historySessions: priorSessions,
        morningReports: scoreReports,
        stagesBySession: scoreStages,
      ).score,
    ).whereType<double>().toList();

    final previousDurations = <double>[];
    final previousEfficiencies = <double>[];
    final previousAwakenings = <double>[];
    for (final previous in historySessions) {
      final previousStages = await widget.database.getStages(previous.id);
      final previousMetrics = SleepSessionMetrics.calculate(
        session: previous,
        stages: previousStages,
      );
      final duration = previousMetrics.sleepDurationMinutes;
      if (duration != null && duration > 0) previousDurations.add(duration.toDouble());
      final efficiency = previousMetrics.sleepEfficiencyPercent;
      if (efficiency != null) previousEfficiencies.add(efficiency);
      if (previousMetrics.hasAwakeSamples) {
        previousAwakenings.add(previousMetrics.awakeningCount.toDouble());
      }
    }

    final previousQuality = <double>[];
    final previousWellbeing = <double>[];
    final previousSleepiness = <double>[];
    for (final previous in historySessions) {
      final previousReport = historyReports[previous.id];
      final quality = previousReport?['sleep_quality'];
      final wellbeing = previousReport?['wellbeing'];
      if (quality is num) previousQuality.add(quality.toDouble());
      if (wellbeing is num) previousWellbeing.add(wellbeing.toDouble());
      final sleepiness = parseAnswers(previousReport)['sleepiness'];
      if (sleepiness is num) previousSleepiness.add(sleepiness.toDouble());
    }

    final currentQuality = report?['sleep_quality'] is num
        ? (report!['sleep_quality'] as num).toDouble()
        : null;
    final currentWellbeing = report?['wellbeing'] is num
        ? (report!['wellbeing'] as num).toDouble()
        : null;
    final currentSleepiness = currentAnswers['sleepiness'] is num
        ? (currentAnswers['sleepiness'] as num).toDouble()
        : null;
    final currentAwakenings = metrics.hasAwakeSamples
        ? metrics.awakeningCount.toDouble()
        : null;

    String durationLabel(int? minutes) => minutes == null
        ? 'Нет достоверных данных'
        : _duration(Duration(minutes: minutes));
    String ratingLabel(Object? value) =>
        value is num ? value.toInt().toString() + ' из 5' : 'Не заполнено';
    String formatDuration(double minutes) {
      final rounded = minutes.round();
      return (rounded ~/ 60).toString() + ' ч ' +
          (rounded % 60).toString() + ' мин';
    }
    String comparisonText(
      String label,
      double? current,
      List<double> previousValues, {
      bool isDuration = false,
      String unit = '',
      String deltaUnit = '',
    }) {
      if (current == null) return label + ': сегодня нет данных.';
      if (previousValues.length < 3) {
        return label + ': недостаточно сопоставимых данных (' +
            previousValues.length.toString() + ' из ' +
            historySessions.length.toString() + ' предыдущих ночей).';
      }
      final average = previousValues.reduce((a, b) => a + b) / previousValues.length;
      final difference = current - average;
      String format(double value) => isDuration
          ? formatDuration(value)
          : value.toStringAsFixed(1) + unit;
      final deltaValue = isDuration
          ? format(difference.abs())
          : difference.abs().toStringAsFixed(1) + deltaUnit;
      final delta = difference > 0
          ? '+' + deltaValue
          : difference < 0
              ? '−' + deltaValue
              : (isDuration ? format(0) : '0.0' + deltaUnit);
      return label + ': сегодня ' + format(current) +
          ', среднее ' + format(average) + ', разница ' + delta +
          ' (n=' + previousValues.length.toString() + ').';
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Краткий итог ночи'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(
                'Фактическая продолжительность сна',
                durationLabel(metrics.sleepDurationMinutes),
                icon: Icons.bedtime_outlined,
              ),
              _detailRow(
                'Время в постели',
                durationLabel(metrics.timeInBedMinutes),
                icon: Icons.hotel_outlined,
              ),
              _detailRow(
                'Эффективность сна',
                metrics.sleepEfficiencyPercent == null
                    ? 'Недостаточно данных'
                    : metrics.sleepEfficiencyPercent!.round().toString() + '%',
                icon: Icons.insights_outlined,
              ),
              _detailRow(
                'Зарегистрированные пробуждения',
                currentAwakenings == null
                    ? 'Нет данных Apple Health'
                    : metrics.awakeningCount.toString(),
                icon: Icons.wb_sunny_outlined,
              ),
              _detailRow(
                'Зарегистрированные звуковые события',
                events.length.toString(),
                icon: Icons.graphic_eq_rounded,
              ),
              if (orderedCategories.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('Категории звуков', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...orderedCategories.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(entry.key + ': ' + entry.value.toString(), style: const TextStyle(fontSize: 13)),
                )),
              ],
              const Divider(height: 22),
              const Text('Твоя утренняя оценка', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Качество сна: ' + ratingLabel(report?['sleep_quality'])),
              Text('Ощущение отдыха: ' + ratingLabel(report?['wellbeing'])),
              Text('Сонливость: ' + ratingLabel(currentAnswers['sleepiness'])),
              if (currentAnswers['skipped'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Text('Субъективная оценка была пропущена.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                ),
              const Divider(height: 22),
              const Text('Сравнение с предыдущими ночами', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(
                'Используются до 7 предыдущих завершённых ночей. В каждом сравнении указано фактическое число доступных наблюдений.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(comparisonText(
                'Продолжительность сна',
                metrics.sleepDurationMinutes?.toDouble(),
                previousDurations,
                isDuration: true,
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(comparisonText(
                'Оценка качества сна 0–100',
                sleepScore.score,
                previousSleepScores,
                unit: ' балла',
                deltaUnit: ' балла',
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(comparisonText(
                'Эффективность сна',
                metrics.sleepEfficiencyPercent,
                previousEfficiencies,
                unit: '%',
                deltaUnit: ' п.п.',
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(comparisonText(
                'Количество пробуждений',
                currentAwakenings,
                previousAwakenings,
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(comparisonText(
                'Качество сна по утренней оценке',
                currentQuality,
                previousQuality,
                unit: ' из 5',
                deltaUnit: ' балла',
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(comparisonText(
                'Ощущение отдыха',
                currentWellbeing,
                previousWellbeing,
                unit: ' из 5',
                deltaUnit: ' балла',
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 5),
              Text(comparisonText(
                'Сонливость',
                currentSleepiness,
                previousSleepiness,
                unit: ' из 5',
                deltaUnit: ' балла',
              ), style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 10),
              const Text(
                'Сравнение описывает личную историю и не устанавливает причинно-следственную связь. Отсутствующие и несопоставимые показатели исключаются.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
              const Divider(height: 22),
              const Text('Оценка качества сна', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              if (sleepScore.score != null) ...[
                Builder(builder: (context) {
                  final value = sleepScore.score!.round();
                  final color = value >= 80
                      ? AppTheme.teal
                      : value >= 60 ? AppTheme.accentPink : const Color(0xFFFF8A8A);
                  return Center(
                    child: Semantics(
                      label: 'Оценка качества сна',
                      value: '$value из 100. Нажмите, чтобы открыть расшифровку.',
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(60),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: AppTheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          builder: (sheetContext) => SafeArea(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Расшифровка оценки сна', style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700,
                                  )),
                                  const SizedBox(height: 5),
                                  Text('Итог: $value из 100. Доступные компоненты нормализованы пропорционально их исходным весам.',
                                    style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                                  const SizedBox(height: 14),
                                  ...sleepScore.components.map((component) {
                                    final contribution = sleepScore.contributionPoints(component);
                                    final effectiveWeight = sleepScore.effectiveWeight(component);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(component.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text('Фактическое значение: ${component.actualValue}',
                                            style: const TextStyle(fontSize: 12)),
                                          Text(
                                            component.score == null
                                              ? 'Не учитывается: недостаточно достоверных данных'
                                              : 'Оценка компонента: ${component.score!.toStringAsFixed(0)} / 100 · исходный вес ${component.weight.toStringAsFixed(0)}% · фактический вес ${effectiveWeight!.toStringAsFixed(1)}% · вклад ${contribution!.toStringAsFixed(1)} балла',
                                            style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(component.detail, style: const TextStyle(
                                            color: AppTheme.muted, fontSize: 11, height: 1.4,
                                          )),
                                        ],
                                      ),
                                    );
                                  }),
                                  const Text('Отсутствующие показатели не заменяются нулями. Это описательная статистика, а не медицинское заключение.',
                                    style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: value / 100),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, progress, child) => SizedBox(
                          width: 108,
                          height: 108,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox.expand(
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 8,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                                  valueColor: AlwaysStoppedAnimation<Color>(color),
                                ),
                              ),
                              child!,
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(value.toString(), style: TextStyle(
                              fontSize: 29, fontWeight: FontWeight.w800, color: color,
                            )),
                            const Text('/ 100', style: TextStyle(
                              color: AppTheme.muted, fontSize: 11,
                            )),
                          ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                }),
                Text(
                  'Учтено компонентов: ${sleepScore.availableComponents} из 4 · исходный вес доступных данных: ${sleepScore.availableWeight.toStringAsFixed(0)}%. Недостающие веса пропорционально перераспределены.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
                ),
              ] else
                Text(
                  'Пока недостаточно данных для надёжной оценки: доступно ${sleepScore.availableComponents} из 4 компонентов и ${sleepScore.availableWeight.toStringAsFixed(0)}% исходного веса. Нужны минимум два компонента и не менее 50% исходного веса.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
                ),
              const SizedBox(height: 6),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Как рассчитана оценка', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                children: sleepScore.components.map((component) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      component.label + ' · ${component.weight.toStringAsFixed(0)}% исходного веса · ' +
                        (component.score == null ? 'не учтено' : component.score!.toStringAsFixed(0) + ' / 100'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text('Фактическое значение: ${component.actualValue}',
                      style: const TextStyle(fontSize: 11)),
                    if (sleepScore.contributionPoints(component) != null)
                      Text('Вклад в итог: ${sleepScore.contributionPoints(component)!.toStringAsFixed(1)} балла',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    Text(component.detail, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
                  ]),
                )).toList(),
              ),
              const Text(
                'Оценка описывает эту ночь по сохранённым данным и не является медицинским заключением. Индивидуальная норма рассчитывается по предыдущим 90 дням; будущие ночи в расчёт не попадают.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {IconData? icon}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[
        Icon(icon, size: 18, color: AppTheme.teal),
        const SizedBox(width: 10),
      ],
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<SleepSession?>(
    future: _future,
    builder: (context, snapshot) {
      final session = snapshot.data ?? widget.session;
      final dateLabel = DateFormat('d MMMM yyyy', 'ru').format(session.startedAt);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Карточка ночи'),
          actions: [
            if (!session.isOpen) IconButton(
              tooltip: 'Переместить в корзину',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('Переместить ночь в корзину?'),
                  content: const Text('Запись и связанные данные сохранятся. Вы сможете восстановить ночь из корзины.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('В корзину')),
                  ],
                ));
                if (confirm != true || !mounted) return;
                await widget.database.moveSessionToTrash(session.id);
                await NotificationService.instance.scheduleTrashExpiry(await widget.database.getTrashExpiryDates());
                if (mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
        body: snapshot.connectionState == ConnectionState.waiting
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Text(dateLabel.toUpperCase(), style: const TextStyle(
                      color: AppTheme.teal, letterSpacing: 1.4, fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                    const SizedBox(height: 8),
                    Text(session.isOpen ? 'Ночная сессия продолжается' : 'Отчёт о ночи',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 18),
                    SectionCard(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Продолжительность', style: TextStyle(color: AppTheme.muted)),
                        const SizedBox(height: 8),
                        Text(_duration(session.duration), style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold,
                        )),
                        const SizedBox(height: 8),
                        Text(session.isOpen
                            ? 'Сессия ещё не завершена — итоговая длительность появится после завершения.'
                            : 'Фактический интервал между сохранёнными временем начала и окончания.',
                            style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                      ],
                    )),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Время', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _detailRow('Нажатие «Ложусь спать»', _dateTime(session.buttonStartedAt), icon: Icons.touch_app_outlined),
                        const Divider(height: 1),
                        _detailRow('Фактическое засыпание', _dateTime(session.actualSleepStartedAt), icon: Icons.bedtime_outlined),
                        const Divider(height: 1),
                        _detailRow('Нажатие «Я проснулась»', _dateTime(session.buttonEndedAt), icon: Icons.touch_app_outlined),
                        const Divider(height: 1),
                        _detailRow('Фактическое пробуждение', _dateTime(session.actualSleepEndedAt), icon: Icons.wb_sunny_outlined),
                        const Divider(height: 1),
                        _detailRow('Источник записи', session.source == 'manual' || session.source == 'manual_entry'
                            ? 'Вручную' : session.source,
                            icon: Icons.info_outline),
                        if (session.userEdited)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Время записи скорректировано вручную. Исходные отметки кнопок сохранены отдельно.',
                              style: TextStyle(color: AppTheme.teal, fontSize: 12, height: 1.4)),
                          ),
                      ],
                    )),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(child: Text('Утренний отчёт', style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold,
                          ))),
                          TextButton.icon(
                            onPressed: () => _editMorningReport(session),
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('Изменить'),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        FutureBuilder<Map<String, Object?>?>(future: _reportFuture, builder: (context, reportState) {
                          final report = reportState.data;
                          if (report == null && session.morningRating == null) return const Text('Оценки ещё не добавлены', style: TextStyle(color: AppTheme.muted));
                          Map<String, dynamic> answers = {};
                          final rawAnswers = report?['answers_json'];
                          if (rawAnswers is String && rawAnswers.isNotEmpty) {
                            try {
                              final decoded = jsonDecode(rawAnswers);
                              if (decoded is Map<String, dynamic>) answers = decoded;
                            } catch (_) {}
                          }
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (session.morningRating != null) Text('Самочувствие: ${session.morningRating} из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (report?['sleep_quality'] != null) Text('Качество сна: ${report!['sleep_quality']} из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (answers['sleepiness'] != null) Text('Сонливость: ${answers['sleepiness']} из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if ((answers['comment'] as String?)?.trim().isNotEmpty == true)
                              Padding(padding: const EdgeInsets.only(top: 8), child: Text(answers['comment'] as String)),
                            if (answers['skipped'] == true) const Text('Субъективная оценка пропущена', style: TextStyle(color: AppTheme.muted)),
                          ]);
                        }),
                        const SizedBox(height: 14),
                        const Text('Заметки этой ночи', style: TextStyle(color: AppTheme.muted)),
                        const SizedBox(height: 6),
                        FutureBuilder<List<SleepNote>>(
                          future: _notesFuture,
                          builder: (context, noteSnapshot) {
                            final notes = noteSnapshot.data ?? const <SleepNote>[];
                            if (noteSnapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(padding: EdgeInsets.all(8),
                                child: LinearProgressIndicator());
                            }
                            if (notes.isEmpty && (session.note?.trim().isEmpty ?? true)) {
                              return const Text('Заметки пока не добавлены',
                                style: TextStyle(color: AppTheme.muted));
                            }
                            return Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (session.note?.trim().isNotEmpty ?? false)
                                  Padding(padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(session.note!, style: const TextStyle(height: 1.5))),
                                ...notes.map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('• ${note.text}', style: const TextStyle(height: 1.5)),
                                )),
                              ]);
                          },
                        ),
                        const SizedBox(height: 6),
                        const Text('Добавлять, редактировать и удалять отдельные заметки можно в разделе «Заметки».',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                      ],
                    )),
                    const SizedBox(height: 12),
                    ScreenTimeCard(database: widget.database, session: session),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Фазы сна', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SleepSessionMetricsCard(session: session, stagesFuture: _stagesFuture),
                      const SizedBox(height: 12),
                      FutureBuilder<List<Map<String, Object?>>>(future: _stagesFuture, builder: (context, state) {
                        final rows = state.data ?? const <Map<String, Object?>>[];
                        if (state.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                        if (rows.isEmpty) return const Text('Источник не предоставил детализацию фаз для этой ночи.', style: TextStyle(color: AppTheme.muted));
                        return Column(children: rows.map((row) {
                          final from = DateTime.parse(row['started_at']! as String).toLocal();
                          final to = DateTime.parse(row['ended_at']! as String).toLocal();
                          final mins = to.difference(from).inMinutes;
                          return _detailRow(row['stage']! as String, '$mins мин · ${DateFormat('HH:mm').format(from)}–${DateFormat('HH:mm').format(to)}');
                        }).toList());
                      }),
                      const Divider(height: 24),
                      const Text('Физиологические показатели', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, Object?>>>(future: _metricsFuture, builder: (context, state) {
                        final rows = state.data ?? const <Map<String, Object?>>[];
                        if (state.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                        if (rows.isEmpty) return const Text('За эту ночь доступные физиологические измерения не импортированы.', style: TextStyle(color: AppTheme.muted));
                        final summaries = SleepMetricSummary.fromSamples(rows);
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final summary in summaries) ...[
                            _detailRow(
                              summary.metricType,
                              'Среднее ${summary.average.toStringAsFixed(1)} ${summary.unit} · мин. ${summary.minimum.toStringAsFixed(1)} · макс. ${summary.maximum.toStringAsFixed(1)}',
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${summary.count} измерений · ${DateFormat('HH:mm').format(summary.firstMeasuredAt)}–${DateFormat('HH:mm').format(summary.lastMeasuredAt)}',
                                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                              ),
                            ),
                          ],
                          const Divider(height: 18),
                          const Text('Отдельные измерения', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          ...(rows.where((row) =>
                            row['metric_type'] is String &&
                            row['value'] is num &&
                            (row['value'] as num).toDouble().isFinite &&
                            row['measured_at'] is String
                          ).toList()
                            ..sort((a, b) => DateTime.parse(a['measured_at']! as String).compareTo(DateTime.parse(b['measured_at']! as String))))
                            .map((row) => _detailRow(
                              row['metric_type']! as String,
                              '${(row['value'] as num).toStringAsFixed(1)} ${row['unit']} · ${DateFormat('HH:mm').format(DateTime.parse(row['measured_at']! as String).toLocal())}',
                            )),
                        ]);
                      }),
                      const SizedBox(height: 8),
                      const Text('Показываются только измерения, реально полученные из Apple Health. Их отсутствие не заменяется оценками.', style: TextStyle(color: AppTheme.teal, fontSize: 12, height: 1.4)),
                    ])),
                    const SizedBox(height: 12),
                    SleepEventTimelineCard(eventsFuture: _timelineFuture),
                    const SizedBox(height: 12),
                    SectionCard(child: FutureBuilder<List<Map<String, Object?>>>(
                      future: _climateFuture,
                      builder: (context, climateState) {
                        if (climateState.connectionState == ConnectionState.waiting) {
                          return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Микроклимат спальни', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            SizedBox(height: 10),
                            LinearProgressIndicator(),
                          ]);
                        }
                        if (climateState.hasError) {
                          return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Микроклимат спальни', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('Не удалось загрузить измерения датчика.', style: TextStyle(color: AppTheme.muted)),
                          ]);
                        }
                        final rows = climateState.data ?? const <Map<String, Object?>>[];
                        final temperature = ClimateMetricSummary.fromSamples(
                          rows, metricType: 'temperature',
                          expectedInterval: const Duration(minutes: 15),
                        );
                        final humidity = ClimateMetricSummary.fromSamples(
                          rows, metricType: 'humidity',
                          expectedInterval: const Duration(minutes: 15),
                        );
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Микроклимат спальни', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Фактические показания выбранного датчика в интервале этой ночи.',
                            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                          const SizedBox(height: 12),
                          _NightClimateMetric(
                            title: 'Температура',
                            summary: temperature,
                            samples: rows.where((row) => row['metric_type'] == 'temperature').toList(),
                          ),
                          const Divider(height: 18, color: AppTheme.surfaceLight),
                          _NightClimateMetric(
                            title: 'Влажность',
                            summary: humidity,
                            samples: rows.where((row) => row['metric_type'] == 'humidity').toList(),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            rows.isEmpty
                              ? 'За эту ночь измерения не поступали. Отсутствующие значения не восстанавливаются и не подставляются.'
                              : 'Всего фактических измерений: ${rows.length}. Покрытие отражает только частоту полученных точек и не гарантирует непрерывный мониторинг.',
                            style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
                          ),
                        ]);
                      },
                    )),
                    const SizedBox(height: 12),
                    WeatherNightDetailCard(database: widget.database, session: session),
                  ],
                ),
              ),
      );
    },
  );
}


class _NightClimateMetric extends StatelessWidget {
  const _NightClimateMetric({
    required this.title,
    required this.summary,
    required this.samples,
  });
  final String title;
  final ClimateMetricSummary? summary;
  final List<Map<String, Object?>> samples;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    if (value == null) {
      return Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        const Text('Нет данных', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
      ]);
    }
    final first = DateFormat('HH:mm').format(value.firstMeasuredAt);
    final last = DateFormat('HH:mm').format(value.lastMeasuredAt);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Мин. ${value.minimum.toStringAsFixed(1)} ${value.unit} · сред. ${value.average.toStringAsFixed(1)} ${value.unit} · макс. ${value.maximum.toStringAsFixed(1)} ${value.unit}'),
      Text('Колебания за ночь (σ): ${value.standardDeviation.toStringAsFixed(2)} ${value.unit}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      Text('Последнее: ${value.lastValue.toStringAsFixed(1)} ${value.unit} · ${DateFormat('HH:mm').format(value.lastMeasuredAt)}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      Text('${value.count} точек · ${first}–${last}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      if (samples.length >= 2) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          width: double.infinity,
          child: CustomPaint(painter: _ClimateSparklinePainter(
            values: samples.map((row) => (row['value'] as num).toDouble()).toList(),
            color: title == 'Температура' ? AppTheme.teal : AppTheme.accentPink,
          )),
        ),
      ],
      if (value.coveragePercent != null)
        Text('Расчётное покрытие интервала: ${value.coveragePercent!.toStringAsFixed(0)}%',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}


class _ClimateSparklinePainter extends CustomPainter {
  const _ClimateSparklinePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    final usableHeight = size.height - 8;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = 4 + (size.width - 8) * i / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[i] - minValue) / range;
      final y = 4 + (1 - normalized) * usableHeight;
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(points.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ClimateSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
