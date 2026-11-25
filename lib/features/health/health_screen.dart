import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/sleep_database.dart';
import '../../data/pdf_report_service.dart';
import '../diary/sleep_session_detail_screen.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';
import 'health_report_service.dart';
import 'health_report_history_card.dart';
import 'health_day_tag_library.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  late Future<_HealthSnapshot> _future;
  late Future<List<HealthReportSnapshot>> _healthReportsFuture;
  int _days = 30;
  DateTimeRange? _customRange;
  DateTimeRange? _comparisonRange;
  DateTime _selectedDay = DateTime.now();
  late Future<_HealthDayEntry> _dayEntryFuture;
  late Future<Map<DateTime, _HealthDayEntry>> _dayEntriesFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _healthReportsFuture = _loadHealthReports();
    _dayEntryFuture = _loadDayEntry(_selectedDay);
    _dayEntriesFuture = _loadAllHealthDayEntries();
  }

  Future<Map<DateTime, _HealthDayEntry>> _loadAllHealthDayEntries() async {
    final rows = await widget.database.getAppMetadataByPrefix('health_day_');
    final result = <DateTime, _HealthDayEntry>{};
    for (final entry in rows.entries) {
      final dateText = entry.key.substring('health_day_'.length);
      final day = DateTime.tryParse(dateText);
      if (day == null) continue;
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is! Map) continue;
        final note = decoded['note'] is String ? decoded['note'] as String : '';
        final tags = decoded['tags'] is List ? (decoded['tags'] as List).whereType<String>().toSet().toList() : <String>[];
        if (note.isNotEmpty || tags.isNotEmpty) result[DateTime(day.year, day.month, day.day)] = _HealthDayEntry(note: note, tags: tags);
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  String _dayMetadataKey(DateTime day) => 'health_day_${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<_HealthDayEntry> _loadDayEntry(DateTime day) async {
    final raw = await widget.database.getAppMetadata(_dayMetadataKey(day));
    if (raw == null || raw.isEmpty) return const _HealthDayEntry(note: '', tags: []);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _HealthDayEntry(note: '', tags: []);
      final note = decoded['note'] is String ? decoded['note'] as String : '';
      final tags = decoded['tags'] is List ? (decoded['tags'] as List).whereType<String>().toSet().toList() : <String>[];
      return _HealthDayEntry(note: note, tags: tags);
    } catch (_) {
      return const _HealthDayEntry(note: '', tags: []);
    }
  }

  Future<void> _selectHealthDay(DateTime day) async {
    final selected = DateTime(day.year, day.month, day.day);
    setState(() {
      _selectedDay = selected;
      _dayEntryFuture = _loadDayEntry(selected);
    });
  }

  Future<void> _editHealthDay() async {
    final existing = await _dayEntryFuture;
    if (!mounted) return;
    const presets = ['Стресс', 'Кофеин', 'Тренировка', 'Болезнь', 'Боль', 'Лекарства', 'Путешествие', 'Поздний ужин', 'Алкоголь', 'Дневной сон'];
    final rawCustomTags = await widget.database.getAppMetadata(HealthDayTagLibrary.storageKey);
    late List<String> customTags;
    try {
      customTags = HealthDayTagLibrary.decode(rawCustomTags)
          .where((tag) => !presets.contains(tag))
          .toList();
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Список собственных отметок повреждён и не был изменён: ${error.message}')),
        );
      }
      return;
    }
    final noteController = TextEditingController(text: existing.note);
    final tagController = TextEditingController();
    final tags = existing.tags.toSet();
    final result = await showDialog<_HealthDayEntry>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Запись за ${_date(_selectedDay)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Отметки дня', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final tag in [...presets, ...customTags])
                    FilterChip(
                      label: Text(tag),
                      selected: tags.contains(tag),
                      onSelected: (selected) => setDialogState(() {
                        if (selected) {
                          tags.add(tag);
                        } else {
                          tags.remove(tag);
                        }
                      }),
                    ),
                  for (final tag in tags.where((tag) =>
                      !presets.contains(tag) && !customTags.contains(tag)).toList())
                    InputChip(
                      label: Text(tag),
                      onDeleted: () => setDialogState(() => tags.remove(tag)),
                    ),
                ]),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final updated = await _manageCustomHealthTags(customTags);
                      if (updated == null) return;
                      customTags = updated;
                      await widget.database.setAppMetadata(
                        HealthDayTagLibrary.storageKey,
                        HealthDayTagLibrary.encode(customTags),
                      );
                      if (context.mounted) setDialogState(() {});
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 17),
                    label: const Text('Управлять своими отметками'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: tagController, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: 'Новая собственная отметка', hintText: 'Например, поздний подъём'))),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      final value = tagController.text.trim();
                      if (value.isEmpty) return;
                      setDialogState(() {
                        tags.add(value);
                        if (!presets.contains(value)) {
                          customTags = HealthDayTagLibrary.add(customTags, value);
                        }
                      });
                      tagController.clear();
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(controller: noteController, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Комментарий к дню', hintText: 'Самочувствие, события, лекарства и другие заметки')),
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, _HealthDayEntry(note: noteController.text.trim(), tags: tags.toList()..sort())), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    noteController.dispose();
    tagController.dispose();
    if (result == null || !mounted) return;
    await widget.database.setAppMetadata(
      HealthDayTagLibrary.storageKey,
      HealthDayTagLibrary.encode(customTags),
    );
    await widget.database.setAppMetadata(_dayMetadataKey(_selectedDay), jsonEncode(result.toJson()));
    if (mounted) setState(() {
      _dayEntryFuture = Future.value(result);
      _dayEntriesFuture = _loadAllHealthDayEntries();
    });
  }

  Future<List<String>?> _manageCustomHealthTags(List<String> initial) async {
    var working = [...initial];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Мои отметки'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Переименование и удаление меняют только список для будущих записей. Уже сохранённые дни останутся без изменений.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  if (working.isEmpty)
                    const Text('Собственных отметок пока нет.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  for (final tag in working)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tag),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Переименовать',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () async {
                              final controller = TextEditingController(text: tag);
                              final value = await showDialog<String>(
                                context: dialogContext,
                                builder: (editContext) => AlertDialog(
                                  title: const Text('Переименовать отметку'),
                                  content: TextField(
                                    controller: controller,
                                    autofocus: true,
                                    textCapitalization: TextCapitalization.sentences,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(editContext),
                                      child: const Text('Отмена'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(editContext, controller.text.trim()),
                                      child: const Text('Сохранить'),
                                    ),
                                  ],
                                ),
                              );
                              controller.dispose();
                              if (value == null) return;
                              try {
                                setDialogState(() {
                                  working = HealthDayTagLibrary.rename(working, tag, value);
                                });
                              } on ArgumentError catch (error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.message?.toString() ?? 'Не удалось переименовать отметку.')),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Удалить из списка',
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('Удалить отметку из списка?'),
                                  content: Text('«$tag» останется в уже сохранённых днях, но больше не будет предлагаться для новых записей.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(confirmContext, false),
                                      child: const Text('Отмена'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(confirmContext, true),
                                      child: const Text('Удалить'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                setDialogState(() {
                                  working = HealthDayTagLibrary.remove(working, tag);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, working),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return null;
    await widget.database.setAppMetadata(
      HealthDayTagLibrary.storageKey,
      HealthDayTagLibrary.encode(result),
    );
    return result;
  }

  Future<List<HealthReportSnapshot>> _loadHealthReports() =>
      HealthReportService(widget.database).generateClosedReports();

  Future<void> _exportHealthReport(HealthReportSnapshot report) async {
    try {
      await PdfReportService.exportHealthSnapshot(report.data, report.title);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось экспортировать отчёт: $error')),
        );
      }
    }
  }

  Future<_HealthSnapshot> _load() async {
    final sessions = await widget.database.getSessions(limit: null);
    final sessionsById = {for (final session in sessions) session.id: session};
    final rows = await widget.database.getAllMetrics();
    final samples = <String, List<_MetricSample>>{};
    for (final row in rows) {
      final sessionId = row['session_id'] as String?;
      if (sessionId == null || !sessionsById.containsKey(sessionId)) continue;
      final type = row['metric_type'] as String? ?? 'unknown';
      final value = row['value'];
      final measuredAt = DateTime.tryParse(row['measured_at'] as String? ?? '');
      if (value is! num || measuredAt == null || !value.isFinite) continue;
      samples.putIfAbsent(type, () => []).add(_MetricSample(
        value: value.toDouble(),
        unit: row['unit'] as String? ?? '',
        measuredAt: measuredAt,
        source: row['source'] as String? ?? 'Источник не указан',
        sessionId: sessionId,
      ));
    }
    for (final values in samples.values) {
      values.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    }
    return _HealthSnapshot(sessions: sessions, samples: samples);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
      _healthReportsFuture = _loadHealthReports();
    });
    await Future.wait([_future, _healthReportsFuture]);
  }

  Future<void> _chooseRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _customRange ?? DateTimeRange(
        start: HealthReportService.shiftCalendarDays(today, -29),
        end: today,
      ),
      helpText: 'Выберите период анализа',
      saveText: 'Применить',
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  Future<void> _chooseComparisonRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _comparisonRange ?? DateTimeRange(
        start: HealthReportService.shiftCalendarDays(today, -59),
        end: HealthReportService.shiftCalendarDays(today, -30),
      ),
      helpText: 'Выберите период для сравнения',
      saveText: 'Сравнить',
    );
    if (picked != null && mounted) setState(() => _comparisonRange = picked);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_HealthSnapshot>(
    future: _future,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final now = DateTime.now();
      final selectedStart = _customRange?.start ?? HealthReportService.lastDaysStart(now, _days);
      final selectedEndLabel = _customRange?.end ?? now;
      final selectedEndExclusive = _customRange == null
          ? now.add(const Duration(microseconds: 1))
          : HealthReportService.calendarDayAfter(_customRange!.end);
      final durationDays = _customRange == null
          ? _days
          : HealthReportService.inclusiveCalendarDays(_customRange!.start, _customRange!.end);
      final defaultPreviousStart = HealthReportService.shiftCalendarDays(selectedStart, -durationDays);
      final previousStart = _comparisonRange?.start ?? defaultPreviousStart;
      final previousEndLabel = _comparisonRange?.end ??
          DateTime(selectedStart.year, selectedStart.month, selectedStart.day - 1);
      final previousEndExclusive = _comparisonRange == null
          ? selectedStart
          : HealthReportService.calendarDayAfter(_comparisonRange!.end);
      final visible = <String, List<_MetricSample>>{};
      final previous = <String, List<_MetricSample>>{};
      if (data != null) {
        for (final entry in data.samples.entries) {
          final currentPoints = entry.value.where((sample) =>
            !sample.measuredAt.isBefore(selectedStart) &&
            sample.measuredAt.isBefore(selectedEndExclusive)).toList();
          final previousPoints = entry.value.where((sample) =>
            !sample.measuredAt.isBefore(previousStart) &&
            sample.measuredAt.isBefore(previousEndExclusive)).toList();
          if (currentPoints.isNotEmpty) visible[entry.key] = currentPoints;
          if (previousPoints.isNotEmpty) previous[entry.key] = previousPoints;
        }
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Моё здоровье',
            subtitle: 'Физиологические измерения из разрешённых источников',
            icon: Icons.favorite_rounded,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(
              data == null ? 'Загрузка данных…' : 'Ночных записей в истории: ${data.sessions.length}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            )),
            IconButton(
              tooltip: 'Обновить',
              onPressed: snapshot.connectionState == ConnectionState.waiting ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
          const SizedBox(height: 12),
          _HealthDayCalendarCard(
            selectedDay: _selectedDay,
            entryFuture: _dayEntryFuture,
            entriesFuture: _dayEntriesFuture,
            onSelect: _selectHealthDay,
            onEdit: _editHealthDay,
          ),
          const SizedBox(height: 12),
          _HealthTagStatsCard(entriesFuture: _dayEntriesFuture, sessions: data?.sessions ?? const [], onSelectDay: _selectHealthDay),
          const SizedBox(height: 12),
          HealthReportHistoryCard(
            reports: _healthReportsFuture,
            onExport: _exportHealthReport,
          ),
          const SizedBox(height: 12),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else if (snapshot.hasError)
            SectionCard(child: Text('Не удалось загрузить показатели: ${snapshot.error}'))
          else if (data == null || data.samples.isEmpty)
            const SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Пока нет физиологических измерений', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Здесь появятся только реальные показатели, полученные из Apple Health. Отсутствующие значения не заменяются расчётными или условными данными.',
                  style: TextStyle(color: AppTheme.muted, height: 1.45)),
              ],
            ))
          else ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('Неделя')),
                ButtonSegment(value: 30, label: Text('Месяц')),
                ButtonSegment(value: 90, label: Text('3 мес.')),
                ButtonSegment(value: 180, label: Text('6 мес.')),
                ButtonSegment(value: 365, label: Text('Год')),
              ],
              selected: {_days},
              onSelectionChanged: (value) => setState(() { _days = value.first; _customRange = null; }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _chooseRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(_customRange == null ? 'Произвольный период' : '${_date(_customRange!.start)} — ${_date(_customRange!.end)}'),
              )),
              if (_customRange != null) IconButton(tooltip: 'Сбросить период', onPressed: () => setState(() => _customRange = null), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _chooseComparisonRange,
                icon: const Icon(Icons.compare_arrows_rounded),
                label: Text(_comparisonRange == null ? 'Сравнить с предыдущим равным периодом' : 'Сравнение: ${_date(_comparisonRange!.start)} — ${_date(_comparisonRange!.end)}'),
              )),
              if (_comparisonRange != null) IconButton(tooltip: 'Сбросить период сравнения', onPressed: () => setState(() => _comparisonRange = null), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const SectionCard(child: Text('За выбранный период измерений нет. Отсутствие записей не означает нулевые значения.', style: TextStyle(color: AppTheme.muted)))
            else ...[
              _CoverageCard(samples: visible),
              const SizedBox(height: 12),
              _ComparisonCard(current: visible, previous: previous, currentStart: selectedStart, currentEnd: selectedEndLabel, previousStart: previousStart, previousEnd: previousEndLabel),
              const SizedBox(height: 12),
              for (final entry in visible.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MetricCard(type: entry.key, samples: entry.value, sessions: {for (final session in data.sessions) session.id: session}, database: widget.database),
                ),
            ],
            const Text(
              'Показатели отражают данные, переданные источником. Они не являются медицинским заключением. Наличие пропусков зависит от устройства, разрешений и фактических измерений.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
            ),
          ],
        ],
      );
    },
  );
}

class _HealthDayEntry {
  const _HealthDayEntry({required this.note, required this.tags});
  final String note;
  final List<String> tags;
  Map<String, Object?> toJson() => {'note': note, 'tags': tags};
}

class _HealthTagStatsCard extends StatefulWidget {
  const _HealthTagStatsCard({required this.entriesFuture, required this.sessions, required this.onSelectDay});
  final Future<Map<DateTime, _HealthDayEntry>> entriesFuture;
  final List<SleepSession> sessions;
  final ValueChanged<DateTime> onSelectDay;

  @override
  State<_HealthTagStatsCard> createState() => _HealthTagStatsCardState();
}

class _HealthTagStatsCardState extends State<_HealthTagStatsCard> {
  String? _selectedTag;
  final Set<String> _overviewTags = {};
  bool _matchAllOverviewTags = false;
  bool _overviewNewestFirst = true;
  DateTime _overviewMonth = DateTime.now();


  Future<void> _showMonthDates({
    required DateTime now,
    required int monthIndex,
    required List<DateTime> dates,
  }) async {
    final start = DateTime(now.year, now.month - 11 + monthIndex);
    final end = DateTime(start.year, start.month + 1);
    final monthDates = dates
        .where((day) => !day.isBefore(start) && day.isBefore(end))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final selectedDate = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Отметка за ${_monthLabel(start)} · ${monthDates.length}'),
        content: SizedBox(
          width: double.maxFinite,
          child: monthDates.isEmpty
              ? const Text('В этом месяце отметка не использовалась.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final day in monthDates)
                      ListTile(
                        dense: true,
                        title: Text(_date(day)),
                        onTap: () => Navigator.pop(dialogContext, day),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть')),
        ],
      ),
    );
    if (selectedDate != null) widget.onSelectDate(selectedDate);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<DateTime, _HealthDayEntry>>(
    future: widget.entriesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const SectionCard(child: LinearProgressIndicator());
      final entries = snapshot.data ?? const <DateTime, _HealthDayEntry>{};
      final usage = <String, List<DateTime>>{};
      for (final entry in entries.entries) {
        for (final tag in entry.value.tags) {
          usage.putIfAbsent(tag, () => []).add(entry.key);
        }
      }
      final tags = usage.keys.toList()..sort((a, b) => usage[b]!.length.compareTo(usage[a]!.length));
      if (tags.isEmpty) {
        return const SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Статистика отметок', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('Добавляйте отметки в календаре — здесь появятся частота, динамика за 12 месяцев и список дат.', style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
          ],
        ));
      }
      final selected = tags.contains(_selectedTag) ? _selectedTag! : tags.first;
      final dates = [...usage[selected]!]..sort((a, b) => b.compareTo(a));
      DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);
      final taggedDays = dates.map(dayOnly).toSet();
      final completedSessions = widget.sessions.where((session) => session.endedAt != null && session.duration != null && session.duration!.inMinutes > 0).toList();
      final taggedSessions = completedSessions.where((session) => taggedDays.contains(dayOnly(session.endedAt!))).toList();
      final otherSessions = completedSessions.where((session) => !taggedDays.contains(dayOnly(session.endedAt!))).toList();
      double? averageDuration(List<SleepSession> values) => values.isEmpty ? null : values.fold<int>(0, (sum, item) => sum + item.duration!.inMinutes) / values.length / 60;
      double? averageRating(List<SleepSession> values) {
        final rated = values.where((session) => session.morningRating != null).toList();
        return rated.isEmpty ? null : rated.fold<int>(0, (sum, item) => sum + item.morningRating!) / rated.length;
      }
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month);
      final previousMonthStart = DateTime(now.year, now.month - 1);
      final currentMonthCount = dates.where((d) => !d.isBefore(monthStart)).length;
      final previousMonthCount = dates.where((d) => !d.isBefore(previousMonthStart) && d.isBefore(monthStart)).length;
      final twelveMonthStart = DateTime(now.year, now.month - 11);
      final recentDates = dates.where((d) => !d.isBefore(twelveMonthStart)).toList();
      final recordedDays = entries.keys.where((d) => !d.isBefore(twelveMonthStart)).length;
      final percentage = HealthDayTagLibrary.percentageOfRecordedDays(
        matchedDays: recentDates.length,
        recordedDays: recordedDays,
      );
      final overviewTags = _overviewTags.where(tags.contains).toSet();
      final matchedEntries = entries.entries.where((entry) =>
        HealthDayTagLibrary.matches(
          dayTags: entry.value.tags,
          selectedTags: overviewTags,
          requireAll: _matchAllOverviewTags,
        )
      ).toList()
        ..sort((a, b) => _overviewNewestFirst
            ? b.key.compareTo(a.key)
            : a.key.compareTo(b.key));
      final overviewPercentage = HealthDayTagLibrary.percentageOfRecordedDays(
        matchedDays: matchedEntries.length,
        recordedDays: entries.length,
      );
      final monthlyCounts = List<int>.generate(12, (index) {
        final start = DateTime(now.year, now.month - 11 + index);
        final end = DateTime(start.year, start.month + 1);
        return recentDates.where((d) => !d.isBefore(start) && d.isBefore(end)).length;
      });
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Статистика отметок', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Выбранная отметка', isDense: true),
            items: [for (final tag in tags) DropdownMenuItem(value: tag, child: Text(tag))],
            onChanged: (value) => setState(() => _selectedTag = value),
          ),
          const SizedBox(height: 12),
          Text('${dates.length} дней с отметкой «$selected»', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            percentage == null
                ? 'Недостаточно дневных записей для расчёта доли за 12 месяцев'
                : '${_number(percentage)}% дней с записями за последние 12 месяцев',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Stat(label: 'Этот месяц', value: '$currentMonthCount')),
            Expanded(child: _Stat(label: 'Прошлый месяц', value: '$previousMonthCount')),
            Expanded(child: _Stat(label: 'Разница', value: (currentMonthCount - previousMonthCount > 0 ? '+' : '') + '${currentMonthCount - previousMonthCount}')),
          ]),
          const SizedBox(height: 14),
          const Text('Частота за 12 месяцев', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (constraints.maxWidth <= 0) return;
                final barWidth = constraints.maxWidth / (12 * 1.7);
                final gap = (constraints.maxWidth - barWidth * 12) / 11;
                final index = (details.localPosition.dx / (barWidth + gap))
                    .floor()
                    .clamp(0, 11)
                    .toInt();
                _showMonthDates(now: now, monthIndex: index, dates: recentDates);
              },
              child: SizedBox(
                height: 70,
                width: double.infinity,
                child: CustomPaint(painter: _MonthlyTagBarsPainter(monthlyCounts)),
              ),
            ),
          ),
          const Text('Нажмите на месяц, чтобы открыть список дат.',
            style: TextStyle(color: AppTheme.muted, fontSize: 10)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_monthLabel(DateTime(now.year, now.month - 11)), style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
            Text(_monthLabel(now), style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
          ]),
          const Divider(height: 20),
          const Text('Связь с ночными записями', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          if (taggedSessions.isEmpty)
            const Text('Пока нет завершённых ночей, дата окончания которых совпадает с днями этой отметки.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35))
          else ...[
            Text('С отметкой: ${taggedSessions.length} ночей · длительность записи ${averageDuration(taggedSessions) == null ? '—' : _number(averageDuration(taggedSessions)!)} ч · оценка ${averageRating(taggedSessions) == null ? '—' : _number(averageRating(taggedSessions)!)} / 5', style: const TextStyle(fontSize: 11, height: 1.4)),
            Text('Без отметки: ${otherSessions.length} ночей · длительность записи ${averageDuration(otherSessions) == null ? '—' : _number(averageDuration(otherSessions)!)} ч · оценка ${averageRating(otherSessions) == null ? '—' : _number(averageRating(otherSessions)!)} / 5', style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
            const Text('Сопоставление описательное, не доказывает влияние отметки на сон. День сопоставляется с ночью по дате её окончания.', style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
          ],
          const Divider(height: 20),
          Text('Даты использования · ${dates.length}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          SizedBox(height: 130, child: ListView.builder(
            itemCount: dates.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined, size: 18),
              title: Text(_date(dates[index]), style: const TextStyle(fontSize: 12)),
              onTap: () => widget.onSelectDay(dates[index]),
            ),
          )),
          const Divider(height: 22),
          const Text('Совместный обзор отметок', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Выберите несколько отметок и задайте правило совпадения дат.', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final tag in tags)
              FilterChip(
                label: Text(tag),
                selected: overviewTags.contains(tag),
                onSelected: (selected) => setState(() { if (selected) { _overviewTags.add(tag); } else { _overviewTags.remove(tag); } }),
              ),
          ]),
          if (overviewTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Любая отметка')),
                ButtonSegment(value: true, label: Text('Все отметки')),
              ],
              selected: {_matchAllOverviewTags},
              onSelectionChanged: (value) => setState(() => _matchAllOverviewTags = value.first),
            ),
            const SizedBox(height: 8),
            Text(
              'Найдено дат: ${matchedEntries.length} · ${matchedEntries.length} из ${entries.length} дней с записями'
              '${overviewPercentage == null ? '' : ' (${_number(overviewPercentage)}%)'}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            for (final tag in overviewTags)
              Text('$tag: ${matchedEntries.where((entry) => entry.value.tags.contains(tag)).length}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            const SizedBox(height: 8),
            _HealthTagOverviewCalendar(
              month: _overviewMonth,
              matchedDays: matchedEntries.map((entry) => entry.key).toSet(),
              onMonthChanged: (month) => setState(() => _overviewMonth = month),
              onSelectDay: widget.onSelectDay,
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Сначала новые')),
                ButtonSegment(value: false, label: Text('Сначала старые')),
              ],
              selected: {_overviewNewestFirst},
              onSelectionChanged: (value) => setState(() => _overviewNewestFirst = value.first),
            ),
            const SizedBox(height: 6),
            SizedBox(height: 120, child: matchedEntries.isEmpty
              ? const Center(child: Text('Совпадений нет', style: TextStyle(color: AppTheme.muted, fontSize: 11)))
              : ListView.builder(
                  itemCount: matchedEntries.length,
                  itemBuilder: (context, index) {
                    final entry = matchedEntries[index];
                    final matched = entry.value.tags.where(overviewTags.contains).toList()..sort();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_note_rounded, size: 18),
                      title: Text(_date(entry.key), style: const TextStyle(fontSize: 12)),
                      subtitle: Text(matched.join(' · '), style: const TextStyle(fontSize: 10)),
                      onTap: () => widget.onSelectDay(entry.key),
                    );
                  },
                )),
          ],

        ],
      ));
    },
  );
}

class _HealthTagOverviewCalendar extends StatelessWidget {
  const _HealthTagOverviewCalendar({
    required this.month,
    required this.matchedDays,
    required this.onMonthChanged,
    required this.onSelectDay,
  });

  final DateTime month;
  final Set<DateTime> matchedDays;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Календарь совпадений',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        Row(children: [
          IconButton(
            tooltip: 'Предыдущий месяц',
            visualDensity: VisualDensity.compact,
            onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(child: Center(child: Text(_monthTitle(month),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))),
          IconButton(
            tooltip: 'Следующий месяц',
            visualDensity: VisualDensity.compact,
            onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        Row(children: [
          for (final day in weekdays)
            Expanded(child: Center(child: Text(day,
              style: const TextStyle(color: AppTheme.muted, fontSize: 9)))),
        ]),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemCount: cellCount,
          itemBuilder: (context, index) {
            final day = DateTime(month.year, month.month, index - firstWeekday + 1);
            final inMonth = day.month == month.month;
            final matched = inMonth && matchedDays.contains(day);
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: matched ? () => onSelectDay(day) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: matched ? AppTheme.teal.withValues(alpha: 0.22) : null,
                  borderRadius: BorderRadius.circular(8),
                  border: matched ? Border.all(color: AppTheme.teal) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 11,
                    color: !inMonth ? AppTheme.muted.withValues(alpha: 0.35)
                        : matched ? AppTheme.teal : AppTheme.muted,
                    fontWeight: matched ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MonthlyTagBarsPainter extends CustomPainter {
  _MonthlyTagBarsPainter(this.counts);
  final List<int> counts;
  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty) return;
    final maxValue = counts.reduce((a, b) => a > b ? a : b);
    final barWidth = size.width / (counts.length * 1.7);
    final gap = (size.width - barWidth * counts.length) / (counts.length - 1);
    final paint = Paint()..color = const Color(0xFFB9A7FF);
    for (var i = 0; i < counts.length; i++) {
      final height = maxValue == 0 ? 2.0 : (counts[i] / maxValue) * (size.height - 4);
      final left = i * (barWidth + gap);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, size.height - height, barWidth, height), const Radius.circular(3)), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _MonthlyTagBarsPainter oldDelegate) => oldDelegate.counts != counts;
}

String _monthLabel(DateTime date) => '${date.month.toString().padLeft(2, '0')}.${date.year}';


class _HealthDayCalendarCard extends StatefulWidget {
  const _HealthDayCalendarCard({required this.selectedDay, required this.entryFuture, required this.entriesFuture, required this.onSelect, required this.onEdit});
  final DateTime selectedDay;
  final Future<_HealthDayEntry> entryFuture;
  final Future<Map<DateTime, _HealthDayEntry>> entriesFuture;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onEdit;

  @override
  State<_HealthDayCalendarCard> createState() => _HealthDayCalendarCardState();
}

class _HealthDayCalendarCardState extends State<_HealthDayCalendarCard> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.selectedDay.year, widget.selectedDay.month);
  }

  @override
  void didUpdateWidget(covariant _HealthDayCalendarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay.month != widget.selectedDay.month || oldWidget.selectedDay.year != widget.selectedDay.year) {
      _visibleMonth = DateTime(widget.selectedDay.year, widget.selectedDay.month);
    }
  }

  void _changeMonth(int offset) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + offset));
  }

  DateTime _dateForCell(int index) {
    final firstWeekday = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday - 1;
    return DateTime(_visibleMonth.year, _visibleMonth.month, index - firstWeekday + 1);
  }

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Календарь здоровья', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Дни с отметками и комментариями выделены в календаре.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
      FutureBuilder<Map<DateTime, _HealthDayEntry>>(
        future: widget.entriesFuture,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? const <DateTime, _HealthDayEntry>{};
          final firstWeekday = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday - 1;
          final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
          final cellCount = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
          const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
          return Column(children: [
            const SizedBox(height: 10),
            Row(children: [
              IconButton(tooltip: 'Предыдущий месяц', onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(child: Center(child: Text(_monthTitle(_visibleMonth), style: const TextStyle(fontWeight: FontWeight.w700)))),
              IconButton(tooltip: 'Следующий месяц', onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            Row(children: [for (final day in weekdays) Expanded(child: Center(child: Text(day, style: const TextStyle(color: AppTheme.muted, fontSize: 10))))]),
            const SizedBox(height: 6),
            for (var row = 0; row < cellCount ~/ 7; row++)
              Row(children: [
                for (var column = 0; column < 7; column++)
                  Expanded(child: _buildDayCell(firstWeekday + row * 7 + column, entries)),
              ]),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator(minHeight: 2)),
          ]);
        },
      ),
      const Divider(height: 18),
      Row(children: [
        Expanded(child: Text(_date(widget.selectedDay), style: const TextStyle(fontWeight: FontWeight.w700))),
        TextButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit_note_rounded), label: const Text('Изменить')),
      ]),
      FutureBuilder<_HealthDayEntry>(
        future: widget.entryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          final entry = snapshot.data ?? const _HealthDayEntry(note: '', tags: []);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (entry.tags.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: [for (final tag in entry.tags) Chip(label: Text(tag))]),
            if (entry.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(entry.note, style: const TextStyle(height: 1.4))),
            if (entry.tags.isEmpty && entry.note.isEmpty) const Text('Для этого дня пока нет отметок и комментариев.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]);
        },
      ),
    ],
  ));

  Widget _buildDayCell(int index, Map<DateTime, _HealthDayEntry> entries) {
    final day = _dateForCell(index);
    final inMonth = day.month == _visibleMonth.month;
    final key = DateTime(day.year, day.month, day.day);
    final entry = entries[key];
    final isSelected = key == DateTime(widget.selectedDay.year, widget.selectedDay.month, widget.selectedDay.day);
    final today = DateTime.now();
    final selectedToday = key.year == today.year && key.month == today.month && key.day == today.day;
    final hasTags = entry?.tags.isNotEmpty ?? false;
    final hasNote = entry?.note.isNotEmpty ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!inMonth) _changeMonth(day.month - _visibleMonth.month + (day.year - _visibleMonth.year) * 12);
          widget.onSelect(day);
        },
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.teal.withValues(alpha: 0.22) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppTheme.teal : selectedToday ? AppTheme.teal.withValues(alpha: 0.55) : Colors.transparent),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${day.day}', style: TextStyle(fontSize: 12, color: inMonth ? null : AppTheme.muted.withValues(alpha: 0.45), fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500)),
            const SizedBox(height: 3),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (hasTags) Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFB9A7FF), shape: BoxShape.circle)),
              if (hasTags && hasNote) const SizedBox(width: 3),
              if (hasNote) Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF65C8D0), shape: BoxShape.circle)),
            ]),
          ]),
        ),
      ),
    );
  }
}

String _monthTitle(DateTime date) {
  const months = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
  return '${months[date.month - 1]} ${date.year}';
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.current, required this.previous, required this.currentStart, required this.currentEnd, required this.previousStart, required this.previousEnd});
  final Map<String, List<_MetricSample>> current;
  final Map<String, List<_MetricSample>> previous;
  final DateTime currentStart;
  final DateTime currentEnd;
  final DateTime previousStart;
  final DateTime previousEnd;

  @override
  Widget build(BuildContext context) {
    final common = current.keys.where((key) => previous.containsKey(key)).toList();
    if (common.isEmpty) {
      return const SectionCard(child: Text('Для выбранных периодов пока недостаточно общих физиологических показателей для сравнения.', style: TextStyle(color: AppTheme.muted)));
    }
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Сравнение периодов', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Выбранный: ${_date(currentStart)} — ${_date(currentEnd)}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        Text('Сравнение: ${_date(previousStart)} — ${_date(previousEnd)}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        const SizedBox(height: 10),
        for (final key in common) ...[
          _ComparisonRow(type: key, current: current[key]!, previous: previous[key]!),
          if (key != common.last) const Divider(height: 18),
        ],
        const SizedBox(height: 6),
        const Text('Сравниваются средние значения доступных измерений. Разница сама по себе не является медицинской оценкой.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
      ],
    ));
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.type, required this.current, required this.previous});
  final String type;
  final List<_MetricSample> current;
  final List<_MetricSample> previous;

  double _average(List<_MetricSample> values) => values.fold<double>(0, (sum, item) => sum + item.value) / values.length;

  @override
  Widget build(BuildContext context) {
    final currentAverage = _average(current);
    final previousAverage = _average(previous);
    final delta = currentAverage - previousAverage;
    final unit = current.last.unit;
    final percent = previousAverage == 0 ? null : delta / previousAverage * 100;
    final deltaText = (delta > 0 ? '+' : '') + _number(delta) + ' ' + unit;
    final percentText = percent == null ? '' : ' (' + (percent > 0 ? '+' : '') + _number(percent) + '%)';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Выбранный период: ${_number(currentAverage)} $unit · период сравнения: ${_number(previousAverage)} $unit', style: const TextStyle(fontSize: 12)),
      Text('Изменение: $deltaText$percentText', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      Text('${current.length} / ${previous.length} измерений', style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
    ]);
  }
}

class _HealthSnapshot {
  const _HealthSnapshot({required this.sessions, required this.samples});
  final List<SleepSession> sessions;
  final Map<String, List<_MetricSample>> samples;
}

class _MetricSample {
  const _MetricSample({required this.value, required this.unit, required this.measuredAt, required this.source, required this.sessionId});
  final double value;
  final String unit;
  final DateTime measuredAt;
  final String source;
  final String sessionId;
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.samples});
  final Map<String, List<_MetricSample>> samples;

  @override
  Widget build(BuildContext context) {
    final all = samples.values.expand((values) => values).toList();
    final total = all.length;
    final first = all.map((s) => s.measuredAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = all.map((s) => s.measuredAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Доступные данные', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('$total измерений · ${samples.length} типа показателей'),
        const SizedBox(height: 4),
        Text('${_date(first)} — ${_date(last)}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      ],
    ));
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.type, required this.samples, required this.sessions, required this.database});
  final String type;
  final List<_MetricSample> samples;
  final Map<String, SleepSession> sessions;
  final SleepDatabase database;

  String get title => switch (type) {
    'Пульс' => 'Пульс',
    'Частота дыхания' => 'Частота дыхания',
    'Насыщение кислородом' => 'SpO₂',
    'Вариабельность пульса SDNN' => 'Вариабельность сердечного ритма (SDNN)',
    'Температура запястья' => 'Температура запястья',
    _ => type,
  };

  @override
  Widget build(BuildContext context) {
    final values = samples.map((s) => s.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final average = values.reduce((a, b) => a + b) / values.length;
    final latest = samples.last;
    final unit = latest.unit;
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_number(latest.value)} $unit', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text('Последнее измерение', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          ])),
          Text('${samples.length} точек', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 54, width: double.infinity, child: CustomPaint(
          painter: _SparklinePainter(values),
        )),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _Stat(label: 'Минимум', value: '${_number(min)} $unit')),
          Expanded(child: _Stat(label: 'Среднее', value: '${_number(average)} $unit')),
          Expanded(child: _Stat(label: 'Максимум', value: '${_number(max)} $unit')),
        ]),
        const SizedBox(height: 8),
        Text('Последнее: ${_date(latest.measuredAt)} · ${latest.source}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: () => _showHistory(context),
          icon: const Icon(Icons.history_rounded, size: 17),
          label: const Text('История измерений'),
        )),
      ],
    ));
  }

  void _showHistory(BuildContext context) {
    final pageContext = context;
    final rows = [...samples]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('История: ' + title),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (context, index) {
              final sample = rows[index];
              final session = sessions[sample.sessionId];
              final nightLabel = session == null ? 'Ночная запись не найдена' : 'Ночь от ' + _date(session.startedAt);
              final canOpenNight = session != null;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: canOpenNight
                    ? () {
                        Navigator.pop(dialogContext);
                        Navigator.of(pageContext).push(MaterialPageRoute<void>(
                          builder: (_) => SleepSessionDetailScreen(database: database, session: session),
                        ));
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_number(sample.value) + ' ' + sample.unit, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(_date(sample.measuredAt) + ' · ' + nightLabel, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                          Text(sample.source, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                        ],
                      )),
                      if (canOpenNight) const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.muted),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
    ],
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final normalized = range == 0 ? .5 : (values[i] - min) / range;
      final y = size.height - normalized * (size.height - 8) - 4;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    final paint = Paint()
      ..color = const Color(0xFFB9A7FF)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.values != values;
}

String _number(double value) => value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
