import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'src/backup_codec.dart';
import 'src/app_text.dart';
import 'src/plan_calendar.dart';
import 'src/time_deviation.dart';
import 'src/work_repository.dart';
import 'src/reminder_service.dart';
import 'src/reminder_settings.dart';
import 'src/report_csv.dart';

void _showError(BuildContext context, Object error) {
  final message = switch (error) {
    StateError e => e.message,
    ArgumentError e => '${e.message}',
    FormatException e => e.message,
    _ => '$error',
  };
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText(message)));
}

String _two(int number) => number.toString().padLeft(2, '0');
String _date(DateTime date) => '${_two(date.day)}.${_two(date.month)}.${date.year}';
String _time(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';
String _dateTime(DateTime date) => '${_date(date)} ${_time(date)}';
String _duration(BuildContext context, int minutes) =>
    '${minutes ~/ 60}${appText(context, ' ч ')}'
    '${_two(minutes % 60)}${appText(context, ' мин')}';
String _timeLeft(BuildContext context, Duration duration) {
  final minutes = (duration.inSeconds.abs() + 59) ~/ 60;
  final days = minutes ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final rest = minutes % 60;
  return days > 0
      ? '$days${appText(context, ' д ')}$hours${appText(context, ' ч')}'
      : '$hours${appText(context, ' ч ')}${_two(rest)}${appText(context, ' мин')}';
}
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
        title: AppText(widget.create
            ? 'Пароль резервной копии'
            : 'Открыть резервную копию'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppText(widget.create
              ? 'Запомните пароль: без него восстановить копию нельзя. Минимум 12 символов.'
              : 'Введите пароль для проверки и просмотра копии.'),
          TextField(
            controller: password,
            obscureText: hidden,
            autofocus: true,
            decoration: InputDecoration(labelText: appText(context, 'Пароль')),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.create)
            TextField(
              controller: repeated,
              obscureText: hidden,
              decoration: InputDecoration(
                labelText: appText(context, 'Повторите пароль'),
                errorText: repeated.text.isNotEmpty &&
                        repeated.text != password.text
                    ? appText(context, 'Пароли не совпадают')
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const AppText('Показать пароль'),
            value: !hidden,
            onChanged: (value) => setState(() => hidden = value != true),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('Отмена'),
          ),
          FilledButton(
            onPressed: password.text.isEmpty ||
                    (widget.create &&
                        (password.text.length < 12 ||
                            repeated.text != password.text))
                ? null
                : () => Navigator.pop(context, password.text),
            child: AppText(widget.create ? 'Продолжить' : 'Проверить'),
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
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  String? languageCode;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final saved = await preferences.getString('language_code');
      if (mounted && saved != null &&
          const ['en', 'ru', 'uk', 'pl', 'es', 'tr', 'uz'].contains(saved)) {
        setState(() => languageCode = saved);
      }
    } catch (_) {
      // The system locale remains available when preferences cannot be read.
    }
  }

  Future<void> _changeLanguage(String? code) async {
    setState(() => languageCode = code);
    if (code == null) {
      await preferences.remove('language_code');
    } else {
      await preferences.setString('language_code', code);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => appText(context, 'Учёт рабочего времени'),
        locale: languageCode == null ? null : Locale(languageCode!),
        supportedLocales: const [
          Locale('en'), Locale('ru'), Locale('uk'), Locale('pl'),
          Locale('es'), Locale('tr'), Locale('uz'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
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
                  body: Center(child: AppText('Ошибка базы данных: ${snapshot.error}')));
            }
            if (!snapshot.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return WorkHome(
              repository: snapshot.data!,
              languageCode: languageCode,
              onLanguageChanged: _changeLanguage,
            );
          },
        ),
      );
}

class WorkHome extends StatefulWidget {
  const WorkHome({super.key, required this.repository,
      required this.languageCode, required this.onLanguageChanged});
  final WorkRepository repository;
  final String? languageCode;
  final ValueChanged<String?> onLanguageChanged;

  @override
  State<WorkHome> createState() => _WorkHomeState();
}

class _WorkHomeState extends State<WorkHome> {
  final ReminderService reminders = ReminderService();
  PackageInfo? packageInfo;
  String get _effectiveLanguageCode {
    if (widget.languageCode != null) return widget.languageCode!;
    for (final locale in WidgetsBinding.instance.platformDispatcher.locales) {
      if (const ['en', 'ru', 'uk', 'pl', 'es', 'tr', 'uz']
          .contains(locale.languageCode)) {
        return locale.languageCode;
      }
    }
    return 'en';
  }
  int tab = 0;
  bool loading = true;
  List<WorkProject> projects = [];
  List<WorkShift> shifts = [];
  Map<String, List<WorkRate>> rates = {};
  String period = 'week';
  DateTime anchor = DateTime.now();
  DateTime planWeek = DateTime.now();
  bool calendarView = false;
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  ReminderSettings reminderSettings = const ReminderSettings();
  Timer? clockTimer;
  DateTimeRange? customRange;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    reminders.onTap = () {
      if (!mounted) return;
      setState(() => tab = 0);
      _reload();
    };
    _reload();
    _loadPlanView();
    _loadReminderSettings();
    clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => packageInfo = info);
    } catch (_) {
      // The rest of the app remains usable if package metadata is unavailable.
    }
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPlanView() async {
    try {
      final saved = await preferences.getBool('plan_calendar_view');
      if (mounted && saved != null) setState(() => calendarView = saved);
    } catch (_) {
      // The list view remains usable if platform preferences are unavailable.
    }
  }

  Future<void> _setCalendarView(bool value) async {
    setState(() => calendarView = value);
    try {
      await preferences.setBool('plan_calendar_view', value);
    } catch (error) {
      if (mounted) {
        _showError(context, 'Не удалось сохранить вид плана: $error');
      }
    }
  }

  Future<void> _loadReminderSettings() async {
    try {
      final startTiming = await preferences.getString('reminder_start_timing');
      final endTiming = await preferences.getString('reminder_end_timing');
      reminderSettings = ReminderSettings(
        startEnabled: await preferences.getBool('reminder_start_enabled') ?? true,
        endEnabled: await preferences.getBool('reminder_end_enabled') ?? true,
        startTiming: ReminderTiming.values.where((v) => v.name == startTiming)
            .firstOrNull ?? ReminderTiming.atTime,
        endTiming: ReminderTiming.values.where((v) => v.name == endTiming)
            .firstOrNull ?? ReminderTiming.atTime,
        eveningHour: await preferences.getInt('reminder_evening_hour') ?? 19,
      );
      if (mounted) setState(() {});
      for (final shift in await widget.repository.shifts()) {
        await _rescheduleShift(shift);
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _saveReminderSettings(ReminderSettings value) async {
    try {
      await preferences.setBool('reminder_start_enabled', value.startEnabled);
      await preferences.setBool('reminder_end_enabled', value.endEnabled);
      await preferences.setString('reminder_start_timing', value.startTiming.name);
      await preferences.setString('reminder_end_timing', value.endTiming.name);
      await preferences.setInt('reminder_evening_hour', value.eveningHour);
      setState(() => reminderSettings = value);
      for (final shift in await widget.repository.shifts()) {
        await _rescheduleShift(shift);
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
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
          const SnackBar(content: AppText('Резервная копия сохранена')),
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
          title: const AppText('Восстановить данные?'),
          content: AppText('${appText(context, 'Файл')}: ${file.name}\n'
              '${appText(context, 'Создан')}: ${_dateTime(preview.createdAt.toLocal())}\n'
              '${appText(context, 'Проектов')}: ${preview.counts['projects']}, '
              '${appText(context, 'тарифов')}: ${preview.counts['rates']}\n'
              '${appText(context, 'Смен')}: ${preview.counts['shifts']}, '
              '${appText(context, 'событий')}: ${preview.counts['shift_events']}\n\n'
              '${appText(context, encrypted ? 'Пароль и целостность проверены.' : 'Старая копия без шифрования.')}\n'
              '${appText(context, 'Текущие данные будут заменены. Сначала сохраните их копию.')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('Восстановить'),
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
        await _rescheduleShift(shift);
      }
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('Данные восстановлены')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _rescheduleShift(WorkShift shift) async {
    await reminders.cancel(shift.id);
    if (shift.status == ShiftStatus.cancelled ||
        shift.status == ShiftStatus.completed) {
      return;
    }
    if (reminderSettings.startEnabled &&
        shift.plannedStart.isAfter(DateTime.now())) {
      await reminders.schedule(
        shiftId: shift.id,
        when: reminderSettings.when(shift.plannedStart, reminderSettings.startTiming),
        projectName: shift.projectName,
        kind: shift.status == ShiftStatus.planned
            ? ReminderKind.checkIn : ReminderKind.start,
        languageCode: _effectiveLanguageCode,
      );
    }
    if (reminderSettings.endEnabled &&
        shift.status != ShiftStatus.planned) {
      final due = shift.plannedEnd ??
          shift.plannedStart.add(const Duration(hours: 8));
      await reminders.schedule(
        shiftId: shift.id,
        when: reminderSettings.when(due, reminderSettings.endTiming),
        projectName: shift.projectName,
        kind: ReminderKind.checkOut,
        languageCode: _effectiveLanguageCode,
      );
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
          title: const AppText('Новый проект'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: appText(context, 'Название работы или проекта')),
            ),
            SwitchListTile(
              title: const AppText('Учитывать оплату'),
              subtitle: const AppText('Выключено: учитываются только часы'),
              value: trackPay,
              onChanged: (value) => update(() => trackPay = value),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const AppText('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (controller.text, trackPay)),
                child: const AppText('Сохранить')),
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
        title: AppText('${appText(context, 'Тариф')}: ${project.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: InputDecoration(labelText: appText(context, 'Название тарифа'))),
          TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: appText(context, 'Евро за час'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const AppText('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, (name.text, amount.text)),
              child: const AppText('Сохранить')),
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
          title: const AppText('Запланировать смену'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: projectId,
              decoration: InputDecoration(labelText: appText(context, 'Проект')),
              items: projects
                  .map((p) => DropdownMenuItem(value: p.id, child: AppText(p.name)))
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  update(() => projectId = id);
                }
              },
            ),
            ListTile(
              title: const AppText('Начало'),
              subtitle: AppText(_dateTime(start)),
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
              title: const AppText('Ожидаемый конец'),
              subtitle: AppText(_dateTime(end)),
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
                child: const AppText('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (projectId, start, end)),
                child: const AppText('Добавить')),
          ],
        ),
      ),
    );
    if (result != null) {
      await _perform(() async {
        final id = await widget.repository.planShift(
            projectId: result.$1, start: result.$2, end: result.$3);
        final planned = (await widget.repository.shifts())
            .singleWhere((item) => item.id == id);
        await _rescheduleShift(planned);
      });
      if (mounted) setState(() => planWeek = result.$2);
    }
  }

  Future<void> _checkIn(WorkShift shift) async {
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
          title: const AppText('Выберите тариф'),
          children: available
              .map((rate) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, rate.id),
                    child: AppText('${rate.name} — '
                        '${_money(rate.centsPerHour, rate.currency)}${appText(context, '/ч')}'),
                  ))
              .toList(),
        ),
      );
      if (rateId == null) return;
    }
    if (mounted) {
      await _perform(() async {
        await widget.repository.checkInShift(shift.id, rateId);
        final active = (await widget.repository.shifts())
            .singleWhere((item) => item.id == shift.id);
        await _rescheduleShift(active);
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
          title: const AppText('Завершить смену'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: const AppText('Время окончания'),
              subtitle: AppText(_dateTime(end)),
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
              decoration: InputDecoration(
                  labelText: appText(context, 'Неоплачиваемый перерыв, минуты')),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const AppText('Отмена')),
            FilledButton(
              onPressed: () {
                final minutes = int.tryParse(breakInput.text.trim());
                if (minutes != null) {
                  Navigator.pop(dialogContext, (end, minutes));
                }
              },
              child: const AppText('Check-out'),
            ),
          ],
        ),
      ),
    );
    breakInput.dispose();
    if (result != null) {
      final approval = await _approveDeviation(
          endDeviation(shift.plannedEnd, result.$1));
      if (approval == null || !mounted) return;
      await _perform(() async {
        await widget.repository.checkOut(
            shift.id, result.$1, breakMinutes: result.$2,
            reason: approval);
        await reminders.cancel(shift.id);
      });
    }
  }

  Future<String?> _approveDeviation(TimeDeviation? deviation) async {
    if (deviation == null) return '';
    final significant = deviation.severity == DeviationSeverity.significant;
    final reasonInput = TextEditingController();
    final approved = await showFormDialogUntilClosed<bool>(
      context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(significant ? 'Проверьте время' : 'Отклонение от плана'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DeviationNotice(deviation: deviation),
          if (significant) ...[
            const AppText('Проверьте время. При необходимости укажите причину.'),
            TextField(
              controller: reasonInput,
              decoration: InputDecoration(labelText: appText(context, 'Причина (необязательно)')),
            ),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('Назад')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('Сохранить фактическое время')),
        ],
      ),
    );
    final reason = reasonInput.text.trim();
    reasonInput.dispose();
    return approved == true ? reason : null;
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
          title: const AppText('Исправить смену'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (shift.status == ShiftStatus.planned)
                DropdownButtonFormField<String>(
                  initialValue: projectId,
                  decoration: InputDecoration(labelText: appText(context, 'Проект')),
                  items: projects
                      .map((p) => DropdownMenuItem(value: p.id, child: AppText(p.name)))
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
                  title: const AppText('Плановое начало'),
                  subtitle: AppText(_dateTime(plannedStart)),
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
                  title: const AppText('Плановый конец'),
                  subtitle: AppText(_dateTime(plannedEnd)),
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
                  decoration: InputDecoration(labelText: appText(context, 'Тариф')),
                  items: availableRates
                      .map((rate) => DropdownMenuItem(
                            value: rate.id,
                            child: AppText('${rate.name} — '
                                '${_money(rate.centsPerHour, rate.currency)}${appText(context, '/ч')}'),
                          ))
                      .toList(),
                  onChanged: (value) => update(() => rateId = value),
                ),
              if ((shift.status == ShiftStatus.active &&
                      !creditedStart.isAfter(DateTime.now())) ||
                  shift.status == ShiftStatus.completed)
                ListTile(
                  title: const AppText('Учтённое начало'),
                  subtitle: AppText(_dateTime(creditedStart)),
                  onTap: () async {
                    final selected = await _pickDateTime(creditedStart);
                    if (selected != null) {
                      update(() => creditedStart = selected);
                    }
                  },
                ),
              if (shift.status == ShiftStatus.completed) ...[
                ListTile(
                  title: const AppText('Учтённый конец'),
                  subtitle: AppText(_dateTime(creditedEnd)),
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
                  decoration: InputDecoration(
                    labelText: appText(context, 'Неоплачиваемый перерыв, минуты'),
                  ),
                ),
              ],
              TextField(
                controller: reasonInput,
                decoration: InputDecoration(
                  labelText: appText(context, 'Причина исправления'),
                  hintText: appText(context, 'Например: ошибся во времени'),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const AppText('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const AppText('Сохранить')),
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
        await _rescheduleShift(updated);
      } else if (shift.status == ShiftStatus.armed) {
        await widget.repository.updateArmedShift(
          shiftId: shift.id,
          plannedStart: plannedStart,
          plannedEnd: plannedEnd,
          rateId: rateId,
          reason: reason,
        );
        final updated = (await widget.repository.shifts())
            .singleWhere((item) => item.id == shift.id);
        await _rescheduleShift(updated);
      } else if (shift.status == ShiftStatus.active &&
          creditedStart.isAfter(DateTime.now())) {
        if (creditedStart != shift.creditedStart) {
          throw StateError('Будущее начало пока нельзя исправить');
        }
        await widget.repository.changeShiftRate(
          shiftId: shift.id, rateId: rateId, reason: reason);
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
    final defaultReason = appText(context, 'Удалено пользователем');
    final confirmed = await showFormDialogUntilClosed<bool>(
      context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('Удалить плановую смену?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppText('${shift.projectName} · ${_dateTime(shift.plannedStart)}'),
          TextField(
            controller: reasonInput,
            autofocus: true,
            decoration: InputDecoration(labelText: appText(context, 'Причина удаления')),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('Назад')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('Удалить смену')),
        ],
      ),
    );
    final reason = reasonInput.text.trim().isEmpty
        ? defaultReason : reasonInput.text.trim();
    reasonInput.dispose();
    if (confirmed != true) return;
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
      return '${appText(context, 'Плановая смена удалена. Причина')}: '
          '${event.reason ?? appText(context, 'не указана')}';
    }
    if (event.kind == 'confirmed' || event.kind == 'completed') {
      final label = event.kind == 'confirmed'
          ? 'Начало подтверждено'
          : 'Смена завершена';
      return event.reason == null ? appText(context, label)
          : '${appText(context, label)}. ${appText(context, 'Причина')}: ${event.reason}';
    }
    if (event.before == null || event.after == null) {
      return switch (event.kind) {
        'planned' => appText(context, 'Смена запланирована'),
        'armed' => appText(context, 'Предварительный check-in'),
        'confirmed' => appText(context, 'Начало подтверждено'),
        'completed' => appText(context, 'Смена завершена'),
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
        changes.add('${appText(context, entry.value)}: '
            '${_auditValue(entry.key, before)} → ${_auditValue(entry.key, after)}');
      }
    }
    final reason = event.reason == null ? ''
        : '${appText(context, 'Причина')}: ${event.reason}\n';
    return '$reason${changes.isEmpty ? appText(context, 'Параметры смены исправлены') : changes.join('\n')}';
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
              const ListTile(title: AppText('История смены')),
              for (final event in events)
                ListTile(
                  title: AppText(_dateTime(event.recordedAt)),
                  subtitle: AppText(_eventDetails(event)),
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
              ListTile(title: AppText('${appText(context, 'История проекта')}: ${project.name}')),
              for (final event in events)
                ListTile(
                  title: AppText(_dateTime(event.recordedAt)),
                  subtitle: AppText(event.description),
                ),
            ]),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _chooseLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => LanguagePickerDialog(selectedLanguageCode: widget.languageCode),
    );
    if (selected != null) {
      widget.onLanguageChanged(selected == 'system' ? null : selected);
    }
  }

  Future<void> _chooseReminders() async {
    final chosen = await showDialog<ReminderSettings>(
      context: context,
      builder: (_) => ReminderSettingsDialog(settings: reminderSettings),
    );
    if (chosen != null && mounted) await _saveReminderSettings(chosen);
  }

  Widget? _shiftCountdown(WorkShift shift) {
    final now = DateTime.now();
    final active = shift.status == ShiftStatus.active &&
        !(shift.creditedStart?.isAfter(now) ?? false);
    if (!active && shift.status != ShiftStatus.planned &&
        shift.status != ShiftStatus.armed) {
      return null;
    }
    final due = active ? shift.plannedEnd :
        (shift.creditedStart ?? shift.plannedStart);
    if (due == null) return null;
    final begin = active
        ? (shift.creditedStart ?? shift.plannedStart)
        : due.subtract(const Duration(hours: 24));
    final total = due.difference(begin).inSeconds;
    final progress = total <= 0
        ? 1.0
        : (now.difference(begin).inSeconds / total).clamp(0.0, 1.0).toDouble();
    final left = due.difference(now);
    final label = active ? appText(context, 'планового конца')
        : appText(context, 'начала');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText(left.isNegative
            ? '${appText(context, 'Время')} $label ${appText(context, 'прошло на')} ${_timeLeft(context, left)}'
            : '${appText(context, 'До')} $label: ${_timeLeft(context, left)}'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: progress),
      ]),
    );
  }

  Widget _shiftCard(WorkShift shift, {bool inPlan = false, bool inToday = false}) {
    final countdown = inToday ? _shiftCountdown(shift) : null;
    final waiting = shift.status == ShiftStatus.active &&
        (shift.creditedStart?.isAfter(DateTime.now()) ?? false);
    final visualStatus = visibleShiftStatus(shift, DateTime.now());
    final status = waiting ? 'Check-in сделан · ожидание начала' : switch (shift.status) {
      ShiftStatus.planned => 'План',
      ShiftStatus.armed => 'Check-in сделан · ожидание начала',
      ShiftStatus.active => 'Идёт работа',
      ShiftStatus.completed => 'Завершена',
      ShiftStatus.cancelled => 'Отменена',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppText('№${shift.rowId} · ${shift.projectName}',
              style: Theme.of(context).textTheme.titleMedium),
          AnimatedSwitcher(duration: const Duration(milliseconds: 250),
            child: Row(key: ValueKey(visualStatus), children: [
            Icon(shiftStatusIcon(visualStatus), size: 19,
                color: shiftStatusColor(visualStatus,
                    Theme.of(context).colorScheme)),
            const SizedBox(width: 6),
            Expanded(child: AppText('${_dateTime(shift.plannedStart)} · ${appText(context, status)}')),
          ])),
          ?countdown,
          if (shift.preCheckInAt != null)
            AppText('${appText(context, 'Check-in сделан')}: ${_dateTime(shift.preCheckInAt!)}'),
          if (shift.creditedStart != null) ...[
            AppText('${appText(context, 'Учтённое начало')}: ${_dateTime(shift.creditedStart!)}'),
            if (startDeviation(shift.plannedStart, shift.creditedStart!)
                case final deviation?)
              DeviationNotice(deviation: deviation),
          ],
          if (shift.creditedEnd != null) ...[
            AppText('${appText(context, 'Учтённый конец')}: ${_dateTime(shift.creditedEnd!)}'),
            if (endDeviation(shift.plannedEnd, shift.creditedEnd!)
                case final deviation?)
              DeviationNotice(deviation: deviation),
          ],
          if (shift.status == ShiftStatus.planned &&
              shift.plannedStart.isBefore(DateTime.now()))
            const AppText('Плановое начало прошло. Сделайте check-in.'),
          if (shift.status == ShiftStatus.active && !waiting &&
              shift.plannedEnd != null &&
              shift.plannedEnd!.isBefore(DateTime.now()))
            const AppText('Плановый конец прошёл. Сделайте check-out.'),
          if (shift.rateName != null) AppText('${appText(context, 'Тариф')}: ${shift.rateName}'),
          if (shift.status == ShiftStatus.completed &&
              shift.rateCentsPerHour != null)
            AppText('${_duration(context, shift.paidMinutes)} · '
                '${_money(shift.earnedCents, shift.currency ?? 'EUR')}'),
          if (shift.status == ShiftStatus.completed &&
              shift.rateCentsPerHour == null)
            AppText(_duration(context, shift.paidMinutes)),
          const SizedBox(height: 8),
          if (!inPlan) switch (shift.status) {
            ShiftStatus.planned => FilledButton.tonal(
                onPressed: () => _checkIn(shift),
                child: const AppText('Check-in')),
            ShiftStatus.armed => const SizedBox.shrink(),
            ShiftStatus.active => FilledButton(
                onPressed: waiting ? null : () => _checkOut(shift),
                child: const AppText('Check-out')),
            _ => const SizedBox.shrink(),
          },
          Wrap(spacing: 8, children: [
            if (!inPlan && shift.status != ShiftStatus.cancelled)
              TextButton.icon(
                onPressed: () => _editShift(shift),
                icon: const Icon(Icons.edit_outlined),
                label: const AppText('Исправить'),
              ),
            if (inPlan && shift.status == ShiftStatus.planned) ...[
              TextButton.icon(
                onPressed: () => _editShift(shift),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const AppText('Изменить план'),
              ),
              TextButton.icon(
                onPressed: () => _cancelPlannedShift(shift),
                icon: const Icon(Icons.delete_outline),
                label: const AppText('Удалить'),
              ),
            ],
            TextButton.icon(
              onPressed: () => _showHistory(shift),
              icon: const Icon(Icons.history),
              label: const AppText('История'),
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
      AppText('${appText(context, 'Сегодня')}, ${_date(now)}',
          style: Theme.of(context).textTheme.headlineSmall),
      if (today.isEmpty) ...[
        const Padding(padding: EdgeInsets.all(16),
            child: AppText('Сегодня смен нет.')),
        TextButton.icon(
          onPressed: () => setState(() => tab = 1),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const AppText('Посмотреть расписание'),
        ),
      ],
      for (final shift in today) _shiftCard(shift, inToday: true),
      OutlinedButton.icon(
          onPressed: _plan,
          icon: const Icon(Icons.add),
          label: const AppText('Запланировать смену')),
    ]);
  }

  Widget _planPage() {
    final monday = DateTime(planWeek.year, planWeek.month,
        planWeek.day - planWeek.weekday + DateTime.monday);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppText(calendarView ? 'План на месяц' : 'План на неделю',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.view_list_outlined),
              label: AppText('Список')),
          ButtonSegment(value: true, icon: Icon(Icons.calendar_month_outlined),
              label: AppText('Календарь')),
        ],
        selected: {calendarView},
        onSelectionChanged: (selection) => _setCalendarView(selection.first),
      ),
      Row(children: [
        IconButton(
          onPressed: () => setState(() => planWeek = calendarView
              ? DateTime(planWeek.year, planWeek.month - 1, 1)
              : DateTime(monday.year, monday.month, monday.day - 7)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(child: AppText(calendarView
            ? '${_two(planWeek.month)}.${planWeek.year}'
            : '${_date(monday)} — ${_date(sunday)}',
            textAlign: TextAlign.center)),
        IconButton(
          onPressed: () => setState(() => planWeek = calendarView
              ? DateTime(planWeek.year, planWeek.month + 1, 1)
              : DateTime(monday.year, monday.month, monday.day + 7)),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      FilledButton.icon(
        onPressed: _plan,
        icon: const Icon(Icons.add),
        label: const AppText('Добавить смену'),
      ),
      const AppText('После check-in перенести или отменить день через план нельзя.'),
      if (calendarView) ...[
        PlanCalendar(
          month: planWeek,
          selectedDay: planWeek,
          shifts: shifts.where((item) =>
              item.status != ShiftStatus.cancelled).toList(),
          onSelectDay: (day) => setState(() => planWeek = day),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: AppText(_date(planWeek),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (!shifts.any((shift) => shift.status != ShiftStatus.cancelled &&
            sameCalendarDay(shift.plannedStart, planWeek)))
          const AppText('На выбранный день смен нет.'),
        for (final shift in shifts.where((item) =>
            item.status != ShiftStatus.cancelled &&
            sameCalendarDay(item.plannedStart, planWeek)))
          _shiftCard(shift, inPlan: true),
      ] else for (var offset = 0; offset < 7; offset++) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: AppText(_date(DateTime(
              monday.year, monday.month, monday.day + offset)),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final shift in shifts.where((item) {
          final day = DateTime(monday.year, monday.month, monday.day + offset);
          return item.status != ShiftStatus.cancelled &&
              item.plannedStart.year == day.year &&
              item.plannedStart.month == day.month &&
              item.plannedStart.day == day.day;
        }))
          _shiftCard(shift, inPlan: true),
      ],
      if (shifts.any((shift) => shift.status == ShiftStatus.cancelled))
        ExpansionTile(
          title: const AppText('Удалённые смены и история'),
          children: [
            for (final shift in shifts.where((item) =>
                item.status == ShiftStatus.cancelled))
              ListTile(
                title: AppText('№${shift.rowId} · ${shift.projectName}'),
                subtitle: AppText(_dateTime(shift.plannedStart)),
                trailing: const Icon(Icons.history),
                onTap: () => _showHistory(shift),
              ),
          ],
        ),
    ]);
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (_) => WorkHoursAboutDialog(version: packageInfo == null
          ? '—'
          : '${packageInfo!.version}+${packageInfo!.buildNumber}'),
    );
  }

  Widget _projectsPage() => ListView(padding: const EdgeInsets.all(16), children: [
        AppText('Проекты',
            style: Theme.of(context).textTheme.headlineSmall),
        FilledButton.icon(
            onPressed: _createProject,
            icon: const Icon(Icons.add),
            label: const AppText('Добавить проект')),
        if (projects.isEmpty) const Padding(
            padding: EdgeInsets.all(16),
            child: AppText('Создайте проект, затем добавьте его тарифы.')),
        for (final project in projects)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppText(project.name,
                    style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  title: const AppText('Учитывать оплату'),
                  subtitle: AppText(project.trackPay
                      ? 'Часы и начисления по тарифу'
                      : 'Только часы, без денежных сумм'),
                  value: project.trackPay,
                  onChanged: (enabled) => _perform(() =>
                      widget.repository.setProjectPayTracking(project.id, enabled)),
                ),
                if (project.trackPay) ...[
                  for (final rate in rates[project.id] ?? <WorkRate>[])
                    ListTile(
                      title: AppText(rate.name),
                      trailing: AppText('${_money(rate.centsPerHour, rate.currency)}${appText(context, '/ч')}'),
                    ),
                  TextButton.icon(
                      onPressed: () => _createRate(project),
                      icon: const Icon(Icons.add),
                      label: const AppText('Добавить тариф')),
                ],
                TextButton.icon(
                  onPressed: () => _showProjectHistory(project),
                  icon: const Icon(Icons.history),
                  label: const AppText('История проекта'),
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
      final csv = buildReportCsv(completed,
          languageCode: Localizations.localeOf(context).languageCode);
      final name = 'work-hours-${range.start.year}-${_two(range.start.month)}-'
          '${_two(range.start.day)}.csv';
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
        mimeType: 'text/csv',
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('Отчёт CSV сохранён')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _shareReport(DateTimeRange range, List<WorkShift> completed) async {
    try {
      final languageCode = Localizations.localeOf(context).languageCode;
      final csv = buildReportCsv(completed, languageCode: languageCode);
      final details = reportShareDetails(range.start, range.end, languageCode);
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/csv')],
        fileNameOverrides: [details.fileName],
        subject: details.subject,
        text: details.body,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ));
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
      AppText('Отчёты', style: Theme.of(context).textTheme.headlineSmall),
      DropdownButton<String>(
        value: period,
        items: const [
          DropdownMenuItem(value: 'day', child: AppText('День')),
          DropdownMenuItem(value: 'week', child: AppText('Неделя')),
          DropdownMenuItem(value: 'month', child: AppText('Месяц')),
          DropdownMenuItem(value: 'custom', child: AppText('Выбранный период')),
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
        Expanded(child: AppText('${_date(range.start)} — '
            '${_date(range.end.subtract(const Duration(days: 1)))}')),
        if (period != 'custom')
          IconButton(
              onPressed: () => _movePeriod(1),
              icon: const Icon(Icons.chevron_right)),
      ]),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppText('${appText(context, 'Учтённое время')}: ${_duration(context, minutes)}'),
          for (final total in totals.entries)
            AppText('${appText(context, 'Сумма')}: ${_money(total.value, total.key)}'),
          if (completed.isEmpty) const AppText('Завершённых смен нет.'),
        ]),
      )),
      OutlinedButton.icon(
        onPressed: completed.isEmpty ? null : () => _exportReport(range, completed),
        icon: const Icon(Icons.download_outlined),
        label: const AppText('Сохранить отчёт CSV'),
      ),
      OutlinedButton.icon(
        onPressed: completed.isEmpty ? null : () => _shareReport(range, completed),
        icon: const Icon(Icons.share_outlined),
        label: const AppText('Поделиться CSV'),
      ),
      for (final shift in completed) _shiftCard(shift),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Сегодня', 'План', 'Проекты', 'Отчёты'];
    return Scaffold(
      appBar: AppBar(
        title: AppText(titles[tab]),
        actions: [
          WorkHoursMenuButton(
            onExport: _exportBackup,
            onImport: _importBackup,
            onAbout: _showAbout,
            onLanguage: _chooseLanguage,
            onReminders: _chooseReminders,
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
        destinations: [
          NavigationDestination(icon: const Icon(Icons.today_outlined),
              label: appText(context, 'Сегодня')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined),
              label: appText(context, 'План')),
          NavigationDestination(icon: const Icon(Icons.work_outline),
              label: appText(context, 'Проекты')),
          NavigationDestination(icon: const Icon(Icons.bar_chart_outlined),
              label: appText(context, 'Отчёты')),
        ],
      ),
    );
  }
}

class LanguagePickerDialog extends StatelessWidget {
  const LanguagePickerDialog({super.key, required this.selectedLanguageCode});

  final String? selectedLanguageCode;

  @override
  Widget build(BuildContext context) => SimpleDialog(
        title: const AppText('Язык приложения'),
        children: [
          for (final entry in const [
            ('system', 'Системный'),
            ('en', 'English'),
            ('ru', 'Русский'),
            ('uk', 'Українська'),
            ('pl', 'Polski'),
            ('es', 'Español'),
            ('tr', 'Türkçe'),
            ('uz', 'Oʻzbekcha'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.$1),
              child: Row(children: [
                Expanded(child: AppText(entry.$2)),
                if (entry.$1 == (selectedLanguageCode ?? 'system'))
                  const Icon(Icons.check),
              ]),
            ),
        ],
      );
}

class WorkHoursMenuButton extends StatelessWidget {
  const WorkHoursMenuButton({super.key, required this.onExport,
      required this.onImport, required this.onAbout, required this.onLanguage,
      this.onReminders});

  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onAbout;
  final VoidCallback onLanguage;
  final VoidCallback? onReminders;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: appText(context, 'Меню'),
        onSelected: (value) {
          switch (value) {
            case 'export': onExport();
            case 'import': onImport();
            case 'about': onAbout();
            case 'language': onLanguage();
            case 'reminders': onReminders?.call();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'export', child: AppText('Сохранить копию')),
          PopupMenuItem(value: 'import', child: AppText('Восстановить копию')),
          PopupMenuItem(value: 'about', child: AppText('О приложении')),
          PopupMenuItem(value: 'language', child: AppText('Язык приложения')),
          PopupMenuItem(value: 'reminders', child: AppText('Напоминания')),
        ],
      );
}

class ReminderSettingsDialog extends StatefulWidget {
  const ReminderSettingsDialog({super.key, required this.settings});
  final ReminderSettings settings;

  @override
  State<ReminderSettingsDialog> createState() => _ReminderSettingsDialogState();
}

class _ReminderSettingsDialogState extends State<ReminderSettingsDialog> {
  late ReminderSettings value = widget.settings;

  String _timingLabel(ReminderTiming timing) => switch (timing) {
    ReminderTiming.atTime => 'В момент события',
    ReminderTiming.hourBefore => 'За 1 час',
    ReminderTiming.dayBefore => 'За 1 день',
    ReminderTiming.previousEvening => 'Вечером накануне',
  };

  Widget _timingPicker(String label, ReminderTiming selected,
      ValueChanged<ReminderTiming> changed) => DropdownButtonFormField<ReminderTiming>(
        key: ValueKey(label),
        initialValue: selected,
        decoration: InputDecoration(labelText: appText(context, label)),
        items: [for (final timing in ReminderTiming.values)
          DropdownMenuItem(value: timing, child: AppText(_timingLabel(timing)))],
        onChanged: (timing) {
          if (timing != null) changed(timing);
        },
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const AppText('Напоминания'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const AppText('О начале смены'),
              value: value.startEnabled,
              onChanged: (enabled) => setState(() =>
                  value = value.copyWith(startEnabled: enabled)),
            ),
            if (value.startEnabled) _timingPicker('Когда напомнить о начале',
                value.startTiming, (timing) => setState(() =>
                    value = value.copyWith(startTiming: timing))),
            SwitchListTile(
              title: const AppText('Об окончании смены'),
              value: value.endEnabled,
              onChanged: (enabled) => setState(() =>
                  value = value.copyWith(endEnabled: enabled)),
            ),
            if (value.endEnabled) _timingPicker('Когда напомнить об окончании',
                value.endTiming, (timing) => setState(() =>
                    value = value.copyWith(endTiming: timing))),
            if ((value.startEnabled &&
                    value.startTiming == ReminderTiming.previousEvening) ||
                (value.endEnabled &&
                    value.endTiming == ReminderTiming.previousEvening))
              ListTile(
                title: const AppText('Время вечером накануне'),
                subtitle: AppText('${_two(value.eveningHour)}:00'),
                onTap: () async {
                  final chosen = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: value.eveningHour, minute: 0),
                  );
                  if (chosen != null && mounted) {
                    setState(() =>
                        value = value.copyWith(eveningHour: chosen.hour));
                  }
                },
              ),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const AppText('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, value),
              child: const AppText('Сохранить')),
        ],
      );
}

class WorkHoursAboutDialog extends StatelessWidget {
  const WorkHoursAboutDialog({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const AppText('О приложении'),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WorkHoursApp', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${appText(context, 'Версия')}: $version'),
          const SizedBox(height: 16),
          const AppText('Создатель: Alexander (u-alexander-gb).'),
          const SizedBox(height: 8),
          const AppText('Приложение для личного учёта рабочих смен, часов и тарифов.'),
          const SizedBox(height: 8),
          const SelectableText('github.com/u-alexander-gb/WorkHoursApp'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const AppText('Закрыть')),
        ],
      );
}
