import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/analysis/sleep_recommendation_text.dart';

void main() {
  group('SleepRecommendationText', () {
    test('suggests checking caffeine timing when awakenings are higher', () {
      final text = SleepRecommendationText.forObservedPattern(
        tagLabel: 'Кофеин',
        metricKey: 'awakenings',
        difference: 1.5,
      );

      expect(text, contains('времени последнего кофеина'));
      expect(text, contains('не доказывает причину'));
    });

    test('suggests tracking dinner timing for shorter sleep', () {
      final text = SleepRecommendationText.forObservedPattern(
        tagLabel: 'Поздний ужин',
        metricKey: 'duration',
        difference: -35,
      );

      expect(text, contains('время ужина'));
      expect(text, contains('более ранним и поздним'));
    });

    test('does not recommend changing illness or medication circumstances', () {
      final text = SleepRecommendationText.forObservedPattern(
        tagLabel: 'Болезнь',
        metricKey: 'score',
        difference: -8,
      );

      expect(text, contains('продолжить отмечать этот фактор'));
      expect(text, isNot(contains('изменить')));
    });

    test('does not create recommendations without a directional sleep metric', () {
      expect(
        SleepRecommendationText.forObservedPattern(
          tagLabel: 'Кофеин',
          metricKey: 'roomTemperature',
          difference: 1.2,
        ),
        isNull,
      );
      expect(
        SleepRecommendationText.forObservedPattern(
          tagLabel: 'Кофеин',
          metricKey: 'awakenings',
          difference: 0,
        ),
        isNull,
      );
    });

    test('does not advise changing a factor when its observed metric is better', () {
      final text = SleepRecommendationText.forObservedPattern(
        tagLabel: 'Кофеин',
        metricKey: 'sleepLatency',
        difference: -12,
      );

      expect(text, contains('более благоприятным значением'));
      expect(text, contains('не доказывает причинную связь'));
    });
  });
}
