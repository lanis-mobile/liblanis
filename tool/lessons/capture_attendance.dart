import 'dart:convert';
import 'package:html/parser.dart';
import 'capture_matrix.dart';
import 'discover.dart' show login;

Future<void> main() async {
  discovery.createSync(recursive: true);
  run.createSync(recursive: true);
  final teacher = await login('teacher');
  final student = await login('student');
  final p = TestCoursePortal(teacher, student);
  try {
    await p.verify();
    await p.trackExisting();
    final entry = await p.add('attendance', subject: 'Attendance fixture');
    final page = parse(
      await p.get(
        teacher,
        'meinunterricht.php?a=attendance&id=$course&entry=$entry',
      ),
    );
    final user = student.session!.userData;
    final name = '${user['nachname']}, ${user['vorname']}';
    final rows = page
        .querySelectorAll('tr[data-id]')
        .where((r) => r.children.first.text.trim() == name)
        .toList();
    if (rows.length != 1) {
      throw StateError(
        'Cannot identify the logged-in test student; refusing attendance changes',
      );
    }
    final id = rows.single.attributes['data-id']!;
    for (final (i, status) in [
      'fehlend',
      'entschuldigt',
      'verspätet',
    ].indexed) {
      if (!rows.single
          .querySelectorAll('option')
          .any((o) => o.attributes['value'] == status)) {
        throw StateError('Status not offered by form');
      }
      await p.post(teacher, {
        'a': 'attendance',
        'id': course,
        'entry': entry,
        'data': teacher.session!.cryptor.encryptString(
          jsonEncode([
            {
              'id': id,
              'status': status,
              if (status == 'verspätet') 'number': '5',
            },
          ]),
        ),
      });
      final detail = await p.capture('attendance_$i');
      if (!parse(detail).querySelector('#history')!.text.contains(status)) {
        throw StateError('Attendance state $status not visible to student');
      }
    }
  } finally {
    await p.cleanup();
    await student.dispose();
    await teacher.dispose();
  }
}
