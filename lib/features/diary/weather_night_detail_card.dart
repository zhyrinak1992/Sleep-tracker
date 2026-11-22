import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../data/weather_history_service.dart';
import '../analysis/moon_phase_analytics.dart';
import '../../models/sleep_session.dart';
import '../../models/weather_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class WeatherNightDetailCard extends StatelessWidget {
  const WeatherNightDetailCard({super.key, required this.database, required this.session});
  final SleepDatabase database;
  final SleepSession session;

  Future<WeatherNightRecord?> _load() async {
    final raw = await database.getAppMetadata('${WeatherHistoryService.recordPrefix}${session.id}');
    if (raw == null || raw.isEmpty) return null;
    final record = WeatherNightRecord.tryParse(raw);
    if (record == null || record.sessionId != session.id) {
      throw const FormatException('Сохранённая погодная запись повреждена или относится к другой ночи.');
    }
    return record;
  }

  String _metric(WeatherMetricSummary? value) {
    if (value == null) return 'Нет данных';
    return 'Мин. ${value.minimum.toStringAsFixed(1)} · сред. ${value.average.toStringAsFixed(1)} · макс. ${value.maximum.toStringAsFixed(1)} ${value.unit}';
  }

  String _clock(String? value) =>
      value != null && value.length >= 16 ? value.substring(11, 16) : 'Нет данных';

  @override
  Widget build(BuildContext context) {
    final actualStart = session.actualSleepStartedAt;
    final actualEnd = session.actualSleepEndedAt;
    final hasActualInterval = actualStart != null && actualEnd != null && actualEnd.isAfter(actualStart);
    final midpoint = hasActualInterval
        ? actualStart.add(Duration(microseconds: actualEnd.difference(actualStart).inMicroseconds ~/ 2))
        : null;
    final moon = midpoint == null ? null : MoonPhaseAnalytics.at(midpoint);

    return SectionCard(
      child: FutureBuilder<WeatherNightRecord?>(
        future: _load(),
        builder: (context, state) {
          if (state.connectionState == ConnectionState.waiting) {
            return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Погода и астрономические условия', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              LinearProgressIndicator(),
            ]);
          }
          if (state.hasError) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Погода и астрономические условия', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Не удалось прочитать погодную запись: ${state.error}',
                style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
            ]);
          }
          final record = state.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Погода и астрономические условия', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (record == null)
              const Text('Историческая погода для этой ночи ещё не загружена. Выбери город и запусти получение истории в разделе «Анализ».',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
            else ...[
              Text(record.location.displayName,
                style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (!record.dataAvailable)
                const Text('Поставщик не вернул исторические значения для этой ночи. Текущая погода не подставляется.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
              else ...[
                _row('Температура', _metric(record.temperature)),
                _row('Относительная влажность', _metric(record.humidity)),
                _row('Давление', _metric(record.pressure)),
                _row('Скорость ветра', _metric(record.windSpeed)),
                _row('Осадки за интервал', record.precipitationMm == null
                    ? 'Нет данных' : '${record.precipitationMm!.toStringAsFixed(1)} мм'),
                const Divider(height: 18, color: AppTheme.surfaceLight),
                _row('Восход солнца', _clock(record.sunrise)),
                _row('Закат солнца', _clock(record.sunset)),
                _row('Световой день', record.daylightHours == null
                    ? 'Нет данных' : '${record.daylightHours!.toStringAsFixed(1)} ч'),
                Text('Часовых измерений: ${record.sampleCount}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
              ],
              const SizedBox(height: 5),
              Text('Источник: ${record.provider} · обновлено ${DateFormat('d MMM yyyy, HH:mm', 'ru').format(record.fetchedAt)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
            ],
            const Divider(height: 18, color: AppTheme.surfaceLight),
            _row('Фаза Луны на середину сна', moon?.label ?? 'Нет фактического интервала сна'),
            _row('Расчётная освещённость Луны', moon == null ? 'Нет данных' : '${(moon.illumination * 100).round()}%'),
            const Text(
              'Погодные значения — архивные оценки поставщика с часовым разрешением; полнота зависит от доступности данных. Фаза и освещённость Луны рассчитываются локально и не измеряют яркость в спальне.',
              style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4),
            ),
          ]);
        },
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Flexible(child: Text(value, textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );
}
