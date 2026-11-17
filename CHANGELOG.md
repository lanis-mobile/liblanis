## Unreleased

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
