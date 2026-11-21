class SleepTag {
  const SleepTag(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;
  static const catalog = <SleepTag>[
    SleepTag('stress', 'Стресс', 'Напряжение, тревога, эмоциональная нагрузка'),
    SleepTag('activity', 'Физическая активность', 'Тренировка, прогулка, нагрузка'),
    SleepTag('nutrition', 'Питание', 'Поздний или непривычный приём пищи'),
    SleepTag('caffeine', 'Кофеин', 'Кофе, чай или энергетические напитки'),
    SleepTag('wellbeing', 'Самочувствие', 'Общее состояние в течение дня'),
    SleepTag('illness', 'Недомогание', 'Болезнь или неприятные симптомы'),
    SleepTag('environment', 'Обстановка', 'Шум, свет, температура помещения'),
    SleepTag('schedule', 'Режим дня', 'Смена графика или необычное расписание'),
    SleepTag('travel', 'Поездка', 'Дорога, смена места или часового пояса'),
  ];
  static SleepTag? byKey(String key) {
    for (final tag in catalog) { if (tag.key == key) return tag; }
    return null;
  }
}
