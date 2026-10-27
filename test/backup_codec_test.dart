import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_app/src/backup_codec.dart';
import 'package:work_hours_app/src/work_repository.dart';

void main() {
  test('encrypted backup can be opened and previewed before restore', () async {
    final repository = await WorkRepository.openInMemory();
    addTearDown(repository.close);
    await repository.addProject('Combo BV');
    final original = await repository.exportBackup();
    final encrypted = await BackupCodec.encrypt(original, 'a-strong-backup-password');

    expect(BackupCodec.isEncrypted(encrypted), isTrue);
    expect(encrypted, isNot(contains('Combo BV')));
    final decrypted = await BackupCodec.decrypt(encrypted, 'a-strong-backup-password');
    final preview = WorkRepository.inspectBackup(decrypted);
    expect(preview.counts['projects'], 1);
    expect(preview.counts['shifts'], 0);
    expect(preview.createdAt.isUtc, isTrue);
    await repository.restoreBackup(decrypted);
    expect((await repository.projects()).single.name, 'Combo BV');
  });

  test('wrong password and changed ciphertext are rejected', () async {
    const password = 'a-strong-backup-password';
    final encrypted = await BackupCodec.encrypt('secret data', password);
    await expectLater(
      BackupCodec.decrypt(encrypted, 'another-strong-password'),
      throwsA(isA<FormatException>()),
    );
    final changed = jsonDecode(encrypted) as Map<String, dynamic>;
    final ciphertext = base64Decode(changed['ciphertext'] as String);
    ciphertext[0] ^= 1;
    changed['ciphertext'] = base64Encode(ciphertext);
    await expectLater(
      BackupCodec.decrypt(jsonEncode(changed), password),
      throwsA(isA<FormatException>()),
    );
  });

  test('legacy JSON remains previewable', () async {
    final repository = await WorkRepository.openInMemory();
    addTearDown(repository.close);
    final legacy = await repository.exportBackup();
    expect(BackupCodec.isEncrypted(legacy), isFalse);
    expect(WorkRepository.inspectBackup(legacy).counts['rates'], 0);
  });
}
