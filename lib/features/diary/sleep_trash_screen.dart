import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../data/notification_service.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class SleepTrashScreen extends StatefulWidget {
  const SleepTrashScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<SleepTrashScreen> createState() => _SleepTrashScreenState();
}

class _SleepTrashScreenState extends State<SleepTrashScreen> {
  late Future<List<SleepSession>> _items;
  final Set<String> _selectedIds = <String>{};
  bool _selectionMode = false;
  @override
  void initState() { super.initState(); _items = widget.database.getTrashedSessions(); }
  Future<void> _reload() async {
    setState(() => _items = widget.database.getTrashedSessions());
    await NotificationService.instance.scheduleTrashExpiry(await widget.database.getTrashExpiryDates());
  }

  Future<void> _restore(SleepSession session) async {
    await widget.database.restoreSessionFromTrash(session.id);
    await _reload();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Запись восстановлена в дневнике')));
  }

  void _toggleSelection(String id) {
    setState(() {
      _selectionMode = true;
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _deleteSelectedForever() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить выбранные записи?'),
      content: Text('Будут безвозвратно удалены ночи: ' + _selectedIds.length.toString() + '. Связанные заметки, показатели и аудиофайлы также будут удалены.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить навсегда')),
      ],
    ));
    if (confirm != true) return;
    final ids = _selectedIds.toList();
    await widget.database.permanentlyDeleteSessions(ids);
    if (!mounted) return;
    setState(() { _selectedIds.clear(); _selectionMode = false; });
    await _reload();
  }
  Future<void> _deleteForever(SleepSession session) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить безвозвратно?'),
      content: const Text('Будут удалены запись ночи, связанные заметки, показатели и аудиофайлы. Это действие нельзя отменить.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить навсегда')),
      ],
    ));
    if (confirm != true) return;
    await widget.database.permanentlyDeleteSession(session.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Корзина')),
    body: FutureBuilder<List<SleepSession>>(
      future: _items,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final sessions = state.data ?? const <SleepSession>[];
        if (sessions.isEmpty) return const Center(child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline, size: 42, color: AppTheme.muted),
            SizedBox(height: 12),
            Text('Корзина пуста', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('Удалённые из дневника ночи можно будет восстановить здесь.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
          ]),
        ));
        return ListView(padding: const EdgeInsets.all(18), children: [
          const Text('Записи хранятся в корзине 30 дней. За 24 часа до окончательного удаления придёт уведомление. До истечения срока ночь можно восстановить.',
            style: TextStyle(color: AppTheme.muted, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_selectionMode) ...[
              FilledButton.icon(onPressed: _selectedIds.isEmpty ? null : _deleteSelectedForever, icon: const Icon(Icons.delete_forever), label: Text('Удалить выбранные (' + _selectedIds.length.toString() + ')')),
              TextButton(onPressed: () => setState(() { _selectedIds.clear(); _selectionMode = false; }), child: const Text('Отмена выбора')),
            ] else OutlinedButton.icon(onPressed: () => setState(() => _selectionMode = true), icon: const Icon(Icons.checklist), label: const Text('Выбрать записи')),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.database.restoreAllTrashedSessions();
                await _reload();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Все записи восстановлены')));
              },
              icon: const Icon(Icons.restore), label: const Text('Восстановить всё'),
            ),
            TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('Очистить корзину?'),
                  content: const Text('Все удалённые ночи и связанные данные будут удалены безвозвратно.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить всё')),
                  ],
                ));
                if (confirm != true) return;
                await widget.database.permanentlyDeleteAllTrashedSessions();
                await _reload();
              },
              icon: const Icon(Icons.delete_forever_outlined), label: const Text('Очистить корзину'),
            ),
          ]),
          const SizedBox(height: 14),
          ...sessions.map((session) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (_selectionMode) Checkbox(value: _selectedIds.contains(session.id), onChanged: (_) => _toggleSelection(session.id)),
                Expanded(child: Text(DateFormat('d MMMM yyyy', 'ru').format(session.startedAt), style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 4),
              if (session.deletedAt != null) Text(
                'Удалено: ' + DateFormat('d MMM yyyy, HH:mm', 'ru').format(session.deletedAt!) +
                ' · окончательное удаление: ' + DateFormat('d MMM yyyy', 'ru').format(session.deletedAt!.add(const Duration(days: 30))),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
              Text(session.duration == null ? 'Без завершённой длительности' : '${session.duration!.inHours} ч ${session.duration!.inMinutes.remainder(60)} мин',
                style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _restore(session), icon: const Icon(Icons.restore), label: const Text('Восстановить'))),
                const SizedBox(width: 8),
                if (!_selectionMode) IconButton(onPressed: () => _deleteForever(session), tooltip: 'Удалить навсегда',
                  icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent)),
              ]),
            ])),
          )),
        ]);
      },
    ),
  );
}
