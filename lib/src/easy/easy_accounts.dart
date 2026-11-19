import '../config.dart';
import '../database/database.dart';
import '../exceptions.dart';
import '../models/account.dart';
import '../models/account_types.dart';
import '../session/session.dart';

/// Account CRUD for [EasyLanisClient] (no Riverpod).
class EasyAccounts {
  final LanisDatabase? _db;
  final LanisConfig _config;
  final bool _ephemeral;
  final Future<void> Function(int id)? _onRemoveActive;
  final Future<void> Function(int id)? _onAccountTypeChanged;

  EasyAccounts({
    required this._db,
    required this._config,
    required this._ephemeral,
    this._onRemoveActive,
    this._onAccountTypeChanged,
  });

  LanisDatabase get _requireDb {
    if (_ephemeral || _db == null) {
      throw ConfigurationException(
        'Ephemeral client has no persistent accounts',
      );
    }
    return _db;
  }

  Future<List<AccountSummary>> list() async {
    if (_ephemeral || _db == null) return [];
    return _db.listAccounts();
  }

  Future<int> add({
    required int schoolId,
    required String username,
    required String password,
    AccountType? accountType,
  }) async {
    final db = _requireDb;
    return db.addAccount(
      schoolId: schoolId,
      schoolName: '',
      username: username,
      password: password,
      accountType: accountType,
    );
  }

  Future<void> remove(int id) async {
    final db = _requireDb;
    await db.deleteAccount(id);
    await _onRemoveActive?.call(id);
  }

  Future<void> setAccountType(int id, AccountType type) async {
    final db = _requireDb;
    await db.setAccountType(id, type);
    await _onAccountTypeChanged?.call(id);
  }

  Future<void> updatePassword(int id, String password) async {
    await _requireDb.updatePassword(id, password);
  }

  /// Probes credentials against SPH without persisting an account.
  Future<String> validateCredentials({
    required int schoolId,
    required String username,
    required String password,
  }) {
    final account = ClearTextAccount(
      localId: 0,
      schoolID: schoolId,
      schoolName: '',
      username: username,
      password: password,
    );
    return LanisSession.getLoginURL(account, _config);
  }
}
