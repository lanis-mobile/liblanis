// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'teacher_parser.dart';

// **************************************************************************
// CacheGenerator
// **************************************************************************

mixin _$TimetableTeacherParserCache on CacheHost {
  _TimetableTeacherParserCached get cached =>
      _TimetableTeacherParserCached(this as TimetableTeacherParser);
}

class _TimetableTeacherParserCached {
  final TimetableTeacherParser _owner;
  _TimetableTeacherParserCached(this._owner);
  Future<MaybeCacheResult<TeacherTimetableOverview>> getHome({
    CacheReadPolicy? cachePolicy,
  }) => _owner.cacheService.execute(
    accountId: _owner.cacheAccountId,
    request: TimetableTeacherParserCacheRequests.getHome(),
    load: () => _owner._getHome(),
    policy: cachePolicy,
  );
  Future<MaybeCacheResult<TeacherTimetablePlan>> getTimetable(
    TeacherTimetableReference reference, {
    CacheReadPolicy? cachePolicy,
  }) => _owner.cacheService.execute(
    accountId: _owner.cacheAccountId,
    request: TimetableTeacherParserCacheRequests.getTimetable(reference),
    load: () => _owner._getTimetable(reference),
    policy: cachePolicy,
  );
}

abstract final class TimetableTeacherParserCacheRequests {
  static CacheRequest<TeacherTimetableOverview> getHome() => CacheRequest(
    operation: 'timetable.teacher.home',
    version: 1,
    arguments: {},
    appletLimit: Duration(microseconds: 3600000000),
    codec: CacheCodec<TeacherTimetableOverview>(
      id: 'package:liblanis/src/models/timetable_teacher.dart#TeacherTimetableOverview<>@1',
      encode: (value) => value.toJson(),
      decode: (json) =>
          TeacherTimetableOverview.fromJson(json as Map<String, dynamic>),
    ),
  );
  static CacheRequest<TeacherTimetablePlan> getTimetable(
    TeacherTimetableReference reference,
  ) => CacheRequest(
    operation: 'timetable.teacher.plan',
    version: 1,
    arguments: {
      'reference': {
        'type': 'package:liblanis/src/models/timetable_teacher.dart#TeacherTimetableReference<>',
        'value': reference.toJson(),
      },
    },
    appletLimit: Duration(microseconds: 3600000000),
    codec: CacheCodec<TeacherTimetablePlan>(
      id: 'package:liblanis/src/models/timetable_teacher.dart#TeacherTimetablePlan<>@1',
      encode: (value) => value.toJson(),
      decode: (json) =>
          TeacherTimetablePlan.fromJson(json as Map<String, dynamic>),
    ),
  );
}
