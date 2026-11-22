import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../data/weather_service.dart';
import '../analysis/moon_phase_analytics.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class _WeatherNightDetail {
  const _WeatherNightDetail({
    required this.location,
    required this.summary,
    required this.updatedAt,
    this.solarDay,
  });

  final WeatherLocation location;
  final WeatherNightSummary summary;
  final DateTime? updatedAt;
  final WeatherSolarDay? solarDay;
}

class WeatherNightDetailCard extends StatefulWidget {
  const WeatherNightDetailCard({super.key, required this.database, required this.session});
  final SleepDatabase database;
  final SleepSession session;

  @override
  State<WeatherNightDetailCard> createState() => _WeatherNightDetailCardState();
}

class _WeatherNightDetailCardState extends State<WeatherNightDetailCard> {
  late Future<_WeatherNightDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant WeatherNightDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _future = _load();
    }
  }

  Future<_WeatherNightDetail?> _load() async {
    final start = widget.session.actualSleepStartedAt;
    final end = widget.session.actualSleepEndedAt;
    if (start == null || end == null || !end.isAfter(start)) return null;

    final service = WeatherService.instance;
    final location = await service.loadSelectedLocation(database: widget.database);
    if (location == null) return null;

    final points = await service.loadCachedWeather(
      database: widget.database,
      location: location,
      start: start,
      end: end,
    );
    final summary = WeatherNightSummary.summarize(points, start: start, end: end);
    final solar = await service.loadSolarDay(
      database: widget.database,
      location: location,
      utcDate: end.toUtc(),
    );
    final updatedAt = await service.loadCacheUpdatedAt(database: widget.database, location: location);
    return _WeatherNightDetail(location: location, summary: summary, solarDay: solar, updatedAt: updatedAt);
  }

  String _updatedLabel(DateTime? value) => value == null
      ? 'время обновления неизвестно'
      : 'обновлено ${DateFormat('d MMM yyyy, HH:mm', 'ru').format(value)}';

  String _number(double? value, String unit) =>
      value == null ? 'Нет данных' : '${value.toStringAsFixed(1)} $unit';

  String _duration(double? seconds) {
    if (seconds == null || !seconds.isFinite) return 'Нет данных';
    return '${(seconds / 3600).toStringAsFixed(1)} ч';
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.session.actualSleepStartedAt;
    final end = widget.session.actualSleepEndedAt;
    final hasActual = start != null && end != null && end.isAfter(start);
    final midpoint = hasActual
        ? start.add(Duration(microseconds: end.difference(start).inMicroseconds ~/ 2))
        : null;
    final moon = midpoint == null ? null : MoonPhaseAnalytics.at(midpoint);

    return SectionCard(
      child: FutureBuilder<_WeatherNightDetail?>(
        future: _future,
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
              Text('Не удалось прочитать архивные данные: ${state.error}',
                style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
            ]);
          }
          final data = state.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Погода и астрономические условия', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            if (!hasActual)
              const Text('Нет фактических границ сна. Погодные показатели и фаза Луны для этой ночи не рассчитываются по времени кнопки начала сессии.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
            else if (data == null)
              const Text('Для этой ночи пока нет кэшированных погодных данных. Выбери город и загрузи историческую погоду в разделе «Анализ».',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
            else ...[
              Text(data.location.label,
                style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (data.summary.sampleCount == 0)
                const Text('В архиве нет почасовых точек внутри фактического интервала сна.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12))
              else ...[
                _row('Температура в среднем', _number(data.summary.averageTemperatureC, '°C')),
                _row('Относительная влажность', _number(data.summary.averageHumidityPercent, '%')),
                _row('Давление', _number(data.summary.averagePressureHpa, 'гПа')),
                _row('Скорость ветра', _number(data.summary.averageWindKmh, 'км/ч')),
                _row('Осадки за интервал', _number(data.summary.totalPrecipitationMm, 'мм')),
                Text('Часовых точек: ${data.summary.sampleCount}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
              ],
              if (data.solarDay != null) ...[
                const Divider(height: 18, color: AppTheme.surfaceLight),
                _row('Восход солнца', serviceTime(data, sunrise: true)),
                _row('Закат солнца', serviceTime(data, sunrise: false)),
                _row('Длительность светового дня', _duration(data.solarDay!.daylightDurationSeconds)),
              ],
            ],
            const Divider(height: 18, color: AppTheme.surfaceLight),
            _row('Фаза Луны на середину сна', moon?.label ?? 'Нет фактического интервала сна'),
            _row('Расчётная освещённость Луны',
              moon == null ? 'Нет данных' : '${(moon.illumination * 100).round()}%'),
            if (data != null)
              Text('Источник: Open-Meteo Historical Weather API · ${_updatedLabel(data.updatedAt)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
            const Text(
              'Погодные значения — архивная модель для координат выбранного города, а не измерение внутри спальни. Фаза и освещённость Луны рассчитываются локально и не измеряют яркость в помещении.',
              style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4),
            ),
          ]);
        },
      ),
    );
  }

  String serviceTime(_WeatherNightDetail data, {required bool sunrise}) {
    final instant = sunrise ? data.solarDay?.sunriseUtc : data.solarDay?.sunsetUtc;
    return WeatherService.instance.formatSolarTime(instant, data.location.timezone);
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
