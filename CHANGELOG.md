## 0.3.3

* Keep empty Monday–Friday weekdays in `TimeTableData` and expose `weekdayIndices`
  so callers can map timetable columns to their actual weekday indices.

## 0.3.2

* Harden `StorageManager` paths, redirects and file cleanup.
* Fix applet parser edge cases (study groups, lessons), model equality and cache codegen.
* Fix `LanisSession` timer lifecycle; coalesce concurrent cached-applet fetches and
  re-authentication so parallel retries no longer invalidate each other's session.
* Roll back failed `addAccount` writes and self-heal orphaned account rows.
* Map unexpected redirects and malformed responses (account type, user data,
  fast travel, conversations) to typed `LanisException`s instead of raw
  `TypeError`/`FormatException`; reject empty ciphertext in `Cryptor`.
* Fix data storage search on iOS (no `GET` request body) and validate its response.

## 0.3.1

* Report distinct login errors for parent accounts without learners, disabled
  accounts, and required password changes.

## 0.3.0

* Replace the archived `encrypt` wrapper with PointyCastle 4 primitives, retaining
  the SPH RSA PKCS1 v1.5 handshake, AES-256-CBC/PKCS7 payloads, OpenSSL `Salted__`
  envelope and existing MD5 key derivation required by the server protocol.
* **Breaking:** `Cryptor.key`, `generateKey()`, `bytesToKeys()` and static decrypt
  helpers now use `Uint8List` instead of `encrypt.Key`. Pass the old key's `.bytes`
  when migrating callers. Session-owned cryptor initialization remains automatic.
* Handle empty plaintext with a complete PKCS7 padding block; reject missing or
  truncated salt envelopes. Verify legacy payloads, public-key PEM formats,
  padding failures, isolate decryption and overlapping authentication.

## 0.2.1

* Upgrade runtime dependencies, including Riverpod 3.5 and annotations 4.0.8,
  and regenerate providers with Riverpod generator 4.0.10.
* Upgrade analyzer, build, source_gen, and the local cache generator tooling;
  require Dart 3.13 or newer.
* Update source syntax and constructor initialization for the current analyzer
  and lint rules. Keep PointyCastle on 3.9.1 for encrypt compatibility.

## 0.2.0

* Separate refresh cadence from offline retention: default applet snapshots remain
  available for seven days, with their original fetch dates preserved.
* Recognize native HTTP transport errors and transient gateway failures for cache
  fallback. Keep loaded data during failed foreground refreshes, without treating
  authentication or parsing failures as successful cache hits.
* Migrate existing timetable/substitution deadlines once and retain already-loaded
  legacy applet data on transport failure without attempting a new login.

* Parse parent course-detail homework marked by a home icon without student
  completion controls, so the app can show its homework box. Read detail
  completion status only from that response; do not transfer overview status.

* Add `@Cacheable`, generated cached companions, detached typed cache requests,
  `MaybeCacheResult`, and session-independent availability and cache-only reads.
* Persist versioned per-account results with hard expiry and guarded writes after
  cache clearing, including across database connections.
* Migrate timetable homes, parent child plans, and unfiltered substitutions to the
  generic cache. Preserve metadata through nested cached reads and fall back only
  on offline or transport failures.

* Add `TimetableParentParser` with a sealed `ParentTimetableHome` result: a child selection or a loaded plan with its pupil ID. Follow single-child redirects and load selected plans through the shared timetable parser.
* Enable parent timetable support when offered by the portal, select the parent parser in `EasyParsers`, and expose `timetableParentParserProvider`.
* Cache both parent timetable result variants and add anonymized fixtures and regression tests for child selection, redirects, request counts, and offline restoration.

* Add a read-only `LessonsParentParser` whose `getHome()` returns a complete `ParentLessonsOverview`, grouped by child, in one request. Course details load on demand.
* Select the parent lessons parser in `EasyParsers` and expose `lessonsParentParserProvider` for Riverpod clients.
* Parse parent course and attendance sections per child, expose `pupilId`, and preserve pupil and semester URL parameters.
* Read parent homework status labels so open homework remains open without a student checkbox.
* Add anonymized parent overview fixtures from live one-child and two-child tests, plus regression coverage for pupil isolation and request counts.

## 0.1.5

* Parse older student course folders and expose `Lesson.isOlder`, with a default of `false`. Preserve semester parameters in course URLs.
* Fix student course details with unlinked teacher names, optional tabs, and compact markup. Match attendance records by exact course ID.
* Fix submission permissions, pages without upload forms, attachment filename encoding, and per-file upload result parsing.
* Add offline student parsing methods for overview, course detail, submission, and upload result documents.
* Preserve error details and original stack traces in lesson, conversation, and calendar operations while keeping exceptions within the `LanisException` hierarchy.
* Add student parser regression fixtures, an anonymized bug report, and mutation tests.

## 0.1.4

* Expose the head message's sender as `Conversation.sender` so clients can address private replies to the correct recipient.
* Document that replies in private-answer-only conversations must target that sender to avoid reaching every participant.

## 0.1.3

* Serialize session authentication calls to prevent concurrent changes to shared cookies and encryption keys.
* Report failed applet reauthentication through the fetch response and unexpected-error hook.
* Mark the connection as disconnected when a keep-alive request returns HTTP 503.
* Preserve the original error type and stack trace for calendar event and conversation detail failures.
* Add connection and login timeouts, and use an offline HTTP adapter in unit tests to avoid waiting on the live portal.

## 0.1.2

* Stop duplicating substitution days when a personal-plan shell uses underscore `data-tag` values together with `#tagDD_MM_YYYY` panels.
* Add a production-shaped synthetic fixture and parser tests for that layout.

## 0.1.1

* Update the pub.dev package description and README listing.

## 0.1.0

* Initial package extract of the SPH client stack from lanis-mobile.
* Riverpod providers for accounts, session, connection status, settings, and applets.
* `EasyLanisClient` imperative API without Riverpod.
* Unified optional `sqlite3` database (in-memory by default).
* Injectable `SecretStore`, configurable `StorageManager`, English-only exceptions.
* Fixture-driven hardening for substitutions, timetable, and calendar parsers.
