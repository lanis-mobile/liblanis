import 'dart:async';
import 'dart:convert';

import '../exceptions.dart';
import '../cache/annotation.dart';
import '../cache/service.dart';
import '../cache/types.dart';
import '../lanis_client.dart';
import 'applet_context.dart';
import 'definition.dart';

enum FetcherStatus { fetching, done, error }

enum ContentStatus { online, offline }

class ExceptionWithStackTrace {
  final Object exception;
  final StackTrace stackTrace;

  ExceptionWithStackTrace({required this.exception, required this.stackTrace});
}

class FetcherResponse<T> {
  final FetcherStatus status;
  final T? content;
  final ContentStatus contentStatus;
  final DateTime fetchedAt;
  final ExceptionWithStackTrace? error;
  final DateTime? responseAt;
  final DateTime? expiresAt;

  FetcherResponse({
    required this.status,
    this.contentStatus = ContentStatus.online,
    required this.error,
    this.content,
    DateTime? fetchedAt,
    this.responseAt,
    this.expiresAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();
}

class AppletResponseStream<T> extends StreamView<FetcherResponse<T>> {
  final FetcherResponse<T>? Function() _valueGetter;

  AppletResponseStream(super.stream, this._valueGetter);

  FetcherResponse<T> get value => _valueGetter()!;
}

/// Data presentation contract shared by online parsers and local-only readers.
abstract interface class AppletDataSource<T> {
  Stream<FetcherResponse<T>> get stream;
  FetcherResponse<T>? get latestResponse;
  void startAutoRefresh();
  void stopAutoRefresh();
  Future<void> fetchData({bool forceRefresh = false, bool secondTry = false});
}

/// Base class for SPH applet parsers (Dart-only, no Flutter).
class AppletParser<T> implements CacheHost, AppletDataSource<T> {
  @override
  CacheService get cacheService => CacheService.shared(ctx.database);
  @override
  int get cacheAccountId => ctx.accountId;
  final AppletContext ctx;
  final AppletMeta appletMeta;
  final Future<bool> Function() isConnected;

  final StreamController<FetcherResponse<T>> _controller =
      StreamController<FetcherResponse<T>>.broadcast();
  FetcherResponse<T> _latestResponse = FetcherResponse(
    status: FetcherStatus.fetching,
    error: null,
  );
  late final AppletResponseStream<T> _stream = AppletResponseStream<T>(
    _controller.stream,
    () => _latestResponse,
  );
  bool isEmpty = true;
  Timer? _refreshTimer;
  Timer? _cacheExpiryTimer;

  @override
  AppletResponseStream<T> get stream => _stream;

  @override
  FetcherResponse<T>? get latestResponse => _latestResponse;

  AppletParser(this.ctx, this.appletMeta, {required this.isConnected});

  /// Starts periodic refresh. Safe to call repeatedly.
  @override
  void startAutoRefresh() {
    if (_refreshTimer != null || _controller.isClosed) return;
    _refreshTimer = Timer.periodic(appletMeta.refreshInterval, timerCallback);
    _scheduleCacheExpiry();
  }

  /// Stops periodic refresh while the applet is off-screen.
  @override
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _cacheExpiryTimer?.cancel();
  }

  void timerCallback(Timer timer) async {
    if (homeCacheRequest != null || await isConnected()) {
      await fetchData(forceRefresh: true);
    }
  }

  CacheRequest<T>? get homeCacheRequest => null;

  Future<MaybeCacheResult<T>> loadCachedHome({CacheReadPolicy? policy}) =>
      cacheService.execute(
        accountId: cacheAccountId,
        request: homeCacheRequest!,
        load: getHome,
        policy: policy,
      );

  T presentCachedHome(T value) => value;

  Future<void> fetchCachedData({CacheReadPolicy? policy}) async {
    if (_controller.isClosed) return;
    var previous = latestResponse;
    var valid = previous?.expiresAt?.isAfter(DateTime.now()) ?? false;
    if (!valid && policy != CacheReadPolicy.cacheOnly) {
      try {
        final cached = await cacheService.readCacheFor(
          accountId: cacheAccountId,
          request: homeCacheRequest!,
        );
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.done,
            error: null,
            content: presentCachedHome(cached.data),
            contentStatus: ContentStatus.offline,
            fetchedAt: cached.fetchedAt,
            responseAt: cached.responseAt,
            expiresAt: cached.expiresAt,
          ),
        );
        previous = latestResponse;
        valid = true;
      } on CacheUnavailableException {
        // Continue with the network when this exact operation has no usable entry.
      } catch (error, stack) {
        _reportUnexpectedError(error, stack);
      }
    }
    if (_controller.isClosed) return;
    addResponse(
      FetcherResponse<T>(
        status: FetcherStatus.fetching,
        error: null,
        content: valid ? previous?.content : null,
        contentStatus: previous?.contentStatus ?? ContentStatus.online,
        fetchedAt: previous?.fetchedAt,
        expiresAt: previous?.expiresAt,
      ),
    );
    try {
      final result = await loadCachedHome(policy: policy);
      addResponse(
        FetcherResponse<T>(
          status: FetcherStatus.done,
          error: null,
          content: presentCachedHome(result.data),
          contentStatus: result.cacheStatus == CacheStatus.cache
              ? ContentStatus.offline
              : ContentStatus.online,
          fetchedAt: result.fetchedAt,
          responseAt: result.responseAt,
          expiresAt: result.expiresAt,
        ),
      );
      isEmpty = false;
    } catch (error, stack) {
      if (CacheService.isTransportFailure(error) &&
          valid &&
          previous?.content != null &&
          (previous?.expiresAt?.isAfter(DateTime.now()) ?? false)) {
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.done,
            content: previous!.content,
            contentStatus: ContentStatus.offline,
            fetchedAt: previous.fetchedAt,
            responseAt: DateTime.now(),
            expiresAt: previous.expiresAt,
            error: ExceptionWithStackTrace(exception: error, stackTrace: stack),
          ),
        );
        return;
      }
      _reportUnexpectedError(error, stack);
      addResponse(
        FetcherResponse<T>(
          status: FetcherStatus.error,
          contentStatus:
              error is CacheUnavailableException ||
                  CacheService.isTransportFailure(error)
              ? ContentStatus.offline
              : ContentStatus.online,
          error: ExceptionWithStackTrace(exception: error, stackTrace: stack),
        ),
      );
    }
  }

  void _scheduleCacheExpiry() {
    _cacheExpiryTimer?.cancel();
    final expiry = _latestResponse.expiresAt;
    if (_refreshTimer == null ||
        _latestResponse.content == null ||
        expiry == null) {
      return;
    }
    final delay = expiry.difference(DateTime.now());
    _cacheExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => fetchData(forceRefresh: true),
    );
  }

  void addResponse(FetcherResponse<T> data) {
    _latestResponse = data;
    _scheduleCacheExpiry();
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  void dispose() {
    stopAutoRefresh();
    _controller.close();
  }

  @override
  Future<void> fetchData({
    bool forceRefresh = false,
    bool secondTry = false,
  }) async {
    if (homeCacheRequest != null) {
      final expiry = _latestResponse.expiresAt;
      if (isEmpty ||
          forceRefresh ||
          _latestResponse.status == FetcherStatus.error ||
          (expiry != null && !DateTime.now().isBefore(expiry))) {
        await fetchCachedData();
      }
      return;
    }
    if (!(await isConnected())) {
      final previous = latestResponse;
      final expiry =
          previous?.expiresAt ??
          previous?.fetchedAt.add(CacheRequest.maximumAge);
      if (previous?.content != null &&
          expiry != null &&
          DateTime.now().isBefore(expiry)) {
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.done,
            error: null,
            content: previous!.content,
            contentStatus: ContentStatus.offline,
            fetchedAt: previous.fetchedAt,
            responseAt: DateTime.now(),
            expiresAt: expiry,
          ),
        );
        return;
      }
      if (previous?.content != null && expiry != null) {
        isEmpty = true;
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.error,
            contentStatus: ContentStatus.offline,
            error: ExceptionWithStackTrace(
              exception: CacheUnavailableException(CacheEntryState.expired),
              stackTrace: StackTrace.current,
            ),
          ),
        );
      }
      if (isEmpty) {
        final offlineData = ctx.database.getAppletOfflineData(
          accountId: ctx.accountId,
          appletId: appletMeta.appletPhpUrl,
        );
        if (offlineData != null &&
            DateTime.now().isBefore(
              offlineData.timestamp.add(CacheRequest.maximumAge),
            )) {
          addResponse(
            FetcherResponse(
              status: FetcherStatus.done,
              contentStatus: ContentStatus.offline,
              content: typeFromJson(offlineData.json),
              fetchedAt: offlineData.timestamp,
              expiresAt: offlineData.timestamp.add(CacheRequest.maximumAge),
              error: null,
            ),
          );
        } else {
          addResponse(
            FetcherResponse(
              status: FetcherStatus.error,
              contentStatus: ContentStatus.offline,
              error: null,
            ),
          );
        }
      }

      return;
    }

    if (isEmpty || forceRefresh) {
      final previous = latestResponse;
      final expiry =
          previous?.expiresAt ??
          previous?.fetchedAt.add(CacheRequest.maximumAge);
      final valid =
          previous?.content != null &&
          expiry != null &&
          DateTime.now().isBefore(expiry);
      addResponse(
        FetcherResponse<T>(
          status: FetcherStatus.fetching,
          error: null,
          content: valid ? previous?.content : null,
          contentStatus: previous?.contentStatus ?? ContentStatus.online,
          fetchedAt: previous?.fetchedAt,
          expiresAt: expiry,
        ),
      );

      try {
        final data = await _getHome();
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.done,
            content: data,
            expiresAt: DateTime.now().add(CacheRequest.maximumAge),
            error: null,
          ),
        );
        isEmpty = false;
      } catch (ex, stack) {
        if (CacheService.isTransportFailure(ex)) {
          final usable = valid && expiry.isAfter(DateTime.now());
          addResponse(
            FetcherResponse<T>(
              status: usable ? FetcherStatus.done : FetcherStatus.error,
              content: usable ? previous?.content : null,
              contentStatus: ContentStatus.offline,
              fetchedAt: previous?.fetchedAt,
              responseAt: DateTime.now(),
              expiresAt: expiry,
              error: ExceptionWithStackTrace(exception: ex, stackTrace: stack),
            ),
          );
          return;
        }
        if (!secondTry) {
          try {
            await ctx.session.authenticate();
          } catch (authError, authStack) {
            _reportUnexpectedError(authError, authStack);
            addResponse(
              FetcherResponse<T>(
                status: FetcherStatus.error,
                error: ExceptionWithStackTrace(
                  exception: authError,
                  stackTrace: authStack,
                ),
              ),
            );
            return;
          }
          await fetchData(forceRefresh: true, secondTry: true);
          return;
        }
        _reportUnexpectedError(ex, stack);
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.error,
            error: ExceptionWithStackTrace(exception: ex, stackTrace: stack),
          ),
        );
      }
    }
  }

  void _reportUnexpectedError(Object error, StackTrace stackTrace) {
    if (!isUnexpectedParserError(error)) return;
    final handler = LanisClient.config?.onUnexpectedError;
    if (handler == null) return;
    try {
      handler(error, stackTrace, appletPhpUrl: appletMeta.appletPhpUrl);
    } catch (_) {
      // Host reporter must never break the fetch stream.
    }
  }

  Future<T> _getHome() async {
    final T value = await getHome();
    if (appletMeta.allowOffline) {
      ctx.database.setAppletOfflineData(
        accountId: ctx.accountId,
        appletId: appletMeta.appletPhpUrl,
        json: jsonEncode(value),
      );
    }
    return value;
  }

  T typeFromJson(String json) {
    throw UnimplementedError('Please add the required overrides in the parser');
  }

  Future<T> getHome() {
    throw UnimplementedError();
  }
}
