import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/features/diary/diary_screen.dart';
import 'package:sleep_tracker/theme/app_theme.dart';

void main() {
  group('SleepCalendarScorePalette', () {
    test('maps scores below 60 to the low-score band', () {
      expect(SleepCalendarScorePalette.colorFor(0), const Color(0xFFE58B91));
      expect(SleepCalendarScorePalette.colorFor(59.99), const Color(0xFFE58B91));
    });

    test('maps scores from 60 through 79.99 to the middle band', () {
      expect(SleepCalendarScorePalette.colorFor(60), const Color(0xFFE6BC70));
      expect(SleepCalendarScorePalette.colorFor(79.99), const Color(0xFFE6BC70));
    });

    test('maps scores from 80 through 100 to the high-score band', () {
      expect(SleepCalendarScorePalette.colorFor(80), AppTheme.teal);
      expect(SleepCalendarScorePalette.colorFor(100), AppTheme.teal);
    });

    test('uses neutral color for missing or invalid values', () {
      expect(SleepCalendarScorePalette.colorFor(null), AppTheme.muted);
      expect(SleepCalendarScorePalette.colorFor(-0.1), AppTheme.muted);
      expect(SleepCalendarScorePalette.colorFor(100.1), AppTheme.muted);
      expect(SleepCalendarScorePalette.colorFor(double.nan), AppTheme.muted);
      expect(SleepCalendarScorePalette.colorFor(double.infinity), AppTheme.muted);
    });
  });
}
