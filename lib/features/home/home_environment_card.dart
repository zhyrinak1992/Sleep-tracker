import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../data/sleep_database.dart';
import '../../data/yandex_smart_home_service.dart';
import '../analysis/moon_phase_analytics.dart';

class HomeEnvironmentCard extends StatefulWidget {
  const HomeEnvironmentCard({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<HomeEnvironmentCard> createState() => _HomeEnvironmentCardState();
}

class _HomeEnvironmentCardState extends State<HomeEnvironmentCard> {
  double? _outsideTemperature;
  double? _roomTemperature;
  double? _roomHumidity;
  String? _roomName;
  String _weatherStatus = 'Определяем местоположение…';
  String _roomStatus = 'Проверяем датчик Яндекса…';
  DateTime? _weatherUpdated;
  DateTime? _roomUpdated;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; });
    await Future.wait([_loadWeather(), _loadYandex()]);
    if (mounted) setState(() { _loading = false; });
  }

  Future<void> _loadWeather() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          !await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _weatherStatus = 'Разрешите геолокацию iPhone');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': position.latitude.toStringAsFixed(5),
        'longitude': position.longitude.toStringAsFixed(5),
        'current': 'temperature_2m',
        'temperature_unit': 'celsius',
        'timezone': 'auto',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final decoded = jsonDecode(response.body);
      final current = decoded is Map ? decoded['current'] : null;
      final value = current is Map ? current['temperature_2m'] : null;
      final measured = current is Map && current['time'] is String
          ? DateTime.tryParse(current['time'] as String) : null;
      if (value is! num || !value.toDouble().isFinite) throw const FormatException('Нет текущей температуры');
      if (mounted) setState(() {
        _outsideTemperature = value.toDouble();
        _weatherUpdated = measured ?? DateTime.now();
        _weatherStatus = 'По геолокации iPhone';
      });
    } catch (_) {
      if (mounted) setState(() => _weatherStatus = 'Погодные данные недоступны');
    }
  }

  Future<void> _loadYandex() async {
    try {
      final service = YandexSmartHomeService.instance;
      if (!await service.isConnected) {
        if (mounted) setState(() => _roomStatus = 'Яндекс не подключён');
        return;
      }
      final deviceId = await widget.database.getAppMetadata('yandex_selected_device_id');
      if (deviceId == null || deviceId.isEmpty) {
        if (mounted) setState(() => _roomStatus = 'Выберите датчик в настройках');
        return;
      }
      try {
        await service.refreshSelectedDevice(
          deviceId: deviceId,
          sessionId: (await widget.database.getOpenSession())?.id,
        );
      } catch (_) {
        // Keep showing the last real sample if the sensor is temporarily offline.
      }
      final rows = await widget.database.getClimateSamples(deviceId: deviceId);
      final temperature = rows.where((row) => row['metric_type'] == 'temperature').toList();
      final humidity = rows.where((row) => row['metric_type'] == 'humidity').toList();
      final latestRows = [...temperature, ...humidity];
      latestRows.sort((a, b) => DateTime.parse(b['measured_at'] as String)
          .compareTo(DateTime.parse(a['measured_at'] as String)));
      if (mounted) setState(() {
        if (temperature.isNotEmpty) {
          final row = temperature.last;
          _roomTemperature = (row['value'] as num).toDouble();
          _roomName = row['room_name'] as String? ?? row['device_name'] as String?;
        }
        if (humidity.isNotEmpty) _roomHumidity = (humidity.last['value'] as num).toDouble();
        _roomUpdated = latestRows.isEmpty ? null : DateTime.parse(latestRows.first['measured_at'] as String).toLocal();
        _roomStatus = latestRows.isEmpty ? 'Нет сохранённых показаний датчика' : 'Данные датчика Яндекса';
      });
    } catch (_) {
      if (mounted) setState(() => _roomStatus = 'Показания Яндекса недоступны');
    }
  }

  String _updated(DateTime? value) => value == null
      ? 'Нет времени измерения'
      : 'Обновлено в ${TimeOfDay.fromDateTime(value).format(context)}';

  Widget _metric(String label, String value, IconData icon) => Expanded(
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 19, color: const Color(0xFFE8C7F6)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Color(0xFFC8BEDF), fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final moon = MoonPhaseAnalytics.at(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF211B43),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF9F80C8).withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.nightlight_round, color: Color(0xFFFFD8A8), size: 19),
          const SizedBox(width: 8),
          const Text('СЕЙЧАС ВОКРУГ ВАС', style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: const Color(0xFFE8C7F6),
            visualDensity: VisualDensity.compact,
            tooltip: 'Обновить показатели',
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _metric('Лунная фаза', moon.label, Icons.dark_mode_outlined),
          _metric('На улице', _outsideTemperature == null ? '—' : '${_outsideTemperature!.toStringAsFixed(1)} °C', Icons.thermostat),
        ]),
        const SizedBox(height: 7),
        Text(_weatherStatus + (_weatherUpdated == null ? '' : ' · ${_updated(_weatherUpdated)}'),
          style: const TextStyle(color: Color(0xFFAAA0C5), fontSize: 10)),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Color(0x334F4770))),
        Row(children: [
          _metric('В комнате', _roomTemperature == null ? '—' : '${_roomTemperature!.toStringAsFixed(1)} °C', Icons.thermostat_auto),
          _metric('Влажность', _roomHumidity == null ? '—' : '${_roomHumidity!.toStringAsFixed(0)} %', Icons.water_drop_outlined),
        ]),
        if (_roomName != null && _roomName!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(_roomName!, style: const TextStyle(color: Color(0xFFAAA0C5), fontSize: 10)),
        ],
        const SizedBox(height: 3),
        Text(_roomStatus + (_roomUpdated == null ? '' : ' · ${_updated(_roomUpdated)}'),
          style: const TextStyle(color: Color(0xFFAAA0C5), fontSize: 10)),
      ]),
    );
  }
}
