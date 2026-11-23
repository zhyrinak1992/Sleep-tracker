import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../analysis/tag_sleep_comparison.dart';
import '../analysis/tag_sleep_comparison_card.dart';
import 'comparison_suggestion_analyzer.dart';

class SuggestedTagComparisonScreen extends StatefulWidget {
  const SuggestedTagComparisonScreen({
    super.key,
    required this.database,
    required this.candidate,
    required this.tagLabels,
  });

  final SleepDatabase database;
  final ComparisonSuggestionCandidate candidate;
  final Map<String, String> tagLabels;

  @override
  State<SuggestedTagComparisonScreen> createState() => _SuggestedTagComparisonScreenState();
}

class _SuggestedTagComparisonScreenState extends State<SuggestedTagComparisonScreen> {
  late Future<List<SleepSession>> _sessions;

  @override
  void initState() {
    super.initState();
    // Fetch again at open time: the suggestion is a prompt, not a frozen result.
    _sessions = widget.database.getSessions(limit: 10000);
  }

  String _period(DateTime start, DateTime end) {
    final last = DateTime(end.year, end.month, end.day - 1);
    return '${DateFormat('d MMM', 'ru').format(start)} — ${DateFormat('d MMM yyyy', 'ru').format(last)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Предложенное сравнение')),
    body: FutureBuilder<List<SleepSession>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось обновить данные для сравнения: ${snapshot.error}'),
          ));
        }
        final now = DateTime.now();
        final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final start = end.subtract(const Duration(days: 90));
        final sessions = snapshot.data ?? const <SleepSession>[];
        final selectedLabels = widget.candidate.tagKeys
            .map((key) => widget.tagLabels[key] ?? 'Отметка')
            .join(' + ');
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Предложение обновлено по текущей истории',
                  style: TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Категории: $selectedLabels'),
                Text('Период: ${_period(start, end)}'),
                const SizedBox(height: 6),
                const Text('Ниже сравнение пересчитывается заново по актуальным ночным записям. Предыдущее предложение не является сохранённым результатом.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
              ],
            )),
            const SizedBox(height: 12),
            TagSleepComparisonCard(
              database: widget.database,
              sessions: sessions,
              start: start,
              endExclusive: end,
              initialTagKeys: widget.candidate.tagKeys,
              initialMetric: widget.candidate.metric,
            ),
          ],
        );
      },
    ),
  );
}
