import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/models/sleep_tag.dart';

void main() {
  test('каталог тегов содержит уникальные стабильные ключи', () {
    final keys = SleepTag.catalog.map((tag) => tag.key).toList();
    expect(keys.toSet().length, keys.length);
    expect(SleepTag.byKey('stress')?.label, 'Стресс');
    expect(SleepTag.byKey('unknown'), isNull);
  });
}
