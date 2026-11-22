import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class SleepSessionEditorScreen extends StatefulWidget {
  const SleepSessionEditorScreen({super.key, required this.database, this.session});
  final SleepDatabase database;
  final SleepSession? session;

  @override
  State<SleepSessionEditorScreen> createState() => _SleepSessionEditorScreenState();
}

class _SleepSessionEditorScreenState extends State<SleepSessionEditorScreen> {
  late DateTime _startedAt;
  late DateTime _endedAt;
  late final TextEditingController _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startedAt = widget.session?.actualSleepStartedAt ?? widget.session?.startedAt ?? now.subtract(const Duration(hours: 8));
    _endedAt = widget.session?.actualSleepEndedAt ?? widget.session?.endedAt ?? now;
    _note = TextEditingController(text: widget.session?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ru'),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _selectStart() async {
    final value = await _pickDateTime(_startedAt);
    if (value != null) setState(() => _startedAt = value);
  }

  Future<void> _selectEnd() async {
    final value = await _pickDateTime(_endedAt);
    if (value != null) setState(() => _endedAt = value);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_endedAt.isAfter(_startedAt)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Время пробуждения должно быть позже времени засыпания.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.database.saveSessionRecord(
        id: widget.session?.id,
        startedAt: _startedAt,
        endedAt: _endedAt,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить запись: $error')));
    }
  }

  Widget _timeRow(String title, DateTime value, VoidCallback onTap, IconData icon) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppTheme.teal),
        title: Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
        subtitle: Text(DateFormat('d MMMM yyyy · HH:mm', 'ru').format(value),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.session == null ? 'Добавить ночь' : 'Изменить ночь')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.session == null ? 'Ручная запись сна' : 'Корректировка данных сна',
          style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Укажите фактическое время сна. Для записей Apple Health исходный источник сохраняется, а изменение отмечается отдельно.',
          style: TextStyle(color: AppTheme.muted, height: 1.45)),
        const SizedBox(height: 18),
        SectionCard(child: Column(children: [
          _timeRow('Засыпание', _startedAt, _selectStart, Icons.nightlight_round),
          const Divider(height: 1),
          _timeRow('Пробуждение', _endedAt, _selectEnd, Icons.wb_sunny_outlined),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Заметка к ночи', hintText: 'Необязательно'),
          ),
        ])),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Сохраняем…' : 'Сохранить запись'),
        )),
      ],
    ),
  );
}
