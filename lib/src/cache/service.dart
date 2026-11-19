import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../exceptions.dart';
import 'store.dart';
import 'types.dart';

/// Account-scoped typed caching. Local inspection and reads never construct a session.
class CacheService {
  static final _shared = Expando<CacheService>('liblanis cache');
  factory CacheService.shared(CacheStore store) =>
      _shared[store] ??= CacheService(store);
  final CacheStore store;
  final DateTime Function() _clock;
  final void Function(Object error, StackTrace stack)? onStorageError;
  final _pending = <String, Future<_Produced>>{};
  static final _zoneKey = Object();

  CacheService(this.store, {DateTime Function()? clock, this.onStorageError})
    : _clock = clock ?? DateTime.now;

  DateTime get _now => _clock().toUtc();
  _Execution? get _current => Zone.current[_zoneKey] as _Execution?;

  Future<CacheAvailability> inspectCacheFor<T>({
    required int accountId,
    required CacheRequest<T> request,
  }) async => _inspect(accountId, request).availability;

  Future<bool> isCacheAvailableFor<T>({
    required int accountId,
    required CacheRequest<T> request,
  }) async => _inspect(accountId, request).availability.isAvailable;

  _Inspection _inspect<T>(int accountId, CacheRequest<T> request) {
    final key = request.keyFor(accountId);
    CacheRecord? record;
    CacheRecord? older;
    try {
      record = store.readCacheRecord(key);
      if (record == null) {
        older = store.readCacheRecord(key, otherVersion: true);
      }
    } on FormatException {
      return const _Inspection(CacheAvailability(CacheEntryState.corrupt));
    } on TypeError {
      return const _Inspection(CacheAvailability(CacheEntryState.corrupt));
    } on ArgumentError {
      return const _Inspection(CacheAvailability(CacheEntryState.corrupt));
    }
    if (record == null) {
      return _Inspection(
        CacheAvailability(
          older == null
              ? CacheEntryState.missing
              : CacheEntryState.incompatible,
        ),
      );
    }
    final expiry = _earliest(
      record.expiresAt,
      record.fetchedAt.add(request.maxAge),
    );
    CacheAvailability state(CacheEntryState state) => CacheAvailability(
      state,
      fetchedAt: record!.fetchedAt,
      expiresAt: expiry,
    );
    if (record.codecId != request.codec.id) {
      return _Inspection(state(CacheEntryState.incompatible));
    }
    if (!_now.isBefore(expiry)) {
      return _Inspection(state(CacheEntryState.expired));
    }
    try {
      final value = request.codec.decode(jsonDecode(record.json));
      if (value == null) return _Inspection(state(CacheEntryState.corrupt));
    } catch (_) {
      return _Inspection(state(CacheEntryState.corrupt));
    }
    if (!_now.isBefore(expiry)) {
      return _Inspection(state(CacheEntryState.expired));
    }
    return _Inspection(
      state(CacheEntryState.available),
      _Produced(record.json, CacheStatus.cache, record.fetchedAt, expiry),
    );
  }

  Future<MaybeCacheResult<T>> readCacheFor<T>({
    required int accountId,
    required CacheRequest<T> request,
  }) async {
    final parent = _current;
    _checkAccount(parent, accountId);
    if (parent?.policy == CacheReadPolicy.networkOnly) {
      throw ConfigurationException(
        'A network-only operation cannot consume cached data',
      );
    }
    final inspected = _inspect(accountId, request);
    if (!inspected.availability.isAvailable) {
      throw CacheUnavailableException(inspected.availability.state);
    }
    return _result(request, inspected.produced!, parent);
  }

  Future<MaybeCacheResult<T>> execute<T>({
    required int accountId,
    required CacheRequest<T> request,
    required Future<T> Function() load,
    CacheReadPolicy? policy,
  }) async {
    final parent = _current;
    _checkAccount(parent, accountId);
    final effective = parent?.policy == CacheReadPolicy.networkOnly
        ? CacheReadPolicy.networkOnly
        : policy ?? parent?.policy ?? CacheReadPolicy.networkFirst;
    if (effective == CacheReadPolicy.cacheOnly) {
      return readCacheFor(accountId: accountId, request: request);
    }
    final key = request.keyFor(accountId);
    for (var current = parent; current != null; current = current.parent) {
      if (current.key == key.identity) {
        throw ConfigurationException('Recursive cache operation');
      }
    }
    final generation = store.cacheGeneration(accountId);
    final executionKey = jsonEncode([
      key.identity,
      request.codec.id,
      request.maxAge.inMicroseconds,
      effective.name,
      generation.global,
      generation.account,
    ]);
    var pending = _pending[executionKey];
    if (pending == null) {
      final context = _Execution(key.identity, accountId, effective, parent);
      pending = runZoned<Future<_Produced>>(
        () => _run(accountId, request, load, generation, context),
        zoneValues: {_zoneKey: context},
      );
      _pending[executionKey] = pending;
      // Handle completion on both paths without introducing an unhandled future.
      pending.then<void>(
        (_) => _pending.remove(executionKey),
        onError: (Object _, StackTrace _) {
          _pending.remove(executionKey);
        },
      );
    }
    try {
      return _result(request, await pending, parent);
    } catch (error, stack) {
      if (effective != CacheReadPolicy.networkFirst ||
          !isTransportFailure(error)) {
        rethrow;
      }
      final inspected = _inspect(accountId, request);
      if (inspected.availability.isAvailable) {
        return _result(request, inspected.produced!, parent);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<_Produced> _run<T>(
    int accountId,
    CacheRequest<T> request,
    Future<T> Function() load,
    CacheGeneration generation,
    _Execution context,
  ) async {
    final value = await load();
    var fetchedAt = _now;
    var status = CacheStatus.network;
    for (final dependency in context.dependencies) {
      fetchedAt = _earliest(fetchedAt, dependency.fetchedAt);
      if (dependency.status == CacheStatus.cache) status = CacheStatus.cache;
    }
    var expiry = fetchedAt.add(request.maxAge);
    for (final dependency in context.dependencies) {
      expiry = _earliest(expiry, dependency.expiresAt);
    }
    if (!_now.isBefore(expiry)) {
      throw CacheUnavailableException(CacheEntryState.expired);
    }
    // Serialization is part of the read contract, so codec bugs cannot trigger fallback.
    final json = value == null ? null : jsonEncode(request.codec.encode(value));
    if (value != null && request.codec.decode(jsonDecode(json!)) == null) {
      throw StateError('A non-null cache value decoded as null');
    }
    try {
      if (json == null) {
        store.removeCacheRecord(request.keyFor(accountId), generation);
      } else {
        store.writeCacheRecord(
          CacheRecord(
            key: request.keyFor(accountId),
            codecId: request.codec.id,
            json: json,
            fetchedAt: fetchedAt,
            expiresAt: expiry,
          ),
          generation,
        );
        store.pruneExpiredCache(_now);
      }
    } catch (error, stack) {
      try {
        onStorageError?.call(error, stack);
      } catch (_) {
        /* Reporting cannot fail a read. */
      }
    }
    return _Produced(json, status, fetchedAt, expiry);
  }

  MaybeCacheResult<T> _result<T>(
    CacheRequest<T> request,
    _Produced produced,
    _Execution? parent,
  ) {
    final data = produced.json == null
        ? null as T
        : request.codec.decode(jsonDecode(produced.json!));
    final responseAt = _now;
    if (!responseAt.isBefore(produced.expiresAt)) {
      throw CacheUnavailableException(CacheEntryState.expired);
    }
    parent?.dependencies.add(produced);
    return MaybeCacheResult(
      data: data,
      cacheStatus: produced.status,
      fetchedAt: produced.fetchedAt,
      responseAt: responseAt,
      expiresAt: produced.expiresAt,
    );
  }

  void clear({int? accountId}) =>
      store.clearStructuredCache(accountId: accountId);

  static bool isTransportFailure(Object error) =>
      error is NoConnectionException ||
      error is LanisDownException ||
      error is SocketException ||
      error is HttpException ||
      (error is http.ClientException &&
          error is! http.RequestAbortedException) ||
      (error is NetworkException &&
          error.originalError != null &&
          isTransportFailure(error.originalError!)) ||
      (error is DioException &&
          error.type == DioExceptionType.unknown &&
          error.error != null &&
          isTransportFailure(error.error!)) ||
      (error is DioException &&
          error.type == DioExceptionType.badResponse &&
          const {408, 502, 503, 504}.contains(error.response?.statusCode)) ||
      (error is DioException &&
          const {
            DioExceptionType.connectionError,
            DioExceptionType.connectionTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.sendTimeout,
          }.contains(error.type));

  static void _checkAccount(_Execution? parent, int accountId) {
    if (parent != null && parent.accountId != accountId) {
      throw ConfigurationException(
        'Nested cache reads must use the same account',
      );
    }
  }

  static DateTime _earliest(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
}

class _Inspection {
  final CacheAvailability availability;
  final _Produced? produced;
  const _Inspection(this.availability, [this.produced]);
}

class _Produced {
  final String? json;
  final CacheStatus status;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  const _Produced(this.json, this.status, this.fetchedAt, this.expiresAt);
}

class _Execution {
  final String key;
  final int accountId;
  final CacheReadPolicy policy;
  final _Execution? parent;
  final dependencies = <_Produced>[];
  _Execution(this.key, this.accountId, this.policy, this.parent);
}
