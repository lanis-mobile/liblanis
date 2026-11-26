import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:liblanis/liblanis.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

const fixtureDir = 'test/fixtures/lessons';
final manifest =
    (jsonDecode(File('$fixtureDir/manifest.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
Document fixture(String source) {
  final entry = manifest.singleWhere(
    (e) => e['source'] == 'student_$source.html',
  );
  return parse(File('$fixtureDir/${entry['fixture']}').readAsStringSync());
}

DetailedLesson detail(Document doc) =>
    LessonsStudentParser.parseDetailedDocument(doc, courseID: '20');

class _Context implements AppletContext {
  @override
  final LanisSession session;
  _Context(this.session);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements LanisSession {
  @override
  final Dio dio;
  _Session(HttpClientAdapter adapter)
    : dio = Dio()..httpClientAdapter = adapter;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailureAdapter implements HttpClientAdapter {
  final DioExceptionType type;
  _FailureAdapter(this.type);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    throw DioException(
      requestOptions: options,
      type: type,
      message: 'fuzz upload transport failure',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('manifest covers the live content and visibility matrix', () {
    expect(manifest.length, greaterThanOrEqualTo(40));
    for (final name in [
      '00_empty_detail',
      '01_blank_detail',
      '06_attachment_detail',
      '11_once_submitted_upload',
      '13_expired_upload',
      for (var i = 0; i < 8; i++) 'visibility_${i}_detail',
    ]) {
      expect(() => fixture(name), returnsNormally, reason: name);
    }
  });

  group('live student fixtures', () {
    for (final item in manifest) {
      final source = item['source'] as String;
      test(source, () {
        final doc = parse(
          File('$fixtureDir/${item['fixture']}').readAsStringSync(),
        );
        if (source.endsWith('_detail.html')) {
          final rows = doc.querySelectorAll(
            '#history table > tbody > tr[data-entry]',
          );
          final result = detail(doc);
          expect(result.name, 'Informatik 1 (fuzzTest-Gym)');
          expect(result.history.length, rows.length);
          expect(
            result.history.map((e) => e.entryID),
            rows.map((e) => e.attributes['data-entry']),
          );
          expect(
            result.history.map((e) => e.topicTitle),
            rows.map((e) => e.children[1].querySelector('b')?.text.trim()),
          );
          expect(
            result.history.expand((e) => e.files).map((f) => f.name),
            doc
                .querySelectorAll('#history .file[data-file]')
                .map((e) => e.attributes['data-file']),
          );
          final uploadLinks = doc.querySelectorAll(
            '#history .btn-group ul a[href*="sus_abgabe"]',
          );
          expect(
            result.history.expand((e) => e.uploads).map((u) => u.url.query),
            uploadLinks.map((e) => Uri.parse(e.attributes['href']!).query),
          );
          expect(
            result.teachers.length,
            doc.querySelectorAll('button[title].dropdown-toggle').length,
          );
        } else if (source.endsWith('_overview.html')) {
          final result = LessonsStudentParser.parseOverviewDocument(doc);
          final cards = doc.querySelectorAll('#mappen .row > div');
          final olderRows = doc.querySelectorAll(
            '#mappen table tbody tr[data-book]',
          );
          expect(result.length, cards.length + olderRows.length);
          expect(
            result.where((lesson) => lesson.isOlder).length,
            olderRows.length,
          );
          expect(result.map((l) => l.courseID), everyElement('20'));
          for (final lesson in result) {
            expect(lesson.name, courseName);
            final current = doc
                .querySelectorAll('tr.printable')
                .where((r) => r.querySelector('.datum') != null);
            expect(
              lesson.currentEntry?.entryID,
              lesson.isOlder || current.isEmpty
                  ? null
                  : current.first.attributes['data-entry'],
            );
          }
        } else if (source.endsWith('_upload.html')) {
          final result = LessonsStudentParser.parseUploadDocument(doc);
          expect(result['course_id'], '20');
          expect(
            result['entry_id'],
            doc.querySelector('h1')!.attributes['data-eintrag'],
          );
          expect(result['upload_id'], '1');
          final own =
              doc
                  .querySelector('a[name="eigene"]')
                  ?.parent
                  ?.querySelectorAll('ul > li') ??
              <Element>[];
          expect((result['own_files'] as List<OwnFile>).length, own.length);
          for (final file in result['own_files'] as List<OwnFile>) {
            expect(file.name, 'fuzz_student.txt');
            expect(file.index, '1');
            expect(Uri.parse(file.url).queryParameters['f'], file.index);
          }
          expect(result['start'], contains('Uhr'));
          expect(result['deadline'], contains('Uhr'));
          expect(result['allowed_file_types'], isNotEmpty);
        } else if (source.endsWith('_status.html')) {
          final result = LessonsStudentParser.parseUploadStatusDocument(doc);
          expect(result, hasLength(1));
          expect(
            result.single.name,
            source.contains('rejected')
                ? 'fuzz_rejected.txt'
                : 'fuzz_student.txt',
          );
          expect(
            result.single.status,
            source.contains('rejected') ? 'fehlgeschlagen' : 'erfolgreich',
          );
        }
      });
    }
  });

  test('older-only overview keeps names, teachers and first-semester URL', () {
    final result = LessonsStudentParser.parseOverviewDocument(
      fixture('00_empty_overview'),
    );
    expect(result, hasLength(1));
    final older = result.single;
    expect(older.isOlder, isTrue);
    expect(older.courseID, '20');
    expect(older.name, courseName);
    expect(older.courseURL.queryParameters['halb'], '1');
    expect(older.teachers, hasLength(2));
    expect(older.teachers.map((teacher) => teacher.teacherKuerzel), ['T', 'T']);
    expect(older.currentEntry, isNull);
  });

  test('current and older semesters of the same course remain separate', () {
    final doc = fixture('02_homework_overview');
    final row = fixture(
      '00_empty_overview',
    ).querySelector('#mappen tr[data-book]')!.clone(true);
    doc.querySelector('#mappen table tbody')!.append(row);
    final result = LessonsStudentParser.parseOverviewDocument(doc);
    expect(result.map((lesson) => lesson.isOlder), [false, true]);
    expect(result.map((lesson) => lesson.courseID), ['20', '20']);
    expect(result.first.currentEntry, isNotNull);
    expect(result.last.currentEntry, isNull);
    expect(result.last.courseURL.queryParameters['halb'], '1');
  });

  test(
    'overview without an older-course table still returns current courses',
    () {
      final doc = fixture('02_homework_overview');
      for (final table in doc.querySelectorAll('#mappen table')) {
        table.remove();
      }
      final result = LessonsStudentParser.parseOverviewDocument(doc);
      expect(result, hasLength(1));
      expect(result.single.isOlder, isFalse);
    },
  );

  test('empty course has no history, marks or exams', () {
    final result = detail(fixture('00_empty_detail'));
    expect(result.history, isEmpty);
    expect(result.marks, isEmpty);
    expect(result.exams, isEmpty);
  });
  test('blank topic is retained as a real history entry', () {
    final result = detail(fixture('01_blank_detail'));
    expect(result.history, hasLength(1));
    expect(result.history.single.topicTitle, 'kein Thema');
    expect(result.history.single.topicDate, DateTime(2026, 11, 12));
    expect(result.history.single.schoolHours, '1. - 2.');
  });
  test(
    'all visibility settings keep the entry and expose only enabled fields',
    () {
      for (var mask = 0; mask < 8; mask++) {
        final entry = detail(
          fixture('visibility_${mask}_detail'),
        ).history.single;
        expect(
          entry.topicTitle,
          mask & 1 != 0
              ? 'LIBLANIS_FUZZ_visibility Visibility fixture'
              : isNull,
        );
        expect(
          entry.description,
          mask & 2 != 0 ? 'LIBLANIS_FUZZ_visibility' : isNull,
        );
        expect(
          entry.homework?.description,
          mask & 4 != 0 ? 'Visible homework' : isNull,
        );
      }
    },
  );

  test(
    'future visibility controls entries rather than losing visible data',
    () {
      expect(detail(fixture('03_future_hidden_detail')).history, hasLength(2));
      final visible = detail(fixture('04_future_visible_detail'));
      expect(visible.history, hasLength(3));
      expect(
        visible.history.any(
          (e) => e.topicTitle?.contains('future_hidden') ?? false,
        ),
        isFalse,
      );
      expect(
        visible.history.any(
          (e) => e.topicTitle?.contains('future_visible') ?? false,
        ),
        isTrue,
      );
    },
  );
  test('attachment filenames and download parameters survive parsing', () {
    final files = detail(
      fixture('06_attachment_detail'),
    ).history.expand((e) => e.files).toList();
    expect(files, hasLength(1));
    expect(files.single.name, 'teacher_attachment.txt');
    expect(files.single.url!.queryParameters['f'], 'teacher_attachment.txt');
    expect(files.single.url!.queryParameters.containsKey('b'), isFalse);
  });
  test(
    'attachment download URLs encode names without changing other parameters',
    () {
      final doc = fixture('06_attachment_detail');
      const name = 'Grüße & spaces.txt';
      doc.querySelector('#history .file[data-file]')!.attributes['data-file'] =
          name;
      final file = detail(doc).history.expand((e) => e.files).single;
      expect(file.name, name);
      expect(file.url!.queryParameters['f'], name);
      expect(file.url!.queryParameters['id'], '20');
    },
  );

  test(
    'single file permission is independent of repeat submission permission',
    () {
      final result = LessonsStudentParser.parseUploadDocument(
        fixture('08_single_file_upload'),
      );
      expect(result['upload_multiple_files'], isFalse);
      expect(result['upload_any_number_of_times'], isTrue);
      expect(result['additional_text'], contains('Fuzz upload instructions'));
    },
  );
  test('LANIS-MOBILE-87: one-shot page retains IDs after form disappears', () {
    final doc = fixture('11_once_submitted_upload');
    expect(doc.querySelector('form'), isNull);
    final result = LessonsStudentParser.parseUploadDocument(doc);
    expect(result['course_id'], '20');
    expect(result['entry_id'], isNotEmpty);
    expect(result['upload_id'], '1');
    expect(result['upload_any_number_of_times'], isFalse);
    expect(result['own_files'], hasLength(1));
  });
  test(
    'expired and future submissions retain requirements and existing files',
    () {
      for (final name in ['12_not_started_upload', '13_expired_upload']) {
        final result = LessonsStudentParser.parseUploadDocument(fixture(name));
        expect(result['course_id'], '20');
        expect(result['own_files'], hasLength(1));
        expect(result['allowed_file_types'], ['GIF', 'JPEG', 'JPG', 'PNG']);
      }
      final history = detail(fixture('13_expired_detail')).history;
      expect(history.expand((e) => e.uploads).single.status, 'closed');
    },
  );
  test('upload dates still match the student view date contract', () async {
    await initializeDateFormatting('de');
    DateTime date(String value) => DateFormat('EEEE d.M.yy H:mm', 'de').parse(
      value.replaceAll(',', '').replaceAll(' den', '').replaceAll(' Uhr', ''),
    );
    final open = LessonsStudentParser.parseUploadDocument(
      fixture('05_open_upload'),
    );
    expect(date(open['start'] as String), DateTime(2026, 11, 12, 8));
    expect(date(open['deadline'] as String), DateTime(2026, 11, 19, 14));
    final expired = LessonsStudentParser.parseUploadDocument(
      fixture('13_expired_upload'),
    );
    expect(date(expired['deadline'] as String), DateTime(2026, 11, 12, 0, 1));
  });

  test('live attendance states belong to the test student and entry', () {
    for (final (i, status) in [
      'fehlend',
      'entschuldigt',
      'verspätet',
    ].indexed) {
      final result = detail(fixture('attendance_${i}_detail'));
      expect(result.history, hasLength(1));
      expect(result.history.single.presence, contains(status));
      final overview = LessonsStudentParser.parseOverviewDocument(
        fixture('attendance_${i}_overview'),
      );
      expect(overview, hasLength(1));
      expect(overview.single.attendances, isNotEmpty);
    }
  });

  test(
    'upload layout fuzz preserves file identifiers and permission flags',
    () {
      final random = Random(87);
      for (var iteration = 0; iteration < 160; iteration++) {
        final doc = fixture('07_own_public_upload');
        if (random.nextBool()) doc.querySelector('form')?.remove();
        if (random.nextBool()) {
          doc
              .querySelector('#content .row')!
              .nodes
              .insert(
                0,
                Element.html('<div class="col-md-12">Extra layout block</div>'),
              );
        }
        for (final label in doc.querySelectorAll(
          'i.fa-check-square-o + span.label',
        )) {
          if (random.nextBool()) label.innerHtml = '<b>erlaubt</b>';
        }
        final info = LessonsStudentParser.parseUploadDocument(doc);
        expect(info['course_id'], '20');
        expect(info['upload_multiple_files'], isTrue);
        expect(info['upload_any_number_of_times'], isTrue);
        final own = (info['own_files'] as List<OwnFile>).single;
        expect(own.name, 'fuzz_student.txt');
        expect(own.index, '1');
      }
    },
  );

  test('public file owner, name and encoded download URL are retained', () {
    final doc = fixture('07_own_public_upload');
    doc.querySelector('#content .col-md-5')!.innerHtml =
        '<ul><li><a href="meinunterricht.php?a=downloadFile&amp;id=20&amp;e=1&amp;abg=1&amp;f=42">Grüße &amp; test.txt</a><span class="label label-info">Student 1</span></li></ul>';
    final info = LessonsStudentParser.parseUploadDocument(doc);
    final file = (info['public_files'] as List<PublicFile>).single;
    expect(file.name, 'Grüße & test.txt');
    expect(file.person, 'Student 1');
    expect(file.index, '42');
    expect(Uri.parse(file.url).queryParameters['f'], '42');
  });

  test('course 20 attendance never attaches to a course whose ID is 2', () {
    final doc = fixture('attendance_0_overview');
    final card = doc.querySelector('#mappen .row > div')!.clone(true);
    card.querySelector('a.btn.btn-primary')!.attributes['href'] =
        'meinunterricht.php?a=sus_view&id=2';
    doc.querySelector('#mappen .row')!.nodes.insert(0, card);
    final lessons = LessonsStudentParser.parseOverviewDocument(doc);
    expect(lessons.singleWhere((l) => l.courseID == '2').attendances, isNull);
    expect(
      lessons.singleWhere((l) => l.courseID == '20').attendances,
      isNotNull,
    );
  });

  test(
    'original bug report: unlinked teacher span parses with all 18 entries',
    () {
      final doc = parse(
        File(
          '$fixtureDir/reports/anonymized_course_detail.html',
        ).readAsStringSync(),
      );
      final button = doc
          .getElementsByClassName('btn btn-primary dropdown-toggle btn-md')
          .single;
      // This is the original, unmodified element layout that broke the old parser.
      expect(button.parent!.querySelector('ul > li > a'), isNull);
      expect(
        button.parent!.querySelector('ul > li > span')!.text.trim(),
        'Fixture Teacher 1',
      );
      final result = LessonsStudentParser.parseDetailedDocument(
        doc,
        courseID: '1001',
      );
      expect(result.name, 'Test course 1');
      expect(result.teachers.single.teacher, 'Fixture Teacher 1');
      expect(result.teachers.single.teacherKuerzel, 'T1');
      expect(result.history, hasLength(18));
      expect(result.history.first.entryID, '120');
      expect(result.history.first.topicTitle, 'Test topic 1');
      expect(result.history.first.topicDate, DateTime(2024, 11, 9));
      expect(
        result.history.expand((entry) => entry.files).map((file) => file.name),
        [
          'attachment_1.pdf',
          'attachment_2.pdf',
          'attachment_3.pdf',
          'attachment_4.pdf',
        ],
      );
    },
  );

  test('original bug report: anonymized overview retains all ten courses', () {
    final doc = parse(
      File('$fixtureDir/reports/anonymized_overview.html').readAsStringSync(),
    );
    final result = LessonsStudentParser.parseOverviewDocument(doc);
    expect(result, hasLength(10));
    expect(
      result.where((lesson) => lesson.currentEntry != null),
      hasLength(10),
    );
    final course = result.singleWhere((lesson) => lesson.courseID == '1001');
    expect(course.name, 'Test course 1');
    expect(course.teachers.single.teacher, 'Fixture Teacher 1');
    expect(course.currentEntry!.entryID, '120');
    expect(
      result.every((lesson) => lesson.name.startsWith('Test course ')),
      isTrue,
    );
  });

  test('anonymized report fixtures match their provenance hashes', () {
    final reports =
        jsonDecode(File('$fixtureDir/reports/manifest.json').readAsStringSync())
            as List;
    expect(reports, hasLength(2));
    for (final report in reports) {
      final html = File(
        '$fixtureDir/reports/${report['fixture']}',
      ).readAsStringSync();
      expect(sha256.convert(utf8.encode(html)).toString(), report['sha256']);
      final doc = parse(html);
      expect(doc.querySelectorAll('script,img,style,template'), isEmpty);
      expect(
        doc
            .querySelectorAll('[title]')
            .every(
              (e) => e.attributes['title']!.startsWith('Fixture Teacher '),
            ),
        isTrue,
      );
      expect(RegExp(r'\b[a-f0-9]{24,}\b').hasMatch(html), isFalse);
      for (final link in doc.querySelectorAll('a[href]')) {
        final uri = Uri.parse(link.attributes['href']!);
        expect(uri.hasAuthority, isFalse);
        final id = uri.queryParameters['id'];
        if (id != null) expect(int.parse(id), inInclusiveRange(1001, 1010));
      }
    }
  });

  test(
    'LANIS-MOBILE-A: absent attendance section preserves courses with null maps',
    () {
      final doc = fixture('02_homework_overview');
      doc.querySelector('#anwesend')!.remove();
      final lessons = LessonsStudentParser.parseOverviewDocument(doc);
      expect(lessons, hasLength(1));
      expect(lessons.single.attendances, isNull);
      expect(lessons.single.currentEntry, isNotNull);
    },
  );
  test('compact date markup and upload buttons keep history fields', () {
    final doc = fixture('06_attachment_detail');
    for (final row in doc.querySelectorAll('#history tr[data-entry]')) {
      row.children[0].innerHtml = row.children[0].innerHtml.replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
    }
    for (final button in doc.querySelectorAll('#history .btn-group button')) {
      button.innerHtml =
          '<i></i>Abgabe<span class="badge">2</span><small>bis 19.11.</small>';
    }
    final result = detail(doc);
    expect(result.history, hasLength(4));
    expect(result.history.expand((e) => e.uploads).single.name, 'Abgabe');
    expect(result.history.every((e) => e.topicDate != null), isTrue);
  });
  test('missing optional tabs do not discard history', () {
    final doc = fixture('06_attachment_detail');
    for (final id in ['marks', 'klausuren', 'attendanceTable']) {
      doc.getElementById(id)?.remove();
    }
    final result = detail(doc);
    expect(result.history, hasLength(4));
    expect(result.marks, isEmpty);
    expect(result.exams, isEmpty);
  });
  test('grade comments belong only to their grade and keep colons', () {
    final doc = fixture('00_empty_detail');
    doc.getElementById('marks')!.innerHtml =
        '<table><tbody><tr><td>Exam A</td><td>12.11.2026</td><td>12</td></tr><tr><td colspan="2"></td><td>Kommentar: A: B</td></tr><tr><td>Exam B</td><td>13.11.2026</td><td>13</td></tr></tbody></table>';
    final result = detail(doc);
    expect(result.marks, hasLength(2));
    expect(result.marks.first.comment, 'A: B');
    expect(result.marks.last.comment, isNull);
  });
  test(
    'seeded layout fuzz preserves entry identities across 160 mutations',
    () {
      final random = Random(20261112);
      final expected = detail(
        fixture('06_attachment_detail'),
      ).history.map((e) => e.entryID).toList();
      for (var i = 0; i < 160; i++) {
        final doc = fixture('06_attachment_detail');
        if (random.nextBool()) doc.getElementById('marks')?.remove();
        if (random.nextBool()) doc.getElementById('klausuren')?.remove();
        if (random.nextBool()) doc.getElementById('attendanceTable')?.remove();
        for (final e in doc.querySelectorAll('.hidden_encoded')) {
          if (random.nextBool()) e.remove();
        }
        if (random.nextBool()) {
          final h = doc.querySelector('#content h1')!;
          for (final e in h.children.toList()) {
            e.remove();
          }
        }
        expect(
          detail(doc).history.map((e) => e.entryID),
          expected,
          reason: 'seed=20261112 iteration=$i',
        );
      }
    },
  );
  test(
    'malformed/authentication pages fail with a Lanis error rather than Dart errors',
    () {
      for (final source in [
        '',
        '<html>Login required</html>',
        '<div id="content"><h1>Wrong page</h1></div>',
      ]) {
        expect(() => detail(parse(source)), throwsA(isA<LanisException>()));
        expect(
          () => LessonsStudentParser.parseOverviewDocument(parse(source)),
          throwsA(isA<LanisException>()),
        );
        expect(
          () => LessonsStudentParser.parseUploadDocument(parse(source)),
          throwsA(isA<LanisException>()),
        );
        expect(
          () => LessonsStudentParser.parseUploadStatusDocument(parse(source)),
          throwsA(isA<LanisException>()),
        );
      }
    },
  );
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
    DioExceptionType.badResponse,
  ]) {
    test(
      'LANIS-MOBILE-CA: upload $type remains typed and includes transport details',
      () async {
        final session = _Session(_FailureAdapter(type));
        final parser = LessonsStudentParser(
          _Context(session),
          isConnected: () async => true,
        );
        addTearDown(parser.dispose);
        addTearDown(() => session.dio.close(force: true));
        await expectLater(
          parser.uploadFile(
            course: '20',
            entry: '1',
            upload: '1',
            file1: MultipartFile.fromString('fuzz', filename: 'fuzz.txt'),
          ),
          throwsA(
            isA<NetworkException>().having(
              (e) => e.cause,
              'cause',
              contains('fuzz upload transport failure'),
            ),
          ),
        );
      },
    );
  }

  test(
    'parses teacher conversationReceiverId in detail and propagates from #aktuell to #mappen and older courses',
    () {
      const detailHtml = '''
<div id="content">
  <h1 data-book="20">Informatik 1</h1>
  <div class="btn-group">
    <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Caputo, Alessio (CAP)">CAP</button>
    <ul class="dropdown-menu">
      <li><span>Caputo, Alessio</span></li>
      <li role="separator" class="divider"></li>
      <li><a title="Nachricht schreiben" href="nachrichten.php?to[]=bC0zMTY5ODM=}">Nachricht schreiben</a></li>
    </ul>
  </div>
  <div id="history"><table><tbody></tbody></table></div>
</div>
''';
      final detailed = LessonsStudentParser.parseDetailedDocument(
        parse(detailHtml),
        courseID: '20',
      );
      expect(detailed.teachers.single.teacherKuerzel, 'CAP');
      expect(detailed.teachers.single.conversationReceiverId, 'l-316983');

      const overviewHtml = '''
<div id="content">
  <div id="aktuell">
    <table><tbody>
      <tr class="printable" data-entry="500">
        <td>
          <h3><a href="meinunterricht.php?a=sus_view&amp;id=20">Informatik 1</a></h3>
          <div class="btn-group">
            <button type="button" class="btn btn-primary dropdown-toggle btn-xs" title="Caputo, Alessio (CAP)">CAP</button>
            <ul class="dropdown-menu">
              <li><span>Caputo, Alessio</span></li>
              <li><a href="nachrichten.php?to[]=bC0zMTY5ODM=}">Nachricht schreiben</a></li>
            </ul>
          </div>
          <span class="datum">12.11.2026</span>
          <span class="thema">Topic</span>
        </td>
      </tr>
    </tbody></table>
  </div>
  <div id="mappen">
    <div class="row">
      <div>
        <h2>Informatik 1</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Caputo, Alessio (CAP)">CAP</button>
          <ul class="dropdown-menu">
            <li><span>Caputo, Alessio</span></li>
          </ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=20">Open</a>
      </div>
      <div>
        <h2>Informatik 2</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Caputo, Alessio (CAP)">CAP</button>
          <ul class="dropdown-menu">
            <li><span>Caputo, Alessio</span></li>
          </ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=21">Open</a>
      </div>
    </div>
    <table><tbody>
      <tr data-book="20">
        <td><a href="meinunterricht.php?a=sus_view&amp;id=20&amp;halb=1">Informatik 1 (alt)</a></td>
        <td><span class="label" title="Caputo, Alessio (CAP)">CAP</span></td>
      </tr>
    </tbody></table>
  </div>
</div>
''';
      final lessons = LessonsStudentParser.parseOverviewDocument(
        parse(overviewHtml),
      );
      expect(lessons, hasLength(3));
      for (final lesson in lessons) {
        expect(
          lesson.teachers.single.conversationReceiverId,
          'l-316983',
          reason: 'lesson ${lesson.name} (isOlder=${lesson.isOlder})',
        );
      }
    },
  );

  test(
    'teacher ID propagation does not leak across colliding kuerzel or names',
    () {
      const overviewHtml = '''
<div id="content">
  <div id="aktuell">
    <table><tbody>
      <tr class="printable" data-entry="600">
        <td>
          <h3><a href="meinunterricht.php?a=sus_view&amp;id=30">Mathe</a></h3>
          <div class="btn-group">
            <button type="button" class="btn btn-primary dropdown-toggle btn-xs" title="Müller, Anna (MUE)">MUE</button>
            <ul class="dropdown-menu">
              <li><a href="nachrichten.php?to[]=bC0xMDUwNDQ=}">Nachricht schreiben</a></li>
            </ul>
          </div>
          <span class="datum">12.11.2026</span>
          <span class="thema">Topic</span>
        </td>
      </tr>
    </tbody></table>
  </div>
  <div id="mappen">
    <div class="row">
      <div>
        <h2>Mathe</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Müller, Anna (MUE)">MUE</button>
          <ul class="dropdown-menu"><li><span>Müller, Anna</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=30">Open</a>
      </div>
      <div>
        <h2>Physik</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Müller, Peter (MUE)">MUE</button>
          <ul class="dropdown-menu"><li><span>Müller, Peter</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=31">Open</a>
      </div>
      <div>
        <h2>Chemie</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Müller, Anna (MUA)">MUA</button>
          <ul class="dropdown-menu"><li><span>Müller, Anna</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=32">Open</a>
      </div>
    </div>
  </div>
</div>
''';
      final lessons = LessonsStudentParser.parseOverviewDocument(
        parse(overviewHtml),
      );
      final byId = {for (final l in lessons) l.courseID: l};
      expect(byId['30']!.teachers.single.conversationReceiverId, 'l-105044');
      expect(byId['31']!.teachers.single.conversationReceiverId, isNull);
      expect(byId['32']!.teachers.single.conversationReceiverId, isNull);
    },
  );

  test(
    'parses teacher email in detail and propagates email alongside conversationReceiverId across overview',
    () {
      const detailHtml = '''
<div id="content">
  <h1 data-book="20">Informatik 1</h1>
  <div class="btn-group">
    <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Caputo, Alessio (CAP)">CAP</button>
    <ul class="dropdown-menu">
      <li><span>Caputo, Alessio</span></li>
      <li role="separator" class="divider"></li>
      <li><a title="Nachricht schreiben" href="nachrichten.php?to[]=bC0zMTY5ODM=}">Nachricht schreiben</a></li>
      <li><a href="MAILTO:alessio.caputo@example.invalid?subject=Informatik">E-Mail senden</a></li>
    </ul>
  </div>
  <div class="btn-group">
    <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Weber, Anna (WEB)">WEB</button>
    <ul class="dropdown-menu">
      <li><span>Weber, Anna</span></li>
      <li><a href="mailto:anna.weber%40example.invalid">E-Mail senden</a></li>
    </ul>
  </div>
  <div class="btn-group">
    <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Klein, Tom (KLE)">KLE</button>
    <ul class="dropdown-menu">
      <li><span>Klein, Tom</span></li>
      <li><a href="mailto:?subject=Empty">E-Mail senden</a></li>
      <li><a href="mailto:not-an-email">Invalid</a></li>
    </ul>
  </div>
  <div id="history"><table><tbody></tbody></table></div>
</div>
''';
      final detailed = LessonsStudentParser.parseDetailedDocument(
        parse(detailHtml),
        courseID: '20',
      );
      expect(detailed.teachers, hasLength(3));
      expect(detailed.teachers[0].teacherKuerzel, 'CAP');
      expect(detailed.teachers[0].conversationReceiverId, 'l-316983');
      expect(detailed.teachers[0].email, 'alessio.caputo@example.invalid');
      expect(detailed.teachers[1].teacherKuerzel, 'WEB');
      expect(detailed.teachers[1].conversationReceiverId, isNull);
      expect(detailed.teachers[1].email, 'anna.weber@example.invalid');
      expect(detailed.teachers[2].teacherKuerzel, 'KLE');
      expect(detailed.teachers[2].conversationReceiverId, isNull);
      expect(detailed.teachers[2].email, isNull);

      // Overview: #aktuell has conversationReceiverId for CAP and email-only for WEB,
      // while #mappen has email for CAP on course 20 and neither on course 21 / older row.
      const overviewHtml = '''
<div id="content">
  <div id="aktuell">
    <table><tbody>
      <tr class="printable" data-entry="500">
        <td>
          <h3><a href="meinunterricht.php?a=sus_view&amp;id=20">Informatik 1</a></h3>
          <div class="btn-group">
            <button type="button" class="btn btn-primary dropdown-toggle btn-xs" title="Caputo, Alessio (CAP)">CAP</button>
            <ul class="dropdown-menu">
              <li><span>Caputo, Alessio</span></li>
              <li><a href="nachrichten.php?to[]=bC0zMTY5ODM=}">Nachricht schreiben</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button type="button" class="btn btn-primary dropdown-toggle btn-xs" title="Weber, Anna (WEB)">WEB</button>
            <ul class="dropdown-menu">
              <li><span>Weber, Anna</span></li>
              <li><a href="mailto:anna.weber@example.invalid?subject=Hi">E-Mail senden</a></li>
            </ul>
          </div>
          <span class="datum">12.11.2026</span>
          <span class="thema">Topic</span>
        </td>
      </tr>
    </tbody></table>
  </div>
  <div id="mappen">
    <div class="row">
      <div>
        <h2>Informatik 1</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Caputo, Alessio (CAP)">CAP</button>
          <ul class="dropdown-menu">
            <li><span>Caputo, Alessio</span></li>
            <li><a href="mailto:alessio.caputo@example.invalid">E-Mail senden</a></li>
          </ul>
        </div>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Weber, Anna (WEB)">WEB</button>
          <ul class="dropdown-menu">
            <li><span>Weber, Anna</span></li>
          </ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=20">Open</a>
      </div>
      <div>
        <h2>Informatik 2</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Caputo, Alessio (CAP)">CAP</button>
          <ul class="dropdown-menu"><li><span>Caputo, Alessio</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=21">Open</a>
      </div>
    </div>
    <table><tbody>
      <tr data-book="20">
        <td><a href="meinunterricht.php?a=sus_view&amp;id=20&amp;halb=1">Informatik 1 (alt)</a></td>
        <td>
          <span class="label" title="Caputo, Alessio (CAP)">CAP</span>
          <span class="label" title="Weber, Anna (WEB)">WEB</span>
        </td>
      </tr>
    </tbody></table>
  </div>
</div>
''';
      final lessons = LessonsStudentParser.parseOverviewDocument(
        parse(overviewHtml),
      );
      expect(lessons, hasLength(3));
      final byName = {for (final l in lessons) l.name: l};

      for (final name in ['Informatik 1', 'Informatik 2', 'Informatik 1 (alt)']) {
        final cap = byName[name]!.teachers.singleWhere(
          (t) => t.teacherKuerzel == 'CAP',
        );
        expect(cap.conversationReceiverId, 'l-316983', reason: name);
        expect(cap.email, 'alessio.caputo@example.invalid', reason: name);
      }

      for (final name in ['Informatik 1', 'Informatik 1 (alt)']) {
        final web = byName[name]!.teachers.singleWhere(
          (t) => t.teacherKuerzel == 'WEB',
        );
        expect(web.conversationReceiverId, isNull, reason: name);
        expect(web.email, 'anna.weber@example.invalid', reason: name);
      }
    },
  );

  test(
    'teacher email propagation does not leak across colliding kuerzel or names',
    () {
      const overviewHtml = '''
<div id="content">
  <div id="aktuell">
    <table><tbody>
      <tr class="printable" data-entry="601">
        <td>
          <h3><a href="meinunterricht.php?a=sus_view&amp;id=30">Mathe</a></h3>
          <div class="btn-group">
            <button type="button" class="btn btn-primary dropdown-toggle btn-xs" title="Müller, Anna (MUE)">MUE</button>
            <ul class="dropdown-menu">
              <li><a href="mailto:anna.mueller@example.invalid">E-Mail senden</a></li>
            </ul>
          </div>
          <span class="datum">12.11.2026</span>
          <span class="thema">Topic</span>
        </td>
      </tr>
    </tbody></table>
  </div>
  <div id="mappen">
    <div class="row">
      <div>
        <h2>Mathe</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Müller, Anna (MUE)">MUE</button>
          <ul class="dropdown-menu"><li><span>Müller, Anna</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=30">Open</a>
      </div>
      <div>
        <h2>Physik</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Müller, Peter (MUE)">MUE</button>
          <ul class="dropdown-menu"><li><span>Müller, Peter</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=31">Open</a>
      </div>
      <div>
        <h2>Chemie</h2>
        <div class="btn-group">
          <button type="button" class="btn btn-primary dropdown-toggle btn-md" title="Müller, Anna (MUA)">MUA</button>
          <ul class="dropdown-menu"><li><span>Müller, Anna</span></li></ul>
        </div>
        <a class="btn btn-primary" href="meinunterricht.php?a=sus_view&amp;id=32">Open</a>
      </div>
    </div>
  </div>
</div>
''';
      final lessons = LessonsStudentParser.parseOverviewDocument(
        parse(overviewHtml),
      );
      final byId = {for (final l in lessons) l.courseID: l};
      expect(byId['30']!.teachers.single.email, 'anna.mueller@example.invalid');
      expect(byId['31']!.teachers.single.email, isNull);
      expect(byId['32']!.teachers.single.email, isNull);
    },
  );
}

const courseName = 'Informatik 1 (fuzzTest-Gym)';
