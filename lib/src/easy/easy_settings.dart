import '../database/database.dart';
import '../settings/typed_settings.dart';

/// Shared and per-account settings for [EasyLanisClient].
class EasySettings {
  final LanisDatabase _db;
  final int? _activeAccountId;

  EasySettings({
    required this._db,
    required this._activeAccountId,
  });

  TypedSettings get shared => TypedSettings.shared(_db);

  /// Per-account settings for the logged-in account, or null when none selected.
  TypedSettings? get account {
    final id = _activeAccountId;
    if (id == null) return null;
    return TypedSettings.account(_db, id);
  }
}
