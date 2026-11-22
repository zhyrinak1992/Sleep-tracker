class WeatherSleepSample {
  const WeatherSleepSample({required this.averageTemperatureC, required this.sleepMinutes});
  final double averageTemperatureC;
  final double sleepMinutes;
}

class WeatherSleepGroup {
  const WeatherSleepGroup({required this.nights, required this.averageSleepMinutes});
  final int nights;
  final double averageSleepMinutes;
}

class WeatherSleepComparison {
  const WeatherSleepComparison({required this.coolerNights, required this.warmerNights});
  final WeatherSleepGroup coolerNights;
  final WeatherSleepGroup warmerNights;

  static WeatherSleepComparison? fromSamples(Iterable<WeatherSleepSample> samples) {
    final ordered = samples.toList()
      ..sort((a, b) => a.averageTemperatureC.compareTo(b.averageTemperatureC));
    if (ordered.length < 4) return null;
    final midpoint = ordered.length ~/ 2;
    WeatherSleepGroup summarize(List<WeatherSleepSample> values) => WeatherSleepGroup(
      nights: values.length,
      averageSleepMinutes: values.map((value) => value.sleepMinutes).reduce((a, b) => a + b) / values.length,
    );
    return WeatherSleepComparison(
      coolerNights: summarize(ordered.take(midpoint).toList()),
      warmerNights: summarize(ordered.skip(midpoint).toList()),
    );
  }
}
