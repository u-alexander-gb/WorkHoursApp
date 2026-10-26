import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderResult {
  const ReminderResult({required this.scheduled, required this.exact});
  final bool scheduled;
  final bool exact;
}

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
    required DateTime start,
    required String projectName,
  }) async {
    if (!Platform.isAndroid || !start.isAfter(DateTime.now())) {
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
    await _plugin.zonedSchedule(
      id: _notificationId(shiftId),
      title: 'Пора подтвердить начало работы',
      body: '$projectName: вы на месте?',
      scheduledDate: tz.TZDateTime.from(start, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'shift_start',
          'Начало смены',
          channelDescription: 'Напоминания о подтверждении начала работы',
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
    await _plugin.cancel(id: _notificationId(shiftId));
  }

  int _notificationId(String shiftId) =>
      int.parse(shiftId.substring(0, 8), radix: 16) & 0x7fffffff;
}
