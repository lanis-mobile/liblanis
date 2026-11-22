import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import '../../models/study_groups.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';

class StudyGroupsStudentParser extends AppletParser<StudentStudyGroups> {
  static final RegExp _examDatePattern = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})');

  StudyGroupsStudentParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.studyGroups,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  Future<StudentStudyGroups> getHome() async {
    final Response response = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/lerngruppen.php',
    );
    return parseDocumentHtml(parse(response.data));
  }

  static DateTime? _parseExamDate(String? raw) {
    if (raw == null) return null;
    final match = _examDatePattern.firstMatch(raw);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String? _parseTeacherEmail(Element teacherGroup) {
    final href = teacherGroup
        .querySelector('ul.dropdown-menu a[href^="mailto:"]')
        ?.attributes['href']
        ?.trim();
    if (href == null || href.length <= 'mailto:'.length) return null;
    var address = href.substring('mailto:'.length);
    final queryStart = address.indexOf('?');
    if (queryStart != -1) {
      address = address.substring(0, queryStart);
    }
    address = address.trim();
    return address.isEmpty ? null : address;
  }

  static String _stripOuterParens(String value) {
    if (value.length >= 2 && value.startsWith('(') && value.endsWith(')')) {
      return value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  static StudentStudyGroups parseDocumentHtml(Document document) {
    final Element? courses = document.getElementById('LGs');
    final Element? exams = document.getElementById('klausuren');

    final List<StudentStudyGroupExam> studyGroupExams = [];
    if (exams != null) {
      final List<String> examTableHead = [
        for (final element in exams.querySelectorAll('thead tr th'))
          element.text.trim(),
      ];

      for (final Element examTableRow in exams
          .querySelectorAll('tbody tr')
          .where((row) => row.attributes['data-type'] == 'klausur')) {
        final String? courseId = examTableRow.attributes['data-lerngruppe'];
        final String? id = examTableRow.attributes['data-id'];
        if (courseId == null ||
            courseId.isEmpty ||
            id == null ||
            id.isEmpty) {
          continue;
        }

        Element? elementInRow(String key) {
          final int index = examTableHead.indexOf(key);
          if (index == -1) return null;
          if (index >= examTableRow.children.length) return null;
          return examTableRow.children[index];
        }

        final date = _parseExamDate(elementInRow('Datum')?.text);
        if (date == null) continue;

        final courseCell = elementInRow('Kurs');
        courseCell?.querySelector('small')?.remove();
        studyGroupExams.add(
          StudentStudyGroupExam(
            id: id,
            courseId: courseId,
            courseName: courseCell?.text.trim() ?? 'Unbekannt',
            date: date,
            type: elementInRow('Art')?.text.trim() ?? 'Unbekannt',
            durationLabel: elementInRow('Dauer')?.text.trim(),
            hoursOfDay: elementInRow('Stunden')?.text.trim(),
          ),
        );
      }
    }

    final List<StudentStudyGroup> studyGroups = [];
    if (courses != null) {
      final List<String> courseTableHead = [
        for (final element in courses.querySelectorAll('thead tr th'))
          element.text.trim(),
      ];

      for (final Element courseTableRow in courses.querySelectorAll(
        'tbody tr',
      )) {
        final String? id = courseTableRow.attributes['data-id'];
        if (id == null) continue;

        Element? elementInRow(String key) {
          final int index = courseTableHead.indexOf(key);
          if (index == -1) return null;
          if (index >= courseTableRow.children.length) return null;
          return courseTableRow.children[index];
        }

        final List<StudentStudyGroupTeacher> teachers = [];
        final teacherElement = elementInRow('Lehrkraft');
        if (teacherElement != null) {
          for (final Element teacherGroup in teacherElement.querySelectorAll(
            '.btn-group',
          )) {
            final teacherName =
                teacherGroup
                    .querySelector('ul.dropdown-menu > li > span')
                    ?.text
                    .trim() ??
                '';
            final commaIndex = teacherName.indexOf(',');
            final String lastName;
            final String firstName;
            if (commaIndex != -1) {
              lastName = teacherName.substring(0, commaIndex).trim();
              firstName = teacherName.substring(commaIndex + 1).trim();
            } else {
              lastName = teacherName;
              firstName = '';
            }
            teachers.add(
              StudentStudyGroupTeacher(
                firstName: firstName,
                lastName: lastName,
                krz:
                    teacherGroup
                        .querySelector('button.btn.btn-primary.dropdown-toggle')
                        ?.text
                        .trim() ??
                    '',
                email: _parseTeacherEmail(teacherGroup),
              ),
            );
          }
        }

        final courseNameCell = elementInRow('Kursname');
        final smallElement = courseNameCell?.querySelector('small');
        final String sysId = _stripOuterParens(smallElement?.text.trim() ?? '');
        smallElement?.remove();

        studyGroups.add(
          StudentStudyGroup(
            id: id,
            semester: elementInRow('Halbjahr')?.text.trim() ?? 'Fehler',
            courseName: courseNameCell?.text.trim() ?? 'Fehler',
            courseSysId: sysId,
            teachers: teachers,
            exams: studyGroupExams
                .where((exam) => exam.courseId == id)
                .toList(),
          ),
        );
      }
    }

    return StudentStudyGroups(groups: studyGroups, exams: studyGroupExams);
  }
}
