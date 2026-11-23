import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/comparison_suggestion_store.dart';
import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../analysis/tag_sleep_comparison.dart';
import '../analysis/tag_sleep_comparison_card.dart';
import 'comparison_suggestion_analyzer.dart';
import 'suggested_tag_comparison_screen.dart';

class ComparisonSuggestionCard extends StatefulWidget {
  const ComparisonSuggestionCard({
    super.key,
    required this.database,
    required this.record,
    required this.tagLabels,
    required this.onProcessed,
  });

  final SleepDatabase database;
  final ComparisonSuggestionRecord record;
  final Map<String, String> tagLabels;
  final VoidCallback onProcessed;

  @override
  State<ComparisonSuggestionCard> createState() => _ComparisonSuggestionCardState();
}

class _ComparisonSuggestionCardState extends State<ComparisonSuggestionCard> {
  bool _busy = false;

  ComparisonSuggestionStore get _store => ComparisonSuggestionStore(
    widget.database.getAppMetadata,
    widget.database.setAppMetadata,
  );

  String _value(double value, TagSleepMetric metric) {
    if (metric == TagSleepMetric.sleepDuration) {
      final minutes = value.round();
      return '${minutes ~/ 60} ч ${minutes.remainder(60)} мин';
    }
    if (metric == TagSleepMetric.morningRating) return '${value.toStringAsFixed(1)} из 5';
    return '${value.toStringAsFixed(1)} эпизода';
  }

  String _differenceUnit(TagSleepMetric metric) => switch (metric) {
    TagSleepMetric.sleepDuration => 'мин',
    TagSleepMetric.morningRating => 'балла',
    TagSleepMetric.awakeningCount => 'эпизода',
  };

  String get _tags => widget.record.candidate.tagKeys
      .map((key) => widget.tagLabels[key] ?? 'Отметка')
      .join(' + ');

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _store.updateStatus(
        id: widget.record.id,
        status: ComparisonSuggestionStatus.opened,
        now: DateTime.now(),
      );
      if (!mounted) return;
      widget.onProcessed();
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SuggestedTagComparisonScreen(
          database: widget.database,
          candidate: widget.record.candidate,
          tagLabels: widget.tagLabels,
        ),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть сравнение: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTemplate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = TagComparisonTemplateStore(
        widget.database.getAppMetadata,
        widget.database.setAppMetadata,
      );
      final templates = await store.load();
      final existing = templates.where((item) =>
        item.tagKeys.toSet().containsAll(widget.record.candidate.tagKeys) &&
        widget.record.candidate.tagKeys.toSet().containsAll(item.tagKeys)).toList();
      if (existing.isEmpty) {
        final baseName = 'Сравнение: $_tags';
        var name = baseName;
        var suffix = 2;
        while (templates.any((item) => item.name.toLowerCase() == name.toLowerCase())) {
          name = '$baseName ($suffix)';
          suffix++;
        }
        await store.save([...templates, TagComparisonTemplate(
          id: const Uuid().v4(),
          name: name,
          tagKeys: widget.record.candidate.tagKeys,
          metric: widget.record.candidate.metric,
        )]);
      }
      await _store.updateStatus(
        id: widget.record.id,
        status: ComparisonSuggestionStatus.saved,
        now: DateTime.now(),
      );
      if (!mounted) return;
      widget.onProcessed();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(existing.isEmpty ? 'Сравнение сохранено как шаблон.' : 'Такой шаблон уже существует. Предложение отмечено как сохранённое.'),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить шаблон: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(ComparisonSuggestionStatus status, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _store.updateStatus(id: widget.record.id, status: status, now: DateTime.now());
      if (!mounted) return;
      widget.onProcessed();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить предложение: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.record.candidate;
    final difference = candidate.difference;
    final signed = difference > 0 ? '+' : difference < 0 ? '−' : '';
    final diffText = candidate.metric == TagSleepMetric.sleepDuration
        ? '$signed${_value(difference.abs(), candidate.metric)}'
        : '$signed${difference.abs().toStringAsFixed(1)} ${_differenceUnit(candidate.metric)}';
    final start = candidate.start;
    final end = DateTime(candidate.endExclusive.year, candidate.endExclusive.month, candidate.endExclusive.day - 1);
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.teal),
          const SizedBox(width: 8),
          const Expanded(child: Text('Новое предложение сравнения',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 10),
        Text(_tags, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Показатель: ${candidate.metric.label}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 8),
        Text('Основание: ${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}–${end.day.toString().padLeft(2, '0')}.${end.month.toString().padLeft(2, '0')} · ${candidate.withNights} ночей с отметками и ${candidate.withoutNights} без них.',
          style: const TextStyle(fontSize: 12, height: 1.4)),
        const SizedBox(height: 6),
        Text('Разница средних: $diffText',
          style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
        Text('Значения: ${_value(candidate.withAverage, candidate.metric)} против ${_value(candidate.withoutAverage, candidate.metric)}. Различие превышает установленный порог для этой метрики; это повод посмотреть данные, а не вывод о причине.',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Открыть сравнение'),
        )),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _busy ? null : _saveTemplate,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Сохранить шаблон'),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _setStatus(
              ComparisonSuggestionStatus.postponed, 'Предложение отложено. Оно не появится снова без новых оснований.',
            ),
            icon: const Icon(Icons.schedule_rounded),
            label: const Text('Отложить'),
          )),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : () => _setStatus(
              ComparisonSuggestionStatus.rejected, 'Предложение отклонено. При накоплении новых данных оно может появиться снова.',
            ),
            child: const Text('Отклонить'),
          ),
        ),
      ],
    ));
  }
}
