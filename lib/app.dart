import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'src/backup_codec.dart';
import 'src/work_repository.dart';
import 'src/reminder_service.dart';
import 'src/report_csv.dart';

void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));

String _two(int number) => number.toString().padLeft(2, '0');
String _date(DateTime date) => '${_two(date.day)}.${_two(date.month)}.${date.year}';
String _time(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';
String _dateTime(DateTime date) => '${_date(date)} ${_time(date)}';
String _duration(int minutes) => '${minutes ~/ 60} ч ${_two(minutes % 60)} мин';
String _money(int cents, String currency) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} $currency';

int? _parseCents(String input) {
  final value = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

/// Keep form controllers alive until the dialog's exit animation removes it.
Future<T?> showFormDialogUntilClosed<T>(BuildContext context,
    {required WidgetBuilder builder}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

class BackupPasswordDialog extends StatefulWidget {
  const BackupPasswordDialog({super.key, required this.create});

  final bool create;

  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  final password = TextEditingController();
  final repeated = TextEditingController();
  bool hidden = true;

  @override
  void dispose() {
    password.dispose();
    repeated.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.create
            ? 'Пароль резервной копии'
            : 'Открыть резервную копию'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.create
              ? 'Запомните пароль: без него восстановить копию нельзя. Минимум 12 символов.'
              : 'Введите пароль для проверки и просмотра копии.'),
          TextField(
            controller: password,
            obscureText: hidden,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.create)
            TextField(
              controller: repeated,
              obscureText: hidden,
              decoration: InputDecoration(
                labelText: 'Повторите пароль',
                errorText: repeated.text.isNotEmpty &&
                        repeated.text != password.text
                    ? 'Пароли не совпадают'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Показать пароль'),
            value: !hidden,
            onChanged: (value) => setState(() => hidden = value != true),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: password.text.isEmpty ||
                    (widget.create &&
                        (password.text.length < 12 ||
                            repeated.text != password.text))
                ? null
                : () => Navigator.pop(context, password.text),
            child: Text(widget.create ? 'Продолжить' : 'Проверить'),
          ),
        ],
      );
}

class WorkHoursApp extends StatefulWidget {
  const WorkHoursApp({super.key});

  @override
  State<WorkHoursApp> createState() => _WorkHoursAppState();
}

class _WorkHoursAppState extends State<WorkHoursApp> {
  late final Future<WorkRepository> repository = WorkRepository.open();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Учёт рабочего времени',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315C84)),
          useMaterial3: true,
        ),
        home: FutureBuilder<WorkRepository>(
          future: repository,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Scaffold(
                  body: Center(child: Text('Ошибка базы данных: ${snapshot.error}')));
            }
            if (!snapshot.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return WorkHome(repository: snapshot.data!);
          },
        ),
      );
}

class WorkHome extends StatefulWidget {
  const WorkHome({super.key, required this.repository});
  final WorkRepository repository;

  @override
  State<WorkHome> createState() => _WorkHomeState();
}

class _WorkHomeState extends State<WorkHome> {
  final ReminderService reminders = ReminderService();
  int tab = 0;
  bool loading = true;
  List<WorkProject> projects = [];
  List<WorkShift> shifts = [];
  Map<String, List<WorkRate>> rates = {};
  String period = 'week';
  DateTime anchor = DateTime.now();
  DateTime planWeek = DateTime.now();
  DateTimeRange? customRange;

  @override
  void initState() {
    super.initState();
    reminders.onTap = () {
      if (!mounted) return;
      setState(() => tab = 0);
      _reload();
    };
    _reload();
  }

  Future<void> _reload() async {
    try {
      final nextProjects = await widget.repository.projects();
      final nextShifts = await widget.repository.shifts();
      final nextRates = <String, List<WorkRate>>{};
      for (final project in nextProjects) {
        nextRates[project.id] = await widget.repository.rates(project.id);
      }
      if (!mounted) return;
      setState(() {
        projects = nextProjects;
        shifts = nextShifts;
        rates = nextRates;
        loading = false;
      });
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      await _reload();
    }
  }

  Future<String?> _askBackupPassword({required bool create}) async {
    return showDialog<String>(
      context: context,
      builder: (_) => BackupPasswordDialog(create: create),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final password = await _askBackupPassword(create: true);
      if (password == null) return;
      final contents = await BackupCodec.encrypt(
        await widget.repository.exportBackup(),
        password,
      );
      final now = DateTime.now();
      final name = 'work-hours-${now.year}-${_two(now.month)}-${_two(now.day)}.whbackup';
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/octet-stream',
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Резервная копия сохранена')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _importBackup() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['whbackup', 'json'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 20 * 1024 * 1024) {
        throw const FormatException('Файл резервной копии слишком большой');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Файл резервной копии слишком большой');
      }
      if (!mounted) return;
      var contents = utf8.decode(bytes);
      final encrypted = BackupCodec.isEncrypted(contents);
      if (encrypted) {
        final password = await _askBackupPassword(create: false);
        if (password == null) return;
        contents = await BackupCodec.decrypt(contents, password);
      }
      final preview = WorkRepository.inspectBackup(contents);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Восстановить данные?'),
          content: Text('Файл: ${file.name}\n'
              'Создан: ${_dateTime(preview.createdAt.toLocal())}\n'
              'Проектов: ${preview.counts['projects']}, '
              'тарифов: ${preview.counts['rates']}\n'
              'Смен: ${preview.counts['shifts']}, '
              'событий: ${preview.counts['shift_events']}\n\n'
              '${encrypted ? 'Пароль и целостность проверены.' : 'Старая копия без шифрования.'}\n'
              'Текущие данные будут заменены. Сначала сохраните их копию.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final previousArmed = shifts.where((s) =>
          s.status == ShiftStatus.planned ||
          s.status == ShiftStatus.armed ||
          s.status == ShiftStatus.active).toList();
      await widget.repository.restoreBackup(contents);
      for (final shift in previousArmed) {
        await reminders.cancel(shift.id);
      }
      final restored = await widget.repository.shifts();
      for (final shift in restored) {
        await _scheduleReminder(shift);
      }
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные восстановлены')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<ReminderResult> _scheduleReminder(WorkShift shift) async {
    final kind = switch (shift.status) {
      ShiftStatus.planned => ReminderKind.checkIn,
      ShiftStatus.armed => ReminderKind.confirmStart,
      ShiftStatus.active => ReminderKind.checkOut,
      _ => null,
    };
    if (kind == null) {
      return const ReminderResult(scheduled: false, exact: false);
    }
    final due = kind == ReminderKind.checkOut
        ? (shift.plannedEnd ?? shift.plannedStart.add(const Duration(hours: 8)))
        : shift.plannedStart;
    final when = kind == ReminderKind.checkOut && !due.isAfter(DateTime.now())
        ? DateTime.now().add(const Duration(minutes: 1))
        : due;
    return reminders.schedule(
      shiftId: shift.id,
      when: when,
      projectName: shift.projectName,
      kind: kind,
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<DateTime?> _pickTimeOnDay(DateTime initial) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(initial.year, initial.month, initial.day,
        time.hour, time.minute);
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    var trackPay = false;
    final result = await showFormDialogUntilClosed<(String, bool)>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Новый проект'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название работы или проекта'),
            ),
            SwitchListTile(
              title: const Text('Учитывать оплату'),
              subtitle: const Text('Выключено: учитываются только часы'),
              value: trackPay,
              onChanged: (value) => update(() => trackPay = value),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (controller.text, trackPay)),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (result != null) {
      await _perform(() => widget.repository.addProject(result.$1,
          trackPay: result.$2));
    }
    controller.dispose();
  }

  Future<void> _createRate(WorkProject project) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final result = await showFormDialogUntilClosed<(String, String)>(
      context,
      builder: (context) => AlertDialog(
        title: Text('Тариф: ${project.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название тарифа')),
          TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Евро за час')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, (name.text, amount.text)),
              child: const Text('Сохранить')),
        ],
      ),
    );
    name.dispose();
    amount.dispose();
    if (result == null) return;
    final cents = _parseCents(result.$2);
    if (cents == null) {
      if (!mounted) return;
      _showError(context, 'Укажите сумму, например 15,50');
      return;
    }
    await _perform(() => widget.repository.addRate(
        projectId: project.id, name: result.$1, centsPerHour: cents));
  }

  Future<void> _plan() async {
    if (projects.isEmpty) {
      await _createProject();
      return;
    }
    final now = DateTime.now();
    var projectId = projects.first.id;
    final monday = DateTime(planWeek.year, planWeek.month,
        planWeek.day - planWeek.weekday + DateTime.monday);
    var start = monday.isAfter(now)
        ? DateTime(monday.year, monday.month, monday.day, 10)
        : DateTime(now.year, now.month, now.day + 1, 10);
    var end = start.add(const Duration(hours: 8));
    final result = await showDialog<(String, DateTime, DateTime)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Запланировать смену'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: projectId,
              decoration: const InputDecoration(labelText: 'Проект'),
              items: projects
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  update(() => projectId = id);
                }
              },
            ),
            ListTile(
              title: const Text('Начало'),
              subtitle: Text(_dateTime(start)),
              onTap: () async {
                final chosen = await _pickDateTime(start);
                if (chosen != null) {
                  update(() {
                    start = chosen;
                    end = start.add(const Duration(hours: 8));
                  });
                }
              },
            ),
            ListTile(
              title: const Text('Ожидаемый конец'),
              subtitle: Text(_dateTime(end)),
              onTap: () async {
                final chosen = await _pickDateTime(end);
                if (chosen != null) {
                  update(() => end = chosen);
                }
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (projectId, start, end)),
                child: const Text('Добавить')),
          ],
        ),
      ),
    );
    if (result != null) {
      await _perform(() async {
        final id = await widget.repository.planShift(
            projectId: result.$1, start: result.$2, end: result.$3);
        final reminder = await reminders.schedule(
          shiftId: id,
          when: result.$2,
          projectName: projects.singleWhere((p) => p.id == result.$1).name,
          kind: ReminderKind.checkIn,
        );
        if (Platform.isAndroid && mounted && !reminder.scheduled &&
            result.$2.isAfter(DateTime.now())) {
          _showError(context, 'План сохранён, но напоминание о check-in не назначено');
        }
      });
      if (mounted) setState(() => planWeek = result.$2);
    }
  }

  Future<void> _arm(WorkShift shift) async {
    final project = projects.singleWhere((item) => item.id == shift.projectId);
    final available = rates[shift.projectId] ?? [];
    if (project.trackPay && available.isEmpty) {
      _showError(context, 'Сначала добавьте тариф для проекта');
      return;
    }
    String? rateId;
    if (project.trackPay) {
      rateId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Выберите тариф'),
          children: available
              .map((rate) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, rate.id),
                    child: Text('${rate.name} — '
                        '${_money(rate.centsPerHour, rate.currency)}/ч'),
                  ))
              .toList(),
        ),
      );
      if (rateId == null) return;
    }
    if (mounted) {
      await _perform(() async {
        await widget.repository.armShift(shift.id, rateId);
        await reminders.cancel(shift.id);
        final reminder = await reminders.schedule(
          shiftId: shift.id,
          when: shift.plannedStart,
          projectName: shift.projectName,
          kind: ReminderKind.confirmStart,
        );
        if (Platform.isAndroid && mounted && !reminder.scheduled &&
            shift.plannedStart.isAfter(DateTime.now())) {
          _showError(context, 'Напоминание не назначено. Проверьте разрешения.');
        } else if (Platform.isAndroid && mounted && reminder.scheduled && !reminder.exact) {
          _showError(context, 'Напоминание может прийти с задержкой.');
        }
      });
    }
  }

  Future<void> _confirm(WorkShift shift) async {
    final now = DateTime.now();
    final start = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Во сколько началась работа?'),
        children: [
          if (!shift.plannedStart.isAfter(now))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, shift.plannedStart),
              child: Text('По плану — ${_time(shift.plannedStart)}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, now),
            child: Text('Сейчас — ${_time(now)}'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              final chosen = await _pickDateTime(now);
              if (dialogContext.mounted && chosen != null) {
                Navigator.pop(dialogContext, chosen);
              }
            },
            child: const Text('Выбрать другое время'),
          ),
        ],
      ),
    );
    if (start != null) {
      await _perform(() async {
        await widget.repository.confirmStart(shift.id, start);
        await reminders.cancel(shift.id);
        final active = (await widget.repository.shifts())
            .singleWhere((item) => item.id == shift.id);
        final reminder = await _scheduleReminder(active);
        if (Platform.isAndroid && mounted && !reminder.scheduled) {
          _showError(context, 'Начало сохранено, но напоминание о check-out не назначено');
        }
      });
    }
  }

  Future<void> _checkOut(WorkShift shift) async {
    final breakInput = TextEditingController(text: '0');
    var end = DateTime.now();
    final result = await showFormDialogUntilClosed<(DateTime, int)>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Завершить смену'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: const Text('Время окончания'),
              subtitle: Text(_dateTime(end)),
              onTap: () async {
                final chosen = await _pickDateTime(end);
                if (chosen != null) {
                  update(() => end = chosen);
                }
              },
            ),
            TextField(
              controller: breakInput,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Неоплачиваемый перерыв, минуты'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final minutes = int.tryParse(breakInput.text.trim());
                if (minutes != null) {
                  Navigator.pop(dialogContext, (end, minutes));
                }
              },
              child: const Text('Check-out'),
            ),
          ],
        ),
      ),
    );
    breakInput.dispose();
    if (result != null) {
      await _perform(() async {
        await widget.repository.checkOut(
            shift.id, result.$1, breakMinutes: result.$2);
        await reminders.cancel(shift.id);
      });
    }
  }

  Future<void> _editShift(WorkShift shift) async {
    var projectId = shift.projectId;
    var plannedStart = shift.plannedStart;
    var plannedEnd = shift.plannedEnd ??
        shift.plannedStart.add(const Duration(hours: 8));
    var rateId = shift.rateId;
    var creditedStart = shift.creditedStart ?? shift.plannedStart;
    var creditedEnd = shift.creditedEnd ?? DateTime.now();
    final breakInput = TextEditingController(text: '${shift.breakMinutes}');
    final reasonInput = TextEditingController();
    final availableRates = rates[shift.projectId] ?? <WorkRate>[];
    final saved = await showFormDialogUntilClosed<bool>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Исправить смену'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (shift.status == ShiftStatus.planned)
                DropdownButtonFormField<String>(
                  initialValue: projectId,
                  decoration: const InputDecoration(labelText: 'Проект'),
                  items: projects
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      update(() => projectId = value);
                    }
                  },
                ),
              if (shift.status == ShiftStatus.planned ||
                  shift.status == ShiftStatus.armed) ...[
                ListTile(
                  title: const Text('Плановое начало'),
                  subtitle: Text(_dateTime(plannedStart)),
                  onTap: () async {
                    final selected = shift.status == ShiftStatus.armed
                        ? await _pickTimeOnDay(plannedStart)
                        : await _pickDateTime(plannedStart);
                    if (selected != null) {
                      update(() {
                        final duration = plannedEnd.difference(plannedStart);
                        plannedStart = selected;
                        plannedEnd = selected.add(duration);
                      });
                    }
                  },
                ),
                ListTile(
                  title: const Text('Плановый конец'),
                  subtitle: Text(_dateTime(plannedEnd)),
                  onTap: () async {
                    final selected = shift.status == ShiftStatus.armed
                        ? await _pickTimeOnDay(plannedEnd)
                        : await _pickDateTime(plannedEnd);
                    if (selected != null) {
                      update(() => plannedEnd = selected);
                    }
                  },
                ),
              ],
              if (shift.status != ShiftStatus.planned &&
                  (shift.rateId != null ||
                      projects.any((p) => p.id == shift.projectId && p.trackPay)))
                DropdownButtonFormField<String>(
                  initialValue: availableRates.any((rate) => rate.id == rateId)
                      ? rateId
                      : null,
                  decoration: const InputDecoration(labelText: 'Тариф'),
                  items: availableRates
                      .map((rate) => DropdownMenuItem(
                            value: rate.id,
                            child: Text('${rate.name} — '
                                '${_money(rate.centsPerHour, rate.currency)}/ч'),
                          ))
                      .toList(),
                  onChanged: (value) => update(() => rateId = value),
                ),
              if (shift.status == ShiftStatus.active ||
                  shift.status == ShiftStatus.completed)
                ListTile(
                  title: const Text('Учтённое начало'),
                  subtitle: Text(_dateTime(creditedStart)),
                  onTap: () async {
                    final selected = await _pickDateTime(creditedStart);
                    if (selected != null) {
                      update(() => creditedStart = selected);
                    }
                  },
                ),
              if (shift.status == ShiftStatus.completed) ...[
                ListTile(
                  title: const Text('Учтённый конец'),
                  subtitle: Text(_dateTime(creditedEnd)),
                  onTap: () async {
                    final selected = await _pickDateTime(creditedEnd);
                    if (selected != null) {
                      update(() => creditedEnd = selected);
                    }
                  },
                ),
                TextField(
                  controller: breakInput,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Неоплачиваемый перерыв, минуты',
                  ),
                ),
              ],
              TextField(
                controller: reasonInput,
                decoration: const InputDecoration(
                  labelText: 'Причина исправления',
                  hintText: 'Например: ошибся во времени',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    final breakMinutes = int.tryParse(breakInput.text.trim());
    final reason = reasonInput.text.trim();
    breakInput.dispose();
    reasonInput.dispose();
    if (saved != true) return;
    if (reason.isEmpty) {
      if (mounted) _showError(context, 'Укажите причину исправления');
      return;
    }
    if (shift.rateId != null && rateId == null) {
      if (mounted) _showError(context, 'Выберите тариф');
      return;
    }
    if (shift.status == ShiftStatus.completed && breakMinutes == null) {
      if (mounted) _showError(context, 'Укажите перерыв в минутах');
      return;
    }
    await _perform(() async {
      if (shift.status == ShiftStatus.planned) {
        await widget.repository.updatePlannedShift(
          shiftId: shift.id,
          projectId: projectId,
          plannedStart: plannedStart,
          plannedEnd: plannedEnd,
          reason: reason,
        );
        await reminders.cancel(shift.id);
        final updated = (await widget.repository.shifts())
            .singleWhere((item) => item.id == shift.id);
        await _scheduleReminder(updated);
      } else if (shift.status == ShiftStatus.armed) {
        await widget.repository.updateArmedShift(
          shiftId: shift.id,
          plannedStart: plannedStart,
          plannedEnd: plannedEnd,
          rateId: rateId,
          reason: reason,
        );
        await reminders.cancel(shift.id);
        if (plannedStart.isAfter(DateTime.now())) {
          final result = await reminders.schedule(
            shiftId: shift.id,
            when: plannedStart,
            projectName: shift.projectName,
            kind: ReminderKind.confirmStart,
          );
          if (Platform.isAndroid && !result.scheduled && mounted) {
            _showError(context, 'Время изменено, но напоминание не назначено');
          }
        }
      } else {
        await widget.repository.correctWorkedShift(
          shiftId: shift.id,
          creditedStart: creditedStart,
          creditedEnd: shift.status == ShiftStatus.completed ? creditedEnd : null,
          breakMinutes: shift.status == ShiftStatus.completed ? breakMinutes! : 0,
          rateId: rateId,
          reason: reason,
        );
      }
    });
  }

  Future<void> _cancelPlannedShift(WorkShift shift) async {
    final reasonInput = TextEditingController();
    final confirmed = await showFormDialogUntilClosed<bool>(
      context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отменить плановую смену?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${shift.projectName} · ${_dateTime(shift.plannedStart)}'),
          TextField(
            controller: reasonInput,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Причина отмены'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Назад')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Отменить смену')),
        ],
      ),
    );
    final reason = reasonInput.text.trim();
    reasonInput.dispose();
    if (confirmed != true) return;
    if (reason.isEmpty) {
      if (mounted) _showError(context, 'Укажите причину отмены');
      return;
    }
    await _perform(() async {
      await widget.repository.cancelPlannedShift(shift.id, reason);
      await reminders.cancel(shift.id);
    });
  }

  String _auditValue(String key, Object? value) {
    if (value == null) return '—';
    if (key == 'project_id') {
      for (final project in projects) {
        if (project.id == value) return project.name;
      }
    }
    if (key.endsWith('_ms')) {
      return _dateTime(DateTime.fromMillisecondsSinceEpoch(value as int));
    }
    return '$value';
  }

  String _eventDetails(ShiftEvent event) {
    if (event.kind == 'cancelled') {
      return 'Плановая смена отменена. Причина: ${event.reason ?? 'не указана'}';
    }
    if (event.before == null || event.after == null) {
      return switch (event.kind) {
        'planned' => 'Смена запланирована',
        'armed' => 'Предварительный check-in',
        'confirmed' => 'Начало подтверждено',
        'completed' => 'Смена завершена',
        _ => event.kind,
      };
    }
    const labels = <String, String>{
      'project_id': 'Проект',
      'planned_start_ms': 'Плановое начало',
      'planned_end_ms': 'Плановый конец',
      'rate_name_snapshot': 'Тариф',
      'rate_cents_snapshot': 'Ставка в центах',
      'currency_snapshot': 'Валюта',
      'credited_start_ms': 'Учтённое начало',
      'credited_end_ms': 'Учтённый конец',
      'break_minutes': 'Перерыв, мин',
    };
    final changes = <String>[];
    for (final entry in labels.entries) {
      final before = event.before![entry.key];
      final after = event.after![entry.key];
      if (before != after) {
        changes.add('${entry.value}: '
            '${_auditValue(entry.key, before)} → ${_auditValue(entry.key, after)}');
      }
    }
    final reason = event.reason == null ? '' : 'Причина: ${event.reason}\n';
    return '$reason${changes.isEmpty ? 'Параметры смены исправлены' : changes.join('\n')}';
  }

  Future<void> _showHistory(WorkShift shift) async {
    try {
      final events = await widget.repository.shiftEvents(shift.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: ListView(children: [
              const ListTile(title: Text('История смены')),
              for (final event in events)
                ListTile(
                  title: Text(_dateTime(event.recordedAt)),
                  subtitle: Text(_eventDetails(event)),
                ),
            ]),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _showProjectHistory(WorkProject project) async {
    try {
      final events = await widget.repository.projectEvents(project.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: ListView(children: [
              ListTile(title: Text('История проекта: ${project.name}')),
              for (final event in events)
                ListTile(
                  title: Text(_dateTime(event.recordedAt)),
                  subtitle: Text(event.description),
                ),
            ]),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Widget _shiftCard(WorkShift shift, {bool inPlan = false}) {
    final status = switch (shift.status) {
      ShiftStatus.planned => 'План',
      ShiftStatus.armed => 'Ожидает подтверждения',
      ShiftStatus.active => 'Идёт работа',
      ShiftStatus.completed => 'Завершена',
      ShiftStatus.cancelled => 'Отменена',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shift.projectName, style: Theme.of(context).textTheme.titleMedium),
          Text('${_dateTime(shift.plannedStart)} · $status'),
          if (shift.status == ShiftStatus.armed &&
              shift.plannedStart.isBefore(DateTime.now()))
            const Text('Плановое начало прошло. Подтвердите прибытие.'),
          if (shift.status == ShiftStatus.planned &&
              shift.plannedStart.isBefore(DateTime.now()))
            const Text('Плановое начало прошло. Сделайте check-in.'),
          if (shift.status == ShiftStatus.active &&
              shift.plannedEnd != null &&
              shift.plannedEnd!.isBefore(DateTime.now()))
            const Text('Плановый конец прошёл. Сделайте check-out.'),
          if (shift.rateName != null) Text('Тариф: ${shift.rateName}'),
          if (shift.status == ShiftStatus.completed &&
              shift.rateCentsPerHour != null)
            Text('${_duration(shift.paidMinutes)} · '
                '${_money(shift.earnedCents, shift.currency ?? 'EUR')}'),
          if (shift.status == ShiftStatus.completed &&
              shift.rateCentsPerHour == null)
            Text(_duration(shift.paidMinutes)),
          const SizedBox(height: 8),
          if (!inPlan) switch (shift.status) {
            ShiftStatus.planned => FilledButton.tonal(
                onPressed: () => _arm(shift),
                child: const Text('Предварительный check-in')),
            ShiftStatus.armed => FilledButton(
                onPressed: () => _confirm(shift),
                child: const Text('Подтвердить начало')),
            ShiftStatus.active => FilledButton(
                onPressed: () => _checkOut(shift),
                child: const Text('Check-out')),
            _ => const SizedBox.shrink(),
          },
          Wrap(spacing: 8, children: [
            if (!inPlan && shift.status != ShiftStatus.cancelled)
              TextButton.icon(
                onPressed: () => _editShift(shift),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Исправить'),
              ),
            if (inPlan && shift.status == ShiftStatus.planned) ...[
              TextButton.icon(
                onPressed: () => _editShift(shift),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Изменить план'),
              ),
              TextButton.icon(
                onPressed: () => _cancelPlannedShift(shift),
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Отменить'),
              ),
            ],
            TextButton.icon(
              onPressed: () => _showHistory(shift),
              icon: const Icon(Icons.history),
              label: const Text('История'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _today() {
    final now = DateTime.now();
    final today = shifts.where((shift) {
      final start = shift.plannedStart;
      return shift.status != ShiftStatus.cancelled &&
          ((start.year == now.year &&
              start.month == now.month &&
              start.day == now.day) ||
          shift.status == ShiftStatus.active);
    });
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Сегодня, ${_date(now)}',
          style: Theme.of(context).textTheme.headlineSmall),
      if (today.isEmpty) const Padding(
          padding: EdgeInsets.all(16), child: Text('На сегодня нет смен.')),
      for (final shift in today) _shiftCard(shift),
      OutlinedButton.icon(
          onPressed: _plan,
          icon: const Icon(Icons.add),
          label: const Text('Запланировать смену')),
    ]);
  }

  Widget _planPage() {
    final monday = DateTime(planWeek.year, planWeek.month,
        planWeek.day - planWeek.weekday + DateTime.monday);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('План на неделю', style: Theme.of(context).textTheme.headlineSmall),
      Row(children: [
        IconButton(
          onPressed: () => setState(() => planWeek =
              DateTime(monday.year, monday.month, monday.day - 7)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(child: Text('${_date(monday)} — ${_date(sunday)}',
            textAlign: TextAlign.center)),
        IconButton(
          onPressed: () => setState(() => planWeek =
              DateTime(monday.year, monday.month, monday.day + 7)),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      FilledButton.icon(
        onPressed: _plan,
        icon: const Icon(Icons.add),
        label: const Text('Добавить смену'),
      ),
      const Text('После check-in перенести или отменить день через план нельзя.'),
      for (var offset = 0; offset < 7; offset++) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(_date(DateTime(
              monday.year, monday.month, monday.day + offset)),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final shift in shifts.where((item) {
          final day = DateTime(monday.year, monday.month, monday.day + offset);
          return item.plannedStart.year == day.year &&
              item.plannedStart.month == day.month &&
              item.plannedStart.day == day.day;
        }))
          _shiftCard(shift, inPlan: true),
      ],
    ]);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'WorkHoursApp',
      applicationLegalese: '© 2026 Alexander. Лицензия MIT.',
      children: const [
        SizedBox(height: 12),
        Text('Создатель: Alexander (u-alexander-gb).'),
        SizedBox(height: 8),
        Text('Приложение для личного учёта рабочих смен, часов и тарифов.'),
        SizedBox(height: 8),
        SelectableText('github.com/u-alexander-gb/WorkHoursApp'),
      ],
    );
  }

  Widget _projectsPage() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Проекты',
            style: Theme.of(context).textTheme.headlineSmall),
        FilledButton.icon(
            onPressed: _createProject,
            icon: const Icon(Icons.add),
            label: const Text('Добавить проект')),
        if (projects.isEmpty) const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Создайте проект, затем добавьте его тарифы.')),
        for (final project in projects)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(project.name,
                    style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  title: const Text('Учитывать оплату'),
                  subtitle: Text(project.trackPay
                      ? 'Часы и начисления по тарифу'
                      : 'Только часы, без денежных сумм'),
                  value: project.trackPay,
                  onChanged: (enabled) => _perform(() =>
                      widget.repository.setProjectPayTracking(project.id, enabled)),
                ),
                if (project.trackPay) ...[
                  for (final rate in rates[project.id] ?? <WorkRate>[])
                    ListTile(
                      title: Text(rate.name),
                      trailing: Text('${_money(rate.centsPerHour, rate.currency)}/ч'),
                    ),
                  TextButton.icon(
                      onPressed: () => _createRate(project),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить тариф')),
                ],
                TextButton.icon(
                  onPressed: () => _showProjectHistory(project),
                  icon: const Icon(Icons.history),
                  label: const Text('История проекта'),
                ),
              ]),
            ),
          ),
      ]);

  DateTimeRange _range() {
    if (period == 'custom' && customRange != null) {
      final selected = customRange!;
      return DateTimeRange(
          start: DateTime(selected.start.year, selected.start.month, selected.start.day),
          end: DateTime(selected.end.year, selected.end.month, selected.end.day + 1));
    }
    if (period == 'day') {
      return DateTimeRange(
          start: DateTime(anchor.year, anchor.month, anchor.day),
          end: DateTime(anchor.year, anchor.month, anchor.day + 1));
    }
    if (period == 'month') {
      return DateTimeRange(
          start: DateTime(anchor.year, anchor.month),
          end: DateTime(anchor.year, anchor.month + 1));
    }
    final monday = DateTime(anchor.year, anchor.month,
        anchor.day - anchor.weekday + 1);
    return DateTimeRange(
        start: monday,
        end: DateTime(monday.year, monday.month, monday.day + 7));
  }

  void _movePeriod(int direction) => setState(() {
        anchor = switch (period) {
          'day' => DateTime(anchor.year, anchor.month, anchor.day + direction),
          'month' => DateTime(anchor.year, anchor.month + direction),
          _ => DateTime(anchor.year, anchor.month, anchor.day + direction * 7),
        };
      });

  List<WorkShift> _completedForRange(DateTimeRange range) => shifts.where((shift) {
        final start = shift.creditedStart;
        return shift.status == ShiftStatus.completed &&
            start != null &&
            !start.isBefore(range.start) &&
            start.isBefore(range.end);
      }).toList();

  Future<void> _exportReport(DateTimeRange range, List<WorkShift> completed) async {
    try {
      final csv = buildReportCsv(completed);
      final name = 'work-hours-${range.start.year}-${_two(range.start.month)}-'
          '${_two(range.start.day)}.csv';
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
        mimeType: 'text/csv',
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отчёт CSV сохранён')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Widget _reports() {
    final range = _range();
    final completed = _completedForRange(range);
    final minutes = completed.fold<int>(0, (sum, s) => sum + s.paidMinutes);
    final totals = <String, int>{};
    for (final shift in completed) {
      if (shift.rateCentsPerHour == null) continue;
      final currency = shift.currency ?? 'EUR';
      totals[currency] = (totals[currency] ?? 0) + shift.earnedCents;
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Отчёты', style: Theme.of(context).textTheme.headlineSmall),
      DropdownButton<String>(
        value: period,
        items: const [
          DropdownMenuItem(value: 'day', child: Text('День')),
          DropdownMenuItem(value: 'week', child: Text('Неделя')),
          DropdownMenuItem(value: 'month', child: Text('Месяц')),
          DropdownMenuItem(value: 'custom', child: Text('Выбранный период')),
        ],
        onChanged: (value) async {
          if (value == null) return;
          if (value == 'custom') {
            final selection = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDateRange: customRange);
            if (selection == null || !mounted) return;
            setState(() {
              period = value;
              customRange = selection;
            });
          } else {
            setState(() => period = value);
          }
        },
      ),
      Row(children: [
        if (period != 'custom')
          IconButton(
              onPressed: () => _movePeriod(-1),
              icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('${_date(range.start)} — '
            '${_date(range.end.subtract(const Duration(days: 1)))}')),
        if (period != 'custom')
          IconButton(
              onPressed: () => _movePeriod(1),
              icon: const Icon(Icons.chevron_right)),
      ]),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Учтённое время: ${_duration(minutes)}'),
          for (final total in totals.entries)
            Text('Сумма: ${_money(total.value, total.key)}'),
          if (completed.isEmpty) const Text('Завершённых смен нет.'),
        ]),
      )),
      OutlinedButton.icon(
        onPressed: completed.isEmpty ? null : () => _exportReport(range, completed),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Сохранить отчёт CSV'),
      ),
      for (final shift in completed) _shiftCard(shift),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Сегодня', 'План', 'Проекты', 'Отчёты'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Меню',
            onSelected: (value) {
              if (value == 'export') {
                _exportBackup();
              } else if (value == 'import') {
                _importBackup();
              } else if (value == 'about') {
                _showAbout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Сохранить копию')),
              PopupMenuItem(value: 'import', child: Text('Восстановить копию')),
              PopupMenuItem(value: 'about', child: Text('О приложении')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : switch (tab) {
                0 => _today(),
                1 => _planPage(),
                2 => _projectsPage(),
                _ => _reports(),
              },
      ))),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Сегодня'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'План'),
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Проекты'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Отчёты'),
        ],
      ),
    );
  }
}
