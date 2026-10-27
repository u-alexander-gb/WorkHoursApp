import 'package:flutter/material.dart';

import 'work_repository.dart';

bool sameCalendarDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

IconData shiftStatusIcon(ShiftStatus status) => switch (status) {
      ShiftStatus.planned => Icons.event_outlined,
      ShiftStatus.armed => Icons.schedule_send_outlined,
      ShiftStatus.active => Icons.play_circle_outline,
      ShiftStatus.completed => Icons.check_circle_outline,
      ShiftStatus.cancelled => Icons.event_busy_outlined,
    };

Color shiftStatusColor(ShiftStatus status, ColorScheme colors) =>
    switch (status) {
      ShiftStatus.planned => colors.primary,
      ShiftStatus.armed => colors.tertiary,
      ShiftStatus.active => Colors.green.shade700,
      ShiftStatus.completed => colors.secondary,
      ShiftStatus.cancelled => colors.outline,
    };

class PlanCalendar extends StatelessWidget {
  const PlanCalendar({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.shifts,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<WorkShift> shifts;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month);
    final gridStart = DateTime(first.year, first.month,
        first.day - first.weekday + DateTime.monday);
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        for (final weekday in weekdays)
          Expanded(child: Center(child: Text(weekday,
              style: Theme.of(context).textTheme.labelSmall))),
      ]),
      const SizedBox(height: 4),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 42,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 0.82,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemBuilder: (context, index) {
          final day = DateTime(gridStart.year, gridStart.month,
              gridStart.day + index);
          final dayShifts = shifts.where((shift) =>
              sameCalendarDay(shift.plannedStart, day)).toList();
          final selected = sameCalendarDay(day, selectedDay);
          final inMonth = day.month == month.month;
          return Semantics(
            label: '${day.day}.${day.month}.${day.year}, '
                '${dayShifts.length} смен',
            button: true,
            selected: selected,
            child: InkWell(
              key: ValueKey('calendar-${day.year}-${day.month}-${day.day}'),
              onTap: () => onSelectDay(day),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? colors.primaryContainer : null,
                  borderRadius: BorderRadius.circular(10),
                  border: selected ? Border.all(color: colors.primary) : null,
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text('${day.day}', style: TextStyle(
                    color: inMonth ? null : colors.outline,
                    fontWeight: selected ? FontWeight.bold : null,
                  )),
                  if (dayShifts.isNotEmpty)
                    Text('${dayShifts.length}',
                        style: Theme.of(context).textTheme.labelSmall),
                  if (dayShifts.isNotEmpty)
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final shift in dayShifts.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: CircleAvatar(
                            radius: 2.5,
                            backgroundColor: shiftStatusColor(shift.status, colors),
                          ),
                        ),
                    ]),
                ]),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
