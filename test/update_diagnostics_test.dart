import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:work_hours_app/app.dart';

void main() {
  testWidgets('about dialog exposes update diagnostics export', (tester) async {
    var exported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkHoursAboutDialog(
          version: '0.2.0-beta.10+11',
          onExportUpdateDiagnostics: () => exported = true,
        ),
      ),
    );

    await tester.tap(find.text('Export update diagnostics'));
    expect(exported, isTrue);
  });
}
