// Release only the ten fictional screenshot assessments to learners.
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'capture_matrix.dart';
import 'discover.dart' show login, credentials;

Future<void> main() async {
  final teacher = await login('teacher');
  final student = await login('student');
  final portal = TestCoursePortal(teacher, student);
  try {
    await portal.verify();
    final numeric =
        jsonDecode(
              File('${run.path}/screenshot_grades.json').readAsStringSync(),
            )
            as Map;
    final qualitative =
        jsonDecode(
              File(
                '${run.path}/screenshot_feedback_marks.json',
              ).readAsStringSync(),
            )
            as Map;
    final ids = <String>{
      for (final entry in numeric.values) '${entry['id']}',
      for (final id in qualitative.values) '$id',
    };
    final before = parse(
      await portal.get(
        teacher,
        'meinunterricht.php?a=notenTableFull&id=$course&halb=1',
      ),
    );
    if (before.querySelector('#content h1')?.attributes['data-book'] !=
        course) {
      throw StateError('Wrong course; refusing to change releases');
    }
    final password = credentials(
      '../lanis/.teacher.credentials.env',
    )['password']!;
    for (final id in ids) {
      final heading = before.querySelector('th[data-id="$id"]');
      final control = heading?.querySelector('.freigabeNote');
      if (heading == null || control == null) {
        throw StateError('Screenshot assessment $id missing');
      }
      final releases =
          (jsonDecode(control.attributes['data-freigaben']!) as List)
              .cast<String>()
              .toSet();
      releases.removeAll(['LernendeText', 'Lernende']);
      releases.add('LernendeHinweis');
      final result = await portal.post(teacher, {
        'a': 'notenFreigabe',
        'b': course,
        'n': id,
        'z[]': releases.toList(),
        'pw': teacher.session!.cryptor.encryptString(password),
      });
      if (result.trim() != '1') {
        throw StateError(
          'Release rejected for assessment $id: ${result.trim()}',
        );
      }
      print('Freigegeben: ${heading.attributes['data-name']}');
    }
    final page = await portal.get(
      student,
      'meinunterricht.php?a=sus_view&id=$course',
    );
    portal.save('screenshot_released_marks_student', page);
    final parsed = LessonsStudentParser.parseDetailedDocument(
      parse(page),
      courseID: course,
    );
    print(
      'Student sees ${parsed.marks.length} marks, ${parsed.marks.where((m) => m.comment != null).length} comments',
    );
    print(
      jsonEncode(
        parsed.marks
            .map((m) => {'name': m.name, 'mark': m.mark, 'comment': m.comment})
            .toList(),
      ),
    );
    if (parsed.marks.length != ids.length) {
      throw StateError(
        'Student mark count does not match released assessments',
      );
    }
  } finally {
    await student.dispose();
    await teacher.dispose();
  }
}
