import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

class _TestAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _TestAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _TestChecker extends ConnectionChecker {
  _TestChecker(_TestAdapter adapter) : super(httpAdapter: adapter);

  @override
  Future<bool> testConnection() async => true;
}

class _TestSession extends LanisSession {
  _TestSession({
    required super.account,
    required super.config,
    required super.connectionChecker,
    required _TestAdapter adapter,
  }) {
    dio.httpClientAdapter = adapter;
  }

  @override
  Future<void> authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    throw StateError('Unit tests must not authenticate');
  }
}

Future<AppletContext> _createContext(_TestAdapter adapter) async {
  final db = LanisDatabase.open();
  final id = await db.addAccount(
    schoolId: 5182,
    schoolName: 'Test School',
    username: 'user',
    password: 'pw',
    accountType: AccountType.teacher,
  );
  final account = (await db.getAccount(id))!;
  final checker = _TestChecker(adapter);
  final session = _TestSession(
    account: account,
    config: const LanisConfig(),
    connectionChecker: checker,
    adapter: adapter,
  );
  addTearDown(() async {
    await session.dispose();
    checker.dispose();
    db.dispose();
  });
  return AppletContext(
    account: account,
    session: session,
    database: db,
    accountSettings: TypedSettings.account(db, id),
  );
}

void main() {
  group('LessonsTeacherParser fixes', () {
    test('postNewEntry omits hardcoded Content-Length and sets book Referer', () async {
      final adapter = _TestAdapter((options) async {
        return ResponseBody.fromString(jsonEncode({'ok': true}), 200);
      });
      final ctx = await _createContext(adapter);
      final parser = LessonsTeacherParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);

      final ok = await parser.postNewEntry(
        book: '42',
        datum: '22.11.2026',
        zeigeauchvorheran: false,
        stundenVon: '1',
        stundenBis: '2',
        subject: 'Topic with a longer body than 296 bytes ${'x' * 300}',
        inhalt: 'Content',
        homework: 'Homework',
        abgabe: false,
        abgabeBisDate: DateTime(2026, 11, 25),
        abgabeBisTime: const SphTimeOfDay(hour: 12, minute: 0),
        abgabeSichtbar: false,
      );

      expect(ok, isTrue);
      expect(adapter.requests, hasLength(1));
      final headers = adapter.requests.single.headers;
      final contentLength =
          headers['content-length'] ?? headers['Content-Length'];
      expect(contentLength?.toString(), isNot('296'));
      if (contentLength != null) {
        expect(int.parse(contentLength.toString()), greaterThan(300));
      }
      expect(
        headers['Referer'],
        'https://start.schulportal.hessen.de/meinunterricht.php?a=view&id=42',
      );
    });

    test('getCourseFolderDetails URL-encodes fileName in download URLs', () async {
      const html = '''
<html>
<head><title>Math - Schulportal</title></head>
<body>
  <div id="content">
    <h1>Math <small>20 - <a>LG</a></small><span>Thema: Algebra</span></h1>
  </div>
  <div id="writeBox">
    <div class="form-group"><label class="col-sm-3 control-label"><span class="fa"></span></label></div>
    <div class="form-group"><label class="col-sm-3 control-label"><span class="fa"></span></label></div>
    <div class="form-group"><label class="col-sm-3 control-label"><span class="fa fa-child"></span></label></div>
    <div class="form-group"><label class="col-sm-3 control-label"><span class="fa fa-child"></span></label></div>
    <div class="form-group"><label class="col-sm-3 control-label"><span class="fa fa-child"></span></label></div>
  </div>
  <select id="stundenVon"><option>1</option></select>
  <table id="historyTable">
    <thead><tr><th>Datum</th><th>Info</th><th>Inhalt</th><th>Aktionen</th></tr></thead>
    <tbody>
      <tr data-entry="99">
        <td>22.11.2026 <small>1. - 2.</small></td>
        <td></td>
        <td>
          <span class="thema">Thema</span>
          <div class="file" data-file="Übung &amp; Test #1.pdf" data-entry="99" data-extension="pdf">
            <i class="fa fa-child fileVisibility on"></i>
          </div>
        </td>
        <td>
          <div class="btn-group"></div>
          <div class="btn-group"><button class="btn"><span class="badge">0</span></button></div>
          <div class="btn-group"><button class="btn"></button></div>
        </td>
      </tr>
    </tbody>
  </table>
</body></html>
''';
      final adapter = _TestAdapter(
        (_) async => ResponseBody.fromString(html, 200),
      );
      final ctx = await _createContext(adapter);
      final parser = LessonsTeacherParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);

      final details = await parser.getCourseFolderDetails('42');
      expect(details.history, hasLength(1));
      final file = details.history.single.files.single;
      expect(file.name, 'Übung & Test #1.pdf');
      expect(file.url.queryParameters['f'], 'Übung & Test #1.pdf');
      expect(file.url.queryParameters['id'], '42');
      expect(file.url.queryParameters['e'], '99');
    });
  });

  group('CalendarParser.getCalendar', () {
    test('URL-encodes searchQuery in form body', () async {
      final adapter = _TestAdapter((options) async {
        if (options.method == 'GET') {
          return ResponseBody.fromString('<html><body></body></html>', 200);
        }
        return ResponseBody.fromString('[]', 200);
      });
      final ctx = await _createContext(adapter);
      final parser = CalendarParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);

      await parser.getCalendar(
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
        searchQuery: 'A & B = 100%',
      );

      final post = adapter.requests.last;
      final parsedForm = Uri.splitQueryString(post.data as String);
      expect(parsedForm['s'], 'A & B = 100%');
      expect(parsedForm['f'], 'getEvents');
    });
  });

  group('ConversationsParser fixes', () {
    test('hideConversation and showConversation accept bool JSON responses and preserve DioException in NetworkException', () async {
      var fail = false;
      final adapter = _TestAdapter((options) async {
        if (fail) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return ResponseBody.fromString(
          'true',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final ctx = await _createContext(adapter);
      final parser = ConversationsParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);

      expect(await parser.hideConversation('u1'), isTrue);
      expect(await parser.showConversation('u1'), isTrue);

      fail = true;
      await expectLater(
        () => parser.hideConversation('u1'),
        throwsA(
          isA<NetworkException>().having(
            (e) => CacheService.isTransportFailure(e),
            'isTransportFailure',
            isTrue,
          ),
        ),
      );
    });

    test('OverviewFiltering.toggleEntry ignores unknown id without throwing', () async {
      final adapter = _TestAdapter(
        (_) async => ResponseBody.fromString('[]', 200),
      );
      final ctx = await _createContext(adapter);
      final parser = ConversationsParser(ctx, isConnected: () async => true);
      addTearDown(parser.dispose);

      final filter = OverviewFiltering(parser);
      filter.entries.add(
        const OverviewEntry(
          id: 'known',
          title: 'Hello',
          shortName: 'ABC',
          fullName: 'Alice',
          date: '01.01.2026',
          unread: false,
          hidden: false,
        ),
      );

      expect(() => filter.toggleEntry('missing', hidden: true), returnsNormally);
      expect(filter.entries.single.hidden, isFalse);
    });
  });

  group('Model equality and hashCode contracts', () {
    test('TimetableSubject hashCode matches ==', () {
      final a = TimetableSubject(
        id: '1',
        name: 'Math',
        raum: 'R1',
        lehrer: 'MUE',
        badge: 'A',
        calendarWeekParity: TimetableWeekParity.even,
        duration: 2,
        stunde: 1,
        startTime: const SphTimeOfDay(hour: 8, minute: 0),
        endTime: const SphTimeOfDay(hour: 9, minute: 30),
      );
      final b = TimetableSubject(
        id: '1',
        name: 'Math',
        raum: 'R1',
        lehrer: 'MUE',
        badge: 'A',
        calendarWeekParity: TimetableWeekParity.even,
        duration: 2,
        stunde: 1,
        startTime: const SphTimeOfDay(hour: 8, minute: 0),
        endTime: const SphTimeOfDay(hour: 9, minute: 30),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect({a}.contains(b), isTrue);
    });

    test('LessonPupil supports value-based Map lookups', () {
      final overview = ParentLessonsOverview(
        lessonsByPupil: {
          const LessonPupil(id: '101', name: 'Alice'): const [],
        },
      );
      expect(
        overview.lessonsByPupil[const LessonPupil(id: '101', name: 'Alice')],
        isNotNull,
      );
      expect(
        const LessonPupil(id: '101', name: 'Alice').hashCode,
        const LessonPupil(id: '101', name: 'Alice').hashCode,
      );
    });

    test('KnownParticipant and OverviewEntry compare fields directly', () {
      final p1 = KnownParticipant(name: 'Alice', type: PersonType.values.first);
      final p2 = KnownParticipant(name: 'Alice', type: PersonType.values.last);
      final p3 = KnownParticipant(name: 'Bob', type: PersonType.values.first);
      expect(p1, equals(p2));
      expect(p1, isNot(equals(p3)));

      const e1 = OverviewEntry(
        id: '1',
        title: 'A',
        shortName: null,
        fullName: 'Alice',
        date: '01.01.2026',
        unread: true,
        hidden: false,
      );
      const e2 = OverviewEntry(
        id: '1',
        title: 'B',
        shortName: null,
        fullName: 'Alice',
        date: '01.01.2026',
        unread: false,
        hidden: true,
      );
      expect(e1, equals(e2));
    });
  });
}
