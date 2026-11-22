import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_tag.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'tag_sleep_comparison.dart';
import 'tag_combination_suggestions.dart';
import '../diary/sleep_session_metrics.dart';

class TagSleepComparisonCard extends StatefulWidget {
  const TagSleepComparisonCard({
    super.key,
    required this.database,
    required this.sessions,
    required this.start,
    required this.endExclusive,
  });

  final SleepDatabase database;
  final List<SleepSession> sessions;
  final DateTime start;
  final DateTime endExclusive;

  @override
  State<TagSleepComparisonCard> createState() => _TagSleepComparisonCardState();
}

class _TagSleepComparisonCardState extends State<TagSleepComparisonCard> {
  late Future<_TagComparisonData> _data;
  Set<String> _tagKeys = {SleepTag.catalog.first.key};
  TagSleepMetric _metric = TagSleepMetric.sleepDuration;
  String? _activeTemplateId;
  bool _saving = false;

  TagComparisonTemplateStore get _store => TagComparisonTemplateStore(
    widget.database.getAppMetadata,
    widget.database.setAppMetadata,
  );

  TagCombinationSuggestionStore get _combinationSuggestionStore => TagCombinationSuggestionStore(
    widget.database.getAppMetadata,
    widget.database.setAppMetadata,
  );

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  @override
  void didUpdateWidget(covariant TagSleepComparisonCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions ||
        oldWidget.start != widget.start ||
        oldWidget.endExclusive != widget.endExclusive) {
      _data = _loadData();
    }
  }

  Future<_TagComparisonData> _loadData() async {
    final tags = await widget.database.getTagsForSessions(
      widget.sessions.map((session) => session.id).toList(),
    );
    final stagesBySession = await widget.database.getStagesForSessions(
      widget.sessions.map((session) => session.id).toList(),
    );
    final awakeningCounts = <String, int>{};
    for (final session in widget.sessions) {
      final stages = stagesBySession[session.id] ?? const <Map<String, Object?>>[];
      final hasAwakeSamples = stages.any((row) {
        final stage = (row['stage'] as String? ?? '').toLowerCase();
        return stage.contains('бодрств') || stage == 'awake' || stage.contains('awake');
      });
      if (!hasAwakeSamples) continue;
      awakeningCounts[session.id] = SleepSessionMetrics.calculate(
        session: session,
        stages: stages,
      ).awakeningCount;
    }
    final templates = await _store.load();
    final customTags = await CustomSleepTagStore(
      widget.database.getAppMetadata,
      widget.database.setAppMetadata,
    ).load();
    final dismissed = await _combinationSuggestionStore.loadDismissed();
    final suggestions = TagCombinationSuggestionAnalyzer.analyze(
      sessions: widget.sessions,
      tagsBySession: tags,
      start: widget.start,
      endExclusive: widget.endExclusive,
      existingCombinations: templates.map((item) => item.tagKeys),
      dismissedSignatures: dismissed,
    );
    return _TagComparisonData(
      tagsBySession: tags,
      awakeningCountsBySession: awakeningCounts,
      templates: templates,
      customTags: customTags,
      suggestions: suggestions,
    );
  }

  Future<void> _reload() async {
    setState(() => _data = _loadData());
    await _data;
  }

  String _formatDifference(double value, TagSleepMetric metric) {
    final sign = value > 0 ? '+' : value < 0 ? '−' : '';
    final absolute = value.abs();
    if (metric == TagSleepMetric.sleepDuration) {
      final minutes = absolute.round();
      return '$sign${minutes ~/ 60} ч ${minutes % 60} мин';
    }
    if (metric == TagSleepMetric.awakeningCount) {
      return '$sign${absolute.round()} эпизодов';
    }
    return '$sign${absolute.toStringAsFixed(1)} балла';
  }

  String _formatValue(double? value, TagSleepMetric metric) {
    if (value == null) return 'Недостаточно данных';
    if (metric == TagSleepMetric.sleepDuration) {
      final minutes = value.round();
      return '${minutes ~/ 60} ч ${minutes % 60} мин';
    }
    if (metric == TagSleepMetric.awakeningCount) {
      return '${value.round()} эпизодов';
    }
    return '${value.toStringAsFixed(1)} из 5';
  }

  Future<void> _saveTemplate(_TagComparisonData data) async {
    final tagKeys = _tagKeys.toList()..sort();
    if (tagKeys.isEmpty) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Сохранить сравнение'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название шаблона',
            hintText: 'Например, «Кофе и сон»',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final templates = await _store.load();
      final duplicate = templates.any((item) => item.name.toLowerCase() == name.trim().toLowerCase());
      if (duplicate) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Шаблон с таким названием уже существует.')),
        );
        return;
      }
      final template = TagComparisonTemplate(
        id: const Uuid().v4(),
        name: name.trim(),
        tagKeys: tagKeys,
        metric: _metric,
        awakeningCountsBySession: data.awakeningCountsBySession,
      );
      await _store.save([...templates, template]);
      if (!mounted) return;
      setState(() {
        _activeTemplateId = template.id;
        _data = _loadData();
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить шаблон: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _renameTemplate(TagComparisonTemplate template) async {
    final controller = TextEditingController(text: template.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать шаблон'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final templates = await _store.load();
    if (templates.any((item) => item.id != template.id &&
        item.name.toLowerCase() == name.trim().toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Шаблон с таким названием уже существует.')),
      );
      return;
    }
    await _store.save(templates.map((item) => item.id == template.id
      ? TagComparisonTemplate(id: item.id, name: name.trim(), tagKeys: item.tagKeys, metric: item.metric)
      : item).toList());
    await _reload();
  }

  Future<void> _dismissCombinationSuggestion(TagCombinationSuggestion suggestion) async {
    await _combinationSuggestionStore.dismiss(suggestion.tagKeys);
    await _reload();
  }

  Future<void> _deleteTemplate(TagComparisonTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить шаблон?'),
        content: Text('«${template.name}» будет удалён. Ночные записи, заметки и отметки останутся без изменений.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirm != true) return;
    final templates = await _store.load();
    await _store.save(templates.where((item) => item.id != template.id).toList());
    if (!mounted) return;
    setState(() {
      if (_activeTemplateId == template.id) _activeTemplateId = null;
      _data = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TagComparisonData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return SectionCard(child: Text('Не удалось загрузить сравнение отметок: ${snapshot.error}'));
      }
      final data = snapshot.data!;
      final availableTags = [...SleepTag.catalog, ...data.customTags];
      String tagLabel(String key) {
        for (final tag in availableTags) {
          if (tag.key == key) return tag.label;
        }
        return 'Отметка недоступна';
      }
      final selectedKeys = _tagKeys.where(
        (key) => availableTags.any((tag) => tag.key == key),
      ).toSet();
      if (selectedKeys.isEmpty) selectedKeys.add(availableTags.first.key);
      final selectedLabels = selectedKeys.map(tagLabel).toList();
      final result = TagSleepComparison.calculate(
        sessions: widget.sessions,
        tagsBySession: data.tagsBySession,
        tagKeys: selectedKeys,
        start: widget.start,
        endExclusive: widget.endExclusive,
        metric: _metric,
      );
      final matchingTemplates = data.templates.where((item) => item.id == _activeTemplateId);
      final activeTemplate = matchingTemplates.isEmpty ? null : matchingTemplates.first;

      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Сравнение по отметкам', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 5),
            const Text(
              'Сопоставление ночей со всеми выбранными отметками одновременно и без полной комбинации. Это наблюдаемая связь, а не доказательство причины.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (data.templates.isNotEmpty) ...[
              const Text('Сохранённые шаблоны', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...data.templates.map((template) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${template.tagKeys.map(tagLabel).join(' + ')} · ${template.metric.label}'),
                selected: template.id == _activeTemplateId,
                onTap: () => setState(() {
                  _activeTemplateId = template.id;
                  _tagKeys = template.tagKeys.toSet();
                  _metric = template.metric;
                }),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Действия с шаблоном',
                  onSelected: (value) {
                    if (value == 'rename') _renameTemplate(template);
                    if (value == 'delete') _deleteTemplate(template);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              )),
              const Divider(height: 18),
            ],
            if (data.suggestions.isNotEmpty) ...[
              const Text('Возможные сочетания', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Эти отметки регулярно встречались вместе в разных ночах текущего периода. Это повод посмотреть данные, а не вывод о причине.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
              ...data.suggestions.map((suggestion) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(suggestion.tagKeys.map(tagLabel).join(' + ')),
                subtitle: Text('Вместе в ${suggestion.nightCount} ночах'),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'Открыть сравнение',
                      onPressed: () => setState(() {
                        _tagKeys = suggestion.tagKeys.toSet();
                        _activeTemplateId = null;
                      }),
                      icon: const Icon(Icons.open_in_new, color: AppTheme.teal),
                    ),
                    IconButton(
                      tooltip: 'Сохранить шаблон',
                      onPressed: () {
                        setState(() {
                          _tagKeys = suggestion.tagKeys.toSet();
                          _activeTemplateId = null;
                        });
                        _saveTemplate(data);
                      },
                      icon: const Icon(Icons.bookmark_add_outlined),
                    ),
                    IconButton(
                      tooltip: 'Не предлагать снова',
                      onPressed: () => _dismissCombinationSuggestion(suggestion),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              )),
              const Divider(height: 18),
            ],
            const Text('Сопоставить сочетание отметок', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: availableTags.map((tag) => FilterChip(
                label: Text(tag.label),
                selected: selectedKeys.contains(tag.key),
                onSelected: (selected) {
                  if (!selected && selectedKeys.length == 1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Оставь хотя бы одну отметку для сравнения.')),
                    );
                    return;
                  }
                  setState(() {
                    if (selected) {
                      _tagKeys.add(tag.key);
                    } else {
                      _tagKeys.remove(tag.key);
                    }
                    _activeTemplateId = null;
                  });
                },
              )).toList(),
            ),
            const SizedBox(height: 10),
            const Text(
              'В группу «с отметками» попадают ночи, где присутствуют все выбранные отметки одновременно.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<TagSleepMetric>(
              value: _metric,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Показатель'),
              items: TagSleepMetric.values.map((metric) => DropdownMenuItem(
                value: metric,
                child: Text(metric.label),
              )).toList(),
              onChanged: (value) => setState(() {
                if (value != null) {
                  _metric = value;
                  _activeTemplateId = null;
                }
              }),
            ),
            const SizedBox(height: 14),
            _groupRow('Со всеми отметками: «${selectedLabels.join(' + ')}»', result.withTag, result.metric),
            const SizedBox(height: 7),
            _groupRow('Без полной комбинации', result.withoutTag, result.metric),
            const SizedBox(height: 12),
            if (!result.isSufficient)
              Text(
                'Пока недостаточно сопоставимых данных. Нужно не менее ${TagSleepComparison.minimumNightsPerGroup} завершённых ночей в каждой группе; сейчас: ${result.withTag.nights} и ${result.withoutTag.nights}.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
              )
            else
              Text(
                'Разница средних: ${_formatDifference(result.difference!, result.metric)} в группе со всеми отметками. Выборки: ${result.withTag.nights} и ${result.withoutTag.nights} ночей.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
              ),
            const SizedBox(height: 5),
            const Text(
              'Учитываются только завершённые ночи с доступным выбранным показателем. Недостающие значения не заменяются нулями. Результат не является медицинским выводом.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _saveTemplate(data),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_saving ? 'Сохранение…' : 'Сохранить как шаблон'),
              ),
            ),
            if (activeTemplate != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  'Шаблон «${activeTemplate.name}» пересчитывается по данным выбранного периода.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _groupRow(String label, TagSleepGroupSummary summary, TagSleepMetric metric) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_formatValue(summary.average, metric), style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${summary.nights} ${summary.nights == 1 ? 'ночь' : 'ночей'}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ]),
      ]);
}

class _TagComparisonData {
  const _TagComparisonData({
    required this.tagsBySession,
    required this.awakeningCountsBySession,
    required this.templates,
    required this.customTags,
    required this.suggestions,
  });
  final Map<String, Set<String>> tagsBySession;
  final Map<String, int> awakeningCountsBySession;
  final List<TagComparisonTemplate> templates;
  final List<SleepTag> customTags;
  final List<TagCombinationSuggestion> suggestions;
}
