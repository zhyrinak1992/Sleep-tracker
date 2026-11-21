import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class SleepSessionComparisonScreen extends StatefulWidget {
  const SleepSessionComparisonScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<SleepSessionComparisonScreen> createState() => _SleepSessionComparisonScreenState();
}

class _SleepSessionComparisonScreenState extends State<SleepSessionComparisonScreen> {
  late Future<List<SleepSession>> _sessionsFuture;
  String? _firstId;
  String? _secondId;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = widget.database.getSessions(limit: 10000);
  }

  Future<void> _reload() async {
    setState(() => _sessionsFuture = widget.database.getSessions(limit: 10000));
    await _sessionsFuture;
  }

  SleepSession? _byId(List<SleepSession> sessions, String? id) {
    if (id == null) return null;
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  String _date(SleepSession session) => DateFormat('d MMM yyyy, HH:mm', 'ru').format(session.startedAt);

  String _duration(Duration? value) {
    if (value == null) return 'Нет данных';
    if (value.isNegative) return 'Некорректный интервал';
    return '${value.inHours} ч ${value.inMinutes.remainder(60)} мин';
  }

  String _rating(int? value) => value == null ? 'Не оценено' : '$value из 5';

  String _delta(Duration? first, Duration? second) {
    if (first == null || second == null || first.isNegative || second.isNegative) {
      return 'Сравнение невозможно: нет двух завершённых ночей';
    }
    final difference = second - first;
    if (difference.inMinutes == 0) return 'Без изменений';
    final absolute = difference.abs();
    final amount = '${absolute.inHours} ч ${absolute.inMinutes.remainder(60)} мин';
    return difference.isNegative ? 'Вторая ночь короче на $amount' : 'Вторая ночь длиннее на $amount';
  }

  String _ratingDelta(int? first, int? second) {
    if (first == null || second == null) return 'Сравнение невозможно: оценка есть не у обеих ночей';
    final difference = second - first;
    if (difference == 0) return 'Без изменений';
    return difference > 0 ? 'Выше на $difference балл(а)' : 'Ниже на ${difference.abs()} балл(а)';
  }

  Widget _nightPicker({required String label, required String? value,
    required List<SleepSession> sessions, required ValueChanged<String?> onChanged}) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      hint: const Text('Выберите ночь'),
      items: sessions.map((session) => DropdownMenuItem<String>(
        value: session.id,
        child: Text('${_date(session)}${session.isOpen ? ' · идёт' : ''}', overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: onChanged,
    );
  }

  Widget _valueColumn(String heading, String value, {Color? color}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(heading, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color), maxLines: 4,
        overflow: TextOverflow.ellipsis),
    ]),
  );

  Widget _comparisonRow(String title, String first, String second, String difference,
      {bool highlight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 9),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _valueColumn('Первая ночь', first),
        const SizedBox(width: 12),
        _valueColumn('Вторая ночь', second),
      ]),
      const SizedBox(height: 7),
      Text(difference, style: TextStyle(fontSize: 12,
        color: highlight ? AppTheme.teal : AppTheme.muted, height: 1.35)),
    ]),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _sessionsFuture,
    builder: (context, snapshot) {
      final sessions = snapshot.data ?? const <SleepSession>[];
      final first = _byId(sessions, _firstId);
      final second = _byId(sessions, _secondId);
      return Scaffold(
        appBar: AppBar(title: const Text('Сравнение ночей')),
        body: snapshot.connectionState == ConnectionState.waiting
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text('Сравните две ночи', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('Выберите любые две сохранённые сессии. Разница рассчитывается только там, где есть сопоставимые данные.',
                style: TextStyle(color: AppTheme.muted, height: 1.45)),
              const SizedBox(height: 18),
              if (sessions.length < 2)
                const SectionCard(child: Text('Для сравнения нужны как минимум две сохранённые ночи.',
                  style: TextStyle(color: AppTheme.muted)))
              else ...[
                SectionCard(child: Column(children: [
                  _nightPicker(label: 'Первая ночь', value: _firstId, sessions: sessions,
                    onChanged: (value) => setState(() {
                      _firstId = value;
                      if (_secondId == value) _secondId = null;
                    })),
                  const SizedBox(height: 14),
                  _nightPicker(label: 'Вторая ночь', value: _secondId, sessions: sessions,
                    onChanged: (value) => setState(() => _secondId = value)),
                ])),
                const SizedBox(height: 14),
                if (first != null && second != null) ...[
                  if (first.id == second.id)
                    const SectionCard(child: Text('Выберите две разные ночи.',
                      style: TextStyle(color: AppTheme.muted)))
                  else ...[
                    SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _comparisonRow('Продолжительность', _duration(first.duration), _duration(second.duration),
                        _delta(first.duration, second.duration), highlight: first.duration != null && second.duration != null),
                      const Divider(height: 1),
                      _comparisonRow('Самочувствие', _rating(first.morningRating), _rating(second.morningRating),
                        _ratingDelta(first.morningRating, second.morningRating),
                        highlight: first.morningRating != null && second.morningRating != null),
                      const Divider(height: 1),
                      _comparisonRow('Начало сессии', DateFormat('d MMM yyyy, HH:mm', 'ru').format(first.startedAt),
                        DateFormat('d MMM yyyy, HH:mm', 'ru').format(second.startedAt), 'Показывается фактически сохранённое время.'),
                      const Divider(height: 1),
                      _comparisonRow('Окончание сессии', first.endedAt == null ? 'Не завершена' : DateFormat('d MMM yyyy, HH:mm', 'ru').format(first.endedAt!),
                        second.endedAt == null ? 'Не завершена' : DateFormat('d MMM yyyy, HH:mm', 'ru').format(second.endedAt!),
                        'Незавершённые сессии не участвуют в сравнении длительности.'),
                      const Divider(height: 1),
                      _comparisonRow('Источник', first.source == 'manual' ? 'Вручную' : first.source,
                        second.source == 'manual' ? 'Вручную' : second.source, 'Источники отображаются без преобразования.'),
                    ])),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Заметки', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _valueColumn('Первая ночь', first.note?.trim().isNotEmpty == true ? first.note! : 'Нет заметки'),
                        const SizedBox(width: 12),
                        _valueColumn('Вторая ночь', second.note?.trim().isNotEmpty == true ? second.note! : 'Нет заметки'),
                      ]),
                    ])),
                    const SizedBox(height: 12),
                    const SectionCard(child: Text('Фазы сна, пульс, дыхание, пробуждения и аудиособытия будут включены в сравнение после подключения соответствующих источников. Сейчас этих данных в проекте нет, поэтому они не имитируются.',
                      style: TextStyle(color: AppTheme.muted, height: 1.5))),
                  ],
                ] else
                  const SectionCard(child: Text('Выберите первую и вторую ночь, чтобы увидеть сравнение.',
                    style: TextStyle(color: AppTheme.muted))),
              ],
            ]),
          ),
      );
    },
  );
}
