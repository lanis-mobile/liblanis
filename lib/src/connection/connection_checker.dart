import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

enum ConnectionStatus { connected, disconnected }

/// Probes SPH reachability and tracks session Dio outcomes.
class ConnectionChecker {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  late final Dio dio;
  DateTime lastRequest = DateTime.now().subtract(const Duration(seconds: 5));
  final HttpClientAdapter? _sharedAdapter;

  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  ConnectionChecker({HttpClientAdapter? httpAdapter})
    : _sharedAdapter = httpAdapter {
    dio = Dio(
      BaseOptions(
        validateStatus: (status) => status != null,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    if (httpAdapter != null) {
      dio.httpClientAdapter = httpAdapter;
    }
    unawaited(testConnection());
  }

  set status(ConnectionStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    lastRequest = DateTime.now();
  }

  ConnectionStatus get status => _status;

  Future<bool> get connected async {
    if (DateTime.now().difference(lastRequest) > const Duration(seconds: 1)) {
      await testConnection();
    }
    return _status == ConnectionStatus.connected;
  }

  Future<bool> testConnection() async {
    try {
      final response = await dio.post(
        'https://start.schulportal.hessen.de/ajax_login.php',
      );
      if (response.statusCode == 503) {
        status = ConnectionStatus.disconnected;
        return false;
      }
      status = ConnectionStatus.connected;
      return true;
    } catch (_) {
      status = ConnectionStatus.disconnected;
      return false;
    }
  }

  void dispose() {
    _statusController.close();
    // Shared Cronet/native adapters must not be closed with this Dio.
    if (_sharedAdapter != null &&
        identical(dio.httpClientAdapter, _sharedAdapter)) {
      dio.httpClientAdapter = IOHttpClientAdapter();
    }
    dio.close(force: true);
  }
}
