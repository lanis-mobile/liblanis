import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../exceptions.dart';

/// Lanis RSA handshake + AES decrypt for SPH payloads.
class Cryptor {
  static const int passphraseSize = 46;
  late Uint8List key;
  bool authenticated = false;
  late Dio dio;

  Future<RSAPublicKey?> getPublicKey() async {
    try {
      final response = await dio.post(
        'https://start.schulportal.hessen.de/ajax.php',
        queryParameters: {'f': 'rsaPublicKey'},
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        ),
      );

      if (response.statusCode == 503) {
        throw LanisDownException();
      }

      return _parsePublicKey(jsonDecode(response.toString())['publickey']);
    } on SocketException {
      return null;
    } on DioException {
      return null;
    }
  }

  Future<String?> handshake(String encryptedKey) async {
    try {
      final response = await dio.post(
        'https://start.schulportal.hessen.de/ajax.php',
        queryParameters: {'f': 'rsaHandshake', 's': Random().nextInt(2000)},
        data: {'key': encryptedKey},
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        ),
      );
      return jsonDecode(response.toString())['challenge'];
    } on SocketException {
      return null;
    } on DioException {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List generateKey() => _randomBytes(passphraseSize);

  static RSAPublicKey _parsePublicKey(String pem) {
    final rows = pem.trim().split(RegExp(r'\r\n?|\n'));
    final header = rows.first;
    if (header != '-----BEGIN PUBLIC KEY-----' &&
        header != '-----BEGIN RSA PUBLIC KEY-----') {
      throw const FormatException('Expected an RSA public key PEM');
    }
    final der = base64Decode(
      rows
          .where((row) => !row.startsWith('-----'))
          .map((row) => row.trim())
          .join(),
    );
    var sequence = ASN1Parser(der).nextObject() as ASN1Sequence;
    if (header == '-----BEGIN PUBLIC KEY-----') {
      final algorithm = sequence.elements![0] as ASN1Sequence;
      final oid = algorithm.elements![0] as ASN1ObjectIdentifier;
      if (oid.objectIdentifierAsString != '1.2.840.113549.1.1.1') {
        throw const FormatException('Expected RSA algorithm');
      }
      final bits = sequence.elements![1] as ASN1BitString;
      sequence =
          ASN1Parser(Uint8List.fromList(bits.stringValues!)).nextObject()
              as ASN1Sequence;
    }
    return RSAPublicKey(
      (sequence.elements![0] as ASN1Integer).integer!,
      (sequence.elements![1] as ASN1Integer).integer!,
    );
  }

  Uint8List encryptKey(RSAPublicKey publicKey) {
    final rsa = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return rsa.process(key);
  }

  bool checkForEqualEncryption(Uint8List challenge) {
    final decryptedChallenge = decrypt(challenge);
    return base64.encode(decryptedChallenge!) == base64.encode(key);
  }

  static Uint8List bytesToKeys(Uint8List salt, Uint8List key) {
    Uint8List concatenatedHashes = Uint8List(0);
    Uint8List currentHash = Uint8List(0);
    var enoughBytesForKey = false;
    Uint8List preHash = Uint8List(0);

    while (!enoughBytesForKey) {
      if (currentHash.isNotEmpty) {
        preHash = Uint8List.fromList(currentHash + key + salt);
      } else {
        preHash = Uint8List.fromList(key + salt);
      }

      currentHash = Uint8List.fromList(md5.convert(preHash).bytes);
      concatenatedHashes = Uint8List.fromList(concatenatedHashes + currentHash);
      if (concatenatedHashes.length >= 48) enoughBytesForKey = true;
    }

    return concatenatedHashes;
  }

  String encryptString(String decryptedData) {
    final salt = _randomBytes(8);
    final encryptedData = _aes(
      true,
      Uint8List.fromList(utf8.encode(decryptedData)),
      salt,
      key,
    );
    final finalEncrypted = utf8.encode('Salted__') + salt + encryptedData;
    return base64.encode(finalEncrypted);
  }

  static List<int>? decryptWithKey(
    Uint8List encryptedDataWithSalt,
    Uint8List key,
  ) {
    if (encryptedDataWithSalt.length <= 16 ||
        String.fromCharCodes(encryptedDataWithSalt.take(8)) != 'Salted__') {
      return null;
    }
    return _aes(
      false,
      encryptedDataWithSalt.sublist(16),
      encryptedDataWithSalt.sublist(8, 16),
      key,
    );
  }

  static Uint8List _aes(
    bool encrypting,
    Uint8List input,
    Uint8List salt,
    Uint8List key,
  ) {
    final derived = bytesToKeys(salt, key);
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            encrypting,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV(
                KeyParameter(derived.sublist(0, 32)),
                derived.sublist(32, 48),
              ),
              null,
            ),
          );
    // PointyCastle's process() assumes at least one input block. PKCS7
    // encryption of an empty message still produces a full padding block.
    if (encrypting && input.isEmpty) {
      final output = Uint8List(cipher.blockSize);
      cipher.doFinal(input, 0, output, 0);
      return output;
    }
    return cipher.process(input);
  }

  List<int>? decrypt(Uint8List encryptedDataWithSalt) {
    return decryptWithKey(encryptedDataWithSalt, key);
  }

  static String? decryptWithKeyString(String encryptedData, Uint8List key) {
    final decryptedBytes = decryptWithKey(base64.decode(encryptedData), key);
    if (decryptedBytes != null) {
      return utf8.decode(decryptedBytes);
    }
    return null;
  }

  String? decryptString(String encryptedData) {
    return decryptWithKeyString(encryptedData, key);
  }

  String decryptEncodedTags(String htmlString) {
    final exp = RegExp(r'<encoded>(.*?)</encoded>');
    return htmlString.replaceAllMapped(exp, (match) {
      final encodedContent = match.group(1);
      final decryptedContent = decryptString(encodedContent!);
      return decryptedContent ?? '';
    });
  }

  /// Decrypt [encryptedData] on a background isolate using this instance's key.
  Future<String?> decryptStringInIsolate(String encryptedData) {
    final keyBytes = key;
    return Isolate.run(() {
      final k = Uint8List.fromList(keyBytes);
      return decryptWithKeyString(encryptedData, k);
    });
  }

  Future<void> initialize(Dio dioClient) async {
    dio = dioClient;
    key = generateKey();

    final publicKey = await getPublicKey();
    if (publicKey == null) {
      throw NetworkException();
    }

    final encryptedKey = encryptKey(publicKey);
    final challenge = await handshake(base64.encode(encryptedKey));
    if (challenge == null) {
      throw NetworkException();
    }

    final equal = checkForEqualEncryption(base64.decode(challenge));
    if (equal) {
      authenticated = true;
      return;
    }

    throw EncryptionCheckFailedException();
  }
}
