import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/sleep_database.dart';
import '../../models/daytime_sleep_entry.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// Manual daytime-rest log. Stored in app_metadata so it is included in the
/// existing transactional backup without requiring a destructive DB migration.
class DaytimeSleepCard extends StatefulWidget {
  const DaytimeSleepCard({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<DaytimeSleepCard> createState() => _DaytimeSleepCardState();
}

class _DaytimeSleepCardState extends State<DaytimeSleepCard> {
  static const _storageKey = 'sleep_tracker_daytime_sleep_v1';
  static const _uuid = Uuid();
  late Future<List<DaytimeSleepEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<DaytimeSleepEntry>> _loadEntries() async {
    final raw = await widget.database.getAppMetadata(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Список дневного сна повреждён. Исходные данные сохранены.');
    }
    final entries = <DaytimeSleepEntry>[];
    for (final item in decoded) {
      final entry = DaytimeSleepEntry.tryParse(item);
      if (entry == null) {
        throw const FormatException('Одна из записей дневного сна повреждена. Сохранённые данные не перезаписаны.');
      }
      entries.add(entry);
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return entries;
  }

  Future<void> _persist(List<DaytimeSleepEntry> entries) async {
    final ordered = [...entries]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    await widget.database.setAppMetadata(
      _storageKey,
      jsonEncode(ordered.map((entry) => entry.toJson()).toList()),
    );
    if (mounted) setState(() => _entriesFuture = Future.value(ordered));
  }

  Future<void> _addOrEdit([DaytimeSleepEntry? existing]) async {
    final result = await showDialog<DaytimeSleepEntry>(
      context: context,
      builder: (_) => _DaytimeSleepEditor(entry: existing),
    );
    if (result == null || !mounted) return;
    final entries = await _loadEntries();
    final index = entries.indexWhere((entry) => entry.id == result.id);
    if (index >= 0) {
      entries[index] = result;
    } else {
      entries.add(result);
    }
    await _persist(entries);
  }

  Future<void> _delete(DaytimeSleepEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить дневной сон?'),
        content: const Text('Запись будет удалена из журнала. Ночные записи сна не изменятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final entries = await _loadEntries();
    entries.removeWhere((item) => item.id == entry.id);
    await _persist(entries);
  }

  String _duration(Duration value) {
    final minutes = value.inMinutes;
    if (minutes >= 60) return '${minutes ~/ 60} ч ${minutes % 60} мин';
    return '$minutes мин';
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Дневной сон', style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Добавить'),
          ),
        ]),
        const Text(
          'Записывай дневной отдых вручную. Эти данные можно будет сопоставлять с последующим ночным сном.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<DaytimeSleepEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text(
                'Не удалось прочитать журнал: ${snapshot.error}',
                style: const TextStyle(color: AppTheme.accentPink, fontSize: 12),
              );
            }
            final entries = snapshot.data ?? const <DaytimeSleepEntry>[];
            if (entries.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Пока нет записей о дневном сне.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              );
            }
            final recent = entries.where((entry) =>
              entry.startedAt.isAfter(DateTime.now().subtract(const Duration(days: 30)))).toList();
            final totalMinutes = recent.fold<int>(0, (sum, entry) => sum + entry.duration.inMinutes);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'За последние 30 дней: ${recent.length} записей · ${_duration(Duration(minutes: totalMinutes))}',
                  style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...entries.map((entry) {
                  final start = entry.startedAt.toLocal();
                  final end = entry.endedAt.toLocal();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.only(top: 3, right: 10),
                          child: Icon(Icons.bedtime_outlined, size: 18, color: AppTheme.teal)),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat('d MMMM yyyy', 'ru').format(start),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(end)} · ${_duration(entry.duration)}',
                              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                            if (entry.note.trim().isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 2),
                                child: Text(entry.note, style: const TextStyle(fontSize: 12, height: 1.35))),
                          ],
                        )),
                        IconButton(
                          tooltip: 'Изменить',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _addOrEdit(entry),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Удалить',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _delete(entry),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _DaytimeSleepEditor extends StatefulWidget {
  const _DaytimeSleepEditor({this.entry});
  final DaytimeSleepEntry? entry;

  @override
  State<_DaytimeSleepEditor> createState() => _DaytimeSleepEditorState();
}

class _DaytimeSleepEditorState extends State<_DaytimeSleepEditor> {
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late TextEditingController _noteController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    final start = entry?.startedAt.toLocal() ?? DateTime.now();
    final end = entry?.endedAt.toLocal() ?? start.add(const Duration(minutes: 30));
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay.fromDateTime(start);
    _end = TimeOfDay.fromDateTime(end);
    _noteController = TextEditingController(text: entry?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (selected != null) setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  void _save() {
    final start = _combine(_date, _start);
    final end = _combine(_date, _end);
    if (!end.isAfter(start)) {
      setState(() => _error = 'Время окончания должно быть позже времени начала в выбранный день.');
      return;
    }
    Navigator.pop(context, DaytimeSleepEntry(
      id: widget.entry?.id ?? const Uuid().v4(),
      startedAt: start,
      endedAt: end,
      note: _noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? 'Добавить дневной сон' : 'Изменить дневной сон'),
    content: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Дата'),
          subtitle: Text(DateFormat('d MMMM yyyy', 'ru').format(_date)),
          onTap: _pickDate,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.play_arrow_rounded),
          title: const Text('Начало'),
          subtitle: Text(_start.format(context)),
          onTap: () => _pickTime(start: true),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.stop_rounded),
          title: const Text('Окончание'),
          subtitle: Text(_end.format(context)),
          onTap: () => _pickTime(start: false),
        ),
        TextField(
          controller: _noteController,
          maxLength: 240,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Заметка (необязательно)'),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppTheme.accentPink, fontSize: 12))),
      ],
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
    ],
  );
}
