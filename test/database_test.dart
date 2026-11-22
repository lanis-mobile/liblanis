import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

void main() {
  group('LanisDatabase', () {
    late LanisDatabase db;

    setUp(() {
      db = LanisDatabase.open();
    });

    tearDown(() {
      db.dispose();
    });

    test('file DB requires SecretStore', () {
      expect(
        () => LanisDatabase.open(path: '/tmp/liblanis_test.db'),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('add, list, get, delete account', () async {
      final id = await db.addAccount(
        schoolId: 1234,
        schoolName: 'Test School',
        username: 'user',
        password: 'secret',
        accountType: AccountType.student,
      );

      final list = await db.listAccounts();
      expect(list, hasLength(1));
      expect(list.first.localId, id);
      expect(list.first.schoolName, 'Test School');

      final account = await db.getAccount(id);
      expect(account, isNotNull);
      expect(account!.password, 'secret');
      expect(account.accountType, AccountType.student);
      expect(account.firstLogin, isTrue);

      await db.updateLastLogin(id);
      final again = await db.getAccount(id);
      expect(again!.firstLogin, isFalse);

      await db.deleteAccount(id);
      expect(await db.listAccounts(), isEmpty);
    });

    test('rejects duplicate school+username', () async {
      await db.addAccount(
        schoolId: 1,
        schoolName: 'A',
        username: 'u',
        password: 'p',
      );
      expect(
        () => db.addAccount(
          schoolId: 1,
          schoolName: 'A',
          username: 'u',
          password: 'p',
        ),
        throwsA(isA<AccountAlreadyExistsException>()),
      );
    });

    test('shared and account settings typed helpers', () async {
      final shared = TypedSettings.shared(db);
      shared.setString('theme', 'dark');
      shared.setBool('notifications-allow', true);
      shared.setInt('interval', 15);
      expect(shared.getString('theme'), 'dark');
      expect(shared.getBool('notifications-allow'), isTrue);
      expect(shared.getInt('interval'), 15);
      expect(shared.getBool('theme'), isNull);
      shared.setString('legacy-false', 'false');
      expect(shared.getBool('legacy-false'), isFalse);

      final id = await db.addAccount(
        schoolId: 2,
        schoolName: 'B',
        username: 'x',
        password: 'y',
      );
      final account = TypedSettings.account(db, id);
      account.setJsonMap('vertretungsplan.php/filter', {
        'Klasse': {
          'filter': ['10a'],
          'strict': true,
        },
      });
      final filter = account.getJsonMap('vertretungsplan.php/filter');
      expect(filter!['Klasse']['filter'], ['10a']);
    });

    test('applet offline data upsert and read', () async {
      final id = await db.addAccount(
        schoolId: 3,
        schoolName: 'C',
        username: 'z',
        password: 'pw',
      );
      db.setAppletOfflineData(
        accountId: id,
        appletId: 'vertretungsplan.php',
        json: '{"days":[],"lastUpdated":"2026-01-01T00:00:00.000"}',
      );
      final data = db.getAppletOfflineData(
        accountId: id,
        appletId: 'vertretungsplan.php',
      );
      expect(data, isNotNull);
      expect(data!.json, contains('days'));

      final listed = db.listAppletOfflineData(accountId: id);
      expect(listed, hasLength(1));
      expect(listed.first.appletId, 'vertretungsplan.php');
    });

    test('delete offline data and clear setting keys', () async {
      final id = await db.addAccount(
        schoolId: 4,
        schoolName: 'D',
        username: 'w',
        password: 'pw',
      );
      db.setAppletOfflineData(
        accountId: id,
        appletId: 'kalender.php',
        json: '{"events":[]}',
      );
      db.deleteAppletOfflineData(accountId: id, appletId: 'kalender.php');
      expect(
        db.getAppletOfflineData(accountId: id, appletId: 'kalender.php'),
        isNull,
      );

      final shared = TypedSettings.shared(db);
      shared.setString('tmp', 'x');
      shared.setString('tmp', null);
      expect(shared.getString('tmp'), isNull);
    });

    test('listAppletOfflineData across accounts', () async {
      final a = await db.addAccount(
        schoolId: 5,
        schoolName: 'E',
        username: 'a',
        password: 'pw',
      );
      final b = await db.addAccount(
        schoolId: 6,
        schoolName: 'F',
        username: 'b',
        password: 'pw',
      );
      db.setAppletOfflineData(
        accountId: a,
        appletId: 'vertretungsplan.php',
        json: '{}',
      );
      db.setAppletOfflineData(
        accountId: b,
        appletId: 'nachrichten.php',
        json: '{}',
      );
      expect(db.listAppletOfflineData(), hasLength(2));
      expect(db.listAppletOfflineData(accountId: a), hasLength(1));
    });

    test(
      'addAccount rolls back the SQLite row when SecretStore.write fails',
      () async {
        final store = _FlakySecretStore(failWrites: true, failDeletes: true);
        final flakyDb = LanisDatabase.open(secretStore: store);
        addTearDown(flakyDb.dispose);

        await expectLater(
          flakyDb.addAccount(
            schoolId: 100,
            schoolName: 'Flaky School',
            username: 'alice',
            password: 'secret',
          ),
          throwsA(isA<StateError>()),
        );

        expect(await flakyDb.listAccounts(), isEmpty);

        // Retrying after the keychain recovers must not throw AccountAlreadyExistsException.
        store.failWrites = false;
        store.failDeletes = false;
        final id = await flakyDb.addAccount(
          schoolId: 100,
          schoolName: 'Flaky School',
          username: 'alice',
          password: 'secret',
        );
        final account = await flakyDb.getAccount(id);
        expect(account?.password, 'secret');
      },
    );

    test(
      'addAccount removes partially written secret when cleanup succeeds',
      () async {
        final store = _FlakySecretStore(failWrites: true, failDeletes: false);
        final flakyDb = LanisDatabase.open(secretStore: store);
        addTearDown(flakyDb.dispose);

        await expectLater(
          flakyDb.addAccount(
            schoolId: 101,
            schoolName: 'School',
            username: 'bob',
            password: 'secret',
          ),
          throwsA(isA<StateError>()),
        );

        expect(await flakyDb.listAccounts(), isEmpty);
        expect(store.values, isEmpty);
      },
    );

    test(
      'addAccount replaces pre-existing incomplete row with empty secret key',
      () async {
        final store = MemorySecretStore();
        final recoveryDb = LanisDatabase.open(secretStore: store);
        addTearDown(recoveryDb.dispose);

        // Simulate a leftover orphan row (e.g. from an interrupted write/lock).
        // ignore: invalid_use_of_internal_member
        recoveryDb.insertEphemeralAccount(schoolId: 102, username: 'carol');

        final id = await recoveryDb.addAccount(
          schoolId: 102,
          schoolName: 'Recovered School',
          username: 'carol',
          password: 'pw',
        );
        final account = await recoveryDb.getAccount(id);
        expect(account?.schoolName, 'Recovered School');
        expect(account?.password, 'pw');
        expect(await recoveryDb.listAccounts(), hasLength(1));
      },
    );

    test(
      'addAccount fails and cleans up secret if row is deleted during SecretStore.write',
      () async {
        final store = _FlakySecretStore();
        final raceDb = LanisDatabase.open(secretStore: store);
        addTearDown(raceDb.dispose);

        store.onWrite = () async {
          final accounts = await raceDb.listAccounts();
          for (final a in accounts) {
            await raceDb.deleteAccount(a.localId);
          }
        };

        await expectLater(
          raceDb.addAccount(
            schoolId: 103,
            schoolName: 'Race School',
            username: 'dave',
            password: 'pw',
          ),
          throwsA(isA<StateError>()),
        );
        expect(await raceDb.listAccounts(), isEmpty);
        expect(store.values, isEmpty);
      },
    );
  });
}

class _FlakySecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool failWrites;
  bool failDeletes;
  Future<void> Function()? onWrite;

  _FlakySecretStore({this.failWrites = false, this.failDeletes = false});

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    if (onWrite != null) {
      await onWrite!();
    }
    if (failWrites) {
      throw StateError('keychain locked');
    }
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('keychain delete failed');
    values.remove(key);
  }
}
