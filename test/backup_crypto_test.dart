import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/backup_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupCrypto', () {
    test('encrypts content and restores it with the same password', () async {
      const source = '{"format":"sleep_tracker_backup","data":{"sessions":[]}}';
      final encrypted = await BackupCrypto.encryptDocument(
        plaintext: source,
        password: 'correct horse battery',
      );

      expect(utf8.decode(encrypted), isNot(contains('sleep_tracker_backup')));
      expect(BackupCrypto.isEncryptedEnvelope(jsonDecode(utf8.decode(encrypted))), isTrue);

      final restored = await BackupCrypto.decryptDocument(
        bytes: encrypted,
        password: 'correct horse battery',
      );
      expect(restored, source);
    });

    test('rejects an incorrect password', () async {
      final encrypted = await BackupCrypto.encryptDocument(
        plaintext: '{"private":"sleep data"}',
        password: 'correct horse battery',
      );
      await expectLater(
        BackupCrypto.decryptDocument(
          bytes: encrypted,
          password: 'incorrect password',
        ),
        throwsA(isA<FormatException>()),
      );
    });


    test('rejects modified ciphertext before returning plaintext', () async {
      final encrypted = await BackupCrypto.encryptDocument(
        plaintext: '{"private":"sleep data"}',
        password: 'correct horse battery',
      );
      final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final cipherText = base64Decode(envelope['ciphertext'] as String);
      cipherText[0] ^= 0x01;
      envelope['ciphertext'] = base64Encode(cipherText);
      final tampered = utf8.encode(jsonEncode(envelope));

      await expectLater(
        BackupCrypto.decryptDocument(
          bytes: tampered,
          password: 'correct horse battery',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('uses a fresh salt and nonce for each archive', () async {
      final first = jsonDecode(utf8.decode(await BackupCrypto.encryptDocument(
        plaintext: '{}',
        password: 'correct horse battery',
      ))) as Map<String, dynamic>;
      final second = jsonDecode(utf8.decode(await BackupCrypto.encryptDocument(
        plaintext: '{}',
        password: 'correct horse battery',
      ))) as Map<String, dynamic>;

      expect(first['salt'], isNot(second['salt']));
      expect(first['nonce'], isNot(second['nonce']));
    });

    test('rejects passwords shorter than ten characters', () async {
      await expectLater(
        BackupCrypto.encryptDocument(
          plaintext: '{}',
          password: 'short',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
