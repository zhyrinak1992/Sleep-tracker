import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/sleep_session.dart';
import 'sleep_database.dart';

class EnvironmentLocation {
  const EnvironmentLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.country,
    this.admin1,
  });

  final String name;
  final double latitude;
  final double longitude;
  final String country;
  final String? admin1;

  String get displayName => [
    name,
    if (admin1 != null && admin1!.isNotEmpty && admin1 != name) admin1!,
    country,
  ].join(', ');

  Map<String, Object?> toMap() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'country': country,
    'admin1': admin1,
  };

  factory EnvironmentLocation.fromMap(Map value) {
    final name = value['name'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final country = value['country'];
    if (name is! String || latitude is! num || longitude is! num || country is! String) {
      throw const FormatException('Некорректные координаты выбранного города.');
    }
    if (!latitude.toDouble().isFinite || !longitude.toDouble().isFinite ||
        latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw const FormatException('Координаты города выходят за допустимые пределы.');
    }
    return EnvironmentLocation(
      name: name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      country: country,
      admin1: value['admin1'] as String?,
    );
  }
}

class NightEnvironmentSummary {
  const NightEnvironmentSummary({
    required this.locationName,
    required this.sampleCount,
    required this.utcOffsetSeconds,
    this.temperatureMin,
    this.temperatureAverage,
    this.temperatureMax,
    this.humidityAverage,
    this.precipitationMm,
    this.windMaxKmh,
    this.weatherCode,
    this.sunriseEpoch,
    this.sunsetEpoch,
  });

  final String locationName;
  final int sampleCount;
  final int utcOffsetSeconds;
  final double? temperatureMin;
  final double? temperatureAverage;
  final double? temperatureMax;
  final double? humidityAverage;
  final double? precipitationMm;
  final double? windMaxKmh;
  final int? weatherCode;
  final int? sunriseEpoch;
  final int? sunsetEpoch;

  bool get hasWeather => sampleCount > 0 &&
      (temperatureAverage != null || humidityAverage != null ||
       precipitationMm != null || windMaxKmh != null || weatherCode != null);

  DateTime? get sunriseLocalWallTime => sunriseEpoch == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (sunriseEpoch! + utcOffsetSeconds) * 1000, isUtc: true);
  DateTime? get sunsetLocalWallTime => sunsetEpoch == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (sunsetEpoch! + utcOffsetSeconds) * 1000, isUtc: true);

  Map<String, Object?> toMap() => {
    'locationName': locationName,
    'sampleCount': sampleCount,
    'utcOffsetSeconds': utcOffsetSeconds,
    'temperatureMin': temperatureMin,
    'temperatureAverage': temperatureAverage,
    'temperatureMax': temperatureMax,
    'humidityAverage': humidityAverage,
    'precipitationMm': precipitationMm,
    'windMaxKmh': windMaxKmh,
    'weatherCode': weatherCode,
    'sunriseEpoch': sunriseEpoch,
    'sunsetEpoch': sunsetEpoch,
  };

  factory NightEnvironmentSummary.fromMap(Map value) {
    num? number(String key) => value[key] is num ? value[key] as num : null;
    return NightEnvironmentSummary(
      locationName: value['locationName'] as String? ?? '',
      sampleCount: (number('sampleCount') ?? 0).toInt(),
      utcOffsetSeconds: (number('utcOffsetSeconds') ?? 0).toInt(),
      temperatureMin: number('temperatureMin')?.toDouble(),
      temperatureAverage: number('temperatureAverage')?.toDouble(),
      temperatureMax: number('temperatureMax')?.toDouble(),
      humidityAverage: number('humidityAverage')?.toDouble(),
      precipitationMm: number('precipitationMm')?.toDouble(),
      windMaxKmh: number('windMaxKmh')?.toDouble(),
      weatherCode: number('weatherCode')?.toInt(),
      sunriseEpoch: number('sunriseEpoch')?.toInt(),
      sunsetEpoch: number('sunsetEpoch')?.toInt(),
    );
  }
}

class NightEnvironmentService {
  NightEnvironmentService._();
  static final NightEnvironmentService instance = NightEnvironmentService._();

  static const locationKey = 'sleep_tracker_environment_location_v1';
  static const _cachePrefix = 'sleep_tracker_night_environment_v1_';
  final http.Client _client = http.Client();

  Future<List<EnvironmentLocation>> searchLocations(String query) async {
    final value = query.trim();
    if (value.length < 2) return const [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': value,
      'count': '8',
      'language': 'ru',
      'format': 'json',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Сервис поиска городов вернул HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['results'] is! List) return const [];
    return (decoded['results'] as List).whereType<Map>().map((row) {
      final latitude = row['latitude'];
      final longitude = row['longitude'];
      if (latitude is! num || longitude is! num) return null;
      return EnvironmentLocation(
        name: row['name'] as String? ?? 'Без названия',
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        country: row['country'] as String? ?? '',
        admin1: row['admin1'] as String?,
      );
    }).whereType<EnvironmentLocation>().toList();
  }

  Future<EnvironmentLocation?> loadLocation({SleepDatabase? database}) async {
    final raw = await (database ?? SleepDatabase.instance).getAppMetadata(locationKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Настройка города повреждена.');
    return EnvironmentLocation.fromMap(decoded);
  }

  Future<void> saveLocation(EnvironmentLocation location, {SleepDatabase? database}) async {
    await (database ?? SleepDatabase.instance).setAppMetadata(
      locationKey, jsonEncode(location.toMap()));
  }

  Future<void> clearLocation({SleepDatabase? database}) async {
    await (database ?? SleepDatabase.instance).setAppMetadata(locationKey, '');
  }

  Future<Map<String, NightEnvironmentSummary>> loadForSessions(
    List<SleepSession> sessions, {
    SleepDatabase? database,
  }) async {
    final db = database ?? SleepDatabase.instance;
    final location = await loadLocation(database: db);
    if (location == null) return const {};
    final valid = sessions.where((session) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      return end != null && end.isAfter(start);
    }).toList();
    if (valid.isEmpty) return const {};

    final locationId = '${location.latitude.toStringAsFixed(3)}_${location.longitude.toStringAsFixed(3)}';
    final result = <String, NightEnvironmentSummary>{};
    final missing = <SleepSession>[];
    final now = DateTime.now().toUtc();

    for (final session in valid) {
      final key = '$_cachePrefix${session.id}_$locationId';
      final raw = await db.getAppMetadata(key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final cache = jsonDecode(raw);
          if (cache is Map && cache['fetchedAt'] is String) {
            final fetchedAt = DateTime.tryParse(cache['fetchedAt'] as String);
            final data = cache['summary'];
            if (fetchedAt != null && data is Map) {
              final summary = NightEnvironmentSummary.fromMap(data);
              final ttl = summary.hasWeather ? const Duration(days: 30) : const Duration(hours: 12);
              if (now.difference(fetchedAt.toUtc()) < ttl) {
                result[session.id] = summary;
                continue;
              }
            }
          }
        } catch (_) {
          // Invalid cache is ignored and refreshed from the provider.
        }
      }
      missing.add(session);
    }
    if (missing.isEmpty) return result;

    final starts = missing.map((session) =>
      (session.actualSleepStartedAt ?? session.startedAt).toUtc()).toList();
    final ends = missing.map((session) =>
      (session.actualSleepEndedAt ?? session.endedAt!).toUtc()).toList();
    final first = starts.reduce((a, b) => a.isBefore(b) ? a : b).subtract(const Duration(days: 2));
    final last = ends.reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(days: 2));
    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'start_date': _date(first),
      'end_date': _date(last),
      'hourly': 'temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,weather_code',
      'daily': 'sunrise,sunset',
      'timezone': 'auto',
      'timeformat': 'unixtime',
      'wind_speed_unit': 'kmh',
      'precipitation_unit': 'mm',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('Архив погоды вернул HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['hourly'] is! Map) {
      throw const FormatException('Сервис погоды вернул данные в неожиданном формате.');
    }
    final hourly = decoded['hourly'] as Map;
    final times = _intList(hourly['time']);
    final temperatures = _numList(hourly['temperature_2m']);
    final humidity = _numList(hourly['relative_humidity_2m']);
    final precipitation = _numList(hourly['precipitation']);
    final wind = _numList(hourly['wind_speed_10m']);
    final codes = _numList(hourly['weather_code']);
    final daily = decoded['daily'] is Map ? decoded['daily'] as Map : const {};
    final sunrises = _intList(daily['sunrise']);
    final sunsets = _intList(daily['sunset']);
    final offset = (decoded['utc_offset_seconds'] as num?)?.toInt() ?? 0;

    for (final session in missing) {
      final start = (session.actualSleepStartedAt ?? session.startedAt).toUtc().millisecondsSinceEpoch ~/ 1000;
      final end = (session.actualSleepEndedAt ?? session.endedAt!).toUtc().millisecondsSinceEpoch ~/ 1000;
      final indices = <int>[
        for (var i = 0; i < times.length; i++)
          if (times[i] >= start && times[i] < end) i,
      ];
      final temp = _selected(temperatures, indices);
      final humid = _selected(humidity, indices);
      final rain = _selected(precipitation, indices);
      final winds = _selected(wind, indices);
      final weatherCodes = _selected(codes, indices).map((x) => x.round()).toList();
      final summary = NightEnvironmentSummary(
        locationName: location.displayName,
        sampleCount: indices.length,
        utcOffsetSeconds: offset,
        temperatureMin: temp.isEmpty ? null : temp.reduce((a, b) => a < b ? a : b),
        temperatureAverage: temp.isEmpty ? null : temp.reduce((a, b) => a + b) / temp.length,
        temperatureMax: temp.isEmpty ? null : temp.reduce((a, b) => a > b ? a : b),
        humidityAverage: humid.isEmpty ? null : humid.reduce((a, b) => a + b) / humid.length,
        precipitationMm: rain.isEmpty ? null : rain.fold<double>(0, (a, b) => a + b),
        windMaxKmh: winds.isEmpty ? null : winds.reduce((a, b) => a > b ? a : b),
        weatherCode: _mode(weatherCodes),
        sunriseEpoch: _nearest(sunrises, end, true),
        sunsetEpoch: _nearest(sunsets, start, false),
      );
      result[session.id] = summary;
      await db.setAppMetadata(
        '$_cachePrefix${session.id}_$locationId',
        jsonEncode({
          'fetchedAt': now.toIso8601String(),
          'summary': summary.toMap(),
        }),
      );
    }
    return result;
  }

  static List<int> _intList(dynamic value) => value is List
      ? value.whereType<num>().map((item) => item.toInt()).toList()
      : const [];

  static List<double?> _numList(dynamic value) => value is List
      ? value.map((item) => item is num && item.toDouble().isFinite ? item.toDouble() : null).toList()
      : const [];

  static List<double> _selected(List<double?> values, List<int> indices) => [
    for (final index in indices)
      if (index < values.length && values[index] != null) values[index]!,
  ];

  static int? _mode(List<int> values) {
    if (values.isEmpty) return null;
    final counts = <int, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static int? _nearest(List<int> values, int reference, bool after) {
    final candidates = values.where((value) => after ? value >= reference : value <= reference).toList();
    if (candidates.isEmpty) return null;
    return after
      ? candidates.reduce((a, b) => a < b ? a : b)
      : candidates.reduce((a, b) => a > b ? a : b);
  }

  static String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
