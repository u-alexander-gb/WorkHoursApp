import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  late WorkRepository repository;

  setUp(() async => repository = await WorkRepository.openInMemory());
  tearDown(() async => repository.close());

  test('plan can move to another day and keeps its change history', () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    final firstDay = DateTime.now().add(const Duration(days: 1));
    final secondDay = firstDay.add(const Duration(days: 2));
    final id = await repository.planShift(
      projectId: project.id,
      start: firstDay,
      end: firstDay.add(const Duration(hours: 8)),
    );

    await repository.updatePlannedShift(
      shiftId: id,
      projectId: project.id,
      plannedStart: secondDay,
      plannedEnd: secondDay.add(const Duration(hours: 8)),
      reason: 'Перенесли рабочий день',
    );

    final shift = (await repository.shifts()).single;
    expect(shift.plannedStart.day, secondDay.day);
    final history = await repository.shiftEvents(id);
    expect(history.first.reason, 'Перенесли рабочий день');
    expect(history.first.before!['planned_start_ms'],
        firstDay.millisecondsSinceEpoch);
    expect(history.first.after!['planned_start_ms'],
        secondDay.millisecondsSinceEpoch);
  });

  test('cancelled plan remains visible in history and backup', () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    final start = DateTime.now().add(const Duration(days: 1));
    final id = await repository.planShift(projectId: project.id, start: start);

    await repository.cancelPlannedShift(id, 'Выходной');

    expect((await repository.shifts()).single.status, ShiftStatus.cancelled);
    final history = await repository.shiftEvents(id);
    expect(history.first.kind, 'cancelled');
    expect(history.first.reason, 'Выходной');
    await repository.restoreBackup(await repository.exportBackup());
    expect((await repository.shifts()).single.status, ShiftStatus.cancelled);
    expect((await repository.shiftEvents(id)).first.reason, 'Выходной');
  });

  test('after check-in a shift cannot be cancelled or moved to another day',
      () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    await repository.addRate(
      projectId: project.id,
      name: 'Сбор',
      centsPerHour: 1500,
    );
    final rate = (await repository.rates(project.id)).single;
    final start = DateTime.now().add(const Duration(days: 1));
    final end = start.add(const Duration(hours: 8));
    final id = await repository.planShift(
      projectId: project.id,
      start: start,
      end: end,
    );
    await repository.armShift(id, rate.id);

    await expectLater(
      repository.cancelPlannedShift(id, 'Нельзя'),
      throwsStateError,
    );
    await expectLater(
      repository.updateArmedShift(
        shiftId: id,
        plannedStart: start.add(const Duration(days: 1)),
        plannedEnd: end.add(const Duration(days: 1)),
        rateId: rate.id,
        reason: 'Нельзя',
      ),
      throwsStateError,
    );
    expect((await repository.shifts()).single.status, ShiftStatus.armed);
    expect((await repository.shiftEvents(id)).length, 2);
  });
}
