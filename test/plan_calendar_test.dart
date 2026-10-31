import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/plan_calendar.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  testWidgets('calendar shows shift count and selects a day', (tester) async {
    var selected = DateTime(2026, 10, 1);
    final shift = WorkShift(
      id: 'shift-1',
      rowId: 1,
      projectId: 'project-1',
      projectName: 'Combo BV',
      status: ShiftStatus.planned,
      plannedStart: DateTime(2026, 10, 15, 10),
      plannedEnd: DateTime(2026, 10, 15, 18),
      rateId: null,
      rateName: null,
      rateCentsPerHour: null,
      currency: null,
      preCheckInAt: null,
      confirmedAt: null,
      creditedStart: null,
      checkedOutAt: null,
      creditedEnd: null,
      breakMinutes: 0,
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: StatefulBuilder(
      builder: (context, update) => PlanCalendar(
        month: DateTime(2026, 10),
        selectedDay: selected,
        shifts: [shift],
        onSelectDay: (day) => update(() => selected = day),
      ),
    )))));

    final day = find.byKey(const ValueKey('calendar-2026-10-15'));
    expect(find.descendant(of: day, matching: find.text('1')), findsOneWidget);
    await tester.tap(day);
    await tester.pump();
    expect(selected, DateTime(2026, 10, 15));
    expect(tester.takeException(), isNull);
  });
}
