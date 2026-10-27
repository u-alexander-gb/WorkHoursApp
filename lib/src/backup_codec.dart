import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

/// Password-protected, authenticated container for a repository JSON backup.
class BackupCodec {
  static const _format = 'work-hours-encrypted-backup';
  static const _iterations = 150000;
  static final _cipher = AesGcm.with256bits();

  static bool isEncrypted(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат резервной копии');
    }
    return decoded['format'] == _format;
  }

  static Future<String> encrypt(String contents, String password) async {
    if (password.length < 12) {
      throw const FormatException('Пароль должен содержать минимум 12 символов');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _deriveKey(password, salt);
    final box = await _cipher.encrypt(
      utf8.encode(contents),
      secretKey: key,
      aad: utf8.encode('$_format:1'),
    );
    return jsonEncode({
      'format': _format,
      'version': 1,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<String> decrypt(String contents, String password) async {
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _format ||
        decoded['version'] != 1 ||
        decoded['kdf'] != 'pbkdf2-hmac-sha256' ||
        decoded['iterations'] != _iterations ||
        decoded['cipher'] != 'aes-256-gcm') {
      throw const FormatException('Неподдерживаемый формат защищённой копии');
    }
    try {
      final salt = base64Decode(decoded['salt'] as String);
      final nonce = base64Decode(decoded['nonce'] as String);
      final ciphertext = base64Decode(decoded['ciphertext'] as String);
      final mac = base64Decode(decoded['mac'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException('Повреждён заголовок резервной копии');
      }
      final key = await _deriveKey(password, salt);
      final cleartext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode('$_format:1'),
      );
      return utf8.decode(cleartext);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Неверный пароль или файл повреждён');
    } on TypeError {
      throw const FormatException('Повреждён заголовок резервной копии');
    } on FormatException catch (error) {
      if (error.message == 'Повреждён заголовок резервной копии') rethrow;
      throw const FormatException('Повреждён файл резервной копии');
    }
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      FlutterPbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
}
