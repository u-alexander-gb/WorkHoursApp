import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_hours_app/src/report_csv.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shift corrections', () {
    late WorkRepository repository;

    setUp(() async => repository = await WorkRepository.openInMemory());
    tearDown(() async => repository.close());

    test('planned shift can change project and time with an audit event', () async {
      await repository.addProject('Первый');
      await repository.addProject('Второй');
      final projects = await repository.projects();
      final first = projects.singleWhere((p) => p.name == 'Первый');
      final second = projects.singleWhere((p) => p.name == 'Второй');
      final start = DateTime.now().add(const Duration(days: 1));
      await repository.planShift(projectId: first.id, start: start);
      final id = (await repository.shifts()).single.id;
      final changedStart = start.add(const Duration(hours: 2));

      await expectLater(
        repository.updatePlannedShift(
          shiftId: id,
          projectId: second.id,
          plannedStart: changedStart,
          plannedEnd: changedStart.subtract(const Duration(minutes: 1)),
          reason: 'Неверное время',
        ),
        throwsArgumentError,
      );
      expect((await repository.shiftEvents(id)).length, 1);

      await repository.updatePlannedShift(
        shiftId: id,
        projectId: second.id,
        plannedStart: changedStart,
        plannedEnd: changedStart.add(const Duration(hours: 6)),
        reason: 'Сменили проект',
      );

      final shift = (await repository.shifts()).single;
      expect(shift.projectName, 'Второй');
      expect(shift.plannedStart.millisecondsSinceEpoch,
          changedStart.millisecondsSinceEpoch);
      final events = await repository.shiftEvents(id);
      expect(events.first.kind, 'corrected');
      expect(events.first.before!['project_id'], first.id);
      expect(events.first.after!['project_id'], second.id);
      expect(events.first.reason, 'Сменили проект');
      expect(events.last.kind, 'planned');
    });

    test('armed correction preserves check-in and rejects another project rate', () async {
      await repository.addProject('A');
      await repository.addProject('B');
      final a = (await repository.projects()).firstWhere((p) => p.name == 'A');
      final b = (await repository.projects()).firstWhere((p) => p.name == 'B');
      for (final name in ['Обычный', 'Вечерний']) {
        await repository.addRate(projectId: a.id, name: name, centsPerHour: 1500);
      }
      await repository.addRate(
          projectId: b.id, name: 'Чужой', centsPerHour: 3000);
      final rates = await repository.rates(a.id);
      final firstRate = rates.first;
      final secondRate = rates.last;
      final foreignRate = (await repository.rates(b.id)).single;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10);
      await repository.planShift(projectId: a.id, start: start);
      final id = (await repository.shifts()).single.id;
      await repository.armShift(id, firstRate.id);
      final checkInAt = (await repository.shifts()).single.preCheckInAt;

      await expectLater(
        repository.updateArmedShift(
          shiftId: id,
          plannedStart: start,
          plannedEnd: start.add(const Duration(hours: 8)),
          rateId: foreignRate.id,
          reason: 'Проверка тарифа',
        ),
        throwsStateError,
      );
      expect((await repository.shiftEvents(id)).length, 2);

      final changedStart = start.add(const Duration(hours: 1));
      await repository.updateArmedShift(
        shiftId: id,
        plannedStart: changedStart,
        plannedEnd: changedStart.add(const Duration(hours: 8)),
        rateId: secondRate.id,
        reason: 'Другое время и тариф',
      );
      final shift = (await repository.shifts()).single;
      expect(shift.preCheckInAt, checkInAt);
      expect(shift.rateId, secondRate.id);
      expect(shift.plannedStart.millisecondsSinceEpoch,
          changedStart.millisecondsSinceEpoch);
      expect((await repository.shiftEvents(id)).first.kind, 'corrected');
    });

    test('completed correction recalculates reports without changing event times', () async {
      await repository.addProject('Combo BV');
      final project = (await repository.projects()).single;
      await repository.addRate(
          projectId: project.id, name: 'Сбор', centsPerHour: 1500);
      await repository.addRate(
          projectId: project.id, name: 'Сортировка', centsPerHour: 2000);
      final rates = await repository.rates(project.id);
      final firstRate = rates.firstWhere((r) => r.name == 'Сбор');
      final secondRate = rates.firstWhere((r) => r.name == 'Сортировка');
      final start = DateTime.now().subtract(const Duration(hours: 8));
      await repository.planShift(projectId: project.id, start: start);
      final id = (await repository.shifts()).single.id;
      await repository.armShift(id, firstRate.id);
      await repository.confirmStart(id, start);
      await repository.checkOut(id, start.add(const Duration(hours: 7)),
          breakMinutes: 0);
      final original = (await repository.shifts()).single;

      await expectLater(
        repository.correctWorkedShift(
          shiftId: id,
          creditedStart: start,
          creditedEnd: start.add(const Duration(hours: 1)),
          breakMinutes: 61,
          rateId: secondRate.id,
          reason: 'Неверный перерыв',
        ),
        throwsArgumentError,
      );
      expect((await repository.shiftEvents(id)).length, 4);

      await repository.correctWorkedShift(
        shiftId: id,
        creditedStart: start.add(const Duration(hours: 1)),
        creditedEnd: start.add(const Duration(hours: 6)),
        breakMinutes: 30,
        rateId: secondRate.id,
        reason: 'Уточнил табель',
      );

      final corrected = (await repository.shifts()).single;
      expect(corrected.paidMinutes, 270);
      expect(corrected.earnedCents, 9000);
      expect(corrected.confirmedAt, original.confirmedAt);
      expect(corrected.checkedOutAt, original.checkedOutAt);
      expect(buildReportCsv([corrected]), contains('90,00'));
      final event = (await repository.shiftEvents(id)).first;
      expect(event.before!['break_minutes'], 0);
      expect(event.after!['break_minutes'], 30);
      expect(event.reason, 'Уточнил табель');

      final backup = await repository.exportBackup();
      await repository.restoreBackup(backup);
      expect((await repository.shifts()).single.earnedCents, 9000);
      expect((await repository.shiftEvents(id)).first.reason, 'Уточнил табель');
    });

    test('active correction changes start and tariff but not confirmation', () async {
      await repository.addProject('Проект');
      final project = (await repository.projects()).single;
      await repository.addRate(
          projectId: project.id, name: 'Обычный', centsPerHour: 1000);
      await repository.addRate(
          projectId: project.id, name: 'Повышенный', centsPerHour: 2000);
      final available = await repository.rates(project.id);
      final start = DateTime.now().subtract(const Duration(hours: 3));
      await repository.planShift(projectId: project.id, start: start);
      final id = (await repository.shifts()).single.id;
      await repository.armShift(id, available.first.id);
      await repository.confirmStart(id, start);
      final original = (await repository.shifts()).single;

      await expectLater(
        repository.correctWorkedShift(
          shiftId: id,
          creditedStart: start,
          creditedEnd: DateTime.now(),
          breakMinutes: 0,
          rateId: available.last.id,
          reason: 'Недопустимый конец',
        ),
        throwsArgumentError,
      );
      await repository.correctWorkedShift(
        shiftId: id,
        creditedStart: start.add(const Duration(minutes: 30)),
        creditedEnd: null,
        breakMinutes: 0,
        rateId: available.last.id,
        reason: 'Исправил начало',
      );
      final corrected = (await repository.shifts()).single;
      expect(corrected.status, ShiftStatus.active);
      expect(corrected.confirmedAt, original.confirmedAt);
      expect(corrected.creditedEnd, isNull);
      expect(corrected.rateId, available.last.id);
      expect((await repository.shiftEvents(id)).first.reason, 'Исправил начало');
    });

    test('old version 1 backup can be restored and corrected', () async {
      await repository.addProject('Старый проект');
      final project = (await repository.projects()).single;
      final start = DateTime.now().add(const Duration(days: 1));
      await repository.planShift(projectId: project.id, start: start);
      final oldBackup = jsonDecode(await repository.exportBackup())
          as Map<String, dynamic>;
      oldBackup['version'] = 1;
      final tables = oldBackup['tables'] as Map<String, dynamic>;
      for (final event in tables['shift_events'] as List) {
        (event as Map<String, dynamic>).remove('details_json');
      }
      await repository.addProject('Временный проект');

      await repository.restoreBackup(jsonEncode(oldBackup));

      expect((await repository.projects()).single.name, 'Старый проект');
      final id = (await repository.shifts()).single.id;
      await repository.updatePlannedShift(
        shiftId: id,
        projectId: project.id,
        plannedStart: start.add(const Duration(hours: 1)),
        plannedEnd: start.add(const Duration(hours: 9)),
        reason: 'Уточнил план',
      );
      expect((await repository.shiftEvents(id)).first.kind, 'corrected');
      expect(jsonDecode(await repository.exportBackup())['version'], 3);
    });
  });

  test('version 1 database upgrades without losing events', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('work-hours-migration-');
    final path = '${directory.path}${Platform.pathSeparator}legacy.db';
    final old = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''CREATE TABLE projects (
        id TEXT PRIMARY KEY, name TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      )''');
      await db.execute('''CREATE TABLE shift_events (
        id TEXT PRIMARY KEY, shift_id TEXT NOT NULL, kind TEXT NOT NULL,
        recorded_ms INTEGER NOT NULL, credited_ms INTEGER
      )''');
    });
    await old.insert('shift_events', {
      'id': 'old-event',
      'shift_id': 'old-shift',
      'kind': 'planned',
      'recorded_ms': 123456789,
    });
    await old.close();

    final upgraded = await WorkRepository.open(databasePath: path);
    final events = await upgraded.shiftEvents('old-shift');
    expect(events.single.kind, 'planned');
    expect(events.single.before, isNull);
    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
