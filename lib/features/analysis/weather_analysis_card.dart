import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/sleep_database.dart';
import '../../data/weather_service.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'weather_sleep_analysis.dart';

class _WeatherNight {
  const _WeatherNight({required this.summary, required this.sleepMinutes, required this.startedAt});
  final WeatherNightSummary summary;
  final double sleepMinutes;
  final DateTime startedAt;
}

class _WeatherAnalysisData {
  const _WeatherAnalysisData({
    required this.location,
    required this.nights,
  });
  final WeatherLocation? location;
  final List<_WeatherNight> nights;
}

class WeatherAnalysisCard extends StatefulWidget {
  const WeatherAnalysisCard({
    super.key,
    required this.database,
    required this.sessions,
  });

  final SleepDatabase database;
  final List<SleepSession> sessions;

  @override
  State<WeatherAnalysisCard> createState() => _WeatherAnalysisCardState();
}

class _WeatherAnalysisCardState extends State<WeatherAnalysisCard> {
  static bool _timeZonesInitialized = false;
  late Future<_WeatherAnalysisData> _future;

  String get _sessionSignature =>
      widget.sessions.map((session) => session.id).join('|');

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
  void didUpdateWidget(covariant WeatherAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSignature = oldWidget.sessions.map((session) => session.id).join('|');
    if (oldSignature != _sessionSignature) {
      _future = _load();
    }
  }

  Future<_WeatherAnalysisData> _load() async {
    final rawLocation = await widget.database.getAppMetadata(WeatherService.locationStorageKey);
    if (rawLocation == null || rawLocation.isEmpty) {
      return const _WeatherAnalysisData(location: null, nights: []);
    }
    final decoded = jsonDecode(rawLocation);
    if (decoded is! Map) {
      throw const FormatException('Сохранённое местоположение повреждено. Данные не перезаписаны.');
    }
    final location = WeatherLocation.fromJson(decoded);
    final valid = widget.sessions.map((session) {
      final start = session.actualSleepStartedAt;
      final end = session.actualSleepEndedAt;
      if (start == null || end == null || !end.isAfter(start)) return null;
      return (session: session, start: start, end: end);
    }).whereType<({SleepSession session, DateTime start, DateTime end})>().toList();
    if (valid.isEmpty) {
      return _WeatherAnalysisData(location: location, nights: const []);
    }
    final start = valid.map((item) => item.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final end = valid.map((item) => item.end).reduce((a, b) => a.isAfter(b) ? a : b);
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
    final solarEvents = await solarFuture;
    final nights = valid.map((item) => _WeatherNight(
      summary: WeatherNightSummary.summarize(
        points,
        start: item.start,
        end: item.end,
        solarEvents: solarEvents,
      ),
      sleepMinutes: item.end.difference(item.start).inMinutes.toDouble(),
      startedAt: item.start,
    )).toList();
    return _WeatherAnalysisData(location: location, nights: nights);
  }

  Future<void> _chooseLocation() async {
    final controller = TextEditingController();
    var loading = false;
    var searched = false;
    String? error;
    List<WeatherLocation> results = const [];
    final selected = await showDialog<WeatherLocation>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Выбрать местоположение'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Укажи город или населённый пункт, для которого нужно сопоставлять историческую погоду со сном. Геолокация телефона не запрашивается.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Город, страна',
                    hintText: 'Например, Berlin',
                  ),
                  onSubmitted: (_) async {
                    setDialogState(() {
                      loading = true;
                      error = null;
                      searched = true;
                    });
                    try {
                      final found = await WeatherService.instance.searchLocations(controller.text);
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        results = found;
                        loading = false;
                      });
                    } catch (exception) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        error = exception.toString();
                        loading = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: loading ? null : () async {
                      setDialogState(() {
                        loading = true;
                        error = null;
                        searched = true;
                      });
                      try {
                        final found = await WeatherService.instance.searchLocations(controller.text);
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          results = found;
                          loading = false;
                        });
                      } catch (exception) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          error = exception.toString();
                          loading = false;
                        });
                      }
                    },
                    child: const Text('Найти'),
                  ),
                ),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppTheme.accentPink, fontSize: 11)),
                if (searched && !loading && error == null && results.isEmpty)
                  const Text('Ничего не найдено. Уточни название города или страну.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (results.isNotEmpty)
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: results.map((location) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(location.name),
                        subtitle: Text([
                          if (location.admin1.isNotEmpty) location.admin1,
                          if (location.country.isNotEmpty) location.country,
                        ].join(', ')),
                        onTap: () => Navigator.pop(dialogContext, location),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (selected == null || !mounted) return;
    await widget.database.setAppMetadata(
      WeatherService.locationStorageKey,
      jsonEncode(selected.toJson()),
    );
    setState(() => _future = _load());
  }

  String _number(double? value, String unit, {int decimals = 1}) =>
      value == null ? 'Нет данных' : '${value.toStringAsFixed(decimals)} $unit';

  String _duration(double minutes) {
    final rounded = minutes.round();
    return '${rounded ~/ 60} ч ${rounded % 60} мин';
  }

  String _daylight(double? seconds) {
    if (seconds == null || !seconds.isFinite || seconds < 0) return '—';
    final minutes = (seconds / 60).round();
    return '${minutes ~/ 60} ч ${minutes % 60} мин';
  }

  String _solarTime(DateTime? value, WeatherLocation location) {
    if (value == null) return '—';
    try {
      final local = tz.TZDateTime.from(value, tz.getLocation(location.timezone));
      return DateFormat('HH:mm').format(local);
    } catch (_) {
      return DateFormat('HH:mm').format(value.toLocal());
    }
  }

  double? _average(Iterable<double?> values) {
    final present = values.whereType<double>().toList();
    if (present.isEmpty) return null;
    return present.reduce((a, b) => a + b) / present.length;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_WeatherAnalysisData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: LinearProgressIndicator());
      }
      if (snapshot.hasError) {
        return SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Погода и сон', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('Не удалось загрузить архив погоды: ${snapshot.error}',
              style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
            Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Повторить'))),
          ],
        ));
      }
      final data = snapshot.data ?? const _WeatherAnalysisData(location: null, nights: []);
      final location = data.location;
      if (location == null) {
        return SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Погода и сон', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            const Text('Выбери город вручную, чтобы сопоставлять историческую погоду с ночными сессиями. Геолокация не используется.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
            Align(alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: _chooseLocation, icon: const Icon(Icons.location_on_outlined), label: const Text('Выбрать город'))),
          ],
        ));
      }
      final available = data.nights.where((night) => night.summary.sampleCount > 0).toList();
      final solarRows = data.nights.where((night) => night.summary.sunriseUtc != null || night.summary.sunsetUtc != null).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final temperatureNights = data.nights.where((night) => night.summary.averageTemperatureC != null).toList();
      final comparison = WeatherSleepComparison.fromSamples(temperatureNights.map((night) =>
        WeatherSleepSample(
          averageTemperatureC: night.summary.averageTemperatureC!,
          sleepMinutes: night.sleepMinutes,
        )));
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Погода и сон', style: TextStyle(fontWeight: FontWeight.w600))),
            TextButton(onPressed: _chooseLocation, child: const Text('Изменить город')),
          ]),
          Text(location.label, style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Исторические почасовые данные для выбранного места. Сопоставление выполняется по времени каждой завершённой ночи; это погодная оценка для координат города, а не измерение внутри спальни.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
          const SizedBox(height: 10),
          Text('Ночей с погодными данными: ${available.length} из ${data.nights.length}',
            style: const TextStyle(color: AppTheme.teal, fontSize: 12, fontWeight: FontWeight.w600)),
          const Divider(height: 18, color: AppTheme.surfaceLight),
          _WeatherMetricRow(label: 'Средняя температура', value: _number(_average(available.map((n) => n.summary.averageTemperatureC)), '°C')),
          const SizedBox(height: 6),
          _WeatherMetricRow(label: 'Средняя влажность', value: _number(_average(available.map((n) => n.summary.averageHumidityPercent)), '%')),
          const SizedBox(height: 6),
          _WeatherMetricRow(label: 'Осадки за ночь (в среднем)', value: _number(_average(available.map((n) => n.summary.totalPrecipitationMm)), 'мм')),
          const SizedBox(height: 6),
          _WeatherMetricRow(label: 'Средняя скорость ветра', value: _number(_average(available.map((n) => n.summary.averageWindKmh)), 'км/ч')),
          const SizedBox(height: 6),
          _WeatherMetricRow(label: 'Атмосферное давление', value: _number(_average(available.map((n) => n.summary.averagePressureHpa)), 'гПа')),
          const Divider(height: 18, color: AppTheme.surfaceLight),
          const Text('Восход и закат по ночам', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          if (solarRows.isEmpty)
            const Text('Солнечные события за выбранные даты недоступны.', style: TextStyle(color: AppTheme.muted, fontSize: 11))
          else
            ...solarRows.take(7).map((night) => _WeatherMetricRow(
              label: DateFormat('d MMM', 'ru').format(night.startedAt),
              value: 'Закат ${_solarTime(night.summary.sunsetUtc, location)} · восход ${_solarTime(night.summary.sunriseUtc, location)} · день ${_daylight(night.summary.daylightDurationSeconds)}',
            )),
          const Divider(height: 18, color: AppTheme.surfaceLight),
          const Text('Продолжительность сна при разной температуре',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 7),
          if (comparison == null)
            const Text('Для сравнения прохладных и тёплых ночей нужны минимум 4 ночи с температурными данными.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4))
          else ...[
            _WeatherMetricRow(
              label: 'Более прохладные (${comparison.coolerNights.nights} ноч.)',
              value: _duration(comparison.coolerNights.averageSleepMinutes),
            ),
            const SizedBox(height: 5),
            _WeatherMetricRow(
              label: 'Более тёплые (${comparison.warmerNights.nights} ноч.)',
              value: _duration(comparison.warmerNights.averageSleepMinutes),
            ),
            const SizedBox(height: 7),
            const Text('Группы делятся по медиане средней температуры ночи в выбранном периоде. Наблюдаемая разница не доказывает причинное влияние погоды на сон.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
          ],
          const SizedBox(height: 8),
          const Text('Источник: Open-Meteo Historical Weather API (архивная реанализная оценка); названия мест — GeoNames. Местоположение выбирается вручную. Weather data by Open-Meteo.com.',
            style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35)),
        ],
      ));
    },
  );
}

class _WeatherMetricRow extends StatelessWidget {
  const _WeatherMetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Text(value, textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );
}
