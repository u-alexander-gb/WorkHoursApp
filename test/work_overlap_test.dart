import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  late WorkRepository repository;
  setUp(() async => repository = await WorkRepository.openInMemory());
  tearDown(() async => repository.close());

  test('worked intervals cannot overlap across midnight', () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day - 1);
    final firstStart = midnight.subtract(const Duration(hours: 2));
    final firstEnd = midnight.add(const Duration(hours: 1));
    final firstId = await repository.planShift(
        projectId: project.id, start: firstStart, end: firstEnd);
    await repository.armShift(firstId, null);
    await repository.confirmStart(firstId, firstStart);
    await repository.checkOut(firstId, firstEnd, breakMinutes: 0);

    final secondStart = firstEnd.subtract(const Duration(minutes: 30));
    final secondId = await repository.planShift(
        projectId: project.id, start: secondStart);
    await repository.armShift(secondId, null);
    await expectLater(repository.confirmStart(secondId, secondStart),
        throwsStateError);
    expect((await repository.shifts())
        .singleWhere((shift) => shift.id == secondId).status,
        ShiftStatus.armed);
  });

  test('reasons for actual times survive backup and restore', () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    final start = DateTime.now().subtract(const Duration(hours: 3));
    final end = start.add(const Duration(hours: 2));
    final id = await repository.planShift(projectId: project.id, start: start);
    await repository.armShift(id, null);
    await repository.confirmStart(id, start, reason: 'Пробка');
    await repository.checkOut(id, end,
        breakMinutes: 0, reason: 'Закончил раньше');

    await repository.restoreBackup(await repository.exportBackup());
    final events = await repository.shiftEvents(id);
    expect(events.first.reason, 'Закончил раньше');
    expect(events[1].reason, 'Пробка');
  });
}
