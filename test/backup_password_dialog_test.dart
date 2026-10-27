import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/app.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  testWidgets('cancelling backup password dialog after typing is safe',
      (tester) async {
    debugPrint('backup dialog test: opening repository');
    final repository = await WorkRepository.openInMemory();
    debugPrint('backup dialog test: repository opened');
    addTearDown(repository.close);
    await tester.pumpWidget(MaterialApp(home: WorkHome(repository: repository)));
    debugPrint('backup dialog test: widget pumped');
    await tester.pumpAndSettle();
    debugPrint('backup dialog test: initial view settled');

    await tester.tap(find.byTooltip('Меню'));
    await tester.pumpAndSettle();
    debugPrint('backup dialog test: menu opened');
    await tester.tap(find.text('Сохранить копию'));
    await tester.pumpAndSettle();
    debugPrint('backup dialog test: dialog opened');

    await tester.enterText(find.byType(TextField).first, 'test-password-123');
    await tester.enterText(find.byType(TextField).last, 'test-password-123');
    debugPrint('backup dialog test: passwords entered');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    debugPrint('backup dialog test: dialog cancelled');

    expect(tester.takeException(), isNull);
    expect(find.text('Пароль резервной копии'), findsNothing);

    await tester.tap(find.byTooltip('Меню'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить копию'));
    await tester.pumpAndSettle();
    expect(find.text('Пароль резервной копии'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling planned shift edit after typing is safe',
      (tester) async {
    final repository = await WorkRepository.openInMemory();
    addTearDown(repository.close);
    await repository.addProject('Test project');
    final project = (await repository.projects()).single;
    final start = DateTime.now().add(const Duration(hours: 1));
    final shiftId = await repository.planShift(
      projectId: project.id,
      start: start,
      end: start.add(const Duration(hours: 8)),
    );
    await tester.pumpWidget(MaterialApp(home: WorkHome(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('План').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Изменить план'), 200);
    await tester.tap(find.text('Изменить план'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test reason');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Исправить смену'), findsNothing);
    expect((await repository.shifts()).singleWhere((s) => s.id == shiftId).plannedStart,
        start);
  });
}
