/// Pure URL query helpers for `stundenplan.php` timetable version dates.
abstract final class TimetableUrlHelper {
  /// Reads the `date` query parameter from [url], or returns `null` if absent
  /// or blank. Tolerates malformed percent-encoding.
  static String? readDateParam(Uri url) {
    final raw = _safeQueryParametersAll(url)['date'];
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.last.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns a copy of [url] with its `date` query parameter set to [date]
  /// (trimmed), or removed when [date] is null or blank.
  ///
  /// Preserves unrelated query parameters verbatim even when [url] contains
  /// non-UTF-8 percent-encoding (e.g. `t=M%FCller`).
  static Uri withDateParam(Uri url, String? date) {
    final trimmed = date?.trim();
    final hasNewDate = trimmed != null && trimmed.isNotEmpty;

    try {
      final existing = url.queryParametersAll;
      final params = <String, List<String>>{
        for (final entry in existing.entries)
          entry.key: List<String>.from(entry.value),
      };
      if (!hasNewDate) {
        params.remove('date');
      } else {
        params['date'] = [trimmed];
      }
      if (params.isEmpty) {
        return _withoutQuery(url);
      }
      return url.replace(
        queryParameters: params.map(
          (k, v) => MapEntry<String, dynamic>(k, v.length == 1 ? v.first : v),
        ),
      );
    } on FormatException {
      // Fallback: rewrite raw '&'-separated segments so unrelated malformed
      // percent-encoded values are never double-encoded.
      final segments = <String>[];
      var replaced = false;
      for (final part in url.query.split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        final rawKey = eq < 0 ? part : part.substring(0, eq);
        if (_safeDecode(rawKey) == 'date') {
          if (hasNewDate && !replaced) {
            segments.add('date=${Uri.encodeQueryComponent(trimmed)}');
            replaced = true;
          }
          continue;
        }
        segments.add(part);
      }
      if (hasNewDate && !replaced) {
        segments.add('date=${Uri.encodeQueryComponent(trimmed)}');
      }
      if (segments.isEmpty) {
        return _withoutQuery(url);
      }
      return url.replace(query: segments.join('&'));
    }
  }

  static Uri _withoutQuery(Uri url) {
    if (url.hasAuthority) {
      return Uri(
        scheme: url.scheme,
        userInfo: url.userInfo,
        host: url.host,
        port: url.hasPort ? url.port : null,
        path: url.path,
        fragment: url.hasFragment ? url.fragment : null,
      );
    }
    return Uri(
      scheme: url.hasScheme ? url.scheme : null,
      path: url.path,
      fragment: url.hasFragment ? url.fragment : null,
    );
  }

  static Map<String, List<String>> _safeQueryParametersAll(Uri uri) {
    try {
      return uri.queryParametersAll;
    } on FormatException {
      final result = <String, List<String>>{};
      for (final part in uri.query.split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        final String key;
        final String value;
        if (eq < 0) {
          key = _safeDecode(part);
          value = '';
        } else {
          key = _safeDecode(part.substring(0, eq));
          value = _safeDecode(part.substring(eq + 1));
        }
        (result[key] ??= <String>[]).add(value);
      }
      return result;
    }
  }

  static String _safeDecode(String raw) {
    try {
      return Uri.decodeQueryComponent(raw);
    } on FormatException {
      return raw;
    } on ArgumentError {
      return raw;
    }
  }
}
