import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sleep_database.dart';

DateTime _parseWeatherUtc(String value) {
  final hasOffset = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value);
  if (hasOffset) return DateTime.parse(value).toUtc();
  final parsed = DateTime.parse(value);
  // The archive request explicitly asks for timezone=UTC. Open-Meteo may
  // serialize UTC hours without a trailing Z, so treat such values as UTC.
  return DateTime.utc(
    parsed.year, parsed.month, parsed.day,
    parsed.hour, parsed.minute, parsed.second, parsed.millisecond,
  );
}

class WeatherLocation {
  const WeatherLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.admin1 = '',
    this.country = '',
    this.timezone = 'UTC',
  });

  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final String admin1;
  final String country;
  final String timezone;

  String get label {
    final parts = <String>[name];
    if (admin1.isNotEmpty && admin1 != name) parts.add(admin1);
    if (country.isNotEmpty) parts.add(country);
    return parts.join(', ');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'admin1': admin1,
    'country': country,
    'timezone': timezone,
  };

  factory WeatherLocation.fromJson(Map value) {
    final id = value['id'];
    final name = value['name'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (id is! num || name is! String || latitude is! num || longitude is! num) {
      throw const FormatException('Некорректно сохранено местоположение для погодной аналитики.');
    }
    return WeatherLocation(
      id: id.toInt(),
      name: name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      admin1: value['admin1'] is String ? value['admin1'] as String : '',
      country: value['country'] is String ? value['country'] as String : '',
      timezone: value['timezone'] is String ? value['timezone'] as String : 'UTC',
    );
  }
}

class HourlyWeatherPoint {
  const HourlyWeatherPoint({
    required this.time,
    this.temperatureC,
    this.humidityPercent,
    this.precipitationMm,
    this.windKmh,
    this.pressureHpa,
  });

  final DateTime time;
  final double? temperatureC;
  final double? humidityPercent;
  final double? precipitationMm;
  final double? windKmh;
  final double? pressureHpa;

  Map<String, Object?> toJson() => {
    'time': time.toUtc().toIso8601String(),
    'temperatureC': temperatureC,
    'humidityPercent': humidityPercent,
    'precipitationMm': precipitationMm,
    'windKmh': windKmh,
    'pressureHpa': pressureHpa,
  };

  factory HourlyWeatherPoint.fromJson(Map value) {
    final time = value['time'];
    if (time is! String) throw const FormatException('В погодном кэше отсутствует время измерения.');
    double? number(String key) {
      final raw = value[key];
      if (raw is! num) return null;
      final result = raw.toDouble();
      return result.isFinite ? result : null;
    }
    return HourlyWeatherPoint(
      time: _parseWeatherUtc(time),
      temperatureC: number('temperatureC'),
      humidityPercent: number('humidityPercent'),
      precipitationMm: number('precipitationMm'),
      windKmh: number('windKmh'),
      pressureHpa: number('pressureHpa'),
    );
  }
}

class SolarEvent {
  const SolarEvent({required this.date, this.sunriseUtc, this.sunsetUtc});

  final String date;
  final DateTime? sunriseUtc;
  final DateTime? sunsetUtc;

  Map<String, Object?> toJson() => {
    'date': date,
    'sunriseUtc': sunriseUtc?.toUtc().toIso8601String(),
    'sunsetUtc': sunsetUtc?.toUtc().toIso8601String(),
  };

  factory SolarEvent.fromJson(Map value) {
    final date = value['date'];
    if (date is! String) throw const FormatException('В солнечном архиве отсутствует дата.');
    DateTime? parse(String key) {
      final raw = value[key];
      if (raw is! String) return null;
      return _parseWeatherUtc(raw);
    }
    return SolarEvent(date: date, sunriseUtc: parse('sunriseUtc'), sunsetUtc: parse('sunsetUtc'));
  }
}

class WeatherNightSummary {
  const WeatherNightSummary({
    required this.sampleCount,
    this.averageTemperatureC,
    this.averageHumidityPercent,
    this.totalPrecipitationMm,
    this.averageWindKmh,
    this.averagePressureHpa,
    this.sunriseUtc,
    this.sunsetUtc,
  });

  final int sampleCount;
  final double? averageTemperatureC;
  final double? averageHumidityPercent;
  final double? totalPrecipitationMm;
  final double? averageWindKmh;
  final double? averagePressureHpa;
  final DateTime? sunriseUtc;
  final DateTime? sunsetUtc;

  static WeatherNightSummary summarize(
    Iterable<HourlyWeatherPoint> points, {
    required DateTime start,
    required DateTime end,
    Iterable<SolarEvent> solarEvents = const [],
  }) {
    final selected = points.where((point) {
      final time = point.time.toUtc();
      return !time.isBefore(start.toUtc()) && time.isBefore(end.toUtc());
    }).toList();

    List<double> values(double? Function(HourlyWeatherPoint) pick) =>
        selected.map(pick).whereType<double>().where((value) => value.isFinite).toList();
    double? average(List<double> data) => data.isEmpty
        ? null
        : data.reduce((a, b) => a + b) / data.length;
    final precipitation = values((point) => point.precipitationMm);
    return WeatherNightSummary(
      sampleCount: selected.length,
      averageTemperatureC: average(values((point) => point.temperatureC)),
      averageHumidityPercent: average(values((point) => point.humidityPercent)),
      totalPrecipitationMm: precipitation.isEmpty
          ? null
          : precipitation.reduce((a, b) => a + b),
      averageWindKmh: average(values((point) => point.windKmh)),
      averagePressureHpa: average(values((point) => point.pressureHpa)),
      sunsetUtc: _nearestSolarEvent(
        solarEvents.map((event) => event.sunsetUtc).whereType<DateTime>(),
        start.toUtc(),
        before: true,
      ),
      sunriseUtc: _nearestSolarEvent(
        solarEvents.map((event) => event.sunriseUtc).whereType<DateTime>(),
        end.toUtc(),
        before: false,
      ),
    );
  }
}

class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const locationStorageKey = 'sleep_tracker_weather_location_v1';
  static const _cachePrefix = 'sleep_tracker_weather_cache_v1_';

  Future<List<WeatherLocation>> searchLocations(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': trimmed,
      'count': '8',
      'language': 'ru',
      'format': 'json',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Сервис поиска городов ответил кодом ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['results'] is! List) return const [];
    return (decoded['results'] as List)
        .whereType<Map>()
        .map(WeatherLocation.fromJson)
        .toList();
  }

  static DateTime? _nearestSolarEvent(
    Iterable<DateTime> events,
    DateTime reference, {
    required bool before,
  }) {
    final candidates = events.map((event) => event.toUtc()).where((event) =>
      before ? !event.isAfter(reference) : !event.isBefore(reference)).toList();
    if (candidates.isEmpty) return null;
    return before
      ? candidates.reduce((a, b) => a.isAfter(b) ? a : b)
      : candidates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<List<HourlyWeatherPoint>> loadHistoricalWeather({
    required SleepDatabase database,
    required WeatherLocation location,
    required DateTime start,
    required DateTime end,
  }) async {
    final startUtc = start.toUtc();
    final endUtc = end.toUtc();
    final startDate = _date(startUtc);
    final endDate = _date(endUtc);
    final cacheKey = '$_cachePrefix${location.id}';
    final cachedRaw = await database.getAppMetadata(cacheKey);
    Map<String, dynamic>? cached;
    List<HourlyWeatherPoint> cachedPoints = const [];
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      final decoded = jsonDecode(cachedRaw);
      if (decoded is! Map) {
        throw const FormatException('Кэш погоды повреждён. Сохранённые данные не перезаписаны.');
      }
      cached = Map<String, dynamic>.from(decoded);
      final rawPoints = cached['points'];
      if (rawPoints is! List) {
        throw const FormatException('В кэше погоды отсутствует список измерений. Сохранённые данные не перезаписаны.');
      }
      cachedPoints = rawPoints.whereType<Map>().map(HourlyWeatherPoint.fromJson).toList();
      final cachedStart = cached['startDate'];
      final cachedEnd = cached['endDate'];
      final dataEndRaw = cached['dataEnd'];
      final dataEnd = dataEndRaw is String ? DateTime.tryParse(dataEndRaw) : null;
      if (cachedStart is String && cachedEnd is String && dataEnd != null &&
          cachedStart.compareTo(startDate) <= 0 && cachedEnd.compareTo(endDate) >= 0 &&
          !dataEnd.isBefore(endUtc.subtract(const Duration(hours: 2)))) {
        return cachedPoints;
      }
    }

    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': location.latitude.toStringAsFixed(5),
      'longitude': location.longitude.toStringAsFixed(5),
      'start_date': startDate,
      'end_date': endDate,
      'hourly': 'temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,pressure_msl',
      'timezone': 'UTC',
      'timeformat': 'iso8601',
    });
    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 30));
    } catch (_) {
      if (cachedPoints.isNotEmpty) return cachedPoints;
      rethrow;
    }
    if (response.statusCode != 200) {
      if (cachedPoints.isNotEmpty) return cachedPoints;
      throw Exception('Архив погоды ответил кодом ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['hourly'] is! Map) {
      if (cachedPoints.isNotEmpty) return cachedPoints;
      throw const FormatException('Сервис не вернул почасовые погодные данные.');
    }
    final hourly = decoded['hourly'] as Map;
    final times = hourly['time'];
    if (times is! List) {
      if (cachedPoints.isNotEmpty) return cachedPoints;
      throw const FormatException('В ответе архива отсутствует временная шкала.');
    }
    List<dynamic> series(String key) =>
        hourly[key] is List ? hourly[key] as List : const [];
    double? at(List<dynamic> values, int index) {
      if (index >= values.length || values[index] is! num) return null;
      final number = (values[index] as num).toDouble();
      return number.isFinite ? number : null;
    }
    final temperatures = series('temperature_2m');
    final humidity = series('relative_humidity_2m');
    final precipitation = series('precipitation');
    final wind = series('wind_speed_10m');
    final pressure = series('pressure_msl');
    final fetched = <HourlyWeatherPoint>[];
    for (var i = 0; i < times.length; i++) {
      final time = times[i];
      if (time is! String) continue;
      fetched.add(HourlyWeatherPoint(
        time: _parseWeatherUtc(time),
        temperatureC: at(temperatures, i),
        humidityPercent: at(humidity, i),
        precipitationMm: at(precipitation, i),
        windKmh: at(wind, i),
        pressureHpa: at(pressure, i),
      ));
    }
    if (fetched.isEmpty) {
      if (cachedPoints.isNotEmpty) return cachedPoints;
      return const [];
    }
    final merged = <String, HourlyWeatherPoint>{
      for (final point in cachedPoints) point.time.toUtc().toIso8601String(): point,
      for (final point in fetched) point.time.toUtc().toIso8601String(): point,
    }.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final oldStart = cached?['startDate'];
    final oldEnd = cached?['endDate'];
    final mergedStart = oldStart is String && oldStart.compareTo(startDate) < 0 ? oldStart : startDate;
    final mergedEnd = oldEnd is String && oldEnd.compareTo(endDate) > 0 ? oldEnd : endDate;
    await database.setAppMetadata(cacheKey, jsonEncode({
      'schemaVersion': 1,
      'locationId': location.id,
      'startDate': mergedStart,
      'endDate': mergedEnd,
      'dataEnd': merged.isEmpty ? null : merged.last.time.toUtc().toIso8601String(),
      'points': merged.map((point) => point.toJson()).toList(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }));
    return merged;
  }

  Future<List<SolarEvent>> loadSolarEvents({
    required SleepDatabase database,
    required WeatherLocation location,
    required DateTime start,
    required DateTime end,
  }) async {
    final startDate = _date(start.toUtc().subtract(const Duration(days: 2)));
    final endDate = _date(end.toUtc().add(const Duration(days: 2)));
    final cacheKey = 'sleep_tracker_solar_cache_v1_${location.id}';
    final cachedRaw = await database.getAppMetadata(cacheKey);
    Map<String, dynamic>? cached;
    List<SolarEvent> cachedEvents = const [];
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      final decoded = jsonDecode(cachedRaw);
      if (decoded is! Map) {
        throw const FormatException('Кэш восхода и заката повреждён. Сохранённые данные не перезаписаны.');
      }
      cached = Map<String, dynamic>.from(decoded);
      final rawEvents = cached['events'];
      if (rawEvents is! List) {
        throw const FormatException('В кэше восхода и заката отсутствует список событий.');
      }
      cachedEvents = rawEvents.whereType<Map>().map(SolarEvent.fromJson).toList();
      final cachedStart = cached['startDate'];
      final cachedEnd = cached['endDate'];
      if (cachedStart is String && cachedEnd is String &&
          cachedStart.compareTo(startDate) <= 0 && cachedEnd.compareTo(endDate) >= 0) {
        return cachedEvents;
      }
    }

    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': location.latitude.toStringAsFixed(5),
      'longitude': location.longitude.toStringAsFixed(5),
      'start_date': startDate,
      'end_date': endDate,
      'daily': 'sunrise,sunset',
      'timezone': 'UTC',
      'timeformat': 'iso8601',
    });
    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 30));
    } catch (_) {
      if (cachedEvents.isNotEmpty) return cachedEvents;
      rethrow;
    }
    if (response.statusCode != 200) {
      if (cachedEvents.isNotEmpty) return cachedEvents;
      throw Exception('Архив восхода и заката ответил кодом ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['daily'] is! Map) {
      if (cachedEvents.isNotEmpty) return cachedEvents;
      throw const FormatException('Сервис не вернул данные восхода и заката.');
    }
    final daily = decoded['daily'] as Map;
    final dates = daily['time'];
    final sunrises = daily['sunrise'];
    final sunsets = daily['sunset'];
    if (dates is! List || sunrises is! List || sunsets is! List) {
      if (cachedEvents.isNotEmpty) return cachedEvents;
      throw const FormatException('В ответе архива отсутствуют солнечные события.');
    }
    final fetched = <SolarEvent>[];
    for (var i = 0; i < dates.length; i++) {
      final date = dates[i];
      if (date is! String) continue;
      DateTime? parse(List values) {
        if (i >= values.length || values[i] is! String) return null;
        return _parseWeatherUtc(values[i] as String);
      }
      fetched.add(SolarEvent(date: date, sunriseUtc: parse(sunrises), sunsetUtc: parse(sunsets)));
    }
    if (fetched.isEmpty) {
      if (cachedEvents.isNotEmpty) return cachedEvents;
      return const [];
    }
    final merged = <String, SolarEvent>{
      for (final event in cachedEvents) event.date: event,
      for (final event in fetched) event.date: event,
    }.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final oldStart = cached?['startDate'];
    final oldEnd = cached?['endDate'];
    final mergedStart = oldStart is String && oldStart.compareTo(startDate) < 0 ? oldStart : startDate;
    final mergedEnd = oldEnd is String && oldEnd.compareTo(endDate) > 0 ? oldEnd : endDate;
    await database.setAppMetadata(cacheKey, jsonEncode({
      'schemaVersion': 1,
      'locationId': location.id,
      'startDate': mergedStart,
      'endDate': mergedEnd,
      'events': merged.map((event) => event.toJson()).toList(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }));
    return merged;
  }
  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
