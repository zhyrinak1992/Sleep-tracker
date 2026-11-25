class SleepRecommendationText {
  const SleepRecommendationText._();

  static String? forObservedPattern({
    required String tagLabel,
    required String metricKey,
    required double difference,
  }) {
    if (!difference.isFinite || difference == 0) return null;
    const lowerIsWorse = {
      'duration',
      'score',
      'efficiency',
      'subjectiveQuality',
      'wellbeing',
    };
    const higherIsWorse = {'awakenings', 'sleepLatency'};
    final isWorse = lowerIsWorse.contains(metricKey)
        ? difference < 0
        : higherIsWorse.contains(metricKey)
            ? difference > 0
            : null;
    if (isWorse == null) return null;

    final label = tagLabel.toLowerCase();
    if (!isWorse) {
      return 'В этом периоде отметка встречалась вместе с более благоприятным значением показателя. Продолжайте наблюдение: совпадение не доказывает причинную связь.';
    }

    if ((label.contains('коф') || label.contains('кофеин')) &&
        (metricKey == 'awakenings' || metricKey == 'sleepLatency' ||
            metricKey == 'duration' || metricKey == 'score')) {
      return 'Можно понаблюдать за временем последнего кофеина и сравнить следующие ночи, когда напиток был раньше или позже. Меняйте по одному фактору; это наблюдение не доказывает причину.';
    }
    if ((label.contains('ужин') || label.contains('еда')) &&
        (metricKey == 'awakenings' || metricKey == 'sleepLatency' ||
            metricKey == 'duration' || metricKey == 'score')) {
      return 'Можно отмечать время ужина и сравнить следующие ночи с более ранним и поздним приёмом пищи. Это поможет проверить, повторяется ли наблюдаемая связь.';
    }
    if ((label.contains('экран') || label.contains('телефон')) &&
        (metricKey == 'awakenings' || metricKey == 'sleepLatency' ||
            metricKey == 'duration' || metricKey == 'score')) {
      return 'Можно отдельно отмечать использование экрана перед сном и сравнивать ночи с разным временем завершения использования.';
    }
    if (label.contains('трен') || label.contains('нагруз')) {
      return 'Можно фиксировать время и характер нагрузки и сравнивать последующие ночи. Не делайте вывод по одной записи.';
    }
    if (label.contains('стресс')) {
      return 'Можно продолжить отмечать стресс и вечерний контекст, а затем проверить, сохраняется ли различие в следующих периодах.';
    }
    return 'Можно продолжить отмечать этот фактор и проверить, повторяется ли различие в следующих ночах. Если это привычка, меняйте по одному фактору за раз.';
  }
}
