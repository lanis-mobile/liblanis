import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:liblanis/liblanis.dart';
import 'package:liblanis/src/session/cryptor.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;

  @override
  Future<bool> get connected async => true;
}

class _Adapter implements HttpClientAdapter {
  int homeRequests = 0;
  int userDataRequests = 0;
  bool failFirst = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path == '/') homeRequests++;
    if (path == '/benutzerverwaltung.php') userDataRequests++;
    return ResponseBody.fromString(
      path == '/startseite.php'
          ? '{"entrys":[]}'
          : path == '/benutzerverwaltung.php'
          ? '<ul class="nav navbar-nav navbar-right"><li><a><i class="fa-child"></i></a></li></ul>'
          : '{}',
      failFirst && path == '/' && homeRequests == 1 ? 503 : 200,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Keep production AES challenge validation while controlling network timing.
class _HandshakeCryptor extends Cryptor {
  final firstHandshake = Completer<void>();
  final releaseFirst = Completer<void>();
  int generatedKeys = 0;
  int handshakes = 0;
  bool pauseFirst = true;

  @override
  encrypt.Key generateKey() => encrypt.Key(
    Uint8List.fromList(List.filled(Cryptor.passphraseSize, ++generatedKeys)),
  );

  @override
  Future<RSAPublicKey?> getPublicKey() async =>
      RSAPublicKey(BigInt.from(3), BigInt.from(3));

  // The transport stands in for RSA; each handshake still receives its own key.
  @override
  Uint8List encryptKey(RSAPublicKey publicKey) => key.bytes;

  @override
  Future<String?> handshake(String encryptedKey) async {
    final serverKey = encrypt.Key(base64Decode(encryptedKey));
    final salt = Uint8List(8);
    final derived = Cryptor.bytesToKeys(salt, serverKey);
    final aes = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(derived.sublist(0, 32)),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
    final challenge = base64Encode([
      ...utf8.encode('Salted__'),
      ...salt,
      ...aes
          .encryptBytes(
            serverKey.bytes,
            iv: encrypt.IV(derived.sublist(32, 48)),
          )
          .bytes,
    ]);
    if (++handshakes == 1) {
      firstHandshake.complete();
      if (pauseFirst) await releaseFirst.future;
    }
    return challenge;
  }
}

void main() {
  late _Adapter adapter;
  late _HandshakeCryptor cryptor;
  late LanisSession session;

  setUp(() async {
    adapter = _Adapter();
    cryptor = _HandshakeCryptor();
    session = LanisSession(
      account: const ClearTextAccount(
        localId: 1,
        schoolID: 1,
        username: 'test',
        password: 'test',
        schoolName: 'Test',
      ),
      config: LanisConfig(httpAdapter: adapter),
      connectionChecker: _OnlineChecker(),
    );
    await session.prepareDio();
    session.cryptor = cryptor;
  });

  tearDown(() async {
    if (!cryptor.releaseFirst.isCompleted) cryptor.releaseFirst.complete();
    await session.dispose();
    session.connectionChecker.dispose();
  });

  Future<void> authenticate({bool withoutData = true}) => session.authenticate(
    withoutData: withoutData,
    withLoginUrl: 'https://start.schulportal.hessen.de/test-login',
  );

  test(
    'overlapping authentication cannot replace a pending handshake key',
    () async {
      final first = authenticate();
      await cryptor.firstHandshake.future;
      final second = authenticate();
      final verified = expectLater(Future.wait([first, second]), completes);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final keysWhilePending = cryptor.generatedKeys;
      cryptor.releaseFirst.complete();
      await verified;
      expect(
        keysWhilePending,
        1,
        reason: "A second handshake must wait for the first",
      );
      expect(cryptor.handshakes, 2);
      expect(session.cryptor.authenticated, isTrue);
    },
  );

  test('queued authentication retains its own data-loading options', () async {
    final first = authenticate();
    await cryptor.firstHandshake.future;
    final second = authenticate(withoutData: false);
    final verified = expectLater(Future.wait([first, second]), completes);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final keysWhilePending = cryptor.generatedKeys;
    cryptor.releaseFirst.complete();
    await verified;
    expect(
      keysWhilePending,
      1,
      reason: "A second handshake must wait for the first",
    );
    expect(adapter.userDataRequests, 1);
    expect(session.accountType, AccountType.student);
  });

  test('a failed authentication does not block the next caller', () async {
    adapter.failFirst = true;
    cryptor.pauseFirst = false;
    final failed = expectLater(
      authenticate(),
      throwsA(isA<LanisDownException>()),
    );
    final next = expectLater(authenticate(), completes);
    await Future.wait([failed, next]);
    expect(adapter.homeRequests, 2);
    expect(cryptor.handshakes, 1);
  });

  test('later authentication still performs a fresh handshake', () async {
    cryptor.pauseFirst = false;
    await authenticate();
    await authenticate();
    expect(cryptor.handshakes, 2);
    expect(adapter.homeRequests, 2);
  });
}
