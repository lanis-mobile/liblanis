import '../applets/definition.dart';
import 'service.dart';

/// Generates cached companions and detached request factories for read methods.
/// The implementation method must be private and return a serializable Future.
class Cacheable {
  final String? operation;
  final int version;
  final AppletMeta? applet;
  final Duration? maxAge;
  const Cacheable({this.operation, this.version = 1, this.applet, this.maxAge});
}

abstract interface class CacheHost {
  CacheService get cacheService;
  int get cacheAccountId;
}
