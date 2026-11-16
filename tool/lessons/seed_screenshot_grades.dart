import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'capture_matrix.dart';
import 'capture_visibility.dart' show formValues;
import 'discover.dart' show login;

final ledger = File('tool/lessons/run/screenshot_grades.json');
final Map<String, dynamic> saved = ledger.existsSync()
    ? jsonDecode(ledger.readAsStringSync()) as Map<String, dynamic>
    : {};
void persist() =>
    ledger.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(saved));
Future<void> main() async {
  final teacher = await login('teacher');
  final student = await login('student');
  final p = TestCoursePortal(teacher, student);
  try {
    await p.verify();
    print(
      'Available teacher apps: ${teacher.session!.travelMenu.map((e) => '${e['name'] ?? e['title']}: ${e['link']}').join('; ')}',
    );
    final specs = [
      {
        'key': 'exam',
        'id': '1',
        'title': 'Klausur 1: Algorithmen und Datenstrukturen',
        'date': '22.10.2026',
        'art': 'schriftlich',
        'score': '12',
        'comment':
            'Sicherer Umgang mit Kontrollstrukturen und Listen. Begründe bei komplexeren Aufgaben deine einzelnen Lösungsschritte noch genauer.',
      },
      {
        'key': 'oral',
        'id': '2',
        'title': 'Mitarbeit: Problemlösen und Teamarbeit',
        'date': '05.11.2026',
        'art': 'mündlich',
        'score': '13',
        'comment':
            'Du bringst eigene Ideen ein, erklärst deine Lösungen verständlich und unterstützt deine Gruppe zuverlässig.',
      },
      {
        'key': 'sql',
        'title': 'Praxistest: SQL und Datenbanken',
        'date': '29.10.2026',
        'art': 'schriftlich',
        'score': '14',
        'comment':
            'Sehr präzise Abfragen und eine überzeugende Dokumentation. Die Gruppierung und Sortierung der Ergebnisse gelingen dir besonders gut.',
      },
      {
        'key': 'programming',
        'title': 'Programmieren: Funktionen und Listen',
        'date': '17.09.2026',
        'art': 'sonstige',
        'score': '11',
        'comment':
            'Die Grundfunktionen arbeiten zuverlässig. Prüfe künftig auch leere Listen und ungültige Eingaben.',
      },
      {
        'key': 'project',
        'title': 'Projektsteckbrief: Digitaler Lernplaner',
        'date': '10.11.2026',
        'art': 'sonstige',
        'score': '13',
        'comment':
            'Klare Zielgruppe, gut formulierte Nutzergeschichten und ein realistischer Zeitplan. Achte auf messbare Abnahmekriterien.',
      },
      {
        'key': 'homework',
        'title': 'Hausaufgaben: Sorgfalt und Vollständigkeit',
        'date': '01.10.2026',
        'art': 'sonstige',
        'score': '15',
        'comment':
            'Alle Aufgaben vollständig und sorgfältig bearbeitet. Deine zusätzlichen Beispiele helfen beim Nachvollziehen der Lösungen.',
      },
    ];
    for (final spec in specs) {
      String? id = (saved[spec['key']] as Map?)?['id'] as String? ?? spec['id'];
      if (id == null) {
        final fields =
            formValues(
              parse(
                await p.get(
                  teacher,
                  'meinunterricht.php?a=notenDaten&id=$course',
                ),
              ).querySelector('form#leistung')!,
            )..addAll({
              'name': spec['title'],
              'datum': spec['date'],
              'art': spec['art'],
              'textfeld': 'ja',
              'erfassung': 'noten',
              'anznoten': '16',
              'fehlerindex': '0',
            });
        final validation = jsonDecode(
          await p.post(teacher, {...fields, 'isAJAX': 'true'}),
        );
        if (validation['back'] != true) {
          throw StateError('Grade validation failed');
        }
        final r = await teacher.session!.dio.post(
          '${base}meinunterricht.php',
          data: fields,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        final location = r.headers.value('location');
        if (location == null) throw StateError('Missing grade redirect');
        id = Uri.parse(location).queryParameters['noten'];
        if (id == null) throw StateError('Missing grade ID');
        saved[spec['key']!] = {'id': id};
        persist();
      }
      var html = await p.get(
        teacher,
        'meinunterricht.php?a=notenErfassung&id=$course&noten=$id',
      );
      var doc = parse(html);
      final h = doc.querySelector('#content h1');
      if (h?.attributes['data-book'] != course ||
          h?.attributes['data-klausur'] != id) {
        throw StateError('Grade does not belong to screenshot course');
      }
      for (final (field, value) in [
        ('name', spec['title']!),
        ('datum', spec['date']!.split('.').reversed.join('-')),
        ('art', spec['art']!),
      ]) {
        await p.post(teacher, {
          'a': 'notenEditSmall',
          'id': course,
          'noten': id,
          'field': field,
          'value': value,
        });
      }
      final user = student.session!.userData;
      final rows = doc
          .querySelectorAll('tr[data-id]')
          .where(
            (row) =>
                row.children.first.text.trim() ==
                '${user['nachname']}, ${user['vorname']}',
          )
          .toList();
      if (rows.length != 1) {
        throw StateError('Cannot identify test student in grade roster');
      }
      final studentId = rows.single.attributes['data-id']!;
      final result = jsonDecode(
        await p.post(teacher, {
          'a': 'notenErfassung',
          'id': course,
          'noten': id,
          'pupilsMarks': teacher.session!.cryptor.encryptString(
            jsonEncode([
              {
                'user': studentId,
                'note': spec['score'],
                'props': [],
                'append': [
                  {'freitext': spec['comment']},
                ],
              },
            ]),
          ),
        }),
      );
      if (result['back'] is! Map || result['back'][studentId] != true) {
        throw StateError('Grade not saved for test student');
      }
      saved[spec['key']!] = {
        'id': id,
        'title': spec['title'],
        'score': spec['score'],
      };
      persist();
      print('Saved ${spec['title']}: ${spec['score']}/15');
    }
    final table = await p.get(teacher, 'meinunterricht.php?a=notenTable&id=20');
    p.save('screenshot_grade_ready_table', table);
    final detail = await p.get(student, 'meinunterricht.php?a=sus_view&id=20');
    p.save('screenshot_grades_student_detail', detail);
    final result = LessonsStudentParser.parseDetailedDocument(
      parse(detail),
      courseID: course,
    );
    print('Student-visible marks: ${result.marks.length}');
    print(
      'Grade controls: ${parse(table).querySelectorAll('#content [data-url],#content [data-action],#content a[href*="noten"]').map((e) => e.outerHtml.substring(0, e.outerHtml.length.clamp(0, 350))).join('\n')}',
    );
  } finally {
    await student.dispose();
    await teacher.dispose();
  }
}
