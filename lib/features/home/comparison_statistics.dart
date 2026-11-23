import 'dart:math' as math;

/// Two-sided Mann–Whitney U test. Exact permutation probabilities are used
/// for small samples; larger samples use a tie-corrected normal approximation.
class ComparisonStatistics {
  ComparisonStatistics._();

  static double? mannWhitneyTwoSidedPValue(
    List<double> first,
    List<double> second,
  ) {
    if (first.length < 2 || second.length < 2 ||
        first.any((value) => !value.isFinite) ||
        second.any((value) => !value.isFinite)) return null;

    final observations = <({double value, bool first})>[
      ...first.map((value) => (value: value, first: true)),
      ...second.map((value) => (value: value, first: false)),
    ]..sort((a, b) => a.value.compareTo(b.value));

    final ranks = List<double>.filled(observations.length, 0);
    final tieSizes = <int>[];
    var index = 0;
    while (index < observations.length) {
      var end = index + 1;
      while (end < observations.length &&
          observations[end].value == observations[index].value) {
        end++;
      }
      final averageRank = ((index + 1) + end) / 2.0;
      for (var i = index; i < end; i++) {
        ranks[i] = averageRank;
      }
      if (end - index > 1) tieSizes.add(end - index);
      index = end;
    }

    var rankSumFirst = 0.0;
    for (var i = 0; i < observations.length; i++) {
      if (observations[i].first) rankSumFirst += ranks[i];
    }
    final n1 = first.length;
    final n2 = second.length;
    final total = n1 + n2;
    final u = rankSumFirst - n1 * (n1 + 1) / 2.0;
    final mean = n1 * n2 / 2.0;
    final observedDistance = (u - mean).abs();

    if (total <= 20) {
      var combinations = 0;
      var extreme = 0;
      final base = n1 * (n1 + 1) / 2.0;

      void enumerate(int start, int remaining, double rankSum) {
        if (remaining == 0) {
          combinations++;
          final candidateU = rankSum - base;
          if ((candidateU - mean).abs() + 1e-9 >= observedDistance) extreme++;
          return;
        }
        final last = ranks.length - remaining;
        for (var i = start; i <= last; i++) {
          enumerate(i + 1, remaining - 1, rankSum + ranks[i]);
        }
      }

      enumerate(0, n1, 0);
      if (combinations == 0) return null;
      return (extreme / combinations).clamp(0.0, 1.0).toDouble();
    }

    final tieCorrection = tieSizes.fold<int>(
      0,
      (sum, size) => sum + size * size * size - size,
    );
    final variance = n1 * n2 / 12.0 *
        ((total + 1) - tieCorrection / (total * (total - 1)));
    if (variance <= 0) return 1;
    final z = math.max(0.0, (observedDistance - 0.5) / math.sqrt(variance)).toDouble();
    final p = (2 * (1 - _normalCdf(z))).clamp(0.0, 1.0).toDouble();
    return p;
  }

  static double _normalCdf(double z) {
    final t = 1 / (1 + 0.2316419 * z);
    final polynomial = t * (0.319381530 +
        t * (-0.356563782 +
        t * (1.781477937 +
        t * (-1.821255978 + t * 1.330274429))));
    final tail = 0.3989422804014327 * math.exp(-z * z / 2) * polynomial;
    return 1 - tail;
  }
}
