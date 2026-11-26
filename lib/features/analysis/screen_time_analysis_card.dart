import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../models/screen_time_entry.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../diary/sleep_session_detail_screen.dart';
import '../diary/sleep_session_metrics.dart';
import 'screen_time_sleep_analysis.dart';

class ScreenTimeAnalysisCard extends StatefulWidget {
  const ScreenTimeAnalysisCard({
    super.key, required this.database, required this.sessions, required this.periodLabel,
  });
  final SleepDatabase database;
  final List<SleepSession> sessions;
  final String periodLabel;

  @override
  State<ScreenTimeAnalysisCard> createState() => _ScreenTimeAnalysisCardState();
}

class _ScreenTimeAnalysisCardState extends State<ScreenTimeAnalysisCard> {
  late Future<_ScreenTimeAnalysisData> _future;
  int _windowMinutes = 60;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ScreenTimeAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions) ||
        !identical(oldWidget.database, widget.database) ||
        oldWidget.periodLabel != widget.periodLabel) {
      _future = _load();
    }
  }

  Future<_ScreenTimeAnalysisData> _load() async {
    final sessions = widget.sessions.where((session) =>
      session.deletedAt == null && session.endedAt != null &&
      session.endedAt!.isAfter(session.startedAt)
    ).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final stored = await widget.database.getAppMetadataByPrefix(ScreenTimeEntry.storagePrefix);
    final legacy = await widget.database.getAppMetadataByPrefix('sleep_tracker_screen_time_v1_');
    final entries = <String, ScreenTimeEntry>{};
    final damaged = <String>{};
    final invalidLastUse = <String>{};
    for (final session in sessions) {
      final raw = stored[ScreenTimeEntry.keyFor(session.id, _windowMinutes)];
      if (raw == null || raw.isEmpty) continue;
      try {
        final entry = ScreenTimeEntry.decode(raw);
        if (entry.sessionId != session.id || entry.windowMinutes != _windowMinutes) {
          throw const FormatException('Отметка относится к другой ночи или окну.');
        }
        entries[session.id] = entry;
      } on FormatException {
        damaged.add(session.id);
      }
    }
    final legacyCount = sessions.where((session) {
      final raw = legacy['sleep_tracker_screen_time_v1_${session.id}'];
      return raw != null && raw.isNotEmpty;
    }).length;
    final ids = entries.keys.toList();
    final stagesBySession = ids.isEmpty
        ? <String, List<Map<String, Object?>>>{}
        : await widget.database.getStagesForSessions(ids);
    final morningReportsBySession = ids.isEmpty
        ? <String, Map<String, Object?>>{}
        : await widget.database.getMorningReportsForSessions(ids);
    final sleepOnsets = <String, DateTime?>{};
    final durationSamples = <ScreenTimeSleepSample>[];
    final lastUseSamples = <ScreenTimeSleepSample>[];
    for (final session in sessions.where((item) => entries.containsKey(item.id))) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
      final referenceStart = metrics.sleepOnsetAt ?? session.actualSleepStartedAt ?? session.startedAt;
      sleepOnsets[session.id] = metrics.sleepOnsetAt;
      final entry = entries[session.id]!;
      final lastUseIsValid = entry.lastUseAt == null || (() {
        final elapsed = referenceStart.difference(entry.lastUseAt!);
        return !elapsed.isNegative && elapsed <= const Duration(hours: 24);
      })();
      if (!lastUseIsValid) invalidLastUse.add(session.id);
      final morning = morningReportsBySession[session.id] ?? const <String, Object?>{};
      final sleepStartAxis = ScreenTimeSleepAnalysis.sleepStartAxis(metrics.sleepOnsetAt);
      final sleepDuration = metrics.sleepDurationMinutes?.toDouble();
      final efficiency = metrics.sleepEfficiencyPercent;
      final awakenings = metrics.hasAwakeSamples &&
          metrics.stageCoveragePercent != null && metrics.stageCoveragePercent! >= 80
          ? metrics.awakeningCount.toDouble() : null;
      final rating = session.morningRating?.toDouble();
      final quality = (morning['sleep_quality'] as num?)?.toDouble();
      final wellbeing = (morning['wellbeing'] as num?)?.toDouble();
      if (entry.screenMinutes != null) {
        durationSamples.add(ScreenTimeSleepSample(
          exposureMinutes: entry.screenMinutes!.toDouble(),
          sleepStartMinutesOfDay: sleepStartAxis,
          sleepDurationMinutes: sleepDuration,
          sleepEfficiencyPercent: efficiency,
          awakeningCount: awakenings,
          morningRating: rating, sleepQuality: quality, wellbeing: wellbeing,
        ));
      }
      if (entry.lastUseAt != null && lastUseIsValid && metrics.sleepOnsetAt != null) {
        final gap = metrics.sleepOnsetAt!.difference(entry.lastUseAt!).inMinutes;
        if (gap >= 0 && gap <= 1440) {
          lastUseSamples.add(ScreenTimeSleepSample(
            exposureMinutes: gap.toDouble(),
            sleepStartMinutesOfDay: sleepStartAxis,
            sleepDurationMinutes: sleepDuration,
            sleepEfficiencyPercent: efficiency,
            awakeningCount: awakenings,
            morningRating: rating, sleepQuality: quality, wellbeing: wellbeing,
          ));
        }
      }
    }
    return _ScreenTimeAnalysisData(
      sessions: sessions, entries: Map.unmodifiable(entries),
      damagedSessionIds: Set.unmodifiable(damaged),
      invalidLastUseSessionIds: Set.unmodifiable(invalidLastUse),
      lastUseWithoutOnsetCount: entries.values.where((entry) => entry.lastUseAt != null && sleepOnsets[entry.sessionId] == null).length,
      durationEntryCount: entries.values.where((entry) => entry.screenMinutes != null).length,
      lastUseEntryCount: entries.values.where((entry) => entry.lastUseAt != null).length,
      legacyEntriesCount: legacyCount, sleepOnsets: Map.unmodifiable(sleepOnsets),
      durationComparison: ScreenTimeSleepAnalysis.compare(durationSamples),
      lastUseComparison: ScreenTimeSleepAnalysis.compare(lastUseSamples),
    );
  }

  Future<void> _changeWindow(int value) async {
    if (value == _windowMinutes) return;
    setState(() {
      _windowMinutes = value;
      _future = _load();
    });
  }

  Future<({DateTime reference, bool hasActualOnset})> _sleepReference(
    SleepSession session, _ScreenTimeAnalysisData data,
  ) async {
    final existing = data.sleepOnsets[session.id];
    if (existing != null) return (reference: existing, hasActualOnset: true);
    if (session.actualSleepStartedAt != null) {
      return (reference: session.actualSleepStartedAt!, hasActualOnset: true);
    }
    final stages = await widget.database.getStages(session.id);
    final metrics = SleepSessionMetrics.calculate(session: session, stages: stages);
    final onset = metrics.sleepOnsetAt;
    return (reference: onset ?? session.startedAt, hasActualOnset: onset != null);
  }

  Future<void> _editEntry(
    SleepSession session, ScreenTimeEntry? existing, _ScreenTimeAnalysisData data,
  ) async {
    if (data.damagedSessionIds.contains(session.id)) return;
    final sleepReference = await _sleepReference(session, data);
    if (!mounted) return;
    final minutesController = TextEditingController(
      text: existing?.screenMinutes?.toString() ?? '',
    );
    var includeLastUse = existing?.lastUseAt != null;
    var selectedTime = existing?.lastUseAt == null
        ? TimeOfDay.fromDateTime(sleepReference.reference.subtract(const Duration(minutes: 30)))
        : TimeOfDay.fromDateTime(existing!.lastUseAt!);
    var validationError = '';
    final result = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Экранное время · ${DateFormat('d MMM yyyy', 'ru').format(session.startedAt)}'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Оцени суммарное использование экранов за последние $_windowMinutes минут до засыпания. Можно заполнить одно поле или оба.',
                style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: minutesController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                decoration: InputDecoration(
                  labelText: 'Минут экранного времени',
                  helperText: 'От 0 до $_windowMinutes минут; поле можно оставить пустым',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeLastUse,
                onChanged: (value) => setDialogState(() {
                  includeLastUse = value ?? false;
                  validationError = '';
                }),
                title: const Text('Указать время последнего использования'),
                subtitle: const Text('В пределах 24 часов до засыпания'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (includeLastUse)
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: dialogContext, initialTime: selectedTime,
                      helpText: 'Когда в последний раз использовался экран?',
                    );
                    if (picked != null) setDialogState(() { selectedTime = picked; validationError = ''; });
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text('Последнее использование: ${selectedTime.format(context)}'),
                ),
              if (!sleepReference.hasActualOnset)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Фактическое время засыпания пока не определено. Время сохранится как ориентир по началу записи, но не попадёт в сравнение интервала до засыпания.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
                ),
              if (validationError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(validationError, style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
                ),
            ],
          )),
          actions: [
            if (existing != null)
              TextButton(onPressed: () => Navigator.pop(dialogContext, 'delete'), child: const Text('Удалить отметку')),
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final rawMinutes = minutesController.text.trim();
                final minutes = rawMinutes.isEmpty ? null : int.tryParse(rawMinutes);
                if (rawMinutes.isNotEmpty && (minutes == null || minutes < 0 || minutes > _windowMinutes)) {
                  setDialogState(() => validationError = 'Введи целое число от 0 до $_windowMinutes.');
                  return;
                }
                if (rawMinutes.isNotEmpty && minutes == null) {
                  setDialogState(() => validationError = 'Введи целое число минут.');
                  return;
                }
                if (minutes == null && !includeLastUse) {
                  setDialogState(() => validationError = 'Укажи длительность экранного времени и/или время последнего использования.');
                  return;
                }
                DateTime? lastUseAt;
                if (includeLastUse) {
                  try {
                    lastUseAt = ScreenTimeEntry.resolveLastUseTime(
                      sleepReference.reference, hour: selectedTime.hour, minute: selectedTime.minute,
                    );
                  } on FormatException catch (error) {
                    setDialogState(() => validationError = error.message);
                    return;
                  }
                }
                final entry = ScreenTimeEntry(
                  sessionId: session.id, windowMinutes: _windowMinutes,
                  screenMinutes: minutes, lastUseAt: lastUseAt, updatedAt: DateTime.now(),
                );
                try {
                  entry.validateForSleepStart(sleepReference.reference);
                } on FormatException catch (error) {
                  setDialogState(() => validationError = error.message);
                  return;
                }
                Navigator.pop(dialogContext, entry);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    minutesController.dispose();
    if (!mounted || result == null) return;
    final key = ScreenTimeEntry.keyFor(session.id, _windowMinutes);
    if (result == 'delete') {
      await widget.database.setAppMetadata(key, '');
    } else if (result is ScreenTimeEntry) {
      await widget.database.setAppMetadata(key, result.encode());
    }
    if (mounted) setState(() => _future = _load());
  }

  String _entryDateRange(_ScreenTimeAnalysisData data) {
    final recordedSessions = data.sessions.where((session) => data.entries.containsKey(session.id)).toList();
    if (recordedSessions.isEmpty) return 'нет отметок';
    final first = recordedSessions.last.startedAt;
    final last = recordedSessions.first.startedAt;
    return '${DateFormat('d MMM yyyy', 'ru').format(first)} — ${DateFormat('d MMM yyyy', 'ru').format(last)}';
  }

  String _minutes(double value) => '${value.round()} мин';
  String _duration(double value) {
    final minutes = value.round();
    return '${minutes ~/ 60} ч ${(minutes % 60).toString().padLeft(2, '0')} мин';
  }

  String _metricLabel(ScreenTimeSleepMetric metric) => switch (metric) {
    ScreenTimeSleepMetric.sleepStartTime => 'Фактическое время засыпания',
    ScreenTimeSleepMetric.sleepDuration => 'Продолжительность сна',
    ScreenTimeSleepMetric.sleepEfficiency => 'Эффективность сна',
    ScreenTimeSleepMetric.awakenings => 'Подтверждённые пробуждения',
    ScreenTimeSleepMetric.morningRating => 'Утренняя оценка',
    ScreenTimeSleepMetric.sleepQuality => 'Качество сна',
    ScreenTimeSleepMetric.wellbeing => 'Самочувствие',
  };

  String _formatMetric(ScreenTimeSleepMetric metric, double value) => switch (metric) {
    ScreenTimeSleepMetric.sleepStartTime => ScreenTimeSleepAnalysis.formatSleepStartMinutes(value),
    ScreenTimeSleepMetric.sleepDuration => _duration(value),
    ScreenTimeSleepMetric.sleepEfficiency => '${value.toStringAsFixed(1)}%',
    ScreenTimeSleepMetric.awakenings => value.toStringAsFixed(1),
    ScreenTimeSleepMetric.morningRating || ScreenTimeSleepMetric.sleepQuality || ScreenTimeSleepMetric.wellbeing => '${value.toStringAsFixed(1)} / 5',
  };

  String _formatDifference(ScreenTimeSleepMetric metric, double value) {
    final sign = value > 0 ? '+' : '';
    return switch (metric) {
      ScreenTimeSleepMetric.sleepStartTime => value.abs() < 0.5
          ? 'без сдвига'
          : '${value.abs().round()} мин ${value > 0 ? 'позже' : 'раньше'}',
      ScreenTimeSleepMetric.sleepDuration => '$sign${value.round()} мин',
      ScreenTimeSleepMetric.sleepEfficiency => '$sign${value.toStringAsFixed(1)} п.п.',
      ScreenTimeSleepMetric.awakenings => '$sign${value.toStringAsFixed(1)}',
      ScreenTimeSleepMetric.morningRating || ScreenTimeSleepMetric.sleepQuality || ScreenTimeSleepMetric.wellbeing => '$sign${value.toStringAsFixed(1)} / 5',
    };
  }

  Widget _metricRows(ScreenTimeGroupSummary group) => Column(
    children: ScreenTimeSleepMetric.values.map((metric) {
      final summary = group.metric(metric);
      final value = summary.average == null ? 'нет данных' : _formatMetric(metric, summary.average!);
      return _row('${_metricLabel(metric)} (n=${summary.validSamples})', value);
    }).toList(),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11))),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _comparisonBlock({
    required String title, required ScreenTimeComparison comparison,
    required String lowerLabel, required String upperLabel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Медиана: ${_minutes(comparison.medianExposureMinutes)}',
        style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 8),
      Text('$lowerLabel · ${comparison.lowerGroup.nights} ночей', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      _metricRows(comparison.lowerGroup),
      const Divider(height: 18, color: AppTheme.surfaceLight),
      Text('$upperLabel · ${comparison.upperGroup.nights} ночей', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      _metricRows(comparison.upperGroup),
      const SizedBox(height: 6),
      for (final metric in ScreenTimeSleepMetric.values)
        _row('Разница · ${_metricLabel(metric)}',
          comparison.differenceFor(metric) == null
              ? 'недостаточно данных'
              : _formatDifference(metric, comparison.differenceFor(metric)!)),
      if (!comparison.hasSufficientGroups)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Для сравнения нужны минимум 4 ночи в каждой группе. Одинаковые значения не разделяются искусственно.',
            style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
        ),
    ],
  );

  Widget _sessionRow(SleepSession session, _ScreenTimeAnalysisData data) {
    final entry = data.entries[session.id];
    final damaged = data.damagedSessionIds.contains(session.id);
    final onset = data.sleepOnsets[session.id];
    final details = damaged
        ? 'Сохранённая отметка повреждена; она не изменена и не включена в анализ.'
        : entry == null
            ? 'Отметка не добавлена'
            : [
                if (onset != null) 'засыпание в ${DateFormat('HH:mm').format(onset)}',
                if (entry.screenMinutes != null) '${entry.screenMinutes} мин за $_windowMinutes мин',
                if (entry.lastUseAt != null) 'последний раз в ${DateFormat('HH:mm').format(entry.lastUseAt!)}',
                if (data.invalidLastUseSessionIds.contains(session.id)) 'время последнего использования вне допустимого интервала — исправь',
                'введено вручную',
              ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(DateFormat('d MMM yyyy · HH:mm', 'ru').format(session.startedAt),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      subtitle: Text(details, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      trailing: IconButton(
        tooltip: entry == null ? 'Добавить отметку' : 'Изменить отметку',
        onPressed: damaged ? null : () => _editEntry(session, entry, data),
        icon: Icon(entry == null ? Icons.add_circle_outline : Icons.edit_outlined, size: 19),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SleepSessionDetailScreen(database: widget.database, session: session),
      )),
    );
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: FutureBuilder<_ScreenTimeAnalysisData>(
      future: _future,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) {
          return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Экранное время перед сном', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 10), LinearProgressIndicator(),
          ]);
        }
        if (state.hasError) return Text('Не удалось загрузить ручные отметки экранного времени: ${state.error}');
        final data = state.data ?? _ScreenTimeAnalysisData.empty();
        final completed = data.sessions.length;
        final recorded = data.entries.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Экранное время перед сном', style: TextStyle(fontWeight: FontWeight.w600))),
              const Text('Ручной ввод', style: TextStyle(color: AppTheme.muted, fontSize: 10)),
            ]),
            const SizedBox(height: 5),
            const Text('Отмечай приблизительное время использования экранов и/или время последнего использования. Содержимое экрана, сайты, приложения и сообщения не собираются.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30 мин')),
                ButtonSegment(value: 60, label: Text('60 мин')),
                ButtonSegment(value: 120, label: Text('120 мин')),
              ],
              selected: {_windowMinutes},
              onSelectionChanged: (values) => _changeWindow(values.first),
            ),
            const SizedBox(height: 8),
            Text('Период: ${widget.periodLabel} · заполнено $recorded из $completed завершённых ночей (длительность: ${data.durationEntryCount}, последнее использование: ${data.lastUseEntryCount})',
              style: const TextStyle(color: AppTheme.teal, fontSize: 11)),
            if (recorded > 0) ...[
              const SizedBox(height: 3),
              Text('Даты отметок: ${_entryDateRange(data)}', style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
            ],
            if (data.legacyEntriesCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Найдено старых отметок: ${data.legacyEntriesCount}. Они сохранены, но не включены в расчёт, так как для них не указано окно 30/60/120 минут.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
              ),
            if (data.lastUseWithoutOnsetCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Время последнего использования сохранено для ${data.lastUseWithoutOnsetCount} ночей, но пока не включено в сравнение: фактическое время засыпания не определено.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
              ),
            if (data.invalidLastUseSessionIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Время последнего использования не попадает в интервал до засыпания в ${data.invalidLastUseSessionIds.length} отметках. Они сохранены; их можно исправить.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
              ),
            if (data.damagedSessionIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Повреждённых отметок: ${data.damagedSessionIds.length}. Они не изменены и исключены из расчёта.',
                  style: const TextStyle(color: AppTheme.accentPink, fontSize: 10)),
              ),
            if (data.durationComparison != null) ...[
              const SizedBox(height: 14),
              _comparisonBlock(
                title: 'По суммарной длительности использования экранов',
                comparison: data.durationComparison!,
                lowerLabel: 'Не больше медианы экранного времени',
                upperLabel: 'Больше медианы экранного времени',
              ),
            ] else if (recorded == 0)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Для выбранного окна пока нет ручных отметок длительности.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11)),
              ),
            if (data.lastUseComparison != null) ...[
              const Divider(height: 24, color: AppTheme.surfaceLight),
              _comparisonBlock(
                title: 'По времени последнего использования',
                comparison: data.lastUseComparison!,
                lowerLabel: 'Ближе к засыпанию',
                upperLabel: 'Раньше до засыпания',
              ),
            ],
            if (data.sessions.isNotEmpty) ...[
              const Divider(height: 22, color: AppTheme.surfaceLight),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Отметки по ночам', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('Добавить или изменить данные для окна $_windowMinutes минут',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                children: [
                  for (final session in data.sessions) _sessionRow(session, data),
                ],
              ),
            ],
            const SizedBox(height: 6),
            const Text('Группы разделяются по медиане фактических ручных значений. Разница описывает наблюдаемую связь и не доказывает причинного влияния экранов на сон. Пустые значения не считаются нулём; сравнение требует минимум четырёх валидных ночей в каждой группе.',
              style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4)),
          ],
        );
      },
    ),
  );
}

class _ScreenTimeAnalysisData {
  const _ScreenTimeAnalysisData({
    required this.sessions, required this.entries, required this.damagedSessionIds,
    required this.invalidLastUseSessionIds, required this.lastUseWithoutOnsetCount,
    required this.durationEntryCount,
    required this.lastUseEntryCount, required this.legacyEntriesCount, required this.sleepOnsets,
    required this.durationComparison, required this.lastUseComparison,
  });

  factory _ScreenTimeAnalysisData.empty() => const _ScreenTimeAnalysisData(
    sessions: [], entries: {}, damagedSessionIds: {}, invalidLastUseSessionIds: {},
    lastUseWithoutOnsetCount: 0, durationEntryCount: 0, lastUseEntryCount: 0, legacyEntriesCount: 0,
    sleepOnsets: {}, durationComparison: null, lastUseComparison: null,
  );

  final List<SleepSession> sessions;
  final Map<String, ScreenTimeEntry> entries;
  final Set<String> damagedSessionIds;
  final Set<String> invalidLastUseSessionIds;
  final int lastUseWithoutOnsetCount;
  final int durationEntryCount;
  final int lastUseEntryCount;
  final int legacyEntriesCount;
  final Map<String, DateTime?> sleepOnsets;
  final ScreenTimeComparison? durationComparison;
  final ScreenTimeComparison? lastUseComparison;
}