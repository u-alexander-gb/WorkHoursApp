import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/time_deviation.dart';

void main() {
  final planned = DateTime(2026, 10, 28, 10);

  test('twenty minutes is ordinary, beyond twenty is significant', () {
    final ordinary = startDeviation(
        planned, planned.add(const Duration(minutes: 20)))!;
    final significant = startDeviation(
        planned, planned.add(const Duration(minutes: 20, seconds: 1)))!;

    expect(ordinary.severity, DeviationSeverity.ordinary);
    expect(ordinary.message, contains('Опоздание'));
    expect(significant.severity, DeviationSeverity.significant);
  });

  test('early arrival and departure use distinct descriptions', () {
    expect(startDeviation(planned,
        planned.subtract(const Duration(minutes: 10)))!.message,
        contains('Ранний приход'));
    expect(endDeviation(planned,
        planned.subtract(const Duration(minutes: 10)))!.message,
        contains('Ранний уход'));
    expect(startDeviation(planned, planned), isNull);
    expect(endDeviation(null, planned), isNull);
  });
}
