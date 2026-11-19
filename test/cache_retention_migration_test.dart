import 'dart:io';
import 'package:liblanis/liblanis.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'extends existing pilot entries once, keeping fetch dates and other operation limits',
    () async {
      final directory = Directory.systemTemp.createTempSync('cache-retention-');
      final path = '${directory.path}/test.db';
      final secret = MemorySecretStore();
      var db = LanisDatabase.open(path: path, secretStore: secret);
      try {
        final account = await db.addAccount(
          schoolId: 1,
          schoolName: 'Test',
          username: 'test',
          password: 'test',
        );
        final now = DateTime.now().toUtc();
        final fetched = now.subtract(const Duration(days: 2));
        final request = TimetableStudentParserCacheRequests.getHome();
        final record = CacheRecord(
          key: request.keyFor(account),
          codecId: request.codec.id,
          json: '{"hours":[],"planForAll":[[],[],[],[],[]]}',
          fetchedAt: fetched,
          expiresAt: fetched.add(const Duration(hours: 1)),
        );
        db.writeCacheRecord(record, db.cacheGeneration(account));
        const shortOperation = 'custom.short';
        final shortKey = CacheKey(
          accountId: account,
          operation: shortOperation,
          version: 1,
          argumentHash: 'custom',
        );
        db.writeCacheRecord(
          CacheRecord(
            key: shortKey,
            codecId: record.codecId,
            json: record.json,
            fetchedAt: fetched,
            expiresAt: record.expiresAt,
          ),
          db.cacheGeneration(account),
        );
        db.dispose();
        final raw = sqlite3.open(path);
        raw.execute(
          "DELETE FROM cache_migrations WHERE name='seven-day-applet-retention'",
        );
        raw.close();
        db = LanisDatabase.open(path: path, secretStore: secret);
        final saved = await CacheService(
          db,
        ).readCacheFor(accountId: account, request: request);
        expect(saved.fetchedAt, fetched);
        expect(saved.expiresAt, fetched.add(const Duration(days: 7)));
        db.dispose();
        final second = sqlite3.open(path);
        second.execute('UPDATE cache_entries SET expires_at=?', [
          now.add(const Duration(hours: 1)).microsecondsSinceEpoch,
        ]);
        second.close();
        db = LanisDatabase.open(path: path, secretStore: secret);
        expect(
          db.readCacheRecord(request.keyFor(account))!.expiresAt,
          now.add(const Duration(hours: 1)),
        );
      } finally {
        db.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
