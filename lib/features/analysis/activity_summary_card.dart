import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/apple_health_activity_service.dart';
import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class ActivitySummaryCard extends StatefulWidget {
  const ActivitySummaryCard({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<ActivitySummaryCard> createState() => _ActivitySummaryCardState();
}

class _ActivitySummaryCardState extends State<ActivitySummaryCard> {
  late Future<Map<String, dynamic>> _future;
  bool _syncing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await widget.database.getAppMetadata(AppleHealthActivityService.storageKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Сохранённые данные активности повреждены. Исходные данные не изменены.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _status = null;
    });
    try {
      final result = await AppleHealthActivityService.instance.syncRecentActivity(database: widget.database);
      if (!mounted) return;
      setState(() {
        _future = _load();
        _status = result.samplesRead == 0
            ? 'Новых доступных измерений не найдено. Ранее сохранённые данные оставлены без изменений.'
            : 'Обновлено дней: ${result.daysUpdated} · измерений: ${result.samplesRead}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось получить активность: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _number(num value) => NumberFormat.decimalPattern('ru').format(value.round());

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Дневная активность', style: TextStyle(fontWeight: FontWeight.w600))),
        TextButton.icon(
          onPressed: _syncing ? null : _sync,
          icon: _syncing
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded, size: 18),
          label: Text(_syncing ? 'Загрузка' : 'Из Apple Health'),
        ),
      ]),
      const Text(
        'Импортируются только доступные данные: шаги, активная энергия и минуты упражнений. Нужны разрешения Apple Health.',
        style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
      ),
      if (_status != null) ...[
        const SizedBox(height: 8),
        Text(_status!, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
      ],
      const SizedBox(height: 10),
      FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return Text('Не удалось прочитать активность: ${snapshot.error}',
              style: const TextStyle(color: AppTheme.accentPink, fontSize: 12));
          }
          final data = snapshot.data ?? {};
          final cutoff = DateTime.now().subtract(const Duration(days: 30));
          final rows = data.entries.where((entry) {
            final date = DateTime.tryParse(entry.key);
            return date != null && !date.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day)) && entry.value is Map;
          }).toList()
            ..sort((a, b) => b.key.compareTo(a.key));
          if (rows.isEmpty) {
            return const Text('Пока нет импортированных данных активности. После выдачи разрешений нажми «Из Apple Health».',
              style: TextStyle(color: AppTheme.muted, fontSize: 12));
          }

          num total(String key) => rows.fold<num>(0, (sum, row) {
            final value = (row.value as Map)[key];
            return sum + (value is num ? value : 0);
          });
          final hasSteps = rows.any((row) => (row.value as Map).containsKey('steps'));
          final hasEnergy = rows.any((row) => (row.value as Map).containsKey('activeEnergyKcal'));
          final hasExercise = rows.any((row) => (row.value as Map).containsKey('exerciseMinutes'));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('За последние 30 дней · ${rows.length} дней с данными',
              style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 8, children: [
              if (hasSteps) _ActivityTotal(label: 'Шаги', value: _number(total('steps'))),
              if (hasEnergy) _ActivityTotal(label: 'Активная энергия', value: '${_number(total('activeEnergyKcal'))} ккал'),
              if (hasExercise) _ActivityTotal(label: 'Упражнения', value: '${_number(total('exerciseMinutes'))} мин'),
            ]),
            const Divider(height: 22, color: AppTheme.surfaceLight),
            ...rows.take(7).map((row) {
              final values = row.value as Map;
              final date = DateTime.parse(row.key);
              final parts = <String>[];
              if (values['steps'] is num) parts.add('${_number(values['steps'] as num)} шагов');
              if (values['activeEnergyKcal'] is num) parts.add('${_number(values['activeEnergyKcal'] as num)} ккал');
              if (values['exerciseMinutes'] is num) parts.add('${_number(values['exerciseMinutes'] as num)} мин упражнений');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(DateFormat('d MMM', 'ru').format(date),
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
                  Expanded(child: Text(parts.join(' · '), style: const TextStyle(fontSize: 12))),
                ]),
              );
            }),
            const Text('Данные отражают записи, доступные приложению в Apple Health. Отсутствующие показатели не считаются нулевыми.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
          ]);
        },
      ),
    ]),
  );
}

class _ActivityTotal extends StatelessWidget {
  const _ActivityTotal({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
  ]);
}
