import 'package:riverpod/riverpod.dart';

import '../cache/service.dart';
import 'core_providers.dart';

/// Local-only dependency graph: no session, authentication, or connection probe.
final cacheServiceProvider = Provider<CacheService>(
  (ref) => CacheService.shared(ref.watch(lanisDatabaseProvider)),
);
