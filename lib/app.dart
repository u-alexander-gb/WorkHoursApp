import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

  Future<void> _exportBackup() async {
    try {
      final contents = await widget.repository.exportBackup();
      final now = DateTime.now();
      final name = 'work-hours-${now.year}-${_two(now.month)}-${_two(now.day)}.json';
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
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
        allowedExtensions: ['json'],
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Восстановить данные?'),
          content: Text('Текущие проекты, тарифы и смены будут заменены '
              'данными из файла ${file.name}. Перед продолжением сохраните '
              'копию текущих данных.'),
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
      final previousArmed = shifts.where((s) => s.status == ShiftStatus.armed).toList();
      await widget.repository.restoreBackup(utf8.decode(bytes));
      for (final shift in previousArmed) {
        await reminders.cancel(shift.id);
      }
      final restored = await widget.repository.shifts();
      for (final shift in restored) {
        if (shift.status == ShiftStatus.armed &&
            shift.plannedStart.isAfter(DateTime.now())) {
          await reminders.schedule(
            shiftId: shift.id,
            start: shift.plannedStart,
            projectName: shift.projectName,
          );
        }
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

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый проект'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название работы или проекта'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (result != null) {
      await _perform(() => widget.repository.addProject(result));
    }
    controller.dispose();
  }

  Future<void> _createRate(WorkProject project) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
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
    var start = DateTime(now.year, now.month, now.day + 1, 10);
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
      await _perform(() => widget.repository.planShift(
          projectId: result.$1, start: result.$2, end: result.$3));
    }
  }

  Future<void> _arm(WorkShift shift) async {
    final available = rates[shift.projectId] ?? [];
    if (available.isEmpty) {
      _showError(context, 'Сначала добавьте тариф для проекта');
      return;
    }
    final rateId = await showDialog<String>(
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
    if (rateId != null) {
      await _perform(() async {
        await widget.repository.armShift(shift.id, rateId);
        final reminder = await reminders.schedule(
          shiftId: shift.id,
          start: shift.plannedStart,
          projectName: shift.projectName,
        );
        if (mounted && !reminder.scheduled) {
          _showError(context, 'Напоминание не назначено. Проверьте разрешения.');
        } else if (mounted && !reminder.exact) {
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
      });
    }
  }

  Future<void> _checkOut(WorkShift shift) async {
    final breakInput = TextEditingController(text: '0');
    var end = DateTime.now();
    final result = await showDialog<(DateTime, int)>(
      context: context,
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
      await _perform(() => widget.repository.checkOut(
          shift.id, result.$1, breakMinutes: result.$2));
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
    final saved = await showDialog<bool>(
      context: context,
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
                    final selected = await _pickDateTime(plannedStart);
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
                    final selected = await _pickDateTime(plannedEnd);
                    if (selected != null) {
                      update(() => plannedEnd = selected);
                    }
                  },
                ),
              ],
              if (shift.status != ShiftStatus.planned)
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
                  title: const Text('Оплачиваемое начало'),
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
                  title: const Text('Оплачиваемый конец'),
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
    if (shift.status != ShiftStatus.planned && rateId == null) {
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
      } else if (shift.status == ShiftStatus.armed) {
        await widget.repository.updateArmedShift(
          shiftId: shift.id,
          plannedStart: plannedStart,
          plannedEnd: plannedEnd,
          rateId: rateId!,
          reason: reason,
        );
        await reminders.cancel(shift.id);
        if (plannedStart.isAfter(DateTime.now())) {
          final result = await reminders.schedule(
            shiftId: shift.id,
            start: plannedStart,
            projectName: shift.projectName,
          );
          if (!result.scheduled && mounted) {
            _showError(context, 'Время изменено, но напоминание не назначено');
          }
        }
      } else {
        await widget.repository.correctWorkedShift(
          shiftId: shift.id,
          creditedStart: creditedStart,
          creditedEnd: shift.status == ShiftStatus.completed ? creditedEnd : null,
          breakMinutes: shift.status == ShiftStatus.completed ? breakMinutes! : 0,
          rateId: rateId!,
          reason: reason,
        );
      }
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
      'credited_start_ms': 'Оплачиваемое начало',
      'credited_end_ms': 'Оплачиваемый конец',
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

  Widget _shiftCard(WorkShift shift) {
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
          if (shift.rateName != null) Text('Тариф: ${shift.rateName}'),
          if (shift.status == ShiftStatus.completed)
            Text('${_duration(shift.paidMinutes)} · '
                '${_money(shift.earnedCents, shift.currency ?? 'EUR')}'),
          const SizedBox(height: 8),
          switch (shift.status) {
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
            TextButton.icon(
              onPressed: () => _editShift(shift),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Исправить'),
            ),
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
      return (start.year == now.year &&
              start.month == now.month &&
              start.day == now.day) ||
          shift.status == ShiftStatus.active;
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

  Widget _planPage() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Смены', style: Theme.of(context).textTheme.headlineSmall),
        FilledButton.icon(
            onPressed: _plan,
            icon: const Icon(Icons.add),
            label: const Text('Добавить смену')),
        if (shifts.isEmpty) const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Пока нет запланированных смен.')),
        for (final shift in shifts) _shiftCard(shift),
      ]);

  Widget _projectsPage() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Проекты и тарифы',
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
                for (final rate in rates[project.id] ?? <WorkRate>[])
                  ListTile(
                    title: Text(rate.name),
                    trailing: Text('${_money(rate.centsPerHour, rate.currency)}/ч'),
                  ),
                TextButton.icon(
                    onPressed: () => _createRate(project),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить тариф')),
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
          Text('Оплачиваемое время: ${_duration(minutes)}'),
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
            tooltip: 'Резервная копия',
            onSelected: (value) {
              if (value == 'export') {
                _exportBackup();
              } else {
                _importBackup();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Сохранить копию')),
              PopupMenuItem(value: 'import', child: Text('Восстановить копию')),
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
