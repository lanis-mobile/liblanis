import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../exceptions.dart';
import '../session/session.dart';

typedef StoragePathLayout =
    String Function({
      required String cacheRoot,
      required int accountId,
      required String urlHash,
      required String filename,
    });

/// Configurable document/file cache backed by the session Dio client.
class StorageManager {
  final LanisSession session;
  final LanisConfig config;
  final int accountId;

  /// Override how cache relative paths are built.
  final StoragePathLayout? pathLayout;

  /// Optional hook after a successful download.
  final Future<void> Function(String path)? onDownloaded;

  /// Optional existence check override.
  final Future<bool> Function(String path)? existsOverride;

  StorageManager({
    required this.session,
    required this.config,
    required this.accountId,
    this.pathLayout,
    this.onDownloaded,
    this.existsOverride,
  });

  String get _cacheRoot {
    final root = config.documentCacheDirectory;
    if (root == null || root.isEmpty) {
      throw StorageNotConfiguredException();
    }
    return root;
  }

  Directory getDocumentCacheDirectory() {
    if (!config.storageEnabled) {
      throw StorageNotConfiguredException('Document storage is disabled');
    }
    final dir = Directory(p.join(_cacheRoot, '$accountId', 'document_cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  String generateUniqueHash(String source) {
    final digest = sha256.convert(utf8.encode(source));
    return digest
        .toString()
        .replaceAll(RegExp(r'[^A-z0-9]'), '')
        .substring(0, 12);
  }

  static String _validateFilename(String filename) {
    if (filename.isEmpty ||
        filename == '.' ||
        filename == '..' ||
        filename.contains('\x00') ||
        filename.contains('/') ||
        filename.contains(r'\')) {
      throw ArgumentError.value(
        filename,
        'filename',
        'Invalid cache filename',
      );
    }
    return filename;
  }

  static bool _isAllowedRedirectHost(String originalHost, String targetHost) {
    final normalizedTarget = targetHost.toLowerCase();
    if (normalizedTarget.isEmpty) return false;
    final normalizedOriginal = originalHost.toLowerCase();
    return normalizedTarget == normalizedOriginal ||
        normalizedTarget == 'schulportal.hessen.de' ||
        normalizedTarget.endsWith('.schulportal.hessen.de');
  }

  static Uri _resolveRedirectUri(Uri baseUri, String location) {
    final trimmed = location.trim();
    if (trimmed.isEmpty) {
      throw NetworkException('Empty redirect location');
    }
    final Uri resolved;
    try {
      resolved = baseUri.resolve(trimmed);
    } on FormatException catch (error, stack) {
      Error.throwWithStackTrace(
        NetworkException.fromError(error, stack),
        stack,
      );
    }
    if (resolved.scheme != 'https' ||
        !_isAllowedRedirectHost(baseUri.host, resolved.host)) {
      throw NetworkException('Refusing untrusted redirect location: $location');
    }
    return resolved;
  }

  String resolvePath(String url, String filename) {
    final safeFilename = _validateFilename(filename);
    final urlHash = generateUniqueHash(url);
    final cacheRoot = p.normalize(getDocumentCacheDirectory().path);
    if (pathLayout != null) {
      return pathLayout!(
        cacheRoot: cacheRoot,
        accountId: accountId,
        urlHash: urlHash,
        filename: safeFilename,
      );
    }
    final resolved = p.normalize(p.join(cacheRoot, urlHash, safeFilename));
    if (!p.isWithin(cacheRoot, resolved)) {
      throw ArgumentError.value(
        filename,
        'filename',
        'Resolved path escapes document cache directory',
      );
    }
    return resolved;
  }

  Future<bool> doesFileExist(String url, String filename) async {
    final filePath = resolvePath(url, filename);
    if (existsOverride != null) {
      return existsOverride!(filePath);
    }
    return File(filePath).existsSync();
  }

  Future<String> downloadFile(
    String url,
    String filename, {
    bool followRedirects = false,
  }) async {
    if (!config.storageEnabled) {
      throw StorageNotConfiguredException('Document storage is disabled');
    }

    final savePath = resolvePath(url, filename);
    final folder = Directory(p.dirname(savePath));
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    if (await doesFileExist(url, filename)) {
      return savePath;
    }

    var response = await session.dio.get(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (status) =>
            status != null && (status == 200 || status == 302),
      ),
    );

    if (response.statusCode == 302 && followRedirects) {
      final location = response.headers.value('location');
      if (location != null) {
        final baseUri = response.realUri.hasScheme
            ? response.realUri
            : Uri.parse(url);
        final redirectUri = _resolveRedirectUri(baseUri, location);
        response = await session.dio.getUri(
          redirectUri,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: false,
            validateStatus: (status) => status == 200,
          ),
        );
      }
    }

    if (response.statusCode != 200 || response.data is! List<int>) {
      throw NetworkException(
        'Download failed with status ${response.statusCode}',
      );
    }

    final file = File(savePath);
    final raf = file.openSync(mode: FileMode.write);
    var closed = false;
    try {
      raf.writeFromSync(response.data as List<int>);
      await raf.close();
      closed = true;
    } catch (_) {
      if (!closed) {
        await raf.close();
      }
      if (file.existsSync()) {
        file.deleteSync();
      }
      rethrow;
    }

    await _enforceLimits(protectPath: savePath);
    if (onDownloaded != null) {
      await onDownloaded!(savePath);
    }
    return savePath;
  }

  Future<void> deleteFilesOlderThan(
    Duration duration, {
    String? protectPath,
  }) async {
    final normalizedProtect = protectPath == null
        ? null
        : p.normalize(protectPath);
    final tempDir = getDocumentCacheDirectory();
    for (final entity in tempDir.listSync(recursive: true)) {
      if (entity is File) {
        if (normalizedProtect != null &&
            p.normalize(entity.path) == normalizedProtect) {
          continue;
        }
        final stat = entity.statSync();
        if (DateTime.now().difference(stat.modified) > duration) {
          entity.deleteSync();
        }
      }
    }
  }

  Future<void> clear() async {
    final dir = getDocumentCacheDirectory();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  Future<void> _enforceLimits({String? protectPath}) async {
    if (config.storageMaxAge != null) {
      await deleteFilesOlderThan(
        config.storageMaxAge!,
        protectPath: protectPath,
      );
    }
    final maxBytes = config.storageMaxBytes;
    if (maxBytes == null) return;

    final normalizedProtect = protectPath == null
        ? null
        : p.normalize(protectPath);
    final dir = getDocumentCacheDirectory();
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => (file: f, modified: f.statSync().modified))
        .toList()
      ..sort((a, b) => a.modified.compareTo(b.modified));

    var total = files.fold<int>(0, (sum, e) => sum + e.file.lengthSync());
    for (final entry in files) {
      if (total <= maxBytes) break;
      if (normalizedProtect != null &&
          p.normalize(entry.file.path) == normalizedProtect) {
        continue;
      }
      total -= entry.file.lengthSync();
      entry.file.deleteSync();
    }
  }
}
