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
    if (calls == 1 || alwaysFail) throw FormatException('fetch failed');
    return 'retried content';
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
}
