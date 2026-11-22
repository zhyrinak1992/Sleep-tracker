import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/sleep_session.dart';
import '../models/weather_models.dart';
import 'sleep_database.dart';

class WeatherSyncResult {
  const WeatherSyncResult({
    required this.nightsUpdated,
    required this.nightsWithData,
    required this.hourlySamples,
  });

  final int nightsUpdated;
  final int nightsWithData;
  final int hourlySamples;
}

/// User-selected location only. Requests historical archive data, never
/// substitutes current weather for a past night.
class WeatherHistoryService {
  WeatherHistoryService._();
  static final instance = WeatherHistoryService._();

  static const locationKey = 'weather_location_v1';
  static const recordPrefix = 'weather_history_v1_';
  static const provider = 'Open-Meteo Historical Weather API';
  static bool _timezoneReady = false;

  Future<List<WeatherLocation>> searchLocations(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) {
      throw ArgumentError('Введи не менее двух символов для поиска города.');
    }
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': normalized,
      'count': '8',
      'language': 'ru',
      'format': 'json',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Сервис поиска городов вернул HTTP ${response.statusCode}.');
    }
    final decoded = httpResponseJson(response.body);
    if (decoded is! Map) throw const FormatException('Некорректный ответ поиска городов.');
    final results = decoded['results'];
    if (results is! List) return const [];
    return results.whereType<Map>().map((item) {
      final name = item['name'];
      final country = item['country'];
      final lat = item['latitude'];
      final lon = item['longitude'];
      final zone = item['timezone'];
      if (name is! String || country is! String || lat is! num || lon is! num || zone is! String) {
        return null;
      }
      return WeatherLocation(
        name: name,
        country: country,
        admin1: item['admin1'] is String ? item['admin1'] as String : null,
        latitude: lat.toDouble(),
        longitude: lon.toDouble(),
        timezone: zone,
      );
    }).whereType<WeatherLocation>().toList();
  }

  Object? httpResponseJson(String body) {
    // Kept local to the service so all network responses pass one JSON parser.
    return jsonDecode(body);
  }

  Future<WeatherLocation?> loadLocation({SleepDatabase? database}) async {
    final db = database ?? SleepDatabase.instance;
    final raw = await db.getAppMetadata(locationKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return WeatherLocation.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocation(WeatherLocation location, {SleepDatabase? database}) async {
    final db = database ?? SleepDatabase.instance;
    await db.setAppMetadata(locationKey, jsonEncode(location.toJson()));
  }

  Future<WeatherSyncResult> syncSessions({
    required List<SleepSession> sessions,
    SleepDatabase? database,
  }) async {
    final db = database ?? SleepDatabase.instance;
    final location = await loadLocation(database: db);
    if (location == null) {
      throw StateError('Сначала выбери город для исторической погоды.');
    }
    final completed = sessions.where((session) {
      final start = session.actualSleepStartedAt ?? session.startedAt;
      final end = session.actualSleepEndedAt ?? session.endedAt;
      return end != null && end.isAfter(start);
    }).toList();
    if (completed.isEmpty) {
      return const WeatherSyncResult(nightsUpdated: 0, nightsWithData: 0, hourlySamples: 0);
    }

    if (!_timezoneReady) {
      tzdata.initializeTimeZones();
      _timezoneReady = true;
    }
    final zone = _locationTimeZone(location.timezone);
    final localStarts = completed.map((session) => tz.TZDateTime.from(
      (session.actualSleepStartedAt ?? session.startedAt).toUtc(), zone,
    )).toList();
    final localEnds = completed.map((session) => tz.TZDateTime.from(
      (session.actualSleepEndedAt ?? session.endedAt!).toUtc(), zone,
    )).toList();
    final first = localStarts.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = localEnds.reduce((a, b) => a.isAfter(b) ? a : b);
    final startDate = _dateKey(first);
    final endDate = _dateKey(last);

    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'start_date': startDate,
      'end_date': endDate,
      'hourly': 'temperature_2m,relative_humidity_2m,pressure_msl,precipitation,wind_speed_10m',
      'daily': 'sunrise,sunset,daylight_duration',
      'timezone': location.timezone,
      'temperature_unit': 'celsius',
      'wind_speed_unit': 'kmh',
      'precipitation_unit': 'mm',
      'timeformat': 'iso8601',
      'models': 'best_match',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Исторический погодный архив вернул HTTP ${response.statusCode}.');
    }
    final decoded = httpResponseJson(response.body);
    if (decoded is! Map) throw const FormatException('Некорректный ответ исторического погодного архива.');
    if (decoded['error'] == true) {
      throw StateError(decoded['reason']?.toString() ?? 'Поставщик не вернул исторические данные.');
    }
    final hourly = decoded['hourly'] is Map ? decoded['hourly'] as Map : const {};
    final daily = decoded['daily'] is Map ? decoded['daily'] as Map : const {};
    final times = _stringList(hourly['time']);
    final temp = _numberList(hourly['temperature_2m']);
    final humidity = _numberList(hourly['relative_humidity_2m']);
    final pressure = _numberList(hourly['pressure_msl']);
    final precipitation = _numberList(hourly['precipitation']);
    final wind = _numberList(hourly['wind_speed_10m']);
    final dailyTimes = _stringList(daily['time']);
    final sunrise = _nullableStringList(daily['sunrise']);
    final sunset = _nullableStringList(daily['sunset']);
    final daylight = _numberList(daily['daylight_duration']);

    var nightsWithData = 0;
    var totalSamples = 0;
    final fetchedAt = DateTime.now();
    for (var i = 0; i < completed.length; i++) {
      final session = completed[i];
      final start = localStarts[i];
      final end = localEnds[i];
      final firstHour = _ceilHour(start);
      final lastHour = _floorHour(end);
      final fromKey = _hourKey(firstHour);
      final toKey = _hourKey(lastHour);
      final indices = <int>[];
      for (var index = 0; index < times.length; index++) {
        final key = _normalizeHourKey(times[index]);
        if (key.compareTo(fromKey) >= 0 && key.compareTo(toKey) <= 0) {
          indices.add(index);
        }
      }

      List<double> selected(List<double?> source) => indices
        .where((index) => index < source.length && source[index] != null)
        .map((index) => source[index]!)
        .where((value) => value.isFinite)
        .toList();

      final temperature = WeatherMetricSummary.fromValues(selected(temp), '°C');
      final humiditySummary = WeatherMetricSummary.fromValues(selected(humidity), '%');
      final pressureSummary = WeatherMetricSummary.fromValues(selected(pressure), 'гПа');
      final windSummary = WeatherMetricSummary.fromValues(selected(wind), 'км/ч');
      final precipitationValues = selected(precipitation);
      final precipitationTotal = precipitationValues.isEmpty
          ? null
          : precipitationValues.reduce((a, b) => a + b);

      final dayIndex = dailyTimes.indexOf(_dateKey(end));
      final sunriseValue = dayIndex >= 0 && dayIndex < sunrise.length ? sunrise[dayIndex] : null;
      final sunsetValue = dayIndex >= 0 && dayIndex < sunset.length ? sunset[dayIndex] : null;
      final daylightSeconds = dayIndex >= 0 && dayIndex < daylight.length ? daylight[dayIndex] : null;
      final sampleCount = indices.where((index) =>
        (index < temp.length && temp[index] != null) ||
        (index < humidity.length && humidity[index] != null) ||
        (index < pressure.length && pressure[index] != null) ||
        (index < wind.length && wind[index] != null) ||
        (index < precipitation.length && precipitation[index] != null)
      ).length;
      final available = temperature != null || humiditySummary != null ||
          pressureSummary != null || windSummary != null ||
          precipitationTotal != null || sunriseValue != null ||
          sunsetValue != null || daylightSeconds != null;
      if (available) nightsWithData++;
      totalSamples += sampleCount;

      final record = WeatherNightRecord(
        sessionId: session.id,
        location: location,
        fetchedAt: fetchedAt,
        provider: provider,
        sampleCount: sampleCount,
        dataAvailable: available,
        temperature: temperature,
        humidity: humiditySummary,
        pressure: pressureSummary,
        windSpeed: windSummary,
        precipitationMm: precipitationTotal,
        sunrise: sunriseValue,
        sunset: sunsetValue,
        daylightHours: daylightSeconds == null ? null : daylightSeconds / 3600,
      );
      await db.setAppMetadata('$recordPrefix${session.id}', record.encode());
    }

    return WeatherSyncResult(
      nightsUpdated: completed.length,
      nightsWithData: nightsWithData,
      hourlySamples: totalSamples,
    );
  }

  tz.Location _locationTimeZone(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _hourKey(tz.TZDateTime date) =>
      '${_dateKey(date)}T${date.hour.toString().padLeft(2, '0')}:00';

  static String _normalizeHourKey(String value) => value.length >= 16 ? value.substring(0, 16) : value;

  static tz.TZDateTime _ceilHour(tz.TZDateTime value) {
    final floor = tz.TZDateTime(value.location, value.year, value.month, value.day, value.hour);
    if (value.minute == 0 && value.second == 0) return floor;
    return floor.add(const Duration(hours: 1));
  }

  static tz.TZDateTime _floorHour(tz.TZDateTime value) =>
      tz.TZDateTime(value.location, value.year, value.month, value.day, value.hour);

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static List<String?> _nullableStringList(Object? value) =>
      value is List ? value.map((item) => item is String ? item : null).toList() : const [];

  static List<double?> _numberList(Object? value) => value is List
      ? value.map((item) => item is num && item.toDouble().isFinite ? item.toDouble() : null).toList()
      : const [];
}
