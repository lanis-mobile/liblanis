import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/liblanis.dart';
import 'package:liblanis/src/session/cryptor.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;

  @override
  Future<bool> get connected async => true;
}

class _CachedOnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async {
    status = ConnectionStatus.connected;
    return true;
  }
}

class _Adapter implements HttpClientAdapter {
  int status = 503;
  int homeStatus = 200;
  int homeRequests = 0;
  int keepAliveRequests = 0;
  final keepAliveReceived = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final keepAlive = options.uri.path == '/ajax_login.php';
    if (keepAlive) {
      keepAliveRequests++;
      if (!keepAliveReceived.isCompleted) keepAliveReceived.complete();
    }
    if (options.uri.path == '/') homeRequests++;
    return ResponseBody.fromString(
      options.uri.path == '/startseite.php' ? '{"entrys":[]}' : '{}',
      keepAlive ? status : (options.uri.path == '/' ? homeStatus : 200),
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Cryptor extends Cryptor {
  @override
  Future<void> initialize(Dio dioClient) async {}
}

class _ManualTimer implements Timer {
  final void Function(Timer) callback;
  _ManualTimer(this.callback);

  @override
  bool isActive = true;

  @override
  int tick = 0;

  void fire() {
    if (isActive) {
      tick++;
      callback(this);
    }
  }

  @override
  void cancel() => isActive = false;
}

void main() {
  late LanisSession session;
  late _Adapter adapter;

  setUp(() async {
    adapter = _Adapter();
    session = LanisSession(
      account: ClearTextAccount(
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
    session.cryptor = _Cryptor();
  });

  tearDown(() async {
    await session.dispose();
    session.connectionChecker.dispose();
  });

  Future<void> addCookie() => session.jar.saveFromResponse(
    Uri.parse('https://start.schulportal.hessen.de/'),
    [Cookie('sid', 'test-session')],
  );

  Future<LanisSession> sessionWithCachedConnection() async {
    final checker = _CachedOnlineChecker();
    final cachedSession = LanisSession(
      account: session.account,
      config: session.config,
      connectionChecker: checker,
    );
    addTearDown(() async {
      await cachedSession.dispose();
      checker.dispose();
    });
    await cachedSession.prepareDio();
    return cachedSession;
  }

  test(
    'authentication immediately after keep-alive 503 reports offline',
    () async {
      final cachedSession = await sessionWithCachedConnection();
      await cachedSession.jar.saveFromResponse(
        Uri.parse('https://start.schulportal.hessen.de/'),
        [Cookie('sid', 'test-session')],
      );
      await cachedSession.preventLogout();
      await expectLater(
        cachedSession.authenticate(),
        throwsA(isA<NoConnectionException>()),
      );
      expect(adapter.homeRequests, 0);
    },
  );

  test(
    'ordinary startup authentication still reports a home-page 503 as down',
    () async {
      adapter.homeStatus = 503;
      final cachedSession = await sessionWithCachedConnection();
      await expectLater(
        cachedSession.authenticate(),
        throwsA(isA<LanisDownException>()),
      );
      expect(adapter.homeRequests, 1);
      expect(adapter.keepAliveRequests, 0);
    },
  );

  test('keep-alive contains a 503 and marks connection disconnected', () async {
    await addCookie();
    await expectLater(session.preventLogout(), completes);
    expect(adapter.keepAliveRequests, 1);
    expect(session.connectionChecker.status, ConnectionStatus.disconnected);
  });

  test('successful keep-alive still marks connection connected', () async {
    adapter.status = 200;
    await addCookie();
    await session.preventLogout();
    expect(adapter.keepAliveRequests, 1);
    expect(session.connectionChecker.status, ConnectionStatus.connected);
  });

  test('absent sid skips keep-alive', () async {
    await session.preventLogout();
    expect(adapter.keepAliveRequests, 0);
  });

  test('the installed periodic callback contains a 503', () async {
    late _ManualTimer timer;
    await runZoned(
      () => session.authenticate(
        withoutData: true,
        withLoginUrl: 'https://start.schulportal.hessen.de/test-login',
      ),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          expect(duration, const Duration(seconds: 10));
          timer = _ManualTimer(callback);
          return timer;
        },
      ),
    );
    await addCookie();
    final disconnected = session.connectionChecker.statusStream.firstWhere(
      (status) => status == ConnectionStatus.disconnected,
    );
    timer.fire();
    await adapter.keepAliveReceived.future.timeout(const Duration(seconds: 1));
    await disconnected.timeout(const Duration(seconds: 1));
    expect(adapter.keepAliveRequests, 1);
    expect(session.connectionChecker.status, ConnectionStatus.disconnected);
  });
}
