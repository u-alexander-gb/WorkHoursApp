import 'reminder_service.dart';
import 'reminder_settings.dart';
import 'work_repository.dart';

class ReminderScheduler {
  const ReminderScheduler(this.reminders);

  final ReminderPort reminders;

  Future<void> reschedule({
    required WorkShift shift,
    required ReminderSettings settings,
    required DateTime now,
    required String languageCode,
  }) async {
    await reminders.cancel(shift.id);
    if (shift.status == ShiftStatus.cancelled ||
        shift.status == ShiftStatus.completed) {
      return;
    }

    if (settings.startEnabled && shift.plannedStart.isAfter(now)) {
      await reminders.schedule(
        shiftId: shift.id,
        when: settings.when(shift.plannedStart, settings.startTiming),
        projectName: shift.projectName,
        kind: shift.status == ShiftStatus.planned
            ? ReminderKind.checkIn
            : ReminderKind.start,
        languageCode: languageCode,
      );
    }

    if (settings.endEnabled && shift.status != ShiftStatus.planned) {
      final due =
          shift.plannedEnd ?? shift.plannedStart.add(const Duration(hours: 8));
      await reminders.schedule(
        shiftId: shift.id,
        when: settings.when(due, settings.endTiming),
        projectName: shift.projectName,
        kind: ReminderKind.checkOut,
        languageCode: languageCode,
      );
    }
  }
}
