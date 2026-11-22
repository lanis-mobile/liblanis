import 'dart:async';

import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;
}

class _Session extends LanisSession {
  Object? failure;
  final failureStack = StackTrace.fromString('authentication failure origin');
  int authenticationCalls = 0;

  _Session({required super.account, required super.config})
    : super(connectionChecker: _OnlineChecker());

  @override
  Future<void> authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    authenticationCalls++;
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack);
  }
}

class _Parser extends AppletParser<String> {
  int calls = 0;
  bool alwaysFail = false;
  Object? readFailure;

  _Parser(AppletContext context)
    : super(
        context,
        const AppletMeta(
          appletPhpUrl: 'test.php',
          supportedAccountTypes: [AccountType.student],
          refreshInterval: Duration(milliseconds: 1),
        ),
        isConnected: () async => true,
      );

  @override
  Future<String> getHome() async {
    calls++;
    if (readFailure != null) throw readFailure!;
    if (calls == 1 || alwaysFail) throw FormatException('fetch failed');
    return 'retried content';
  }
}

class _CachedParser extends AppletParser<String> {
  int calls = 0;
  bool alwaysFail = false;
  Object? readFailure;
  Object? presentFailure;

  _CachedParser(AppletContext context)
    : super(
        context,
        const AppletMeta(
          appletPhpUrl: 'cached_test.php',
          supportedAccountTypes: [AccountType.student],
          refreshInterval: Duration(milliseconds: 1),
        ),
        isConnected: () async => true,
      );

  static final CacheRequest<String> _homeRequest = CacheRequest<String>(
    operation: 'test.cached.home',
    arguments: const {},
    codec: CacheCodec<String>(
      id: 'string:v1',
      encode: (value) => value,
      decode: (json) => json as String,
    ),
    maxAge: const Duration(hours: 1),
  );

  @override
  CacheRequest<String> get homeCacheRequest => _homeRequest;

  @override
  String presentCachedHome(String value) {
    if (presentFailure != null) throw presentFailure!;
    return value;
  }

  @override
  Future<String> getHome() async {
    calls++;
    if (readFailure != null) throw readFailure!;
    if (calls == 1 || alwaysFail) throw FormatException('session expired html');
    return 'cached retried content';
  }
}

void main() {
  late _Session session;
  late _Parser parser;
  late LanisDatabase database;
  late List<Object> reported;

  setUp(() {
    reported = [];
    LanisClient.configure(
      onUnexpectedError: (error, stack, {required appletPhpUrl}) {
        reported.add(error);
      },
    );
    database = LanisDatabase.open();
    final account = ClearTextAccount(
      localId: 1,
      schoolID: 1,
      username: 'test',
      password: 'test',
      schoolName: 'Test',
      accountType: AccountType.student,
    );
    session = _Session(account: account, config: LanisClient.config!);
    parser = _Parser(
      AppletContext(
        session: session,
        database: database,
        account: account,
        accountSettings: TypedSettings.account(database, 1),
      ),
    );
  });

  tearDown(() async {
    parser.dispose();
    await session.dispose();
    session.connectionChecker.dispose();
    database.dispose();
    LanisClient.reset();
  });

  test(
    'a foreground transport failure keeps a loaded legacy module without logging in again',
    () async {
      parser.calls = 1;
      await parser.fetchData();
      final fetched = parser.latestResponse!.fetchedAt;
      parser.readFailure = NoConnectionException();
      await parser.fetchData(forceRefresh: true);
      expect(parser.latestResponse!.status, FetcherStatus.done);
      expect(parser.latestResponse!.content, 'retried content');
      expect(parser.latestResponse!.contentStatus, ContentStatus.offline);
      expect(parser.latestResponse!.fetchedAt, fetched);
      expect(session.authenticationCalls, 0);
    },
  );

  for (final failure in <Object>[
    NoConnectionException(),
    LanisDownException(),
    WrongCredentialsException(),
    LoginTimeoutException('10s'),
    UnknownException('HTTP 429'),
    StateError('unexpected authentication failure'),
  ]) {
    test(
      'refresh contains ${failure.runtimeType} from re-authentication',
      () async {
        session.failure = failure;
        final responses = <FetcherResponse<String>>[];
        final subscription = parser.stream.listen(responses.add);
        addTearDown(subscription.cancel);

        await expectLater(parser.fetchData(forceRefresh: true), completes);
        await Future<void>.delayed(Duration.zero);

        expect(session.authenticationCalls, 1);
        expect(parser.calls, 1);
        expect(responses.map((r) => r.status), [
          FetcherStatus.fetching,
          FetcherStatus.error,
        ]);
        expect(responses.last.error!.exception, same(failure));
        expect(
          responses.last.error!.stackTrace.toString(),
          contains('authentication failure origin'),
        );
        expect(
          reported,
          isUnexpectedParserError(failure) ? [same(failure)] : isEmpty,
        );
      },
    );
  }

  test('periodic refresh contains a failed re-authentication', () async {
    session.failure = NoConnectionException();
    final response = parser.stream.firstWhere(
      (r) => r.status == FetcherStatus.error,
    );
    parser.startAutoRefresh();
    final result = await response.timeout(const Duration(seconds: 1));
    parser.stopAutoRefresh();
    expect(result.error!.exception, same(session.failure));
  });

  test('successful re-authentication retries the fetch once', () async {
    await parser.fetchData();
    expect(session.authenticationCalls, 1);
    expect(parser.calls, 2);
    expect(parser.latestResponse!.content, 'retried content');
    expect(parser.latestResponse!.status, FetcherStatus.done);
    expect(reported, isEmpty);
  });

  test('final fetch failure still uses normal reporting', () async {
    parser.alwaysFail = true;
    await parser.fetchData();
    expect(session.authenticationCalls, 1);
    expect(parser.calls, 2);
    expect(parser.latestResponse!.status, FetcherStatus.error);
    expect(parser.latestResponse!.error!.exception, isA<FormatException>());
    expect(reported, hasLength(1));
  });

  group('cached applet re-authentication', () {
    late _CachedParser cachedParser;

    setUp(() async {
      final id = await database.addAccount(
        schoolId: 1,
        schoolName: 'Test',
        username: 'cached_test',
        password: 'pw',
        accountType: AccountType.student,
      );
      final account = (await database.getAccount(id))!;
      cachedParser = _CachedParser(
        AppletContext(
          session: session,
          database: database,
          account: account,
          accountSettings: TypedSettings.account(database, id),
        ),
      );
    });

    tearDown(() {
      cachedParser.dispose();
    });

    test('re-authenticates once and retries on non-transport error', () async {
      await cachedParser.fetchData();
      expect(session.authenticationCalls, 1);
      expect(cachedParser.calls, 2);
      expect(cachedParser.latestResponse!.status, FetcherStatus.done);
      expect(cachedParser.latestResponse!.content, 'cached retried content');
      expect(reported, isEmpty);
    });

    test('does not re-authenticate on transport failure', () async {
      cachedParser.readFailure = NoConnectionException();
      await cachedParser.fetchData();
      expect(session.authenticationCalls, 0);
      expect(cachedParser.calls, 1);
      expect(cachedParser.latestResponse!.status, FetcherStatus.error);
      expect(cachedParser.latestResponse!.contentStatus, ContentStatus.offline);
    });

    test('does not re-authenticate on cacheOnly miss', () async {
      await cachedParser.fetchCachedData(policy: CacheReadPolicy.cacheOnly);
      expect(session.authenticationCalls, 0);
      expect(cachedParser.calls, 0);
      expect(cachedParser.latestResponse!.status, FetcherStatus.error);
    });

    test('emits auth error when re-authentication fails', () async {
      session.failure = WrongCredentialsException();
      await cachedParser.fetchData();
      expect(session.authenticationCalls, 1);
      expect(cachedParser.calls, 1);
      expect(cachedParser.latestResponse!.status, FetcherStatus.error);
      expect(
        cachedParser.latestResponse!.error!.exception,
        same(session.failure),
      );
      expect(reported, isEmpty);
    });

    test('reports final failure when retry also fails', () async {
      cachedParser.alwaysFail = true;
      await cachedParser.fetchData();
      expect(session.authenticationCalls, 1);
      expect(cachedParser.calls, 2);
      expect(cachedParser.latestResponse!.status, FetcherStatus.error);
      expect(
        cachedParser.latestResponse!.error!.exception,
        isA<FormatException>(),
      );
      expect(reported, hasLength(1));
    });

    test(
      'does not re-authenticate on ConfigurationException or NotSupportedException',
      () async {
        for (final error in [
          ConfigurationException('bad redirect'),
          NotSupportedException('unsupported'),
        ]) {
          cachedParser.readFailure = error;
          await cachedParser.fetchData(forceRefresh: true);
          expect(session.authenticationCalls, 0);
          expect(cachedParser.latestResponse!.status, FetcherStatus.error);
          expect(cachedParser.latestResponse!.error!.exception, same(error));
        }
      },
    );

    test(
      'does not re-authenticate when presentCachedHome throws after load succeeds',
      () async {
        cachedParser.calls = 1; // make getHome succeed
        cachedParser.presentFailure = StateError('presentation bug');
        await cachedParser.fetchData();
        expect(session.authenticationCalls, 0);
        expect(cachedParser.calls, 2);
        expect(cachedParser.latestResponse!.status, FetcherStatus.error);
        expect(
          cachedParser.latestResponse!.error!.exception,
          isA<StateError>(),
        );
        expect(reported, hasLength(1));
      },
    );

    test(
      'preserves valid cached content if re-authentication fails with a transport error',
      () async {
        // Seed valid cache first.
        cachedParser.calls = 1;
        await cachedParser.fetchData();
        expect(cachedParser.latestResponse!.status, FetcherStatus.done);
        expect(cachedParser.latestResponse!.content, 'cached retried content');

        // Next refresh hits an expired session, then loses connection during re-auth.
        cachedParser.calls = 0;
        session.failure = NoConnectionException();
        await cachedParser.fetchData(forceRefresh: true);

        expect(session.authenticationCalls, 1);
        expect(cachedParser.latestResponse!.status, FetcherStatus.done);
        expect(cachedParser.latestResponse!.content, 'cached retried content');
        expect(
          cachedParser.latestResponse!.contentStatus,
          ContentStatus.offline,
        );
        expect(
          cachedParser.latestResponse!.error!.exception,
          same(session.failure),
        );
        expect(reported, isEmpty);
      },
    );

    test(
      'overlapping cached refreshes coalesce into a single re-authentication',
      () async {
        await Future.wait([
          cachedParser.fetchData(forceRefresh: true),
          cachedParser.fetchData(forceRefresh: true),
        ]);
        expect(session.authenticationCalls, 1);
        expect(cachedParser.calls, 2);
        expect(cachedParser.latestResponse!.status, FetcherStatus.done);
        expect(cachedParser.latestResponse!.content, 'cached retried content');
        expect(reported, isEmpty);
      },
    );
  });
}
