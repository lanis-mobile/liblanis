import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;

  @override
  Future<bool> get connected async => true;
}

class _SearchAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  int statusCode = 200;
  String body = '[[],[]]';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _SearchAdapter adapter;
  late LanisDatabase database;
  late LanisSession session;
  late DataStorageParser parser;

  setUp(() async {
    adapter = _SearchAdapter();
    database = LanisDatabase.open();
    const account = ClearTextAccount(
      localId: 1,
      schoolID: 1,
      username: 'test',
      password: 'test',
      schoolName: 'Test',
      accountType: AccountType.student,
    );
    session = LanisSession(
      account: account,
      config: LanisConfig(httpAdapter: adapter),
      connectionChecker: _OnlineChecker(),
    );
    await session.prepareDio();
    parser = DataStorageParser(
      AppletContext(
        session: session,
        database: database,
        account: account,
        accountSettings: TypedSettings.account(database, 1),
      ),
      isConnected: () async => true,
    );
  });

  tearDown(() async {
    parser.dispose();
    await session.dispose();
    session.connectionChecker.dispose();
    database.dispose();
  });

  test('searchFiles sends a bodyless GET request and returns first result list', () async {
    adapter.body = jsonEncode([
      [
        {'id': '42', 'text': 'undraw-work-chat-hc3y.svg'},
      ],
    ]);

    final results = await parser.searchFiles('undraw');

    expect(adapter.lastOptions?.method, 'GET');
    expect(adapter.lastOptions?.data, isNull);
    expect(adapter.lastOptions?.queryParameters, {
      'q': 'undraw',
      'a': 'searchFiles',
    });
    expect(results, [
      {'id': '42', 'text': 'undraw-work-chat-hc3y.svg'},
    ]);
  });

  test('searchFiles maps 302 redirect to UnauthorizedException', () async {
    adapter.statusCode = 302;
    adapter.body = '';
    await expectLater(
      parser.searchFiles('test'),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('searchFiles rejects unexpected JSON object payloads', () async {
    adapter.statusCode = 200;
    adapter.body = jsonEncode({'error': 'unexpected'});
    await expectLater(
      parser.searchFiles('test'),
      throwsA(isA<UnknownException>()),
    );
  });

  test('searchFiles returns empty list without requesting for queries under 2 chars', () async {
    expect(await parser.searchFiles(''), isEmpty);
    expect(await parser.searchFiles('a'), isEmpty);
    expect(adapter.lastOptions, isNull);
  });

  test('searchFiles returns empty list for server short-query response', () async {
    adapter.statusCode = 200;
    adapter.body = jsonEncode({
      'id': 0,
      'text': 'Bitte mindestens zwei Zeichen eingeben!',
    });
    expect(await parser.searchFiles('ab'), isEmpty);
  });

  test('searchFiles returns empty list for empty array response', () async {
    adapter.statusCode = 200;
    adapter.body = '[[]]';
    expect(await parser.searchFiles('test'), isEmpty);
  });
}
