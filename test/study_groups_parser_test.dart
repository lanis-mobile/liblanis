import 'package:html/parser.dart' show parse;
import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

void main() {
  group('StudyGroupsStudentParser.parseDocumentHtml', () {
    test(
      'parses observed live multi-teacher markup with stylesheet child and optional mailto',
      () {
        const html = '''
<html><body>
  <table id="LGs">
    <thead>
      <tr>
        <th>Halbjahr</th>
        <th>Kursname</th>
        <th>Lehrkraft</th>
      </tr>
    </thead>
    <tbody>
      <tr data-id="101">
        <td>2026/1</td>
        <td>Mathematik <small>(M-GK-1)</small></td>
        <td>
          <link rel="stylesheet" href="/css/teacher.css">
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">
              <i class="fa fa-user"></i> MUE <span class="caret"></span>
            </button>
            <ul class="dropdown-menu">
              <li><span><i class="fa fa-user fa-fw"></i> Müller, Anna</span></li>
              <li class="divider" role="separator"></li>
              <li><a href="nachrichten.php?new=1"><i class="fas fa-mail-bulk fa-fw"></i> Nachricht senden</a></li>
              <li><a href="mailto:anna.mueller@example.invalid?subject=Hi"><i class="fa fa-at fa-fw"></i> E-Mail senden</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">
              <i class="fa fa-user"></i> SCH <span class="caret"></span>
            </button>
            <ul class="dropdown-menu">
              <li><span><i class="fa fa-user fa-fw"></i> Schmidt, Max</span></li>
              <li class="divider" role="separator"></li>
              <li><a href="nachrichten.php?new=2"><i class="fas fa-mail-bulk fa-fw"></i> Nachricht senden</a></li>
            </ul>
          </div>
        </td>
      </tr>
      <tr data-id="102">
        <td>2026/1</td>
        <td>Deutsch <small>D-LK</small></td>
        <td>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">
              <i class="fa fa-user"></i> BEK <span class="caret"></span>
            </button>
            <ul class="dropdown-menu">
              <li><span><i class="fa fa-user fa-fw"></i> Becker</span></li>
            </ul>
          </div>
        </td>
      </tr>
      <tr data-id="103">
        <td>2026/1</td>
        <td>Kunst</td>
        <td></td>
      </tr>
    </tbody>
  </table>
</body></html>
''';

        final result = StudyGroupsStudentParser.parseDocumentHtml(parse(html));
        expect(result.exams, isEmpty);
        expect(result.groups, hasLength(3));

        final math = result.groups[0];
        expect(math.id, '101');
        expect(math.semester, '2026/1');
        expect(math.courseName, 'Mathematik');
        expect(math.courseSysId, 'M-GK-1');
        expect(math.teachers, hasLength(2));

        expect(math.teachers[0].krz, 'MUE');
        expect(math.teachers[0].lastName, 'Müller');
        expect(math.teachers[0].firstName, 'Anna');
        expect(math.teachers[0].email, 'anna.mueller@example.invalid');
        expect(math.teachers[0].conversationReceiverId, isNull);

        expect(math.teachers[1].krz, 'SCH');
        expect(math.teachers[1].lastName, 'Schmidt');
        expect(math.teachers[1].firstName, 'Max');
        expect(math.teachers[1].email, isNull);
        expect(math.teachers[1].conversationReceiverId, isNull);

        final german = result.groups[1];
        expect(german.courseName, 'Deutsch');
        expect(german.courseSysId, 'D-LK');
        expect(german.teachers.single.lastName, 'Becker');
        expect(german.teachers.single.firstName, '');

        final art = result.groups[2];
        expect(art.courseName, 'Kunst');
        expect(art.courseSysId, '');
        expect(art.teachers, isEmpty);
      },
    );

    test(
      'parses exam dates with or without weekday prefix and skips invalid exam rows without suppressing courses',
      () {
        const html = '''
<html><body>
  <table id="klausuren">
    <thead>
      <tr>
        <th>Datum</th>
        <th>Kurs</th>
        <th>Art</th>
        <th>Dauer</th>
        <th>Stunden</th>
      </tr>
    </thead>
    <tbody>
      <tr data-type="klausur" data-id="e1" data-lerngruppe="101">
        <td>Mo. 15.12.2030</td>
        <td>Mathematik <small>(M-GK-1)</small></td>
        <td>Klausur</td>
        <td>90 min</td>
        <td>1.-2.</td>
      </tr>
      <tr data-type="klausur" data-id="e2" data-lerngruppe="101">
        <td>01.12.2030</td>
        <td>Mathematik</td>
        <td>Test</td>
        <td>45 min</td>
        <td>3.</td>
      </tr>
      <tr data-type="klausur" data-id="e3" data-lerngruppe="101">
        <td>Di.03.12.2030</td>
        <td>Mathematik</td>
        <td>Test</td>
        <td>45 min</td>
        <td>4.</td>
      </tr>
      <tr data-type="klausur" data-id="e-rollover" data-lerngruppe="101">
        <td>31.02.2030</td>
        <td>Mathematik</td>
        <td>Invalid</td>
        <td>45 min</td>
        <td>5.</td>
      </tr>
      <tr data-type="klausur" data-id="e-missing-course">
        <td>04.12.2030</td>
        <td>Mathematik</td>
        <td>Invalid</td>
        <td>45 min</td>
        <td>6.</td>
      </tr>
    </tbody>
  </table>
  <table id="LGs">
    <thead>
      <tr>
        <th>Halbjahr</th>
        <th>Kursname</th>
        <th>Lehrkraft</th>
      </tr>
    </thead>
    <tbody>
      <tr data-id="101">
        <td>2026/1</td>
        <td>Mathematik <small>()</small></td>
        <td></td>
      </tr>
    </tbody>
  </table>
</body></html>
''';

        final result = StudyGroupsStudentParser.parseDocumentHtml(parse(html));
        expect(result.exams, hasLength(3));
        expect(result.exams.map((e) => e.id).toList(), ['e1', 'e2', 'e3']);
        expect(result.exams[0].date, DateTime(2030, 12, 15));
        expect(result.exams[1].date, DateTime(2030, 12, 1));
        expect(result.exams[2].date, DateTime(2030, 12, 3));

        // sortedExams returns a sorted copy without mutating exams in place.
        final sorted = result.sortedExams;
        expect(sorted.map((e) => e.id).toList(), ['e2', 'e3', 'e1']);
        expect(result.exams.map((e) => e.id).toList(), ['e1', 'e2', 'e3']);

        expect(result.groups, hasLength(1));
        expect(result.groups.single.courseSysId, '');
        expect(result.groups.single.exams, hasLength(3));
      },
    );

    test(
      'parses conversation receiver IDs from nachrichten.php links including trailing brace quirk',
      () {
        const html = '''
<html><body>
  <table id="LGs">
    <thead>
      <tr><th>Halbjahr</th><th>Kursname</th><th>Lehrkraft</th></tr>
    </thead>
    <tbody>
      <tr data-id="201">
        <td>2026/1</td>
        <td>Informatik</td>
        <td>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">CAP</button>
            <ul class="dropdown-menu">
              <li><span>Caputo, Alessio</span></li>
              <li class="divider"></li>
              <li><a href="nachrichten.php?to[]=bC0zMTY5ODM=}">Nachricht senden</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">RAS</button>
            <ul class="dropdown-menu">
              <li><span>Schirmer, Rajan</span></li>
              <li><a href="nachrichten.php?to[]=bC0yNjgxMzg=">Nachricht senden</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">DIR</button>
            <ul class="dropdown-menu">
              <li><span>Direct, Teacher</span></li>
              <li><a href="nachrichten.php?to[]=l-105044">Nachricht senden</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">BAD</button>
            <ul class="dropdown-menu">
              <li><span>Invalid, Link</span></li>
              <li><a href="nachrichten.php?to[]=!!!not-base64!!!">Nachricht senden</a></li>
            </ul>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
</body></html>
''';

        final result = StudyGroupsStudentParser.parseDocumentHtml(parse(html));
        final teachers = result.groups.single.teachers;
        expect(teachers, hasLength(4));
        expect(teachers[0].conversationReceiverId, 'l-316983');
        expect(teachers[1].conversationReceiverId, 'l-268138');
        expect(teachers[2].conversationReceiverId, 'l-105044');
        expect(teachers[3].conversationReceiverId, isNull);
      },
    );

    test('parses teacher emails robustly across mailto edge cases', () {
      const html = '''
<html><body>
  <table id="LGs">
    <thead>
      <tr><th>Halbjahr</th><th>Kursname</th><th>Lehrkraft</th></tr>
    </thead>
    <tbody>
      <tr data-id="202">
        <td>2026/1</td>
        <td>Mathe</td>
        <td>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">UPP</button>
            <ul class="dropdown-menu">
              <li><span>Upper, Case</span></li>
              <li><a href=" MAILTO:upper.case@example.invalid?subject=Hello ">E-Mail</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">ENC</button>
            <ul class="dropdown-menu">
              <li><span>Encoded, Mail</span></li>
              <li><a href="mailto:encoded%40example.invalid">E-Mail</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">EMP</button>
            <ul class="dropdown-menu">
              <li><span>Empty, Mail</span></li>
              <li><a href="mailto:?subject=Empty">E-Mail</a></li>
            </ul>
          </div>
          <div class="btn-group">
            <button class="btn btn-primary dropdown-toggle btn-sm">INV</button>
            <ul class="dropdown-menu">
              <li><span>Invalid, Mail</span></li>
              <li><a href="mailto:not-an-email">E-Mail</a></li>
            </ul>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
</body></html>
''';
      final result = StudyGroupsStudentParser.parseDocumentHtml(parse(html));
      final teachers = result.groups.single.teachers;
      expect(teachers, hasLength(4));
      expect(teachers[0].email, 'upper.case@example.invalid');
      expect(teachers[1].email, 'encoded@example.invalid');
      expect(teachers[2].email, isNull);
      expect(teachers[3].email, isNull);
    });
  });
}
