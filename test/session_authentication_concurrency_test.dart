import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:pointycastle/export.dart';
import 'package:liblanis/liblanis.dart';
import 'package:liblanis/src/session/cryptor.dart';
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
  String? loginDenial;
  String? appsRedirect;
  String appsContentType = 'text/plain';
  Completer<void>? homeStarted;
  Completer<void>? releaseHome;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path == '/test-login' && loginDenial != null) {
      return ResponseBody.fromString(
        jsonEncode({'back': false, 'text': loginDenial}),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      );
    }
    if (path == '/startseite.php' && appsRedirect != null) {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          HttpHeaders.locationHeader: [appsRedirect!],
        },
      );
    }
    if (path == '/') {
      homeRequests++;
      if (homeStarted != null && !homeStarted!.isCompleted) {
        homeStarted!.complete();
      }
      if (releaseHome != null) {
        await releaseHome!.future;
      }
    }
    if (path == '/benutzerverwaltung.php') userDataRequests++;
    return ResponseBody.fromString(
      path == '/startseite.php'
          ? '{"entrys":[]}'
          : path == '/benutzerverwaltung.php'
          ? '<ul class="nav navbar-nav navbar-right"><li><a><i class="fa-child"></i></a></li></ul>'
          : '{}',
      failFirst && path == '/' && homeRequests == 1 ? 503 : 200,
      headers: {
        Headers.contentTypeHeader: [
          path == '/startseite.php' ? appsContentType : 'text/plain',
        ],
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
  Uint8List generateKey() =>
      Uint8List.fromList(List.filled(Cryptor.passphraseSize, ++generatedKeys));

  @override
  Future<RSAPublicKey?> getPublicKey() async =>
      RSAPublicKey(BigInt.from(3), BigInt.from(3));

  // The transport stands in for RSA; each handshake still receives its own key.
  @override
  Uint8List encryptKey(RSAPublicKey publicKey) => key;

  @override
  Future<String?> handshake(String encryptedKey) async {
    final serverKey = base64Decode(encryptedKey);
    final salt = Uint8List(8);
    final derived = Cryptor.bytesToKeys(salt, serverKey);
    final aes =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV(
                KeyParameter(derived.sublist(0, 32)),
                derived.sublist(32, 48),
              ),
              null,
            ),
          );
    final challenge = base64Encode([
      ...utf8.encode('Salted__'),
      ...salt,
      ...aes.process(serverKey),
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

  test('a parent without linked learners gets a dedicated error', () async {
    adapter.loginDenial =
        'Für diesen Account sind keine Lernenden hinterlegt, weshalb ein Login '
        'nicht möglich ist.';
    await expectLater(
      authenticate(),
      throwsA(isA<ParentAccountWithoutLearnersException>()),
    );
  });

  test('a school-disabled account gets a dedicated error', () async {
    adapter.loginDenial =
        'Der Login für diesen Account ist durch den schulischen Admin gesperrt '
        'worden.';
    await expectLater(authenticate(), throwsA(isA<AccountDisabledException>()));
  });

  test('a password change redirect gets a dedicated error', () async {
    adapter.appsRedirect = 'benutzerverwaltung.php?a=userChangePassword';
    await expectLater(
      authenticate(),
      throwsA(isA<PasswordChangeRequiredException>()),
    );
  });

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

  test(
    'reauthenticateIfStale skips re-login after authGeneration advances',
    () async {
      cryptor.pauseFirst = false;
      final observed = session.authGeneration;
      await authenticate();
      expect(session.authGeneration, observed + 1);
      expect(cryptor.handshakes, 1);

      await session.reauthenticateIfStale(observed);
      expect(cryptor.handshakes, 1);
      expect(adapter.homeRequests, 1);
    },
  );

  test(
    'getFastTravelMenu maps unexpected 302 redirects to UnauthorizedException',
    () async {
      adapter.appsRedirect = 'index.php';
      await expectLater(
        session.getFastTravelMenu(),
        throwsA(isA<UnauthorizedException>()),
      );
    },
  );

  test(
    'reauthenticateIfStale joins an in-flight withLoginUrl login without extra handshakes',
    () async {
      final observed = session.authGeneration;
      final fullLogin = authenticate(withoutData: false);
      await cryptor.firstHandshake.future;

      final retry1 = session.reauthenticateIfStale(observed);
      final retry2 = session.reauthenticateIfStale(observed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cryptor.releaseFirst.complete();

      await Future.wait([fullLogin, retry1, retry2]);
      expect(cryptor.handshakes, 1);
      expect(adapter.homeRequests, 1);
      expect(session.authGeneration, observed + 1);
    },
  );

  test(
    'reauthenticateIfStale receives normalized LanisDownException when joined login fails with 503',
    () async {
      adapter.failFirst = true;
      adapter.homeStarted = Completer<void>();
      adapter.releaseHome = Completer<void>();
      cryptor.pauseFirst = false;

      final observed = session.authGeneration;
      final starter = expectLater(
        authenticate(),
        throwsA(isA<LanisDownException>()),
      );
      await adapter.homeStarted!.future;
      final joined = expectLater(
        session.reauthenticateIfStale(observed),
        throwsA(isA<LanisDownException>()),
      );
      adapter.releaseHome!.complete();

      await Future.wait([starter, joined]);
      expect(adapter.homeRequests, 1);
    },
  );

  test(
    'getFastTravelMenu accepts pre-decoded Map from application/json responses',
    () async {
      adapter.appsContentType = 'application/json';
      final menu = await session.getFastTravelMenu();
      expect(menu, isEmpty);
    },
  );

  test(
    'parseAccountType throws UnknownException when navbar icon is absent',
    () {
      expect(
        () => session.parseAccountType(Document.html('<html><body></body></html>')),
        throwsA(isA<UnknownException>()),
      );
    },
  );
}
