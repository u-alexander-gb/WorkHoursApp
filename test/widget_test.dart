import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/app.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigation opens projects and reports', (tester) async {
    final repository = await WorkRepository.openInMemory();
    addTearDown(repository.close);

    await tester.pumpWidget(MaterialApp(home: WorkHome(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Сегодня'), findsWidgets);

    await tester.tap(find.text('Проекты').last);
    await tester.pumpAndSettle();
    expect(find.text('Проекты и тарифы'), findsOneWidget);

    await tester.tap(find.text('Отчёты').last);
    await tester.pumpAndSettle();
    expect(find.text('Оплачиваемое время: 0 ч 00 мин'), findsOneWidget);
  });
}
