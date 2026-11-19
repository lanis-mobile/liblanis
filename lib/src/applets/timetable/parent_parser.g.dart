// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parent_parser.dart';

// **************************************************************************
// CacheGenerator
// **************************************************************************

mixin _$TimetableParentParserCache on CacheHost {
  _TimetableParentParserCached get cached =>
      _TimetableParentParserCached(this as TimetableParentParser);
}

class _TimetableParentParserCached {
  final TimetableParentParser _owner;
  _TimetableParentParserCached(this._owner);
  Future<MaybeCacheResult<ParentTimetableHome>> getHome({
    CacheReadPolicy? cachePolicy,
  }) => _owner.cacheService.execute(
    accountId: _owner.cacheAccountId,
    request: TimetableParentParserCacheRequests.getHome(),
    load: () => _owner._getHome(),
    policy: cachePolicy,
  );
  Future<MaybeCacheResult<ParentTimetableLoaded>> getTimetable(
    ParentTimetableReference reference, {
    CacheReadPolicy? cachePolicy,
  }) => _owner.cacheService.execute(
    accountId: _owner.cacheAccountId,
    request: TimetableParentParserCacheRequests.getTimetable(reference),
    load: () => _owner._getTimetable(reference),
    policy: cachePolicy,
  );
}

abstract final class TimetableParentParserCacheRequests {
  static CacheRequest<ParentTimetableHome> getHome() => CacheRequest(
    operation: 'timetable.parent.home',
    version: 1,
    arguments: {},
    appletLimit: Duration(microseconds: 3600000000),
    codec: CacheCodec<ParentTimetableHome>(
      id: 'package:liblanis/src/models/timetable_parent.dart#ParentTimetableHome<>@1',
      encode: (value) => value.toJson(),
      decode: (json) =>
          ParentTimetableHome.fromJson(json as Map<String, dynamic>),
    ),
  );
  static CacheRequest<ParentTimetableLoaded> getTimetable(
    ParentTimetableReference reference,
  ) => CacheRequest(
    operation: 'timetable.parent.plan',
    version: 1,
    arguments: {
      'reference': {
        'type':
            'package:liblanis/src/models/timetable_parent.dart#ParentTimetableReference<>',
        'value': reference.toJson(),
      },
    },
    appletLimit: Duration(microseconds: 3600000000),
    codec: CacheCodec<ParentTimetableLoaded>(
      id: 'package:liblanis/src/models/timetable_parent.dart#ParentTimetableLoaded<>@1',
      encode: (value) => value.toJson(),
      decode: (json) =>
          ParentTimetableLoaded.fromJson(json as Map<String, dynamic>),
    ),
  );
}
