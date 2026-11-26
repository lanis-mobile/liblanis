import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../../exceptions.dart';
import '../../models/lessons.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import 'overview_parser.dart';
import 'student_parser.dart';

/// Read-only lessons API for parents, with courses scoped to their pupil.
///
/// [getHome] returns every child and their parsed overview in one request.
/// [getDetailedCourseView] loads a course only when it is opened.
/// Homework missing from the portal response remains absent.
class LessonsParentParser extends AppletParser<ParentLessonsOverview> {
  LessonsParentParser(AppletContext ctx, {Future<bool> Function()? isConnected})
    : super(
        ctx,
        Applets.lessons,
        isConnected:
            isConnected ?? () => ctx.session.connectionChecker.connected,
      );

  Future<Document> _overview() async {
    final response = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/meinunterricht.php',
      queryParameters: {'cacheBreaker': DateTime.now().millisecondsSinceEpoch},
    );
    return parse(response.data);
  }

  /// Parse the full page into child-to-course mappings using one request.
  @override
  Future<ParentLessonsOverview> getHome() async =>
      parseOverviewDocument(await _overview());

  static List<LessonPupil> _parsePupilsDocument(Document document) {
    final pupils = <LessonPupil>[];
    for (final box in document.querySelectorAll('.pupilbox')) {
      final heading = box.querySelector('h2[data-pupil]');
      final id = heading?.attributes['data-pupil'];
      if (id == null || id.isEmpty || heading == null) {
        throw UnknownException('Missing parent pupil identity');
      }
      if (pupils.any((pupil) => pupil.id == id)) {
        throw UnknownException('Duplicate parent pupil identity');
      }
      pupils.add(LessonPupil(id: id, name: heading.text.trim()));
    }
    if (pupils.isEmpty) {
      throw UnknownException('Missing parent pupil sections (.pupilbox)');
    }
    return pupils;
  }

  static ParentLessonsOverview parseOverviewDocument(Document document) {
    try {
      final pupils = _parsePupilsDocument(document);
      final boxes = document.querySelectorAll('.pupilbox');
      final lessonsByPupil = {
        for (var i = 0; i < pupils.length; i++)
          pupils[i]: parseLessonsOverview(
            boxes[i],
            foldersId: 'mappen${pupils[i].id}',
            attendanceId: 'anwesend${pupils[i].id}',
            pupilId: pupils[i].id,
          ),
      };
      propagateLessonTeacherConversationIds(
        lessonsByPupil.values.expand((courses) => courses),
      );
      return ParentLessonsOverview(lessonsByPupil: lessonsByPupil);
    } catch (error, stack) {
      if (error is LanisException) rethrow;
      Error.throwWithStackTrace(
        UnknownException(
          'Parent lesson overview: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }

  /// Load exactly one parent course URL, including its `p` query parameter.
  /// Visible homework is parsed with or without student completion controls.
  /// Completion status is taken only from the detail response.
  /// Homework absent from the detail HTML remains absent.
  Future<DetailedLesson> getDetailedCourseView(
    String url, {
    bool force = false,
  }) async {
    final pupilId = Uri.parse(url).queryParameters['p'];
    if (pupilId == null || pupilId.isEmpty) {
      throw ConfigurationException('Parent course URL requires a pupil (p)');
    }
    final parser = LessonsStudentParser(ctx, isConnected: isConnected);
    try {
      return await parser.getDetailedCourseView(url, force: force);
    } finally {
      parser.dispose();
    }
  }
}
