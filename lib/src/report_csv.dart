import 'work_repository.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String _timestamp(DateTime value) =>
    '${_two(value.day)}.${_two(value.month)}.${value.year} '
    '${_two(value.hour)}:${_two(value.minute)}';

String _cell(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp(r'[;"\r\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String buildReportCsv(Iterable<WorkShift> shifts) {
  final completed = shifts
      .where((shift) => shift.status == ShiftStatus.completed &&
          shift.creditedStart != null && shift.creditedEnd != null)
      .toList()
    ..sort((a, b) => a.creditedStart!.compareTo(b.creditedStart!));
  final output = StringBuffer();
  output.writeln('Проект;Тариф;Начало;Конец;Перерыв, мин;Оплачено, мин;'
      'Ставка за час;Валюта;Начислено');
  final totals = <String, (int, int)>{};
  for (final shift in completed) {
    final currency = shift.currency ?? 'EUR';
    final current = totals[currency] ?? (0, 0);
    totals[currency] =
        (current.$1 + shift.paidMinutes, current.$2 + shift.earnedCents);
    final fields = [
      shift.projectName,
      shift.rateName,
      _timestamp(shift.creditedStart!),
      _timestamp(shift.creditedEnd!),
      shift.breakMinutes,
      shift.paidMinutes,
      ((shift.rateCentsPerHour ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ','),
      currency,
      (shift.earnedCents / 100).toStringAsFixed(2).replaceAll('.', ','),
    ];
    output.writeln(fields.map(_cell).join(';'));
  }
  for (final entry in totals.entries) {
    output.writeln([
      'Итого', '', '', '', '', entry.value.$1, '', entry.key,
      (entry.value.$2 / 100).toStringAsFixed(2).replaceAll('.', ','),
    ].map(_cell).join(';'));
  }
  return output.toString();
}
