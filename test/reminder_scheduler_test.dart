import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/reminder_scheduler.dart';
import 'package:work_hours_app/src/reminder_service.dart';
import 'package:work_hours_app/src/reminder_settings.dart';
import 'package:work_hours_app/src/work_repository.dart';

class _FakeReminders implements ReminderPort {
  final List<String> calls = [];
  final List<({ReminderKind kind, DateTime when})> scheduled = [];

  @override
  Future<void> cancel(String shiftId) async => calls.add('cancel:$shiftId');

  @override
  Future<ReminderResult> schedule({
    required String shiftId,
    required DateTime when,
    required String projectName,
    required ReminderKind kind,
    required String languageCode,
  }) async {
    calls.add('schedule:$shiftId:${kind.name}');
    scheduled.add((kind: kind, when: when));
    return const ReminderResult(scheduled: true, exact: true);
  }
}

WorkShift _shift({
  required ShiftStatus status,
  required DateTime start,
  DateTime? end,
}) => WorkShift(
  id: '0123456789abcdef',
  rowId: 1,
  projectId: 'project',
  projectName: 'Project',
  status: status,
  plannedStart: start,
  plannedEnd: end,
  rateId: null,
  rateName: null,
  rateCentsPerHour: null,
  currency: null,
  preCheckInAt: null,
  confirmedAt: null,
  creditedStart: null,
  checkedOutAt: null,
  creditedEnd: null,
  breakMinutes: 0,
);

void main() {
  final now = DateTime(2026, 11, 9, 8);

  test('rescheduling a planned shift cancels old reminders first', () async {
    final fake = _FakeReminders();
    final start = now.add(const Duration(hours: 2));

    await ReminderScheduler(fake).reschedule(
      shift: _shift(status: ShiftStatus.planned, start: start),
      settings: const ReminderSettings(),
      now: now,
      languageCode: 'ru',
    );

    expect(fake.calls, [
      'cancel:0123456789abcdef',
      'schedule:0123456789abcdef:checkIn',
    ]);
  });

  test(
    'cancelled shifts keep reminders cancelled and are not rescheduled',
    () async {
      final fake = _FakeReminders();

      await ReminderScheduler(fake).reschedule(
        shift: _shift(
          status: ShiftStatus.cancelled,
          start: now.add(const Duration(hours: 2)),
        ),
        settings: const ReminderSettings(),
        now: now,
        languageCode: 'ru',
      );

      expect(fake.calls, ['cancel:0123456789abcdef']);
    },
  );

  test(
    'active shifts get a start and checkout reminder after rescheduling',
    () async {
      final fake = _FakeReminders();
      final start = now.add(const Duration(hours: 2));
      final end = start.add(const Duration(hours: 8));

      await ReminderScheduler(fake).reschedule(
        shift: _shift(status: ShiftStatus.active, start: start, end: end),
        settings: const ReminderSettings(),
        now: now,
        languageCode: 'ru',
      );

      expect(fake.scheduled.map((item) => item.kind), [
        ReminderKind.start,
        ReminderKind.checkOut,
      ]);
    },
  );

  test(
    'completed shifts cancel both old reminders without scheduling new ones',
    () async {
      final fake = _FakeReminders();

      await ReminderScheduler(fake).reschedule(
        shift: _shift(
          status: ShiftStatus.completed,
          start: now.subtract(const Duration(hours: 2)),
        ),
        settings: const ReminderSettings(),
        now: now,
        languageCode: 'ru',
      );

      expect(fake.calls, ['cancel:0123456789abcdef']);
      expect(fake.scheduled, isEmpty);
    },
  );
}
