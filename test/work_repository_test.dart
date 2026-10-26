import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/report_csv.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkRepository repository;

  setUp(() async {
    repository = await WorkRepository.openInMemory();
  });

  tearDown(() async {
    await repository.close();
  });

  test('planned work is unpaid until check-out', () async {
    await repository.addProject('Combo BV — сбор ягод');
    final project = (await repository.projects()).single;
    await repository.addRate(
      projectId: project.id,
      name: 'Сбор',
      centsPerHour: 1500,
    );
    await repository.addRate(
      projectId: project.id,
      name: 'Сортировка',
      centsPerHour: 1700,
    );
    final rate = (await repository.rates(project.id))
        .firstWhere((item) => item.name == 'Сбор');
    final start = DateTime.now().subtract(const Duration(hours: 9));
    final end = start.add(const Duration(hours: 8));

    await repository.planShift(projectId: project.id, start: start, end: end);
    var shift = (await repository.shifts()).single;
    expect(shift.status, ShiftStatus.planned);
    expect(shift.earnedCents, 0);

    await repository.armShift(shift.id, rate.id);
    shift = (await repository.shifts()).single;
    expect(shift.status, ShiftStatus.armed);
    expect(shift.rateName, 'Сбор');
    expect(shift.earnedCents, 0);

    await repository.confirmStart(shift.id, start);
    shift = (await repository.shifts()).single;
    expect(shift.status, ShiftStatus.active);
    expect(shift.earnedCents, 0);

    await repository.checkOut(shift.id, end, breakMinutes: 30);
    shift = (await repository.shifts()).single;
    expect(shift.status, ShiftStatus.completed);
    expect(shift.paidMinutes, 450);
    expect(shift.earnedCents, 11250);
  });

  test('a rate from another project cannot be selected', () async {
    await repository.addProject('Проект A');
    await repository.addProject('Проект B');
    final projects = await repository.projects();
    await repository.addRate(
      projectId: projects[1].id,
      name: 'Чужой тариф',
      centsPerHour: 2000,
    );
    final foreignRate = (await repository.rates(projects[1].id)).single;
    await repository.planShift(
      projectId: projects[0].id,
      start: DateTime.now().add(const Duration(days: 1)),
    );
    final shift = (await repository.shifts()).single;

    await expectLater(
      repository.armShift(shift.id, foreignRate.id),
      throwsStateError,
    );
    expect((await repository.shifts()).single.status, ShiftStatus.planned);
  });

  test('break cannot exceed elapsed time', () async {
    await repository.addProject('Проект');
    final project = (await repository.projects()).single;
    await repository.addRate(
      projectId: project.id,
      name: 'Обычный',
      centsPerHour: 1000,
    );
    final rate = (await repository.rates(project.id)).single;
    final start = DateTime.now().subtract(const Duration(hours: 2));
    await repository.planShift(projectId: project.id, start: start);
    final id = (await repository.shifts()).single.id;
    await repository.armShift(id, rate.id);
    await repository.confirmStart(id, start);

    await expectLater(
      repository.checkOut(id, start.add(const Duration(hours: 1)),
          breakMinutes: 61),
      throwsArgumentError,
    );
    expect((await repository.shifts()).single.status, ShiftStatus.active);
  });

  test('backup restores projects, rates, shifts and events', () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    await repository.addRate(
      projectId: project.id,
      name: 'Сбор',
      centsPerHour: 1500,
    );
    final rate = (await repository.rates(project.id)).single;
    final start = DateTime.now().subtract(const Duration(hours: 8));
    await repository.planShift(projectId: project.id, start: start);
    final id = (await repository.shifts()).single.id;
    await repository.armShift(id, rate.id);
    await repository.confirmStart(id, start);
    await repository.checkOut(id, start.add(const Duration(hours: 7)),
        breakMinutes: 30);
    final backup = await repository.exportBackup();

    await repository.addProject('Лишний проект');
    await repository.restoreBackup(backup);

    expect((await repository.projects()).map((p) => p.name), ['Combo BV']);
    expect((await repository.rates(project.id)).single.name, 'Сбор');
    expect((await repository.shifts()).single.earnedCents, 9750);
    final restored = jsonDecode(await repository.exportBackup());
    expect((restored['tables']['shift_events'] as List).length, 4);
  });

  test('failed restore keeps existing data', () async {
    await repository.addProject('Существующий проект');
    final backup = jsonDecode(await repository.exportBackup()) as Map<String, dynamic>;
    final tables = backup['tables'] as Map<String, dynamic>;
    (tables['rates'] as List).add({
      'id': 'invalid',
      'project_id': 'missing',
      'name': 'Тариф',
      'cents_per_hour': 1000,
      'currency': 'EUR',
      'archived': 0,
    });

    await expectLater(repository.restoreBackup(jsonEncode(backup)), throwsA(isA<Exception>()));
    expect((await repository.projects()).single.name, 'Существующий проект');
  });

  test('CSV report escapes names and includes totals', () async {
    await repository.addProject('Combo; "BV"');
    final project = (await repository.projects()).single;
    await repository.addRate(
      projectId: project.id,
      name: 'Сбор',
      centsPerHour: 1500,
    );
    final rate = (await repository.rates(project.id)).single;
    final start = DateTime.now().subtract(const Duration(hours: 2));
    await repository.planShift(projectId: project.id, start: start);
    final id = (await repository.shifts()).single.id;
    await repository.armShift(id, rate.id);
    await repository.confirmStart(id, start);
    await repository.checkOut(id, start.add(const Duration(hours: 1)),
        breakMinutes: 0);

    final csv = buildReportCsv(await repository.shifts());
    expect(csv, contains('"Combo; ""BV"""'));
    expect(csv, contains('Итого;;;;;60;;EUR;15,00'));
  });
}
