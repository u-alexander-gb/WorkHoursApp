import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_text.dart';

class ReminderResult {
  const ReminderResult({required this.scheduled, required this.exact});
  final bool scheduled;
  final bool exact;
}

enum ReminderKind { checkIn, start, checkOut }

class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  void Function()? onTap;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => onTap?.call(),
    );
  }

  Future<ReminderResult> schedule({
    required String shiftId,
    required DateTime when,
    required String projectName,
    required ReminderKind kind,
    required String languageCode,
  }) async {
    if (!Platform.isAndroid || !when.isAfter(DateTime.now())) {
      return const ReminderResult(scheduled: false, exact: false);
    }
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final allowed = await android?.requestNotificationsPermission();
    if (allowed == false) {
      return const ReminderResult(scheduled: false, exact: false);
    }
    var exact = await android?.canScheduleExactNotifications() ?? false;
    if (!exact) {
      await android?.requestExactAlarmsPermission();
      exact = await android?.canScheduleExactNotifications() ?? false;
    }
    final title = switch (kind) {
      ReminderKind.checkIn => 'Напоминание о начале смены',
      ReminderKind.start => 'Работа начинается',
      ReminderKind.checkOut => 'Пора сделать check-out',
    };
    final body = switch (kind) {
      ReminderKind.checkIn => 'Проверьте расписание и сделайте check-in.',
      ReminderKind.start => 'Начало учёта часов по плану. Подтверждение не требуется.',
      ReminderKind.checkOut => 'Смена ещё не завершена.',
    };
    await _plugin.zonedSchedule(
      id: _notificationId(shiftId, kind),
      title: appTextForLanguage(languageCode, title),
      body: '$projectName: ${appTextForLanguage(languageCode, body)}',
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kind == ReminderKind.checkOut ? 'shift_end' : 'shift_start',
          appTextForLanguage(languageCode,
              kind == ReminderKind.checkOut ? 'Конец смены' : 'Начало смены'),
          channelDescription: kind == ReminderKind.checkOut
              ? appTextForLanguage(languageCode, 'Напоминания о завершении работы')
              : appTextForLanguage(languageCode, 'Напоминания о начале работы'),
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: shiftId,
    );
    return ReminderResult(scheduled: true, exact: exact);
  }

  Future<void> cancel(String shiftId) async {
    if (!Platform.isAndroid) return;
    await initialize();
    await _plugin.cancel(id: _notificationId(shiftId, ReminderKind.checkIn));
    await _plugin.cancel(id: _notificationId(shiftId, ReminderKind.checkOut));
  }

  int _notificationId(String shiftId, ReminderKind kind) =>
      ((int.parse(shiftId.substring(0, 8), radix: 16) & 0x3fffffff) * 2) +
      (kind == ReminderKind.checkOut ? 1 : 0);
}
