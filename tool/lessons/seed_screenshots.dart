// Leave a persistent, fictional screenshot dataset in the dedicated course.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'capture_matrix.dart';
import 'capture_visibility.dart' show formValues;
import 'discover.dart' show login;

const inputs = 'tool/lessons/screenshot_inputs';
final stateFile = File('tool/lessons/run/screenshot_state.json');
final Map<String, dynamic> state = stateFile.existsSync()
    ? jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>
    : {};
void persist() {
  final tmp = File('${stateFile.path}.tmp')
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(state));
  tmp.renameSync(stateFile.path);
}

Future<void> upload(
  TestCoursePortal p,
  String entry,
  String filename, {
  bool student = false,
}) async {
  final response = await (student ? p.student : p.teacher).session!.dio.post(
    '${base}meinunterricht.php',
    data: FormData.fromMap({
      'a': student ? 'sus_abgabe' : 'uploadFileBook',
      if (student) ...{
        'b': course,
        'e': entry,
        'id': '1',
      } else ...{
        'id': course,
        'entry': entry,
      },
      student ? 'file1' : 'file': await MultipartFile.fromFile(
        '$inputs/$filename',
        filename: filename,
      ),
    }),
  );
  File(
    '${run.path}/screenshot_upload_${student ? 'student' : 'teacher'}_${entry}_$filename.response',
  ).writeAsStringSync('${response.data}');
}

Future<void> main(List<String> args) async {
  run.createSync(recursive: true);
  discovery.createSync(recursive: true);
  final lessons =
      (jsonDecode(File('$inputs/lessons.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
  if (args.contains('--dry-run')) {
    print(
      '${lessons.length} permanent lessons; attachments, five submissions, homework and attendance in course $courseName only.',
    );
    return;
  }
  final teacher = await login('teacher');
  final student = await login('student');
  final p = TestCoursePortal(teacher, student);
  try {
    await p.verify();
    final book = await p.get(
      teacher,
      'meinunterricht.php?a=editBook&id=$course',
    );
    final settings = formValues(parse(book).querySelector('form')!);
    final original = File('${run.path}/screenshot_original_book.html');
    if (!original.existsSync()) original.writeAsStringSync(book);
    await p.post(teacher, {
      ...settings,
      'Thema': '1',
      'Inhalt': '1',
      'Hausaufgaben': '1',
    });
    String? studentId;
    for (final lesson in lessons) {
      final key = lesson['key'] as String;
      final record = Map<String, dynamic>.from(state[key] as Map? ?? {});
      String? entry = record['id'] as String?;
      if (entry == null) {
        final date = lesson['date'] as String;
        final page = await p.teacherCourse();
        final existing = parse(page)
            .querySelectorAll('tr[data-entry]')
            .where(
              (r) =>
                  r.text.contains(lesson['subject'] as String) &&
                  r.text.contains(date),
            )
            .toList();
        if (existing.length > 1) {
          throw StateError(
            'Duplicate screenshot title/date; refusing another copy',
          );
        }
        if (existing.isNotEmpty) {
          entry = existing.single.attributes['data-entry']!;
        } else {
          final reply = await p.post(teacher, {
            'a': 'newBookEntry',
            'book': course,
            'datum': date,
            'stundenVon': lesson['from'],
            'stundenBis': lesson['to'],
            'subject': lesson['subject'],
            'inhalt': lesson['content'],
            'homework': lesson['homework'],
            'zeigeauchvorheran': 'ja',
            if (lesson['upload'] != null) 'abgabe': '1',
            'abgabeBis': '2026-11-30 18:00:00',
            'abgabeBisDate': '30.11.2026',
            'abgabeBisTime': '18:00',
            'abgabeSichtbar': 'Alle',
          });
          File(
            '${run.path}/screenshot_create_$key.response',
          ).writeAsStringSync(reply);
          final created = parse(await p.teacherCourse())
              .querySelectorAll('tr[data-entry]')
              .where(
                (r) =>
                    r.text.contains(lesson['subject'] as String) &&
                    r.text.contains(date),
              )
              .toList();
          if (created.length != 1) {
            throw StateError('Cannot verify screenshot lesson $key');
          }
          entry = created.single.attributes['data-entry']!;
        }
        record['id'] = entry;
        state[key] = record;
        persist();
      }
      final attachments = List<String>.from(
        record['attachments'] as List? ?? [],
      );
      for (final filename in (lesson['attachments'] as List).cast<String>()) {
        if (attachments.contains(filename)) continue;
        await upload(p, entry, filename);
        attachments.add(filename);
        record['attachments'] = attachments;
        state[key] = record;
        persist();
      }
      if (lesson['homework'] != '' && record['homeworkSet'] != true) {
        final response = await p.post(student, {
          'a': 'sus_homeworkDone',
          'entry': entry,
          'id': course,
          'b': lesson['homeworkDone'] == true ? 'done' : 'undone',
        });
        if (response.trim() != '1') {
          throw StateError('Homework update rejected for $key');
        }
        record['homeworkSet'] = true;
        state[key] = record;
        persist();
      }
      if (lesson['upload'] != null && record['submissionSet'] != true) {
        final submission = lesson['upload'] as Map<String, dynamic>;
        await p.setting(entry, 'Titel', submission['title'] as String);
        await p.setting(
          entry,
          'Text',
          'Bitte gib eine gut lesbare, nachvollziehbare Lösung ab. Prüfe vor dem Hochladen die Dateien und dokumentiere deine Arbeitsschritte.',
        );
        await p.setting(entry, 'MehrereDateien', 'ja');
        if (submission['file'] != null && record['uploaded'] != true) {
          await upload(p, entry, submission['file'] as String, student: true);
          record['uploaded'] = true;
          state[key] = record;
          persist();
        }
        final end = DateTime.parse(submission['deadline'] as String);
        await p.setting(
          entry,
          'Bis',
          '${end.day.toString().padLeft(2, '0')}.${end.month.toString().padLeft(2, '0')}.${end.year} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
        );
        record['submissionSet'] = true;
        state[key] = record;
        persist();
      }
      if (record['attendanceSet'] != true) {
        if (studentId == null) {
          final roster = parse(
            await p.get(
              teacher,
              'meinunterricht.php?a=attendance&id=$course&entry=$entry',
            ),
          );
          final user = student.session!.userData;
          final matches = roster
              .querySelectorAll('tr[data-id]')
              .where(
                (r) =>
                    r.children.first.text.trim() ==
                    '${user['nachname']}, ${user['vorname']}',
              )
              .toList();
          if (matches.length != 1) {
            throw StateError('Test student cannot be identified');
          }
          studentId = matches.single.attributes['data-id']!;
        }
        final index = int.parse(key.split('_').last);
        final presence = index == 7
            ? 'fehlend'
            : index == 15
            ? 'entschuldigt'
            : index == 20
            ? 'verspätet'
            : index == 17
            ? 'beurlaubt'
            : 'anwesend';
        await p.post(teacher, {
          'a': 'attendance',
          'id': course,
          'entry': entry,
          'data': teacher.session!.cryptor.encryptString(
            jsonEncode([
              {
                'id': studentId,
                'status': presence,
                if (presence == 'verspätet') 'number': '5',
                if (presence == 'beurlaubt') 'comment': 'Schulveranstaltung',
              },
            ]),
          ),
        });
        record['attendanceSet'] = true;
        state[key] = record;
        persist();
      }
      print('${lesson['date']}: ${lesson['subject']} (entry $entry)');
    }
    final detail = await p.get(
      student,
      'meinunterricht.php?a=sus_view&id=$course',
    );
    p.save('screenshot_ready_detail', detail);
    p.save(
      'screenshot_ready_overview',
      await p.get(student, 'meinunterricht.php'),
    );
    final result = LessonsStudentParser.parseDetailedDocument(
      parse(detail),
      courseID: course,
    );
    print(
      'Verified: history=${result.history.length}, attachments=${result.history.fold<int>(0, (n, e) => n + e.files.length)}, submissions=${result.history.fold<int>(0, (n, e) => n + e.uploads.length)}, marks=${result.marks.length}, exams=${result.exams.length}',
    );
    print('Screenshot dataset retained. No cleanup performed.');
  } finally {
    await student.dispose();
    await teacher.dispose();
  }
}
