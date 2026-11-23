import 'dart:math' as math;

import 'sleep_dynamics_analysis.dart';

enum SleepChangeKind {
  duration,
  score,
  efficiency,
  awakenings,
  quality,
  wellbeing,
  bedtimeVariability,
  wakeVariability,
  bedtimeShift,
  wakeShift,
}

class SleepChangeItem {
  const SleepChangeItem({
    required this.kind,
    required this.title,
    required this.previousValue,
    required this.currentValue,
    required this.delta,
    required this.unit,
    required this.previousSamples,
    required this.currentSamples,
    required this.threshold,
    required this.description,
  });

  final SleepChangeKind kind;
  final String title;
  final double previousValue;
  final double currentValue;
  final double delta;
  final String unit;
  final int previousSamples;
  final int currentSamples;
  final double threshold;
  final String description;

  double get significance => delta.abs() / threshold;

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'title': title,
    'previousValue': previousValue,
    'currentValue': currentValue,
    'delta': delta,
    'unit': unit,
    'previousSamples': previousSamples,
    'currentSamples': currentSamples,
    'threshold': threshold,
    'description': description,
  };
}

class SleepChangeInsights {
  const SleepChangeInsights({
    required this.items,
    required this.mainChange,
    required this.hasComparableData,
  });

  final List<SleepChangeItem> items;
  final SleepChangeItem? mainChange;
  final bool hasComparableData;

  bool get hasNotableChanges => items.isNotEmpty;

  static SleepChangeInsights calculate({
    required SleepDynamicsSummary current,
    required SleepDynamicsSummary previous,
  }) {
    final candidates = <SleepChangeItem>[];

    void add({
      required SleepChangeKind kind,
      required String title,
      required double? before,
      required double? after,
      required int beforeCount,
      required int afterCount,
      required int minimumSamples,
      required double threshold,
      required String unit,
      required String Function(double before, double after, double delta) describe,
    }) {
      if (before == null || after == null ||
          !before.isFinite || !after.isFinite ||
          beforeCount < minimumSamples || afterCount < minimumSamples) return;
      final delta = after - before;
      if (delta.abs() < threshold) return;
      candidates.add(SleepChangeItem(
        kind: kind,
        title: title,
        previousValue: before,
        currentValue: after,
        delta: delta,
        unit: unit,
        previousSamples: beforeCount,
        currentSamples: afterCount,
        threshold: threshold,
        description: describe(before, after, delta),
      ));
    }

    String signed(double value, String suffix, {int decimals = 0}) {
      final sign = value > 0 ? '+' : '';
      return '$sign${value.toStringAsFixed(decimals)}$suffix';
    }

    String duration(double value) {
      final minutes = value.round();
      if (minutes ~/ 60 == 0) return '${minutes} мин';
      if (minutes % 60 == 0) return '${minutes ~/ 60} ч';
      return '${minutes ~/ 60} ч ${minutes % 60} мин';
    }

    add(
      kind: SleepChangeKind.duration, title: 'Средняя длительность сна',
      before: previous.averageSleepMinutes, after: current.averageSleepMinutes,
      beforeCount: previous.durationSamples, afterCount: current.durationSamples,
      minimumSamples: 7, threshold: 20, unit: 'мин',
      describe: (a, b, d) => 'Средняя длительность сна ${d > 0 ? 'увеличилась' : 'сократилась'} на ${duration(d.abs())}: ${duration(a)} → ${duration(b)} (ночей: ${previous.durationSamples} → ${current.durationSamples}).',
    );
    add(
      kind: SleepChangeKind.score, title: 'Средняя оценка сна (0–100)',
      before: previous.averageSleepScore, after: current.averageSleepScore,
      beforeCount: previous.scoreSamples, afterCount: current.scoreSamples,
      minimumSamples: 7, threshold: 3, unit: 'балла',
      describe: (a, b, d) => 'Средний SleepScore ${d > 0 ? 'увеличился' : 'снизился'} на ${d.abs().toStringAsFixed(1)} балла: ${a.toStringAsFixed(1)} → ${b.toStringAsFixed(1)} (ночей: ${previous.scoreSamples} → ${current.scoreSamples}).',
    );
    add(
      kind: SleepChangeKind.efficiency, title: 'Эффективность сна',
      before: previous.averageEfficiency, after: current.averageEfficiency,
      beforeCount: previous.efficiencySamples, afterCount: current.efficiencySamples,
      minimumSamples: 5, threshold: 3, unit: 'п.п.',
      describe: (a, b, d) => 'Средняя эффективность сна изменилась на ${signed(d, ' п.п.')}: ${a.toStringAsFixed(1)}% → ${b.toStringAsFixed(1)}% (ночей: ${previous.efficiencySamples} → ${current.efficiencySamples}).',
    );
    add(
      kind: SleepChangeKind.awakenings, title: 'Пробуждения за ночь',
      before: previous.averageAwakenings, after: current.averageAwakenings,
      beforeCount: previous.awakeningSamples, afterCount: current.awakeningSamples,
      minimumSamples: 5, threshold: 0.5, unit: 'раза',
      describe: (a, b, d) => 'Среднее число пробуждений ${d > 0 ? 'увеличилось' : 'уменьшилось'} на ${d.abs().toStringAsFixed(1)} за ночь: ${a.toStringAsFixed(1)} → ${b.toStringAsFixed(1)} (ночей: ${previous.awakeningSamples} → ${current.awakeningSamples}).',
    );
    add(
      kind: SleepChangeKind.quality, title: 'Субъективное качество сна',
      before: previous.averageQuality, after: current.averageQuality,
      beforeCount: previous.qualitySamples, afterCount: current.qualitySamples,
      minimumSamples: 5, threshold: 0.3, unit: 'балла',
      describe: (a, b, d) => 'Оценка качества сна ${d > 0 ? 'увеличилась' : 'снизилась'} на ${d.abs().toStringAsFixed(1)} балла: ${a.toStringAsFixed(1)} → ${b.toStringAsFixed(1)} из 5 (оценок: ${previous.qualitySamples} → ${current.qualitySamples}).',
    );
    add(
      kind: SleepChangeKind.wellbeing, title: 'Утреннее самочувствие',
      before: previous.averageWellbeing, after: current.averageWellbeing,
      beforeCount: previous.wellbeingSamples, afterCount: current.wellbeingSamples,
      minimumSamples: 5, threshold: 0.3, unit: 'балла',
      describe: (a, b, d) => 'Оценка утреннего самочувствия ${d > 0 ? 'увеличилась' : 'снизилась'} на ${d.abs().toStringAsFixed(1)} балла: ${a.toStringAsFixed(1)} → ${b.toStringAsFixed(1)} из 5 (оценок: ${previous.wellbeingSamples} → ${current.wellbeingSamples}).',
    );
    add(
      kind: SleepChangeKind.bedtimeVariability, title: 'Разброс времени засыпания',
      before: previous.bedtimeDeviationMinutes, after: current.bedtimeDeviationMinutes,
      beforeCount: previous.regularitySamples, afterCount: current.regularitySamples,
      minimumSamples: 7, threshold: 15, unit: 'мин',
      describe: (a, b, d) => 'Разброс времени засыпания ${d < 0 ? 'сократился' : 'увеличился'} на ${duration(d.abs())}: ${duration(a)} → ${duration(b)} (ночей: ${previous.regularitySamples} → ${current.regularitySamples}).',
    );
    add(
      kind: SleepChangeKind.wakeVariability, title: 'Разброс времени пробуждения',
      before: previous.wakeTimeDeviationMinutes, after: current.wakeTimeDeviationMinutes,
      beforeCount: previous.regularitySamples, afterCount: current.regularitySamples,
      minimumSamples: 7, threshold: 15, unit: 'мин',
      describe: (a, b, d) => 'Разброс времени пробуждения ${d < 0 ? 'сократился' : 'увеличился'} на ${duration(d.abs())}: ${duration(a)} → ${duration(b)} (ночей: ${previous.regularitySamples} → ${current.regularitySamples}).',
    );

    double? signedClockDelta(int? before, int? after) {
      if (before == null || after == null) return null;
      return ((after - before + 720) % 1440) - 720;
    }

    final bedShift = signedClockDelta(previous.typicalBedtimeMinute, current.typicalBedtimeMinute);
    if (bedShift != null && previous.regularitySamples >= 7 && current.regularitySamples >= 7 && bedShift.abs() >= 20) {
      candidates.add(SleepChangeItem(
        kind: SleepChangeKind.bedtimeShift, title: 'Типичное время засыпания',
        previousValue: previous.typicalBedtimeMinute!.toDouble(),
        currentValue: current.typicalBedtimeMinute!.toDouble(),
        delta: bedShift, unit: 'мин', previousSamples: previous.regularitySamples,
        currentSamples: current.regularitySamples, threshold: 20,
        description: 'Типичное время засыпания сдвинулось на ${duration(bedShift.abs())} ${bedShift > 0 ? 'позже' : 'раньше'} (ночей: ${previous.regularitySamples} → ${current.regularitySamples}).',
      ));
    }
    final wakeShift = signedClockDelta(previous.typicalWakeMinute, current.typicalWakeMinute);
    if (wakeShift != null && previous.regularitySamples >= 7 && current.regularitySamples >= 7 && wakeShift.abs() >= 20) {
      candidates.add(SleepChangeItem(
        kind: SleepChangeKind.wakeShift, title: 'Типичное время пробуждения',
        previousValue: previous.typicalWakeMinute!.toDouble(),
        currentValue: current.typicalWakeMinute!.toDouble(),
        delta: wakeShift, unit: 'мин', previousSamples: previous.regularitySamples,
        currentSamples: current.regularitySamples, threshold: 20,
        description: 'Типичное время пробуждения сдвинулось на ${duration(wakeShift.abs())} ${wakeShift > 0 ? 'позже' : 'раньше'} (ночей: ${previous.regularitySamples} → ${current.regularitySamples}).',
      ));
    }

    candidates.sort((a, b) => b.significance.compareTo(a.significance));
    SleepChangeItem? main;
    if (candidates.isNotEmpty) {
      if (candidates.length == 1 ||
          (candidates[0].significance - candidates[1].significance).abs() > 0.05) {
        main = candidates.first;
      }
    }

    final hasComparableData = [
      previous.durationSamples >= 7 && current.durationSamples >= 7,
      previous.scoreSamples >= 7 && current.scoreSamples >= 7,
      previous.efficiencySamples >= 5 && current.efficiencySamples >= 5,
      previous.qualitySamples >= 5 && current.qualitySamples >= 5,
      previous.wellbeingSamples >= 5 && current.wellbeingSamples >= 5,
      previous.awakeningSamples >= 5 && current.awakeningSamples >= 5,
      previous.regularitySamples >= 7 && current.regularitySamples >= 7,
    ].any((value) => value);

    return SleepChangeInsights(
      items: List.unmodifiable(candidates),
      mainChange: main,
      hasComparableData: hasComparableData,
    );
  }

  String get personalSummary {
    if (!hasComparableData) {
      return 'Для персонального итога пока недостаточно сопоставимых записей в обоих 30-дневных периодах.';
    }
    if (items.isEmpty) {
      return 'По доступным показателям выраженных изменений выше установленных порогов не выявлено.';
    }
    final lines = items.take(4).map((item) => item.description).join('\n');
    final remaining = items.length - math.min(items.length, 4);
    return remaining > 0
        ? '$lines\nЕщё заметных изменений: $remaining.'
        : lines;
  }
}
