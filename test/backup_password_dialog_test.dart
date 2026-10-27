import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/app.dart';
void main() {
  testWidgets('cancelling backup password dialog after typing is safe',
      (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          await showDialog<String>(
            context: context,
            builder: (_) => const BackupPasswordDialog(create: true),
          );
          closed = true;
        },
        child: const Text('Open backup'),
      ))),
    ));

    await tester.tap(find.text('Open backup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'test-password-123');
    await tester.enterText(find.byType(TextField).last, 'test-password-123');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.text('Пароль резервной копии'), findsNothing);
  });

  testWidgets('form controllers survive cancel animation', (tester) async {
    var released = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          final reason = TextEditingController();
          await showFormDialogUntilClosed<bool>(
            context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Изменить план'),
              content: TextField(controller: reason),
              actions: [TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              )],
            ),
          );
          reason.dispose();
          released = true;
        },
        child: const Text('Open plan editor'),
      ))),
    ));

    await tester.tap(find.text('Open plan editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test reason');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(released, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.text('Изменить план'), findsNothing);
  });
}
