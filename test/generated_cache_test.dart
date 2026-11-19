import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:liblanis/liblanis.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

class _Adapter implements HttpClientAdapter {
  int calls = 0;
  bool offline = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    calls++;
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'offline',
      );
    }
    final name = options.uri.queryParameters['p'] == null
        ? 'two_pupils_overview'
        : 'pupil_1_detail';
    return ResponseBody.fromString(
      File('test/fixtures/timetable/parents/$name.html').readAsStringSync(),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Session implements LanisSession {
  @override
  final Dio dio;
  _Session(_Adapter adapter) : dio = Dio()..httpClientAdapter = adapter;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ForbiddenSession extends Session {
  @override
  LanisSession? build() =>
      throw StateError('Session constructed during offline lookup');
}

void main() {
  late LanisDatabase database;
  late AppletContext context;
  late _Adapter adapter;
  late TimetableParentParser parent;
  setUp(() async {
    database = LanisDatabase.open();
    final id = await database.addAccount(
      schoolId: 1,
      schoolName: 'Test',
      username: 'parent',
      password: 'test',
      accountType: AccountType.parent,
    );
    adapter = _Adapter();
    context = AppletContext(
      session: _Session(adapter),
      database: database,
      account: (await database.getAccount(id))!,
      accountSettings: TypedSettings.account(database, id),
    );
    parent = TimetableParentParser(
      context,
      isConnected: () async => throw StateError('Unexpected online check'),
    );
  });
  tearDown(() {
    parent.dispose();
    database.dispose();
    LanisClient.reset();
  });

  test(
    'annotation-generated calls and detached availability share exact keys',
    () async {
      final home = await parent.cached.getHome();
      expect(home.cacheStatus, CacheStatus.network);
      final selection = home.data as ParentTimetableSelection;
      final first = selection.timetables.first;
      final second = selection.timetables.last;
      final cache = CacheService.shared(database);
      expect(
        await cache.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getHome(),
        ),
        isTrue,
      );
      expect(
        await cache.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getTimetable(first),
        ),
        isFalse,
      );
      final loaded = await parent.cached.getTimetable(first);
      expect(loaded.data.pupilId, first.pupilId);
      expect(
        await cache.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getTimetable(first),
        ),
        isTrue,
      );
      expect(
        await cache.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getTimetable(second),
        ),
        isFalse,
      );
      final calls = adapter.calls;
      final restored = await parent.cached.getTimetable(
        first,
        cachePolicy: CacheReadPolicy.cacheOnly,
      );
      expect(restored.cacheStatus, CacheStatus.cache);
      expect(restored.fetchedAt, loaded.fetchedAt);
      expect(adapter.calls, calls);
    },
  );

  test(
    'reopening a migrated parser refreshes expired in-memory content',
    () async {
      await parent.fetchData();
      final previous = parent.latestResponse!;
      final calls = adapter.calls;
      parent.addResponse(
        FetcherResponse(
          status: FetcherStatus.done,
          error: null,
          content: previous.content,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      await parent.fetchData();
      expect(adapter.calls, calls + 1);
      expect(parent.latestResponse!.expiresAt!.isAfter(DateTime.now()), isTrue);
    },
  );

  test(
    'cache service provider and typed requests require no session or connection checker',
    () async {
      final container = ProviderContainer(
        overrides: [
          lanisDatabaseProvider.overrideWithValue(database),
          sessionProvider.overrideWith(_ForbiddenSession.new),
          connectionCheckerProvider.overrideWith(
            (ref) => throw StateError('Connection checker constructed'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final cache = container.read(cacheServiceProvider);
      expect(
        await cache.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getHome(),
        ),
        isFalse,
      );
      expect(adapter.calls, 0);
    },
  );

  test(
    'migrated fetchData bypasses preflight and does not authenticate after a transport failure',
    () async {
      await parent.fetchData();
      expect(parent.latestResponse!.status, FetcherStatus.done);
      adapter.offline = true;
      await parent.fetchData(forceRefresh: true);
      expect(parent.latestResponse!.status, FetcherStatus.done);
      expect(parent.latestResponse!.contentStatus, ContentStatus.offline);
      // The fake session has no authenticate implementation: reaching it would fail.
    },
  );

  test(
    'unfiltered substitutions are cached independently of presentation settings',
    () async {
      final unfiltered = SubstitutionPlan(
        days: [
          SubstitutionDay(
            parsedDate: '17.11.2026',
            substitutions: [
              Substitution(
                tag: '17.11.2026',
                tag_en: '2026-11-17',
                stunde: '1',
                klasse: 'A',
              ),
              Substitution(
                tag: '17.11.2026',
                tag_en: '2026-11-17',
                stunde: '2',
                klasse: 'B',
              ),
            ],
          ),
        ],
      );
      final request = SubstitutionsParserCacheRequests.getHome();
      final cache = CacheService.shared(database);
      await cache.execute(
        accountId: context.accountId,
        request: request,
        load: () async => unfiltered,
      );
      final parser = SubstitutionsParser(
        context,
        isConnected: () async => false,
      );
      addTearDown(parser.dispose);
      final stored = (await cache.readCacheFor(
        accountId: context.accountId,
        request: request,
      )).data;
      context.accountSettings.setJsonMap('vertretungsplan.php/filter', {
        'Klasse': {
          'filter': ['A'],
          'strict': true,
        },
      });
      expect(
        parser.presentCachedHome(stored).allSubstitutions.single.klasse,
        'A',
      );
      context.accountSettings.setJsonMap('vertretungsplan.php/filter', {
        'Klasse': {
          'filter': ['B'],
          'strict': true,
        },
      });
      expect(
        parser.presentCachedHome(stored).allSubstitutions.single.klasse,
        'B',
      );
      expect(stored.allSubstitutions, hasLength(2));
      expect(adapter.calls, 0);
    },
  );

  test(
    'legacy timetable import preserves age and refuses filtered substitutions',
    () async {
      final before = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      database.setAppletOfflineData(
        accountId: context.accountId,
        appletId: 'stundenplan.php',
        json: File(
          'test/fixtures/timetable/parents/two_pupils_overview.html',
        ).readAsStringSync(),
        timestamp: before,
      );
      await CachedAppletHomes.migrateLegacyTimetables(database);
      expect(
        await parent.cacheService.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getHome(),
        ),
        isFalse,
      );
      final home = TimetableParentParser.parseSelectionDocument(
        parse(
          File(
            'test/fixtures/timetable/parents/two_pupils_overview.html',
          ).readAsStringSync(),
        ),
      );
      database.setAppletOfflineData(
        accountId: context.accountId,
        appletId: 'stundenplan.php',
        json: jsonEncode(home),
        timestamp: before,
      );
      database.setAppletOfflineData(
        accountId: context.accountId,
        appletId: 'vertretungsplan.php',
        json: '{"days":[]}',
        timestamp: before,
      );
      await CachedAppletHomes.migrateLegacyTimetables(database);
      final imported = await parent.cacheService.readCacheFor(
        accountId: context.accountId,
        request: TimetableParentParserCacheRequests.getHome(),
      );
      expect(imported.fetchedAt, before);
      expect(
        await parent.cacheService.isCacheAvailableFor(
          accountId: context.accountId,
          request: SubstitutionsParserCacheRequests.getHome(),
        ),
        isFalse,
      );
      parent.cacheService.clear(accountId: context.accountId);
      await CachedAppletHomes.migrateLegacyTimetables(database);
      expect(
        await parent.cacheService.isCacheAvailableFor(
          accountId: context.accountId,
          request: TimetableParentParserCacheRequests.getHome(),
        ),
        isFalse,
      );
    },
  );
}
