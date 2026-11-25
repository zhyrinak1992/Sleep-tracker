import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/health/health_day_tag_library.dart';

void main() {
  group('HealthDayTagLibrary', () {
    test('decodes, trims, deduplicates and sorts saved labels', () {
      expect(
        HealthDayTagLibrary.decode('[" Кофеин ","Стресс","Кофеин","","Тренировка"]'),
        ['Кофеин', 'Стресс', 'Тренировка'],
      );
    });

    test('adds a custom label without duplicates', () {
      expect(
        HealthDayTagLibrary.add(['Стресс'], '  Перелёт  '),
        ['Перелёт', 'Стресс'],
      );
      expect(
        HealthDayTagLibrary.add(['Стресс'], 'Стресс'),
        ['Стресс'],
      );
    });

    test('renames and removes library labels without touching day entries', () {
      final originalDayTags = ['Кофеин', 'Стресс'];
      final library = ['Кофеин', 'Стресс'];
      final renamed = HealthDayTagLibrary.rename(library, 'Кофеин', 'Кофе');
      expect(renamed, ['Кофе', 'Стресс']);
      expect(HealthDayTagLibrary.remove(renamed, 'Стресс'), ['Кофе']);
      expect(originalDayTags, ['Кофеин', 'Стресс']);
    });

    test('rejects empty or duplicate rename targets', () {
      expect(
        () => HealthDayTagLibrary.rename(['Кофеин'], 'Кофеин', '  '),
        throwsArgumentError,
      );
      expect(
        () => HealthDayTagLibrary.rename(['Кофеин', 'Стресс'], 'Кофеин', 'Стресс'),
        throwsArgumentError,
      );
    });

    test('does not silently replace a damaged library', () {
      expect(
        () => HealthDayTagLibrary.decode('{"not":"a list"}'),
        throwsFormatException,
      );
    });

    test('encodes a normalized reusable list', () {
      expect(
        HealthDayTagLibrary.encode([' Стресс ', 'Кофеин', 'Стресс', '']),
        '["Кофеин","Стресс"]',
      );
    });
  });
}
