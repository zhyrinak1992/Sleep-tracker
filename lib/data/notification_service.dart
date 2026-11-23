import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_timezone/flutter_local_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const String _sleepStartPayload = 'sleep_start_offer';
  static const int _deferredSleepOfferId = 5099;
  final ValueNotifier<bool> sleepStartRequested = ValueNotifier<bool>(false);

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.payload == _sleepStartPayload) {
      sleepStartRequested.value = true;
    }
  }

  Future<void> initialize() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final zoneName = LocalTimezone.getTimeZoneName();
    tz.setLocalLocation(tz.getLocation(zoneName));
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse?.payload == _sleepStartPayload) {
      sleepStartRequested.value = true;
    }
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

  // Three rolling days keep 42 night reminders below iOS's pending
  // local-notification limit while leaving room for other app notifications.
  static const int _nightReminderBaseId = 5000;
  static const int _nightReminderDays = 3;
  static const List<(int, int)> _nightReminderTimes = [
    (23, 55), (0, 0), (0, 30), (1, 0), (1, 30), (2, 0), (2, 30),
    (3, 0), (3, 30), (4, 0), (4, 30), (5, 0), (5, 30), (6, 0),
  ];

  static int _nightReminderId(int dayOffset, int slotIndex) =>
      _nightReminderBaseId + dayOffset * 20 + slotIndex;

  Future<void> scheduleNightReminders() async {
    await initialize();
    await cancelNightReminders();
    final now = tz.TZDateTime.now(tz.local);
    for (var dayOffset = 0; dayOffset < _nightReminderDays; dayOffset++) {
      final day = tz.TZDateTime(tz.local, now.year, now.month, now.day + dayOffset);
      for (var slotIndex = 0; slotIndex < _nightReminderTimes.length; slotIndex++) {
        final time = _nightReminderTimes[slotIndex];
        final scheduled = tz.TZDateTime(tz.local, day.year, day.month, day.day, time.$1, time.$2);
        if (!scheduled.isAfter(now)) continue;
        final isPreSleep = slotIndex == 0;
        await _plugin.zonedSchedule(
          _nightReminderId(dayOffset, slotIndex),
          isPreSleep ? 'Проверка перед сном' : 'Ночное наблюдение не начато',
          isPreSleep
              ? 'Вы уже ложитесь спать? Откройте приложение, чтобы начать ночное наблюдение.'
              : 'Если вы уже спите, откройте Sleep Tracker и запустите запись звуковых событий.',
          scheduled,
          const NotificationDetails(
            iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
            android: AndroidNotificationDetails('sleep_night', 'Ночное наблюдение', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: _sleepStartPayload,
        );
      }
    }
  }


  /// Повторное предложение начать ночное наблюдение после выбора «Отложить».
  /// Отсрочка действует 30 минут; открытие уведомления передаёт управление
  /// приложению, где пользователь подтверждает запуск.
  Future<void> deferSleepStart() async {
    await initialize();
    await _plugin.cancel(_deferredSleepOfferId);
    final scheduled = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 30));
    await _plugin.zonedSchedule(
      _deferredSleepOfferId,
      'Ночное наблюдение отложено',
      'Готовы начать наблюдение за сном? Откройте Sleep Tracker.',
      scheduled,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        android: AndroidNotificationDetails(
          'sleep_night',
          'Ночное наблюдение',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: _sleepStartPayload,
    );
  }

  Future<void> cancelNextMidnightAttempt() async {
    await initialize();
    final now = tz.TZDateTime.now(tz.local);
    // Cancel one upcoming 00:00–06:00 half-hour slot only. All other
    // reminders, including the following night's series, remain scheduled.
    for (var dayOffset = 0; dayOffset < _nightReminderDays; dayOffset++) {
      final day = tz.TZDateTime(tz.local, now.year, now.month, now.day + dayOffset);
      for (var slotIndex = 1; slotIndex < _nightReminderTimes.length; slotIndex++) {
        final time = _nightReminderTimes[slotIndex];
        final scheduled = tz.TZDateTime(tz.local, day.year, day.month, day.day, time.$1, time.$2);
        if (scheduled.isAfter(now)) {
          await _plugin.cancel(_nightReminderId(dayOffset, slotIndex));
          return;
        }
      }
    }
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

  /// Напоминает за 24 часа до ближайшего окончательного удаления ночи.
  Future<void> scheduleTrashExpiry(Iterable<DateTime> expiries) async {
    await initialize();
    const notificationId = 4301;
    await _plugin.cancel(notificationId);
    final future = expiries.toList()..sort();
    if (future.isEmpty) return;
    final expiry = future.first;
    final reminderAt = expiry.subtract(const Duration(hours: 24));
    final now = tz.TZDateTime.now(tz.local);
    if (!expiry.isAfter(now)) return;
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      android: AndroidNotificationDetails('sleep_trash', 'Корзина записей сна', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
    );
    if (!reminderAt.isAfter(now)) {
      await _plugin.show(notificationId, 'Скоро очистка корзины', 'Одна или несколько удалённых ночей будут окончательно удалены в ближайшие 24 часа. Их ещё можно восстановить.', details);
      return;
    }
    await _plugin.zonedSchedule(notificationId, 'Скоро очистка корзины', 'Через 24 часа одна или несколько ночей будут удалены из корзины окончательно.', tz.TZDateTime.from(reminderAt, tz.local), details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }
  Future<void> cancelNightReminders() async {
    await _plugin.cancel(_deferredSleepOfferId);
    // Remove legacy repeating IDs from previous app versions.
    for (var id = 4200; id <= 4213; id++) {
      await _plugin.cancel(id);
    }
    // Remove date-specific IDs in the rolling three-day window.
    for (var id = _nightReminderBaseId;
        id < _nightReminderBaseId + _nightReminderDays * 20;
        id++) {
      await _plugin.cancel(id);
    }
  }


}
