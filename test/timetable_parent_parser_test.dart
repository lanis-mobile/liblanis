import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'package:riverpod/riverpod.dart';
import 'package:liblanis/liblanis.dart'
    show appletContextProvider, timetableParentParserProvider;
import 'package:test/test.dart';

const fixtureDirectory = 'test/fixtures/timetable/parents';
String fixture(String name) =>
    File('$fixtureDirectory/$name.html').readAsStringSync();
ParentTimetableSelection overview([String name = 'two_pupils_overview']) =>
    TimetableParentParser.parseSelectionDocument(parse(fixture(name)));

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String overviewHtml = fixture('two_pupils_overview');
  String? detailHtml;
  bool failTransport = false;
  bool redirectHome = false;
  String? redirectLocation;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    if (failTransport) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'fixture transport failure',
      );
    }
    if (options.method != 'GET' || options.uri.path != '/stundenplan.php') {
      throw StateError('Unexpected request');
    }
    if (options.uri.queryParameters['a'] == null) {
      if (redirectHome) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            if (redirectLocation != null) 'location': [redirectLocation!],
          },
        );
      }
      return ResponseBody.fromString(overviewHtml, 200);
    }
    final pupil = options.uri.queryParameters['p'];
    if (!['101', '102'].contains(pupil)) throw StateError('Unexpected pupil');
    return ResponseBody.fromString(
      detailHtml ?? fixture('pupil_${pupil == '101' ? 1 : 2}_detail'),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Checker extends ConnectionChecker {
  _Checker(_Adapter adapter) : super(httpAdapter: adapter);

  @override
  Future<bool> testConnection() async => true;
}

class _Session extends LanisSession {
  _Session({
    required super.account,
    required super.config,
    required super.connectionChecker,
    required _Adapter adapter,
  }) {
    dio.httpClientAdapter = adapter;
    dio.options.followRedirects = false;
    dio.options.validateStatus = (status) => status == 200 || status == 302;
  }
  @override
  Future<void> authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    throw StateError('Unit tests must not authenticate');
  }
}

void main() {
  late LanisDatabase database;
  late _Adapter adapter;
  late _Session session;
  late AppletContext context;
  late TimetableParentParser parser;
  var online = true;

  setUp(() async {
    adapter = _Adapter();
    LanisClient.configure(httpAdapter: adapter);
    database = LanisDatabase.open();
    final id = await database.addAccount(
      schoolId: 1,
      schoolName: 'Test',
      username: 'parent',
      password: 'test',
      accountType: AccountType.parent,
    );
    final account = (await database.getAccount(id))!;
    session = _Session(
      account: account,
      config: LanisClient.config!,
      connectionChecker: _Checker(adapter),
      adapter: adapter,
    );
    context = AppletContext(
      session: session,
      database: database,
      account: account,
      accountSettings: TypedSettings.account(database, id),
    );
    online = true;
    parser = TimetableParentParser(context, isConnected: () async => online);
  });
  tearDown(() async {
    parser.dispose();
    await session.dispose();
    session.connectionChecker.dispose();
    database.dispose();
    LanisClient.reset();
  });

  test(
    'single-child redirect loads the plan in exactly two requests',
    () async {
      adapter.redirectHome = true;
      adapter.redirectLocation =
          (jsonDecode(
                    File(
                      '$fixtureDirectory/single_child_redirect.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['location']
              as String;
      final result = await parser.getHome();
      expect(result, isA<ParentTimetableLoaded>());
      final loaded = result as ParentTimetableLoaded;
      expect(loaded.pupilId, '102');
      expect(loaded.timetable.planForAll!.expand((day) => day), isNotEmpty);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.uri.queryParameters,
        Uri.parse(adapter.redirectLocation!).queryParameters,
      );
    },
  );

  test('absolute portal redirect preserves child identity', () async {
    adapter.redirectHome = true;
    adapter.redirectLocation =
        'https://start.schulportal.hessen.de/stundenplan.php?e=1&a=detail_klasse&k=1&p=102';
    final loaded = await parser.getHome() as ParentTimetableLoaded;
    expect(loaded.pupilId, '102');
    expect(adapter.requests, hasLength(2));
  });

  test(
    'missing or invalid redirect is rejected without fetching another page',
    () async {
      adapter.redirectHome = true;
      for (final target in <String?>[
        null,
        '',
        'https://example.com/stundenplan.php?a=detail_klasse&p=101',
        'index.php?login=1',
        'stundenplan.php?a=detail_klasse&k=1',
      ]) {
        adapter.redirectLocation = target;
        adapter.requests.clear();
        await expectLater(parser.getHome(), throwsA(isA<LanisException>()));
        expect(adapter.requests, hasLength(1));
      }
    },
  );

  test('an already rendered plan is returned without another request', () async {
    final doc = parse(fixture('pupil_1_detail'));
    doc
        .querySelector('#content')!
        .append(
          parseFragment(
            '<a href="stundenplan.php?a=detail_klasse&k=1&p=101&pdf=1">PDF</a>',
          ),
        );
    adapter.overviewHtml = doc.outerHtml;
    final loaded = await parser.getHome() as ParentTimetableLoaded;
    expect(loaded.pupilId, '101');
    expect(loaded.timetable.planForAll!.expand((day) => day), isNotEmpty);
    expect(adapter.requests, hasLength(1));
  });

  test('rendered plan without a unique child identity is rejected', () async {
    adapter.overviewHtml = fixture('pupil_1_detail');
    await expectLater(parser.getHome(), throwsA(isA<UnknownException>()));
    expect(adapter.requests, hasLength(1));
  });

  test(
    'redirected loaded plan survives offline cache with its pupil identity',
    () async {
      adapter.redirectHome = true;
      adapter.redirectLocation =
          'stundenplan.php?e=1&a=detail_klasse&k=1&p=102';
      await parser.fetchData();
      expect(parser.latestResponse!.status, FetcherStatus.done);
      final onlineResult =
          parser.latestResponse!.content! as ParentTimetableLoaded;
      final offline = TimetableParentParser(
        context,
        isConnected: () async => false,
      );
      addTearDown(offline.dispose);
      await offline.fetchCachedData(policy: CacheReadPolicy.cacheOnly);
      expect(offline.latestResponse!.contentStatus, ContentStatus.offline);
      final restored =
          offline.latestResponse!.content! as ParentTimetableLoaded;
      expect(restored.pupilId, '102');
      expect(restored.timetable.toJson(), onlineResult.timetable.toJson());
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'single-reference selection variant returns a named reference and class',
    () {
      final result = overview('one_pupil_overview');
      expect(result.timetables, hasLength(1));
      final ref = result.timetables.single;
      expect(ref.pupilId, '101');
      expect(ref.pupilName, 'Pupil 1');
      expect(ref.className, '1');
      expect(ref.url.queryParameters, {
        'e': '1',
        'a': 'detail_klasse',
        'k': '1',
        'p': '101',
      });
    },
  );

  test(
    'two-child captured layout retains separate URLs for the same class',
    () {
      final refs = overview().timetables;
      expect(refs.map((r) => r.pupilId), ['101', '102']);
      expect(refs.map((r) => r.pupilName), ['Pupil 1', 'Pupil 2']);
      expect(refs.map((r) => r.className), everyElement('1'));
      expect(refs.map((r) => r.url.queryParameters['p']), ['101', '102']);
    },
  );

  test('overview requests no child detail pages', () async {
    final result = await parser.getHome() as ParentTimetableSelection;
    expect(result.timetables, hasLength(2));
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.queryParameters, isEmpty);
  });

  test(
    'choosing the second child requests that child and preserves extra parameters',
    () async {
      final refs =
          (await parser.getHome() as ParentTimetableSelection).timetables;
      final second = refs.last;
      final selected = ParentTimetableReference(
        pupilId: second.pupilId,
        pupilName: second.pupilName,
        className: second.className,
        url: second.url.replace(
          queryParameters: {
            ...second.url.queryParameters,
            'date': '2026-11-17',
          },
        ),
      );
      final loaded = await parser.getTimetable(selected);
      expect(loaded.pupilId, selected.pupilId);
      final table = loaded.timetable;
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.uri.queryParameters, {
        'e': '1',
        'a': 'detail_klasse',
        'k': '1',
        'p': '102',
        'date': '2026-11-17',
      });
      expect(table.planForAll!.expand((day) => day), isNotEmpty);
      expect(table.planForOwn, isNull);
    },
  );

  for (var i = 1; i <= 2; i++) {
    test('captured child $i detail uses the shared table parser', () async {
      final loaded = await parser.getTimetable(overview().timetables[i - 1]);
      expect(loaded.pupilId, '${100 + i}');
      final table = loaded.timetable;
      final doc = parse(fixture('pupil_${i}_detail'));
      final subjects = table.planForAll!.expand((day) => day).toList();
      expect(subjects.length, doc.querySelectorAll('#all .stunde').length);
      expect(subjects, isNotEmpty);
      expect(subjects.map((s) => s.name), everyElement(startsWith('Subject ')));
      expect(table.hours, isNotEmpty);
    });
  }

  test('existing own-plan parsing is available for parent details', () async {
    final doc = parse(fixture('pupil_1_detail'));
    final own = doc.querySelector('#all')!.clone(true)..id = 'own';
    doc.querySelector('#content')!.append(own);
    adapter.detailHtml = doc.outerHtml;
    final loaded = await parser.getTimetable(overview().timetables.first);
    final table = loaded.timetable;
    expect(
      table.planForOwn!.expand((day) => day).length,
      table.planForAll!.expand((day) => day).length,
    );
  });

  test('mismatched pupils and invalid URLs fail before any request', () async {
    for (final url in [
      'stundenplan.php?e=1&a=detail_klasse&k=1&p=102',
      'stundenplan.php?e=1&a=detail_klasse&k=1',
      'stundenplan.php?e=1&a=detail_klasse&k=1&p=',
      'https://example.com/stundenplan.php?a=detail_klasse&p=101',
      'meinunterricht.php?a=detail_klasse&p=101',
    ]) {
      final ref = ParentTimetableReference(
        pupilId: '101',
        pupilName: 'Pupil',
        className: '1',
        url: Uri.parse(url),
      );
      await expectLater(
        parser.getTimetable(ref),
        throwsA(isA<ConfigurationException>()),
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test(
    'error and authentication pages do not become empty timetables',
    () async {
      adapter.detailHtml = '<div id="content"><h1>Login required</h1></div>';
      await expectLater(
        parser.getTimetable(overview().timetables.first),
        throwsA(
          isA<UnknownException>().having(
            (e) => e.cause,
            'cause',
            contains('Missing parent timetable table'),
          ),
        ),
      );
      expect(
        () => TimetableParentParser.parseSelectionDocument(
          parse(adapter.detailHtml!),
        ),
        throwsA(isA<LanisException>()),
      );
    },
  );

  test(
    'transport failures retain error details inside the Lanis exception hierarchy',
    () async {
      adapter.failTransport = true;
      for (final operation in [
        parser.getHome,
        () => parser.getTimetable(overview().timetables.first),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<NetworkException>().having(
              (error) => error.cause,
              'cause',
              contains('fixture transport failure'),
            ),
          ),
        );
      }
    },
  );

  test('empty valid overview has no references', () {
    final result = TimetableParentParser.parseSelectionDocument(
      parse('<div id="content"><div id="accordion"></div></div>'),
    );
    expect(result.timetables, isEmpty);
  });

  test(
    'malformed child labels or missing pupil parameters fail with typed errors',
    () {
      for (final mutation in ['label', 'pupil']) {
        final doc = parse(fixture('two_pupils_overview'));
        final link = doc.querySelector('a.list-group-item')!;
        if (mutation == 'label') {
          link.text = 'Pupil without class';
        } else {
          link.attributes['href'] = 'stundenplan.php?a=detail_klasse&k=1';
        }
        expect(
          () => TimetableParentParser.parseSelectionDocument(doc),
          throwsA(isA<LanisException>()),
        );
      }
    },
  );

  test(
    'name whitespace is normalized and parentheses inside names are retained',
    () {
      final doc = parse(fixture('one_pupil_overview'));
      doc.querySelector('a.list-group-item')!.text =
          '  Pupil (test)\n Name   ( 10 A ) ';
      final ref = TimetableParentParser.parseSelectionDocument(
        doc,
      ).timetables.single;
      expect(ref.pupilName, 'Pupil (test) Name');
      expect(ref.className, '10 A');
    },
  );

  test(
    'overview and child references survive the applet offline cache',
    () async {
      await parser.fetchData();
      expect(parser.latestResponse!.status, FetcherStatus.done);
      expect(
        (parser.latestResponse!.content! as ParentTimetableSelection)
            .timetables,
        hasLength(2),
      );
      final cached = database.readCacheRecord(
        TimetableParentParserCacheRequests.getHome().keyFor(context.accountId),
      )!;
      expect(jsonDecode(cached.json)['timetables'], hasLength(2));
      final offline = TimetableParentParser(
        context,
        isConnected: () async => false,
      );
      addTearDown(offline.dispose);
      await offline.fetchCachedData(policy: CacheReadPolicy.cacheOnly);
      expect(offline.latestResponse!.contentStatus, ContentStatus.offline);
      final restored =
          (offline.latestResponse!.content! as ParentTimetableSelection)
              .timetables;
      expect(restored.map((r) => r.pupilId), ['101', '102']);
      expect(restored.last.url, overview().timetables.last.url);
      expect(restored.last.pupilName, 'Pupil 2');
      expect(adapter.requests, hasLength(1));
    },
  );

  test('loaded plans preserve the matching child name in offline JSON', () {
    final document = parse(fixture('pupil_1_detail'));
    document.body!.append(
      parseFragment(
        '<nav><a href="stundenplan.php?a=detail_klasse&p=102">Other, Child (2)</a><a href="stundenplan.php?a=detail_klasse&p=101">Pupil (test) Name (1)</a></nav>',
      ),
    );
    final loaded = TimetableParentParser.parseLoadedDocument(
      document,
      pupilId: '101',
    );
    expect(loaded.pupilName, 'Pupil (test) Name');
    final restored = ParentTimetableLoaded.fromJson(
      jsonDecode(jsonEncode(loaded)),
    );
    expect(restored.pupilName, loaded.pupilName);
    final legacy = loaded.toJson()..remove('pupilName');
    expect(ParentTimetableLoaded.fromJson(legacy).pupilName, isNull);
  });

  test('support detection still requires the portal menu entry', () {
    expect(session.doesSupportFeature(Applets.timetable), isFalse);
    session.travelMenu = [
      {'link': 'stundenplan.php'},
    ];
    expect(session.doesSupportFeature(Applets.timetable), isTrue);
    expect(
      session.doesSupportFeature(
        Applets.timetable,
        overrideAccountType: AccountType.student,
      ),
      isTrue,
    );
    expect(
      session.doesSupportFeature(
        Applets.timetable,
        overrideAccountType: AccountType.teacher,
      ),
      isTrue,
    );
  });

  test(
    'imperative dispatch selects the parent parser and retains student access',
    () {
      final registry = EasyParsers(ctx: context, isConnected: () async => true);
      addTearDown(registry.disposeAll);
      expect(
        registry.forApplet('stundenplan.php'),
        same(registry.timetableParent),
      );
      expect(registry.timetable, isA<TimetableStudentParser>());
      final student = AppletContext(
        session: session,
        database: database,
        account: context.account.copyWith(accountType: AccountType.student),
        accountSettings: context.accountSettings,
      );
      final studentRegistry = EasyParsers(
        ctx: student,
        isConnected: () async => true,
      );
      addTearDown(studentRegistry.disposeAll);
      expect(
        studentRegistry.forApplet('stundenplan.php'),
        same(studentRegistry.timetable),
      );
    },
  );

  test('Riverpod exposes the distinct parent timetable parser', () async {
    final container = ProviderContainer(
      overrides: [appletContextProvider.overrideWithValue(context)],
    );
    addTearDown(container.dispose);
    final parent = container.read(timetableParentParserProvider);
    expect(parent, isA<TimetableParentParser>());
    expect(
      (await parent.getHome() as ParentTimetableSelection).timetables,
      hasLength(2),
    );
  });
}
