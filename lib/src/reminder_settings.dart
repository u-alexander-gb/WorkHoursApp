enum ReminderTiming { atTime, hourBefore, dayBefore, previousEvening }

class ReminderSettings {
  const ReminderSettings({
    this.startEnabled = true,
    this.endEnabled = true,
    this.startTiming = ReminderTiming.atTime,
    this.endTiming = ReminderTiming.atTime,
    this.eveningHour = 19,
  });

  final bool startEnabled;
  final bool endEnabled;
  final ReminderTiming startTiming;
  final ReminderTiming endTiming;
  final int eveningHour;

  DateTime when(DateTime due, ReminderTiming timing) => switch (timing) {
    ReminderTiming.atTime => due,
    ReminderTiming.hourBefore => due.subtract(const Duration(hours: 1)),
    ReminderTiming.dayBefore => due.subtract(const Duration(days: 1)),
    ReminderTiming.previousEvening =>
      DateTime(due.year, due.month, due.day - 1, eveningHour),
  };

  ReminderSettings copyWith({bool? startEnabled, bool? endEnabled,
      ReminderTiming? startTiming, ReminderTiming? endTiming, int? eveningHour}) =>
      ReminderSettings(
        startEnabled: startEnabled ?? this.startEnabled,
        endEnabled: endEnabled ?? this.endEnabled,
        startTiming: startTiming ?? this.startTiming,
        endTiming: endTiming ?? this.endTiming,
        eveningHour: eveningHour ?? this.eveningHour,
      );
}
