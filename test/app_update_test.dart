import 'package:flutter_test/flutter_test.dart';

import 'package:work_hours_app/src/app_update.dart';

void main() {
  test('parses a valid update manifest', () {
    final update = parseUpdateManifest({
      'version': '0.2.0-beta.9',
      'releaseUrl': 'https://github.com/example/release',
      'androidUrl': 'https://github.com/example/app.apk',
      'windowsUrl': 'https://github.com/example/app.zip',
    }, '0.2.0-beta.8+9');

    expect(update?.version, '0.2.0-beta.9');
    expect(update?.androidUrl, endsWith('.apk'));
  });

  test('does not report a manifest for the installed version', () {
    final update = parseUpdateManifest({
      'version': '0.2.0-beta.8',
      'releaseUrl': 'https://github.com/example/release',
    }, '0.2.0-beta.8+9');

    expect(update, isNull);
  });

  test('rejects a malformed manifest', () {
    expect(
      () => parseUpdateManifest({'version': '0.2.0-beta.9'}, '0.2.0-beta.8'),
      throwsA(isA<FormatException>()),
    );
  });
}
