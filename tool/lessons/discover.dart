import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';

Map<String, String> credentials(String path) {
  return {
    for (final raw in File(path).readAsLinesSync())
      if (raw.trim().isNotEmpty &&
          !raw.trim().startsWith('#') &&
          raw.contains('='))
        raw.split('=').first.trim().toLowerCase(): raw
            .substring(raw.indexOf('=') + 1)
            .trim()
            .replaceAll(RegExp(r'''^['"]|['"]$'''), ''),
  };
}

Future<EasyLanisClient> login(String role) async {
  final env = credentials('../lanis/.$role.credentials.env');
  final client = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['schoolid']!),
    username: env['username']!,
    password: env['password']!,
  );
  await client.login();
  return client;
}

Future<void> main(List<String> args) async {
  for (final role in ['teacher', 'student']) {
    final c = await login(role);
    try {
      final url = args.isEmpty ? 'meinunterricht.php?jump=no' : args.first;
      final r = await c.session!.dio.get(
        'https://start.schulportal.hessen.de/$url',
      );
      final html = r.data.toString();
      Directory('tool/lessons/discovery').createSync(recursive: true);
      File(
        'tool/lessons/discovery/${role}_${args.length > 1 ? args[1] : 'home'}.html',
      ).writeAsStringSync(html);
      final d = parse(html);
      print(
        jsonEncode({
          'role': role,
          'status': r.statusCode,
          'title': d.querySelector('title')?.text.trim(),
          'links': d
              .querySelectorAll('a[href*="meinunterricht"]')
              .map((e) => {'text': e.text.trim(), 'href': e.attributes['href']})
              .toList(),
          'forms': d
              .querySelectorAll('form')
              .map(
                (f) => {
                  'action': f.attributes['action'],
                  'id': f.id,
                  'controls': f
                      .querySelectorAll('input,select,textarea')
                      .map(
                        (e) => {
                          'tag': e.localName,
                          'name': e.attributes['name'],
                          'type': e.attributes['type'],
                          'value': e.attributes['type'] == 'password'
                              ? 'REDACTED'
                              : e.attributes['value'],
                        },
                      )
                      .toList(),
                },
              )
              .toList(),
        }),
      );
    } finally {
      await c.dispose();
    }
  }
}
