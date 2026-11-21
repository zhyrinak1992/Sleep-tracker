import 'dart:async';
import 'package:flutter/material.dart';
import 'data/notification_service.dart';
import 'data/sleep_database.dart';
import 'features/home/home_screen.dart';
import 'features/diary/diary_screen.dart';
import 'features/analysis/analysis_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/settings/settings_screen.dart';
import 'theme/app_theme.dart';

class SleepTrackerApp extends StatelessWidget {
  const SleepTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Трекер сна',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
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
  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) => _cleanupAudio());
  }

  @override
  void dispose() { _cleanupTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  Future<void> _cleanupAudio() async {
    await _database.deleteExpiredAudioEvents(DateTime.now());
    final events = await _database.getAudioEvents();
    await NotificationService.instance.scheduleAudioExpiry(events.map((row) => DateTime.parse(row['expires_at']! as String)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cleanupAudio();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(database: _database),
      AnalysisScreen(database: _database),
      DiaryScreen(database: _database),
      NotesScreen(database: _database),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nightlight_round), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Анализ'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Дневник'),
          NavigationDestination(icon: Icon(Icons.sticky_note_2_outlined), label: 'Заметки'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
      ),
    );
  }
}
