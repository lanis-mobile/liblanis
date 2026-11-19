// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parser.dart';

// **************************************************************************
// CacheGenerator
// **************************************************************************

mixin _$TimetableStudentParserCache on CacheHost {
  _TimetableStudentParserCached get cached =>
      _TimetableStudentParserCached(this as TimetableStudentParser);
}

class _TimetableStudentParserCached {
  final TimetableStudentParser _owner;
  _TimetableStudentParserCached(this._owner);
  Future<MaybeCacheResult<TimeTable>> getHome({CacheReadPolicy? cachePolicy}) =>
      _owner.cacheService.execute(
        accountId: _owner.cacheAccountId,
        request: TimetableStudentParserCacheRequests.getHome(),
        load: () => _owner._getHome(),
        policy: cachePolicy,
      );
}

abstract final class TimetableStudentParserCacheRequests {
  static CacheRequest<TimeTable> getHome() => CacheRequest(
    operation: 'timetable.student.home',
    version: 1,
    arguments: {},
    appletLimit: Duration(microseconds: 3600000000),
    codec: CacheCodec<TimeTable>(
      id: 'package:liblanis/src/models/timetable.dart#TimeTable<>@1',
      encode: (value) => value.toJson(),
      decode: (json) => TimeTable.fromJson(json as Map<String, dynamic>),
    ),
  );
}
