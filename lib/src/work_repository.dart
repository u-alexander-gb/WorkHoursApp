import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _newId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

enum ShiftStatus { planned, armed, active, completed, cancelled }

class WorkProject {
  const WorkProject({required this.id, required this.name});
  final String id;
  final String name;
}

class WorkRate {
  const WorkRate({
    required this.id,
    required this.projectId,
    required this.name,
    required this.centsPerHour,
    required this.currency,
  });
  final String id;
  final String projectId;
  final String name;
  final int centsPerHour;
  final String currency;
}

class WorkShift {
  const WorkShift({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.status,
    required this.plannedStart,
    required this.plannedEnd,
    required this.rateId,
    required this.rateName,
    required this.rateCentsPerHour,
    required this.currency,
    required this.preCheckInAt,
    required this.confirmedAt,
    required this.creditedStart,
    required this.checkedOutAt,
    required this.creditedEnd,
    required this.breakMinutes,
  });

  final String id;
  final String projectId;
  final String projectName;
  final ShiftStatus status;
  final DateTime plannedStart;
  final DateTime? plannedEnd;
  final String? rateId;
  final String? rateName;
  final int? rateCentsPerHour;
  final String? currency;
  final DateTime? preCheckInAt;
  final DateTime? confirmedAt;
  final DateTime? creditedStart;
  final DateTime? checkedOutAt;
  final DateTime? creditedEnd;
  final int breakMinutes;

  int get paidMinutes {
    if (status != ShiftStatus.completed ||
        creditedStart == null ||
        creditedEnd == null) {
      return 0;
    }
    final elapsed = creditedEnd!.difference(creditedStart!).inMinutes;
    return max(0, elapsed - breakMinutes);
  }

  int get earnedCents {
    final rate = rateCentsPerHour;
    if (rate == null) return 0;
    return (paidMinutes * rate + 30) ~/ 60;
  }
}

class WorkRepository {
  WorkRepository._(this._db);
  final Database _db;

  static const _backupColumns = <String, List<String>>{
    'projects': ['id', 'name', 'archived'],
    'rates': [
      'id', 'project_id', 'name', 'cents_per_hour', 'currency', 'archived'
    ],
    'shifts': [
      'id', 'project_id', 'rate_id', 'status', 'planned_start_ms',
      'planned_end_ms', 'pre_check_in_ms', 'confirmed_ms',
      'credited_start_ms', 'checked_out_ms', 'credited_end_ms',
      'break_minutes', 'rate_name_snapshot', 'rate_cents_snapshot',
      'currency_snapshot'
    ],
    'shift_events': ['id', 'shift_id', 'kind', 'recorded_ms', 'credited_ms'],
  };

  static Future<WorkRepository> open() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final directory = await getDatabasesPath();
    final path = '$directory${Platform.pathSeparator}work_hours.db';
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
    );
    return WorkRepository._(db);
  }

  static Future<WorkRepository> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
    );
    return WorkRepository._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE rates (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL REFERENCES projects(id),
            name TEXT NOT NULL,
            cents_per_hour INTEGER NOT NULL CHECK (cents_per_hour >= 0),
            currency TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE shifts (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL REFERENCES projects(id),
            rate_id TEXT REFERENCES rates(id),
            status TEXT NOT NULL,
            planned_start_ms INTEGER NOT NULL,
            planned_end_ms INTEGER,
            pre_check_in_ms INTEGER,
            confirmed_ms INTEGER,
            credited_start_ms INTEGER,
            checked_out_ms INTEGER,
            credited_end_ms INTEGER,
            break_minutes INTEGER NOT NULL DEFAULT 0,
            rate_name_snapshot TEXT,
            rate_cents_snapshot INTEGER,
            currency_snapshot TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE shift_events (
            id TEXT PRIMARY KEY,
            shift_id TEXT NOT NULL REFERENCES shifts(id),
            kind TEXT NOT NULL,
            recorded_ms INTEGER NOT NULL,
            credited_ms INTEGER
          )
        ''');
  }

  Future<void> close() => _db.close();

  Future<String> exportBackup() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _backupColumns.keys) {
      tables[table] = await _db.query(table);
    }
    return jsonEncode({
      'format': 'work-hours-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    });
  }

  Future<void> restoreBackup(String contents) async {
    final Object? decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'work-hours-backup' ||
        decoded['version'] != 1 ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат резервной копии');
    }
    final source = decoded['tables'] as Map<String, dynamic>;
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in _backupColumns.entries) {
      final rawRows = source[entry.key];
      if (rawRows is! List) {
        throw const FormatException('В копии отсутствует таблица данных');
      }
      final rows = <Map<String, Object?>>[];
      for (final rawRow in rawRows) {
        if (rawRow is! Map<String, dynamic> ||
            rawRow.keys.any((column) => !entry.value.contains(column)) ||
            rawRow.values.any((value) =>
                value != null && value is! String && value is! int)) {
          throw const FormatException('В копии есть неверные данные');
        }
        rows.add(Map<String, Object?>.from(rawRow));
      }
      tables[entry.key] = rows;
    }
    await _db.transaction((tx) async {
      for (final table in _backupColumns.keys.toList().reversed) {
        await tx.delete(table);
      }
      for (final table in _backupColumns.keys) {
        for (final row in tables[table]!) {
          await tx.insert(table, row);
        }
      }
    });
  }

  Future<List<WorkProject>> projects() async {
    final rows = await _db.query('projects',
        where: 'archived = 0', orderBy: 'name COLLATE NOCASE');
    return rows
        .map((row) => WorkProject(id: row['id'] as String, name: row['name'] as String))
        .toList();
  }

  Future<List<WorkRate>> rates(String projectId) async {
    final rows = await _db.query('rates',
        where: 'project_id = ? AND archived = 0',
        whereArgs: [projectId],
        orderBy: 'name COLLATE NOCASE');
    return rows.map(_rateFromRow).toList();
  }

  Future<List<WorkShift>> shifts() async {
    final rows = await _db.rawQuery('''
      SELECT s.*, p.name AS project_name
      FROM shifts s JOIN projects p ON p.id = s.project_id
      WHERE s.status != 'cancelled'
      ORDER BY s.planned_start_ms DESC
    ''');
    return rows.map(_shiftFromRow).toList();
  }

  Future<void> addProject(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Название проекта обязательно');
    await _db.insert('projects', {'id': _newId(), 'name': clean});
  }

  Future<void> addRate({
    required String projectId,
    required String name,
    required int centsPerHour,
    String currency = 'EUR',
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || centsPerHour < 0) {
      throw ArgumentError('Проверьте название и сумму тарифа');
    }
    await _db.insert('rates', {
      'id': _newId(),
      'project_id': projectId,
      'name': clean,
      'cents_per_hour': centsPerHour,
      'currency': currency,
    });
  }

  Future<void> planShift({
    required String projectId,
    required DateTime start,
    DateTime? end,
  }) async {
    if (end != null && !end.isAfter(start)) {
      throw ArgumentError('Конец плана должен быть позже начала');
    }
    final id = _newId();
    await _db.transaction((tx) async {
      await tx.insert('shifts', {
        'id': id,
        'project_id': projectId,
        'status': ShiftStatus.planned.name,
        'planned_start_ms': start.millisecondsSinceEpoch,
        'planned_end_ms': end?.millisecondsSinceEpoch,
      });
      await _recordEvent(tx, id, 'planned');
    });
  }

  Future<void> armShift(String shiftId, String rateId) async {
    await _db.transaction((tx) async {
      final shift = await _requireShift(tx, shiftId, ShiftStatus.planned);
      final rows = await tx.query('rates',
          where: 'id = ? AND project_id = ? AND archived = 0',
          whereArgs: [rateId, shift['project_id']],
          limit: 1);
      if (rows.isEmpty) throw StateError('Тариф этого проекта не найден');
      final rate = _rateFromRow(rows.single);
      await tx.update(
          'shifts',
          {
            'status': ShiftStatus.armed.name,
            'rate_id': rate.id,
            'rate_name_snapshot': rate.name,
            'rate_cents_snapshot': rate.centsPerHour,
            'currency_snapshot': rate.currency,
            'pre_check_in_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [shiftId]);
      await _recordEvent(tx, shiftId, 'armed');
    });
  }

  Future<void> confirmStart(String shiftId, DateTime creditedStart) async {
    final now = DateTime.now();
    if (creditedStart.isAfter(now.add(const Duration(minutes: 1)))) {
      throw ArgumentError('Начало работы не может быть в будущем');
    }
    await _db.transaction((tx) async {
      await _requireShift(tx, shiftId, ShiftStatus.armed);
      await tx.update(
          'shifts',
          {
            'status': ShiftStatus.active.name,
            'confirmed_ms': now.millisecondsSinceEpoch,
            'credited_start_ms': creditedStart.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [shiftId]);
      await _recordEvent(tx, shiftId, 'confirmed', creditedStart);
    });
  }

  Future<void> checkOut(String shiftId, DateTime creditedEnd,
      {required int breakMinutes}) async {
    if (breakMinutes < 0) {
      throw ArgumentError('Перерыв не может быть отрицательным');
    }
    await _db.transaction((tx) async {
      final shift = await _requireShift(tx, shiftId, ShiftStatus.active);
      final start = DateTime.fromMillisecondsSinceEpoch(
          shift['credited_start_ms'] as int);
      final minutes = creditedEnd.difference(start).inMinutes;
      if (minutes <= 0 || breakMinutes > minutes) {
        throw ArgumentError('Проверьте время окончания и перерыв');
      }
      await tx.update(
          'shifts',
          {
            'status': ShiftStatus.completed.name,
            'checked_out_ms': DateTime.now().millisecondsSinceEpoch,
            'credited_end_ms': creditedEnd.millisecondsSinceEpoch,
            'break_minutes': breakMinutes,
          },
          where: 'id = ?',
          whereArgs: [shiftId]);
      await _recordEvent(tx, shiftId, 'completed', creditedEnd);
    });
  }

  Future<Map<String, Object?>> _requireShift(
      Transaction tx, String id, ShiftStatus status) async {
    final rows = await tx.query('shifts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.single['status'] != status.name) {
      throw StateError('Состояние смены изменилось. Обновите экран.');
    }
    return rows.single;
  }

  Future<void> _recordEvent(Transaction tx, String shiftId, String kind,
      [DateTime? credited]) async {
    await tx.insert('shift_events', {
      'id': _newId(),
      'shift_id': shiftId,
      'kind': kind,
      'recorded_ms': DateTime.now().millisecondsSinceEpoch,
      'credited_ms': credited?.millisecondsSinceEpoch,
    });
  }
}

WorkRate _rateFromRow(Map<String, Object?> row) => WorkRate(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      centsPerHour: row['cents_per_hour'] as int,
      currency: row['currency'] as String,
    );

WorkShift _shiftFromRow(Map<String, Object?> row) {
  DateTime? time(String key) {
    final value = row[key] as int?;
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  return WorkShift(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    projectName: row['project_name'] as String,
    status: ShiftStatus.values.byName(row['status'] as String),
    plannedStart: time('planned_start_ms')!,
    plannedEnd: time('planned_end_ms'),
    rateId: row['rate_id'] as String?,
    rateName: row['rate_name_snapshot'] as String?,
    rateCentsPerHour: row['rate_cents_snapshot'] as int?,
    currency: row['currency_snapshot'] as String?,
    preCheckInAt: time('pre_check_in_ms'),
    confirmedAt: time('confirmed_ms'),
    creditedStart: time('credited_start_ms'),
    checkedOutAt: time('checked_out_ms'),
    creditedEnd: time('credited_end_ms'),
    breakMinutes: row['break_minutes'] as int,
  );
}
