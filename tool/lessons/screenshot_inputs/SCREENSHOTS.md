# Screenshot course

Course: Informatik 1 (fuzzTest-Gym), ID 20.

The persistent dataset contains 24 lessons from 13 August to 12 November 2026,
23 homework tasks, 13 attachments, five submission assignments, and attendance
records for the configured test student. Eighteen homework tasks are completed
and five remain pending. Four assignments contain a student submission.

Use the student account in the app and refresh the Unterricht overview.
The latest lesson is "Projektwerkstatt: Lernplaner entwickeln". It includes
a detailed project brief, a worksheet, a starter project, a README, pending
homework, an open submission, and teacher feedback on the submitted ZIP file.

Useful views for screenshots:

- The Unterricht overview shows the current topic, attachments, and missing-hours badge.
- The homework view shows pending and completed tasks.
- The course history shows a full term of lessons, descriptions, homework, and files.
- The latest submission shows its deadline, requirements, a submitted project, and feedback.
- Older submissions show closed deadlines and retained files.
- The attendance view includes attendance, excused absence, unexcused absence, leave, and lateness.

Six numeric assessments and four qualitative feedback entries are released
to learners, including all ten comments. The student account and the parser
both show all ten assessments. Refresh the course's Leistungen tab in the app.

Release each assessment in the teacher portal under Leistungen > ausführlich
with its eye icon. Select Lernende mit Hinweistext and confirm with the teacher
password. The equivalent local tool is
`dart run tool/lessons/release_screenshot_marks.dart`. Its read-back is recorded
in the ignored `tool/lessons/run/mark_release.log`.

Portal documentation:
https://support.schulportal.hessen.de/knowledgebase.php?article=924

The teacher account cannot create exam-planner dates for this learning group.
The portal explicitly requires an account with the appropriate scheduling role.
No exam date was created.

The seed tools keep their IDs in `tool/lessons/run/screenshot_state.json`,
`screenshot_grades.json`, and `screenshot_feedback_marks.json`. The dataset is
intentionally retained and does not use the temporary fuzz-entry marker.
