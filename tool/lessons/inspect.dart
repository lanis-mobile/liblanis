import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart';
import 'discover.dart' show login;

Future<void> main() async {
  for (final role in ['teacher', 'student']) {
    final c = await login(role);
    try {
      final paths = role == 'teacher'
          ? {
              'upload_settings':
                  'meinunterricht.php?a=abgabenBookEntry&id=20&e=1&abg=1',
              'edit': 'meinunterricht.php?a=editBookEntry&id=20&entry=1',
              'attendance': 'meinunterricht.php?a=attendance&id=20&entry=1',
              'book': 'meinunterricht.php?a=editBook&id=20',
            }
          : {'upload': 'meinunterricht.php?a=sus_abgabe&b=20&e=1&id=1'};
      for (final p in paths.entries) {
        final html = (await c.session!.dio.get(
          'https://start.schulportal.hessen.de/${p.value}',
        )).data.toString();
        File(
          'tool/lessons/discovery/${role}_${p.key}.html',
        ).writeAsStringSync(html);
        final d = parse(html);
        print(
          jsonEncode({
            'role': role,
            'page': p.key,
            'forms': d
                .querySelectorAll('form')
                .map(
                  (f) => {
                    'action': f.attributes['action'],
                    'id': f.id,
                    'controls': f
                        .querySelectorAll('input,select,textarea,button[name]')
                        .map(
                          (e) => {
                            'tag': e.localName,
                            'name': e.attributes['name'],
                            'type': e.attributes['type'],
                            'value': e.attributes['value'],
                            'text': e.localName == 'select'
                                ? e.text.trim()
                                : null,
                          },
                        )
                        .toList(),
                  },
                )
                .toList(),
            'links': d
                .querySelectorAll('#content a')
                .map(
                  (a) => {'text': a.text.trim(), 'href': a.attributes['href']},
                )
                .toList(),
          }),
        );
      }
    } finally {
      await c.dispose();
    }
  }
}
