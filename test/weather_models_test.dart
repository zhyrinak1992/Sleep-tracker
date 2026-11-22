import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/weather_models.dart';

void main() {
  test('weather location round-trips and validates coordinates', () {
    const location = WeatherLocation(
      name: 'Dubna',
      country: 'Russia',
      admin1: 'Moscow Oblast',
      latitude: 56.7333,
      longitude: 37.1667,
      timezone: 'Europe/Moscow',
    );
    final parsed = WeatherLocation.tryParse(location.toJson());
    expect(parsed, isNotNull);
    expect(parsed!.displayName, 'Dubna, Moscow Oblast, Russia');
    expect(parsed.timezone, 'Europe/Moscow');
    expect(WeatherLocation.tryParse({
      'name': 'bad',
      'country': 'X',
      'latitude': 200,
      'longitude': 0,
      'timezone': 'UTC',
    }), isNull);
  });

  test('weather metric summary calculates only finite actual values', () {
    final summary = WeatherMetricSummary.fromValues([4, 6, 8], '°C');
    expect(summary, isNotNull);
    expect(summary!.minimum, 4);
    expect(summary.average, 6);
    expect(summary.maximum, 8);
    expect(summary.count, 3);
    expect(WeatherMetricSummary.fromValues([], '°C'), isNull);
  });

  test('weather night record round-trips with missing values left absent', () {
    const location = WeatherLocation(
      name: 'Dubna',
      country: 'Russia',
      latitude: 56.7333,
      longitude: 37.1667,
      timezone: 'Europe/Moscow',
    );
    final record = WeatherNightRecord(
      sessionId: 'night-1',
      location: location,
      fetchedAt: DateTime.utc(2026, 11, 22, 8),
      provider: 'Open-Meteo Historical Weather API',
      sampleCount: 7,
      dataAvailable: true,
      temperature: WeatherMetricSummary.fromValues([4, 5, 6], '°C'),
      precipitationMm: 0,
      sunrise: '2026-11-22T08:12',
      sunset: '2026-11-22T16:10',
      daylightHours: 7.97,
    );
    final restored = WeatherNightRecord.tryParse(record.encode());
    expect(restored, isNotNull);
    expect(restored!.sessionId, 'night-1');
    expect(restored.temperature!.average, 5);
    expect(restored.humidity, isNull);
    expect(restored.precipitationMm, 0);
    expect(restored.sampleCount, 7);
  });
}
