import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/app.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  late WorkRepository repository;

  setUp(() async {
    repository = await WorkRepository.openInMemory();
    await repository.addProject('Combo BV');
  });
  tearDown(() async => repository.close());

  Future<void> openHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: WorkHome(
        repository: repository,
        languageCode: 'ru',
        onLanguageChanged: (_) {},
      ),
    ));
    // SQLite completes on its own event loop outside the widget test clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Сегодня,'), findsOneWidget);
  }

  testWidgets('cancel project and planned shift forms after editing',
      (tester) async {
    await openHome(tester);
    await tester.tap(find.byIcon(Icons.work_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Temporary project');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((await repository.projects()).length, 1);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить смену'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(await repository.shifts(), isEmpty);
  });

  testWidgets('cancel plan edit and cancellation reason after typing',
      (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10);
    final project = (await repository.projects()).single;
    await repository.planShift(
      projectId: project.id,
      start: start,
      end: start.add(const Duration(hours: 8)),
    );
    await openHome(tester);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Изменить план'));
    await tester.tap(find.text('Изменить план'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Temporary reason');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Отменить').last);
    await tester.tap(find.text('Отменить').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Temporary cancellation');
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((await repository.shifts()).single.status, ShiftStatus.planned);
  });
}
