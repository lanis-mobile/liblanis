# Student lessons regression coverage

The live captures were recorded on 12 November 2026 against
`Informatik 1 (fuzzTest-Gym)`, course `20`. The original course settings were
restored and all generated entries were removed after capture.

| GlitchTip issue | Observed failure | Reproduction and regression |
| --- | --- | --- |
| [CA](https://glitchtip.orion.alessioc42.dev/organizations/lanis/issues/394) | `uploadFile` discards the underlying Dio error and throws `NetworkException`. The latest event has upload requests without response status codes. | Three offline transport injections cover connection failure, timeout, and bad response. They verify `NetworkException` retains diagnostic details. A real upload succeeds in the live course. The original remote network failure cannot be identified or recreated exactly from the old event. |
| [87](https://glitchtip.orion.alessioc42.dev/organizations/lanis/issues/263) | The upload deletion UI passes null `course_id` to a required `String`. | A live one-shot submission removes the upload form. Parsing now recovers identifiers from `h1` metadata. The existing `lanis/test/applets/upload_page_test.dart` checks deletion with missing and valid identifiers. |
| [AI](https://glitchtip.orion.alessioc42.dev/organizations/lanis/issues/338), M1, LV, NA | The upload result dialog uses a disposed widget context. | Existing upload widget tests invoke the saved details action after disposal and verify the mounted action still opens the dialog. HTML alone cannot reproduce a widget lifecycle error. |
| [EN](https://glitchtip.orion.alessioc42.dev/organizations/lanis/issues/471), other historical course-screen groups | The course screen reads `data!.semester1URL` after loading fails. | New `lanis/test/applets/course_overview_test.dart` forces the request and retry to fail and checks that the screen renders without a null-check crash. A second test completes a request after disposal. |
| [A](https://glitchtip.orion.alessioc42.dev/organizations/lanis/issues/10) | Attendance aggregation reads `lesson.attendances!`. | An offline mutation removes the overview attendance section while retaining its course and current entry. Existing attendance tests verify null maps are skipped. Three live states cover absent, excused, and late attendance. |
| Discord export | The teacher name is a `span` instead of the expected anchor. | The anonymized original course-detail report retains its unlinked teacher span. The regression parses its teacher and all 18 history entries directly. |

Issue metadata can describe an older event in a group. In particular, the
latest inspected event in issue 54 originates in `StudyGroupsStudentParser`,
although its issue title points to the course screen. That event is outside
this module. Course-screen issue counts are not treated as exact counts of a
single underlying failure.

The old detail-screen loader catches errors locally without reporting them.
Changing parser error details does not by itself make those handled failures
appear in GlitchTip. This capture work does not change that reporting behavior.

The live matrix exposed additional parser failures:

| State | Previous behavior | Regression |
| --- | --- | --- |
| Multiple files forbidden | The parser selects only green permission labels and indexes the missing second item. | A live single-file fixture verifies `false` for multiple files and `true` for repeat submissions. |
| Multiple files and repeat submissions forbidden | Both permission labels disappear from the old selector, causing `RangeError`. | The live one-shot fixture verifies both permissions and keeps the existing file. |
| Future or expired submission | The form can disappear although requirements and existing files remain. | Live fixtures retain dates, file types, files, and identifiers. |
| Minified history dates and upload buttons | Positional text-node and newline indexing can fail or extract the wrong field. | A DOM mutation retains dates, school hours, and the upload name. |
| Optional marks or exam tab absent | Null casts and forced child indexing fail. | Seeded mutations preserve all history entries with empty optional lists. |
| Course IDs 2 and 20 | Substring matching can attach course 20's attendance to course 2. | An overview mutation checks exact query-parameter matching. |

Grade comment rows and public-file owner labels have synthetic tests. These
states were not written to the live course. Invalid authentication pages must
throw a `LanisException`, rather than masquerading as an empty plan or exposing
a generic Dart exception.

The UI checks also have a local negative-control run. Removing each historical
guard caused its corresponding test to fail: `data!` after a failed course load,
`attendances!` on a null map, the upload dialog action after disposal, and deletion
with a null course ID. The current guards were restored before rerunning the
passing widget tests. Flutter's debug build reports an invalid `BuildContext`
for the disposed dialog action. The older production event reports a null-check
failure for that same lifecycle state.
