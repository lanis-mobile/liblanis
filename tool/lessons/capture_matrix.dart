// Local mutations of the named fuzz course; no teacher parser used.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'discover.dart' show login, credentials;

const base = 'https://start.schulportal.hessen.de/';
const course = '20';
const courseName = 'Informatik 1 (fuzzTest-Gym)';
const marker = 'LIBLANIS_FUZZ_';
final discovery = Directory('tool/lessons/discovery');
final run = Directory('tool/lessons/run');

class TestCoursePortal {
  final EasyLanisClient teacher;
  final EasyLanisClient student;
  final created = <String>[];
  TestCoursePortal(this.teacher, this.student);
  Future<String> get(EasyLanisClient client, String path) async =>
      (await client.session!.dio.get(
        '$base$path',
        queryParameters: {
          '_cachebreaker': DateTime.now().millisecondsSinceEpoch,
        },
      )).data.toString();
  Future<String> post(
    EasyLanisClient client,
    Map<String, dynamic> values,
  ) async {
    final body = values.entries
        .expand(
          (e) => (e.value is List ? e.value as List : [e.value]).map(
            (v) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('$v')}',
          ),
        )
        .join('&');
    final r = await client.session!.dio.post(
      '${base}meinunterricht.php',
      data: body,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'X-Requested-With': 'XMLHttpRequest'},
      ),
    );
    return r.data.toString();
  }

  Future<String> teacherCourse() =>
      get(teacher, 'meinunterricht.php?a=view&id=$course');
  Future<void> verify() async {
    final d = parse(await get(teacher, 'meinunterricht.php?jump=no'));
    if (!d
        .querySelectorAll('a')
        .any(
          (a) =>
              a.text.trim() == courseName &&
              a.attributes['href'] == 'meinunterricht.php?a=view&id=$course',
        )) {
      throw StateError('Named test course missing; refusing writes');
    }
  }

  Future<void> trackExisting() async {
    final d = parse(await teacherCourse());
    for (final row in d.querySelectorAll('tr[data-entry]')) {
      if (row.text.contains(marker)) created.add(row.attributes['data-entry']!);
    }
    persist();
  }

  void persist() => File(
    '${run.path}/created_entries.json',
  ).writeAsStringSync(jsonEncode(created));
  Future<String> add(
    String name, {
    String subject = 'Fuzz lesson',
    String homework = '',
    String date = '12.11.2026',
    bool visible = true,
    bool upload = false,
    String from = '1',
    String to = '2',
  }) async {
    final label = '$marker$name';
    final r = await post(teacher, {
      'a': 'newBookEntry',
      'book': course,
      'datum': date,
      'stundenVon': from,
      'stundenBis': to,
      'subject': subject.isEmpty ? '' : '$label $subject',
      'inhalt': label,
      'homework': homework,
      if (visible) 'zeigeauchvorheran': 'ja',
      if (upload) 'abgabe': '1',
      'abgabeBis': '2026-11-19 14:00:00',
      'abgabeBisDate': '19.11.2026',
      'abgabeBisTime': '14:00',
      'abgabeSichtbar': 'Alle',
    });
    File('${discovery.path}/create_$name.json').writeAsStringSync(r);
    final page = await teacherCourse();
    final rows = parse(page)
        .querySelectorAll('tr[data-entry]')
        .where((r) => r.text.contains(label))
        .toList();
    if (rows.length != 1) throw StateError('Creation not confirmed for $name');
    final id = rows.single.attributes['data-entry']!;
    created.add(id);
    persist();
    return id;
  }

  Future<void> setting(String entry, String field, String value) async {
    final result = await post(teacher, {
      'a': 'abgabenEditSmall',
      'buch': course,
      'eintrag': entry,
      'abgabe': '1',
      'field': field,
      'value': value,
    });
    File('${discovery.path}/setting_$field.json').writeAsStringSync(result);
    final parsed = jsonDecode(result);
    if (parsed is! Map || '${parsed['status']}' != '1') {
      throw StateError('Upload setting $field was rejected');
    }
  }

  Future<String> capture(String name, {String? contains}) async {
    String detail = '';
    for (var attempt = 0; attempt < 4; attempt++) {
      detail = await get(student, 'meinunterricht.php?a=sus_view&id=$course');
      if (contains == null || detail.contains(contains)) break;
      if (attempt == 3) throw StateError('Student page did not show $contains');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    save('student_${name}_detail', detail);
    save('student_${name}_overview', await get(student, 'meinunterricht.php'));
    print(
      'Captured $name: ${parse(detail).querySelectorAll('#history table > tbody > tr').length} history rows',
    );
    return detail;
  }

  void save(String name, String html) =>
      File('${discovery.path}/$name.html').writeAsStringSync(html);
  Future<void> captureUpload(String name, String entry) async => save(
    'student_${name}_upload',
    await get(
      student,
      'meinunterricht.php?a=sus_abgabe&b=$course&e=$entry&id=1',
    ),
  );
  Future<void> upload(
    String entry,
    String filename, {
    bool attachment = false,
  }) async {
    final client = attachment ? teacher : student;
    final fields = <String, dynamic>{
      'a': attachment ? 'uploadFileBook' : 'sus_abgabe',
      if (attachment) 'id': course,
      if (attachment) 'entry': entry,
      if (!attachment) ...{'b': course, 'e': entry, 'id': '1'},
      attachment ? 'file' : 'file1': MultipartFile.fromString(
        'liblanis fixture file\n',
        filename: filename,
      ),
    };
    final response = await client.session!.dio.post(
      '${base}meinunterricht.php',
      data: FormData.fromMap(fields),
    );
    if (attachment) {
      File(
        '${discovery.path}/attachment_response.json',
      ).writeAsStringSync('${response.data}');
    } else {
      save(
        'student_${filename.replaceAll('.', '_')}_status',
        '${response.data}',
      );
    }
  }

  Future<void> cleanup() async {
    final env = credentials('../lanis/.teacher.credentials.env');
    for (final id in created.toList().reversed) {
      final current = parse(await teacherCourse());
      final row = current.querySelector('tr[data-entry="$id"]');
      if (row == null) {
        created.remove(id);
        persist();
        continue;
      }
      if (!row.text.contains(marker)) {
        throw StateError('Refusing to delete entry without fuzz marker');
      }
      final result = await post(teacher, {
        'a': 'deleteBookEntry',
        'b': course,
        'e': id,
        'pw': teacher.session!.cryptor.encryptString(env['password']!),
      });
      if (result.trim() != '1') {
        throw StateError('Cleanup rejected for entry $id');
      }
      created.remove(id);
      persist();
    }
    print('Cleanup verified: no generated entries remain');
  }
}

Future<void> main(List<String> args) async {
  discovery.createSync(recursive: true);
  run.createSync(recursive: true);
  if (args.contains('--dry-run')) {
    print(
      'Course $courseName ($course): empty, blank, unicode/homework, future hidden/visible, attachments, public/private uploads, one-shot, expired, rejected type; cleanup in finally',
    );
    return;
  }
  final teacher = await login('teacher');
  EasyLanisClient? student;
  try {
    student = await login('student');
    final p = TestCoursePortal(teacher, student);
    await p.verify();
    await p.trackExisting();
    if (args.contains('--cleanup-only')) {
      await p.cleanup();
      return;
    }
    // A previous interrupted run is cleaned before starting, never duplicated.
    await p.cleanup();
    try {
      await p.capture('00_empty');
      await p.add('blank', subject: '');
      await p.capture('01_blank');
      await p.add(
        'unicode',
        subject: 'Grüße <>& "quotes" 🧪',
        homework: '**Bold**\nA & B < C\nhttps://example.invalid',
        from: '3',
        to: '3',
      );
      await p.capture('02_homework', contains: 'LIBLANIS_FUZZ_unicode');
      await p.add('future_hidden', date: '20.11.2026', visible: false);
      final hidden = await p.capture('03_future_hidden');
      if (parse(hidden)
          .querySelector('#history')!
          .text
          .contains('LIBLANIS_FUZZ_future_hidden')) {
        throw StateError('Future hidden entry leaked');
      }
      await p.add('future_visible', date: '20.11.2026');
      await p.capture(
        '04_future_visible',
        contains: 'LIBLANIS_FUZZ_future_visible',
      );
      final entry = await p.add(
        'upload',
        subject: 'Upload fixture',
        homework: 'Upload homework',
        upload: true,
      );
      await p.capture('05_upload_open', contains: 'LIBLANIS_FUZZ_upload');
      await p.captureUpload('05_open', entry);
      await p.upload(entry, 'teacher_attachment.txt', attachment: true);
      await p.capture('06_attachment', contains: 'teacher_attachment.txt');
      await p.upload(entry, 'fuzz_student.txt');
      await p.captureUpload('07_own_public', entry);
      await p.capture('07_uploaded');
      await p.setting(entry, 'Text', 'Fuzz upload instructions');
      await p.setting(entry, 'Titel', 'Fuzz upload 🧪');
      await p.setting(entry, 'MehrereDateien', 'nein');
      await p.captureUpload('08_single_file', entry);
      await p.setting(entry, 'SichtbarFuer', 'Lehrende');
      await p.captureUpload('09_private', entry);
      await p.setting(entry, 'Dateitypen', 'GIF, JPEG, JPG, PNG');
      await p.upload(entry, 'fuzz_rejected.txt');
      await p.captureUpload('10_images_only', entry);
      await p.setting(entry, 'Einmalabgabe', 'ja');
      await p.captureUpload('11_once_submitted', entry);
      await p.capture('11_once_submitted');
      await p.setting(entry, 'Von', '18.11.2026 08:00');
      await p.captureUpload('12_not_started', entry);
      await p.setting(entry, 'Von', '11.11.2026 08:00');
      await p.setting(entry, 'Bis', '12.11.2026 00:01');
      await p.captureUpload('13_expired', entry);
      await p.capture('13_expired');
      print(
        'Student identity keys: ${student.session!.userData.keys.join(',')}',
      );
    } finally {
      await p.cleanup();
    }
  } finally {
    await student?.dispose();
    await teacher.dispose();
  }
}
