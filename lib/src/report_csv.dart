import 'work_repository.dart';
import 'app_text.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String _timestamp(DateTime value) =>
    '${_two(value.day)}.${_two(value.month)}.${value.year} '
    '${_two(value.hour)}:${_two(value.minute)}';

String _date(DateTime value) =>
    '${_two(value.day)}.${_two(value.month)}.${value.year}';

({String fileName, String subject, String body}) reportShareDetails(
    DateTime start, DateTime endExclusive, String languageCode) {
  final end = endExclusive.subtract(const Duration(days: 1));
  final period = '${_date(start)} — ${_date(end)}';
  final fileName = 'work-hours-${start.year}-${_two(start.month)}-'
      '${_two(start.day)}-to-${end.year}-${_two(end.month)}-${_two(end.day)}.csv';
  return (
    fileName: fileName,
    subject: '${appTextForLanguage(languageCode, 'Отчёт о рабочих часах')}: $period',
    body: appTextForLanguage(languageCode,
        'Отчёт о рабочих часах за выбранный период во вложении.'),
  );
}

String _cell(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp(r'[;"\r\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String buildReportCsv(Iterable<WorkShift> shifts, {String languageCode = 'ru'}) {
  final completed = shifts
      .where((shift) => shift.status == ShiftStatus.completed &&
          shift.creditedStart != null && shift.creditedEnd != null)
      .toList()
    ..sort((a, b) => a.creditedStart!.compareTo(b.creditedStart!));
  final output = StringBuffer();
  output.writeln([
    'Проект', 'Тариф', 'Начало', 'Конец', 'Перерыв, мин', 'Учтено, мин',
    'Ставка за час', 'Валюта', 'Начислено',
  ].map((value) => _cell(appTextForLanguage(languageCode, value))).join(';'));
  final totals = <String, (int, int)>{};
  var totalMinutes = 0;
  for (final shift in completed) {
    totalMinutes += shift.paidMinutes;
    final currency = shift.currency;
    if (shift.rateCentsPerHour != null && currency != null) {
      final current = totals[currency] ?? (0, 0);
      totals[currency] =
          (current.$1 + shift.paidMinutes, current.$2 + shift.earnedCents);
    }
    final fields = [
      shift.projectName,
      shift.rateName,
      _timestamp(shift.creditedStart!),
      _timestamp(shift.creditedEnd!),
      shift.breakMinutes,
      shift.paidMinutes,
      shift.rateCentsPerHour == null
          ? ''
          : (shift.rateCentsPerHour! / 100).toStringAsFixed(2).replaceAll('.', ','),
      currency,
      shift.rateCentsPerHour == null
          ? ''
          : (shift.earnedCents / 100).toStringAsFixed(2).replaceAll('.', ','),
    ];
    output.writeln(fields.map(_cell).join(';'));
  }
  output.writeln([appTextForLanguage(languageCode, 'Всего часов'), '', '', '', '', totalMinutes, '', '', '']
      .map(_cell).join(';'));
  for (final entry in totals.entries) {
    output.writeln([
      appTextForLanguage(languageCode, 'Итого'), '', '', '', '', entry.value.$1, '', entry.key,
      (entry.value.$2 / 100).toStringAsFixed(2).replaceAll('.', ','),
    ].map(_cell).join(';'));
  }
  return output.toString();
}
