import 'dart:convert';

import '../applets/definition.dart';
import '../applets/file_distribution/parser.dart';
import '../applets/substitutions/parser.dart';
import '../applets/timetable/parser.dart';
import '../applets/timetable/parent_parser.dart';
import '../database/database.dart';
import '../models/account_types.dart';
import '../models/file_distribution.dart';
import '../models/substitution.dart';
import '../models/timetable.dart';
import '../models/timetable_parent.dart';
import 'service.dart';
import 'store.dart';
import 'types.dart';

/// UI-independent registration of an applet home and its detached cache request.
class CachedAppletHome<T> {
  final AppletMeta applet;
  final AccountType accountType;
  final CacheRequest<T> Function() request;
  const CachedAppletHome({
    required this.applet,
    required this.accountType,
    required this.request,
  });

  Future<bool> isAvailable(CacheService cache, int accountId) =>
      cache.isCacheAvailableFor(accountId: accountId, request: request());
  Future<MaybeCacheResult<T>> read(CacheService cache, int accountId) =>
      cache.readCacheFor(accountId: accountId, request: request());
}

abstract final class CachedAppletHomes {
  static final List<CachedAppletHome<dynamic>> all = List.unmodifiable([
    CachedAppletHome<TimeTable>(
      applet: Applets.timetable,
      accountType: AccountType.student,
      request: TimetableStudentParserCacheRequests.getHome,
    ),
    CachedAppletHome<ParentTimetableHome>(
      applet: Applets.timetable,
      accountType: AccountType.parent,
      request: TimetableParentParserCacheRequests.getHome,
    ),
    for (final type in AccountType.values)
      CachedAppletHome<SubstitutionPlan>(
        applet: Applets.substitutions,
        accountType: type,
        request: SubstitutionsParserCacheRequests.getHome,
      ),
    for (final type in AccountType.values)
      CachedAppletHome<FileDistributionHome>(
        applet: Applets.fileDistribution,
        accountType: type,
        request: FileDistributionParserCacheRequests.getHome,
      ),
  ]);

  static CachedAppletHome<dynamic>? find(String applet, AccountType? type) =>
      all
          .where(
            (home) =>
                home.applet.appletPhpUrl == applet && home.accountType == type,
          )
          .firstOrNull;

  /// Import compatible timetable snapshots only. Legacy substitutions may already
  /// be destructively filtered, so cannot satisfy an unfiltered cache operation.
  static Future<void> migrateLegacyTimetables(
    LanisDatabase database, {
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().toUtc();
    final accounts = await database.listAccounts();
    for (final row in database.listAppletOfflineData()) {
      if (row.appletId != Applets.timetable.appletPhpUrl) continue;
      final account = accounts
          .where((a) => a.localId == row.accountId)
          .firstOrNull;
      final home = find(row.appletId, account?.accountType);
      if (home == null) continue;
      final request = home.request();
      try {
        if (request.version != 1 ||
            database.readCacheRecord(request.keyFor(row.accountId)) != null) {
          continue;
        }
        final legacy = database.getAppletOfflineData(
          accountId: row.accountId,
          appletId: row.appletId,
        );
        if (legacy == null) continue;
        final expiry = legacy.timestamp.toUtc().add(request.maxAge);
        if (!now.isBefore(expiry)) continue;
        // Invalid legacy JSON is ignored; it never becomes an available home.
        final decoded = jsonDecode(legacy.json) as Map<String, dynamic>;
        if (home.accountType == AccountType.student &&
            (decoded['hours'] is! List ||
                (decoded['planForAll'] is! List &&
                    decoded['planForOwn'] is! List))) {
          continue;
        }
        final generation = database.cacheGeneration(row.accountId);
        final value = home.accountType == AccountType.student
            ? TimeTable.fromJson(decoded)
            : ParentTimetableHome.fromJson(decoded);
        database.writeCacheRecord(
          CacheRecord(
            key: request.keyFor(row.accountId),
            codecId: request.codec.id,
            json: jsonEncode(value),
            fetchedAt: legacy.timestamp.toUtc(),
            expiresAt: expiry,
          ),
          generation,
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      }
    }
  }
}
