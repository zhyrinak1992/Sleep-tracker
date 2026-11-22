import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/night_environment_service.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class _EnvironmentResult {
  const _EnvironmentResult({required this.location, required this.summaries});
  final EnvironmentLocation? location;
  final Map<String, NightEnvironmentSummary> summaries;
}

class NightEnvironmentAnalysisCard extends StatefulWidget {
  const NightEnvironmentAnalysisCard({
    super.key,
    required this.database,
    required this.sessions,
  });
  final SleepDatabase database;
  final List<SleepSession> sessions;

  @override
  State<NightEnvironmentAnalysisCard> createState() => _NightEnvironmentAnalysisCardState();
}

class _NightEnvironmentAnalysisCardState extends State<NightEnvironmentAnalysisCard> {
  late Future<_EnvironmentResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant NightEnvironmentAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) _future = _load();
  }

  Future<_EnvironmentResult> _load() async {
    final location = await NightEnvironmentService.instance.loadLocation(database: widget.database);
    if (location == null) return const _EnvironmentResult(location: null, summaries: {});
    final summaries = await NightEnvironmentService.instance.loadForSessions(
      widget.sessions,
      database: widget.database,
    );
    return _EnvironmentResult(location: location, summaries: summaries);
  }

  String _weather(int? code) {
    switch (code) {
      case 0: return 'Ясно';
      case 1: return 'Преимущественно ясно';
      case 2: return 'Переменная облачность';
      case 3: return 'Пасмурно';
      case 45: case 48: return 'Туман';
      case 51: case 53: case 55: return 'Морось';
      case 56: case 57: return 'Переохлаждённая морось';
      case 61: case 63: case 65: return 'Дождь';
      case 66: case 67: return 'Переохлаждённый дождь';
      case 71: case 73: case 75: case 77: return 'Снег';
      case 80: case 81: case 82: return 'Ливневый дождь';
      case 85: case 86: return 'Снегопад';
      case 95: case 96: case 99: return 'Гроза';
      default: return 'Код погоды ${code ?? 'неизвестен'}';
    }
  }

  String _time(DateTime? value) =>
      value == null ? 'Нет данных' : DateFormat('HH:mm').format(value);

  String _temp(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} °C';

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<_EnvironmentResult>(
    future: _future,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: LinearProgressIndicator());
      }
      if (state.hasError) {
        return SectionCard(child: Text('Не удалось получить архив погоды: ${state.error}',
          style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)));
      }
      final result = state.data!;
      if (result.location == null) {
        return const SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Погода и солнечный цикл', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('Сначала выбери город в настройках приложения. Точное местоположение не запрашивается.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
          ],
        ));
      }
      final rows = widget.sessions
        .where((session) => result.summaries.containsKey(session.id))
        .map((session) => MapEntry(session, result.summaries[session.id]!))
        .toList()
        ..sort((a, b) => b.key.startedAt.compareTo(a.key.startedAt));
      final available = rows.where((row) => row.value.hasWeather).length;
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Погода и солнечный цикл',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(result.location!.displayName,
            style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Ночей с архивными погодными измерениями: $available из ${rows.length}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          const Divider(height: 18, color: AppTheme.surfaceLight),
          if (rows.isEmpty)
            const Text('В выбранном периоде нет завершённых ночей.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12))
          else
            ...rows.take(7).map((row) {
              final session = row.key;
              final data = row.value;
              final date = DateFormat('d MMM', 'ru').format(session.startedAt);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(date, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  if (data.hasWeather) ...[
                    _row('Условия', _weather(data.weatherCode)),
                    _row('Температура мин./сред./макс.',
                      '${_temp(data.temperatureMin)} / ${_temp(data.temperatureAverage)} / ${_temp(data.temperatureMax)}'),
                    _row('Влажность в среднем',
                      data.humidityAverage == null ? '—' : '${data.humidityAverage!.round()} %'),
                    _row('Осадки за ночь',
                      data.precipitationMm == null ? '—' : '${data.precipitationMm!.toStringAsFixed(1)} мм'),
                    _row('Максимальный ветер',
                      data.windMaxKmh == null ? '—' : '${data.windMaxKmh!.toStringAsFixed(1)} км/ч'),
                    _row('Часовых точек', '${data.sampleCount}'),
                  ] else
                    const Text('Архив погоды за эту ночь пока недоступен.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 11)),
                  _row('Закат до сна', _time(data.sunsetLocalWallTime)),
                  _row('Восход после сна', _time(data.sunriseLocalWallTime)),
                ]),
              );
            }),
          const Text(
            'Погодные значения рассчитаны по часовому архиву Open-Meteo для выбранного города, а не по датчику внутри спальни. Недоступные часы не восстанавливаются.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 4),
          const Text('Источник данных: Open-Meteo · open-meteo.com',
            style: TextStyle(color: AppTheme.muted, fontSize: 10)),
        ],
      ));
    },
  );
}
