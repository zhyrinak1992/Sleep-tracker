import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_note.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_tag.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _searchController = TextEditingController();
  late Future<List<SleepSession>> _sessions;
  late Future<List<SleepNote>> _notes;
  DateTime? _month;
  String _query = '';
  final Set<String> _selectedTags = <String>{};
  Future<Set<String>> _taggedSessionIds = Future.value(<String>{});

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _sessions = widget.database.getSessions(limit: 500);
    _notes = widget.database.getNotes(search: _query, month: _month);
    _taggedSessionIds = widget.database.getSessionIdsWithTags(_selectedTags.toList());
  }

  Future<void> _addNote(SleepSession session) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новая заметка'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.centerLeft,
            child: Text(DateFormat('d MMMM yyyy', 'ru').format(session.startedAt),
              style: const TextStyle(color: AppTheme.muted))),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Текст заметки',
              hintText: 'Что хочется отметить?', alignLabelWithHint: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await widget.database.addNote(session.id, controller.text);
      if (mounted) setState(_reload);
    }
    controller.dispose();
  }

  Future<void> _editNote(SleepNote note) async {
    final controller = TextEditingController(text: note.text);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Изменить заметку'),
        content: TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 7,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Текст заметки', alignLabelWithHint: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await widget.database.editNote(note.id, controller.text);
      if (mounted) setState(_reload);
    }
    controller.dispose();
  }

  Future<void> _deleteNote(SleepNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Будет удалена только эта заметка. Ночная запись и остальные заметки сохранятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.database.deleteNote(note.id);
      if (mounted) setState(_reload);
    }
  }

  Future<void> _editNightMetadata(SleepSession session) async {
    var includeRating = session.morningRating != null;
    var rating = session.morningRating ?? 3;
    final initialTags = await widget.database.getTagsForSession(session.id);
    final selectedTags = initialTags.toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Отметки и самочувствие'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Факторы и обстоятельства', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 2, children: SleepTag.catalog.map((tag) => FilterChip(
              label: Text(tag.label), selected: selectedTags.contains(tag.key),
              onSelected: (selected) => setDialogState(() {
                if (selected) { selectedTags.add(tag.key); } else { selectedTags.remove(tag.key); }
              }),
            )).toList()),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
              title: const Text('Оценить самочувствие'), value: includeRating,
              onChanged: (value) => setDialogState(() => includeRating = value)),
            if (includeRating) ...[
              Text('Оценка: $rating из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(min: 1, max: 5, divisions: 4, value: rating.toDouble(),
                onChanged: (value) => setDialogState(() => rating = value.round())),
              const Text('1 — очень плохо · 5 — отлично',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await widget.database.updateMorningRating(session.id, includeRating ? rating : null);
      await widget.database.setTagsForSession(session.id, SleepTag.catalog
        .where((tag) => selectedTags.contains(tag.key)).toList());
      if (mounted) setState(_reload);
    }
  }

  Future<void> _chooseMonth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(context: context,
      initialDate: _month ?? now, firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2), helpText: 'Выбери месяц');
    if (selected != null) setState(() { _month = DateTime(selected.year, selected.month); _reload(); });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _sessions,
    builder: (context, sessionSnapshot) {
      final sessions = sessionSnapshot.data ?? const <SleepSession>[];
      return FutureBuilder<List<SleepNote>>(
        future: _notes,
        builder: (context, noteSnapshot) {
          final notes = noteSnapshot.data ?? const <SleepNote>[];
          return FutureBuilder<Set<String>>(
            future: _taggedSessionIds,
            builder: (context, tagSnapshot) {
              final taggedSessionIds = tagSnapshot.data ?? const <String>{};
              final visibleNotes = _selectedTags.isEmpty
                  ? notes
                  : notes.where((note) => taggedSessionIds.contains(note.sessionId)).toList();
          return ListView(padding: const EdgeInsets.all(20), children: [
            const ScreenHeader(
              title: 'Заметки',
              subtitle: 'Несколько независимых заметок к каждой ночи',
              icon: Icons.sticky_note_2_rounded,
            ),
            const SizedBox(height: 0),
            TextField(controller: _searchController,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
                hintText: 'Поиск по тексту заметок', suffixIcon: IconButton(
                  tooltip: 'Очистить поиск', icon: const Icon(Icons.close),
                  onPressed: () { _searchController.clear(); setState(() { _query = ''; _reload(); }); })),
              onSubmitted: (value) => setState(() { _query = value.trim(); _reload(); })),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(onPressed: _chooseMonth,
                icon: const Icon(Icons.calendar_month),
                label: Text(_month == null ? 'Все месяцы' : DateFormat('LLLL yyyy', 'ru').format(_month!))),
              if (_month != null) TextButton(onPressed: () => setState(() { _month = null; _reload(); }),
                child: const Text('Сбросить')),
            ]),
            const SizedBox(height: 10),
            const Text('Фильтр по отметкам', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 7, runSpacing: 2, children: [
              ...SleepTag.catalog.map((tag) => FilterChip(
                label: Text(tag.label),
                selected: _selectedTags.contains(tag.key),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _selectedTags.add(tag.key);
                  } else {
                    _selectedTags.remove(tag.key);
                  }
                  _reload();
                }),
              )),
              if (_selectedTags.isNotEmpty)
                ActionChip(label: const Text('Сбросить отметки'),
                  onPressed: () => setState(() { _selectedTags.clear(); _reload(); })),
            ]),
            const SizedBox(height: 12),
            if (sessionSnapshot.connectionState == ConnectionState.waiting || noteSnapshot.connectionState == ConnectionState.waiting || tagSnapshot.connectionState == ConnectionState.waiting)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (sessions.isEmpty)
              const SectionCard(child: Text('Сначала создай ночную сессию на главном экране.'))
            else ...[
              SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Ночные записи', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...sessions.where((s) => _month == null || (s.startedAt.year == _month!.year && s.startedAt.month == _month!.month)).map((session) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(DateFormat('d MMMM yyyy', 'ru').format(session.startedAt)),
                      if (session.morningRating != null) Text('Самочувствие: ${session.morningRating}/5',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                    ])),
                    IconButton(tooltip: 'Факторы и оценка', onPressed: () => _editNightMetadata(session),
                      icon: const Icon(Icons.tune)),
                    IconButton(tooltip: 'Добавить заметку', onPressed: () => _addNote(session),
                      icon: const Icon(Icons.add_comment_outlined, color: AppTheme.teal)),
                  ]),
                )),
              ])),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text('Текстовые заметки (${visibleNotes.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ]),
              const SizedBox(height: 8),
              if (visibleNotes.isEmpty)
                const SectionCard(child: Text('Заметок по выбранным условиям пока нет.',
                  style: TextStyle(color: AppTheme.muted)))
              else ...visibleNotes.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(DateFormat('d MMMM yyyy', 'ru').format(note.sessionStartedAt),
                      style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700))),
                    IconButton(tooltip: 'Изменить', onPressed: () => _editNote(note), icon: const Icon(Icons.edit_outlined, size: 19)),
                    IconButton(tooltip: 'Удалить', onPressed: () => _deleteNote(note), icon: const Icon(Icons.delete_outline, size: 19)),
                  ]),
                  Text(note.text, style: const TextStyle(height: 1.45)),
                ])),
              )),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh), label: const Text('Обновить')),
          ]);
            },
          );
        },
      );
    },
  );
}
