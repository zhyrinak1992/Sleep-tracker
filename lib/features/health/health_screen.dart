import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  late Future<_HealthSnapshot> _future;
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
    final noteController = TextEditingController(text: existing.note);
    final tagController = TextEditingController();
    final tags = existing.tags.toSet();
    const presets = ['Стресс', 'Кофеин', 'Тренировка', 'Болезнь', 'Боль', 'Лекарства', 'Путешествие', 'Поздний ужин', 'Алкоголь', 'Дневной сон'];
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
                  for (final tag in presets)
                    FilterChip(label: Text(tag), selected: tags.contains(tag), onSelected: (selected) => setDialogState(() { if (selected) { tags.add(tag); } else { tags.remove(tag); } })),
                  for (final tag in tags.where((tag) => !presets.contains(tag)).toList())
                    InputChip(label: Text(tag), onDeleted: () => setDialogState(() => tags.remove(tag))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: tagController, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: 'Своя отметка', hintText: 'Например, поздний подъём'))),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { final value = tagController.text.trim(); if (value.isNotEmpty) { setDialogState(() => tags.add(value)); tagController.clear(); } }),
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
    await widget.database.setAppMetadata(_dayMetadataKey(_selectedDay), jsonEncode(result.toJson()));
    if (mounted) setState(() {
      _dayEntryFuture = Future.value(result);
      _dayEntriesFuture = _loadAllHealthDayEntries();
    });
  }

  Future<_HealthSnapshot> _load() async {
    final sessions = await widget.database.getSessions(limit: 5000);
    final samples = <String, List<_MetricSample>>{};
    for (final session in sessions) {
      final rows = await widget.database.getMetrics(session.id);
      for (final row in rows) {
        final type = row['metric_type'] as String? ?? 'unknown';
        final value = row['value'];
        final measuredAt = DateTime.tryParse(row['measured_at'] as String? ?? '');
        if (value is! num || measuredAt == null || !value.isFinite) continue;
        samples.putIfAbsent(type, () => []).add(_MetricSample(
          value: value.toDouble(),
          unit: row['unit'] as String? ?? '',
          measuredAt: measuredAt,
          source: row['source'] as String? ?? 'Источник не указан',
          sessionId: session.id,
        ));
      }
    }
    for (final values in samples.values) {
      values.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    }
    return _HealthSnapshot(sessions: sessions, samples: samples);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _chooseRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now),
      helpText: 'Выберите период анализа',
      saveText: 'Применить',
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  Future<void> _chooseComparisonRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _comparisonRange ?? DateTimeRange(start: now.subtract(const Duration(days: 59)), end: now.subtract(const Duration(days: 30))),
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
      final selectedStart = _customRange?.start ?? DateTime(now.year, now.month, now.day).subtract(Duration(days: _days - 1));
      final selectedEnd = _customRange == null ? now : DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day, 23, 59, 59);
      final durationDays = selectedEnd.difference(selectedStart).inDays + 1;
      final defaultPreviousStart = selectedStart.subtract(Duration(days: durationDays));
      final defaultPreviousEnd = selectedStart.subtract(const Duration(microseconds: 1));
      final previousStart = _comparisonRange?.start ?? defaultPreviousStart;
      final previousEnd = _comparisonRange == null ? defaultPreviousEnd : DateTime(_comparisonRange!.end.year, _comparisonRange!.end.month, _comparisonRange!.end.day, 23, 59, 59);
      final visible = <String, List<_MetricSample>>{};
      final previous = <String, List<_MetricSample>>{};
      if (data != null) {
        for (final entry in data.samples.entries) {
          final currentPoints = entry.value.where((sample) => !sample.measuredAt.isBefore(selectedStart) && !sample.measuredAt.isAfter(selectedEnd)).toList();
          final previousPoints = entry.value.where((sample) => !sample.measuredAt.isBefore(previousStart) && !sample.measuredAt.isAfter(previousEnd)).toList();
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
            onSelect: _selectHealthDay,
            onEdit: _editHealthDay,
          ),
          const SizedBox(height: 12),
          _HealthTagStatsCard(entriesFuture: _dayEntriesFuture),
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
                ButtonSegment(value: 7, label: Text('7 дней')),
                ButtonSegment(value: 30, label: Text('30 дней')),
                ButtonSegment(value: 90, label: Text('90 дней')),
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
              _ComparisonCard(current: visible, previous: previous, previousStart: previousStart, previousEnd: previousEnd),
              const SizedBox(height: 12),
              for (final entry in visible.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MetricCard(type: entry.key, samples: entry.value, sessions: {for (final session in data.sessions) session.id: session}),
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
  const _HealthTagStatsCard({required this.entriesFuture});
  final Future<Map<DateTime, _HealthDayEntry>> entriesFuture;

  @override
  State<_HealthTagStatsCard> createState() => _HealthTagStatsCardState();
}

class _HealthTagStatsCardState extends State<_HealthTagStatsCard> {
  String? _selectedTag;

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
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month);
      final previousMonthStart = DateTime(now.year, now.month - 1);
      final currentMonthCount = dates.where((d) => !d.isBefore(monthStart)).length;
      final previousMonthCount = dates.where((d) => !d.isBefore(previousMonthStart) && d.isBefore(monthStart)).length;
      final recordedDays = entries.keys.where((d) => !d.isBefore(DateTime(now.year, now.month - 11))).length;
      final percentage = recordedDays == 0 ? 0.0 : dates.length / recordedDays * 100;
      final monthlyCounts = List<int>.generate(12, (index) {
        final start = DateTime(now.year, now.month - 11 + index);
        final end = DateTime(start.year, start.month + 1);
        return dates.where((d) => !d.isBefore(start) && d.isBefore(end)).length;
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
          Text('${_number(percentage)}% дней с записями за последние 12 месяцев', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Stat(label: 'Этот месяц', value: '$currentMonthCount')),
            Expanded(child: _Stat(label: 'Прошлый месяц', value: '$previousMonthCount')),
            Expanded(child: _Stat(label: 'Разница', value: (currentMonthCount - previousMonthCount > 0 ? '+' : '') + '${currentMonthCount - previousMonthCount}')),
          ]),
          const SizedBox(height: 14),
          const Text('Частота за 12 месяцев', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SizedBox(height: 70, width: double.infinity, child: CustomPaint(painter: _MonthlyTagBarsPainter(monthlyCounts))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_monthLabel(DateTime(now.year, now.month - 11)), style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
            Text(_monthLabel(now), style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
          ]),
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
            ),
          )),
        ],
      ));
    },
  );
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

class _HealthDayCalendarCard extends StatelessWidget {
  const _HealthDayCalendarCard({required this.selectedDay, required this.entryFuture, required this.onSelect, required this.onEdit});
  final DateTime selectedDay;
  final Future<_HealthDayEntry> entryFuture;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Календарь здоровья', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Выберите день, чтобы добавить несколько отметок и личный комментарий.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
      CalendarDatePicker(
        initialDate: selectedDay,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        onDateChanged: onSelect,
      ),
      const Divider(height: 12),
      Row(children: [
        Expanded(child: Text(_date(selectedDay), style: const TextStyle(fontWeight: FontWeight.w700))),
        TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_note_rounded), label: const Text('Изменить')),
      ]),
      FutureBuilder<_HealthDayEntry>(
        future: entryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          final entry = snapshot.data ?? const _HealthDayEntry(note: '', tags: []);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (entry.tags.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: [for (final tag in entry.tags) Chip(label: Text(tag))]),
            if (entry.note.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(entry.note, style: const TextStyle(height: 1.4)),
            ),
            if (entry.tags.isEmpty && entry.note.isEmpty) const Text('Для этого дня пока нет отметок и комментариев.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]);
        },
      ),
    ],
  ));
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.current, required this.previous, required this.previousStart, required this.previousEnd});
  final Map<String, List<_MetricSample>> current;
  final Map<String, List<_MetricSample>> previous;
  final DateTime previousStart;
  final DateTime previousEnd;

  @override
  Widget build(BuildContext context) {
    final common = current.keys.where((key) => previous.containsKey(key)).toList();
    if (common.isEmpty) {
      return const SectionCard(child: Text('Для сравнения пока недостаточно измерений в предыдущем равном по длительности периоде.', style: TextStyle(color: AppTheme.muted)));
    }
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Сравнение периодов', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${_date(previousStart)} — ${_date(previousEnd)}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
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
      Text('Сейчас: ${_number(currentAverage)} $unit · ранее: ${_number(previousAverage)} $unit', style: const TextStyle(fontSize: 12)),
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
  const _MetricCard({required this.type, required this.samples, required this.sessions});
  final String type;
  final List<_MetricSample> samples;
  final Map<String, SleepSession> sessions;

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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_number(sample.value) + ' ' + sample.unit, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_date(sample.measuredAt) + ' · ' + nightLabel, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  Text(sample.source, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                ],
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
