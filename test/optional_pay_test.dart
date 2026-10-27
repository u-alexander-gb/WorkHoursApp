import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/report_csv.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  late WorkRepository repository;
  setUp(() async => repository = await WorkRepository.openInMemory());
  tearDown(() async => repository.close());

  test('hours can be recorded and exported without any tariff', () async {
    await repository.addProject('Волонтёрская работа');
    final project = (await repository.projects()).single;
    expect(project.trackPay, isFalse);
    final start = DateTime.now().subtract(const Duration(hours: 3));
    final id = await repository.planShift(
      projectId: project.id,
      start: start,
      end: start.add(const Duration(hours: 4)),
    );

    await repository.armShift(id, null);
    await repository.confirmStart(id, start);
    await repository.checkOut(id, start.add(const Duration(hours: 2)),
        breakMinutes: 15);

    final shift = (await repository.shifts()).single;
    expect(shift.paidMinutes, 105);
    expect(shift.rateId, isNull);
    expect(shift.earnedCents, 0);
    final csv = buildReportCsv([shift]);
    expect(csv, contains('Всего часов;;;;;105'));
    expect(csv, isNot(contains('0,00;EUR')));
    await repository.restoreBackup(await repository.exportBackup());
    expect((await repository.projects()).single.trackPay, isFalse);
    expect((await repository.shifts()).single.paidMinutes, 105);
  });

  test('enabling pay affects new shifts and preserves existing time-only shifts',
      () async {
    await repository.addProject('Combo BV');
    final project = (await repository.projects()).single;
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final timeOnlyId = await repository.planShift(
        projectId: project.id, start: start);
    await repository.armShift(timeOnlyId, null);
    await repository.confirmStart(timeOnlyId, start);
    await repository.checkOut(timeOnlyId, start.add(const Duration(hours: 1)),
        breakMinutes: 0);

    await repository.setProjectPayTracking(project.id, true);
    await repository.addRate(
        projectId: project.id, name: 'Сбор', centsPerHour: 1500);
    final nextStart = DateTime.now().add(const Duration(days: 1));
    final paidId = await repository.planShift(
        projectId: project.id, start: nextStart);
    await expectLater(repository.armShift(paidId, null), throwsStateError);
    await repository.armShift(paidId, (await repository.rates(project.id)).single.id);

    final shifts = await repository.shifts();
    expect(shifts.singleWhere((s) => s.id == timeOnlyId).rateId, isNull);
    expect(shifts.singleWhere((s) => s.id == paidId).rateCentsPerHour, 1500);
  });

  test('older backup defaults existing projects to pay tracking', () async {
    await repository.addProject('Старый проект', trackPay: true);
    final backup = jsonDecode(await repository.exportBackup())
        as Map<String, dynamic>;
    backup['version'] = 2;
    final tables = backup['tables'] as Map<String, dynamic>;
    for (final row in tables['projects'] as List) {
      (row as Map<String, dynamic>).remove('track_pay');
    }
    await repository.restoreBackup(jsonEncode(backup));
    expect((await repository.projects()).single.trackPay, isTrue);
  });
}
