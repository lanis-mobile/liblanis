import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'capture_matrix.dart';
import 'discover.dart' show login;

Map<String, dynamic> formValues(Element form) {
  final values = <String, dynamic>{};
  for (final field in form.querySelectorAll(
    'input[name],textarea[name],select[name]',
  )) {
    final name = field.attributes['name']!;
    final type = field.attributes['type'];
    if ((type == 'checkbox' || type == 'radio') &&
        !field.attributes.containsKey('checked')) {
      continue;
    }
    if (type == 'file' || type == 'submit') continue;
    final value = field.localName == 'textarea'
        ? field.text
        : field.localName == 'select'
        ? (field.querySelector('option[selected]') ??
                      field.querySelector('option'))
                  ?.attributes['value'] ??
              ''
        : field.attributes['value'] ?? '';
    if (values.containsKey(name)) {
      values[name] = [
        ...(values[name] is List ? values[name] : [values[name]]),
        value,
      ];
    } else {
      values[name] = value;
    }
  }
  return values;
}

Future<void> main() async {
  discovery.createSync(recursive: true);
  run.createSync(recursive: true);
  final teacher = await login('teacher');
  final student = await login('student');
  final p = TestCoursePortal(teacher, student);
  Map<String, dynamic>? original;
  try {
    await p.verify();
    await p.trackExisting();
    final book = await p.get(
      teacher,
      'meinunterricht.php?a=editBook&id=$course',
    );
    File('${run.path}/original_book.html').writeAsStringSync(book);
    final form = parse(book).querySelector('form')!;
    original = formValues(form);
    await p.add(
      'visibility',
      subject: 'Visibility fixture',
      homework: 'Visible homework',
    );
    for (var mask = 0; mask < 8; mask++) {
      final settings = Map<String, dynamic>.from(original);
      for (final (i, key) in ['Thema', 'Inhalt', 'Hausaufgaben'].indexed) {
        settings.remove(key);
        if (mask & (1 << i) != 0) settings[key] = '1';
      }
      await p.post(teacher, settings);
      final check = formValues(
        parse(
          await p.get(teacher, 'meinunterricht.php?a=editBook&id=$course'),
        ).querySelector('form')!,
      );
      for (final key in ['Thema', 'Inhalt', 'Hausaufgaben']) {
        if (check.containsKey(key) != settings.containsKey(key)) {
          throw StateError('Visibility $key did not persist');
        }
      }
      await p.capture('visibility_$mask');
    }
    final marks = await p.get(
      teacher,
      'meinunterricht.php?a=notenDaten&id=$course',
    );
    p.save('teacher_marks', marks);
    print(
      jsonEncode({
        'gradeForms': parse(
          marks,
        ).querySelectorAll('form').map((e) => formValues(e)).toList(),
      }),
    );
  } finally {
    if (original != null) {
      await p.post(teacher, original);
      final restored = formValues(
        parse(
          await p.get(teacher, 'meinunterricht.php?a=editBook&id=$course'),
        ).querySelector('form')!,
      );
      if (jsonEncode(restored) != jsonEncode(original)) {
        throw StateError('Course settings restore did not match snapshot');
      }
      print('Course visibility restored and verified');
    }
    await p.cleanup();
    await student.dispose();
    await teacher.dispose();
  }
}
