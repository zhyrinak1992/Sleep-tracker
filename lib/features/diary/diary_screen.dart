import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../data/notification_service.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';
import 'sleep_session_detail_screen.dart';
import 'sleep_session_comparison_screen.dart';
import 'reference_night_comparison_screen.dart';
import 'sleep_session_editor_screen.dart';
import 'sleep_trash_screen.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late Future<List<SleepSession>> _sessions;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  final Set<String> _selectedSessionIds = <String>{};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _sessions = widget.database.getSessions(limit: 1000);
  }

  Future<void> _reload() async {
    setState(() => _sessions = widget.database.getSessions(limit: 1000));
    await _sessions;
  }

  void _toggleSessionSelection(SleepSession session) {
    if (session.isOpen) return;
    setState(() {
      _selectionMode = true;
      if (!_selectedSessionIds.add(session.id)) _selectedSessionIds.remove(session.id);
      if (_selectedSessionIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _moveSelectedToTrash() async {
    if (_selectedSessionIds.isEmpty) return;
    final ids = _selectedSessionIds.toList();
    await widget.database.moveSessionsToTrash(ids);
    if (!mounted) return;
    setState(() { _selectedSessionIds.clear(); _selectionMode = false; });
    await _reload();
    await NotificationService.instance.scheduleTrashExpiry(await widget.database.getTrashExpiryDates());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Перемещено в корзину: ' + ids.length.toString())));
  }
  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  Color _ratingColor(int? rating) {
    if (rating == null) return AppTheme.muted.withValues(alpha: 0.55);
    if (rating <= 2) return const Color(0xFFE58B91);
    if (rating == 3) return const Color(0xFFE6BC70);
    return AppTheme.teal;
  }

  String _sourceLabel(SleepSession session) {
    final source = session.source.trim();
    final label = source.isEmpty || source == 'manual' || source == 'manual_entry'
        ? 'Вручную'
        : source;
    return session.userEdited ? '$label · изменено вручную' : label;
  }

  String _duration(Duration? d) {
    if (d == null) return 'Идёт сейчас';
    if (d.isNegative) return 'Некорректный интервал';
    return '${d.inHours} ч ${d.inMinutes.remainder(60)} мин';
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selectedDay = _day(_visibleMonth);
    });
  }

  void _openSession(SleepSession session) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SleepSessionDetailScreen(database: widget.database, session: session),
    )).then((_) => _reload());
  }

  Widget _calendar(List<SleepSession> sessions) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leading = first.weekday - 1;
    final days = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final byDay = <DateTime, List<SleepSession>>{};
    for (final session in sessions) {
      byDay.putIfAbsent(_day(session.startedAt), () => []).add(session);
    }
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return SectionCard(padding: const EdgeInsets.fromLTRB(14, 16, 14, 14), child: Column(
      children: [
        Row(children: [
          IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(DateFormat('LLLL yyyy', 'ru').format(_visibleMonth),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 8),
        Row(children: weekdays.map((day) => Expanded(child: Center(child: Text(day,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600))))).toList()),
        const SizedBox(height: 8),
        ...List.generate(cells ~/ 7, (week) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: List.generate(7, (weekday) {
            final index = week * 7 + weekday;
            final dayNumber = index - leading + 1;
            if (dayNumber < 1 || dayNumber > days) return const Expanded(child: SizedBox(height: 48));
            final date = DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber);
            final daySessions = byDay[_day(date)] ?? const <SleepSession>[];
            final hasSession = daySessions.isNotEmpty;
            final selected = DateUtils.isSameDay(date, _selectedDay);
            final hasOpen = daySessions.any((s) => s.isOpen);
            final rated = daySessions.where((s) => s.morningRating != null).toList();
            final rating = rated.isEmpty ? null :
              (rated.map((s) => s.morningRating!).reduce((a, b) => a + b) / rated.length).round();
            final markerColor = hasOpen ? const Color(0xFF8BC7E8) : _ratingColor(rating);
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _selectedDay = _day(date)),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.teal.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: selected ? AppTheme.teal : Colors.transparent),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$dayNumber', style: TextStyle(
                      color: selected ? AppTheme.teal : Colors.white,
                      fontWeight: selected || hasSession ? FontWeight.bold : FontWeight.normal,
                    )),
                    const SizedBox(height: 4),
                    Container(width: 5, height: 5, decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasSession ? markerColor : Colors.transparent,
                    )),
                  ]),
                ),
              ),
            ));
          })),
        )),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 8, alignment: WrapAlignment.center, children: const [
          _LegendDot(color: Color(0xFFE58B91), label: '1–2'),
          _LegendDot(color: Color(0xFFE6BC70), label: '3'),
          _LegendDot(color: AppTheme.teal, label: '4–5'),
          _LegendDot(color: Color(0xFF8BC7E8), label: 'Идёт'),
        ]),
        const SizedBox(height: 6),
        const Text('Цвет отражает только сохранённую оценку самочувствия. Без оценки цветовая отметка не ставится.',
          textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
      ],
    ));
  }

  Widget _selectedDaySessions(List<SleepSession> sessions) {
    final daySessions = sessions.where((s) => DateUtils.isSameDay(s.startedAt, _selectedDay)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(DateFormat('d MMMM yyyy', 'ru').format(_selectedDay),
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      if (daySessions.isEmpty)
        const SectionCard(child: Text('На эту дату записей нет.', style: TextStyle(color: AppTheme.muted)))
      else
        ...daySessions.map((session) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onLongPress: () => _toggleSessionSelection(session),
            onTap: () => _selectionMode ? _toggleSessionSelection(session) : _openSession(session),
            child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (_selectionMode && !session.isOpen) Checkbox(
                  value: _selectedSessionIds.contains(session.id),
                  onChanged: (_) => _toggleSessionSelection(session),
                ),
                Expanded(child: Text(session.isOpen ? 'Сессия продолжается' : 'Ночная сессия',
                  style: const TextStyle(color: AppTheme.muted))),
                if (!_selectionMode) IconButton(
                  tooltip: 'Изменить запись',
                  onPressed: () async {
                    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
                      builder: (_) => SleepSessionEditorScreen(database: widget.database, session: session),
                    ));
                    if (saved == true) await _reload();
                  },
                  icon: const Icon(Icons.edit_outlined, color: AppTheme.teal),
                ),
                if (!_selectionMode) const Icon(Icons.chevron_right, color: AppTheme.muted),
              ]),
              const SizedBox(height: 7),
              Text(_duration(session.duration), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Начало ${DateFormat('HH:mm').format(session.startedAt)}'
                '${session.endedAt == null ? '' : ' · Конец ${DateFormat('HH:mm').format(session.endedAt!)}'}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 5),
              Row(children: [
                const Icon(Icons.storage_outlined, size: 13, color: AppTheme.muted),
                const SizedBox(width: 5),
                Expanded(child: Text('Источник: ${_sourceLabel(session)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11))),
              ]),
              if (session.morningRating != null) ...[
                const SizedBox(height: 8),
                Row(children: [Icon(Icons.circle, size: 8, color: _ratingColor(session.morningRating)),
                  const SizedBox(width: 7), Text('Самочувствие: ${session.morningRating}/5')]),
              ],
              if (session.note?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(session.note!, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted)),
              ],
            ])),
          ),
        )),
    ]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepSession>>(
    future: _sessions,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <SleepSession>[];
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const ScreenHeader(
            title: 'Дневник сна',
            subtitle: 'Календарь и история ночных сессий',
            icon: Icons.calendar_month_rounded,
          ),
          const SizedBox(height: 0),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => SleepSessionEditorScreen(database: widget.database),
                ));
                if (saved == true) await _reload();
              },
              icon: const Icon(Icons.add), label: const Text('Добавить ночь'),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SleepSessionComparisonScreen(database: widget.database),
              )),
              icon: const Icon(Icons.compare_arrows), label: const Text('Сравнить'),
            )),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReferenceNightComparisonScreen(database: widget.database),
            )),
            icon: const Icon(Icons.stars_rounded),
            label: const Text('Сравнить с эталонной ночью'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SleepTrashScreen(database: widget.database),
              ));
              await _reload();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Корзина'),
          ),
          if (_selectionMode) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: _selectedSessionIds.isEmpty ? null : _moveSelectedToTrash,
                icon: const Icon(Icons.delete_outline),
                label: Text('В корзину (' + _selectedSessionIds.length.toString() + ')'),
              )),
              const SizedBox(width: 8),
              TextButton(onPressed: () => setState(() { _selectedSessionIds.clear(); _selectionMode = false; }), child: const Text('Отмена')),
            ]),
          ] else ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              label: const Text('Выбрать ночи для удаления'),
            ),
          ],
          const SizedBox(height: 18),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
          else ...[
            _calendar(rows),
            const SizedBox(height: 22),
            _selectedDaySessions(rows),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Обновить дневник')),
        ]),
      );
    },
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
  ]);
}
