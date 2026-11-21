import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_timezone/flutter_local_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final zoneName = LocalTimezone.getTimeZoneName();
    tz.setLocalLocation(tz.getLocation(zoneName));
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  Future<void> reportReady() async {
    await initialize();
    await _plugin.show(4101, 'Утренний отчёт готов',
      'Откройте «Трекер сна», чтобы посмотреть и сохранить оценку самочувствия и качества сна.',
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        android: AndroidNotificationDetails('sleep_reports', 'Отчёты сна', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
      ));
  }

  Future<void> scheduleNightReminders() async {
    await initialize();
    final now = tz.TZDateTime.now(tz.local);
    final times = <(int, int, int)>[(4200, 23, 55), (4201, 0, 0)];
    for (var minute = 30; minute <= 360; minute += 30) {
      times.add((4201 + minute ~/ 30, minute ~/ 60, minute % 60));
    }
    for (final item in times) {
      var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, item.$2, item.$3);
      if (!next.isAfter(now)) next = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, item.$2, item.$3);
      await _plugin.zonedSchedule(
        item.$1, item.$1 == 4200 ? 'Проверка перед сном' : 'Ночное наблюдение не начато',
        item.$1 == 4200
          ? 'Вы уже ложитесь спать? Откройте приложение, чтобы начать ночное наблюдение.'
          : 'Если вы уже спите, откройте Sleep Tracker и запустите запись звуковых событий.',
        next,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
          android: AndroidNotificationDetails('sleep_night', 'Ночное наблюдение', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelNextMidnightAttempt() async {
    final now = tz.TZDateTime.now(tz.local);
    if (now.hour == 23) { await _plugin.cancel(4201); return; }
    final currentMinutes = now.hour * 60 + now.minute;
    final nextSlot = ((currentMinutes ~/ 30) + 1) * 30;
    if (nextSlot <= 360) await _plugin.cancel(4201 + nextSlot ~/ 30);
  }

  Future<void> scheduleAudioExpiry(Iterable<DateTime> expiries) async {
    await initialize();
    const notificationId = 4300;
    await _plugin.cancel(notificationId);
    final future = expiries.toList()..sort();
    if (future.isEmpty) return;
    final expiry = future.first;
    final reminderAt = expiry.subtract(const Duration(hours: 24));
    final now = tz.TZDateTime.now(tz.local);
    if (!expiry.isAfter(now)) return;
    if (!reminderAt.isAfter(now)) {
      await _plugin.show(notificationId, 'Скоро удаление аудиофрагментов',
        'Один или несколько аудиофрагментов будут удалены в ближайшие 24 часа.',
        const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
          android: AndroidNotificationDetails('sleep_audio', 'Аудиофрагменты', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
        ));
      return;
    }
    await _plugin.zonedSchedule(notificationId, 'Скоро удаление аудиофрагментов',
      'Один или несколько аудиофрагментов будут автоматически удалены через 24 часа.',
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        android: AndroidNotificationDetails('sleep_audio', 'Аудиофрагменты', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
      ), androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }

  Future<void> cancelNightReminders() async {
    for (var id = 4200; id <= 4213; id++) { await _plugin.cancel(id); }
  }


}
