import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart';

String sanitize(String html) {
  final d = parse(html);
  final content = d.getElementById('content');
  if (content == null) throw StateError('Missing #content');
  for (final e in content.querySelectorAll('script,img,style')) {
    e.remove();
  }
  // Keep only the dedicated course in overview cards, current entries and attendance rows.
  for (final e in content.querySelectorAll('#mappen .row > div')) {
    if (!e
        .querySelectorAll('a[href]')
        .any(
          (a) =>
              Uri.tryParse(a.attributes['href']!)?.queryParameters['id'] ==
              '20',
        )) {
      e.remove();
    }
  }
  for (final e in content.querySelectorAll(
    'tr.printable, #anwesend tbody > tr, #mappen table tbody > tr',
  )) {
    if (!e
        .querySelectorAll('a[href]')
        .any(
          (a) =>
              Uri.tryParse(a.attributes['href']!)?.queryParameters['id'] ==
              '20',
        )) {
      e.remove();
    }
  }
  for (final label in content.querySelectorAll(
    '#mappen table .label[title], #anwesend .label[title]',
  )) {
    label.attributes['title'] = 'Teacher';
    label.text = 'T';
  }
  for (final e in content.querySelectorAll('.hidden_encoded')) {
    e.text = 'ENCODED_TEST_VALUE';
  }
  var teacher = 0;
  for (final e in content.querySelectorAll('button[title]')) {
    if (!e.classes.contains('dropdown-toggle')) continue;
    teacher++;
    e.attributes['title'] = 'Teacher $teacher (T$teacher)';
    e.innerHtml =
        '<i class="fa fa-user"></i> T$teacher <span class="caret"></span>';
    for (final n in e.parent!.querySelectorAll('ul > li > a, ul > li > span')) {
      n.text = 'Teacher $teacher';
    }
  }
  for (final e in content.querySelectorAll('a[href]')) {
    if ((e.attributes['href'] ?? '').contains('nachrichten.php')) {
      e.attributes['href'] = '#';
    }
  }
  for (final e in content.querySelectorAll(
    '[data-toggle="tooltip"], [data-original-title]',
  )) {
    e.attributes.remove('data-original-title');
  }
  return '<!doctype html><html><head><meta charset="utf-8"></head><body>${content.outerHtml}</body></html>';
}

void main() {
  final dir = Directory('test/fixtures/lessons')..createSync(recursive: true);
  final files =
      Directory('tool/lessons/discovery')
          .listSync()
          .whereType<File>()
          .where(
            (f) => RegExp(
              r'/student_(?:[0-9]|visibility_|attendance_|fuzz_).*(?:overview|detail|upload|status)\.html$',
            ).hasMatch(f.path),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final old in dir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.html'),
  )) {
    old.deleteSync();
  }
  final seen = <String, String>{};
  final manifest = <Map<String, dynamic>>[];
  for (final file in files) {
    final body = sanitize(file.readAsStringSync());
    final hash = sha256.convert(utf8.encode(body)).toString();
    final name = file.path.split('/').last;
    final kept = seen[hash] ?? name;
    if (!seen.containsKey(hash)) {
      File('${dir.path}/$name').writeAsStringSync(body);
      seen[hash] = name;
    }
    manifest.add({
      'source': name,
      'fixture': kept,
      'sha256': hash,
      'provenance':
          'live student view; scoped to test course; scripts/navigation and personal identifiers removed',
    });
  }
  File(
    '${dir.path}/manifest.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  print(
    'Packed ${seen.length} distinct fixtures from ${files.length} captures',
  );
}
