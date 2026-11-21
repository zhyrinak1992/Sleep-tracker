import 'package:flutter/material.dart';
import 'app.dart';
import 'data/notification_service.dart';
import 'data/sleep_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  await SleepDatabase.instance.deleteExpiredAudioEvents(DateTime.now());
  final openSession = await SleepDatabase.instance.getOpenSession();
  if (openSession == null) await NotificationService.instance.scheduleNightReminders();
  final events = await SleepDatabase.instance.getAudioEvents();
  await NotificationService.instance.scheduleAudioExpiry(events.map((event) => DateTime.parse(event['expires_at']! as String)));
  runApp(const SleepTrackerApp());
}
