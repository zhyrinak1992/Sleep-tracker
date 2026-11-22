import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
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
  @override
  void initState() { super.initState(); _items = widget.database.getTrashedSessions(); }
  Future<void> _reload() async => setState(() => _items = widget.database.getTrashedSessions());

  Future<void> _restore(SleepSession session) async {
    await widget.database.restoreSessionFromTrash(session.id);
    await _reload();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Запись восстановлена в дневнике')));
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
          const Text('Записи здесь не удаляются автоматически. Вы можете восстановить ночь или удалить её вместе со связанными данными окончательно.',
            style: TextStyle(color: AppTheme.muted, height: 1.4)),
          const SizedBox(height: 14),
          ...sessions.map((session) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('d MMMM yyyy', 'ru').format(session.startedAt), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(session.duration == null ? 'Без завершённой длительности' : '${session.duration!.inHours} ч ${session.duration!.inMinutes.remainder(60)} мин',
                style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _restore(session), icon: const Icon(Icons.restore), label: const Text('Восстановить'))),
                const SizedBox(width: 8),
                IconButton(onPressed: () => _deleteForever(session), tooltip: 'Удалить навсегда',
                  icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent)),
              ]),
            ])),
          )),
        ]);
      },
    ),
  );
}
