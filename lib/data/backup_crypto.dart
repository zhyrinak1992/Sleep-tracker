import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Password-based authenticated encryption for portable backup documents.
/// The password is never persisted by the app.
class BackupCrypto {
  BackupCrypto._();

  static const envelopeFormat = 'sleep_tracker_encrypted_backup';
  static const envelopeVersion = 1;
  static const iterations = 310000;
  static const _cipherName = 'AES-256-GCM';
  static const _kdfName = 'PBKDF2-HMAC-SHA256';

  static bool isEncryptedEnvelope(Object? decoded) =>
      decoded is Map && decoded['format'] == envelopeFormat;

  static Future<List<int>> encryptDocument({
    required String plaintext,
    required String password,
  }) async {
    _validatePassword(password);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final box = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final envelope = <String, Object?>{
      'format': envelopeFormat,
      'envelopeVersion': envelopeVersion,
      'cipher': _cipherName,
      'kdf': _kdfName,
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope));
  }

  static Future<String> decryptDocument({
    required List<int> bytes,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const FormatException('Введите пароль резервной копии.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != envelopeFormat ||
        decoded['envelopeVersion'] != envelopeVersion ||
        decoded['cipher'] != _cipherName ||
        decoded['kdf'] != _kdfName ||
        decoded['iterations'] != iterations) {
      throw const FormatException('Формат зашифрованной резервной копии не поддерживается.');
    }
    try {
      final salt = base64Decode(decoded['salt'] as String);
      final nonce = base64Decode(decoded['nonce'] as String);
      final cipherText = base64Decode(decoded['ciphertext'] as String);
      final mac = base64Decode(decoded['mac'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException('Повреждены параметры шифрования резервной копии.');
      }
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      final clearBytes = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return utf8.decode(clearBytes);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Неверный пароль или резервная копия повреждена.');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Не удалось расшифровать резервную копию: неверный пароль или повреждённый файл.');
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 10) {
      throw const FormatException('Пароль должен содержать не менее 10 символов.');
    }
  }
}
