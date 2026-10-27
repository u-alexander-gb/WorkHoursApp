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

class ShiftEvent {
  const ShiftEvent({
    required this.kind,
    required this.recordedAt,
    required this.reason,
    required this.before,
    required this.after,
  });

  final String kind;
  final DateTime recordedAt;
  final String? reason;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
}

class BackupPreview {
  const BackupPreview({required this.createdAt, required this.counts});

  final DateTime createdAt;
  final Map<String, int> counts;
}

class _ParsedBackup {
  const _ParsedBackup(this.preview, this.tables);

  final BackupPreview preview;
  final Map<String, List<Map<String, Object?>>> tables;
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
    'shift_events': [
      'id', 'shift_id', 'kind', 'recorded_ms', 'credited_ms', 'details_json'
    ],
  };

  static Future<WorkRepository> open({String? databasePath}) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final directory = databasePath == null ? await getDatabasesPath() : null;
    final path = databasePath ??
        '$directory${Platform.pathSeparator}work_hours.db';
    final db = await openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return WorkRepository._(db);
  }

  static Future<WorkRepository> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
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
            credited_ms INTEGER,
            details_json TEXT
          )
        ''');
  }

  static Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE shift_events ADD COLUMN details_json TEXT');
    }
  }

  Future<void> close() => _db.close();

  Future<String> exportBackup() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _backupColumns.keys) {
      tables[table] = await _db.query(table);
    }
    return jsonEncode({
      'format': 'work-hours-backup',
      'version': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    });
  }

  static BackupPreview inspectBackup(String contents) =>
      _parseBackup(contents).preview;

  static _ParsedBackup _parseBackup(String contents) {
    final Object? decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'work-hours-backup' ||
        (decoded['version'] != 1 && decoded['version'] != 2) ||
        decoded['tables'] is! Map<String, dynamic> ||
        decoded['createdAt'] is! String) {
      throw const FormatException('Неверный формат резервной копии');
    }
    final createdAt = DateTime.tryParse(decoded['createdAt'] as String);
    if (createdAt == null) {
      throw const FormatException('Неверная дата резервной копии');
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
        final row = Map<String, Object?>.from(rawRow);
        if (decoded['version'] == 1 && entry.key == 'shift_events') {
          row['details_json'] = null;
        }
        if (entry.key == 'shift_events' && row['details_json'] is String) {
          final details = jsonDecode(row['details_json'] as String);
          if (details is! Map<String, dynamic> ||
              details['reason'] is! String ||
              details['before'] is! Map ||
              details['after'] is! Map) {
            throw const FormatException('Повреждена история исправлений');
          }
        }
        rows.add(row);
      }
      tables[entry.key] = rows;
    }
    return _ParsedBackup(
      BackupPreview(
        createdAt: createdAt,
        counts: {for (final entry in tables.entries) entry.key: entry.value.length},
      ),
      tables,
    );
  }

  Future<void> restoreBackup(String contents) async {
    final tables = _parseBackup(contents).tables;
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

  Future<List<ShiftEvent>> shiftEvents(String shiftId) async {
    final rows = await _db.query('shift_events',
        where: 'shift_id = ?',
        whereArgs: [shiftId],
        orderBy: 'recorded_ms DESC, rowid DESC');
    return rows.map((row) {
      final raw = row['details_json'] as String?;
      final details = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      return ShiftEvent(
        kind: row['kind'] as String,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(row['recorded_ms'] as int),
        reason: details?['reason'] as String?,
        before: details == null
            ? null
            : Map<String, Object?>.from(details['before'] as Map),
        after: details == null
            ? null
            : Map<String, Object?>.from(details['after'] as Map),
      );
    }).toList();
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

  Future<void> updatePlannedShift({
    required String shiftId,
    required String projectId,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    required String reason,
  }) async {
    _validatePlan(plannedStart, plannedEnd);
    await _db.transaction((tx) async {
      final before = await _requireShift(tx, shiftId, ShiftStatus.planned);
      final project = await tx.query('projects',
          where: 'id = ? AND archived = 0', whereArgs: [projectId], limit: 1);
      if (project.isEmpty) throw StateError('Проект не найден');
      await _updateWithAudit(tx, shiftId, before, {
        'project_id': projectId,
        'planned_start_ms': plannedStart.millisecondsSinceEpoch,
        'planned_end_ms': plannedEnd.millisecondsSinceEpoch,
      }, reason);
    });
  }

  Future<void> updateArmedShift({
    required String shiftId,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    required String rateId,
    required String reason,
  }) async {
    _validatePlan(plannedStart, plannedEnd);
    await _db.transaction((tx) async {
      final before = await _requireShift(tx, shiftId, ShiftStatus.armed);
      final rate = await _requireRate(tx, rateId, before['project_id'] as String);
      await _updateWithAudit(tx, shiftId, before, {
        'planned_start_ms': plannedStart.millisecondsSinceEpoch,
        'planned_end_ms': plannedEnd.millisecondsSinceEpoch,
        ..._rateSnapshot(rate),
      }, reason);
    });
  }

  Future<void> correctWorkedShift({
    required String shiftId,
    required DateTime creditedStart,
    required DateTime? creditedEnd,
    required int breakMinutes,
    required String rateId,
    required String reason,
  }) async {
    if (creditedStart.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw ArgumentError('Начало работы не может быть в будущем');
    }
    await _db.transaction((tx) async {
      final rows = await tx.query('shifts',
          where: 'id = ?', whereArgs: [shiftId], limit: 1);
      if (rows.isEmpty) throw StateError('Смена не найдена');
      final before = rows.single;
      final status = before['status'];
      if (status != ShiftStatus.active.name &&
          status != ShiftStatus.completed.name) {
        throw StateError('Эту смену нельзя исправить в текущем состоянии');
      }
      if (status == ShiftStatus.active.name) {
        if (creditedEnd != null || breakMinutes != 0) {
          throw ArgumentError('Активная смена ещё не завершена');
        }
      } else {
        if (creditedEnd == null || breakMinutes < 0 ||
            !creditedEnd.isAfter(creditedStart) ||
            breakMinutes > creditedEnd.difference(creditedStart).inMinutes) {
          throw ArgumentError('Проверьте время окончания и перерыв');
        }
      }
      final rate = await _requireRate(tx, rateId, before['project_id'] as String);
      await _updateWithAudit(tx, shiftId, before, {
        'credited_start_ms': creditedStart.millisecondsSinceEpoch,
        'credited_end_ms': creditedEnd?.millisecondsSinceEpoch,
        'break_minutes': breakMinutes,
        ..._rateSnapshot(rate),
      }, reason);
    });
  }

  void _validatePlan(DateTime start, DateTime end) {
    if (!end.isAfter(start)) {
      throw ArgumentError('Конец плана должен быть позже начала');
    }
  }

  Future<WorkRate> _requireRate(Transaction tx, String rateId, String projectId) async {
    final rows = await tx.query('rates',
        where: 'id = ? AND project_id = ? AND archived = 0',
        whereArgs: [rateId, projectId],
        limit: 1);
    if (rows.isEmpty) throw StateError('Тариф этого проекта не найден');
    return _rateFromRow(rows.single);
  }

  Map<String, Object?> _rateSnapshot(WorkRate rate) => {
        'rate_id': rate.id,
        'rate_name_snapshot': rate.name,
        'rate_cents_snapshot': rate.centsPerHour,
        'currency_snapshot': rate.currency,
      };

  Future<void> _updateWithAudit(Transaction tx, String shiftId,
      Map<String, Object?> before, Map<String, Object?> changes,
      String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Укажите причину исправления');
    }
    final after = {...before, ...changes};
    final oldValues = _auditValues(before);
    final newValues = _auditValues(after);
    if (jsonEncode(oldValues) == jsonEncode(newValues)) return;
    await tx.update('shifts', changes, where: 'id = ?', whereArgs: [shiftId]);
    await tx.insert('shift_events', {
      'id': _newId(),
      'shift_id': shiftId,
      'kind': 'corrected',
      'recorded_ms': DateTime.now().millisecondsSinceEpoch,
      'details_json': jsonEncode({
        'reason': reason.trim(),
        'before': oldValues,
        'after': newValues,
      }),
    });
  }

  Map<String, Object?> _auditValues(Map<String, Object?> row) => {
        for (final key in [
          'project_id', 'planned_start_ms', 'planned_end_ms', 'rate_id',
          'rate_name_snapshot', 'rate_cents_snapshot', 'currency_snapshot',
          'credited_start_ms', 'credited_end_ms', 'break_minutes'
        ])
          key: row[key],
      };

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
