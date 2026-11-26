import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../../exceptions.dart';
import '../../models/file_info.dart';
import '../../models/lessons.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import '../teacher_message_link.dart';
import 'overview_parser.dart';

class LessonsStudentParser extends AppletParser<Lessons> {
  LessonsStudentParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.lessons,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  Future<Lessons> getHome() async {
    final response = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/meinunterricht.php',
      queryParameters: {'cacheBreaker': DateTime.now().millisecondsSinceEpoch},
    );
    return parseOverviewDocument(parse(response.data));
  }

  /// Parse the student overview offline, using the same path as [getHome].
  static Lessons parseOverviewDocument(Document document) =>
      _parse('lesson overview', () {
        return parseLessonsOverview(
          document.documentElement!,
          foldersId: 'mappen',
          attendanceId: 'anwesend',
        );
      });

  Future<DetailedLesson> getDetailedCourseView(
    String url, {
    bool force = false,
  }) async {
    try {
      final courseID = requiredLessonCourseId(url);

      final response = await ctx.session.dio.get(
        Uri.parse(
          'https://start.schulportal.hessen.de/',
        ).resolve(url).toString(),
        queryParameters: {
          if (force) "cacheBreaker": DateTime.now().millisecondsSinceEpoch,
        },
      );
      Document document = parse(response.data);

      return parseDetailedDocument(
        document,
        courseID: courseID,
        pupilId: Uri.parse(url).queryParameters['p'],
      );
    } catch (e, stack) {
      if (e is LanisException) rethrow;
      Error.throwWithStackTrace(
        UnknownException('${e.runtimeType}: $e'),
        stack,
      );
    }
  }

  /// Parse a course detail page without an authenticated session.
  static DetailedLesson parseDetailedDocument(
    Document document, {
    required String courseID,
    String? pupilId,
  }) => _parse('course detail', () {
    //course name
    final heading = document
        .getElementById('content')
        ?.querySelector('h1')
        ?.clone(true);
    if (heading == null) throw UnknownException('Missing course heading');
    for (final child in heading.querySelectorAll('small, button, i')) {
      child.remove();
    }
    final courseTitle = heading.text.trim();

    Uri? semester1URL;
    for (final link in document.querySelectorAll('a[href]')) {
      final uri = Uri.parse(link.attributes['href']!);
      if (uri.queryParameters['id'] == courseID &&
          uri.queryParameters['halb'] == '1' &&
          (pupilId == null || uri.queryParameters['p'] == pupilId)) {
        semester1URL = uri;
        break;
      }
    }

    if (document.getElementById('history') == null) {
      throw UnknownException('Missing student course history (#history)');
    }

    //historie
    List<CurrentEntry> history = [];

    Element? historySection = document.getElementById("history");
    List<Element>? historyTableRows = historySection?.querySelectorAll(
      "table>tbody>tr[data-entry]",
    );

    historyTableRows?.forEach((tableRow) {
      tableRow.children[2]
              .querySelector("div.hidden.hidden_encoded")
              ?.innerHtml =
          "";

      String? description = tableRow.children[1]
          .querySelector("span.markup i.far.fa-comment-alt:first-child")
          ?.parent
          ?.text
          .trim();

      String? homework = tableRow.children[1]
          .querySelector(
            'span.homework + br + span.markup, '
            'i.fa-home + br + span.markup',
          )
          ?.text
          .trim();
      final homeworkDone =
          tableRow.querySelector('span.done:not(.hidden)') != null;

      List<FileInfo> files = [];
      if (tableRow.children[1].querySelector("div.alert.alert-info") != null) {
        String baseURL = "https://start.schulportal.hessen.de/";
        baseURL += tableRow.children[1]
            .querySelector("div.alert.alert-info>a")!
            .attributes["href"]!;
        baseURL = baseURL.replaceAll("&b=zip", "");

        for (var fileDiv
            in tableRow.getElementsByClassName("files")[0].children) {
          String? filename = fileDiv.attributes["data-file"];
          files.add(
            FileInfo(
              name: filename,
              size: fileDiv.querySelector("a>small")?.text,
              url: Uri.parse(baseURL).replace(
                queryParameters: {
                  ...Uri.parse(baseURL).queryParameters,
                  'f': ?filename,
                },
              ),
            ),
          );
        }
      }

      List<LessonUpload> uploads = [];
      final uploadGroups = tableRow.children[1].querySelectorAll(
        "div.btn-group",
      );
      for (final uploadGroup in uploadGroups) {
        final openUpload = uploadGroup.querySelector(".btn-warning");
        final closedUpload = uploadGroup.querySelector(".btn-default");

        const String baseURL = "https://start.schulportal.hessen.de/";

        if (openUpload != null) {
          uploads.add(
            LessonUpload(
              name: _uploadName(openUpload),
              status: "open",
              url: Uri.parse(
                baseURL +
                    uploadGroup
                        .querySelector("ul.dropdown-menu li a")!
                        .attributes["href"]!,
              ),
              uploaded: openUpload.querySelector("span.badge")?.text,
              date: openUpload
                  .querySelector("small")
                  ?.text
                  .replaceAll("\n", "")
                  .replaceAll(
                    "                                                                ",
                    "",
                  )
                  .replaceAll("bis ", "")
                  .replaceAll("um", ""),
            ),
          );
        } else if (closedUpload != null) {
          uploads.add(
            LessonUpload(
              name: _uploadName(closedUpload),
              status: "closed",
              url: Uri.parse(
                baseURL +
                    uploadGroup
                        .querySelector("ul.dropdown-menu li a")!
                        .attributes["href"]!,
              ),
              uploaded: closedUpload.querySelector("span.badge")?.text,
            ),
          );
        }
      }

      final dateCell = tableRow.children[0];
      final dateMatch = RegExp(
        r'\d{2}\.\d{2}\.\d{4}',
      ).firstMatch(dateCell.text);
      if (dateMatch == null) {
        throw UnknownException('Missing history entry date');
      }
      final schoolHours = dateCell
          .querySelector('small')
          ?.text
          .replaceAll('Stunde', '')
          .trim();

      history.add(
        CurrentEntry(
          entryID: tableRow.attributes["data-entry"]!,
          topicTitle: tableRow.children[1].querySelector("td>b")?.text.trim(),
          description: description,
          presence: tableRow.children[2].text.trim() == 'nicht erfasst'
              ? null
              : tableRow.children[2].text.trim(),
          topicDate: DateTime.parse(
            dateMatch.group(0)!.split('.').reversed.join('-'),
          ),
          schoolHours: schoolHours,
          files: files,
          uploads: uploads,
          homework: (homework != null)
              ? Homework(description: homework, homeWorkDone: homeworkDone)
              : null,
        ),
      );
    });

    //anwesenheiten
    Element? presenceSection = document.getElementById("attendanceTable");
    List<Element>? attendanceTableRows = presenceSection?.querySelectorAll(
      "table>tbody>tr",
    );

    Map<String, String> attendances = {};

    attendanceTableRows?.forEach((row) {
      var encodedElements = row.getElementsByClassName("hidden_encoded");
      for (var e in encodedElements) {
        e.innerHtml = "";
      }
      if (row.children.length >= 2) {
        attendances[row.children[0].text.trim()] = row.children[1].text.trim();
      }
    });

    // Marks / Grades
    var marksSection = document.getElementById("marks");
    final markTableRows =
        marksSection?.querySelectorAll('table > tbody > tr') ?? <Element>[];

    List<LessonMark> marks = [];

    for (Element row in markTableRows) {
      var encodedElements = row.getElementsByClassName("hidden_encoded");
      for (var e in encodedElements) {
        e.innerHtml = "";
      }

      String? comment;
      Element? mnCommentElement = row.nextElementSibling;
      if (row.children.length == 3 &&
          mnCommentElement != null &&
          mnCommentElement.children.length == 2) {
        Element element = mnCommentElement;
        Element commentElement = element.querySelectorAll("td")[1];
        comment = commentElement.text.trim().replaceFirst(
          RegExp(r'^[^:]*:\s*'),
          '',
        );
        if (comment.trim().isEmpty) {
          comment = null;
        }
      }

      if (row.children.length == 3) {
        marks.add(
          LessonMark(
            name: row.children[0].text.trim(),
            date: row.children[1].text.trim(),
            mark: row.children[2].text.trim(),
            comment: comment,
          ),
        );
      }
    }

    //leistungskontrollen
    Element? examSection = document.getElementById("klausuren");

    List<LessonExam> lessonExams = [];

    if (examSection != null &&
        examSection.children.isNotEmpty &&
        !examSection.text.contains(
          "Diese Kursmappe beinhaltet leider noch keine Leistungskontrollen!",
        )) {
      for (var element in examSection.children) {
        String exams = "";

        final elements = element.querySelectorAll("ul li");

        for (var element in elements) {
          //todo better solution that splitting the string with "  ...  "
          var exam = element.text.trim().split(
            "                                                                                                    ",
          );
          exams +=
              "${exam.first.trim()} ${exam.last != exam.first ? exam.last.trim() : ""}";
          if (element != elements.last) {
            exams += "\n";
          }
        }

        lessonExams.add(
          LessonExam(
            name: element.querySelector("h1,h2,h3,h4,h5,h6")?.text.trim() ?? "",
            value: exams == "" ? "Keine Daten!" : exams,
          ),
        );
      }
    }
    final teacherButtons = document.getElementsByClassName(
      "btn btn-primary dropdown-toggle btn-md",
    );
    return DetailedLesson(
      courseID: courseID,
      pupilId: pupilId,
      name: courseTitle,
      teachers: teacherButtons
          .map<LessonTeacher>(
            (e) => LessonTeacher(
              teacher:
                  e.attributes['title']?.split(' (').first.trim() ??
                  e.parent
                      ?.querySelector('ul > li > a, ul > li > span')
                      ?.text
                      .trim(),
              teacherKuerzel: e.text.trim(),
              conversationReceiverId: parseTeacherConversationReceiverId(
                e.parent,
              ),
            ),
          )
          .toList(),
      history: history,
      marks: marks,
      exams: lessonExams,
      attendances: attendances,
      semester1URL: semester1URL,
    );
  });

  Future<String> setHomework(
    String courseID,
    String courseEntry,
    bool status,
  ) async {
    //returns the response of the http request. 1 means success.

    final response = await ctx.session.dio.post(
      "https://start.schulportal.hessen.de/meinunterricht.php",
      data: {
        "a": "sus_homeworkDone",
        "entry": courseEntry,
        "id": courseID,
        "b": status ? "done" : "undone",
      },
      options: Options(
        headers: {
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "X-Requested-With": "XMLHttpRequest", //this is important
        },
      ),
    );

    return response.data;
  }

  Future<String> deleteUploadedFile({
    required String course,
    required String entry,
    required String upload,
    required String file,
    required String userPasswordEncrypted,
  }) async {
    try {
      final response = await ctx.session.dio.post(
        "https://start.schulportal.hessen.de/meinunterricht.php",
        data: {
          "a": "sus_abgabe",
          "d": "delete",
          "b": course,
          "e": entry,
          "id": upload,
          "f": file,
          "pw": userPasswordEncrypted,
        },
        options: Options(
          headers: {
            "Accept": "*/*",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "X-Requested-With": "XMLHttpRequest",
          },
        ),
      );

      // "-1" Wrong password
      // "-2" Delete was not possible
      // "0" Unknown error
      // "1" Lanis had a good day
      return response.data;
    } on SocketException catch (error, stack) {
      Error.throwWithStackTrace(NetworkException(error.toString()), stack);
    } on DioException catch (error, stack) {
      Error.throwWithStackTrace(NetworkException(error.toString()), stack);
    } catch (e, stack) {
      if (e is LanisException) rethrow;
      Error.throwWithStackTrace(
        UnknownException('${e.runtimeType}: $e'),
        stack,
      );
    }
  }

  Future<dynamic> getUploadInfo(String url) async {
    try {
      final response = await ctx.session.dio.get(url);
      final parsed = parse(response.data);

      return parseUploadDocument(parsed);
    } on SocketException catch (error, stack) {
      Error.throwWithStackTrace(NetworkException(error.toString()), stack);
    } on DioException catch (error, stack) {
      Error.throwWithStackTrace(NetworkException(error.toString()), stack);
    } catch (e, stack) {
      if (e is LanisException) rethrow;
      Error.throwWithStackTrace(
        UnknownException('${e.runtimeType}: $e'),
        stack,
      );
    }
  }

  /// Parse submission requirements, identifiers, and files offline.
  static Map<String, dynamic> parseUploadDocument(
    Document parsed,
  ) => _parse('upload page', () {
    final content = parsed.getElementById('content');
    final start = content?.querySelector('[data-field="Von"]');
    final deadline = content?.querySelector('[data-field="Bis"]');
    if (content == null || start == null || deadline == null) {
      throw UnknownException('Missing submission requirements (Von/Bis)');
    }
    var requirements = start;
    while (!requirements.classes.contains('col-md-12') &&
        requirements.parent != null) {
      requirements = requirements.parent!;
    }
    final permissions = requirements.querySelectorAll(
      'i.fa-check-square-o + span.label, i.fa-square-o + span.label',
    );
    if (permissions.length != 2) {
      throw UnknownException('Missing submission permission labels');
    }
    final fileLabels = requirements.querySelectorAll('i.fa-file + span.label');
    if (fileLabels.length != 2) {
      throw UnknownException('Missing allowed file types or maximum file size');
    }
    final heading = content.querySelector('h1');
    final form = content
        .querySelector('form input[name="a"][value="sus_abgabe"]')
        ?.parent;
    String? identifier(String name, String attribute) =>
        form?.querySelector('input[name="$name"]')?.attributes['value'] ??
        heading?.attributes[attribute];
    final ownSection = content.querySelector('a[name="eigene"]')?.parent;
    final ownFiles = <OwnFile>[];
    for (final item in ownSection?.querySelectorAll('ul > li') ?? <Element>[]) {
      final link = item.querySelector('a[href]');
      if (link == null) continue;
      final uri = Uri.parse(
        'https://start.schulportal.hessen.de/',
      ).resolve(link.attributes['href']!);
      final copy = item.clone(true);
      for (final node in copy.querySelectorAll('a, small, button, ul')) {
        node.remove();
      }
      final comment = copy.text.trim();
      ownFiles.add(
        OwnFile(
          name: link.text.trim(),
          url: uri.toString(),
          time: item.querySelector('small')?.text.trim() ?? '',
          index: uri.queryParameters['f'] ?? '',
          comment: comment.isEmpty ? null : comment,
        ),
      );
    }
    final publicFiles = <PublicFile>[];
    for (final item in content.querySelectorAll('.col-md-5 ul li')) {
      final link = item.querySelector('a[href]');
      if (link == null) continue;
      publicFiles.add(
        PublicFile(
          name: link.text.trim(),
          url: Uri.parse(
            'https://start.schulportal.hessen.de/',
          ).resolve(link.attributes['href']!).toString(),
          index: Uri.parse(link.attributes['href']!).queryParameters['f'] ?? '',
          person:
              item.querySelector('span.label.label-info')?.text.trim() ?? '',
        ),
      );
    }
    final extra = requirements
        .querySelector('.alert.alert-info')
        ?.text
        .trim()
        .replaceFirst(RegExp(r'^Zusatztext:\s*'), '');
    return {
      'start': start.text
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\bab\s+'), ''),
      'deadline': deadline.text
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\bspätestens\s+'), ''),
      'upload_multiple_files': permissions[0].text.trim() == 'erlaubt',
      'upload_any_number_of_times': permissions[1].text.trim() == 'erlaubt',
      'visibility': requirements
          .querySelector('i.fa-eye + span.label, i.fa-eye-slash + span.label')
          ?.text
          .trim(),
      'automatic_deletion': requirements
          .querySelector('i.fa-trash-o + span.label')
          ?.text
          .trim(),
      'allowed_file_types': fileLabels[0].text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'max_file_size': fileLabels[1].text.trim(),
      'course_id': identifier('b', 'data-buch'),
      'entry_id': identifier('e', 'data-eintrag'),
      'upload_id': identifier('id', 'data-abgabe'),
      'own_files': ownFiles,
      'public_files': publicFiles,
      'additional_text': extra == null || extra.isEmpty ? null : extra,
    };
  });

  Future<List<FileStatus>> uploadFile({
    required String course,
    required String entry,
    required String upload,
    required MultipartFile file1,
    MultipartFile? file2,
    MultipartFile? file3,
    MultipartFile? file4,
    MultipartFile? file5,
  }) async {
    try {
      final FormData uploadData = FormData.fromMap({
        "a": "sus_abgabe",
        "b": course,
        "e": entry,
        "id": upload,
        "file1": file1,
        "file2": file2,
        "file3": file3,
        "file4": file4,
        "file5": file5,
      });

      final response = await ctx.session.dio.post(
        "https://start.schulportal.hessen.de/meinunterricht.php",
        data: uploadData,
        options: Options(
          headers: {
            "Accept": "*/*",
            "Content-Type": "multipart/form-data;",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "same-origin",
          },
        ),
      );

      final parsed = parse(response.data);

      return parseUploadStatusDocument(parsed);
    } on SocketException catch (error, stack) {
      Error.throwWithStackTrace(NetworkException(error.toString()), stack);
    } on DioException catch (error, stack) {
      Error.throwWithStackTrace(NetworkException(error.toString()), stack);
    } catch (e, stack) {
      if (e is LanisException) rethrow;
      Error.throwWithStackTrace(
        UnknownException('${e.runtimeType}: $e'),
        stack,
      );
    }
  }

  /// Parse the server's per-file upload results offline.
  static List<FileStatus> parseUploadStatusDocument(Document parsed) =>
      _parse('upload results', () {
        final messages = <FileStatus>[];
        for (final item in parsed.querySelectorAll('#content ul > li')) {
          final name = item.querySelector('b');
          final status = item.querySelector('span.label');
          if (name == null || status == null) continue;
          final copy = item.clone(true);
          copy.querySelector('b')?.remove();
          copy.querySelector('span.label')?.remove();
          final message = copy.text.trim();
          messages.add(
            FileStatus(
              name: name.text.trim(),
              status: status.text.trim(),
              message: message.isEmpty ? null : message,
            ),
          );
        }
        if (messages.isEmpty) {
          throw UnknownException('Missing per-file upload results');
        }
        return messages;
      });

  static String _uploadName(Element button) {
    final label = button.clone(true);
    for (final child in label.querySelectorAll('i, small, .badge, .caret')) {
      child.remove();
    }
    return label.text.trim();
  }

  static T _parse<T>(String operation, T Function() read) {
    try {
      return read();
    } catch (error, stack) {
      if (error is LanisException) rethrow;
      Error.throwWithStackTrace(
        UnknownException(
          'Failed to parse $operation: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }
}
