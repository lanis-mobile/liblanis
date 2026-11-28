import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';

final intCodec = CacheCodec<int>(
  id: 'test.int',
  encode: (v) => v,
  decode: (v) => v as int,
);
final nullableIntCodec = CacheCodec<int?>(
  id: 'test.nullableInt',
  encode: (v) => v,
  decode: (v) => v as int?,
);
CacheRequest<int> request({
  String operation = 'test.read',
  Object? arguments = const {},
  int version = 1,
  Duration? age,
  Duration? appletLimit,
}) => CacheRequest(
  operation: operation,
  arguments: arguments,
  codec: intCodec,
  version: version,
  maxAge: age,
  appletLimit: appletLimit,
);

void main() {
  late LanisDatabase db;
  late CacheService cache;
  late int account;
  late int otherAccount;
  late DateTime now;
  final start = DateTime.utc(2026, 11, 17, 10);
  setUp(() async {
    db = LanisDatabase.open();
    account = await db.addAccount(
      schoolId: 1,
      schoolName: 'Test',
      username: 'one',
      password: 'test',
    );
    otherAccount = await db.addAccount(
      schoolId: 1,
      schoolName: 'Test',
      username: 'two',
      password: 'test',
    );
    now = start;
    cache = CacheService(db, clock: () => now);
  });
  tearDown(() => db.dispose());

  test(
    'canonical arguments, accounts, versions and operations form independent identities',
    () async {
      final a = request(
        arguments: {
          'z': [1, 2],
          'a': {'y': true, 'x': null},
        },
      );
      final same = request(
        arguments: {
          'a': {'x': null, 'y': true},
          'z': [1, 2],
        },
      );
      expect(a.argumentHash, same.argumentHash);
      await cache.execute(accountId: account, request: a, load: () async => 10);
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: same),
        isTrue,
      );
      for (final other in [
        request(
          arguments: {
            'z': [2, 1],
            'a': {'y': true, 'x': null},
          },
        ),
        request(operation: 'another'),
        request(version: 2),
      ]) {
        expect(
          await cache.isCacheAvailableFor(accountId: account, request: other),
          isFalse,
        );
      }
      expect(
        await cache.isCacheAvailableFor(accountId: otherAccount, request: a),
        isFalse,
      );
      await expectLater(
        cache.readCacheFor(accountId: otherAccount, request: a),
        throwsA(isA<CacheUnavailableException>()),
      );
    },
  );

  test('arguments are snapshotted and unsupported objects fail explicitly', () {
    final args = {'x': 1};
    final r = request(arguments: args);
    args['x'] = 2;
    expect(r.argumentsJson, '{"x":1}');
    expect(() => request(arguments: DateTime.now()), throwsArgumentError);
    expect(() => request(arguments: double.nan), throwsArgumentError);
    expect(
      () => request(arguments: {1: 'not a JSON key'}),
      throwsArgumentError,
    );
  });

  test(
    'network and cache results preserve original time but have current response time',
    () async {
      final r = request(age: const Duration(hours: 1));
      final online = await cache.execute(
        accountId: account,
        request: r,
        load: () async => 7,
      );
      expect(online.cacheStatus, CacheStatus.network);
      expect(online.fetchedAt, start);
      now = now.add(const Duration(minutes: 20));
      final offline = await cache.readCacheFor(accountId: account, request: r);
      expect(offline.data, 7);
      expect(offline.cacheStatus, CacheStatus.cache);
      expect(offline.fetchedAt, start);
      expect(offline.responseAt, now);
      expect(offline.expiresAt, start.add(const Duration(hours: 1)));
    },
  );

  test(
    'cache-only never calls the provided loader, including on a miss',
    () async {
      var calls = 0;
      final r = request();
      await expectLater(
        cache.execute(
          accountId: account,
          request: r,
          policy: CacheReadPolicy.cacheOnly,
          load: () async {
            calls++;
            return 1;
          },
        ),
        throwsA(isA<CacheUnavailableException>()),
      );
      expect(calls, 0);
      await cache.execute(accountId: account, request: r, load: () async => 9);
      final hit = await cache.execute(
        accountId: account,
        request: r,
        policy: CacheReadPolicy.cacheOnly,
        load: () async {
          calls++;
          return 2;
        },
      );
      expect(hit.data, 9);
      expect(calls, 0);
    },
  );

  test(
    'applet cadence is independent from seven-day offline retention',
    () async {
      final r = request(
        age: const Duration(days: 20),
        appletLimit: const Duration(minutes: 10),
      );
      await cache.execute(accountId: account, request: r, load: () async => 1);
      now = start.add(const Duration(hours: 2));
      expect(r.refreshInterval, const Duration(minutes: 10));
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: r),
        isTrue,
      );
      now = start.add(const Duration(days: 7));
      final state = await cache.inspectCacheFor(accountId: account, request: r);
      expect(state.state, CacheEntryState.expired);
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: r),
        isFalse,
      );
      await expectLater(
        cache.readCacheFor(accountId: account, request: r),
        throwsA(isA<CacheUnavailableException>()),
      );
      final seven = request(age: const Duration(days: 30));
      expect(seven.maxAge, const Duration(days: 7));
    },
  );

  test(
    'native Android and iOS client errors fall back without swallowing parsing or cancellation',
    () async {
      final r = request();
      await cache.execute(accountId: account, request: r, load: () async => 9);
      final native = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.unknown,
        error: http.ClientException('net::ERR_INTERNET_DISCONNECTED'),
      );
      expect(
        (await cache.execute(
          accountId: account,
          request: r,
          load: () async => throw native,
        )).cacheStatus,
        CacheStatus.cache,
      );
      expect(
        CacheService.isTransportFailure(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            error: const FormatException('bad HTML'),
          ),
        ),
        isFalse,
      );
      expect(
        CacheService.isTransportFailure(http.RequestAbortedException()),
        isFalse,
      );
      for (final status in [401, 403, 500]) {
        final options = RequestOptions(path: '/');
        expect(
          CacheService.isTransportFailure(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: status),
            ),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'tightening policy shortens old entries and relaxed policy cannot revive expiry',
    () async {
      final original = request(age: const Duration(hours: 1));
      await cache.execute(
        accountId: account,
        request: original,
        load: () async => 1,
      );
      now = start.add(const Duration(minutes: 30));
      expect(
        (await cache.inspectCacheFor(
          accountId: account,
          request: request(age: const Duration(minutes: 10)),
        )).state,
        CacheEntryState.expired,
      );
      now = start.add(const Duration(hours: 2));
      expect(
        (await cache.inspectCacheFor(
          accountId: account,
          request: request(age: const Duration(days: 1)),
        )).state,
        CacheEntryState.expired,
      );
    },
  );

  test('corrupt, incompatible and null payloads are not available', () async {
    final r = request();
    void write(String value, {String? codecId}) => db.writeCacheRecord(
      CacheRecord(
        key: r.keyFor(account),
        codecId: codecId ?? r.codec.id,
        json: value,
        fetchedAt: start,
        expiresAt: start.add(const Duration(hours: 1)),
      ),
      db.cacheGeneration(account),
    );
    write('invalid JSON');
    expect(
      (await cache.inspectCacheFor(accountId: account, request: r)).state,
      CacheEntryState.corrupt,
    );
    write('"wrong type"');
    expect(
      (await cache.inspectCacheFor(accountId: account, request: r)).state,
      CacheEntryState.corrupt,
    );
    write('null');
    expect(
      (await cache.inspectCacheFor(accountId: account, request: r)).state,
      CacheEntryState.corrupt,
    );
    write('1', codecId: 'older.codec');
    expect(
      (await cache.inspectCacheFor(accountId: account, request: r)).state,
      CacheEntryState.incompatible,
    );
    write('1');
    expect(
      (await cache.inspectCacheFor(
        accountId: account,
        request: request(version: 2),
      )).state,
      CacheEntryState.incompatible,
    );
  });

  test(
    'successful null is returned without caching and replaces the exact old entry',
    () async {
      final r = CacheRequest<int?>(
        operation: 'nullable',
        codec: nullableIntCodec,
        arguments: {},
      );
      await cache.execute(accountId: account, request: r, load: () async => 2);
      await cache.execute(
        accountId: otherAccount,
        request: r,
        load: () async => 3,
      );
      final result = await cache.execute(
        accountId: account,
        request: r,
        load: () async => null,
      );
      expect(result.data, isNull);
      expect(result.cacheStatus, CacheStatus.network);
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: r),
        isFalse,
      );
      expect(
        await cache.isCacheAvailableFor(accountId: otherAccount, request: r),
        isTrue,
      );
    },
  );

  test('empty non-null domain results remain available', () async {
    final codec = CacheCodec<List<int>>(
      id: 'list',
      encode: (v) => v,
      decode: (v) => (v as List).cast<int>(),
    );
    final r = CacheRequest(operation: 'empty', arguments: {}, codec: codec);
    await cache.execute(
      accountId: account,
      request: r,
      load: () async => <int>[],
    );
    expect(
      await cache.isCacheAvailableFor(accountId: account, request: r),
      isTrue,
    );
    expect(
      (await cache.readCacheFor(accountId: account, request: r)).data,
      isEmpty,
    );
  });

  test('only structured transport failures trigger fallback', () async {
    final r = request();
    await cache.execute(accountId: account, request: r, load: () async => 5);
    for (final error in <Object>[
      NoConnectionException(),
      const SocketException('offline'),
      DioException(
        requestOptions: RequestOptions(path: 'test'),
        type: DioExceptionType.connectionError,
      ),
      NetworkException.fromError(
        const SocketException('offline'),
        StackTrace.current,
      ),
    ]) {
      final result = await cache.execute(
        accountId: account,
        request: r,
        load: () async => throw error,
      );
      expect(result.data, 5);
      expect(result.cacheStatus, CacheStatus.cache);
    }
    for (final error in <Object>[
      WrongCredentialsException(),
      UnknownException('parser failure'),
      const FormatException('markup'),
      NetworkException('unstructured legacy failure'),
      DioException(
        requestOptions: RequestOptions(path: 'test'),
        type: DioExceptionType.badResponse,
      ),
    ]) {
      await expectLater(
        cache.execute(
          accountId: account,
          request: r,
          load: () async => throw error,
        ),
        throwsA(same(error)),
      );
    }
  });

  test(
    'failed request without usable fallback retains the original error and stack',
    () async {
      final error = NoConnectionException();
      final origin = StackTrace.fromString('original transport origin');
      try {
        await cache.execute(
          accountId: account,
          request: request(),
          load: () async => Error.throwWithStackTrace(error, origin),
        );
        fail('Expected failure');
      } catch (e, stack) {
        expect(e, same(error));
        expect(stack.toString(), contains('original transport origin'));
      }
    },
  );

  test('identical concurrent calls share execution', () async {
    final pending = Completer<int>();
    var calls = 0;
    final r = request();
    Future<int> load() {
      calls++;
      return pending.future;
    }

    final first = cache.execute(accountId: account, request: r, load: load);
    final second = cache.execute(accountId: account, request: r, load: load);
    pending.complete(8);
    expect((await first).data, 8);
    expect((await second).data, 8);
    expect(calls, 1);
  });

  test('mixed policies do not share fallback or network execution', () async {
    final r = request();
    await cache.execute(accountId: account, request: r, load: () async => 4);
    final first = Completer<int>();
    final second = Completer<int>();
    final networkFirst = cache.execute(
      accountId: account,
      request: r,
      load: () => first.future,
    );
    final networkOnly = cache.execute(
      accountId: account,
      request: r,
      load: () => second.future,
      policy: CacheReadPolicy.networkOnly,
    );
    final expectFailure = expectLater(
      networkOnly,
      throwsA(isA<NoConnectionException>()),
    );
    final onlyCache = await cache.execute(
      accountId: account,
      request: r,
      load: () async => throw StateError('Must not execute'),
      policy: CacheReadPolicy.cacheOnly,
    );
    expect(onlyCache.data, 4);
    first.completeError(NoConnectionException());
    second.completeError(NoConnectionException());
    expect((await networkFirst).cacheStatus, CacheStatus.cache);
    await expectFailure;
  });

  test(
    'nested fallback preserves oldest time and earliest dependency deadline',
    () async {
      final child = request(
        operation: 'child',
        age: const Duration(minutes: 50),
      );
      final home = request(operation: 'home', age: const Duration(hours: 1));
      await cache.execute(
        accountId: account,
        request: child,
        load: () async => 10,
      );
      now = start.add(const Duration(minutes: 40));
      final result = await cache.execute(
        accountId: account,
        request: home,
        load: () async {
          final inner = await cache.execute(
            accountId: account,
            request: child,
            load: () async => throw NoConnectionException(),
          );
          return inner.data + 1;
        },
      );
      expect(result.cacheStatus, CacheStatus.cache);
      expect(result.fetchedAt, start);
      expect(result.responseAt, now);
      expect(result.expiresAt, start.add(const Duration(minutes: 50)));
      final stored = await cache.readCacheFor(
        accountId: account,
        request: home,
      );
      expect(stored.data, 11);
      expect(stored.expiresAt, result.expiresAt);
      now = start.add(const Duration(minutes: 50));
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: home),
        isFalse,
      );
    },
  );

  test(
    'a dependency expiring during composition cannot be refreshed by the outer write',
    () async {
      final child = request(
        operation: 'child',
        age: const Duration(minutes: 1),
      );
      final home = request(operation: 'home');
      await cache.execute(
        accountId: account,
        request: child,
        load: () async => 1,
      );
      await expectLater(
        cache.execute(
          accountId: account,
          request: home,
          load: () async {
            final inner = await cache.readCacheFor(
              accountId: account,
              request: child,
            );
            now = now.add(const Duration(minutes: 2));
            return inner.data;
          },
        ),
        throwsA(isA<CacheUnavailableException>()),
      );
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: home),
        isFalse,
      );
    },
  );

  test('network-only policy propagates into nested reads', () async {
    final child = request(operation: 'child');
    await cache.execute(
      accountId: account,
      request: child,
      load: () async => 10,
    );
    await expectLater(
      cache.execute(
        accountId: account,
        request: request(operation: 'outer'),
        policy: CacheReadPolicy.networkOnly,
        load: () async => (await cache.execute(
          accountId: account,
          request: child,
          load: () async => throw NoConnectionException(),
        )).data,
      ),
      throwsA(isA<NoConnectionException>()),
    );
    await expectLater(
      cache.execute(
        accountId: account,
        request: request(operation: 'direct'),
        policy: CacheReadPolicy.networkOnly,
        load: () async =>
            (await cache.readCacheFor(accountId: account, request: child)).data,
      ),
      throwsA(isA<ConfigurationException>()),
    );
  });

  test('recursive cache operations fail instead of deadlocking', () async {
    final r = request();
    await expectLater(
      cache.execute(
        accountId: account,
        request: r,
        load: () async => (await cache.execute(
          accountId: account,
          request: r,
          load: () async => 1,
        )).data,
      ),
      throwsA(isA<ConfigurationException>()),
    );
  });

  test(
    'clearing during a request prevents writes without failing its original caller',
    () async {
      final r = request();
      final pending = Completer<int>();
      final old = cache.execute(
        accountId: account,
        request: r,
        load: () => pending.future,
      );
      cache.clear(accountId: account);
      pending.complete(12);
      expect((await old).data, 12);
      expect(
        await cache.isCacheAvailableFor(accountId: account, request: r),
        isFalse,
      );
    },
  );

  test(
    'post-clear calls do not join old work and a late null cannot delete the new value',
    () async {
      final r = CacheRequest<int?>(
        operation: 'nullable',
        arguments: {},
        codec: nullableIntCodec,
      );
      final pending = Completer<int?>();
      final old = cache.execute(
        accountId: account,
        request: r,
        load: () => pending.future,
      );
      cache.clear(accountId: account);
      await cache.execute(accountId: account, request: r, load: () async => 20);
      pending.complete(null);
      await old;
      expect(
        (await cache.readCacheFor(accountId: account, request: r)).data,
        20,
      );
    },
  );

  test(
    'account clearing and deletion isolate data and clear legacy snapshots',
    () async {
      final r = request();
      await cache.execute(accountId: account, request: r, load: () async => 1);
      await cache.execute(
        accountId: otherAccount,
        request: r,
        load: () async => 2,
      );
      db.setAppletOfflineData(
        accountId: account,
        appletId: 'stundenplan.php',
        json: '{}',
      );
      cache.clear(accountId: account);
      expect(db.listAppletOfflineData(), isEmpty);
      expect(
        await cache.isCacheAvailableFor(accountId: otherAccount, request: r),
        isTrue,
      );
      await db.deleteAccount(otherAccount);
      expect(db.structuredCacheUsage().entries, 0);
    },
  );

  test(
    'malformed persistent cache metadata is unavailable without hiding other entries',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'liblanis-corrupt-cache-',
      );
      final path = '${directory.path}/cache.sqlite';
      final persisted = LanisDatabase.open(
        path: path,
        secretStore: MemorySecretStore(),
      );
      final local = await persisted.addAccount(
        schoolId: 1,
        schoolName: 'Test',
        username: 'test',
        password: 'test',
      );
      final service = CacheService(persisted, clock: () => now);
      final r = request();
      await service.execute(accountId: local, request: r, load: () async => 1);
      final raw = sqlite3.open(path);
      try {
        raw.execute("UPDATE cache_entries SET fetched_at='broken'");
        expect(
          (await service.inspectCacheFor(accountId: local, request: r)).state,
          CacheEntryState.corrupt,
        );
        expect(
          await service.isCacheAvailableFor(
            accountId: local,
            request: request(version: 2),
          ),
          isFalse,
        );
        persisted.setAppletOfflineData(
          accountId: local,
          appletId: 'broken.php',
          json: '{}',
        );
        persisted.setAppletOfflineData(
          accountId: local,
          appletId: 'valid.php',
          json: '{}',
        );
        raw.execute(
          "UPDATE applet_offline_data SET timestamp='broken' WHERE applet_id='broken.php'",
        );
        expect(persisted.listAppletOfflineData().single.appletId, 'valid.php');
        expect(persisted.structuredCacheUsage(accountId: local).entries, 3);
        service.clear(accountId: local);
        expect(persisted.structuredCacheUsage(accountId: local).entries, 0);
      } finally {
        raw.close();
        persisted.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'a database clear generation is visible to another connection',
    () async {
      final directory = Directory.systemTemp.createTempSync('liblanis-cache-');
      final secret = MemorySecretStore();
      final first = LanisDatabase.open(
        path: '${directory.path}/cache.db',
        secretStore: secret,
      );
      final second = LanisDatabase.open(
        path: '${directory.path}/cache.db',
        secretStore: secret,
      );
      try {
        final id = await first.addAccount(
          schoolId: 1,
          schoolName: 'Test',
          username: 'shared',
          password: 'test',
        );
        final r = request();
        final generation = first.cacheGeneration(id);
        second.clearStructuredCache(accountId: id);
        expect(
          first.writeCacheRecord(
            CacheRecord(
              key: r.keyFor(id),
              codecId: r.codec.id,
              json: '1',
              fetchedAt: start,
              expiresAt: start.add(const Duration(hours: 1)),
            ),
            generation,
          ),
          isFalse,
        );
        expect(first.readCacheRecord(r.keyFor(id)), isNull);
      } finally {
        first.dispose();
        second.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'parent timetable sealed values serialize through the same generic service',
    () async {
      final codec = CacheCodec<ParentTimetableHome>(
        id: 'parent.home',
        encode: (v) => v.toJson(),
        decode: (v) => ParentTimetableHome.fromJson(v as Map<String, dynamic>),
      );
      final r = CacheRequest(
        operation: 'parent.home',
        codec: codec,
        arguments: {},
        appletLimit: Applets.timetable.refreshInterval,
      );
      final home = TimetableParentParser.parseSelectionDocument(parseFixture());
      await cache.execute(
        accountId: account,
        request: r,
        load: () async => home,
      );
      final cached =
          (await cache.readCacheFor(accountId: account, request: r)).data
              as ParentTimetableSelection;
      expect(cached.timetables, hasLength(2));
    },
  );

  test(
    'availableRequestsFor batch-checks metadata across accounts, expiry, versions, and operations',
    () async {
      final r1 = request(
        arguments: {'id': '1'},
        age: const Duration(hours: 2),
      );
      final r2 = request(
        arguments: {'id': '2'},
        age: const Duration(minutes: 30),
      );
      final r3 = request(
        arguments: {'id': '3'},
        age: const Duration(hours: 2),
      );
      final rOtherOp = request(
        operation: 'other.read',
        arguments: {'id': '1'},
        age: const Duration(hours: 2),
      );
      final rV2 = request(
        arguments: {'id': '1'},
        version: 2,
        age: const Duration(hours: 2),
      );

      await cache.execute(accountId: account, request: r1, load: () async => 1);
      await cache.execute(accountId: account, request: r2, load: () async => 2);
      await cache.execute(
        accountId: otherAccount,
        request: r3,
        load: () async => 3,
      );
      await cache.execute(
        accountId: account,
        request: rOtherOp,
        load: () async => 4,
      );

      // Initially r1, r2, and rOtherOp are available for `account`; r3 (other account)
      // and rV2 (different version) are not.
      final initial = await cache.availableRequestsFor(
        accountId: account,
        requests: [r1, r2, r3, rOtherOp, rV2],
      );
      expect(initial, {r1, r2, rOtherOp});

      // Advance clock past r2's 30-minute expiry while r1 remains valid.
      now = start.add(const Duration(minutes: 45));
      final afterExpiry = await cache.availableRequestsFor(
        accountId: account,
        requests: [r1, r2, r3, rOtherOp, rV2],
      );
      expect(afterExpiry, {r1, rOtherOp});

      // Stricter request maxAge also filters out entries older than maxAge.
      final r1Strict = request(
        arguments: {'id': '1'},
        age: const Duration(minutes: 15),
      );
      final strict = await cache.availableRequestsFor(
        accountId: account,
        requests: [r1Strict],
      );
      expect(strict, isEmpty);

      // Empty input returns empty set.
      expect(
        await cache.availableRequestsFor<int>(
          accountId: account,
          requests: const [],
        ),
        isEmpty,
      );
    },
  );
}

// No session or connection checker is created to parse or inspect this fixture.
dynamic parseFixture() => parse(
  File(
    'test/fixtures/timetable/parents/two_pupils_overview.html',
  ).readAsStringSync(),
);
