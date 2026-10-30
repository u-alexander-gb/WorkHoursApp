import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/report_csv.dart';

void main() {
  test('CSV share metadata names the selected inclusive period', () {
    final details = reportShareDetails(
      DateTime(2026, 10, 30),
      DateTime(2026, 11, 2),
      'ru',
    );

    expect(details.fileName, 'work-hours-2026-10-30-to-2026-11-01.csv');
    expect(details.subject, 'Отчёт о рабочих часах: 30.10.2026 — 01.11.2026');
    expect(details.body,
        'Отчёт о рабочих часах за выбранный период во вложении.');
  });

  test('CSV share metadata follows the chosen app language', () {
    final details = reportShareDetails(
      DateTime(2026, 10, 30),
      DateTime(2026, 10, 31),
      'en',
    );

    expect(details.subject, 'Work hours report: 30.10.2026 — 30.10.2026');
    expect(details.body,
        'The work hours report for the selected period is attached.');
  });
}
