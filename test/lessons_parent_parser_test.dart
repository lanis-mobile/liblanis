import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:liblanis/easy_client.dart';
import 'package:test/test.dart';

const fixtures = 'test/fixtures/lessons/parents';
Document overview(String name) =>
    parse(File('$fixtures/${name}_overview.html').readAsStringSync());

List<Lesson> allCourses(Document doc) =>
    LessonsParentParser.parseOverviewDocument(
      doc,
    ).lessonsByPupil.values.expand((courses) => courses).toList();
Lessons coursesFor(ParentLessonsOverview overview, String id) => overview
    .lessonsByPupil
    .entries
    .singleWhere((entry) => entry.key.id == id)
    .value;

const parentDetail = '''<div id="content">
<h1 data-book="1001">Test course</h1>
<div class="btn-group"><button class="btn btn-primary dropdown-toggle btn-md">T1</button>
<ul><li><span>Fixture teacher</span></li></ul></div>
<a href="meinunterricht.php?a=sus_view&amp;id=1001&amp;p=102&amp;halb=1">Other pupil</a>
<a href="meinunterricht.php?a=sus_view&amp;id=1001&amp;p=101&amp;halb=1">First semester</a>
<div id="history"><table><tbody>
<tr data-entry="201"><td>12.11.2026<br><small>1. Stunde</small></td>
<td><b>Test topic</b></td><td>anwesend</td></tr>
</tbody></table></div></div>''';

class _Session implements LanisSession {
  @override
  final Dio dio;
  @override
  int get authGeneration => 0;
  _Session(_Adapter adapter) : dio = Dio()..httpClientAdapter = adapter;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements TypedSettings {
  @override
  Map<String, dynamic>? getJsonMap(String key) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Context implements AppletContext {
  @override
  final LanisSession session;
  @override
  final TypedSettings accountSettings = _Settings();
  @override
  final ClearTextAccount account;
  _Context(_Adapter adapter, {AccountType type = AccountType.parent})
    : session = _Session(adapter),
      account = ClearTextAccount(
        localId: 1,
        schoolID: 1,
        username: 'test',
        password: 'test',
        schoolName: 'Test school',
        accountType: type,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  final String? overviewHtml;
  final String detailHtml;
  _Adapter({this.overviewHtml, this.detailHtml = parentDetail});
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    if (options.method != 'GET' || options.uri.path != '/meinunterricht.php') {
      throw StateError('Unexpected request');
    }
    return ResponseBody.fromString(
      options.uri.queryParameters['a'] == 'sus_view'
          ? detailHtml
          : overviewHtml ??
                File('$fixtures/two_pupils_overview.html').readAsStringSync(),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('one-child live layout exposes identity, current and older courses', () {
    final doc = overview('one_pupil');
    final pupils = LessonsParentParser.parseOverviewDocument(
      doc,
    ).lessonsByPupil.keys;
    expect(pupils, hasLength(1));
    expect(pupils.single.id, '101');
    expect(pupils.single.name, 'Test pupil 101');
    final courses = allCourses(doc);
    expect(courses, hasLength(3));
    expect(courses.map((c) => c.pupilId), everyElement('101'));
    expect(courses.where((c) => c.isOlder), hasLength(1));
    for (final c in courses) {
      expect(c.courseID, c.courseURL.queryParameters['id']);
      expect(c.courseID, isNot(contains('&')));
      expect(c.courseURL.queryParameters['p'], c.pupilId);
    }
    expect(courses.last.courseURL.queryParameters['halb'], '1');
  });

  test('two-child live layout keeps shared course IDs separate', () {
    final doc = overview('two_pupils');
    final pupils = LessonsParentParser.parseOverviewDocument(
      doc,
    ).lessonsByPupil.keys;
    expect(pupils.map((p) => p.id), unorderedEquals(['101', '102']));
    final courses = allCourses(doc);
    expect(courses, hasLength(6));
    for (final id in ['101', '102']) {
      final selected = coursesFor(
        LessonsParentParser.parseOverviewDocument(doc),
        id,
      );
      expect(selected, hasLength(3));
      expect(selected.map((c) => c.pupilId), everyElement(id));
      expect(
        selected.map((c) => c.courseURL.queryParameters['p']),
        everyElement(id),
      );
    }
    expect(
      courses.where((c) => c.pupilId == '101').map((c) => c.courseID),
      courses.where((c) => c.pupilId == '102').map((c) => c.courseID),
    );
  });

  test('attendance and current entries never cross pupil sections', () {
    final doc = overview('two_pupils');
    for (final (index, box) in doc.querySelectorAll('.pupilbox').indexed) {
      final pupilId = box
          .querySelector('h2[data-pupil]')!
          .attributes['data-pupil']!;
      box.querySelector('[id^="aktuell"]')!.innerHtml =
          '<table><tbody><tr class="printable" data-entry="${700 + index}"><td>'
          '<h3><a href="meinunterricht.php?a=sus_view&amp;id=1001&amp;p=$pupilId">Course</a></h3>'
          '<span class="datum">12.11.2026</span><span class="thema">Topic</span>'
          '</td></tr></tbody></table>';
      box.querySelector('[id^="anwesend"]')!.innerHtml =
          '<table><thead><tr><th>Kurs</th><th>anwesend</th></tr></thead><tbody>'
          '<tr><td><a href="meinunterricht.php?a=sus_view&amp;id=1001&amp;p=$pupilId">Course</a></td>'
          '<td>${11 + index}</td></tr></tbody></table>';
    }
    final courses = allCourses(doc);
    for (var i = 0; i < 2; i++) {
      final course = courses.firstWhere(
        (c) =>
            c.pupilId ==
                doc
                    .querySelectorAll('h2[data-pupil]')[i]
                    .attributes['data-pupil'] &&
            c.courseID == '1001' &&
            !c.isOlder,
      );
      expect(course.currentEntry!.entryID, '${700 + i}');
      expect(course.attendances!['anwesend'], '${11 + i}');
    }
  });

  test('parent open and done labels work without student checkboxes', () {
    final doc = overview('two_pupils');
    expect(doc.querySelectorAll('.undone'), isEmpty);
    final homework = allCourses(doc)
        .where((c) => !c.isOlder)
        .map((c) => c.currentEntry?.homework)
        .whereType<Homework>()
        .toList();
    expect(homework.map((h) => h.homeWorkDone), containsAll([false, true]));
    expect(homework.map((h) => h.description), everyElement(isNotEmpty));
  });

  test('parent open text is recognized if the warning style changes', () {
    final doc = overview('two_pupils');
    final label = doc.querySelector('.homework .done.label-warning')!;
    label.classes.remove('label-warning');
    label.text = ' offen ';
    final courses = allCourses(doc);
    expect(
      courses.any((c) => c.currentEntry?.homework?.homeWorkDone == false),
      isTrue,
    );
  });

  test('a child with no courses remains discoverable', () {
    final doc = overview('two_pupils');
    final box = doc.querySelectorAll('.pupilbox').last;
    box.querySelector('[id^="mappen"]')!.innerHtml = '<div class="row"></div>';
    box.querySelector('[id^="aktuell"]')!.innerHtml = '';
    expect(
      LessonsParentParser.parseOverviewDocument(doc).lessonsByPupil.keys,
      hasLength(2),
    );
    expect(
      coursesFor(
        LessonsParentParser.parseOverviewDocument(doc),
        box.querySelector('h2[data-pupil]')!.attributes['data-pupil']!,
      ),
      isEmpty,
    );
    expect(allCourses(doc), hasLength(3));
  });

  test('missing or duplicate pupil identities fail with typed errors', () {
    final missing = overview('one_pupil');
    missing.querySelector('h2[data-pupil]')!.attributes.remove('data-pupil');
    final duplicate = overview('two_pupils');
    duplicate.querySelectorAll('h2[data-pupil]').last.attributes['data-pupil'] =
        duplicate.querySelector('h2[data-pupil]')!.attributes['data-pupil']!;
    for (final doc in [parse('<form>Login</form>'), missing, duplicate]) {
      expect(
        () =>
            LessonsParentParser.parseOverviewDocument(doc).lessonsByPupil.keys,
        throwsA(isA<LanisException>()),
      );
    }
  });

  test('missing attendance section is optional for a parent course', () {
    final doc = overview('one_pupil');
    doc.querySelector('[id^="anwesend"]')!.remove();
    expect(allCourses(doc).map((c) => c.attendances), everyElement(isNull));
  });

  test(
    'parent detail homework without student controls reaches its own field',
    () {
      final doc = parse(
        parentDetail.replaceFirst(
          '<td><b>Test topic</b></td>',
          '<td><b>Test topic</b><br>'
              '<span class="markup"><i class="far fa-comment-alt"></i>Lesson description</span>'
              '<br><br><i class="fas fa-home"></i><br>'
              '<span class="markup">Read chapter 3</span></td>',
        ),
      );
      final detail = LessonsStudentParser.parseDetailedDocument(
        doc,
        courseID: '1001',
        pupilId: '101',
      );
      final entry = detail.history.single;
      expect(entry.description, 'Lesson description');
      expect(entry.homework?.description, 'Read chapter 3');
      expect(entry.homework?.homeWorkDone, isFalse);
    },
  );

  for (final done in [false, true]) {
    test('detail homework completion requires a visible done marker ($done)', () {
      final doc = parse(
        parentDetail.replaceFirst(
          '<td><b>Test topic</b></td>',
          '<td><b>Test topic</b><br><i class="fas fa-home"></i>'
              '<span class="homework"><span class="done${done ? '' : ' hidden'}">Done</span></span>'
              '<br><span class="markup">Homework with controls</span></td>',
        ),
      );
      final entry = LessonsStudentParser.parseDetailedDocument(
        doc,
        courseID: '1001',
        pupilId: '101',
      ).history.single;
      expect(entry.homework?.description, 'Homework with controls');
      expect(entry.homework?.homeWorkDone, done);
    });
  }

  for (final done in [false, true]) {
    test('parent detail ignores the overview completion status: $done', () async {
      final document = overview('two_pupils');
      final label = document.querySelector(
        '#aktuell101 tr[data-entry="201"] .homework .done',
      )!;
      label.classes.remove('label-warning');
      label.classes.add(done ? 'label-success' : 'label-warning');
      label.text = done ? 'erledigt' : 'offen';
      final html = parentDetail.replaceFirst(
        '<td><b>Test topic</b></td>',
        '<td><b>Test topic</b><br><i class="fas fa-home"></i><br><span class="markup">Homework</span></td>',
      );
      final adapter = _Adapter(
        overviewHtml: document.outerHtml,
        detailHtml: html,
      );
      final parser = LessonsParentParser(
        _Context(adapter),
        isConnected: () async => true,
      );
      addTearDown(parser.dispose);
      await parser.getHome();
      final detail = await parser.getDetailedCourseView(
        'meinunterricht.php?a=sus_view&id=1001&p=101',
      );
      expect(detail.history.single.homework!.homeWorkDone, isFalse);
      expect(adapter.requests, hasLength(2));
    });
  }

  test(
    'one overview request returns all children and courses before a detail request',
    () async {
      final adapter = _Adapter();
      final parser = LessonsParentParser(
        _Context(adapter),
        isConnected: () async => true,
      );
      addTearDown(parser.dispose);
      final overview = await parser.getHome();
      expect(overview, isA<ParentLessonsOverview>());
      expect(overview.lessonsByPupil, hasLength(2));
      expect(
        overview.lessonsByPupil.keys.map((p) => p.name),
        unorderedEquals(['Test pupil 101', 'Test pupil 102']),
      );
      expect(overview.lessonsByPupil.values.map((courses) => courses.length), [
        3,
        3,
      ]);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.queryParameters.containsKey('a'), isFalse);
      final courses = coursesFor(overview, '101');
      final course = courses.first;
      final detail = await parser.getDetailedCourseView(
        course.courseURL.toString(),
        force: true,
      );
      expect(adapter.requests, hasLength(2));
      final request = adapter.requests.last;
      expect(request.uri.queryParameters['id'], course.courseID);
      expect(request.uri.queryParameters['p'], '101');
      expect(request.uri.queryParameters, contains('cacheBreaker'));
      expect(detail.courseID, course.courseID);
      expect(detail.pupilId, '101');
      expect(detail.teachers.single.teacher, 'Fixture teacher');
      expect(detail.history, hasLength(1));
      expect(detail.history.single.homework, isNull);
      expect(detail.semester1URL!.queryParameters['p'], '101');
      expect(detail.semester1URL!.queryParameters['halb'], '1');
    },
  );

  test(
    'parent getHome preserves its grouped result in the fetch stream',
    () async {
      final adapter = _Adapter();
      final parser = LessonsParentParser(
        _Context(adapter),
        isConnected: () async => true,
      );
      addTearDown(parser.dispose);
      await parser.fetchData(forceRefresh: true);
      expect(parser.latestResponse!.status, FetcherStatus.done);
      final result = parser.latestResponse!.content!;
      expect(result, isA<ParentLessonsOverview>());
      expect(result.lessonsByPupil, hasLength(2));
      expect(
        result.lessonsByPupil.values.expand((courses) => courses),
        hasLength(6),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test(
    'detail URL without a pupil is rejected before making a request',
    () async {
      final adapter = _Adapter();
      final parser = LessonsParentParser(
        _Context(adapter),
        isConnected: () async => true,
      );
      addTearDown(parser.dispose);
      for (final url in [
        'meinunterricht.php?a=sus_view&id=1001',
        'meinunterricht.php?a=sus_view&id=1001&p=',
      ]) {
        await expectLater(
          parser.getDetailedCourseView(url),
          throwsA(isA<ConfigurationException>()),
        );
      }
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'imperative registry chooses a distinct parser for each account type',
    () {
      for (final type in AccountType.values) {
        final parsers = EasyParsers(
          ctx: _Context(_Adapter(), type: type),
          isConnected: () async => true,
        );
        addTearDown(parsers.disposeAll);
        final lessons = parsers.forApplet('meinunterricht.php');
        switch (type) {
          case AccountType.parent:
            expect(lessons, same(parsers.lessonsParent));
          case AccountType.student:
            expect(lessons, same(parsers.lessonsStudent));
          case AccountType.teacher:
            expect(lessons, same(parsers.lessonsTeacher));
        }
      }
    },
  );
}
