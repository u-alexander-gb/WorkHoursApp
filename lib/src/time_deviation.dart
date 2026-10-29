import 'package:flutter/material.dart';
import 'app_text.dart';

enum DeviationSeverity { ordinary, significant }

class TimeDeviation {
  const TimeDeviation(this.message, this.severity);

  final String message;
  final DeviationSeverity severity;
}

TimeDeviation? startDeviation(DateTime planned, DateTime actual) =>
    _deviation(planned, actual, early: 'Ранний приход', late: 'Опоздание');

TimeDeviation? endDeviation(DateTime? planned, DateTime actual) =>
    planned == null
        ? null
        : _deviation(planned, actual,
            early: 'Ранний уход', late: 'Поздний уход');

TimeDeviation? _deviation(DateTime planned, DateTime actual,
    {required String early, required String late}) {
  final microseconds = actual.difference(planned).inMicroseconds;
  if (microseconds == 0) return null;
  const minuteMicros = 60 * 1000000;
  final minutes = (microseconds.abs() + minuteMicros - 1) ~/ minuteMicros;
  return TimeDeviation(
    '${microseconds < 0 ? early : late}: $minutes мин относительно плана',
    microseconds.abs() > 20 * minuteMicros
        ? DeviationSeverity.significant
        : DeviationSeverity.ordinary,
  );
}

class DeviationNotice extends StatelessWidget {
  const DeviationNotice({super.key, required this.deviation});

  final TimeDeviation deviation;

  @override
  Widget build(BuildContext context) {
    final significant = deviation.severity == DeviationSeverity.significant;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(significant ? Icons.warning_amber_outlined : Icons.info_outline,
            color: significant ? colors.error : colors.tertiary),
        const SizedBox(width: 8),
        Expanded(child: AppText(deviation.message)),
      ]),
    );
  }
}
