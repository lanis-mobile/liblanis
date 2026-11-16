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
  final file = File('${run.path}/screenshot_feedback_marks.json');
  final Map<String, dynamic> ledger = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : {};
  void persist() => file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(ledger),
  );
  try {
    await p.verify();
    final specs = [
      {
        'key': 'participation',
        'name': 'Mitarbeit: Argumentieren und Erklären',
        'scale': '35',
        'value': 'gut',
        'comment':
            'Du erklärst deine Lösungswege verständlich und greifst die Ideen anderer auf. Nutze Fachbegriffe noch etwas gezielter.',
      },
      {
        'key': 'homework',
        'name': 'Hausaufgaben: Sorgfalt und Vollständigkeit',
        'scale': '37',
        'value': 'gemacht',
        'comment':
            'Die Aufgaben sind vollständig bearbeitet. Deine Testfälle zeigen, dass du auch Grenzsituationen berücksichtigt hast.',
      },
      {
        'key': 'teamwork',
        'name': 'Projektarbeit: Zusammenarbeit',
        'scale': '36',
        'value': '++',
        'comment':
            'Sehr verlässliche Zusammenarbeit. Aufgaben sind klar verteilt, Fortschritte werden dokumentiert und Feedback wird konstruktiv umgesetzt.',
      },
      {
        'key': 'progress',
        'name': 'Lernfortschritt: Selbstständiges Arbeiten',
        'scale': '35',
        'value': 'sehr gut',
        'comment':
            'Du findest zunehmend selbstständig passende Lösungsstrategien und dokumentierst wichtige Entscheidungen nachvollziehbar.',
      },
    ];
    for (final spec in specs) {
      String? id = ledger[spec['key']] as String?;
      if (id == null) {
        final data =
            formValues(
              parse(
                await p.get(teacher, 'meinunterricht.php?a=notenDaten&id=20'),
              ).querySelector('#leistung')!,
            )..addAll({
              'name': spec['name'],
              'datum': '12.11.2026',
              'art': 'sonstige',
              'textfeld': 'ja',
              'erfassung': 'noten',
              'anznoten': spec['scale'],
              'fehlerindex': '0',
            });
        final r = await teacher.session!.dio.post(
          '${base}meinunterricht.php',
          data: data,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        final location = r.headers.value('location');
        if (location == null) {
          throw StateError('Missing qualitative grade redirect');
        }
        id = Uri.parse(location).queryParameters['noten'];
        if (id == null) throw StateError('Missing qualitative grade ID');
        ledger[spec['key']!] = id;
        persist();
      }
      final page = parse(
        await p.get(
          teacher,
          'meinunterricht.php?a=notenErfassung&id=20&noten=$id',
        ),
      );
      final user = student.session!.userData;
      final row = page
          .querySelectorAll('tr[data-id]')
          .singleWhere(
            (r) =>
                r.children.first.text.trim() ==
                '${user['nachname']}, ${user['vorname']}',
          );
      final pupil = row.attributes['data-id']!;
      final option = row
          .querySelectorAll('select option')
          .singleWhere((e) => e.text.trim() == spec['value']);
      final value = option.attributes['value']!;
      final reply = jsonDecode(
        await p.post(teacher, {
          'a': 'notenErfassung',
          'id': course,
          'noten': id,
          'pupilsMarks': teacher.session!.cryptor.encryptString(
            jsonEncode([
              {
                'user': pupil,
                'note': value,
                'props': [],
                'append': [
                  {'freitext': spec['comment']},
                ],
              },
            ]),
          ),
        }),
      );
      if (reply['back'][pupil] != true) {
        throw StateError('Qualitative grade save failed');
      }
      print('Saved ${spec['name']}: ${spec['value']}');
    }
    final html = await p.get(student, 'meinunterricht.php?a=sus_view&id=20');
    p.save('screenshot_feedback_marks_student', html);
    final result = LessonsStudentParser.parseDetailedDocument(
      parse(html),
      courseID: course,
    );
    print(
      'Student-visible marks: ${result.marks.map((m) => '${m.name}: ${m.mark}').join('; ')}',
    );
  } finally {
    await student.dispose();
    await teacher.dispose();
  }
}
