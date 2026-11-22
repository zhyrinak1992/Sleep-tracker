import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../models/screen_time_entry.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class ScreenTimeCard extends StatefulWidget {
  const ScreenTimeCard({super.key, required this.database, required this.session});
  final SleepDatabase database;
  final SleepSession session;

  @override
  State<ScreenTimeCard> createState() => _ScreenTimeCardState();
}

class _ScreenTimeCardState extends State<ScreenTimeCard> {
  late Future<ScreenTimeEntry?> _future;
  bool _damaged = false;

  String get _key => 'sleep_tracker_screen_time_v1_${widget.session.id}';
  DateTime get _sleepStart =>
      widget.session.actualSleepStartedAt ?? widget.session.startedAt;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ScreenTimeEntry?> _load() async {
    final raw = await widget.database.getAppMetadata(_key);
    if (raw == null || raw.isEmpty) {
      _damaged = false;
      return null;
    }
    try {
      final entry = ScreenTimeEntry.decode(raw);
      if (entry.sessionId != widget.session.id) {
        throw const FormatException('Запись относится к другой ночи.');
      }
      _damaged = false;
      return entry;
    } on FormatException {
      _damaged = true;
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _edit(ScreenTimeEntry? existing) async {
    final controller = TextEditingController(
      text: (existing?.durationMinutes ?? 30).toString(),
    );
    final initial = existing?.lastUseAt ??
        _sleepStart.subtract(const Duration(minutes: 30));
    var selectedTime = TimeOfDay.fromDateTime(initial);
    var validationError = '';
    final result = await showDialog<ScreenTimeEntry?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Экранное время перед сном'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Укажи приблизительную продолжительность использования телефона или других экранов перед этой ночью. Данные вводятся вручную.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Минут перед сном',
                  helperText: 'От 0 до 360 минут',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: dialogContext,
                    initialTime: selectedTime,
                    helpText: 'Когда отложили экран?',
                  );
                  if (picked != null) {
                    setDialogState(() {
                      selectedTime = picked;
                      validationError = '';
                    });
                  }
                },
                icon: const Icon(Icons.schedule),
                label: Text('Последнее использование: ${selectedTime.format(context)}'),
              ),
              if (validationError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(validationError,
                    style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
                ),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final minutes = int.tryParse(controller.text.trim());
                if (minutes == null || minutes < 0 || minutes > 360) {
                  setDialogState(() => validationError = 'Введи целое число от 0 до 360.');
                  return;
                }
                var lastUse = DateTime(
                  _sleepStart.year, _sleepStart.month, _sleepStart.day,
                  selectedTime.hour, selectedTime.minute,
                );
                if (lastUse.isAfter(_sleepStart)) {
                  lastUse = lastUse.subtract(const Duration(days: 1));
                }
                if (lastUse.isAfter(_sleepStart) ||
                    _sleepStart.difference(lastUse) > const Duration(hours: 24)) {
                  setDialogState(() => validationError = 'Время должно быть в пределах 24 часов до начала сна.');
                  return;
                }
                Navigator.pop(dialogContext, ScreenTimeEntry(
                  sessionId: widget.session.id,
                  durationMinutes: minutes,
                  lastUseAt: lastUse,
                  updatedAt: DateTime.now(),
                ));
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await widget.database.setAppMetadata(_key, result.encode());
    await _refresh();
  }

  Future<void> _clear() async {
    await widget.database.setAppMetadata(_key, '');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: FutureBuilder<ScreenTimeEntry?>(
      future: _future,
      builder: (context, snapshot) {
        final entry = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Экранное время перед сном',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: snapshot.connectionState == ConnectionState.waiting || _damaged
                    ? null
                    : () => _edit(entry),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: Text(entry == null ? 'Добавить' : 'Изменить'),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Ручная оценка. iOS не предоставляет обычным приложениям произвольную историю экранного времени без специальных системных разрешений.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              const Text('Сохранённая запись повреждена. Она не была изменена.',
                style: TextStyle(color: AppTheme.accentPink, fontSize: 12))
            else if (entry == null)
              const Text('Для этой ночи отметка ещё не добавлена.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12))
            else ...[
              _valueRow('Использование экранов', '${entry.durationMinutes} мин'),
              _valueRow('Последнее использование',
                DateFormat('d MMM, HH:mm', 'ru').format(entry.lastUseAt)),
              if (!_damaged)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _clear,
                    child: const Text('Удалить отметку'),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );

  Widget _valueRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );
}
