# Capture student lesson fixtures

Run these commands from `liblanis`. The capture tools read
`../lanis/.teacher.credentials.env` and `../lanis/.student.credentials.env`.
Both files contain `schoolid`, `username`, and `password`.

The tools verify course `20` has the exact name
`Informatik 1 (fuzzTest-Gym)` before writing. They use authenticated HTTP
and the portal's forms and JavaScript endpoints. They never invoke
`LessonsTeacherParser`.

1. Preview the content matrix with `dart run tool/lessons/capture_matrix.dart --dry-run`.
2. Capture entries, attachments, and submissions with `dart run tool/lessons/capture_matrix.dart`.
3. Capture all eight topic, description, and homework visibility combinations with `dart run tool/lessons/capture_visibility.dart`.
4. Capture the test student's attendance states with `dart run tool/lessons/capture_attendance.dart`.
5. Build the offline corpus with `dart run tool/lessons/pack_fixtures.dart`.
6. Run `dart test test/lessons_student_parser_test.dart`.

The captures use fixed November 2026 dates. Update the date inputs and date
assertions together when recording a different school term. Never run capture
tools concurrently against this course.

Every generated entry contains `LIBLANIS_FUZZ_`. The tools delete only entries
with that marker, including their attachments and submissions, in `finally`.
The visibility tool restores and verifies the original course form values.
Attendance writes target only the logged-in test student on a generated entry.

If a process stops before cleanup, run
`dart run tool/lessons/capture_matrix.dart --cleanup-only`. Generated entry IDs
are also recorded in the ignored `run/created_entries.json` file.
The visibility tool saves its original settings in `run/original_book.html`.
If the process is killed, restore those settings before another visibility run.

`discovery/` and `run/` contain private, ignored captures. The packer retains
only the test course's main content, replaces teacher names and encoded values,
removes scripts, images, and messaging addresses, and deduplicates the resulting
HTML by SHA-256. Review fixtures before committing. `manifest.json` maps every
source state to its retained fixture.

The tests use static entry points shared with the production HTTP methods.
They read no credentials and make no network requests. The corpus includes
successful and rejected upload responses. Additional tests apply seeded DOM
mutations and inject transport failures.

See [the regression coverage](regressions.md) for the GlitchTip issue mapping.
