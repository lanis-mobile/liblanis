import 'dart:async';

import 'package:dio/dio.dart';
import 'package:liblanis/easy_client.dart';
import 'package:test/test.dart';

import 'support/offline_http_adapter.dart';

void main() {
  tearDown(LanisClient.reset);

  group('EasyLanisClient.inMemory', () {
    test('opens in-memory database', () {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      expect(client.database.isInMemory, isTrue);
      expect(client.connection.status, isA<ConnectionStatus>());
    });

    test('account add, list, and remove', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 99,
        username: 'alice',
        password: 'pw',
      );

      final accounts = await client.accounts.list();
      expect(accounts, hasLength(1));
      expect(accounts.single.username, 'alice');

      await client.accounts.remove(id);
      expect(await client.accounts.list(), isEmpty);
    });

    test('settings read and write', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      client.settings.shared.setString('color', 'blue');
      expect(client.settings.shared.getString('color'), 'blue');

      final id = await client.accounts.add(
        schoolId: 1,
        username: 'u',
        password: 'p',
      );

      expect(client.settings.account, isNull);

      await _prepareAccount(client, id);

      expect(client.settings.account, isNotNull);
      client.settings.account!.setBool('notifications-allow', false);
      expect(client.settings.account!.getBool('notifications-allow'), isFalse);
    });

    test('storage is null without cache directory', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 1,
        username: 'u',
        password: 'p',
      );
      await _prepareAccount(client, id);

      expect(client.storage, isNull);
    });

    test('storage available when cache dir configured', () async {
      final client = _offlineInMemory(
        documentCacheDirectory: '/tmp/liblanis_easy_cache_test',
      );
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 1,
        username: 'u',
        password: 'p',
      );
      await _prepareAccount(client, id);

      expect(client.storage, isNotNull);
    });

    test('parsers throws when no account prepared', () {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      expect(
        () => client.parsers,
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('parsers available after account prepared', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 1,
        username: 'u',
        password: 'p',
      );
      await _prepareAccount(client, id);

      expect(client.parsers.substitutions, isA<SubstitutionsParser>());
      expect(client.parsers.calendar, isA<CalendarParser>());
      expect(client.parsers.forApplet('kalender.php'), isA<CalendarParser>());
    });

    test('logout clears session and parsers', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 9,
        username: 'z',
        password: 'p',
      );
      await _prepareAccount(client, id);
      expect(client.session, isNotNull);

      await client.logout();

      expect(client.session, isNull);
      expect(client.isAuthenticated, isFalse);
      expect(client.settings.account, isNull);
      expect(
        () => client.parsers,
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('account switch replaces active session', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id1 = await client.accounts.add(
        schoolId: 1,
        username: 'u1',
        password: 'p',
      );
      final id2 = await client.accounts.add(
        schoolId: 2,
        username: 'u2',
        password: 'p',
      );

      await _prepareAccount(client, id1);
      expect(client.session?.account.localId, id1);

      await _prepareAccount(client, id2);
      expect(client.session?.account.localId, id2);
      expect(client.settings.account, isNotNull);
    });

    test('setAccountType updates active account snapshot', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 1,
        username: 'u',
        password: 'p',
      );
      await _prepareAccount(client, id);

      await client.accounts.setAccountType(id, AccountType.student);
      final updated = await client.database.getAccount(id);
      expect(updated?.accountType, AccountType.student);
    });

    test('remove active account logs out', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 9,
        username: 'z',
        password: 'p',
      );
      await _prepareAccount(client, id);

      await client.accounts.remove(id);

      expect(client.session, isNull);
      expect(await client.accounts.list(), isEmpty);
    });

    test('supportedApplets empty before authentication', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      final id = await client.accounts.add(
        schoolId: 1,
        username: 'u',
        password: 'p',
      );
      await _prepareAccount(client, id);

      expect(client.supportedApplets, isEmpty);
      expect(client.isAuthenticated, isFalse);
    });

    test('login requires accountId for persistent client', () async {
      final client = _offlineInMemory();
      addTearDown(() => client.dispose());

      expect(
        () => client.login(),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });

  group('EasyLanisClient.ephemeral', () {
    test('has no persistent accounts', () async {
      final client = EasyLanisClient.ephemeral(
        schoolId: 1,
        username: 'u',
        password: 'p',
        httpAdapter: OfflineHttpAdapter(),
      );
      addTearDown(() => client.dispose());

      expect(await client.accounts.list(), isEmpty);
      expect(
        () => client.accounts.add(
          schoolId: 1,
          username: 'x',
          password: 'p',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('login without accountId prepares ephemeral session', () async {
      final client = EasyLanisClient.ephemeral(
        schoolId: 1,
        username: 'u',
        password: 'p',
        httpAdapter: OfflineHttpAdapter(),
      );
      addTearDown(() => client.dispose());

      try {
        await client.login();
      } on TimeoutException {
        // Live probe timed out (should not happen with OfflineHttpAdapter).
      } on DioException {
        // Transport error before it is mapped to LanisException.
      } on NoConnectionException {
        // Expected when SPH is unreachable (CI).
      } on LanisException {
        // Other SPH errors are also acceptable in CI.
      }

      expect(client.session, isNotNull);
      expect(client.session?.account.username, 'u');
    });

    test(
      'ephemeral client supports structured cache, account settings, and offline data without FK errors',
      () async {
        final client = EasyLanisClient.ephemeral(
          schoolId: 5182,
          username: 'u',
          password: 'p',
          httpAdapter: OfflineHttpAdapter(),
        );
        addTearDown(client.dispose);

        expect(await client.accounts.list(), isEmpty);

        try {
          await client.login();
        } on LanisException {
          // Offline adapter throws; session and parsers are still initialized.
        }

        final accountId = client.session!.account.localId;
        client.database.setAccountSetting(accountId, 'theme', 'dark');
        expect(client.database.getAccountSetting(accountId, 'theme'), 'dark');

        client.database.setAppletOfflineData(
          accountId: accountId,
          appletId: 'vertretungsplan.php',
          json: '{}',
        );
        expect(
          client.database.getAppletOfflineData(
            accountId: accountId,
            appletId: 'vertretungsplan.php',
          ),
          isNotNull,
        );

        final cache = CacheService(client.database);
        final request = CacheRequest<String>(
          operation: 'test.ephemeral',
          arguments: const {},
          codec: CacheCodec<String>(
            id: 'string:v1',
            encode: (value) => value,
            decode: (json) => json as String,
          ),
          maxAge: const Duration(hours: 1),
        );
        await cache.execute(
          accountId: accountId,
          request: request,
          load: () async => 'ok',
        );
        final cached = await cache.readCacheFor(
          accountId: accountId,
          request: request,
        );
        expect(cached.data, 'ok');
      },
    );
  });

  group('EasyLanisClient.open', () {
    test('requires secretStore for file path', () {
      final client = EasyLanisClient.open(
        databasePath: '/tmp/x.db',
        secretStore: MemorySecretStore(),
        httpAdapter: OfflineHttpAdapter(),
      );
      addTearDown(client.dispose);
      expect(client.database.isInMemory, isFalse);
    });
  });
}

EasyLanisClient _offlineInMemory({String? documentCacheDirectory}) {
  return EasyLanisClient.inMemory(
    documentCacheDirectory: documentCacheDirectory,
    httpAdapter: OfflineHttpAdapter(),
  );
}

/// Prepares session and parsers without requiring a successful SPH login.
Future<void> _prepareAccount(EasyLanisClient client, int accountId) async {
  try {
    await client.login(accountId: accountId);
  } on TimeoutException {
    // Session is prepared before authenticate; do not fail the unit test.
  } on DioException {
    // Same if a transport error escapes mapping.
  } on LanisException {
    // SPH unreachable or mocked offline — session is still prepared.
  }
}
