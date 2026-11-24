// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parser.dart';

// **************************************************************************
// CacheGenerator
// **************************************************************************

mixin _$FileDistributionParserCache on CacheHost {
  _FileDistributionParserCached get cached =>
      _FileDistributionParserCached(this as FileDistributionParser);
}

class _FileDistributionParserCached {
  final FileDistributionParser _owner;
  _FileDistributionParserCached(this._owner);
  Future<MaybeCacheResult<FileDistributionHome>> getHome({
    CacheReadPolicy? cachePolicy,
  }) => _owner.cacheService.execute(
    accountId: _owner.cacheAccountId,
    request: FileDistributionParserCacheRequests.getHome(),
    load: () => _owner._getHome(),
    policy: cachePolicy,
  );
}

abstract final class FileDistributionParserCacheRequests {
  static CacheRequest<FileDistributionHome> getHome() => CacheRequest(
    operation: 'fileDistribution.home',
    version: 1,
    arguments: {},
    appletLimit: Duration(microseconds: 900000000),
    codec: CacheCodec<FileDistributionHome>(
      id: 'package:liblanis/src/models/file_distribution.dart#FileDistributionHome<>@1',
      encode: (value) => value.toJson(),
      decode: (json) =>
          FileDistributionHome.fromJson(json as Map<String, dynamic>),
    ),
  );
}
