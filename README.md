# liblanis

[![pub package](https://img.shields.io/pub/v/liblanis.svg)](https://pub.dev/packages/liblanis)

Pure Dart client for [Schulportal Hessen (SPH / Lanis)](https://start.schulportal.hessen.de).

Session stack, multi-account storage, optional `sqlite3` persistence, injectable secrets, and applet parsers. **No Flutter dependency** for the core API. Flutter apps can use the Riverpod integration documented below.

Published on [pub.dev](https://pub.dev/packages/liblanis). Also used as a submodule of [lanis-mobile/lanis](https://github.com/lanis-mobile/lanis).

## Features

- Full SPH session stack (login, cookies, RSA/AES cryptor, HTML/JSON applet parsers)
- `**EasyLanisClient**` — imperative API without Riverpod (default for scripts, CI, other Dart projects)
- Optional Riverpod multi-account registry for Flutter apps
- Optional single SQLite database (file or in-memory)
- `sharedOverAccountSettings` and `accountSpecificSettings` with typed helpers
- Typed, account-scoped offline caching with generated request descriptors and availability checks
- Configurable `StorageManager` (caller supplies cache directory)

## Install

```sh
dart pub add liblanis
```

Or add `liblanis` under `dependencies` in your `pubspec.yaml` (see [pub.dev](https://pub.dev/packages/liblanis) for the current version).
For Flutter apps that use the Riverpod API, also add:

```yaml
dependencies:
  flutter_riverpod: ^3.0.0
  sqlite3_flutter_libs: ^0.5.0 # load native sqlite on mobile
```

## Quick start

Import `package:liblanis/easy_client.dart`. No `ProviderScope` or code generation required.

### In-memory (tests, quick scripts)

```dart
import 'package:liblanis/easy_client.dart';

Future<void> main() async {
  final client = EasyLanisClient.inMemory();

  final id = await client.accounts.add(
    schoolId: 5151,
    username: 'student.user',
    password: r'...',
  );

  await client.login(accountId: id);

  // Direct parser call
  final plan = await client.parsers.substitutions.getHome();

  // Cached fetch with offline fallback (same as AppletParser.fetchData)
  final response = await client.parsers.calendar.fetch(forceRefresh: true);
  if (response.contentStatus == ContentStatus.offline) {
    // using cached events
  }

  client.connection.onStatusChanged.listen((status) {
    // ConnectionStatus.connected / disconnected
  });

  await client.logout();
  await client.dispose();
}
```

### Available parsers

Access via `client.parsers` after login:


| Getter           | Applet                    |
| ---------------- | ------------------------- |
| `substitutions`  | Vertretungsplan           |
| `timetable`      | Stundenplan (student)     |
| `timetableParent` | Stundenplan (parent)      |
| `calendar`       | Kalender                  |
| `conversations`  | Nachrichten               |
| `lessonsStudent` | Mein Unterricht (student) |
| `lessonsParent`  | Mein Unterricht (parent)  |
| `lessonsTeacher` | Mein Unterricht (teacher) |
| `dataStorage`    | Dateispeicher             |
| `studyGroups`    | Lerngruppen               |


Generic access for smoke tests: `client.parsers.forApplet('kalender.php')`.

### Parent lessons

`LessonsParentParser` provides a read-only API for parent accounts.
`forApplet('meinunterricht.php')` selects this parser for a parent account.
Riverpod clients access it through `lessonsParentParserProvider`.

| Method | Result | Requests per call |
| --- | --- | --- |
| `getHome()` | `ParentLessonsOverview` with every child and their parsed courses | One overview request |
| `getDetailedCourseView(course.courseURL.toString())` | One course's history, marks, exams, and attendance | One course request |

`getHome()` parses the complete parent page once. Its `lessonsByPupil` property
is a `Map<LessonPupil, Lessons>`, including children whose course lists are empty.
Each key contains the child's `id` and `name`. Each value contains that child's
parsed course overview. Selecting a child uses this map without another request.
The parser never loads course details automatically.

```dart
final parser = client.parsers.lessonsParent;
final overview = await parser.getHome();
for (final entry in overview.lessonsByPupil.entries) {
	final child = entry.key;
	final courses = entry.value;
	print('${child.name}: ${courses.length} courses');
}
// After the user selects a child and opens a course:
final courses = overview.lessonsByPupil.values.first;
if (courses.isNotEmpty) {
	final detail = await parser.getDetailedCourseView(
		courses.first.courseURL.toString(),
	);
}
```

`Lesson.pupilId` and `DetailedLesson.pupilId` identify the child.
Use the pupil ID together with the course ID when storing parent courses.
Several children can share a course ID.
`courseURL` preserves the portal's `p` and semester parameters, while `courseID` contains only the course ID.
Parent detail requests require a URL with a nonempty `p` parameter.

Parent homework status comes from the overview's status labels.
If a parent detail page contains no homework, `history` entries keep `homework: null`.
The parser does not copy the latest overview homework into historical entries.

### Parent timetable

`TimetableParentParser.getHome()` returns the sealed `ParentTimetableHome` type.
Its variants follow the portal's response:

| Result | Contents | Requests |
| --- | --- | --- |
| `ParentTimetableSelection` | Child references in `timetables` | One overview request |
| `ParentTimetableLoaded` | `pupilId` and a parsed `TimeTable` in `timetable` | Two requests when the portal redirects to a single child's plan |

Each `ParentTimetableReference` contains `pupilId`, `pupilName`, `className`, and
the portal's timetable `url`. A selection does not fetch any child's plan.

```dart
final parser = client.parsers.timetableParent;
final home = await parser.getHome();
switch (home) {
	case ParentTimetableLoaded(:final pupilId, :final timetable):
		print('$pupilId: ${timetable.weekBadge}');
	case ParentTimetableSelection(:final timetables):
		// After the user selects a reference:
		if (timetables.isNotEmpty) {
			final loaded = await parser.getTimetable(timetables.first);
			print(loaded.pupilId);
		}
}
```

`getTimetable(reference)` makes one request and returns `ParentTimetableLoaded`.
It preserves the pupil, class, and other URL parameters. Every loaded result
carries its pupil ID, including when two children share the same class plan.
The single-child flow obtains the ID from the portal's redirect without a
separate child-discovery request.

`forApplet('stundenplan.php')` selects the parent parser for parent accounts.
Riverpod clients access it through `timetableParentParserProvider`.
Support detection requires the timetable entry in the account's portal menu.
The existing `timetable` getter and `timetableParserProvider` remain the student API.

The standard `fetch()` flow caches either result variant for offline use.
A cached selection retains its references, while a cached loaded result retains
its pupil ID and parsed plan. Explicit `getTimetable()` calls require a connection.

## Flutter (Riverpod)

Prefer `package:liblanis/liblanis.dart` when you want the provider-based multi-account API used by lanis-mobile.

On Flutter mobile hosts, initialize sqlite before `runApp`:

```dart
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  // ...
}
```

### Configure and mount

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liblanis/liblanis.dart';

Future<void> main() async {
  final overrides = LanisClient.configure(
    databasePath: '/path/to/lanis.db', // null => in-memory
    secretStore: MySecureStore(),      // required when databasePath != null
    documentCacheDirectory: '/path/to/cache', // required for downloads
    // httpAdapter: cronetAdapter,     // optional
    userAgent: 'Lanis-Mobile/v3.7.2+83',
  );

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const MyApp(),
    ),
  );
}

class MySecureStore implements SecretStore {
  // e.g. FlutterSecureStorage
  @override
  Future<void> write(String key, String value) async { /* ... */ }
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async { /* ... */ }
}
```

### Accounts & session

```dart
final id = await ref.read(accountsProvider.notifier).add(
  schoolId: 5151,
  schoolName: 'Example',
  username: 'user',
  password: 'pass',
);

await ref.read(activeAccountProvider.notifier).select(id);
await ref.read(sessionProvider.notifier).authenticate();

ref.listen(connectionStatusProvider, (prev, next) {
  // ConnectionStatus.connected / disconnected
});
```

### Settings

```dart
final shared = ref.read(sharedOverAccountSettingsProvider);
shared.setString('theme', 'dark');

final account = ref.read(accountSpecificSettingsProvider);
account.setJsonMap('vertretungsplan.php/filter', {/* ... */});
```

### Applets

```dart
final response = await ref.read(substitutionsProvider.future);
if (response.contentStatus == ContentStatus.offline) {
  // cached SubstitutionPlan
}
final plan = response.content;

// Or use the long-lived parser + stream:
final parser = ref.read(substitutionsParserProvider);
await parser.fetchData();
parser.stream.listen(/* FetcherResponse<SubstitutionPlan> */);
```

### Document downloads

```dart
final storage = ref.read(storageManagerProvider);
if (storage != null) {
  final path = await storage.downloadFile(url, filename);
}
```

Calling download APIs without `documentCacheDirectory` throws `StorageNotConfiguredException`.

## Configuration rules


| Option                         | Behavior                                 |
| ------------------------------ | ---------------------------------------- |
| `databasePath: null`           | In-memory sqlite; `SecretStore` optional |
| `databasePath: set`            | File DB; `**secretStore` required**      |
| `documentCacheDirectory: null` | Downloads disabled                       |
| `httpAdapter`                  | Optional Dio adapter injection           |


## Development

```bash
cd liblanis
dart pub get
dart run build_runner build
dart test
dart analyze
```

## License

GPL-3.0 — see [LICENSE](LICENSE).

## Typed offline cache (unreleased)

Timetable and substitution parsers expose a generated `cached` companion.
Existing direct methods retain their plain return types; use the companion when
you need caching and response metadata:

```dart
final parser = client.parsers.timetable;
final result = await parser.cached.getHome();
// result.data, result.cacheStatus, result.fetchedAt, result.responseAt,
// result.expiresAt
```

Use the concrete parser instance appropriate for the account. Parent timetables
support `parser.cached.getHome()` and `parser.cached.getTimetable(reference)`.
The home and individual timetable are independent cache operations.

Availability and cache-only reads do not need a parser, session, or connectivity
check. Construct a generated request with the same arguments as the read:

```dart
final request = TimetableParentParserCacheRequests.getTimetable(reference);
final available = await cache.isCacheAvailableFor(
  accountId: accountId,
  request: request,
);
final result = await cache.readCacheFor(
  accountId: accountId,
  request: request,
);
```

Here `cache` is `client.cache`, `CacheService.shared(database)`, or the value of
`cacheServiceProvider`. `inspectCacheFor` also distinguishes missing, expired,
incompatible, and corrupt entries. A successful availability check is a snapshot;
a later read can still fail if the entry expires or is cleared.

The default policy tries the network and falls back only for offline or transport
failures. Authentication and parsing errors propagate. Pass
`cachePolicy: CacheReadPolicy.cacheOnly` or use `readCacheFor` for explicit offline
browsing. Cache reads do not authenticate an account. `networkOnly` propagates
through nested reads and disables fallback. Results always include their fetch
and response timestamps. Nested results preserve the oldest fetch time and the
earliest expiry; any cached dependency marks the combined result as cached.

The applet refresh interval controls refresh cadence: one hour for timetables
and ten minutes for substitutions. Cached results remain available offline for
seven days unless an operation explicitly sets a shorter `maxAge`. `refreshInterval`
and `maxAge` are separate request properties. At the retention deadline, entries
become unavailable; reading or displaying them does not extend their lifetime. Successful null results are returned but
not stored, and remove the previous exact entry. Empty collections are cacheable.
Substitutions are stored unfiltered and projected through account settings after
reading. Cache keys include account, operation, version, and canonical arguments.

`cache.clear(accountId: accountId)` clears that account's generic and legacy
snapshots. Omit the account for a global clear. Persistent generation counters
prevent requests already running in another database connection from repopulating
a cleared cache. Online writes do not yet invalidate related read operations.

### Add a cacheable read

The development generator lives in `packages/liblanis_cache_generator`. Add it as
a dev dependency alongside `build_runner`, import the public cache types, declare
a part, and apply the generated mixin:

```dart
part 'example.g.dart';

class Example with _$ExampleCache implements CacheHost {
  @override
  final CacheService cacheService;
  @override
  final int cacheAccountId;

  Example(this.cacheService, this.cacheAccountId);

  @Cacheable(operation: 'example.items', maxAge: Duration(minutes: 10))
  Future<List<String>> _items({required int page}) async => fetchItems(page);
}
```

Run `dart run build_runner build`. Call `example.cached.items(page: 1)` and use
`ExampleCacheRequests.items(page: 1)` for detached availability or offline reads.
Applet parsers already implement `CacheHost`; set `applet: Applets.timetable`,
for example, to inherit its refresh limit. Keep annotated methods private so
callers deliberately choose the cached companion or an existing plain API.

The generator supports primitives, nullable values, lists, string-keyed maps,
DateTime, Uri, enums, and models with `toJson`/`fromJson`. It rejects unsupported
signatures during generation, including callbacks, method or owner generics,
optional positional parameters, and the reserved `cachePolicy` parameter.
Increase the operation version when changing payload compatibility. This first
migration covers timetables and substitutions; other applets retain their existing
behavior until migrated. See [the migration plan](OFFLINE_CACHE_MIGRATION.md).
