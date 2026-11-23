/// Transparent 0–100 descriptive sleep-quality score.
/// The score is not a medical assessment. Missing components are excluded
/// and the remaining weights are proportionally normalized.
class SleepScoreComponent {
  const SleepScoreComponent({
    required this.key,
    required this.label,
    required this.weight,
    required this.score,
    required this.detail,
  });

  final String key;
  final String label;
  final double weight;
  final double? score;
  final String detail;

  Map<String, Object?> toMap() => {
    'key': key,
    'label': label,
    'weight': weight,
    'score': score,
    'detail': detail,
  };
}

class SleepScoreResult {
  const SleepScoreResult({
    required this.score,
    required this.availableWeight,
    required this.availableComponents,
    required this.components,
  });

  final double? score;
  final double availableWeight;
  final int availableComponents;
  final List<SleepScoreComponent> components;

  bool get isAvailable => score != null;

  Map<String, Object?> toMap() => {
    'score': score == null ? null : score!.round(),
    'availableWeight': availableWeight,
    'availableComponents': availableComponents,
    'components': components.map((item) => item.toMap()).toList(),
    'weights': const {
      'duration': 40,
      'efficiency': 30,
      'awakenings': 20,
      'subjectiveQuality': 10,
    },
    'methodVersion': 1,
  };
}

class SleepScoreCalculator {
  SleepScoreCalculator._();

  static const double durationWeight = 40;
  static const double efficiencyWeight = 30;
  static const double awakeningsWeight = 20;
  static const double subjectiveQualityWeight = 10;
  static const double minimumAvailableWeight = 50;
  static const int minimumAvailableComponents = 2;
  static const int durationGraceMinutes = 180;

  static SleepScoreResult calculate({
    required int? sleepDurationMinutes,
    required int? personalLowerMinutes,
    required int? personalUpperMinutes,
    required double? sleepEfficiencyPercent,
    required int? awakeningCount,
    required bool awakeningsAvailable,
    required int? subjectiveQuality,
  }) {
    final durationScore = _durationScore(
      sleepDurationMinutes, personalLowerMinutes, personalUpperMinutes,
    );
    final efficiencyScore = _efficiencyScore(sleepEfficiencyPercent);
    final awakeningsScore = awakeningsAvailable && awakeningCount != null &&
        awakeningCount >= 0
        ? (100 - awakeningCount * 20).clamp(0, 100).toDouble()
        : null;
    final qualityScore = subjectiveQuality != null &&
        subjectiveQuality >= 1 && subjectiveQuality <= 5
        ? (subjectiveQuality - 1) * 25.0
        : null;

    final components = <SleepScoreComponent>[
      SleepScoreComponent(
        key: 'duration', label: 'Продолжительность сна',
        weight: durationWeight, score: durationScore,
        detail: durationScore == null
          ? 'Нет подтверждённого индивидуального диапазона или длительности сна.'
          : 'Сравнение с личным диапазоном сна; внутри диапазона — 100, за его границами балл плавно снижается до нуля на расстоянии 3 часов.',
      ),
      SleepScoreComponent(
        key: 'efficiency', label: 'Эффективность сна',
        weight: efficiencyWeight, score: efficiencyScore,
        detail: efficiencyScore == null
          ? 'Недостаточное покрытие измерениями сна и бодрствования.'
          : '70% и ниже — 0; 90% и выше — 100; между ними — линейная шкала.',
      ),
      SleepScoreComponent(
        key: 'awakenings', label: 'Пробуждения',
        weight: awakeningsWeight, score: awakeningsScore,
        detail: awakeningsScore == null
          ? 'Нет достоверных данных о пробуждениях.'
          : '0 пробуждений — 100; за каждое зарегистрированное пробуждение снимается 20 баллов, минимум — 0.',
      ),
      SleepScoreComponent(
        key: 'subjectiveQuality', label: 'Субъективное качество сна',
        weight: subjectiveQualityWeight, score: qualityScore,
        detail: qualityScore == null
          ? 'Утренняя оценка качества сна не заполнена.'
          : 'Оценка 1–5 линейно переводится в диапазон 0–100.',
      ),
    ];

    final available = components.where((item) => item.score != null).toList();
    final availableWeight = available.fold<double>(0, (sum, item) => sum + item.weight);
    final canCalculate = available.length >= minimumAvailableComponents &&
        availableWeight >= minimumAvailableWeight;
    final score = canCalculate
        ? available.fold<double>(0, (sum, item) =>
            sum + item.score! * item.weight) / availableWeight
        : null;

    return SleepScoreResult(
      score: score,
      availableWeight: availableWeight,
      availableComponents: available.length,
      components: List.unmodifiable(components),
    );
  }

  static double? _durationScore(int? duration, int? lower, int? upper) {
    if (duration == null || duration <= 0 || lower == null || upper == null ||
        lower <= 0 || upper < lower) return null;
    if (duration >= lower && duration <= upper) return 100;
    final distance = duration < lower ? lower - duration : duration - upper;
    return (100 * (1 - distance / durationGraceMinutes))
        .clamp(0, 100).toDouble();
  }

  static double? _efficiencyScore(double? efficiency) {
    if (efficiency == null || !efficiency.isFinite ||
        efficiency < 0 || efficiency > 100) return null;
    return ((efficiency - 70) / 20 * 100).clamp(0, 100).toDouble();
  }
}
