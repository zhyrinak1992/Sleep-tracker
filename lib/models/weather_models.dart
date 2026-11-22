import 'dart:convert';

class WeatherLocation {
  const WeatherLocation({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.admin1,
  });

  final String name;
  final String country;
  final String? admin1;
  final double latitude;
  final double longitude;
  final String timezone;

  String get displayName => [
    name,
    if (admin1 != null && admin1!.isNotEmpty) admin1,
    country,
  ].whereType<String>().join(', ');

  Map<String, Object?> toJson() => {
    'name': name,
    'country': country,
    'admin1': admin1,
    'latitude': latitude,
    'longitude': longitude,
    'timezone': timezone,
  };

  static WeatherLocation? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final country = raw['country'];
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    final timezone = raw['timezone'];
    if (name is! String || country is! String ||
        latitude is! num || longitude is! num || timezone is! String) {
      return null;
    }
    final lat = latitude.toDouble();
    final lon = longitude.toDouble();
    if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return null;
    }
    return WeatherLocation(
      name: name,
      country: country,
      admin1: raw['admin1'] is String ? raw['admin1'] as String : null,
      latitude: lat,
      longitude: lon,
      timezone: timezone,
    );
  }
}

class WeatherMetricSummary {
  const WeatherMetricSummary({
    required this.minimum,
    required this.average,
    required this.maximum,
    required this.count,
    required this.unit,
  });

  final double minimum;
  final double average;
  final double maximum;
  final int count;
  final String unit;

  Map<String, Object?> toJson() => {
    'minimum': minimum,
    'average': average,
    'maximum': maximum,
    'count': count,
    'unit': unit,
  };

  static WeatherMetricSummary? fromValues(List<double> values, String unit) {
    final valid = values.where((v) => v.isFinite).toList();
    if (valid.isEmpty) return null;
    final minimum = valid.reduce((a, b) => a < b ? a : b);
    final maximum = valid.reduce((a, b) => a > b ? a : b);
    final average = valid.reduce((a, b) => a + b) / valid.length;
    return WeatherMetricSummary(
      minimum: minimum,
      average: average,
      maximum: maximum,
      count: valid.length,
      unit: unit,
    );
  }

  static WeatherMetricSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final minimum = raw['minimum'];
    final average = raw['average'];
    final maximum = raw['maximum'];
    final count = raw['count'];
    final unit = raw['unit'];
    if (minimum is! num || average is! num || maximum is! num ||
        count is! int || count <= 0 || unit is! String) return null;
    final min = minimum.toDouble();
    final avg = average.toDouble();
    final max = maximum.toDouble();
    if (!min.isFinite || !avg.isFinite || !max.isFinite) return null;
    return WeatherMetricSummary(
      minimum: min,
      average: avg,
      maximum: max,
      count: count,
      unit: unit,
    );
  }
}

class WeatherNightRecord {
  const WeatherNightRecord({
    required this.sessionId,
    required this.location,
    required this.fetchedAt,
    required this.provider,
    required this.sampleCount,
    required this.dataAvailable,
    this.temperature,
    this.humidity,
    this.pressure,
    this.windSpeed,
    this.precipitationMm,
    this.sunrise,
    this.sunset,
    this.daylightHours,
  });

  final String sessionId;
  final WeatherLocation location;
  final DateTime fetchedAt;
  final String provider;
  final int sampleCount;
  final bool dataAvailable;
  final WeatherMetricSummary? temperature;
  final WeatherMetricSummary? humidity;
  final WeatherMetricSummary? pressure;
  final WeatherMetricSummary? windSpeed;
  final double? precipitationMm;
  final String? sunrise;
  final String? sunset;
  final double? daylightHours;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'location': location.toJson(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'provider': provider,
    'sampleCount': sampleCount,
    'dataAvailable': dataAvailable,
    'temperature': temperature?.toJson(),
    'humidity': humidity?.toJson(),
    'pressure': pressure?.toJson(),
    'windSpeed': windSpeed?.toJson(),
    'precipitationMm': precipitationMm,
    'sunrise': sunrise,
    'sunset': sunset,
    'daylightHours': daylightHours,
  };

  String encode() => jsonEncode(toJson());

  static WeatherNightRecord? tryParse(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map) return null;
    final sessionId = raw['sessionId'];
    final location = WeatherLocation.tryParse(raw['location']);
    final fetchedAt = raw['fetchedAt'];
    final provider = raw['provider'];
    final sampleCount = raw['sampleCount'];
    final dataAvailable = raw['dataAvailable'];
    if (sessionId is! String || sessionId.isEmpty || location == null ||
        fetchedAt is! String || provider is! String ||
        sampleCount is! int || sampleCount < 0 || dataAvailable is! bool) return null;
    final fetched = DateTime.tryParse(fetchedAt);
    if (fetched == null) return null;
    double? optionalNumber(Object? value) {
      if (value is! num) return null;
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }
    return WeatherNightRecord(
      sessionId: sessionId,
      location: location,
      fetchedAt: fetched.toLocal(),
      provider: provider,
      sampleCount: sampleCount,
      dataAvailable: dataAvailable,
      temperature: WeatherMetricSummary.tryParse(raw['temperature']),
      humidity: WeatherMetricSummary.tryParse(raw['humidity']),
      pressure: WeatherMetricSummary.tryParse(raw['pressure']),
      windSpeed: WeatherMetricSummary.tryParse(raw['windSpeed']),
      precipitationMm: optionalNumber(raw['precipitationMm']),
      sunrise: raw['sunrise'] is String ? raw['sunrise'] as String : null,
      sunset: raw['sunset'] is String ? raw['sunset'] as String : null,
      daylightHours: optionalNumber(raw['daylightHours']),
    );
  }
}
