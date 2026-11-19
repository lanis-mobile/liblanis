import '../database/database.dart';

/// Typed key-value helpers over JSON-encoded settings rows.
class TypedSettings {
  final String? Function(String key) _read;
  final void Function(String key, String? value) _write;
  final void Function(String key) _delete;

  TypedSettings({
    required this._read,
    required this._write,
    required this._delete,
  });

  /// Share storage while keeping every setting inside a separate namespace.
  TypedSettings scoped(String prefix) => TypedSettings(
    read: (key) => _read('$prefix$key'),
    write: (key, value) => _write('$prefix$key', value),
    delete: (key) => _delete('$prefix$key'),
  );

  factory TypedSettings.shared(LanisDatabase db) {
    return TypedSettings(
      read: db.getSharedSetting,
      write: db.setSharedSetting,
      delete: db.deleteSharedSetting,
    );
  }

  factory TypedSettings.account(LanisDatabase db, int accountId) {
    return TypedSettings(
      read: (key) => db.getAccountSetting(accountId, key),
      write: (key, value) => db.setAccountSetting(accountId, key, value),
      delete: (key) => db.deleteAccountSetting(accountId, key),
    );
  }

  String? getString(String key) {
    final v = LanisDatabase.decodeValue(_read(key));
    return v?.toString();
  }

  void setString(String key, String? value) {
    if (value == null) {
      _delete(key);
    } else {
      _write(key, LanisDatabase.encodeValue(value));
    }
  }

  bool? getBool(String key) {
    final v = LanisDatabase.decodeValue(_read(key));
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
      // Do not coerce arbitrary strings (e.g. Map.toString()) to false.
      return null;
    }
    return null;
  }

  void setBool(String key, bool? value) {
    if (value == null) {
      _delete(key);
    } else {
      _write(key, LanisDatabase.encodeValue(value));
    }
  }

  int? getInt(String key) {
    final v = LanisDatabase.decodeValue(_read(key));
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  void setInt(String key, int? value) {
    if (value == null) {
      _delete(key);
    } else {
      _write(key, LanisDatabase.encodeValue(value));
    }
  }

  double? getDouble(String key) {
    final v = LanisDatabase.decodeValue(_read(key));
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void setDouble(String key, double? value) {
    if (value == null) {
      _delete(key);
    } else {
      _write(key, LanisDatabase.encodeValue(value));
    }
  }

  Map<String, dynamic>? getJsonMap(String key) {
    final v = LanisDatabase.decodeValue(_read(key));
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  void setJsonMap(String key, Map<String, dynamic>? value) {
    if (value == null) {
      _delete(key);
    } else {
      _write(key, LanisDatabase.encodeValue(value));
    }
  }

  List<dynamic>? getJsonList(String key) {
    final v = LanisDatabase.decodeValue(_read(key));
    if (v is List) return v;
    return null;
  }

  void setJsonList(String key, List<dynamic>? value) {
    if (value == null) {
      _delete(key);
    } else {
      _write(key, LanisDatabase.encodeValue(value));
    }
  }

  void remove(String key) => _delete(key);
}
