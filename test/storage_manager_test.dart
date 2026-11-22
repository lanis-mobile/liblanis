import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/liblanis.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _RecordingAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _StubChecker extends ConnectionChecker {
  _StubChecker(_RecordingAdapter adapter) : super(httpAdapter: adapter);

  @override
  Future<bool> testConnection() async => true;
}

class _StubSession extends LanisSession {
  _StubSession({
    required super.account,
    required super.config,
    required super.connectionChecker,
    required _RecordingAdapter adapter,
  }) {
    dio.httpClientAdapter = adapter;
  }

  @override
  Future<void> authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    throw StateError('Unit tests must not authenticate');
  }
}

StorageManager _createManager({
  required Directory tempDir,
  required _RecordingAdapter adapter,
  int? storageMaxBytes,
  Duration? storageMaxAge,
  Future<void> Function(String path)? onDownloaded,
}) {
  final config = LanisConfig(
    documentCacheDirectory: tempDir.path,
    storageEnabled: true,
    storageMaxBytes: storageMaxBytes,
    storageMaxAge: storageMaxAge,
  );
  const account = ClearTextAccount(
    localId: 1,
    schoolID: 5182,
    username: 'student',
    password: 'pw',
    schoolName: 'Test School',
  );
  final checker = _StubChecker(adapter);
  final session = _StubSession(
    account: account,
    config: config,
    connectionChecker: checker,
    adapter: adapter,
  );
  addTearDown(() async {
    await session.dispose();
    checker.dispose();
  });
  return StorageManager(
    session: session,
    config: config,
    accountId: 1,
    onDownloaded: onDownloaded,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('liblanis_storage_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('StorageManager.resolvePath', () {
    test('rejects path traversal, separators, and invalid filenames', () {
      final adapter = _RecordingAdapter(
        (_) async => ResponseBody.fromBytes(Uint8List(0), 200),
      );
      final manager = _createManager(tempDir: tempDir, adapter: adapter);

      for (final bad in [
        '',
        '.',
        '..',
        '../escape.pdf',
        '../../etc/passwd',
        '/etc/passwd',
        'nested/file.pdf',
        r'nested\file.pdf',
        r'..\escape.pdf',
        'bad\x00name.pdf',
      ]) {
        expect(
          () => manager.resolvePath(
            'https://start.schulportal.hessen.de/file',
            bad,
          ),
          throwsArgumentError,
          reason: 'Expected ArgumentError for "$bad"',
        );
      }
    });

    test('resolves valid filenames inside the document cache directory', () {
      final adapter = _RecordingAdapter(
        (_) async => ResponseBody.fromBytes(Uint8List(0), 200),
      );
      final manager = _createManager(tempDir: tempDir, adapter: adapter);
      final resolved = manager.resolvePath(
        'https://start.schulportal.hessen.de/file',
        'Grüße & test.pdf',
      );
      expect(
        p.isWithin(manager.getDocumentCacheDirectory().path, resolved),
        isTrue,
      );
      expect(p.basename(resolved), 'Grüße & test.pdf');
    });
  });

  group('StorageManager.downloadFile redirects', () {
    test('resolves relative and leading-slash redirects properly', () async {
      final adapter = _RecordingAdapter((options) async {
        if (options.uri.path == '/dir/start.php') {
          return ResponseBody.fromBytes(
            Uint8List(0),
            302,
            headers: {
              'location': ['/assets/logo.png?v=1'],
            },
          );
        }
        if (options.uri.toString() ==
            'https://start.schulportal.hessen.de/assets/logo.png?v=1') {
          return ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200);
        }
        throw StateError('Unexpected URI: ${options.uri}');
      });
      final manager = _createManager(tempDir: tempDir, adapter: adapter);

      final path = await manager.downloadFile(
        'https://start.schulportal.hessen.de/dir/start.php',
        'logo.png',
        followRedirects: true,
      );

      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.uri.toString(),
        'https://start.schulportal.hessen.de/assets/logo.png?v=1',
      );
    });

    test('allows redirects to *.schulportal.hessen.de', () async {
      final adapter = _RecordingAdapter((options) async {
        if (options.uri.host == 'start.schulportal.hessen.de') {
          return ResponseBody.fromBytes(
            Uint8List(0),
            302,
            headers: {
              'location': ['https://cdn.schulportal.hessen.de/img/school.png'],
            },
          );
        }
        if (options.uri.toString() ==
            'https://cdn.schulportal.hessen.de/img/school.png') {
          return ResponseBody.fromBytes(Uint8List.fromList([9, 8, 7]), 200);
        }
        throw StateError('Unexpected URI: ${options.uri}');
      });
      final manager = _createManager(tempDir: tempDir, adapter: adapter);

      final path = await manager.downloadFile(
        'https://start.schulportal.hessen.de/logo.php',
        'school.png',
        followRedirects: true,
      );

      expect(File(path).readAsBytesSync(), [9, 8, 7]);
      expect(adapter.requests, hasLength(2));
    });

    test(
      'refuses external, lookalike, and non-HTTPS redirects without following',
      () async {
        for (final badLocation in [
          'https://evil.example/logo.png',
          'https://evil-schulportal.hessen.de/logo.png',
          'http://start.schulportal.hessen.de/logo.png',
          'file:///etc/passwd',
          '   ',
        ]) {
          final adapter = _RecordingAdapter((options) async {
            return ResponseBody.fromBytes(
              Uint8List(0),
              302,
              headers: {
                'location': [badLocation],
              },
            );
          });
          final manager = _createManager(tempDir: tempDir, adapter: adapter);

          await expectLater(
            () => manager.downloadFile(
              'https://start.schulportal.hessen.de/logo.php?case=${Uri.encodeComponent(badLocation)}',
              'logo.png',
              followRedirects: true,
            ),
            throwsA(isA<NetworkException>()),
            reason: 'Expected NetworkException for redirect "$badLocation"',
          );
          expect(
            adapter.requests,
            hasLength(1),
            reason: 'Must not issue second request for "$badLocation"',
          );
        }
      },
    );
  });

  group('StorageManager._enforceLimits', () {
    test(
      'evicts older files but preserves the just-downloaded file even if it exceeds storageMaxBytes',
      () async {
        final downloadedCallbacks = <String>[];
        final adapter = _RecordingAdapter((options) async {
          if (options.uri.path == '/old.bin') {
            return ResponseBody.fromBytes(Uint8List(10), 200);
          }
          return ResponseBody.fromBytes(Uint8List(20), 200);
        });
        final manager = _createManager(
          tempDir: tempDir,
          adapter: adapter,
          storageMaxBytes: 15,
          onDownloaded: (path) async => downloadedCallbacks.add(path),
        );

        final oldPath = await manager.downloadFile(
          'https://start.schulportal.hessen.de/old.bin',
          'old.bin',
        );
        // Backdate old file so eviction order is deterministic.
        File(oldPath).setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 5)),
        );

        final newPath = await manager.downloadFile(
          'https://start.schulportal.hessen.de/new.bin',
          'new.bin',
        );

        expect(File(oldPath).existsSync(), isFalse);
        expect(File(newPath).existsSync(), isTrue);
        expect(File(newPath).lengthSync(), 20);
        expect(downloadedCallbacks, contains(newPath));
      },
    );
  });
}
