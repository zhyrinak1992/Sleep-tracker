import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/night_environment_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  test('formats selected location and validates coordinate bounds', () {
    const location = EnvironmentLocation(
      name: 'Дубна',
      latitude: 56.733,
      longitude: 37.167,
      country: 'Россия',
      admin1: 'Московская область',
    );
    expect(location.displayName, 'Дубна, Московская область, Россия');
    expect(EnvironmentLocation.fromMap(location.toMap()).longitude, closeTo(37.167, 0.0001));
    expect(
      () => EnvironmentLocation.fromMap({
        'name': 'Invalid',
        'latitude': 120,
        'longitude': 0,
        'country': 'X',
      }),
      throwsFormatException,
    );
  });

  test('night environment summary round-trips nullable weather and sun data', () {
    const summary = NightEnvironmentSummary(
      locationName: 'Dubna, Russia',
      sampleCount: 6,
      utcOffsetSeconds: 10800,
      temperatureMin: -2,
      temperatureAverage: 0.5,
      temperatureMax: 3,
      humidityAverage: 78,
      precipitationMm: 0.4,
      windMaxKmh: 12,
      weatherCode: 3,
      sunriseEpoch: 1795327200,
      sunsetEpoch: 1795290000,
    );
    final decoded = NightEnvironmentSummary.fromMap(summary.toMap());
    expect(decoded.sampleCount, 6);
    expect(decoded.temperatureAverage, 0.5);
    expect(decoded.weatherCode, 3);
    expect(decoded.sunriseEpoch, summary.sunriseEpoch);
    expect(decoded.hasWeather, isTrue);
  });
  test('sunrise and sunset use the selected location timezone including DST', () {
    final summerEpoch = DateTime.utc(2026, 6, 21, 3).millisecondsSinceEpoch ~/ 1000;
    final summary = NightEnvironmentSummary(
      locationName: 'Berlin, Germany',
      sampleCount: 1,
      utcOffsetSeconds: 3600,
      timezoneName: 'Europe/Berlin',
      sunriseEpoch: summerEpoch,
    );
    expect(summary.sunriseLocalWallTime!.hour, 5);
  });

}
