import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_note.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class SleepSessionDetailScreen extends StatefulWidget {
  const SleepSessionDetailScreen({super.key, required this.database, required this.session});

  final SleepDatabase database;
  final SleepSession session;

  @override
  State<SleepSessionDetailScreen> createState() => _SleepSessionDetailScreenState();
}

class _SleepSessionDetailScreenState extends State<SleepSessionDetailScreen> {
  late Future<SleepSession?> _future;
  late Future<List<SleepNote>> _notesFuture;
  late Future<List<Map<String, Object?>>> _stagesFuture;
  late Future<List<Map<String, Object?>>> _metricsFuture;
  late Future<Map<String, Object?>?> _reportFuture;

  @override
  void initState() {
    super.initState();
    _future = widget.database.getSessionById(widget.session.id);
    _notesFuture = widget.database.getNotes(sessionId: widget.session.id);
    _stagesFuture = widget.database.getStages(widget.session.id);
    _metricsFuture = widget.database.getMetrics(widget.session.id);
    _reportFuture = widget.database.getMorningReport(widget.session.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.database.getSessionById(widget.session.id);
      _notesFuture = widget.database.getNotes(sessionId: widget.session.id);
      _stagesFuture = widget.database.getStages(widget.session.id);
      _metricsFuture = widget.database.getMetrics(widget.session.id);
      _reportFuture = widget.database.getMorningReport(widget.session.id);
    });
    await _future;
  }

  String _duration(Duration? duration) {
    if (duration == null) return 'Пока не рассчитана';
    if (duration.isNegative) return 'Некорректный интервал';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours ч ${minutes.toString().padLeft(2, '0')} мин';
  }

  String _dateTime(DateTime? value) => value == null
      ? 'Не указано'
      : DateFormat('d MMMM yyyy, HH:mm', 'ru').format(value);

  Future<void> _editMorningReport(SleepSession session) async {
    final existing = await widget.database.getMorningReport(session.id);
    Map<String, dynamic> answers = {};
    final raw = existing?['answers_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) answers = decoded;
      } catch (_) {}
    }
    var quality = (existing?['sleep_quality'] as int?) ?? 3;
    var wellbeing = (existing?['wellbeing'] as int?) ?? session.morningRating ?? 3;
    var sleepiness = (answers['sleepiness'] as num?)?.toInt() ?? 3;
    final comment = TextEditingController(text: answers['comment'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Утренний отчёт'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Насколько хорошо вы спали?'),
              Text('$quality из 5'),
              Slider(min: 1, max: 5, divisions: 4, value: quality.toDouble(), onChanged: (v) => setDialogState(() => quality = v.round())),
              const SizedBox(height: 8),
              const Text('Насколько вы чувствуете себя отдохнувшей?'),
              Text('$wellbeing из 5'),
              Slider(min: 1, max: 5, divisions: 4, value: wellbeing.toDouble(), onChanged: (v) => setDialogState(() => wellbeing = v.round())),
              const SizedBox(height: 8),
              const Text('Насколько сильно хочется спать сейчас?'),
              Text('$sleepiness из 5'),
              Slider(min: 1, max: 5, divisions: 4, value: sleepiness.toDouble(), onChanged: (v) => setDialogState(() => sleepiness = v.round())),
              TextField(controller: comment, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Комментарий (необязательно)')),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'skip'), child: const Text('Пропустить оценку')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, 'save'), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (!mounted) { comment.dispose(); return; }
    if (result == 'skip') {
      await widget.database.saveMorningReport(sessionId: session.id, wellbeing: null, quality: null, answersJson: jsonEncode({'skipped': true}));
      await widget.database.updateMorningRating(session.id, null);
    } else if (result == 'save') {
      await widget.database.saveMorningReport(
        sessionId: session.id, wellbeing: wellbeing, quality: quality,
        answersJson: jsonEncode({'wellbeing': wellbeing, 'sleepQuality': quality, 'sleepiness': sleepiness, 'comment': comment.text.trim(), 'skipped': false}),
      );
      await widget.database.updateMorningRating(session.id, wellbeing);
    }
    comment.dispose();
    if (result == 'save' || result == 'skip') {
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Утренний отчёт сохранён')));
    }
  }

  Widget _detailRow(String label, String value, {IconData? icon}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[
        Icon(icon, size: 18, color: AppTheme.teal),
        const SizedBox(width: 10),
      ],
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<SleepSession?>(
    future: _future,
    builder: (context, snapshot) {
      final session = snapshot.data ?? widget.session;
      final dateLabel = DateFormat('d MMMM yyyy', 'ru').format(session.startedAt);
      return Scaffold(
        appBar: AppBar(title: const Text('Карточка ночи')),
        body: snapshot.connectionState == ConnectionState.waiting
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Text(dateLabel.toUpperCase(), style: const TextStyle(
                      color: AppTheme.teal, letterSpacing: 1.4, fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                    const SizedBox(height: 8),
                    Text(session.isOpen ? 'Ночная сессия продолжается' : 'Отчёт о ночи',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 18),
                    SectionCard(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Продолжительность', style: TextStyle(color: AppTheme.muted)),
                        const SizedBox(height: 8),
                        Text(_duration(session.duration), style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold,
                        )),
                        const SizedBox(height: 8),
                        Text(session.isOpen
                            ? 'Сессия ещё не завершена — итоговая длительность появится после завершения.'
                            : 'Фактический интервал между сохранёнными временем начала и окончания.',
                            style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                      ],
                    )),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Время', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _detailRow('Начало', _dateTime(session.startedAt), icon: Icons.bedtime_outlined),
                        const Divider(height: 1),
                        _detailRow('Окончание', _dateTime(session.endedAt), icon: Icons.wb_sunny_outlined),
                        const Divider(height: 1),
                        _detailRow('Источник записи', session.source == 'manual' ? 'Вручную' : session.source,
                            icon: Icons.info_outline),
                      ],
                    )),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(child: Text('Утренний отчёт', style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold,
                          ))),
                          TextButton.icon(
                            onPressed: () => _editMorningReport(session),
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('Изменить'),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        FutureBuilder<Map<String, Object?>?>(future: _reportFuture, builder: (context, reportState) {
                          final report = reportState.data;
                          if (report == null && session.morningRating == null) return const Text('Оценки ещё не добавлены', style: TextStyle(color: AppTheme.muted));
                          Map<String, dynamic> answers = {};
                          final rawAnswers = report?['answers_json'];
                          if (rawAnswers is String && rawAnswers.isNotEmpty) {
                            try {
                              final decoded = jsonDecode(rawAnswers);
                              if (decoded is Map<String, dynamic>) answers = decoded;
                            } catch (_) {}
                          }
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (session.morningRating != null) Text('Самочувствие: ${session.morningRating} из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (report?['sleep_quality'] != null) Text('Качество сна: ${report!['sleep_quality']} из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (answers['sleepiness'] != null) Text('Сонливость: ${answers['sleepiness']} из 5', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if ((answers['comment'] as String?)?.trim().isNotEmpty == true)
                              Padding(padding: const EdgeInsets.only(top: 8), child: Text(answers['comment'] as String)),
                            if (answers['skipped'] == true) const Text('Субъективная оценка пропущена', style: TextStyle(color: AppTheme.muted)),
                          ]);
                        }),
                        const SizedBox(height: 14),
                        const Text('Заметки этой ночи', style: TextStyle(color: AppTheme.muted)),
                        const SizedBox(height: 6),
                        FutureBuilder<List<SleepNote>>(
                          future: _notesFuture,
                          builder: (context, noteSnapshot) {
                            final notes = noteSnapshot.data ?? const <SleepNote>[];
                            if (noteSnapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(padding: EdgeInsets.all(8),
                                child: LinearProgressIndicator());
                            }
                            if (notes.isEmpty && (session.note?.trim().isEmpty ?? true)) {
                              return const Text('Заметки пока не добавлены',
                                style: TextStyle(color: AppTheme.muted));
                            }
                            return Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (session.note?.trim().isNotEmpty ?? false)
                                  Padding(padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(session.note!, style: const TextStyle(height: 1.5))),
                                ...notes.map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('• ${note.text}', style: const TextStyle(height: 1.5)),
                                )),
                              ]);
                          },
                        ),
                        const SizedBox(height: 6),
                        const Text('Добавлять, редактировать и удалять отдельные заметки можно в разделе «Заметки».',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                      ],
                    )),
                    const SizedBox(height: 12),
                    SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Фазы сна', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, Object?>>>(future: _stagesFuture, builder: (context, state) {
                        final rows = state.data ?? const <Map<String, Object?>>[];
                        if (state.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                        if (rows.isEmpty) return const Text('Источник не предоставил детализацию фаз для этой ночи.', style: TextStyle(color: AppTheme.muted));
                        return Column(children: rows.map((row) {
                          final from = DateTime.parse(row['started_at']! as String).toLocal();
                          final to = DateTime.parse(row['ended_at']! as String).toLocal();
                          final mins = to.difference(from).inMinutes;
                          return _detailRow(row['stage']! as String, '$mins мин · ${DateFormat('HH:mm').format(from)}–${DateFormat('HH:mm').format(to)}');
                        }).toList());
                      }),
                      const Divider(height: 24),
                      const Text('Физиологические показатели', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, Object?>>>(future: _metricsFuture, builder: (context, state) {
                        final rows = state.data ?? const <Map<String, Object?>>[];
                        if (state.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                        if (rows.isEmpty) return const Text('За эту ночь доступные физиологические измерения не импортированы.', style: TextStyle(color: AppTheme.muted));
                        return Column(children: rows.map((row) => _detailRow(row['metric_type']! as String, '${(row['value'] as num).toStringAsFixed(1)} ${row['unit']} · ${DateFormat('HH:mm').format(DateTime.parse(row['measured_at']! as String).toLocal())}')).toList());
                      }),
                      const SizedBox(height: 8),
                      const Text('Показываются только измерения, реально полученные из Apple Health. Их отсутствие не заменяется оценками.', style: TextStyle(color: AppTheme.teal, fontSize: 12, height: 1.4)),
                    ])),
                  ],
                ),
              ),
      );
    },
  );
}
