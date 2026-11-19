// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parser.dart';

// **************************************************************************
// CacheGenerator
// **************************************************************************

mixin _$SubstitutionsParserCache on CacheHost {
  _SubstitutionsParserCached get cached =>
      _SubstitutionsParserCached(this as SubstitutionsParser);
}

class _SubstitutionsParserCached {
  final SubstitutionsParser _owner;
  _SubstitutionsParserCached(this._owner);
  Future<MaybeCacheResult<SubstitutionPlan>> getHome({
    CacheReadPolicy? cachePolicy,
  }) => _owner.cacheService.execute(
    accountId: _owner.cacheAccountId,
    request: SubstitutionsParserCacheRequests.getHome(),
    load: () => _owner._getHome(),
    policy: cachePolicy,
  );
}

abstract final class SubstitutionsParserCacheRequests {
  static CacheRequest<SubstitutionPlan> getHome() => CacheRequest(
    operation: 'substitutions.home',
    version: 1,
    arguments: {},
    appletLimit: Duration(microseconds: 600000000),
    codec: CacheCodec<SubstitutionPlan>(
      id: 'package:liblanis/src/models/substitution.dart#SubstitutionPlan<>@1',
      encode: (value) => value.toJson(),
      decode: (json) => SubstitutionPlan.fromJson(json as Map<String, dynamic>),
    ),
  );
}
