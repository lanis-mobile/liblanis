import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/src/session/cryptor.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Future<RSAPublicKey> publicKey(String pem) async {
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: jsonEncode({'publickey': pem}),
              statusCode: 200,
            ),
          );
        },
      ),
    );
  try {
    return (await (Cryptor()..dio = dio).getPublicKey())!;
  } finally {
    dio.close();
  }
}

void main() {
  final legacy = fixture('cryptor_legacy_vectors');
  final key = base64Decode(legacy['key'] as String);
  final vectors = (legacy['vectors'] as List).cast<Map<String, dynamic>>();

  test(
    'decrypts payloads produced by liblanis 0.2.1 and encrypt 5.0.3',
    () async {
      final cryptor = Cryptor()..key = key;
      for (final vector in vectors) {
        final ciphertext = vector['ciphertext'] as String;
        expect(cryptor.decryptString(ciphertext), vector['plaintext']);
        expect(
          await cryptor.decryptStringInIsolate(ciphertext),
          vector['plaintext'],
        );
        expect(
          cryptor.decryptEncodedTags('<p><encoded>$ciphertext</encoded></p>'),
          '<p>${vector['plaintext']}</p>',
        );
      }
    },
  );

  test(
    'round trips Unicode, empty and block-boundary messages with fresh salts',
    () {
      final cryptor = Cryptor()..key = key;
      for (final message in [
        '',
        ...vectors.map((v) => v['plaintext'] as String),
      ]) {
        final first = cryptor.encryptString(message);
        final second = cryptor.encryptString(message);
        expect(first, isNot(second));
        expect(cryptor.decryptString(first), message);
        expect(cryptor.decryptString(second), message);
      }
      expect(cryptor.generateKey(), hasLength(Cryptor.passphraseSize));
      expect(
        cryptor.generateKey(),
        isNot(orderedEquals(cryptor.generateKey())),
      );
    },
  );

  test('rejects missing envelope, truncated blocks and invalid padding', () {
    expect(Cryptor.decryptWithKey(Uint8List(0), key), isNull);
    expect(Cryptor.decryptWithKey(Uint8List(32), key), isNull);
    expect(
      Cryptor.decryptWithKey(
        Uint8List.fromList([...utf8.encode('Salted__'), ...Uint8List(8)]),
        key,
      ),
      isNull,
    );
    final bytes = base64Decode(vectors.first['ciphertext'] as String);
    expect(
      () => Cryptor.decryptWithKey(bytes.sublist(0, bytes.length - 1), key),
      throwsArgumentError,
    );
    // Flip the last byte of the penultimate CBC block. This changes exactly
    // the final padding byte in the last plaintext block.
    final corrupted = base64Decode(vectors[3]['ciphertext'] as String);
    corrupted[corrupted.length - 17] ^= 1;
    expect(
      () => Cryptor.decryptWithKey(corrupted, key),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('SPKI and PKCS1 public keys encrypt a 46-byte handshake with RSA PKCS1 v1.5', () async {
    final rsa = fixture('cryptor_rsa');
    final spki = await publicKey(rsa['spkiPem'] as String);
    final pkcs1 = await publicKey(
      (rsa['pkcs1Pem'] as String).replaceAll('\n', '\r\n'),
    );
    expect(spki.modulus, pkcs1.modulus);
    expect(spki.exponent, pkcs1.exponent);
    final pem = rsa['privatePem'] as String;
    final der = base64Decode(
      pem.split('\n').where((line) => !line.startsWith('-----')).join(),
    );
    var sequence = ASN1Parser(der).nextObject() as ASN1Sequence;
    if (pem.startsWith('-----BEGIN PRIVATE KEY-----')) {
      sequence =
          ASN1Parser((sequence.elements![2] as ASN1OctetString).octets)
                  .nextObject()
              as ASN1Sequence;
    }
    BigInt integer(int index) =>
        (sequence.elements![index] as ASN1Integer).integer!;
    final privateKey = RSAPrivateKey(
      integer(1),
      integer(3),
      integer(4),
      integer(5),
    );
    final decryptor = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final cryptor = Cryptor()..key = key;
    for (final public in [spki, pkcs1]) {
      final ciphertext = cryptor.encryptKey(public);
      expect(ciphertext, hasLength(256));
      expect(decryptor.process(ciphertext), orderedEquals(key));
    }
  });

  test('rejects non-public-key PEM input', () async {
    await expectLater(
      publicKey('-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----'),
      throwsFormatException,
    );
  });
}
