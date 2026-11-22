import 'dart:convert';
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

class _ConversationsAdapter implements HttpClientAdapter {
  int statusCode = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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
  late _ConversationsAdapter adapter;
  late LanisDatabase database;
  late LanisSession session;
  late ConversationsParser parser;

  setUp(() async {
    adapter = _ConversationsAdapter();
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
    session.cryptor = Cryptor()..key = Uint8List.fromList(List.filled(46, 7));
    parser = ConversationsParser(
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

  test('getHome maps 302 redirect to UnauthorizedException', () async {
    adapter.statusCode = 302;
    adapter.body = '';
    await expectLater(
      parser.getHome(),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('getHome maps non-string rows (e.g. false) to UnsaltedOrUnknownException', () async {
    adapter.statusCode = 200;
    adapter.body = jsonEncode({'rows': false});
    await expectLater(
      parser.getHome(),
      throwsA(isA<UnsaltedOrUnknownException>()),
    );
  });

  test('getHome maps corrupted PKCS7 padding to UnsaltedOrUnknownException', () async {
    final otherCryptor = Cryptor()..key = Uint8List.fromList(List.filled(46, 9));
    final encryptedWithWrongKey = otherCryptor.encryptString('[]');
    adapter.statusCode = 200;
    adapter.body = jsonEncode({'rows': encryptedWithWrongKey});
    await expectLater(
      parser.getHome(),
      throwsA(isA<UnsaltedOrUnknownException>()),
    );
  });
}
