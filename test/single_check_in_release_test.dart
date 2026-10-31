import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_hours_app/src/reminder_settings.dart';
import 'package:work_hours_app/src/report_csv.dart';
import 'package:work_hours_app/src/work_repository.dart';

DateTime _nowMillis() =>
    DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('early single check-in credits planned start and keeps data in backup', () async {
    final repository = await WorkRepository.openInMemory();
    try {
      await repository.addProject('Combo BV');
      final project = (await repository.projects()).single;
      final planned = _nowMillis().subtract(const Duration(hours: 2));
      final tapped = planned.subtract(const Duration(minutes: 30));
      final end = planned.add(const Duration(hours: 1));
      final id = await repository.planShift(
          projectId: project.id, start: planned, end: end);

      await repository.checkInShift(id, null, checkedInAt: tapped);
      var shift = (await repository.shifts()).single;
      expect(shift.status, ShiftStatus.active);
      expect(shift.preCheckInAt, tapped);
      expect(shift.creditedStart, planned);
      expect(shift.confirmedAt, isNull);
      expect((await repository.shiftEvents(id)).first.kind, 'checked_in');

      await repository.checkOut(id, end, breakMinutes: 0);
      shift = (await repository.shifts()).single;
      expect(shift.paidMinutes, 60);
      expect(buildReportCsv([shift]), contains('${shift.rowId};Combo BV'));

      final backup = await repository.exportBackup();
      expect(jsonDecode(backup)['version'], 4);
      await repository.restoreBackup(backup);
      final restored = (await repository.shifts()).single;
      expect(restored.rowId, shift.rowId);
      expect(restored.paidMinutes, 60);
      expect((await repository.shiftEvents(id)).first.kind, 'completed');
    } finally {
      await repository.close();
    }
  });

  test('late check-in credits tap time; tariff can be corrected after check-in', () async {
    final repository = await WorkRepository.openInMemory();
    try {
      await repository.addProject('Combo BV', trackPay: true);
      final project = (await repository.projects()).single;
      await repository.addRate(projectId: project.id, name: 'A', centsPerHour: 1000);
      await repository.addRate(projectId: project.id, name: 'B', centsPerHour: 1500);
      final rates = await repository.rates(project.id);
      final planned = _nowMillis().subtract(const Duration(hours: 3));
      final tapped = planned.add(const Duration(minutes: 30));
      final id = await repository.planShift(projectId: project.id,
          start: planned, end: planned.add(const Duration(hours: 2)));
      await repository.checkInShift(id, rates.first.id, checkedInAt: tapped);
      expect((await repository.shifts()).single.creditedStart, tapped);
      await repository.changeShiftRate(
          shiftId: id, rateId: rates.last.id, reason: 'Исправил тариф');
      final shift = (await repository.shifts()).single;
      expect(shift.rateId, rates.last.id);
      expect((await repository.shiftEvents(id)).first.reason, 'Исправил тариф');
    } finally {
      await repository.close();
    }
  });

  test('deleted plan retains row ID and cannot be deleted after check-in', () async {
    final repository = await WorkRepository.openInMemory();
    try {
      await repository.addProject('Проект');
      final project = (await repository.projects()).single;
      final start = _nowMillis().add(const Duration(days: 1));
      final first = await repository.planShift(projectId: project.id, start: start);
      await repository.cancelPlannedShift(first, 'Выходной');
      final second = await repository.planShift(
          projectId: project.id, start: start.add(const Duration(days: 1)));
      final shifts = await repository.shifts();
      expect(shifts.singleWhere((s) => s.id == first).rowId, 1);
      expect(shifts.singleWhere((s) => s.id == second).rowId, 2);
      await repository.checkInShift(second, null,
          checkedInAt: start.add(const Duration(days: 1, hours: -1)));
      await expectLater(repository.cancelPlannedShift(second, 'Нельзя'),
          throwsStateError);
      expect((await repository.shiftEvents(first)).first.reason, 'Выходной');
    } finally {
      await repository.close();
    }
  });

  test('version 3 backup keeps shifts and history with assigned row IDs', () async {
    final repository = await WorkRepository.openInMemory();
    try {
      await repository.addProject('Старый проект');
      final project = (await repository.projects()).single;
      final id = await repository.planShift(projectId: project.id,
          start: _nowMillis().add(const Duration(days: 1)));
      final old = jsonDecode(await repository.exportBackup()) as Map<String, dynamic>;
      old['version'] = 3;
      for (final row in (old['tables'] as Map<String, dynamic>)['shifts'] as List) {
        (row as Map<String, dynamic>).remove('row_number');
      }
      await repository.restoreBackup(jsonEncode(old));
      expect((await repository.shifts()).single.rowId, 1);
      expect((await repository.shiftEvents(id)).single.kind, 'planned');
    } finally {
      await repository.close();
    }
  });

  test('global reminder timing supports day before and previous evening', () {
    const settings = ReminderSettings(eveningHour: 19);
    final due = DateTime(2026, 11, 5, 10);
    expect(settings.when(due, ReminderTiming.atTime), due);
    expect(settings.when(due, ReminderTiming.hourBefore), DateTime(2026, 11, 5, 9));
    expect(settings.when(due, ReminderTiming.dayBefore), DateTime(2026, 11, 4, 10));
    expect(settings.when(due, ReminderTiming.previousEvening), DateTime(2026, 11, 4, 19));
  });

  test('updating a version 3 database preserves shift and audit events', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('workhours-v3-');
    final path = '${directory.path}${Platform.pathSeparator}work.db';
    try {
      final old = await openDatabase(path, version: 3,
          onCreate: (db, _) async {
        await db.execute('CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0, track_pay INTEGER NOT NULL DEFAULT 0)');
        await db.execute('CREATE TABLE rates (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, name TEXT NOT NULL, cents_per_hour INTEGER NOT NULL, currency TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0)');
        await db.execute('CREATE TABLE shifts (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, rate_id TEXT, status TEXT NOT NULL, planned_start_ms INTEGER NOT NULL, planned_end_ms INTEGER, pre_check_in_ms INTEGER, confirmed_ms INTEGER, credited_start_ms INTEGER, checked_out_ms INTEGER, credited_end_ms INTEGER, break_minutes INTEGER NOT NULL DEFAULT 0, rate_name_snapshot TEXT, rate_cents_snapshot INTEGER, currency_snapshot TEXT)');
        await db.execute('CREATE TABLE shift_events (id TEXT PRIMARY KEY, shift_id TEXT NOT NULL, kind TEXT NOT NULL, recorded_ms INTEGER NOT NULL, credited_ms INTEGER, details_json TEXT)');
        await db.execute('CREATE TABLE project_events (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, recorded_ms INTEGER NOT NULL, description TEXT NOT NULL)');
      });
      final planned = _nowMillis().add(const Duration(hours: 1));
      final tapped = planned.subtract(const Duration(minutes: 30));
      await old.insert('projects', {'id': 'old-project', 'name': 'Combo BV'});
      await old.insert('shifts', {
        'id': 'old-shift', 'project_id': 'old-project', 'status': 'armed',
        'planned_start_ms': planned.millisecondsSinceEpoch,
        'pre_check_in_ms': tapped.millisecondsSinceEpoch,
      });
      await old.insert('shift_events', {
        'id': 'old-event', 'shift_id': 'old-shift', 'kind': 'armed',
        'recorded_ms': tapped.millisecondsSinceEpoch,
      });
      await old.close();

      final updated = await WorkRepository.open(databasePath: path);
      try {
        expect((await updated.projects()).single.name, 'Combo BV');
        final shift = (await updated.shifts()).single;
        expect(shift.rowId, 1);
        expect(shift.status, ShiftStatus.active);
        expect(shift.preCheckInAt, tapped);
        expect(shift.creditedStart, planned);
        expect((await updated.shiftEvents(shift.id)).single.kind, 'armed');
      } finally {
        await updated.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
