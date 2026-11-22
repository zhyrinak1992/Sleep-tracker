import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/sleep_database.dart';
import '../../data/weather_service.dart';
import '../../models/sleep_session.dart';
import '../analysis/moon_phase_analytics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class _NightWeatherData {
  const _NightWeatherData({required this.location, required this.summary});
  final WeatherLocation location;
  final WeatherNightSummary summary;
}

class WeatherNightDetailCard extends StatefulWidget {
  const WeatherNightDetailCard({
    super.key,
    required this.database,
    required this.session,
  });

  final SleepDatabase database;
  final SleepSession session;

  @override
  State<WeatherNightDetailCard> createState() => _WeatherNightDetailCardState();
}

class _WeatherNightDetailCardState extends State<WeatherNightDetailCard> {
  static bool _timeZonesInitialized = false;
  late Future<_NightWeatherData?> _future;

  @override
  void initState() {
    super.initState();
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
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

    final raw = await widget.database.getAppMetadata(WeatherService.locationStorageKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Сохранённое местоположение для погоды повреждено.');
    }
    final location = WeatherLocation.fromJson(decoded);
    final pointsFuture = WeatherService.instance.loadHistoricalWeather(
      database: widget.database,
      location: location,
      start: start,
      end: end,
    );
    final solarFuture = WeatherService.instance.loadSolarEvents(
      database: widget.database,
      location: location,
      start: start,
      end: end,
    );
    final points = await pointsFuture;
    final solar = await solarFuture;
    return _NightWeatherData(
      location: location,
      summary: WeatherNightSummary.summarize(
        points,
        start: start,
        end: end,
        solarEvents: solar,
      ),
    );
  }

  String _number(double? value, String unit, {int decimals = 1}) =>
      value == null ? 'Нет данных' : '${value.toStringAsFixed(decimals)} $unit';

  String _solarTime(DateTime? value, WeatherLocation location) {
    if (value == null) return 'Нет данных';
    try {
      return DateFormat('HH:mm').format(
        tz.TZDateTime.from(value, tz.getLocation(location.timezone)),
      );
    } catch (_) {
      return DateFormat('HH:mm').format(value.toLocal());
    }
  }

  String _daylight(double? seconds) {
    if (seconds == null || !seconds.isFinite || seconds < 0) return 'Нет данных';
    final minutes = (seconds / 60).round();
    return '${minutes ~/ 60} ч ${minutes % 60} мин';
  }

  MoonPhasePoint? _moonPhase() {
    final start = widget.session.actualSleepStartedAt;
    final end = widget.session.actualSleepEndedAt;
    if (start == null || end == null || !end.isAfter(start)) return null;
    final midpoint = start.add(Duration(microseconds: end.difference(start).inMicroseconds ~/ 2));
    return MoonPhaseAnalytics.at(midpoint);
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 10),
      Flexible(child: Text(value, textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final moon = _moonPhase();
    final hasActualInterval = widget.session.actualSleepStartedAt != null &&
        widget.session.actualSleepEndedAt != null &&
        widget.session.actualSleepEndedAt!.isAfter(widget.session.actualSleepStartedAt!);
    return FutureBuilder<_NightWeatherData?>(
    future: _future,
    builder: (context, state) {
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Погода и солнечный цикл этой ночи',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (state.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator()
          else if (state.hasError)
            Text('Не удалось загрузить архив погоды: ${state.error}',
              style: const TextStyle(color: AppTheme.accentPink, fontSize: 12))
          else if (!hasActualInterval)
            const Text('Погодные и астрономические показатели не рассчитываются: источник не предоставил фактические начало и окончание сна.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
          else if (state.data == null)
            const Text('Выбери город в разделе «Анализ», чтобы получать историческую погоду. GPS не используется.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))
          else ...[
            Text(state.data!.location.label,
              style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
            const SizedBox(height: 8),
            if (state.data!.summary.sampleCount > 0) ...[
              _row('Почасовых точек в интервале', '${state.data!.summary.sampleCount}'),
              _row('Средняя температура', _number(state.data!.summary.averageTemperatureC, '°C')),
              _row('Средняя влажность', _number(state.data!.summary.averageHumidityPercent, '%', decimals: 0)),
              _row('Осадки за ночь', _number(state.data!.summary.totalPrecipitationMm, 'мм')),
              _row('Средняя скорость ветра', _number(state.data!.summary.averageWindKmh, 'км/ч')),
              _row('Среднее атмосферное давление', _number(state.data!.summary.averagePressureHpa, 'гПа')),
            ] else
              const Text('Архивные погодные измерения за эту ночь пока недоступны.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            const Divider(height: 18, color: AppTheme.surfaceLight),
            _row('Закат до начала сна',
              _solarTime(state.data!.summary.sunsetUtc, state.data!.location)),
            _row('Восход после пробуждения',
              _solarTime(state.data!.summary.sunriseUtc, state.data!.location)),
            _row('Длительность светового дня', _daylight(state.data!.summary.daylightDurationSeconds)),
            if (moon != null) ...[
              _row('Фаза Луны в середине сна', moon.label),
              _row('Расчётная освещённость Луны', MoonPhaseAnalytics.percent(moon.illumination)),
            ],
            const SizedBox(height: 6),
            const Text(
              'Источник: Open-Meteo Historical Weather API. Это архивная модель для выбранного города, а не измерение внутри спальни. Недостающие часы не интерполируются.',
              style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.4),
            ),
          ],
        ],
      ));
    },
  );
  }
}
