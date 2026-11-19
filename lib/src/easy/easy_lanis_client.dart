import 'package:dio/dio.dart';

import '../applets/applet_context.dart';
import '../applets/definition.dart';
import '../config.dart';
import '../cache/service.dart';
import '../connection/connection_checker.dart';
import '../database/database.dart';
import '../exceptions.dart';
import '../lanis_client.dart';
import '../models/account.dart';
import '../models/account_types.dart';
import '../secret_store.dart';
import '../session/session.dart';
import '../settings/typed_settings.dart';
import '../storage/storage_manager.dart';
import 'easy_accounts.dart';
import 'easy_connection.dart';
import 'easy_parsers.dart';
import 'easy_settings.dart';

/// Imperative Lanis client without Riverpod.
///
/// Use [EasyLanisClient.inMemory], [EasyLanisClient.open], or
/// [EasyLanisClient.ephemeral] to construct, then [login] and [parsers].
class EasyLanisClient {
  EasyLanisClient._({
    required LanisConfig config,
    required LanisDatabase db,
    required bool ephemeral,
    this._ephemeralAccount,
  }) : _config = config,
       _db = db,
       _ephemeral = ephemeral {
    _connection = ConnectionChecker(httpAdapter: config.httpAdapter);
    _accounts = EasyAccounts(
      db: ephemeral ? null : db,
      config: config,
      ephemeral: ephemeral,
      onRemoveActive: _onAccountRemoved,
      onAccountTypeChanged: _onAccountTypeChanged,
    );
  }

  final LanisConfig _config;
  final LanisDatabase _db;
  final bool _ephemeral;
  ClearTextAccount? _ephemeralAccount;

  late final ConnectionChecker _connection;
  late final EasyAccounts _accounts;

  ClearTextAccount? _activeAccount;
  LanisSession? _session;
  EasyParsers? _parsers;
  StorageManager? _storageManager;
  bool _authenticated = false;
  bool _disposed = false;

  /// In-memory database (CI unit tests, quick scripts).
  factory EasyLanisClient.inMemory({
    String? documentCacheDirectory,
    HttpClientAdapter? httpAdapter,
    String userAgent = 'liblanis/0.1.0',
    bool storageEnabled = true,
    Duration? storageMaxAge,
    int? storageMaxBytes,
    UnexpectedErrorHandler? onUnexpectedError,
  }) {
    LanisClient.configure(
      documentCacheDirectory: documentCacheDirectory,
      httpAdapter: httpAdapter,
      userAgent: userAgent,
      storageEnabled: storageEnabled,
      storageMaxAge: storageMaxAge,
      storageMaxBytes: storageMaxBytes,
      onUnexpectedError: onUnexpectedError,
    );
    final config = LanisClient.config!;
    final db = LanisDatabase.open(
      path: config.databasePath,
      secretStore: config.secretStore,
    );
    return EasyLanisClient._(config: config, db: db, ephemeral: false);
  }

  /// Persistent file database (CLI tools, other apps).
  factory EasyLanisClient.open({
    required String databasePath,
    required SecretStore secretStore,
    String? documentCacheDirectory,
    HttpClientAdapter? httpAdapter,
    String userAgent = 'liblanis/0.1.0',
    bool storageEnabled = true,
    Duration? storageMaxAge,
    int? storageMaxBytes,
    UnexpectedErrorHandler? onUnexpectedError,
  }) {
    LanisClient.configure(
      databasePath: databasePath,
      secretStore: secretStore,
      documentCacheDirectory: documentCacheDirectory,
      httpAdapter: httpAdapter,
      userAgent: userAgent,
      storageEnabled: storageEnabled,
      storageMaxAge: storageMaxAge,
      storageMaxBytes: storageMaxBytes,
      onUnexpectedError: onUnexpectedError,
    );
    final config = LanisClient.config!;
    final db = LanisDatabase.open(
      path: config.databasePath,
      secretStore: config.secretStore,
    );
    return EasyLanisClient._(config: config, db: db, ephemeral: false);
  }

  /// Credentials in memory only — no persistent accounts (smoke tests).
  factory EasyLanisClient.ephemeral({
    required int schoolId,
    required String username,
    required String password,
    AccountType? accountType,
    HttpClientAdapter? httpAdapter,
    String userAgent = 'liblanis/0.1.0',
    UnexpectedErrorHandler? onUnexpectedError,
  }) {
    LanisClient.configure(
      httpAdapter: httpAdapter,
      userAgent: userAgent,
      onUnexpectedError: onUnexpectedError,
    );
    final config = LanisClient.config!;
    final db = LanisDatabase.open(
      path: config.databasePath,
      secretStore: config.secretStore,
    );
    return EasyLanisClient._(
      config: config,
      db: db,
      ephemeral: true,
      ephemeralAccount: ClearTextAccount(
        localId: 1,
        schoolID: schoolId,
        schoolName: '',
        username: username,
        password: password,
        accountType: accountType,
      ),
    );
  }

  LanisDatabase get database => _db;

  EasyAccounts get accounts => _accounts;

  EasyConnection get connection => EasyConnection(_connection);

  EasySettings get settings =>
      EasySettings(db: _db, activeAccountId: _activeAccount?.localId);

  /// Document cache manager, or null when not logged in or cache dir unset.
  StorageManager? get storage {
    if (_activeAccount == null || _session == null) return null;
    if (_config.documentCacheDirectory == null) return null;
    return _storageManager ??= StorageManager(
      session: _session!,
      config: _config,
      accountId: _activeAccount!.localId,
    );
  }

  CacheService get cache => CacheService.shared(_db);

  bool get isAuthenticated => _authenticated;

  LanisSession? get session => _session;

  EasyParsers get parsers {
    if (_parsers == null) {
      throw ConfigurationException('Login required before accessing parsers');
    }
    return _parsers!;
  }

  /// PHP applet URLs enabled for the current session and account type.
  Set<String> get supportedApplets {
    if (_session == null || _activeAccount == null) return const {};
    final type = _activeAccount!.accountType ?? _session!.accountTypeOrNull;
    if (type == null) return const {};
    return {
      for (final applet in Applets.all)
        if (_session!.doesSupportFeature(applet, overrideAccountType: type))
          applet.appletPhpUrl,
    };
  }

  /// Selects an account, prepares HTTP, and authenticates with SPH.
  ///
  /// For [EasyLanisClient.ephemeral], [accountId] is optional.
  Future<void> login({
    int? accountId,
    String? loginUrl,
    bool withoutData = false,
  }) async {
    _ensureNotDisposed();

    final ClearTextAccount account;
    if (_ephemeral) {
      if (_ephemeralAccount == null) {
        throw ConfigurationException('Ephemeral account not configured');
      }
      account = _ephemeralAccount!;
    } else {
      if (accountId == null) {
        throw ConfigurationException('accountId is required');
      }
      final loaded = await _db.getAccount(accountId);
      if (loaded == null) {
        throw UnknownException('Account $accountId not found');
      }
      account = loaded;
    }

    final previousId = _activeAccount?.localId;
    if (previousId != null && previousId != account.localId) {
      await _clearSession(skipDeauthenticate: false);
    } else if (previousId == account.localId && _session != null) {
      await _clearSession(skipDeauthenticate: false);
    }

    _activeAccount = account;
    _session = LanisSession(
      account: account,
      config: _config,
      connectionChecker: _connection,
    );
    await _session!.prepareDio();
    _rebuildParsers();
    _storageManager = null;

    await _session!.authenticate(
      withLoginUrl: loginUrl,
      withoutData: withoutData,
    );

    if (!_ephemeral) {
      await _db.updateLastLogin(account.localId);
      if (account.accountType == null) {
        final detectedType = _session!.accountTypeOrNull;
        if (detectedType != null) {
          await _db.setAccountType(account.localId, detectedType);
          final updated = await _db.getAccount(account.localId);
          if (updated != null) {
            _activeAccount = updated;
            _rebuildParsers();
          }
        }
      }
    } else if (_activeAccount!.accountType == null) {
      final detected = _session!.accountTypeOrNull;
      if (detected != null) {
        _activeAccount = _activeAccount!.copyWith(accountType: detected);
        _rebuildParsers();
      }
    }

    _authenticated = true;
  }

  /// Logs out and clears session state. Parsers are disposed.
  Future<void> logout() async {
    _ensureNotDisposed();
    await _clearSession(skipDeauthenticate: false);
    _activeAccount = null;
    _authenticated = false;
  }

  /// Selects the preferred startup account and logs in, if one exists.
  Future<void> loginPreferred() async {
    _ensureNotDisposed();
    if (_ephemeral) {
      await login();
      return;
    }
    final account = await _db.getPreferredStartupAccount();
    if (account == null) {
      await logout();
      return;
    }
    await login(accountId: account.localId);
  }

  /// Releases connection, session, and database resources.
  Future<void> dispose() async {
    if (_disposed) return;
    await logout();
    _connection.dispose();
    _db.dispose();
    _disposed = true;
  }

  Future<void> _clearSession({required bool skipDeauthenticate}) async {
    _parsers?.disposeAll();
    _parsers = null;
    _storageManager = null;
    if (_session != null) {
      if (!skipDeauthenticate) {
        try {
          await _session!.deAuthenticate();
        } catch (_) {}
      }
      await _session!.dispose();
      _session = null;
    }
  }

  void _rebuildParsers() {
    _parsers?.disposeAll();
    if (_session == null || _activeAccount == null) {
      _parsers = null;
      return;
    }
    _parsers = EasyParsers(
      ctx: AppletContext(
        session: _session!,
        database: _db,
        account: _activeAccount!,
        accountSettings: TypedSettings.account(_db, _activeAccount!.localId),
      ),
      isConnected: () => _connection.connected,
    );
  }

  Future<void> _onAccountRemoved(int id) async {
    if (_activeAccount?.localId == id) {
      await logout();
    }
  }

  Future<void> _onAccountTypeChanged(int id) async {
    if (_activeAccount?.localId == id) {
      final updated = await _db.getAccount(id);
      if (updated != null) {
        _activeAccount = updated;
      }
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('EasyLanisClient has been disposed');
    }
  }
}
