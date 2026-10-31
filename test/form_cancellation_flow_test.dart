import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_hours_app/app.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  late WorkRepository repository;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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
    final projects = await tester.runAsync(repository.projects);
    expect(projects!.length, 1);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить смену'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final shifts = await tester.runAsync(repository.shifts);
    expect(shifts, isEmpty);
  });

  testWidgets('cancel plan edit and deletion reason after typing',
      (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10);
    await tester.runAsync(() async {
      final project = (await repository.projects()).single;
      await repository.planShift(
        projectId: project.id,
        start: start,
        end: start.add(const Duration(hours: 8)),
      );
    });
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

    await tester.ensureVisible(find.text('Удалить').last);
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Temporary cancellation');
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final shifts = await tester.runAsync(repository.shifts);
    expect(shifts!.single.status, ShiftStatus.planned);
  });
}
