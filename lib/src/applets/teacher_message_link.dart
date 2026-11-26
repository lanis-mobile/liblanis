import 'dart:convert';

import 'package:html/dom.dart';

final RegExp _receiverIdPattern = RegExp(r'^[a-zA-Z]+-[a-zA-Z0-9_]+$');

/// Extracts a teacher's email address from a teacher dropdown `.btn-group`
/// containing a `mailto:` link.
String? parseTeacherEmail(Element? teacherGroup) {
  if (teacherGroup == null) return null;
  for (final selector in const ['ul.dropdown-menu a[href]', 'a[href]']) {
    for (final link in teacherGroup.querySelectorAll(selector)) {
      final email = parseTeacherEmailFromHref(link.attributes['href']);
      if (email != null) return email;
    }
  }
  return null;
}

/// Extracts an email address from a `mailto:` href, stripping query parameters.
String? parseTeacherEmailFromHref(String? rawHref) {
  if (rawHref == null) return null;
  final trimmed = rawHref.trim();
  if (trimmed.length <= 'mailto:'.length) return null;
  if (!trimmed.toLowerCase().startsWith('mailto:')) return null;

  var address = trimmed.substring('mailto:'.length);
  final queryStart = address.indexOf('?');
  if (queryStart != -1) {
    address = address.substring(0, queryStart);
  }
  try {
    address = Uri.decodeComponent(address);
  } on ArgumentError {
    // Keep the raw address if percent-decoding fails.
  }
  address = address.trim();
  if (address.isEmpty || !address.contains('@')) return null;
  return address;
}

/// Extracts the Conversations receiver ID (e.g. `l-105044`) from a teacher
/// dropdown `.btn-group` containing a `nachrichten.php?to[]=<base64>` link.
///
/// SPH occasionally appends a stray `}` to the `to[]` query value (e.g.
/// `nachrichten.php?to[]=bC0xMDUwNDQ=}`), which is stripped before decoding.
String? parseTeacherConversationReceiverId(Element? teacherGroup) {
  if (teacherGroup == null) return null;
  for (final selector in const [
    'ul.dropdown-menu a[href*="nachrichten.php"]',
    'a[href*="nachrichten.php"]',
  ]) {
    for (final link in teacherGroup.querySelectorAll(selector)) {
      final receiverId = parseConversationReceiverIdFromHref(
        link.attributes['href'],
      );
      if (receiverId != null) return receiverId;
    }
  }
  return null;
}

/// Decodes a Conversations receiver ID from a `nachrichten.php` href.
String? parseConversationReceiverIdFromHref(String? rawHref) {
  if (rawHref == null) return null;
  final trimmed = rawHref.trim();
  if (trimmed.isEmpty) return null;

  // Strip stray braces (observed in SPH markup as `to[]=bC0xMDUwNDQ=}`) before
  // parsing so `Uri.tryParse` accepts the query string.
  final sanitized = trimmed.replaceAll('}', '');
  final uri = Uri.tryParse(sanitized);
  if (uri == null) return null;

  if (!uri.path.toLowerCase().endsWith('nachrichten.php')) return null;

  final rawTo =
      uri.queryParametersAll['to[]']?.firstOrNull ??
      uri.queryParametersAll['to']?.firstOrNull;
  if (rawTo == null) return null;

  return _decodeReceiverId(rawTo);
}

String? _decodeReceiverId(String raw) {
  final value = raw.replaceAll('}', '').trim();
  if (value.isEmpty) return null;

  if (_receiverIdPattern.hasMatch(value)) {
    return value;
  }

  try {
    final normalized = base64.normalize(
      value.replaceAll(' ', '+').replaceAll('-', '+').replaceAll('_', '/'),
    );
    final decoded = utf8
        .decode(base64.decode(normalized), allowMalformed: false)
        .trim();
    if (_receiverIdPattern.hasMatch(decoded)) {
      return decoded;
    }
  } on FormatException {
    return null;
  }

  return null;
}
