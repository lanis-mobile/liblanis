import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../exceptions.dart';

enum CacheStatus { network, cache }

enum CacheReadPolicy { networkFirst, cacheOnly, networkOnly }

enum CacheEntryState { available, missing, expired, incompatible, corrupt }

class MaybeCacheResult<T> {
  final T data;
  final CacheStatus cacheStatus;
  final DateTime fetchedAt;
  final DateTime responseAt;
  final DateTime expiresAt;

  const MaybeCacheResult({
    required this.data,
    required this.cacheStatus,
    required this.fetchedAt,
    required this.responseAt,
    required this.expiresAt,
  });

  MaybeCacheResult<R> map<R>(R Function(T value) transform) => MaybeCacheResult(
    data: transform(data),
    cacheStatus: cacheStatus,
    fetchedAt: fetchedAt,
    responseAt: responseAt,
    expiresAt: expiresAt,
  );
}

class CacheCodec<T> {
  final String id;
  final Object? Function(T value) encode;
  final T Function(Object? json) decode;
  const CacheCodec({
    required this.id,
    required this.encode,
    required this.decode,
  });
}

/// A detached, immutable description of a read. Construction never creates a session.
class CacheRequest<T> {
  static const maximumAge = Duration(days: 7);
  final String operation;
  final int version;
  final CacheCodec<T> codec;
  final Duration maxAge;

  /// Target refresh cadence; offline retention is independent.
  final Duration refreshInterval;
  final String argumentsJson;
  late final String argumentHash = sha256
      .convert(utf8.encode(argumentsJson))
      .toString();

  CacheRequest({
    required this.operation,
    this.version = 1,
    required this.codec,
    required Object? arguments,
    Duration? appletLimit,
    Duration? maxAge,
  }) : argumentsJson = jsonEncode(_canonical(arguments)),
       maxAge = [maximumAge, ?maxAge].reduce((a, b) => a < b ? a : b),
       refreshInterval = [
         maximumAge,
         ?appletLimit,
         ?maxAge,
       ].reduce((a, b) => a < b ? a : b) {
    if (operation.isEmpty ||
        version < 1 ||
        this.maxAge <= Duration.zero ||
        refreshInterval <= Duration.zero) {
      throw ArgumentError('Cache operation, version, and age must be positive');
    }
  }

  CacheKey keyFor(int accountId) => CacheKey(
    accountId: accountId,
    operation: operation,
    version: version,
    argumentHash: argumentHash,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheRequest<T> &&
          operation == other.operation &&
          version == other.version &&
          codec.id == other.codec.id &&
          maxAge == other.maxAge &&
          argumentHash == other.argumentHash;

  @override
  int get hashCode =>
      Object.hash(operation, version, codec.id, maxAge, argumentHash);

  static Object? _canonical(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) throw ArgumentError('Non-finite cache argument');
      return value;
    }
    if (value is List) return value.map(_canonical).toList();
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError('Cache argument maps require string keys');
        }
        sorted[entry.key as String] = _canonical(entry.value);
      }
      return sorted;
    }
    throw ArgumentError('Cache arguments must use explicit JSON codecs');
  }
}

class CacheKey {
  final int accountId;
  final String operation;
  final int version;
  final String argumentHash;
  const CacheKey({
    required this.accountId,
    required this.operation,
    required this.version,
    required this.argumentHash,
  });
  String get identity =>
      jsonEncode([accountId, operation, version, argumentHash]);
}

class CacheAvailability {
  final CacheEntryState state;
  final DateTime? fetchedAt;
  final DateTime? expiresAt;
  bool get isAvailable => state == CacheEntryState.available;
  const CacheAvailability(this.state, {this.fetchedAt, this.expiresAt});
}

class CacheUnavailableException extends LanisException {
  final CacheEntryState state;
  CacheUnavailableException(this.state)
    : super('Cache unavailable: ${state.name}');
  @override
  String get defaultMessage => 'Cache unavailable';
}
