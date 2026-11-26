import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/easy_client.dart';
import 'package:liblanis/liblanis.dart'
    show appletContextProvider, timetableTeacherParserProvider;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

const _fixtureDir = 'test/fixtures/timetable/teachers';

String _fixture(String name) => File('$_fixtureDir/$name.html').readAsStringSync();

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String overviewHtml = _fixture('overview_all');
  String teacherHtml = _fixture('teacher_with_pauses_vplan_rumbs');
  String classHtml = _fixture('class_all');
  String roomHtml = _fixture('room_bookable_rumbs');
  String pauseHtml = _fixture('pause_all');
  String freeRoomsHtml = _fixture('free_rooms_post');
  bool denyOtherTeacher = false;
  bool failTransport = false;
  int? overrideStatusCode;
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
    if (overrideStatusCode != null) {
      return ResponseBody.fromString(
        '',
        overrideStatusCode!,
        headers: {
          if (redirectLocation != null) 'location': [redirectLocation!],
        },
      );
    }
    if (options.uri.path != '/stundenplan.php') {
      throw StateError('Unexpected path: ${options.uri}');
    }
    final action = options.uri.queryParameters['a'];
    return switch (action) {
      null || 'start' => ResponseBody.fromString(overviewHtml, 200),
      'detail' => ResponseBody.fromString(
        denyOtherTeacher && options.uri.queryParameters['t'] == 'CAP'
            ? _fixture('teacher_other_denied')
            : teacherHtml,
        200,
      ),
      'detail_klasse' => ResponseBody.fromString(classHtml, 200),
      'detail_raum' => ResponseBody.fromString(roomHtml, 200),
      'detail_pause' => ResponseBody.fromString(pauseHtml, 200),
      'freeRoom' => ResponseBody.fromString(freeRoomsHtml, 200),
      _ => throw StateError('Unexpected action: $action'),
    };
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
  group('TimetableTeacherParser offline fixture parsing', () {
    test('parses overview with all 4 categories, own button, and freeRoom link', () {
      final overview = TimetableTeacherParser.parseOverviewHtml(
        _fixture('overview_all'),
      );

      expect(overview.canViewOtherTeachers, isTrue);
      expect(overview.ownTimetableUrl, isNotNull);
      expect(overview.ownTimetableUrl!.queryParameters['a'], 'detail');
      expect(overview.freeRoomsUrl?.queryParameters['a'], 'freeRoom');

      expect(
        overview.teachers.map((t) => t.id),
        containsAll(['MUE', 'CAP', 'CAP2']),
      );
      expect(
        overview.teachers.firstWhere((t) => t.id == 'CAP2').label,
        'unpriviligiert, alessio (CAP2)',
      );
      expect(overview.classes.map((c) => c.id), containsAll(['1', '10TEST', 'G1']));
      expect(
        overview.rooms.map((r) => r.id),
        containsAll(['R101', 'R102', 'Sporthalle 1']),
      );
      expect(
        overview.breakSupervisions.map((p) => p.id),
        containsAll(['Großer Hof', 'Kantine & Aula', 'Südhof / Eingang']),
      );

      // JSON round-trip
      final restored = TeacherTimetableOverview.fromJson(
        jsonDecode(jsonEncode(overview.toJson())) as Map<String, dynamic>,
      );
      expect(restored.teachers, equals(overview.teachers));
      expect(restored.classes, equals(overview.classes));
      expect(restored.rooms, equals(overview.rooms));
      expect(restored.breakSupervisions, equals(overview.breakSupervisions));
      expect(restored.canViewOtherTeachers, isTrue);
    });

    test('parses overview when teacherCanSee=own (Lehrkräfte omitted, #collapseN shifted)', () {
      final overview = TimetableTeacherParser.parseOverviewHtml(
        _fixture('overview_own_only'),
      );

      expect(overview.canViewOtherTeachers, isFalse);
      expect(overview.teachers, isEmpty);
      expect(overview.classes.map((c) => c.id), containsAll(['1', '10TEST', 'G1']));
      expect(
        overview.breakSupervisions.map((p) => p.id),
        containsAll(['Großer Hof', 'Kantine & Aula', 'Südhof / Eingang']),
      );
      expect(overview.freeRoomsUrl?.queryParameters['a'], 'freeRoom');
    });

    test('parses teacher plan with KursnamenEinblenden, VonBisAusblenden, hinweis, badges, multi-class', () {
      final plan = TimetableTeacherParser.parsePlanHtml(
        _fixture('teacher_own_rich'),
        category: TeacherTimetableCategory.teacher,
        targetId: 'CAP2',
      );

      expect(plan.category, TeacherTimetableCategory.teacher);
      expect(plan.targetId, 'CAP2');
      expect(plan.title, 'unpriviligiert, alessio (CAP2)');
      expect(plan.timesHidden, isTrue);
      expect(plan.planDate, '2026-11-23');
      expect(plan.validFromLabel, 'ab 23.11.2026');
      expect(plan.noticeHtml, contains('Bitte Raumänderungen beachten!'));
      expect(plan.weekdayIndices, [0, 1, 2, 3, 4]);
      expect(plan.availableTargets.map((t) => t.id), containsAll(['MUE', 'CAP', 'CAP2']));

      // Tuesday: Chemie in Ch-Labor, badge B, course G1-Ch, duration 2
      final tuesday = plan.days[1];
      final chemie = tuesday.firstWhere((e) => e.subject == 'Chemie');
      expect(chemie.kind, TeacherTimetableEntryKind.regular);
      expect(chemie.room, 'Ch-Labor');
      expect(chemie.classes, ['G1']);
      expect(chemie.badge, 'B');
      expect(chemie.course, 'G1-Ch');
      expect(chemie.duration, 2);

      // Thursday: Sport with multiple classes ['1', '2']
      final thursday = plan.days[3];
      final sport = thursday.firstWhere((e) => e.subject == 'Sport');
      expect(sport.classes, ['1', '2']);
      expect(sport.room, 'Sporthalle 1');
      expect(sport.course, '1_2-Sp');

      // Friday: Kunst with U-week badge
      final friday = plan.days[4];
      final kunst = friday.firstWhere((e) => e.subject == 'Kunst');
      expect(kunst.badge, 'U');
      expect(kunst.room, 'Ku-Raum');
    });

    test('throws UnauthorizedException when teacherCanSee=own denies another teacher plan', () {
      expect(
        () => TimetableTeacherParser.parsePlanHtml(
          _fixture('teacher_other_denied'),
          category: TeacherTimetableCategory.teacher,
          targetId: 'CAP',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('parses teacher plan with Pausenaufsichten, embedded substitutions, and Räume & Medien booking', () {
      final plan = TimetableTeacherParser.parsePlanHtml(
        _fixture('teacher_with_pauses_vplan_rumbs'),
        category: TeacherTimetableCategory.teacher,
        targetId: 'CAP2',
      );

      expect(plan.weekdayIndices, [0, 1, 2, 3, 4]);
      expect(plan.hasBreakSupervisions, isTrue);
      expect(plan.hasEmbeddedSubstitutions, isTrue);
      expect(plan.hasRoomBookings, isTrue);

      // Monday hour 3: Pausenaufsicht "Großer Hof" sibling of Deutsch
      final monPauses = plan.days[0].where((e) => e.isBreakSupervision).toList();
      expect(monPauses, hasLength(1));
      expect(monPauses.single.supervisionLocation, 'Großer Hof');
      expect(monPauses.single.teachers, ['CAP2']);
      expect(monPauses.single.hourIndex, 3);

      // Wednesday hour 1: Pausenaufsicht "Südhof"
      final wedPauses = plan.days[2].where((e) => e.isBreakSupervision).toList();
      expect(wedPauses.map((e) => e.supervisionLocation), contains('Südhof'));

      // Thursday: embedded Vertretungsplan added (Mathe in R102) + changed (Sport, Deutsch)
      final thuSubs = plan.days[3].where((e) => e.isEmbeddedSubstitution).toList();
      final added = thuSubs.where(
        (e) => e.kind == TeacherTimetableEntryKind.substitutionAdded,
      );
      final changed = thuSubs.where(
        (e) => e.kind == TeacherTimetableEntryKind.substitutionChanged,
      );
      expect(added, isNotEmpty);
      expect(added.first.subject, 'Mathe');
      expect(added.first.room, 'R102');
      expect(added.first.classes, ['1']);
      expect(added.first.embeddedDate, '26.11.2026');
      expect(added.first.substitutionCreateUrl, isNotNull);
      expect(added.first.externalUrl?.path, '/vertretungsplan.php');
      expect(changed, isNotEmpty);
      expect(changed.first.embeddedDate, '26.11.2026');

      // Friday: embedded Räume & Medien booking for "10er Slot BBB" on 27.11.2026
      final friBookings = plan.days[4].where((e) => e.isRoomBooking).toList();
      expect(friBookings, hasLength(1));
      expect(friBookings.single.room, '10er Slot BBB');
      expect(friBookings.single.embeddedDate, '27.11.2026');
      expect(friBookings.single.externalUrl?.path, '/raeumeundmedien.php');

      // JSON round-trip preserves all entry kinds & fields
      final restored = TeacherTimetablePlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
      );
      expect(restored.hasBreakSupervisions, isTrue);
      expect(restored.hasEmbeddedSubstitutions, isTrue);
      expect(restored.hasRoomBookings, isTrue);
      expect(restored.days[4].single.room, '10er Slot BBB');
    });

    test('parses class plan with teacher links (all mode) and plain text teachers (own mode)', () {
      final allPlan = TimetableTeacherParser.parsePlanHtml(
        _fixture('class_all'),
        category: TeacherTimetableCategory.schoolClass,
        targetId: '1',
      );
      expect(allPlan.title, '1');
      final monAll = allPlan.days[0];
      final matheAll = monAll.firstWhere((e) => e.subject == 'Mathe');
      expect(matheAll.room, 'R101');
      expect(matheAll.teachers, ['CAP']);
      expect(matheAll.classes, ['1']);

      // Thursday co-teaching stacked cells (CAP & CAP2)
      final thuSport = allPlan.days[3].where((e) => e.subject == 'Sport').toList();
      expect(thuSport, hasLength(2));
      expect(thuSport.expand((e) => e.teachers), containsAll(['CAP', 'CAP2']));

      // Under teacherCanSee=own, teacher codes are plain text inside <small>
      final ownPlan = TimetableTeacherParser.parsePlanHtml(
        _fixture('class_own_mode'),
        category: TeacherTimetableCategory.schoolClass,
        targetId: '1',
      );
      final matheOwn = ownPlan.days[0].firstWhere((e) => e.subject == 'Mathe');
      expect(matheOwn.room, 'R101');
      expect(matheOwn.teachers, ['CAP']);
    });

    test('parses room plan with teacher contacts, embedded substitutions, and Räume & Medien button', () {
      final contactsPlan = TimetableTeacherParser.parsePlanHtml(
        _fixture('room_with_contacts'),
        category: TeacherTimetableCategory.room,
        targetId: 'Sporthalle 1',
      );
      expect(contactsPlan.roomTeachers, ['CAP', 'CAP2']);
      expect(contactsPlan.roomTeacherContacts, hasLength(1));
      expect(contactsPlan.roomTeacherContacts.single.teacherCode, 'CAP');
      expect(contactsPlan.roomTeacherContacts.single.email, 'contact@alessioc42.dev');
      final thuSport = contactsPlan.days[3].where((e) => e.subject == 'Sport').toList();
      expect(thuSport, hasLength(2));
      expect(thuSport.first.classes, ['1', '2']);

      final vplanRoom = TimetableTeacherParser.parsePlanHtml(
        _fixture('room_with_vplan'),
        category: TeacherTimetableCategory.room,
        targetId: 'R102',
      );
      expect(vplanRoom.hasEmbeddedSubstitutions, isTrue);
      final thuVplan = vplanRoom.days[3]
          .where((e) => e.kind == TeacherTimetableEntryKind.substitutionAdded)
          .toList();
      expect(thuVplan, hasLength(2));
      expect(thuVplan.first.subject, 'Mathe');
      expect(thuVplan.first.teachers, ['CAP2']);
      expect(thuVplan.first.classes, ['1']);

      final rumbsRoom = TimetableTeacherParser.parsePlanHtml(
        _fixture('room_bookable_rumbs'),
        category: TeacherTimetableCategory.room,
        targetId: '10er Slot BBB',
      );
      expect(rumbsRoom.bookableInRumbs, isTrue);
      expect(rumbsRoom.rumbsUrl?.path, '/raeumeundmedien.php');
      // Sparse 4-day Mon-Thu table
      expect(rumbsRoom.weekdayIndices, [0, 1, 2, 3]);
    });

    test('parses break supervision (Pausenaufsichten) plan in both all and own modes', () {
      for (final name in ['pause_all', 'pause_own_mode']) {
        final plan = TimetableTeacherParser.parsePlanHtml(
          _fixture(name),
          category: TeacherTimetableCategory.breakSupervision,
          targetId: 'Großer Hof',
        );
        expect(plan.title, 'Großer Hof');
        expect(plan.hasBreakSupervisions, isTrue);

        // Monday hour 3: CAP and CAP2
        final mon = plan.days[0];
        expect(mon, hasLength(2));
        expect(mon.every((e) => e.isBreakSupervision), isTrue);
        expect(mon.map((e) => e.teachers.single), containsAll(['CAP', 'CAP2']));
        expect(mon.every((e) => e.supervisionLocation == 'Großer Hof'), isTrue);
        expect(mon.first.hourIndex, 3);

        // Tuesday hour 3: CAP2
        final tue = plan.days[1];
        expect(tue, hasLength(1));
        expect(tue.single.teachers, ['CAP2']);
      }
    });

    test('parses free rooms POST result', () {
      final result = TimetableTeacherParser.parseFreeRoomsHtml(
        _fixture('free_rooms_post'),
      );
      expect(result.weekday, 1);
      expect(result.selectedHours, [1, 2]);
      expect(result.availableHours, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(result.rooms, isNotEmpty);
      expect(result.rooms.first.category, TeacherTimetableCategory.room);
      expect(result.rooms.first.id, 'RM24-0');

      final restored = TeacherFreeRoomsResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>,
      );
      expect(restored.rooms.length, result.rooms.length);
      expect(restored.selectedHours, [1, 2]);
    });
  });

  group('TimetableTeacherParser HTTP, caching, EasyParsers & Riverpod integration', () {
    late LanisDatabase database;
    late _Adapter adapter;
    late _Session session;
    late AppletContext context;
    late TimetableTeacherParser parser;
    var online = true;

    setUp(() async {
      online = true;
      adapter = _Adapter();
      LanisClient.configure(httpAdapter: adapter);
      database = LanisDatabase.open();
      final id = await database.addAccount(
        schoolId: 1,
        schoolName: 'Test',
        username: 'teacher',
        password: 'test',
        accountType: AccountType.teacher,
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
        accountSettings: TypedSettings.account(database, account.localId),
      );
      parser = TimetableTeacherParser(context, isConnected: () async => online);
    });

    tearDown(() async {
      parser.dispose();
      database.dispose();
    });

    test('fetches overview, all 4 plan types, free rooms, and caches home offline', () async {
      final overview = await parser.getHome();
      expect(overview.teachers, isNotEmpty);

      final teacherPlan = await parser.getTeacherTimetable('CAP2');
      expect(teacherPlan.hasBreakSupervisions, isTrue);
      expect(teacherPlan.hasEmbeddedSubstitutions, isTrue);
      expect(teacherPlan.hasRoomBookings, isTrue);

      final classPlan = await parser.getClassTimetable('1');
      expect(classPlan.days[0].any((e) => e.subject == 'Mathe'), isTrue);

      final roomPlan = await parser.getRoomTimetable('10er Slot BBB');
      expect(roomPlan.bookableInRumbs, isTrue);

      final pausePlan = await parser.getBreakSupervisionTimetable('Großer Hof');
      expect(pausePlan.days[0], hasLength(2));

      final free = await parser.getFreeRooms(weekday: 1, hours: [1, 2]);
      expect(free.selectedHours, [1, 2]);
      expect(free.rooms, isNotEmpty);
      expect(adapter.requests.last.method, 'POST');
      expect(adapter.requests.last.data, 'tag=1&stunde%5B%5D=1&stunde%5B%5D=2');

      // Offline cache read via loadCachedHome
      await parser.loadCachedHome();
      online = false;
      adapter.failTransport = true;
      final cached = await parser.loadCachedHome(policy: CacheReadPolicy.cacheOnly);
      expect(cached.cacheStatus, CacheStatus.cache);
      expect(cached.data.teachers.length, overview.teachers.length);
    });

    test('EasyParsers routes stundenplan.php for AccountType.teacher to TimetableTeacherParser', () {
      final parsers = EasyParsers(ctx: context, isConnected: () async => true);
      expect(parsers.forApplet('stundenplan.php'), isA<TimetableTeacherParser>());
      expect(
        Applets.timetable.supportedAccountTypes,
        contains(AccountType.teacher),
      );
      parsers.disposeAll();
    });

    test('Riverpod timetableTeacherParserProvider returns TimetableTeacherParser', () {
      final container = ProviderContainer(
        overrides: [appletContextProvider.overrideWithValue(context)],
      );
      addTearDown(container.dispose);
      expect(
        container.read(timetableTeacherParserProvider),
        isA<TimetableTeacherParser>(),
      );
    });

    test('normalizes reference URLs, validates portal URLs, and caches getTimetable', () async {
      final overview = await parser.getHome();
      final roomRef = overview.rooms.first;
      expect(roomRef.url.isAbsolute, isTrue);
      expect(roomRef.url.host, 'start.schulportal.hessen.de');
      expect(overview.ownTimetableUrl?.isAbsolute, isTrue);
      expect(overview.freeRoomsUrl?.isAbsolute, isTrue);

      final cachedPlan = await parser.cached.getTimetable(roomRef);
      expect(cachedPlan.data.bookableInRumbs, isTrue);
      expect(cachedPlan.data, equals(await parser.getTimetable(roomRef)));

      // Reject wrong host, pdf=1, and mismatched action
      await expectLater(
        () => parser.getTimetable(
          TeacherTimetableReference(
            category: TeacherTimetableCategory.room,
            id: 'R102',
            label: 'R102',
            url: Uri.parse('https://evil.example/stundenplan.php?a=detail_raum&r=R102'),
          ),
        ),
        throwsA(isA<ConfigurationException>()),
      );
      await expectLater(
        () => parser.getTimetable(
          TeacherTimetableReference(
            category: TeacherTimetableCategory.room,
            id: 'R102',
            label: 'R102',
            url: Uri.parse('https://start.schulportal.hessen.de/stundenplan.php?a=detail_raum&r=R102&pdf=1'),
          ),
        ),
        throwsA(isA<ConfigurationException>()),
      );
      await expectLater(
        () => parser.getTimetable(
          TeacherTimetableReference(
            category: TeacherTimetableCategory.room,
            id: 'R102',
            label: 'R102',
            url: Uri.parse('https://start.schulportal.hessen.de/stundenplan.php?a=detail_klasse&k=1'),
          ),
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('handles getOwnTimetable, GET getFreeRooms, weekday validation, HTTP 302, and errors', () async {
      final own = await parser.getOwnTimetable();
      expect(own.targetId, isNotEmpty);

      final freeGet = await parser.getFreeRooms();
      expect(adapter.requests.last.method, 'GET');
      expect(freeGet.rooms.first.url.isAbsolute, isTrue);

      await expectLater(
        () => parser.getFreeRooms(weekday: 0, hours: [1]),
        throwsA(isA<RangeError>()),
      );

      // Denied other teacher -> UnauthorizedException
      adapter.denyOtherTeacher = true;
      await expectLater(
        () => parser.getTeacherTimetable('CAP'),
        throwsA(isA<UnauthorizedException>()),
      );
      adapter.denyOtherTeacher = false;

      // HTTP 302 redirect to login -> UnauthorizedException (not empty cached plan)
      adapter.overrideStatusCode = 302;
      adapter.redirectLocation = '/index.php';
      await expectLater(() => parser.getHome(), throwsA(isA<UnauthorizedException>()));
      await expectLater(() => parser.getRoomTimetable('R102'), throwsA(isA<UnauthorizedException>()));
      await expectLater(() => parser.getFreeRooms(), throwsA(isA<UnauthorizedException>()));
      adapter.overrideStatusCode = null;
      adapter.redirectLocation = null;

      // Transport failure -> NetworkException
      adapter.failTransport = true;
      await expectLater(() => parser.getHome(), throwsA(isA<NetworkException>()));
      await expectLater(() => parser.getRoomTimetable('R102'), throwsA(isA<NetworkException>()));
      await expectLater(() => parser.getFreeRooms(), throwsA(isA<NetworkException>()));
    });

    test('rejects unexpected HTML without .plan or select#tag, keeps non-teacher parentheses, strips badges, clamps rowspan', () {
      expect(
        () => TimetableTeacherParser.parsePlanHtml(
          '<div id="content"><h1>Login</h1></div>',
          category: TeacherTimetableCategory.room,
        ),
        throwsA(isA<UnknownException>()),
      );
      expect(
        () => TimetableTeacherParser.parseFreeRoomsHtml(
          '<div id="content"><h1>Unexpected</h1></div>',
        ),
        throwsA(isA<UnknownException>()),
      );

      // Non-teacher title with parentheses retains full title as targetId
      final roomWithParens = TimetableTeacherParser.parsePlanHtml(
        '<div id="content"><h1>Raum 101 (Musik) <small>Stundenplan</small></h1><div class="plan"></div></div>',
        category: TeacherTimetableCategory.room,
      );
      expect(roomWithParens.targetId, 'Raum 101 (Musik)');

      // Badge inside <small> is stripped from teacher name, and rowspan="0" is clamped to 1
      final badgeAndRowspan = TimetableTeacherParser.parsePlanHtml(
        '''
        <div id="content">
          <h1>10a <small>Stundenplan</small></h1>
          <div class="plan">
            <table>
              <thead><tr><th>Stunde</th><th>Montag</th></tr></thead>
              <tbody>
                <tr><td></td><td></td></tr>
                <tr>
                  <td><b>1</b><br><small>08:00 - 08:45</small></td>
                  <td rowspan="0">
                    <div class="stunde">
                      <b>Mathe</b><br>
                      <small>CAP <span class="badge">B</span></small>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        ''',
        category: TeacherTimetableCategory.schoolClass,
        targetId: '10a',
      );
      final entry = badgeAndRowspan.days[0].single;
      expect(entry.teachers, ['CAP']);
      expect(entry.badge, 'B');
      expect(entry.duration, 1);
    });

    test('handles invalid UTF-8/Latin-1 percent-encoding and malformed hrefs without throwing FormatException', () {
      final overview = TimetableTeacherParser.parseOverviewHtml('''
        <div id="content">
          <a class="btn" href="stundenplan.php?a=detail&x=%E0%A4%A">Own</a>
          <div id="accordion">
            <div class="panel">
              <div class="panel-title">Lehrkräfte</div>
              <a class="list-group-item" href="stundenplan.php?a=detail&t=M%FCller">Müller</a>
            </div>
          </div>
        </div>
      ''');
      expect(overview.ownTimetableUrl, isNotNull);
      expect(overview.teachers, hasLength(1));

      final plan = TimetableTeacherParser.parsePlanHtml(
        '''
        <div id="content">
          <h1>R</h1>
          <a href="http://[::1/raeumeundmedien.php">R</a>
          <select class="select2-class"><option value="%C0%AF" selected>X</option></select>
          <div class="plan">
            <table>
              <thead><tr><th>Stunde</th><th>Montag</th></tr></thead>
              <tbody>
                <tr><td></td><td></td></tr>
                <tr>
                  <td><b>1</b></td>
                  <td>
                    <div class="stunde">
                      <b>Mathe</b>
                      <a href="http://[::1/vertretungsplan.php">V</a>
                      <a href="http://[::1/meinunterricht.php?a=vertretung">C</a>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        ''',
        category: TeacherTimetableCategory.room,
      );
      expect(plan.rumbsUrl, isNull);
      expect(plan.days[0].single.externalUrl, isNull);
      expect(plan.days[0].single.substitutionCreateUrl, isNull);

      final free = TimetableTeacherParser.parseFreeRoomsHtml('''
        <div id="content">
          <select id="tag"><option value="1" selected>Mo</option></select>
          <ul><li><a href="stundenplan.php?a=detail_raum&r=R%FC">R</a></li></ul>
        </div>
      ''');
      expect(free.rooms, hasLength(1));
    });
  });
}
