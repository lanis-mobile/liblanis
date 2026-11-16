import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'capture_matrix.dart';
import 'capture_visibility.dart' show formValues;
import 'discover.dart' show login;

Future<void> main() async {
  final teacher = await login('teacher');
  final student = await login('student');
  final p = TestCoursePortal(teacher, student);
  try {
    await p.verify();
    final entries =
        jsonDecode(File('${run.path}/screenshot_state.json').readAsStringSync())
            as Map;
    final latestEntry = entries['lesson_23']['id'] as String;
    final html = await p.get(
      teacher,
      'meinunterricht.php?a=notenFaktoren&id=$course&halb=1',
    );
    final form = parse(html).querySelector('#content form')!;
    final factors = formValues(form)
      ..addAll({
        'faktormündlich': '2',
        'faktorschriftlich': '2',
        'faktorsonstige': '1',
      });
    for (final key in factors.keys.toList()) {
      if (RegExp(r'^note\d+$').hasMatch(key)) factors[key] = '1';
    }
    await teacher.session!.dio.post(
      '${base}meinunterricht.php',
      data: factors,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final storedFactors = formValues(
      parse(
        await p.get(
          teacher,
          'meinunterricht.php?a=notenFaktoren&id=$course&halb=1',
        ),
      ).querySelector('#content form')!,
    );
    print(
      'Saved grade weights: ${storedFactors.entries.where((e) => e.key.startsWith('note') || e.key.startsWith('faktor')).map((e) => '${e.key}=${e.value}').join(', ')}',
    );
    final response = await p.post(teacher, {
      'a': 'abgabenEditSmall',
      'buch': course,
      'eintrag': latestEntry,
      'abgabe': '1',
      'field': 'KommentarLehrende',
      'index': '1',
      'value':
          'Ein überzeugender Zwischenstand: klare Struktur und sinnvolle Funktionen. Ergänze für das Code-Review bitte noch Tests für leere Eingaben und die Tastaturbedienung.',
    });
    File(
      '${run.path}/screenshot_feedback_response.json',
    ).writeAsStringSync(response);
    final detail = await p.get(
      student,
      'meinunterricht.php?a=sus_view&id=$course',
    );
    p.save('screenshot_final_detail', detail);
    final overview = await p.get(student, 'meinunterricht.php');
    p.save('screenshot_final_overview', overview);
    final result = LessonsStudentParser.parseDetailedDocument(
      parse(detail),
      courseID: course,
    );
    final lessons = LessonsStudentParser.parseOverviewDocument(parse(overview));
    final current = lessons.firstWhere(
      (l) => l.courseID == course && !l.isOlder,
    );
    print(
      jsonEncode({
        'history': result.history.length,
        'marks': result.marks
            .map((m) => {'name': m.name, 'mark': m.mark, 'comment': m.comment})
            .toList(),
        'exams': result.exams.length,
        'attendance': result.attendances,
        'files': result.history.expand((e) => e.files).length,
        'submissions': result.history
            .expand((e) => e.uploads)
            .map(
              (u) => {
                'name': u.name,
                'status': u.status,
                'uploaded': u.uploaded,
              },
            )
            .toList(),
        'currentTopic': current.currentEntry?.topicTitle,
        'homeworkPending':
            current.currentEntry?.homework?.homeWorkDone == false,
      }),
    );
    final uploadPage = await p.get(
      student,
      'meinunterricht.php?a=sus_abgabe&b=$course&e=$latestEntry&id=1',
    );
    p.save('screenshot_final_upload', uploadPage);
    final info = LessonsStudentParser.parseUploadDocument(parse(uploadPage));
    print(
      'Own files and feedback: ${(info['own_files'] as List<OwnFile>).map((f) => '${f.name}: ${f.comment}').join('; ')}',
    );
  } finally {
    await student.dispose();
    await teacher.dispose();
  }
}
