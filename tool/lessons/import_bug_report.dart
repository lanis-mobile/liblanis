// Import already-extracted HTML bodies from the local debug-report archive.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

void replaceText(Element element, String value) {
  final nodes = <Text>[];
  void visit(Node node) {
    if (node is Text) nodes.add(node);
    for (final child in node.nodes) {
      visit(child);
    }
  }

  visit(element);
  if (nodes.isEmpty) {
    element.nodes.add(Text(value));
    return;
  }
  for (final node in nodes) {
    node.text = '';
  }
  nodes.first.text = value;
}

void main() {
  final inputs = {
    'course_detail': File('temp/export_fach_einzeln.html'),
    'overview': File('temp/export_uebersicht.html'),
  };
  final documents = {
    for (final entry in inputs.entries)
      entry.key: parse(entry.value.readAsStringSync()),
  };
  final courseIds = <String, String>{};
  final teachers = <String, int>{};
  final filenames = <String, String>{};
  String courseId(String old) =>
      courseIds.putIfAbsent(old, () => '${1001 + courseIds.length}');
  String fileName(String old) => filenames.putIfAbsent(old, () {
    final extension = old.contains('.')
        ? old.split('.').last.toLowerCase()
        : 'txt';
    return 'attachment_${filenames.length + 1}.$extension';
  });
  String entryId(String old) => '${int.parse(old) + 100}';
  String teacherAlias(String old) =>
      'Fixture Teacher ${teachers.putIfAbsent(old, () => teachers.length + 1)}';
  String teacherCode(String old) {
    teacherAlias(old);
    return 'T${teachers[old]}';
  }

  String date(String raw) => raw.replaceAllMapped(
    RegExp(r'\b(\d{2})\.(\d{2})\.2026\b'),
    (m) => '${m[1]}.${m[2]}.2024',
  );
  final primary = documents['course_detail']!
      .querySelector('#content h1')!
      .attributes['data-book']!;
  courseId(primary);
  final out = Directory('test/fixtures/lessons/reports')
    ..createSync(recursive: true);
  final metadata = <Map<String, dynamic>>[];
  for (final report in documents.entries) {
    final content = report.value.getElementById('content')!;
    for (final node in content.querySelectorAll(
      'script,style,img,link,template',
    )) {
      node.remove();
    }
    for (final button in content.querySelectorAll(
      'button.dropdown-toggle[title]',
    )) {
      final identity = button.text.trim();
      final alias = teacherAlias(identity);
      final code = teacherCode(identity);
      button.attributes['title'] = '$alias ($code)';
      replaceText(button, code);
      for (final item in button.parent!.querySelectorAll(
        'ul > li > a, ul > li > span',
      )) {
        replaceText(item, alias);
      }
    }
    for (final label in content.querySelectorAll(
      '#anwesend .label[title], #mappen table .label[title]',
    )) {
      final identity = label.text.trim();
      label.attributes['title'] =
          '${teacherAlias(identity)} (${teacherCode(identity)})';
      replaceText(label, teacherCode(identity));
    }
    for (final link in content.querySelectorAll('a[href]')) {
      final uri = Uri.tryParse(link.attributes['href']!);
      if (uri == null || uri.path != 'meinunterricht.php') {
        link.attributes['href'] = '#';
        continue;
      }
      final params = Map<String, String>.from(uri.queryParameters);
      final oldCourse = params['id'];
      if (oldCourse != null) {
        params['id'] = courseId(oldCourse);
        if (params['a'] == 'sus_view') {
          replaceText(
            link,
            'Test course ${int.parse(courseId(oldCourse)) - 1000}',
          );
        }
      }
      for (final key in ['e', 'entry']) {
        if (params[key] != null) params[key] = entryId(params[key]!);
      }
      if (params['f'] != null) params['f'] = fileName(params['f']!);
      params.removeWhere(
        (key, value) =>
            !['a', 'id', 'halb', 'e', 'entry', 'b', 'abg', 'f'].contains(key),
      );
      link.attributes['href'] = uri.replace(queryParameters: params).toString();
    }
    for (final card in content.querySelectorAll('#mappen .row > div')) {
      final link = card.querySelector('a.btn.btn-primary[href]');
      final id = Uri.tryParse(
        link?.attributes['href'] ?? '',
      )?.queryParameters['id'];
      if (id != null) {
        final heading = card.querySelector('h2');
        if (heading != null) {
          replaceText(heading, 'Test course ${int.parse(id) - 1000}');
        }
      }
    }
    if (report.key == 'course_detail') {
      final heading = content.querySelector('h1')!;
      for (final text in heading.nodes.whereType<Text>()) {
        if (text.text.trim().isNotEmpty) text.text = 'Test course 1';
      }
      for (final (index, row)
          in content.querySelectorAll('#history tr[data-entry]').indexed) {
        final cells = row.children;
        final topic = cells[1].querySelector('b');
        if (topic != null) replaceText(topic, 'Test topic ${index + 1}');
        for (final markup in cells[1].querySelectorAll('.markup')) {
          replaceText(
            markup,
            markup.querySelector('i') == null
                ? 'Homework for test entry ${index + 1}.'
                : 'Description for test entry ${index + 1}.',
          );
        }
        if (cells.length > 2) {
          final presence = cells[2].text.contains('nicht erfasst')
              ? 'nicht erfasst'
              : 'anwesend';
          replaceText(cells[2], presence);
        }
      }
      for (final row in content.querySelectorAll('#attendanceTable tbody tr')) {
        if (row.children.length > 1) replaceText(row.children[1], '0');
      }
    }
    for (final (index, row)
        in content.querySelectorAll('tr.printable').indexed) {
      final topic = row.querySelector('.thema');
      if (topic != null) replaceText(topic, 'Test topic ${index + 1}');
      final homework = row.querySelector('.realHomework');
      if (homework != null) {
        replaceText(homework, 'Homework for test course ${index + 1}.');
      }
    }
    for (final (index, markup)
        in content.querySelectorAll('.inhalt .markup').indexed) {
      replaceText(markup, 'Description for test course ${index + 1}.');
    }
    for (final button in content.querySelectorAll('button.dropdown-toggle')) {
      if (button.attributes['title']?.startsWith('Fixture Teacher') != true) {
        replaceText(button, 'Courses');
      }
    }
    for (final row in content.querySelectorAll('#anwesend tbody tr')) {
      for (final cell in row.children.skip(2)) {
        replaceText(cell, '0');
      }
    }
    for (final file in content.querySelectorAll('.file[data-file]')) {
      final name = fileName(file.attributes['data-file']!);
      file.attributes['data-file'] = name;
      final label = file.localName == 'a' ? file : file.querySelector('a');
      if (label != null) replaceText(label, name);
    }
    for (final encoded in content.querySelectorAll('.hidden_encoded')) {
      encoded.text = 'ENCODED_FIXTURE_VALUE';
    }
    for (final element in [content, ...content.querySelectorAll('*')]) {
      final isTeacher =
          element.localName == 'button' &&
              element.classes.contains('dropdown-toggle') ||
          element.classes.contains('label') &&
              element.attributes['title']?.startsWith('Fixture Teacher') ==
                  true;
      element.attributes.removeWhere(
        (key, value) =>
            ![
              'class',
              'id',
              'href',
              'name',
              'rowspan',
              'colspan',
              'data-entry',
              'data-book',
              'data-file',
              'data-extension',
              'title',
            ].contains(key.toString()) ||
            key == 'title' && !isTeacher,
      );
      if (element.attributes['data-book'] != null) {
        element.attributes['data-book'] = courseId(
          element.attributes['data-book']!,
        );
      }
      if (element.attributes['data-entry'] != null) {
        element.attributes['data-entry'] = entryId(
          element.attributes['data-entry']!,
        );
      }
      final id = element.attributes['id'];
      if (id != null) element.attributes['id'] = id.replaceAll('2026', '2024');
      for (final node in element.nodes.whereType<Text>()) {
        node.text = date(node.text);
      }
    }
    final html =
        '<!doctype html><html><head><meta charset="utf-8"></head><body>${content.outerHtml}</body></html>\n';
    final filename = 'anonymized_${report.key}.html';
    File('${out.path}/$filename').writeAsStringSync(html);
    metadata.add({
      'fixture': filename,
      'source': report.key == 'course_detail'
          ? 'export_fach_einzeln.txt'
          : 'export_uebersicht.txt',
      'sha256': sha256.convert(utf8.encode(html)).toString(),
      'provenance':
          'Anonymized user-provided debug-report response body. Navigation and scripts removed; teacher dropdown tag structure retained; names, IDs, dates, topics, homework, filenames and attendance values replaced.',
    });
  }
  File(
    '${out.path}/manifest.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metadata));
  print('Imported ${metadata.length} anonymized report fixtures');
}
