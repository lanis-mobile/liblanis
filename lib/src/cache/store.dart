import 'types.dart';

typedef CacheGeneration = ({int global, int account});

class CacheRecord {
  final CacheKey key;
  final String codecId;
  final String json;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  const CacheRecord({
    required this.key,
    required this.codecId,
    required this.json,
    required this.fetchedAt,
    required this.expiresAt,
  });
}

abstract interface class CacheStore {
  CacheRecord? readCacheRecord(CacheKey key, {bool otherVersion = false});
  CacheGeneration cacheGeneration(int accountId);
  bool writeCacheRecord(CacheRecord record, CacheGeneration generation);
  bool removeCacheRecord(CacheKey key, CacheGeneration generation);
  void clearStructuredCache({int? accountId});
  int pruneExpiredCache(DateTime now, {int limit = 100});
  ({int entries, int bytes}) structuredCacheUsage({int? accountId});
}
