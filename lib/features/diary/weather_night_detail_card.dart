import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/sleep_database.dart';
import '../../data/weather_service.dart';
import '../analysis/moon_phase_analytics.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class _NightWeatherData {
  const _NightWeatherData({
    required this.location,
    required this.summary,
    this.updatedAt,
  });

  final WeatherLocation location;
  final WeatherNightSummary summary;
  final DateTime? updatedAt;
}

class WeatherNightDetailCard extends StatefulWidget {
  const WeatherNightDetailCard({super.key, required this.database, required this.session});
  final SleepDatabase database;
  final SleepSession session;

  @override
  State<WeatherNightDetailCard> createState() => _WeatherNightDetailCardState();
}

class _WeatherNightDetailCardState extends State<WeatherNightDetailCard> {
  late Future<_NightWeatherData?> _future;
  static bool _timezoneReady = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant WeatherNightDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.actualSleepStartedAt != widget.session.actualSleepStartedAt ||
        oldWidget.session.actualSleepEndedAt != widget.session.actualSleepEndedAt) {
      _future = _load();
    }
  }

  Future<_NightWeatherData?> _load() async {
    final start = widget.session.actualSleepStartedAt;
    final end = widget.session.actualSleepEndedAt;
    if (start == null || end == null || !end.isAfter(start)) return null;

    final service = WeatherService.instance;
    final location = await service.loadSelectedLocation(database: widget.database);
    if (location == null) return null;

    final pointsFuture = service.loadHistoricalWeather(
      database: widget.database,
      location: location,
      start: start,
      end: end,
    );
    final solarFuture = service.loadSolarEvents(
      database: widget.database,
      location: location,
      start: start,
      end: end,
    );
    final points = await pointsFuture;
    final solarEvents = await solarFuture;
    final summary = WeatherNightSummary.summarize(
      points,
      start: start,
      end: end,
      solarEvents: solarEvents,
    );
    final updatedAt = await service.loadLatestCacheUpdatedAt(
      database: widget.database,
      location: location,
    );
    return _NightWeatherData(location: location, summary: summary, updatedAt: updatedAt);
  }

  String _time(DateTime? value, String timezone) {
    if (value == null) return 'Нет данных';
    if (!_timezoneReady) {
      tzdata.initializeTimeZones();
      _timezoneReady = true;
    }
    try {
      final local = tz.TZDateTime.from(value.toUtc(), tz.getLocation(timezone));
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Нет данных';
    }
  }

  String _number(double? value, String unit) =>
      value == null ? 'Нет данных' : '${value.toStringAsFixed(1)} $unit';

  String _duration(double? seconds) =>
      seconds == null || !seconds.isFinite ? 'Нет данных' : '${(seconds / 3600).toStringAsFixed(1)} ч';

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
      child: FutureBuilder<_NightWeatherData?>(
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
              Text('Не удалось загрузить архив: ${state.error}',
                style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
            ]);
          }
          final data = state.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Погода и астрономические условия', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            if (!hasActual)
              const Text('Нет фактических границ сна. Погодные условия и фаза Луны не рассчитываются по времени нажатия кнопки.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
            else if (data == null)
              const Text('Сначала выбери город в разделе «Анализ», чтобы получить исторические погодные данные.',
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
              const Divider(height: 18, color: AppTheme.surfaceLight),
              _row('Восход солнца', _time(data.summary.sunriseUtc, data.location.timezone)),
              _row('Закат солнца', _time(data.summary.sunsetUtc, data.location.timezone)),
              _row('Длительность светового дня', _duration(data.summary.daylightDurationSeconds)),
              if (data.updatedAt != null)
                Text('Open-Meteo Historical Weather API · обновлено ${DateFormat('d MMM yyyy, HH:mm', 'ru').format(data.updatedAt!)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
            ],
            const Divider(height: 18, color: AppTheme.surfaceLight),
            _row('Фаза Луны на середину сна', moon?.label ?? 'Нет фактического интервала сна'),
            _row('Расчётная освещённость Луны',
              moon == null ? 'Нет данных' : '${(moon.illumination * 100).round()}%'),
            const Text(
              'Погодные значения — архивная модель для координат выбранного города, а не измерение внутри спальни. Фаза и освещённость Луны рассчитываются локально.',
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
