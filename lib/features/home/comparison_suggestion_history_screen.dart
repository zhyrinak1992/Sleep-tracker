import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/comparison_suggestion_store.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_tag.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import '../analysis/tag_sleep_comparison.dart';
import 'suggested_tag_comparison_screen.dart';

class ComparisonSuggestionHistoryScreen extends StatefulWidget {
  const ComparisonSuggestionHistoryScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<ComparisonSuggestionHistoryScreen> createState() => _ComparisonSuggestionHistoryScreenState();
}

class _ComparisonSuggestionHistoryScreenState extends State<ComparisonSuggestionHistoryScreen> {
  late Future<_SuggestionHistoryData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SuggestionHistoryData> _load() async {
    final store = ComparisonSuggestionStore(
      widget.database.getAppMetadata,
      widget.database.setAppMetadata,
    );
    final history = await store.loadHistory();
    final custom = await CustomSleepTagStore(
      widget.database.getAppMetadata,
      widget.database.setAppMetadata,
    ).load();
    final labels = <String, String>{
      for (final tag in [...SleepTag.catalog, ...custom]) tag.key: tag.label,
    };
    history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _SuggestionHistoryData(history: history, labels: labels);
  }

  String _status(ComparisonSuggestionStatus status) => switch (status) {
    ComparisonSuggestionStatus.pending => 'Ожидает обработки',
    ComparisonSuggestionStatus.opened => 'Открыто',
    ComparisonSuggestionStatus.saved => 'Сохранено как шаблон',
    ComparisonSuggestionStatus.postponed => 'Отложено',
    ComparisonSuggestionStatus.rejected => 'Отклонено',
    ComparisonSuggestionStatus.closed => 'Закрыто',
    ComparisonSuggestionStatus.notViewed => 'Не просмотрено',
  };

  String _date(DateTime value) => DateFormat('d MMM yyyy, HH:mm', 'ru').format(value.toLocal());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('История предложений')),
    body: FutureBuilder<_SuggestionHistoryData>(
      future: _future,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (state.hasError) return Center(child: Text('Не удалось загрузить историю предложений: ${state.error}'));
        final data = state.data!;
        if (data.history.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('История предложений появится, когда накопятся достаточные данные для содержательного сравнения.'),
          ));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const ScreenHeader(
              title: 'История предложений сравнений',
              subtitle: 'Все показанные, открытые, сохранённые, отложенные и отклонённые предложения',
              icon: Icons.history_rounded,
            ),
            const SizedBox(height: 12),
            ...data.history.map((record) {
              final labels = record.candidate.tagKeys
                .map((key) => data.labels[key] ?? 'Отметка')
                .join(' + ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SectionCard(child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(labels, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${record.candidate.metric.label}\n${_status(record.status)} · ${_date(record.createdAt)}\nВыборки: ${record.candidate.withNights} и ${record.candidate.withoutNights} ночей',
                      style: const TextStyle(fontSize: 11, height: 1.45),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ComparisonSuggestionHistoryDetailScreen(
                      database: widget.database,
                      record: record,
                      tagLabels: data.labels,
                    ),
                  )),
                )),
              );
            }),
          ],
        );
      },
    ),
  );
}

class ComparisonSuggestionHistoryDetailScreen extends StatelessWidget {
  const ComparisonSuggestionHistoryDetailScreen({
    super.key,
    required this.database,
    required this.record,
    required this.tagLabels,
  });

  final SleepDatabase database;
  final ComparisonSuggestionRecord record;
  final Map<String, String> tagLabels;

  String _status(ComparisonSuggestionStatus status) => switch (status) {
    ComparisonSuggestionStatus.pending => 'Ожидает обработки',
    ComparisonSuggestionStatus.opened => 'Открыто',
    ComparisonSuggestionStatus.saved => 'Сохранено как шаблон',
    ComparisonSuggestionStatus.postponed => 'Отложено',
    ComparisonSuggestionStatus.rejected => 'Отклонено',
    ComparisonSuggestionStatus.closed => 'Закрыто',
    ComparisonSuggestionStatus.notViewed => 'Не просмотрено',
  };

  String _pValue(double value) => value < 0.001
      ? 'p < 0,001'
      : 'p = ${value.toStringAsFixed(3).replaceAll('.', ',')}';

  String _differenceUnit(TagSleepMetric metric) => switch (metric) {
    TagSleepMetric.sleepDuration => 'мин',
    TagSleepMetric.morningRating => 'балла',
    TagSleepMetric.awakeningCount => 'эпизода',
  };

  @override
  Widget build(BuildContext context) {
    final candidate = record.candidate;
    final tags = candidate.tagKeys.map((key) => tagLabels[key] ?? 'Отметка').join(' + ');
    return Scaffold(
      appBar: AppBar(title: const Text('Предложение сравнения')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tags, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 6),
              Text(candidate.metric.label),
              Text('Период: ${DateFormat('d MMM yyyy', 'ru').format(candidate.start.toLocal())} — ${DateFormat('d MMM yyyy', 'ru').format(DateTime(candidate.endExclusive.toLocal().year, candidate.endExclusive.toLocal().month, candidate.endExclusive.toLocal().day - 1))}'),
              const SizedBox(height: 8),
              Text('Ночи с отметками: ${candidate.withNights}; без комбинации: ${candidate.withoutNights}.'),
              Text('Средние значения: ${candidate.withAverage.toStringAsFixed(1)} и ${candidate.withoutAverage.toStringAsFixed(1)} ${candidate.metric.unit}.'),
              Text('Разница: ${candidate.difference > 0 ? '+' : ''}${candidate.difference.toStringAsFixed(1)} ${_differenceUnit(candidate.metric)}.'),
              Text('U-критерий Манна — Уитни: ${_pValue(candidate.pValue)}.'),
              const SizedBox(height: 8),
              Text('Текущий статус: ${_status(record.status)}',
                style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
            ],
          )),
          const SizedBox(height: 12),
          SectionCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('История статусов', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...record.statusEvents.map((event) {
                final statusName = event['status'] as String? ?? '';
                final status = ComparisonSuggestionStatus.values.where((item) => item.name == statusName);
                final at = DateTime.tryParse(event['at'] as String? ?? '');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text('${status.isEmpty ? statusName : _status(status.first)} · ${at == null ? 'время не указано' : DateFormat('d MMM yyyy, HH:mm', 'ru').format(at.toLocal())}',
                    style: const TextStyle(fontSize: 12)),
                );
              }),
            ],
          )),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SuggestedTagComparisonScreen(
                database: database,
                candidate: candidate,
                tagLabels: tagLabels,
              ),
            )),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Пересчитать и открыть сравнение'),
          ),
          const SizedBox(height: 8),
          const Text('При открытии из истории сравнение пересчитывается по актуальным ночным записям. Сохранённое предложение остаётся в истории и не возвращается на главный экран автоматически.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45)),
        ],
      ),
    );
  }
}

class _SuggestionHistoryData {
  const _SuggestionHistoryData({required this.history, required this.labels});
  final List<ComparisonSuggestionRecord> history;
  final Map<String, String> labels;
}
