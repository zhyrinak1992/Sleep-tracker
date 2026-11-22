import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/weather_service.dart';
import 'package:sleep_tracker/features/analysis/weather_sleep_analysis.dart';

void main() {
  test('night weather summary uses only hourly points inside the sleep interval', () {
    final points = [
      HourlyWeatherPoint(
        time: DateTime.utc(2026, 11, 21, 22),
        temperatureC: 99,
        humidityPercent: 99,
        precipitationMm: 99,
        windKmh: 99,
        pressureHpa: 999,
      ),
      HourlyWeatherPoint(
        time: DateTime.utc(2026, 11, 22, 0),
        temperatureC: 8,
        humidityPercent: 50,
        precipitationMm: 0.5,
        windKmh: 3,
        pressureHpa: 1000,
      ),
      HourlyWeatherPoint(
        time: DateTime.utc(2026, 11, 22, 1),
        temperatureC: 12,
        humidityPercent: 70,
        precipitationMm: 1,
        windKmh: 5,
        pressureHpa: 1002,
      ),
      HourlyWeatherPoint(
        time: DateTime.utc(2026, 11, 22, 3),
        temperatureC: 77,
      ),
    ];

    final summary = WeatherNightSummary.summarize(
      points,
      start: DateTime.utc(2026, 11, 22),
      end: DateTime.utc(2026, 11, 22, 2),
    );
    expect(summary.sampleCount, 2);
    expect(summary.averageTemperatureC, 10);
    expect(summary.averageHumidityPercent, 60);
    expect(summary.totalPrecipitationMm, 1.5);
    expect(summary.averageWindKmh, 4);
    expect(summary.averagePressureHpa, 1001);
  });

  test('missing weather values remain null instead of being replaced with zero', () {
    final summary = WeatherNightSummary.summarize([
      HourlyWeatherPoint(time: DateTime.utc(2026, 11, 22, 1)),
    ], start: DateTime.utc(2026, 11, 22), end: DateTime.utc(2026, 11, 22, 2));
    expect(summary.sampleCount, 1);
    expect(summary.averageTemperatureC, isNull);
    expect(summary.averageHumidityPercent, isNull);
    expect(summary.totalPrecipitationMm, isNull);
  });

  test('compares sleep duration for cooler and warmer nights by selected-period median', () {
    final result = WeatherSleepComparison.fromSamples([
      const WeatherSleepSample(averageTemperatureC: 4, sleepMinutes: 420),
      const WeatherSleepSample(averageTemperatureC: 6, sleepMinutes: 450),
      const WeatherSleepSample(averageTemperatureC: 8, sleepMinutes: 480),
      const WeatherSleepSample(averageTemperatureC: 10, sleepMinutes: 510),
      const WeatherSleepSample(averageTemperatureC: 12, sleepMinutes: 540),
    ]);
    expect(result, isNotNull);
    expect(result!.coolerNights.nights, 2);
    expect(result.coolerNights.averageSleepMinutes, 435);
    expect(result.warmerNights.nights, 3);
    expect(result.warmerNights.averageSleepMinutes, 510);
  });

  test('does not compare temperature groups with fewer than four nights', () {
    expect(WeatherSleepComparison.fromSamples([
      const WeatherSleepSample(averageTemperatureC: 4, sleepMinutes: 420),
      const WeatherSleepSample(averageTemperatureC: 6, sleepMinutes: 450),
      const WeatherSleepSample(averageTemperatureC: 8, sleepMinutes: 480),
    ]), isNull);
  });
  test('selects the nearest sunset before sleep and sunrise after wake', () {
    final events = [
      SolarEvent(
        date: '2026-11-21',
        sunsetUtc: DateTime.utc(2026, 11, 21, 15),
        sunriseUtc: DateTime.utc(2026, 11, 21, 6),
      ),
      SolarEvent(
        date: '2026-11-22',
        sunsetUtc: DateTime.utc(2026, 11, 22, 15),
        sunriseUtc: DateTime.utc(2026, 11, 22, 6, 30),
      ),
      SolarEvent(
        date: '2026-11-23',
        sunsetUtc: DateTime.utc(2026, 11, 23, 15),
        sunriseUtc: DateTime.utc(2026, 11, 23, 6, 20),
      ),
    ];
    final summary = WeatherNightSummary.summarize(
      const [],
      start: DateTime.utc(2026, 11, 21, 21),
      end: DateTime.utc(2026, 11, 22, 6),
      solarEvents: events,
    );
    expect(summary.sunsetUtc, DateTime.utc(2026, 11, 21, 15));
    expect(summary.sunriseUtc, DateTime.utc(2026, 11, 22, 6, 30));
  });

  test('keeps solar events absent when no matching events are returned', () {
    final summary = WeatherNightSummary.summarize(
      const [],
      start: DateTime.utc(2026, 11, 21, 21),
      end: DateTime.utc(2026, 11, 22, 6),
    );
    expect(summary.sunsetUtc, isNull);
    expect(summary.sunriseUtc, isNull);
  });


  test('uses daylight duration from the day of the next sunrise', () {
    final events = [
      SolarEvent(
        date: '2026-11-22',
        sunriseUtc: DateTime.utc(2026, 11, 22, 6, 30),
        sunsetUtc: DateTime.utc(2026, 11, 22, 15, 10),
        daylightDurationSeconds: 8 * 3600 + 40 * 60,
      ),
    ];
    final summary = WeatherNightSummary.summarize(
      const [],
      start: DateTime.utc(2026, 11, 21, 21),
      end: DateTime.utc(2026, 11, 22, 6),
      solarEvents: events,
    );
    expect(summary.daylightDurationSeconds, 8 * 3600 + 40 * 60);
  });

  test('solar cache accepts older entries without daylight duration', () {
    final event = SolarEvent.fromJson({
      'date': '2026-11-22',
      'sunriseUtc': '2026-11-22T06:30:00Z',
      'sunsetUtc': '2026-11-22T15:10:00Z',
    });
    expect(event.daylightDurationSeconds, isNull);
    expect(event.toJson()['daylightDurationSeconds'], isNull);
  });

}
