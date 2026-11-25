import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/notification_service.dart';
import 'data/audio_observation_service.dart';
import 'data/climate_polling_policy.dart';
import 'data/sleep_database.dart';
import 'data/yandex_smart_home_service.dart';
import 'features/home/home_screen.dart';
import 'features/diary/diary_screen.dart';
import 'features/analysis/analysis_screen.dart';
import 'features/health/health_screen.dart';
import 'features/health/health_day_tag_monthly_report.dart';
import 'features/notes/notes_screen.dart';
import 'features/settings/settings_screen.dart';
import 'theme/app_theme.dart';
import 'features/security/app_lock_gate.dart';

class SleepTrackerApp extends StatelessWidget {
  const SleepTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // In release builds Flutter's default error widget can appear as a
    // featureless grey rectangle. Show the actual exception instead.
    ErrorWidget.builder = (details) => Material(
      color: AppTheme.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            'Не удалось отобразить этот экран.\n\n${details.exceptionAsString()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );

    return MaterialApp(
      title: 'Трекер сна',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
      locale: const Locale('ru', 'RU'),
      home: const AppLockGate(child: AppShell()),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  final _database = SleepDatabase.instance;
  final List<Widget?> _pages = List<Widget?>.filled(6, null);
  Timer? _cleanupTimer;
  Timer? _climateTimer;
  bool _climateRefreshInProgress = false;

  Widget _createPage(int index) {
    switch (index) {
      case 0:
        return HomeScreen(database: _database);
      case 1:
        return AnalysisScreen(database: _database);
      case 2:
        return DiaryScreen(database: _database);
      case 3:
        return NotesScreen(database: _database);
      case 4:
        return HealthScreen(database: _database);
      case 5:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) { _cleanupAudio(); _cleanupTrash(); });
    _cleanupTrash();
    _startClimatePolling();
    _ensureNightReminders();
    _generateClosedHealthTagReports();
  }

  Future<void> _ensureNightReminders() async {
    try {
      final openSession = await _database.getOpenSession();
      if (openSession == null) {
        await NotificationService.instance.scheduleNightReminders();
      } else {
        await NotificationService.instance.cancelNightReminders();
        try {
          await AudioObservationService.instance.recoverObservationIfNeeded();
        } catch (error, stackTrace) {
          debugPrint('Could not recover active night audio: $error\\n$stackTrace');
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Night reminder scheduling failed: $error\\n$stackTrace');
    }
  }

  void _startClimatePolling() {
    _climateTimer?.cancel();
    _refreshClimate();
    _climateTimer = Timer.periodic(const Duration(minutes: 15), (_) => _refreshClimate());
  }

  void _stopClimatePolling() {
    _climateTimer?.cancel();
    _climateTimer = null;
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _stopClimatePolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _cleanupAudio() async {
    try {
      await _database.deleteExpiredAudioEvents(DateTime.now());
      final events = await _database.getAudioEvents();
      await NotificationService.instance.scheduleAudioExpiry(
        events.map((row) => DateTime.parse(row['expires_at']! as String)),
      );
    } catch (error, stackTrace) {
      debugPrint('Audio cleanup failed: $error\n$stackTrace');
    }
  }

  Future<void> _cleanupTrash() async {
    try {
      await _database.purgeExpiredTrash();
      final expiries = await _database.getTrashExpiryDates();
      await NotificationService.instance.scheduleTrashExpiry(expiries);
    } catch (error, stackTrace) {
      debugPrint('Trash cleanup failed: $error\\n$stackTrace');
    }
  }

  Future<void> _generateClosedHealthTagReports() async {
    try {
      await HealthDayTagMonthlyReportService(_database).generateClosedReports();
    } catch (error, stackTrace) {
      debugPrint('Monthly health tag report generation failed: $error\\n$stackTrace');
    }
  }
  Future<void> _refreshClimate() async {
    if (_climateRefreshInProgress) return;
    _climateRefreshInProgress = true;
    try {
      await YandexSmartHomeService.instance.refreshConfiguredDeviceIfNeeded();
    } catch (error, stackTrace) {
      debugPrint('Yandex climate sampling failed: $error\\n$stackTrace');
    } finally {
      _climateRefreshInProgress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClimatePolling();
      _cleanupAudio();
      _cleanupTrash();
      _ensureNightReminders();
      _generateClosedHealthTagReports();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final keepPollingForActiveNight =
          state != AppLifecycleState.detached &&
          shouldKeepClimatePollingInBackground(
            audioObservationActive: AudioObservationService.instance.observing.value,
            audioObservationPaused: AudioObservationService.instance.paused.value,
          );
      if (!keepPollingForActiveNight) _stopClimatePolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    _pages[_index] ??= _createPage(_index);
    final pages = List<Widget>.generate(
      _pages.length,
      (index) => _pages[index] ?? const SizedBox.shrink(),
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF10132F),
              AppTheme.background,
              Color(0xFF11152F),
            ],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: IndexedStack(index: _index, children: pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nightlight_round), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Анализ'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Дневник'),
          NavigationDestination(icon: Icon(Icons.sticky_note_2_outlined), label: 'Заметки'),
          NavigationDestination(icon: Icon(Icons.favorite_outline_rounded), label: 'Здоровье'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
      ),
    );
  }
}
