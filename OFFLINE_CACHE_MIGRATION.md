# Generic offline cache migration for liblanis

Status: initial implementation, 17 November 2026. Companion: [lanis plan](../lanis/OFFLINE_CACHE_MIGRATION.md).

## Generic cache implementation

Implemented the SQLite cache store and generation guards, typed requests and
codecs, the annotation generator, cached parser companions, detached availability
checks, strict expiry, transport-only fallback, and nested-result provenance.
Migrated student and parent timetable homes, parent timetable details, and
unfiltered substitutions. Compatible unexpired legacy timetable homes retain
their original age; legacy filtered substitutions are deliberately not imported.

Validation: code generation succeeds, static analysis is clean, and the full
library suite passes 281 tests. Coverage includes generation errors, typed
identity, nested provenance, strict expiry, offline provider isolation, corrupt
metadata, and cache-clear races across database connections.

The original phases below remain the design reference. Broader applet migration,
mutation invalidation, and publishing the generator/runtime packages remain
separate follow-up work. The generator is currently a repository-local dev
package; generated parser files are checked in.

## Baseline

The branch `fix/parent-lessons-and-homework` contains these completed changes:

- `03b45be`: parent Lessons overview and homework status.
- `6e7f93a`: parent timetable selection and single-child loading.

The timetable API returns `ParentTimetableHome`. Its variants are
`ParentTimetableSelection` and `ParentTimetableLoaded`. The latter contains a
pupil ID and a parsed `TimeTable`. A single-child redirect takes two requests.
A multi-child selection takes one request, followed by one request per chosen
plan. The last complete library test run passed 231 tests.

Current applet caching lives in `AppletParser.fetchData()` and the
`applet_offline_data` table in `LanisDatabase`. Each account and applet has one
JSON snapshot. Direct method calls bypass this mechanism. The app currently
uses published liblanis 0.1.5.

## Confirmed architecture

The following requirements come from the agreed design:

- Preserve the app's explicit offline startup and cached-module entry points.
- Reading cached data never changes authentication state or proves a login.
- Explicit offline browsing is cache-only until the user explicitly retries
  login. It never probes connectivity or starts authentication implicitly.
- Use an annotation to enable caching for serializable asynchronous reads.
- Provide a generic availability check for every annotated function and its
  parameters. Home pages and detail functions use the same mechanism.
- Treat different functions as independent cache operations. Do not infer a
  child-plan cache hit from a home result containing similar JSON.
- Availability means a result can be decoded and used now, rather than merely
  that a row exists.
- Return `MaybeCacheResult<T>` for both network and cached successes. Include
  data, cache status, the original fetch timestamp, and the response timestamp.
- Default to network-first reads with fallback for offline and classified
  transport failures. Authentication and parsing errors remain errors.
- Use the applet `refreshInterval` for refresh cadence. Retain offline data for
  seven days, unless an operation explicitly sets a shorter limit. This replaces
  the earlier applet-interval hard expiry by the user's updated decision.
- Propagate cached provenance through nested reads. Use the oldest contributing
  fetch timestamp and never outlive the earliest dependency expiry.
- Cache unfiltered domain data. Apply user-configured presentation filters after
  reading it, outside the cached operation.
- Do not cache successful top-level null results. Nullable reads can still
  return a network result envelope with null data.
- Defer automatic invalidation after mutations to a later change.
- Clearing cache must prevent already-running operations from repopulating the
  cleared scope.

The exact helper names below are proposed spellings of these contracts.

## Result and read policies

Use a result envelope for every successful read, whether it was cached or not:

```dart
enum CacheStatus { network, cache }

class MaybeCacheResult<T> {
	final T data;
	final CacheStatus cacheStatus;
	final DateTime fetchedAt;
	final DateTime responseAt;
	final DateTime expiresAt;
}
```

`fetchedAt` records the successful network fetch in UTC. Persist that timestamp
and preserve it on cache reads. `responseAt` records when the current call
produces its result, also in UTC. Reading or inspecting a cache entry must not
extend its lifetime. An empty domain result can still be a successful cached
value. A cache miss is not an empty domain result.

`T` may be nullable. A successful network null is returned as
`MaybeCacheResult<T?>` with network status and both timestamps, but it is not
stored and cannot itself satisfy availability. Nullable fields inside a
non-null result remain serializable. To avoid reviving an older value after an
authoritative null, remove the previous entry for that exact request as the
replacement rule. This does not invalidate any other operation.

`expiresAt` exposes the effective expiry to callers, including a shorter expiry
inherited from nested data. A successful null can carry its computed deadline
in the envelope, but creates no entry usable before that deadline.

Use these explicit policies:

| Policy | Behavior |
| --- | --- |
| `networkFirst` | Execute the read. Save a successful non-null serializable result. On an eligible availability failure, return a usable matching entry. |
| `cacheOnly` | Read a usable matching entry. Never execute the function, probe the network, or authenticate. |
| `networkOnly` | Execute the read without cache fallback. Successful results may update the cache. Use this for fresh-data consumers such as notifications. |

In cache-only mode, return a typed cache-unavailable error if no usable entry
exists. After a failed network attempt with no usable fallback, preserve the
original error and stack. Do not save failed requests, parser errors, or login
pages as successful cached data.

Initially classify transport failures explicitly: disconnected state, DNS and
socket failures, connection failures, and transport timeouts. Preserve the
underlying exception as structured data. Do not classify failures by matching
English error strings. Keep HTTP application errors outside automatic fallback
unless a later policy explicitly includes a status. Manual offline startup
remains available during server outages.

## Availability contract

Use the same generated request descriptor for execution, storage, and checking:

```dart
final request = TimetableParentParserCacheRequests.getTimetable(reference);

final available = await cache.isCacheAvailableFor(
	accountId: accountId,
	request: request,
);

final homeAvailable = await cache.isCacheAvailableFor(
	accountId: accountId,
	request: TimetableParentParserCacheRequests.getHome(),
);
```

Both factories are generated from annotated functions and retain their typed
arguments and result codecs. They do not execute those functions. There is no
special timetable cache implementation. The same API applies to a course URL,
a conversation ID, or another supported set of serializable arguments.

The generic interfaces are:

```dart
Future<bool> isCacheAvailableFor<T>({
	required int accountId,
	required CacheRequest<T> request,
});

Future<CacheAvailability> inspectCacheFor<T>({
	required int accountId,
	required CacheRequest<T> request,
});
```

`CacheAvailability` reports a state such as `available`, `missing`, `expired`,
`incompatible`, or `corrupt`, with fetch and expiry timestamps when known.
`isCacheAvailableFor()` is true only for `available`. Database failures remain
errors rather than silently becoming misses.

A check must verify account scope, operation, argument identity, schema version,
expiry, and successful decoding with the same codec used by reads. Cache
inspection performs no HTTP, account selection, session initialization,
connection probe, or authentication. Detached request factories allow startup
to check several accounts before any parser or session is constructed.

Availability is a point-in-time result. A later read must still handle eviction
or expiry. The UI must not assume that a previous true result guarantees a
future hit.

Provide a corresponding `readCacheFor(accountId, request)` operation returning
`MaybeCacheResult<T>`. It accepts the same descriptor and reads local storage
only. This gives unauthenticated offline screens a direct data path without
constructing the parser that implements the network read.

## Operation identity and storage

Add a general-purpose `cache_entries` table instead of interpreting arbitrary
cache keys as PHP applet identifiers. The logical primary key contains:

```text
account ID + operation ID + schema version + argument digest
```

Store the JSON payload, original fetch timestamp, and expiry timestamp. Register
the operation's codec and owning applet separately from the payload. Keep
module navigation metadata separate from raw cache rows. Add an expiry index
and bounded cleanup of expired entries so parameterized reads do not grow
the database indefinitely.

Increment the operation schema version when its serialized shape or meaning
changes. Never reuse an old version with an incompatible codec.

Generate keys from canonical JSON for every declared data argument, including
named arguments and resolved defaults. Canonicalization sorts map keys and
preserves list order. Include type information where JSON representations could
otherwise collide. Use explicit codecs for types such as `Uri` and `DateTime`.
Never use `toString()`, instance identity, or process-specific `hashCode` as a
cache key. Build generation fails for unsupported argument or return types.

The default key includes the full serialized input. Equivalent inputs with
different serialized values may produce separate entries. Do not silently drop
fields or infer a pupil-only key for a method receiving a full reference.
A method needing a narrower identity can expose narrower data arguments.

Arguments do not describe hidden settings dependencies. Refactor current
`SubstitutionsParser.getHome()` so its cached read returns unfiltered data. Apply
account filters to a copy or a non-mutating projection after retrieval. Do not
filter the cached object in place. A filter change must update the visible
projection without a network fetch or a new cache entry. Other hidden inputs
that change server data must become explicit data arguments or context-version
inputs. Do not cache a settings-dependent result under a parameterless key.

Account scope is supplied by the cache context and is mandatory. It is not
inferred from a username in arguments. Account deletion removes its cache rows
through the database relationship. Do not store authentication credentials as
cache arguments.

Each function has its own operation ID and version. A successful annotated home
read creates its home entry. A child function becomes available only if that
annotated operation has a successful matching entry. If an annotated home
actually invokes an annotated child read, both executed operations can write
entries normally. No payload inspection or implicit cross-operation aliases
are required.

## Expiry

The user updated the retention policy during foreground outage testing. Applet
refresh intervals no longer make saved data unusable. `CacheRequest.refreshInterval`
is the target refresh cadence, while `CacheRequest.maxAge` limits offline retention.

```text
refresh interval = min(applet interval, explicit operation limit, seven days)
maximum age = min(explicit operation limit if set, seven days)
own expiry = fetchedAt + maximum age
effective expiresAt = min(own expiry, contributing dependency expiries)
```

Timetables refresh hourly and substitutions every ten minutes, but both remain
available offline for seven days. Cached reads keep the original fetch timestamp.
At or after the retention deadline, reads and availability checks reject the entry.
A fallback must not repeatedly schedule an already-passed refresh timestamp.

The SQLite migration extends existing pilot-operation rows to seven days from
their original fetch time, once. It does not modify payloads or fetch dates and
cannot restore rows already deleted by earlier cleanup. Other operations retain
their stored deadlines. Explicit shorter limits still apply on read.

## Annotation and generation

Use `@Cacheable()` on a raw asynchronous read with serializable data arguments
and a serializable `Future<T>` result. Start with methods. Reject streams,
callbacks, unsupported generic types, and mutation methods in the initial
migration. An annotation cannot prove a method is free of side effects, so
annotation placement remains part of review.

Dart annotations do not replace existing method bodies. Generate wrappers and
request factories through `build_runner`. Reuse model `toJson()` and `fromJson()`
codecs where valid, including tagged serialization for sealed results. Add
serialization generation only where a model has no suitable codec.

Inventory codecs before annotating a module. The timetable sealed result and
its references already have codecs. Lessons models need serialization work
before migration. In particular, encode the `Map<LessonPupil, Lessons>` in
`ParentLessonsOverview` as explicit entries, not JSON object keys derived from
`LessonPupil.toString()`. Test nested lessons, homework, files, and optional
fields before enabling their cache operations.

Prefer a generated companion so existing return types remain compatible:

```dart
@Cacheable()
Future<ParentTimetableLoaded> _getTimetable(
	ParentTimetableReference reference,
) async {
	// Networking and parsing only.
}

// Proposed generated facade:
final MaybeCacheResult<ParentTimetableLoaded> result =
	await parser.cached.getTimetable(reference);
```

Keep existing plain-data methods during migration. The new facade returns
`MaybeCacheResult<T>`. Generated request factories use the same signature,
operation ID, codec, and key builder as the facade. Never generate availability
checks from a second, independently maintained key algorithm.

Read policy is execution context, not part of the data arguments or cache key.
An offline route supplies a cache-only context. Background tasks supply a
network-only context. Policy must propagate to nested calls. Generated wrappers
must not let a cached nested result become falsely labeled as fresh network
data or receive a new fetch timestamp in an outer cached result.

## Nested-result composition

Track consumed nested results in a per-call execution context. Inspection of
availability does not count as consuming data. A nested annotated read registers
its provenance even when the raw outer implementation only uses `.data`.

Compose an outer result using these rules:

1. If any consumed result came from cache, mark the outer result `CacheStatus.cache`.
   Use `network` only when every contributing read was a network result.
2. Set `fetchedAt` to the oldest contributing fetch timestamp, including the
   outer operation's own fresh inputs. Set `responseAt` to the current delivery
   time.
3. Set `expiresAt` to the earliest of the outer deadline computed from that
   `fetchedAt` and all contributing dependency expiries.
4. If storing the outer result, preserve those timestamps and provenance. Its
   write time must not become a new fetch time. Physical retention of an inner
   row is not required, but its validity deadline constrains the outer snapshot.
5. Validate the effective expiry again before returning or storing the result.
   An expired contributing value cannot become a usable outer cache result.

For example, a fresh single-child redirect followed by a cached plan fetched
40 minutes earlier produces a cached home result with that older fetch time.
The new redirect does not reset the timetable's lifetime. This rule governs
actual nested calls and does not create aliases between independent functions.

## Policy dispatch, refresh, and request coalescing

Choose the effective policy before calling the existing connection checker,
`AppletParser.fetchData()` preflight, authentication retry, or refresh hooks.
`cacheOnly` dispatches directly to the local read operation. A cache miss or
expiry cannot enter the legacy blanket authentication retry path.

Offline routes must not start the existing auto-refresh timer, whose callback
probes connectivity. A local timer may expire displayed data without contacting
the network. Online authentication recovery remains separate from cache
availability and is attempted only for classified authentication failures.

Keep persistent cache identity independent of read policy. In-flight execution
identity must additionally include the effective policy, execution context,
and cache-clear generation. Initially coalesce only calls with compatible,
identical execution policies. A cache-only call never joins network work, and a
network-only caller never receives another caller's fallback. Each caller
applies its own allowed fallback after execution. Sharing lower-level transport
work across policies is an optional later optimization.

## Clearing and invalidation

Maintain persistent clear generations for the supported clear scopes. Capture
the relevant generation tokens before starting an operation. Clear entries and
advance their generation atomically. Commit a subsequent cache write only if
all captured generations still match, in the same database transaction. Apply
that check to exact-entry removal after a null response too, so an old request
cannot delete a new post-clear value.

Use database-backed generations so the foreground app and background isolate
observe the same clear operation. Do not implement this as an in-memory flag.
A new post-clear call must not join pre-clear in-flight work. A pre-clear network
request may still deliver its result to its original caller, but may not persist
that result into the cleared scope. Queries must see the cleared state.

Support user-requested clearing and account deletion in this migration.
Automatic cross-operation invalidation after successful homework changes,
message sending, or other mutations is explicitly deferred. Keep that follow-up
separate from the exact-request replacement rule for successful null reads.

## Implementation sequence

1. Add cache result, policy, request, availability, and codec contracts. Preserve
   existing public parser signatures and applet streams.
2. Add `cache_entries` and a typed cache service. Implement exact lookup, expiry,
   safe inspection, a session-free local read operation, and clear-generation
   protection. Prove those contracts with local tests before code generation.
3. Add annotation generation, detached request factories, and companion wrappers.
   Generate a module manifest mapping applets to their home descriptors. The
   manifest contains data identifiers and supported account types, not widgets.
4. Pilot an existing timetable home read and a parameterized parent timetable
   read. Keep each operation independently keyed. Exercise single-child loaded
   and multi-child selection results without special payload aliases.
5. Make `AppletParser.fetchData()` delegate migrated home reads to the cache
   service. Adapt `MaybeCacheResult<T>.data` back into `FetcherResponse<T>` so
   `CombinedAppletBuilder<T>` can remain in place. Preserve original cache age
   in `FetcherResponse.fetchedAt`. Map cache source explicitly to its existing
   offline-content presentation. Dispatch policy before legacy connectivity,
   timer, and authentication hooks so cache-only reads cannot enter them.
6. Migrate legacy known home snapshots through their registered descriptors and
   codecs. Derive scope from persisted account type. Retain the legacy table
   during rollout. Unknown, incompatible, corrupt, and expired records are not
   offered as available modules. Do not rewrite their age as the migration time.
   Do not import an already-filtered legacy substitution snapshot as a complete
   unfiltered result. Preserve it only through the legacy compatibility path
   until a successful unfiltered network read populates the new operation.
7. Provide temporary legacy reads and writes only for unchanged, supported home
   formats needed by the released app. Do not put parent sealed results into a
   legacy student snapshot format. Verify rollback before removing adapters.
8. Refactor settings-dependent reads such as substitutions to cache unfiltered
   data and project current filters afterward. Release the library contracts
   and migrate app call sites using the companion plan. Expand annotation
   coverage module by module. Keep mutations and notification freshness rules
   outside automatic fallback.
9. Remove legacy cache paths only after the app no longer reads raw legacy
   snapshots and migration coverage is complete.

Batch writes and generation checks must be atomic. A failed local cache write
should not turn a successful network read into a network failure. Report
cache-storage failures separately. Coalesce calls only under the policy and
generation rules above. A failed or cancelled caller must not erase a previously
valid entry or publish a partial payload.

## Verification and completion criteria

Add tests for the following behaviors:

- Identical parameters generate identical keys in both calls and checks.
- Different accounts, methods, versions, pupils, URLs, dates, and data arguments
  remain isolated. Named-argument ordering does not change a key.
- A missing, expired, incompatible, or undecodable entry is unavailable.
- Valid empty collections remain available. Successful top-level null responses
  are returned without caching and remove only their exact previous entry.
- Age checks enforce the optional shorter operation limit and seven-day cap,
  independently from applet refresh cadence, including the exact boundary.
- `fetchedAt` survives a cache hit. `responseAt` advances. Inspection never
  refreshes either the fetch timestamp or expiry.
- Both parent timetable result variants survive JSON round trips.
- Cache-only reads and availability checks cause zero HTTP, authentication,
  connectivity-probe, or session-construction calls.
- Offline and transport failures can fall back. Authentication failures,
  permission failures, and parser bugs cannot become successful cache hits.
- A home result never invents an entry for another annotated function.
- A fresh outer read consuming cached inner data reports cached status, the
  oldest fetch timestamp, and the earliest allowed expiry. Outer writes and
  repeated reads never extend a dependency's validity.
- Compatible concurrent requests share execution. Mixed-policy calls remain
  isolated: cache-only performs no network work, and network-only receives no
  fallback. Different accounts and clear generations never share execution.
- A real offline provider graph constructs no session or connection checker.
  Legacy refresh timers and authentication retry paths remain inactive.
- Changing filters projects the cached unfiltered substitutions without another
  network call and without mutating the stored or shared cached object.
- Clearing during an in-flight request prevents its write in both foreground
  and background execution. Calls begun after clearing use a new generation.
- Legacy migration preserves scope, data age, expiry, and rollback compatibility.
- Account deletion and selective clearing remove the intended entries only.

Run library generation, analysis, and the full test suite. Consumer projects
must compile against the release before enabling the new app integration.

## Boundaries for this change

This plan does not change authentication into a cache-based state. It does not
queue writes offline, make downloads durable, automatically cache arbitrary
HTTP responses, or infer that a cached module home contains every detail page.
Automatic mutation invalidation is deferred. File caching remains a separate
facility. The initial module implementations are described at the top; expand
annotation coverage in later changes.
