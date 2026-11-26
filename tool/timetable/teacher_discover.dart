import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' show parse;
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

Map<String, String> loadDotEnv(String path) {
  final map = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final i = line.indexOf('=');
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    map[line.substring(0, i).trim().toLowerCase()] = v;
  }
  return map;
}

String cb() => '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

Future<EasyLanisClient> login(String envPath) async {
  final env = loadDotEnv(envPath);
  final client = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['schoolid']!),
    username: env['username']!,
    password: env['password']!,
    userAgent: 'liblanis-teacher-timetable-discover/0.1.0',
  );
  await client.login();
  return client;
}

Map<String, Object?> summarizeDoc(String html, Uri uri, int? statusCode) {
  final doc = parse(html);
  final links = doc
      .querySelectorAll('a[href*="stundenplan.php"]')
      .map((e) => {
            'href': e.attributes['href'] ?? '',
            'text': e.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          })
      .toList();
  final selects = doc.querySelectorAll('select').map((s) {
    return {
      'id': s.id,
      'name': s.attributes['name'],
      'options': s
          .querySelectorAll('option')
          .map((o) => {
                'value': o.attributes['value'],
                'text': o.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
                'selected': o.attributes.containsKey('selected'),
              })
          .take(25)
          .toList(),
      'optionCount': s.querySelectorAll('option').length,
    };
  }).toList();
  final forms = doc.querySelectorAll('form').map((f) {
    return {
      'action': f.attributes['action'],
      'method': f.attributes['method'],
      'id': f.id,
      'inputs': f
          .querySelectorAll('input, select, textarea, button')
          .map((el) => {
                'tag': el.localName,
                'type': el.attributes['type'],
                'name': el.attributes['name'],
                'id': el.id,
                'value': el.attributes['value'],
                'checked': el.attributes.containsKey('checked'),
                'text': el.localName == 'button'
                    ? el.text.replaceAll(RegExp(r'\s+'), ' ').trim()
                    : null,
              })
          .toList(),
    };
  }).toList();
  final tables = doc.querySelectorAll('table').map((t) {
    return {
      'id': t.id,
      'class': t.className,
      'rows': t.querySelectorAll('tr').length,
      'headers': t
          .querySelectorAll('thead th, tr:first-child th, tr:first-child td')
          .map((c) => c.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .take(15)
          .toList(),
      'stundeCount': t.querySelectorAll('.stunde').length,
    };
  }).toList();
  final headings = doc
      .querySelectorAll('h1, h2, h3, h4, .panel-title, .card-title, .nav-tabs li, .nav-pills li')
      .map((e) => '${e.localName}.${e.className}: ${e.text.replaceAll(RegExp(r'\s+'), ' ').trim()}')
      .where((t) => !t.endsWith(': '))
      .toList();
  return {
    'uri': uri.toString(),
    'status': statusCode,
    'bytes': html.length,
    'headings': headings,
    'links': links,
    'selects': selects,
    'forms': forms,
    'tables': tables,
  };
}

Future<void> discoverFor(
  String role,
  String envPath,
  Directory outDir,
) async {
  final roleDir = Directory(p.join(outDir.path, role))..createSync(recursive: true);
  final client = await login(envPath);
  try {
    final session = client.session!;
    stdout.writeln('[$role] logged in: accountType=${session.accountTypeOrNull} userData=${session.userData}');

    final summary = <String, Object?>{
      'accountType': session.accountTypeOrNull?.toString(),
      'userData': session.userData,
    };

    // 1. Fetch stundenplan.php directly (follow redirects manually or check 302)
    final resp0 = await session.dio.get(
      'https://start.schulportal.hessen.de/stundenplan.php?${cb()}',
    );
    var html0 = resp0.data.toString();
    final loc0 = resp0.headers.value('location');
    summary['root_status'] = resp0.statusCode;
    summary['root_location'] = loc0;
    summary['root_realUri'] = resp0.realUri.toString();
    await File(p.join(roleDir.path, 'root.html')).writeAsString(html0);
    summary['root'] = summarizeDoc(html0, resp0.realUri, resp0.statusCode);

    if (loc0 != null && loc0.isNotEmpty) {
      final redir = resp0.realUri.resolve(loc0);
      final resp1 = await session.dio.getUri(redir);
      final html1 = resp1.data.toString();
      await File(p.join(roleDir.path, 'root_redirected.html')).writeAsString(html1);
      summary['root_redirected'] = summarizeDoc(html1, resp1.realUri, resp1.statusCode);
      html0 = html1;
    }

    // Collect all unique stundenplan.php links from root page
    final doc0 = parse(html0);
    final hrefs = <String>{};
    for (final a in doc0.querySelectorAll('a[href*="stundenplan.php"]')) {
      final h = a.attributes['href']?.trim();
      if (h != null && h.isNotEmpty && !h.contains('pdf') && !h.contains('delete')) {
        hrefs.add(h);
      }
    }
    // Also probe known/guessed teacher endpoints
    final probes = <String>[
      ...hrefs,
      'stundenplan.php?a=start',
      'stundenplan.php?a=detail',
      'stundenplan.php?a=detail_klasse',
      'stundenplan.php?a=detail_raum',
      'stundenplan.php?a=detail_kurs',
      'stundenplan.php?a=detail_lehrer',
      'stundenplan.php?a=pausenaufsicht',
      'stundenplan.php?a=pausenaufsichten',
      'stundenplan.php?a=aufsicht',
      'stundenplan.php?a=aufsichten',
      'stundenplan.php?a=admin',
      'stundenplan.php?a=upload',
      'stundenplan.php?a=wochen',
      'stundenplan.php?a=raster',
      'stundenplan.php?a=leistenplan',
    ].toSet();

    final pages = <String, Object?>{};
    var idx = 0;
    for (final href in probes) {
      idx++;
      final uri = Uri.parse('https://start.schulportal.hessen.de/').resolve(href);
      try {
        final r = await session.dio.getUri(uri);
        final h = r.data.toString();
        final slug = href
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
        await File(p.join(roleDir.path, '${idx}_$slug.html')).writeAsString(h);
        pages[href] = {
          'location': r.headers.value('location'),
          ...summarizeDoc(h, r.realUri, r.statusCode),
        };
        stdout.writeln('[$role] GET $href -> ${r.statusCode} (${h.length}b) loc=${r.headers.value('location')}');
      } catch (e) {
        pages[href] = {'error': e.toString()};
        stdout.writeln('[$role] GET $href -> ERR $e');
      }
    }
    summary['pages'] = pages;

    await File(p.join(roleDir.path, 'summary.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary),
    );
  } finally {
    await client.logout();
    await client.dispose();
  }
}

Future<void> main() async {
  final outDir = Directory('tool/timetable/discovery/teacher_probe')
    ..createSync(recursive: true);
  await discoverFor('admin', '../.teacher.credentials.admin.env', outDir);
  await discoverFor('unpriv', '../.teacher.credentials.unpriv.env', outDir);
  stdout.writeln('Done! Summaries written under ${outDir.path}');
}
