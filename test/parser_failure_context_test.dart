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
  final Object failure;

  _FailingCryptor([Object? failure])
    : failure =
          failure ??
          const FormatException(
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
        expect(
          error.toString(),
          isNot(contains('PRIVATE_CONVERSATION_CONTENT')),
        );
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

  test(
    'calendar event failure includes details and the parsing stack',
    () async {
      final parser = CalendarParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);
      try {
        await parser.getEvent('event');
        fail('Malformed event JSON must fail');
      } on UnknownException catch (error, stack) {
        expect(error, isA<LanisException>());
        expect(error.cause, contains('FormatException'));
        expect(error.cause, contains('Unexpected character'));
        expect(stack.toString(), contains('CalendarParser.getEvent'));
      }
    },
  );

  test(
    'lesson parsing failure includes details and its original location',
    () async {
      final parser = LessonsStudentParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);
      try {
        await parser.getUploadInfo(
          'https://start.schulportal.hessen.de/upload',
        );
        fail('Missing upload sections must fail');
      } on UnknownException catch (error, stack) {
        expect(error, isA<LanisException>());
        expect(error.cause, contains('Missing submission requirements'));
        expect(error, isA<LanisException>());
        expect(
          stack.toString(),
          contains('LessonsStudentParser.getUploadInfo'),
        );
      }
    },
  );

  test(
    'conversation boolean parsing retains error details and stack',
    () async {
      final parser = ConversationsParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);
      try {
        await parser.hideConversation('conversation');
        fail('Invalid boolean response must fail');
      } on UnknownException catch (error, stack) {
        expect(error.cause, contains('FormatException'));
        expect(error.cause, contains('Invalid boolean'));
        expect(
          stack.toString(),
          contains('ConversationsParser.hideConversation'),
        );
      }
    },
  );

  test('conversation refresh retains the original failure stack', () async {
    final cryptor = _FailingCryptor(StateError('encryption unavailable'));
    session.cryptor = cryptor;
    final parser = ConversationsParser(ctx, isConnected: () async => true);
    addTearDown(parser.dispose);
    try {
      await parser.refreshConversation('conversation', 0);
      fail('Encryption failure must fail');
    } on UnknownException catch (error, stack) {
      expect(error.cause, contains('StateError'));
      expect(error.cause, contains('encryption unavailable'));
      expect(stack.toString(), cryptor.origin.toString());
    }
  });

  test('existing Lanis exceptions retain their type and identity', () async {
    final failure = UnauthorizedException('session expired');
    final cryptor = _FailingCryptor(failure);
    session.cryptor = cryptor;
    final parser = ConversationsParser(ctx, isConnected: () async => true);
    addTearDown(parser.dispose);
    try {
      await parser.refreshConversation('conversation', 0);
      fail('Authorization failure must fail');
    } on LanisException catch (error, stack) {
      expect(error, same(failure));
      expect(stack.toString(), cryptor.origin.toString());
    }
  });
}
