import 'package:flutter_test/flutter_test.dart';

import 'package:work_hours_app/src/app_version.dart';

void main() {
  test('beta releases are ordered by beta number', () {
    expect(isNewerAppVersion('v0.2.0-beta.7', '0.2.0-beta.6+7'), isTrue);
  });

  test('build number does not change release ordering', () {
    expect(compareAppVersions('0.2.0-beta.7+8', '0.2.0-beta.7+9'), 0);
  });

  test('stable release is newer than beta', () {
    expect(isNewerAppVersion('0.2.0', '0.2.0-beta.7+8'), isTrue);
  });

  test('beta release is not newer than stable release', () {
    expect(isNewerAppVersion('0.2.0-beta.8', '0.2.0'), isFalse);
  });

  test('malformed release tags are ignored', () {
    expect(compareAppVersions('not-a-version', '0.2.0-beta.7'), 0);
  });
}
