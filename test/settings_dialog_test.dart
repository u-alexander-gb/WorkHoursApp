import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/app.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      );

  testWidgets('language picker shows seven languages and returns selection',
      (tester) async {
    String? selected;
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          selected = await showDialog<String>(
            context: context,
            builder: (_) => const LanguagePickerDialog(
                selectedLanguageCode: null),
          );
        },
        child: const Text('Open'),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final language in [
      'English', 'Русский', 'Українська', 'Polski',
      'Español', 'Türkçe', 'Oʻzbekcha',
    ]) {
      expect(find.text(language), findsOneWidget);
    }
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(selected, 'ru');
  });

  testWidgets('three-dot menu contains language beside About', (tester) async {
    var openedLanguage = false;
    await tester.pumpWidget(host(WorkHoursMenuButton(
      onExport: () {},
      onImport: () {},
      onAbout: () {},
      onLanguage: () => openedLanguage = true,
    )));
    await tester.tap(find.byType(WorkHoursMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('О приложении'), findsOneWidget);
    expect(find.text('Язык приложения'), findsOneWidget);
    await tester.tap(find.text('Язык приложения'));
    await tester.pumpAndSettle();
    expect(openedLanguage, isTrue);
  });

  testWidgets('About shows installed version without Flutter branding',
      (tester) async {
    await tester.pumpWidget(host(
      const WorkHoursAboutDialog(version: '0.2.0-beta.2+3'),
    ));
    expect(find.text('Версия: 0.2.0-beta.2+3'), findsOneWidget);
    expect(find.textContaining('Создатель: Alexander'), findsOneWidget);
    expect(find.textContaining('Flutter'), findsNothing);
    expect(find.textContaining('Лицензия'), findsNothing);
  });
}
