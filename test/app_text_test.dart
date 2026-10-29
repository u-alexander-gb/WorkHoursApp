import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/app_text.dart';

void main() {
  test('all supported languages translate core navigation and notifications', () {
    const expected = {
      'en': ('Today', 'Time to check in'),
      'ru': ('Сегодня', 'Пора сделать check-in'),
      'uk': ('Сьогодні', 'Час зробити check-in'),
      'pl': ('Dzisiaj', 'Czas na check-in'),
      'es': ('Hoy', 'Hora de hacer check-in'),
      'tr': ('Bugün', 'Check-in zamanı'),
      'uz': ('Bugun', 'Check-in vaqti'),
    };
    for (final entry in expected.entries) {
      expect(appTextForLanguage(entry.key, 'Сегодня'), entry.value.$1);
      expect(appTextForLanguage(entry.key, 'Пора сделать check-in'),
          entry.value.$2);
    }
  });

  test('dynamic warnings keep values and translate the explanation', () {
    expect(
      appTextForLanguage('en', 'Опоздание: 21 мин относительно плана'),
      'Late arrival: 21 min from plan',
    );
    expect(appTextForLanguage('es', 'My project'), 'My project');
  });
}
