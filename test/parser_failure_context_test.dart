import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/liblanis.dart';
import 'package:liblanis/src/session/cryptor.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;
}

class _Adapter implements HttpClientAdapter {
  String events = 'invalid calendar JSON';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    options.method == 'GET' ? '<html></html>' : events,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/plain'],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _FailingCryptor extends Cryptor {
  final failure = const FormatException(
    'invalid encrypted conversation input',
    'PRIVATE_CONVERSATION_CONTENT',
  );
  final origin = StackTrace.fromString('original cryptor stack');

  @override
  String encryptString(String decryptedData) =>
      Error.throwWithStackTrace(failure, origin);
}

void main() {
  late LanisSession session;
  late LanisDatabase db;
  late AppletContext ctx;
  late _Adapter adapter;

  setUp(() async {
    db = LanisDatabase.open();
    adapter = _Adapter();
    final account = ClearTextAccount(
      localId: 1,
      schoolID: 1,
      username: 'u',
      password: 'p',
      schoolName: 'Test',
    );
    session = LanisSession(
      account: account,
      config: LanisConfig(httpAdapter: adapter),
      connectionChecker: _OnlineChecker(),
    );
    await session.prepareDio();
    ctx = AppletContext(
      session: session,
      database: db,
      account: account,
      accountSettings: TypedSettings.account(db, 1),
    );
  });
  tearDown(() async {
    await session.dispose();
    session.connectionChecker.dispose();
    db.dispose();
  });

  test('calendar retains the parsing cause and original stack', () async {
    final parser = CalendarParser(ctx, isConnected: () async => true);
    addTearDown(parser.dispose);
    try {
      await parser.getCalendar(
        startDate: DateTime(2026),
        endDate: DateTime(2027),
      );
      fail('Malformed calendar JSON must fail');
    } on UnknownException catch (error, stack) {
      expect(error.cause, contains('FormatException'));
      expect(stack.toString(), contains('CalendarParser.parseEventsJson'));
    }
  });

  test('valid empty calendar still succeeds', () async {
    adapter.events = '[]';
    final parser = CalendarParser(ctx, isConnected: () async => true);
    addTearDown(parser.dispose);
    expect(
      await parser.getCalendar(
        startDate: DateTime(2026),
        endDate: DateTime(2027),
      ),
      isEmpty,
    );
  });

  test('calendar diagnostics exclude response content', () async {
    adapter.events = '{"student":"PRIVATE_CALENDAR_CONTENT"}';
    final parser = CalendarParser(ctx, isConnected: () async => true);
    addTearDown(parser.dispose);
    try {
      await parser.getCalendar(
        startDate: DateTime(2026),
        endDate: DateTime(2027),
      );
      fail('Wrong-shaped calendar JSON must fail');
    } on UnknownException catch (error, stack) {
      expect(error.cause, 'FormatException');
      expect(error.toString(), isNot(contains('PRIVATE_CALENDAR_CONTENT')));
      expect(stack.toString(), contains('CalendarParser.parseEventsJson'));
    }
  });

  test(
    'conversation retains its unexpected cause and original stack',
    () async {
      session.cryptor = _FailingCryptor();
      final parser = ConversationsParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);
      try {
        await parser.getSingleConversation('conversation');
        fail('Malformed encrypted input must fail');
      } on UnknownException catch (error, stack) {
        expect(error.cause, 'FormatException');
        expect(error.toString(), isNot(contains('PRIVATE_CONVERSATION_CONTENT')));
        expect(stack.toString(), contains('original cryptor stack'));
      }
    },
  );

  test('conversation offline failure remains typed', () async {
    final parser = ConversationsParser(ctx, isConnected: () async => false);
    addTearDown(parser.dispose);
    await expectLater(
      parser.getSingleConversation('conversation'),
      throwsA(isA<NoConnectionException>()),
    );
  });
}
