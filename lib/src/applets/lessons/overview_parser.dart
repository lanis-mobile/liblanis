import 'package:html/dom.dart';

import '../../exceptions.dart';
import '../../models/file_info.dart';
import '../../models/lessons.dart';

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
  var schoolClasses = scope.querySelectorAll("tr.printable");
  for (var schoolClass in schoolClasses) {
    if (schoolClass.querySelector(".datum") != null) {
      String? topicTitle = schoolClass.querySelector(".thema")?.text.trim();
      String? topicDateString = schoolClass
          .querySelector(".datum")
          ?.text
          .trim();
      DateTime? topicDate = DateTime.parse(
        topicDateString!.split(".").reversed.join("-"),
      );
      String? courseURL = schoolClass
          .querySelector("td>h3>a")
          ?.attributes["href"];
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
