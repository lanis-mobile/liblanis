import 'package:html/dom.dart';

import '../../exceptions.dart';
import '../../models/file_info.dart';
import '../../models/lessons.dart';
import '../teacher_message_link.dart';

/// Shared HTML parsing for student and per-pupil parent overview sections.
Lessons parseLessonsOverview(
  Element scope, {
  required String foldersId,
  required String attendanceId,
  String? pupilId,
}) {
  var lessons = <Lesson>[];

  var kursmappenDOM = scope.querySelector('[id="$foldersId"]');
  if (kursmappenDOM == null) {
    throw UnknownException('Missing course folders (#$foldersId)');
  }
  final row = kursmappenDOM.getElementsByClassName('row');
  var mappen = row.isEmpty ? null : row[0].children;
  if (mappen != null) {
    for (var mappe in mappen) {
      String url = mappe
          .querySelector("a.btn.btn-primary")!
          .attributes["href"]!;
      lessons.add(
        Lesson(
          name: mappe.getElementsByTagName("h2")[0].text.trim(),
          teachers: mappe
              .querySelectorAll("div.btn-group>button")
              .map<LessonTeacher>(
                (e) => LessonTeacher(
                  teacher: e.attributes["title"]?.split(" (")[0].trim(),
                  teacherKuerzel: e.text.trim(),
                  email: parseTeacherEmail(e.parent),
                  conversationReceiverId: parseTeacherConversationReceiverId(
                    e.parent,
                  ),
                ),
              )
              .toList(),
          courseURL: Uri.parse(url),
          courseID: requiredLessonCourseId(url),
          pupilId: pupilId,
        ),
      );
    }
  }

  // Older folders use table rows instead of course cards. Keep their
  // semester URL intact, including when the same course also has a card.
  for (final tableRow in kursmappenDOM.querySelectorAll(
    'table tbody tr[data-book]',
  )) {
    final link = tableRow.querySelector('td a[href*="a=sus_view"]');
    if (link == null) continue;
    final url = link.attributes['href']!;
    lessons.add(
      Lesson(
        courseID: requiredLessonCourseId(url),
        pupilId: pupilId,
        name: link.text.trim(),
        courseURL: Uri.parse(url),
        isOlder: true,
        teachers: tableRow
            .querySelectorAll('td .label[title]')
            .map(
              (label) => LessonTeacher(
                teacher: label.attributes['title']?.split(' (').first.trim(),
                teacherKuerzel: label.text.trim(),
              ),
            )
            .toList(),
      ),
    );
  }

  //Aktuelle Einträge
  final discoveredTeachers = <LessonTeacher>[];
  var schoolClasses = scope.querySelectorAll("tr.printable");
  for (var schoolClass in schoolClasses) {
    final rowCourseURL = schoolClass
        .querySelector("td>h3>a")
        ?.attributes["href"];
    final rowTeachers = schoolClass
        .querySelectorAll("div.btn-group:not(.files)>button")
        .map<LessonTeacher>(
          (e) => LessonTeacher(
            teacher: e.attributes["title"]?.split(" (")[0].trim(),
            teacherKuerzel: e.text.trim(),
            email: parseTeacherEmail(e.parent),
            conversationReceiverId: parseTeacherConversationReceiverId(
              e.parent,
            ),
          ),
        )
        .where((t) => t.conversationReceiverId != null || t.email != null)
        .toList();
    discoveredTeachers.addAll(rowTeachers);

    if (rowCourseURL != null && rowTeachers.isNotEmpty) {
      for (var lesson in lessons) {
        if (lesson.courseURL.toString() == rowCourseURL) {
          _applyTeacherContactInfo(lesson.teachers, rowTeachers);
        }
      }
    }

    if (schoolClass.querySelector(".datum") != null) {
      String? topicTitle = schoolClass.querySelector(".thema")?.text.trim();
      String? topicDateString = schoolClass
          .querySelector(".datum")
          ?.text
          .trim();
      DateTime? topicDate = DateTime.parse(
        topicDateString!.split(".").reversed.join("-"),
      );
      String? courseURL = rowCourseURL;
      int fileCount = schoolClass.getElementsByClassName('file').length;

      Homework? homework;
      if (schoolClass.querySelector('.homework') != null) {
        homework = Homework(
          description:
              schoolClass.querySelector('.realHomework')?.text.trim() ?? '',
          homeWorkDone:
              schoolClass.querySelector('.undone') == null &&
              schoolClass.querySelector('.homework .done.label-warning') ==
                  null &&
              schoolClass
                      .querySelector('.homework .done')
                      ?.text
                      .trim()
                      .toLowerCase() !=
                  'offen',
        );
      }
      String entryID = schoolClass.attributes["data-entry"]!;

      // find lesson by courseURL and add currentEntry
      for (var lesson in lessons) {
        if (lesson.courseURL.toString() == courseURL) {
          lesson.currentEntry = CurrentEntry(
            entryID: entryID,
            topicTitle: topicTitle,
            topicDate: topicDate,
            homework: homework,
            uploads: const [],
            files: List.generate(fileCount, (_) => FileInfo()),
          );
          break;
        }
      }
    }
  }

  propagateLessonTeacherContactInfo(
    lessons,
    additionalSources: discoveredTeachers,
  );

  //Anwesenheiten
  var anwesendDOM = scope.querySelector('[id="$attendanceId"]');
  var thead = anwesendDOM?.querySelector("thead>tr");
  var tbody = anwesendDOM?.querySelectorAll("tbody>tr");

  List<String> keys = [];
  thead?.children.forEach((element) => keys.add(element.text.trim()));

  tbody?.forEach((row) {
    var textElements = [];
    for (var i = 0; i < row.children.length; i++) {
      var col = row.children[i];
      col.querySelector("div.hidden.hidden_encoded")?.innerHtml = "";

      textElements.add(col.text.trim());
    }

    Map<String, String> attendances = {};

    for (int i = 0; i < keys.length; i++) {
      var key = keys[i].toLowerCase();
      var value = i < textElements.length ? textElements[i] : '';
      if (['kurs', 'lehrkraft'].contains(key)) continue;

      if (value == "") {
        value = "0";
      }

      attendances[key] = value;
    }
    final courseURL = row.querySelector('a[href]')?.attributes['href'];
    if (courseURL == null) return;
    final courseId = Uri.parse(courseURL).queryParameters['id'];

    // find lesson by courseURL and add attendances
    for (var lesson in lessons) {
      if (courseId == lesson.courseID) {
        lesson.attendances = attendances;
        break;
      }
    }
  });

  //sort lessons by date
  lessons.sort((a, b) {
    if (a.isOlder != b.isOlder) return a.isOlder ? 1 : -1;
    if (a.isOlder) return 0;
    if (a.currentEntry?.topicDate == null) {
      return b.currentEntry?.topicDate == null ? 0 : 1;
    }
    if (b.currentEntry?.topicDate == null) return -1;
    return b.currentEntry!.topicDate!.compareTo(a.currentEntry!.topicDate!);
  });

  return lessons;
}

String requiredLessonCourseId(String url) {
  final id = Uri.parse(url).queryParameters['id'];
  if (id == null || id.isEmpty) {
    throw UnknownException('Missing course ID in lesson URL');
  }
  return id;
}

String _normalizeTeacherKey(String? value) =>
    (value ?? '').trim().toLowerCase();

void _applyTeacherContactField(
  Iterable<LessonTeacher> targets,
  Iterable<LessonTeacher> sources, {
  required String? Function(LessonTeacher) getValue,
  required void Function(LessonTeacher, String) setValue,
}) {
  final knownSources = [
    for (final source in sources)
      if (getValue(source) case final value? when value.isNotEmpty)
        (
          krz: _normalizeTeacherKey(source.teacherKuerzel),
          name: _normalizeTeacherKey(source.teacher),
          value: value,
        ),
  ];
  if (knownSources.isEmpty) return;

  for (final target in targets) {
    final existing = getValue(target);
    if (existing != null && existing.isNotEmpty) continue;
    final krz = _normalizeTeacherKey(target.teacherKuerzel);
    final name = _normalizeTeacherKey(target.teacher);
    if (krz.isEmpty && name.isEmpty) continue;

    final exactPairValues = <String>{};
    final compatibleValues = <String>{};

    for (final source in knownSources) {
      final krzMatches = krz.isNotEmpty && source.krz == krz;
      final nameMatches = name.isNotEmpty && source.name == name;
      if (!krzMatches && !nameMatches) continue;

      final krzConflicts =
          krz.isNotEmpty && source.krz.isNotEmpty && source.krz != krz;
      final nameConflicts =
          name.isNotEmpty && source.name.isNotEmpty && source.name != name;
      if (krzConflicts || nameConflicts) continue;

      if (krzMatches && nameMatches) {
        exactPairValues.add(source.value);
      }
      compatibleValues.add(source.value);
    }

    if (exactPairValues.length == 1) {
      setValue(target, exactPairValues.single);
    } else if (exactPairValues.isEmpty && compatibleValues.length == 1) {
      setValue(target, compatibleValues.single);
    }
  }
}

void _applyTeacherContactInfo(
  Iterable<LessonTeacher> targets,
  Iterable<LessonTeacher> sources,
) {
  _applyTeacherContactField(
    targets,
    sources,
    getValue: (teacher) => teacher.conversationReceiverId,
    setValue: (teacher, value) => teacher.conversationReceiverId = value,
  );
  _applyTeacherContactField(
    targets,
    sources,
    getValue: (teacher) => teacher.email,
    setValue: (teacher, value) => teacher.email = value,
  );
}

/// Propagates discovered teacher contact info (conversation receiver IDs and
/// email addresses) across lessons in the same overview response without making
/// extra network requests.
void propagateLessonTeacherContactInfo(
  Iterable<Lesson> lessons, {
  Iterable<LessonTeacher> additionalSources = const [],
}) {
  final allTargets = [for (final lesson in lessons) ...lesson.teachers];
  final allSources = [
    ...additionalSources,
    for (final teacher in allTargets)
      if (teacher.conversationReceiverId != null || teacher.email != null)
        teacher,
  ];
  if (allSources.isEmpty) return;
  _applyTeacherContactInfo(allTargets, allSources);
}
