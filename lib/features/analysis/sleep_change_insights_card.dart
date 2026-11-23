import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'sleep_change_insights.dart';

class SleepChangeInsightsCard extends StatelessWidget {
  const SleepChangeInsightsCard({super.key, required this.insights});

  final SleepChangeInsights insights;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Итог за два 30-дневных периода',
            style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(insights.personalSummary,
            style: const TextStyle(fontSize: 12, height: 1.5)),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppTheme.surfaceLight),
          const SizedBox(height: 12),
          const Text('Главное изменение периода',
            style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (!insights.hasComparableData)
            const Text('Блок появится, когда накопится достаточно сопоставимых данных.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
          else if (insights.mainChange == null)
            const Text('Одного выраженного главного изменения не выявлено. При близкой значимости нескольких показателей не выбирается произвольный победитель.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
          else ...[
            Text(insights.mainChange!.title,
              style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(insights.mainChange!.description,
              style: const TextStyle(fontSize: 12, height: 1.5)),
            Text('Отбор: изменение не меньше установленного порога для этой метрики; значимость нормирована на её собственный порог. Ночи/оценки: ${insights.mainChange!.previousSamples} → ${insights.mainChange!.currentSamples}.',
              style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
