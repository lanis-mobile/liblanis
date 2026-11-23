import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:liblanis/liblanis.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

int subjectCount(TimeTable table) {
  return table.planForAll!.fold<int>(0, (n, day) => n + day.length);
}

List<TimetableSubject> allSubjects(TimeTable table) {
  return [for (final day in table.planForAll!) ...day];
}

/// Stable identity for comparing plans across display settings (ignores times).
String subjectKey(TimetableSubject s, int dayIndex) {
  return '$dayIndex|${s.name}|${s.raum}|${s.lehrer}|${s.duration}|${s.stunde}';
}

Set<String> subjectKeys(TimeTable table) {
  final keys = <String>{};
  for (var d = 0; d < table.planForAll!.length; d++) {
    for (final s in table.planForAll![d]) {
      keys.add(subjectKey(s, d));
    }
  }
  return keys;
}

int countStundeInAll(String html) {
  final document = parse(html);
  final all = document.querySelector('#all');
  if (all == null) return 0;
  return all.querySelectorAll('.stunde').length;
}

/// Name + room text from each `.stunde` under `#all` (DOM ground truth).
List<(String?, String)> domLessonSignals(String html) {
  final document = parse(html);
  final all = document.querySelector('#all');
  if (all == null) return const [];
  return [
    for (final row in all.querySelectorAll('.stunde'))
      (
        row.querySelector('b')?.text.trim(),
        row.nodes
            .map((node) => node.nodeType == 3 ? node.text!.trim() : '')
            .join(),
      ),
  ];
}

void main() {
  // CSV plan stems × admin display settings (deduped by content hash).
  final fixtureDir = Directory('test/fixtures/timetable');

  List<File> listHtmlFixtures() {
    return fixtureDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.html'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// First kept permutation whose filename starts with `[csvStem]__`.
  File fixtureForCsv(String csvStem, {int? vonbis}) {
    final matches = listHtmlFixtures().where((f) {
      final name = p.basename(f.path);
      if (!name.startsWith('${csvStem}__')) return false;
      if (vonbis != null && !name.contains('__vonbis-${vonbis}__')) {
        return false;
      }
      return true;
    }).toList();
    expect(
      matches,
      isNotEmpty,
      reason: 'no permutation fixture for csv stem "$csvStem" vonbis=$vonbis',
    );
    return matches.first;
  }

  TimeTable parseFile(File file) {
    return TimetableStudentParser.parseDocumentHtml(
      parse(file.readAsStringSync()),
    );
  }

  test('fixture directory exists with HTML samples', () {
    expect(fixtureDir.existsSync(), isTrue);
    expect(listHtmlFixtures().length, greaterThanOrEqualTo(20));
  });

  group('timetable parser fixtures', () {
    late final List<File> fixtures;

    setUpAll(() {
      fixtures = listHtmlFixtures();
    });

    test('every fixture parses without throwing', () {
      for (final file in fixtures) {
        final name = p.basename(file.path);
        expect(() => parseFile(file), returnsNormally, reason: name);
      }
    });

    test('every fixture matches DOM .stunde count, names, and rooms', () {
      for (final file in fixtures) {
        final name = p.basename(file.path);
        final html = file.readAsStringSync();
        final table = parseFile(file);
        final subjects = allSubjects(table);
        final dom = domLessonSignals(html);
        expect(subjects.length, dom.length, reason: '$name count');
        expect(subjects.length, countStundeInAll(html), reason: name);

        final parsedPairs = [
          for (final s in subjects) (s.name, s.raum ?? ''),
        ]..sort((a, b) => a.toString().compareTo(b.toString()));
        final domPairs = [
          for (final d in dom) d,
        ]..sort((a, b) => a.toString().compareTo(b.toString()));
        expect(parsedPairs, domPairs, reason: '$name name/raum');
      }
    });

    test('empty plan yields empty days/hours', () {
      final file = fixtureForCsv('01_empty');
      final table = parseFile(file);
      expect(subjectCount(table), 0);
      expect(table.hours, isEmpty);
      expect(table.planForAll, isNotNull);
    });

    test('single monday lesson has Bio in RM02 on day 0 with times', () {
      final file = fixtureForCsv('02_single_monday_lesson', vonbis: 0);
      final table = parseFile(file);
      expect(subjectCount(table), 1);
      expect(table.hours, isNotEmpty);
      expect(table.hours!.first.startTime.hour, 8);
      expect(table.hours!.first.endTime.hour, 9);

      expect(table.planForAll!.length, greaterThanOrEqualTo(1));
      final monday = table.planForAll![0];
      expect(monday, hasLength(1));
      final lesson = monday.single;
      expect(lesson.name, 'Bio');
      expect(lesson.raum, contains('RM02'));
      expect(lesson.startTime.hour, 8);
      expect(lesson.startTime.minute, 0);
      expect(lesson.endTime.hour, 9);
      expect(lesson.endTime.minute, 0);
      expect(lesson.duration, 1);
      // other weekdays empty
      for (var d = 1; d < table.planForAll!.length; d++) {
        expect(table.planForAll![d], isEmpty, reason: 'day $d');
      }
    });

    test('single monday with VonBis hidden still yields the lesson', () {
      final file = fixtureForCsv('02_single_monday_lesson', vonbis: 1);
      final table = parseFile(file);
      expect(subjectCount(table), 1);
      final lesson = table.planForAll![0].single;
      expect(lesson.name, 'Bio');
      expect(lesson.raum, contains('RM02'));
      // hours row list needs .VonBis — empty when hidden
      expect(table.hours, isEmpty);
    });

    test('vonbis-0/1 pairs with equal DOM keep lesson identities', () {
      // Pair files that differ only in vonbis; skip captures whose HTML diverged.
      final byName = {
        for (final f in fixtures) p.basename(f.path): f,
      };
      var paired = 0;
      for (final name in byName.keys) {
        if (!name.contains('__vonbis-0__')) continue;
        final counterpart = name.replaceFirst('__vonbis-0__', '__vonbis-1__');
        final other = byName[counterpart];
        if (other == null) continue;
        final htmlA = byName[name]!.readAsStringSync();
        final htmlB = other.readAsStringSync();
        if (countStundeInAll(htmlA) != countStundeInAll(htmlB)) continue;
        paired++;
        final a = parseFile(byName[name]!);
        final b = parseFile(other);
        expect(
          subjectKeys(a),
          subjectKeys(b),
          reason: '$name vs $counterpart',
        );
        // When the DOM actually has .VonBis, hours must parse; hidden → empty.
        final vonBisCount =
            parse(htmlA).querySelector('#all')?.querySelectorAll('.VonBis').length ??
            0;
        if (vonBisCount > 0) {
          expect(a.hours, isNotEmpty, reason: name);
          expect(b.hours, isEmpty, reason: counterpart);
        }
      }
      expect(paired, greaterThanOrEqualTo(10));
    });

    test('dense rowspan grid parses multiple subjects with names/rooms', () {
      final file = fixtureForCsv('11_dense_rowspan_grid', vonbis: 0);
      final table = parseFile(file);
      final subjects = allSubjects(table);
      expect(subjects.length, greaterThanOrEqualTo(10));
      expect(table.planForAll!.length, greaterThanOrEqualTo(5));
      expect(subjects.any((s) => s.name == 'Ch'), isTrue);
      expect(subjects.every((s) => (s.raum ?? '').contains('RM11')), isTrue);
      expect(subjects.any((s) => s.duration >= 2), isTrue);
      expect(
        subjects.every(
          (s) =>
              s.startTime.hour > 0 ||
              s.startTime.minute > 0 ||
              s.endTime.hour > 0,
        ),
        isTrue,
        reason: 'vonbis-0 lessons should carry real clock times',
      );
    });

    test('full grid parses without range errors and keeps lessons', () {
      final file = fixtureForCsv('24_full_grid_mon_fri', vonbis: 0);
      final html = file.readAsStringSync();
      final table = parseFile(file);
      final subjects = allSubjects(table);
      expect(subjects.length, countStundeInAll(html));
      expect(subjects.length, greaterThanOrEqualTo(40));
      expect(subjects.every((s) => (s.raum ?? '').contains('RM24')), isTrue);
      expect(table.hours!.length, greaterThanOrEqualTo(5));
    });

    test('missing #all tbody returns empty plan (LANIS-MOBILE-I)', () {
      const html = '''
        <html><body>
          <div id="own"><table><tbody></tbody></table></div>
        </body></html>
      ''';
      final table = TimetableStudentParser.parseDocumentHtml(parse(html));
      expect(table.planForAll, isEmpty);
      expect(table.hours, isEmpty);
    });

    test('collision-heavy plan does not overrun day columns', () {
      final file = fixtureForCsv('20_collision_heavy', vonbis: 0);
      final table = parseFile(file);
      expect(table.planForAll, isNotNull);
      expect(subjectCount(table), greaterThanOrEqualTo(10));
      for (final day in table.planForAll!) {
        expect(day, isA<List<TimetableSubject>>());
        for (final s in day) {
          expect(s.name, isNotNull);
          expect(s.raum, contains('RM20'));
        }
      }
    });
  });

  group('TimetableStudentParser.getTimetableDocument redirects', () {
    Future<TimetableStudentParser> createParser(
      _TimetableTestAdapter adapter,
    ) async {
      final db = LanisDatabase.open();
      final id = await db.addAccount(
        schoolId: 5182,
        schoolName: 'Test School',
        username: 'student',
        password: 'pw',
        accountType: AccountType.student,
      );
      final account = (await db.getAccount(id))!;
      const config = LanisConfig();
      final checker = _TimetableTestChecker(adapter);
      final session = _TimetableTestSession(
        account: account,
        config: config,
        connectionChecker: checker,
        adapter: adapter,
      );
      final ctx = AppletContext(
        account: account,
        session: session,
        database: db,
        accountSettings: TypedSettings.account(db, id),
      );
      final parser = TimetableStudentParser(ctx, isConnected: () async => true);
      addTearDown(() async {
        parser.dispose();
        await session.dispose();
        checker.dispose();
        db.dispose();
      });
      return parser;
    }

    test('resolves leading-slash and relative redirects cleanly', () async {
      for (final location in [
        '/stundenplan.php?a=klasse&p=1',
        'stundenplan.php?a=klasse&p=1',
      ]) {
        final adapter = _TimetableTestAdapter((options) async {
          if (options.uri.queryParameters.isEmpty) {
            return ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': [location],
              },
            );
          }
          return ResponseBody.fromString(
            '<html><body><div id="all"><table><tbody></tbody></table></div></body></html>',
            200,
          );
        });
        final parser = await createParser(adapter);

        final doc = await parser.getTimetableDocument();
        expect(doc, isNotNull);
        expect(doc!.getElementById('all'), isNotNull);
        expect(adapter.requests, hasLength(2));
        expect(
          adapter.requests.last.uri.toString(),
          'https://start.schulportal.hessen.de/stundenplan.php?a=klasse&p=1',
          reason: 'Redirect "$location" should resolve without double slashes',
        );
      }
    });

    test('rejects untrusted external or non-HTTPS redirects', () async {
      for (final badLocation in [
        'https://evil.example/stundenplan.php',
        'http://start.schulportal.hessen.de/stundenplan.php',
      ]) {
        final adapter = _TimetableTestAdapter((options) async {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [badLocation],
            },
          );
        });
        final parser = await createParser(adapter);

        await expectLater(
          () => parser.getTimetableDocument(),
          throwsA(isA<ConfigurationException>()),
          reason: 'Expected ConfigurationException for "$badLocation"',
        );
        expect(adapter.requests, hasLength(1));
      }
    });
  });

  group('TimeTableData', () {
    TimetableSubject makeSubject(String id, {String? badge}) => TimetableSubject(
      id: id,
      name: id,
      raum: 'R-$id',
      lehrer: 'L',
      badge: badge,
      duration: 1,
      startTime: const SphTimeOfDay(hour: 8, minute: 0),
      endTime: const SphTimeOfDay(hour: 8, minute: 45),
      stunde: 1,
    );

    final hour = TimeTableRow(
      TimeTableRowType.lesson,
      const SphTimeOfDay(hour: 8, minute: 0),
      const SphTimeOfDay(hour: 8, minute: 45),
      '1',
      1,
    );

    test('keeps empty Wednesday in a 5-day plan', () {
      final plan = [
        [makeSubject('mo')],
        [makeSubject('di')],
        <TimetableSubject>[],
        [makeSubject('do')],
        [makeSubject('fr')],
      ];
      final data = TimeTableData(
        plan,
        TimeTable(hours: [hour], planForAll: plan),
        const {},
        null,
      );

      expect(data.timetableDays, hasLength(5));
      expect(data.timetableDays[2], isEmpty);
      expect(data.weekdayIndices, [0, 1, 2, 3, 4]);
    });

    test('drops empty Saturday and Sunday in a 7-day plan', () {
      final plan = [
        [makeSubject('mo')],
        [makeSubject('di')],
        [makeSubject('mi')],
        [makeSubject('do')],
        [makeSubject('fr')],
        <TimetableSubject>[],
        <TimetableSubject>[],
      ];
      final data = TimeTableData(
        plan,
        TimeTable(hours: [hour], planForAll: plan),
        const {},
        null,
      );

      expect(data.timetableDays, hasLength(5));
      expect(data.weekdayIndices, [0, 1, 2, 3, 4]);
    });

    test('drops empty Saturday while keeping non-empty Sunday with index 6', () {
      final plan = [
        [makeSubject('mo')],
        [makeSubject('di')],
        [makeSubject('mi')],
        [makeSubject('do')],
        [makeSubject('fr')],
        <TimetableSubject>[],
        [makeSubject('so')],
      ];
      final data = TimeTableData(
        plan,
        TimeTable(hours: [hour], planForAll: plan),
        const {},
        null,
      );

      expect(data.timetableDays, hasLength(6));
      expect(data.weekdayIndices, [0, 1, 2, 3, 4, 6]);
    });

    test('returns empty days and indices when filtering hides all lessons', () {
      final plan = [
        [makeSubject('mo', badge: 'A')],
        <TimetableSubject>[],
        [makeSubject('mi', badge: 'A')],
      ];
      final timetable = TimeTable(hours: [hour], planForAll: plan);

      final unmatchedBadge = TimeTableData(plan, timetable, const {}, 'B');
      expect(unmatchedBadge.timetableDays, isEmpty);
      expect(unmatchedBadge.weekdayIndices, isEmpty);

      final allHidden = TimeTableData(
        plan,
        timetable,
        const {
          'hidden-lessons': ['mo', 'mi'],
        },
        null,
      );
      expect(allHidden.timetableDays, isEmpty);
      expect(allHidden.weekdayIndices, isEmpty);
    });
  });
}

class _TimetableTestAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _TimetableTestAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _TimetableTestChecker extends ConnectionChecker {
  _TimetableTestChecker(_TimetableTestAdapter adapter)
    : super(httpAdapter: adapter);

  @override
  Future<bool> testConnection() async => true;
}

class _TimetableTestSession extends LanisSession {
  _TimetableTestSession({
    required super.account,
    required super.config,
    required super.connectionChecker,
    required _TimetableTestAdapter adapter,
  }) {
    dio.httpClientAdapter = adapter;
    dio.options.followRedirects = false;
    dio.options.validateStatus = (status) => status == 200 || status == 302;
  }

  @override
  Future<void> authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    throw StateError('Unit tests must not authenticate');
  }
}
