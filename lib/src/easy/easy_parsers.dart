import '../applets/applet_context.dart';
import '../applets/applet_parser.dart';
import '../models/account_types.dart';
import '../applets/calendar/parser.dart';
import '../applets/conversations/parser.dart';
import '../applets/data_storage/parser.dart';
import '../applets/definition.dart';
import '../applets/file_distribution/parser.dart';
import '../applets/lessons/student_parser.dart';
import '../applets/lessons/parent_parser.dart';
import '../applets/lessons/teacher_parser.dart';
import '../applets/study_groups/parser.dart';
import '../applets/substitutions/parser.dart';
import '../applets/timetable/parser.dart';
import '../applets/timetable/parent_parser.dart';
import '../applets/timetable/teacher_parser.dart';
import '../exceptions.dart';

/// Lazy registry of applet parsers for [EasyLanisClient].
class EasyParsers {
  final AppletContext _ctx;
  final Future<bool> Function() _isConnected;

  SubstitutionsParser? _substitutions;
  TimetableStudentParser? _timetable;
  TimetableParentParser? _timetableParent;
  TimetableTeacherParser? _timetableTeacher;
  CalendarParser? _calendar;
  ConversationsParser? _conversations;
  LessonsStudentParser? _lessonsStudent;
  LessonsParentParser? _lessonsParent;
  LessonsTeacherParser? _lessonsTeacher;
  DataStorageParser? _dataStorage;
  StudyGroupsStudentParser? _studyGroups;
  FileDistributionParser? _fileDistribution;

  EasyParsers({
    required this._ctx,
    required this._isConnected,
  }) {
    substitutions.loadFilterFromStorage();
  }

  SubstitutionsParser get substitutions =>
      _substitutions ??= SubstitutionsParser(_ctx, isConnected: _isConnected);

  TimetableStudentParser get timetable =>
      _timetable ??= TimetableStudentParser(_ctx, isConnected: _isConnected);

  TimetableParentParser get timetableParent => _timetableParent ??=
      TimetableParentParser(_ctx, isConnected: _isConnected);

  TimetableTeacherParser get timetableTeacher => _timetableTeacher ??=
      TimetableTeacherParser(_ctx, isConnected: _isConnected);

  CalendarParser get calendar =>
      _calendar ??= CalendarParser(_ctx, isConnected: _isConnected);

  ConversationsParser get conversations =>
      _conversations ??= ConversationsParser(_ctx, isConnected: _isConnected);

  LessonsStudentParser get lessonsStudent =>
      _lessonsStudent ??= LessonsStudentParser(_ctx, isConnected: _isConnected);

  LessonsParentParser get lessonsParent =>
      _lessonsParent ??= LessonsParentParser(_ctx, isConnected: _isConnected);

  LessonsTeacherParser get lessonsTeacher =>
      _lessonsTeacher ??= LessonsTeacherParser(_ctx, isConnected: _isConnected);

  DataStorageParser get dataStorage =>
      _dataStorage ??= DataStorageParser(_ctx, isConnected: _isConnected);

  StudyGroupsStudentParser get studyGroups => _studyGroups ??=
      StudyGroupsStudentParser(_ctx, isConnected: _isConnected);

  FileDistributionParser get fileDistribution => _fileDistribution ??=
      FileDistributionParser(_ctx, isConnected: _isConnected);

  AppletParser<dynamic> forApplet(String phpUrl) {
    final known = Applets.all.any((a) => a.appletPhpUrl == phpUrl);
    if (!known) {
      throw UnknownException('Unknown applet: $phpUrl');
    }
    if (phpUrl == Applets.lessons.appletPhpUrl) {
      final type = _ctx.account.accountType ?? _ctx.session.accountTypeOrNull;
      if (type == AccountType.teacher) return lessonsTeacher;
      if (type == AccountType.parent) return lessonsParent;
      return lessonsStudent;
    }
    if (phpUrl == Applets.timetable.appletPhpUrl) {
      final type = _ctx.account.accountType ?? _ctx.session.accountTypeOrNull;
      if (type == AccountType.teacher) return timetableTeacher;
      if (type == AccountType.parent) return timetableParent;
      return timetable;
    }
    return switch (phpUrl) {
      'vertretungsplan.php' => substitutions,
      'stundenplan.php' => timetable,
      'kalender.php' => calendar,
      'nachrichten.php' => conversations,
      'dateispeicher.php' => dataStorage,
      'lerngruppen.php' => studyGroups,
      'dateiverteilung.php' => fileDistribution,
      _ => throw UnknownException('Unknown applet: $phpUrl'),
    };
  }

  void disposeAll() {
    _substitutions?.dispose();
    _timetable?.dispose();
    _timetableParent?.dispose();
    _timetableTeacher?.dispose();
    _calendar?.dispose();
    _conversations?.dispose();
    _lessonsStudent?.dispose();
    _lessonsParent?.dispose();
    _lessonsTeacher?.dispose();
    _dataStorage?.dispose();
    _studyGroups?.dispose();
    _fileDistribution?.dispose();
    _substitutions = null;
    _timetable = null;
    _timetableParent = null;
    _timetableTeacher = null;
    _calendar = null;
    _conversations = null;
    _lessonsStudent = null;
    _lessonsParent = null;
    _lessonsTeacher = null;
    _dataStorage = null;
    _studyGroups = null;
    _fileDistribution = null;
  }
}

/// Convenience wrapper around [AppletParser.fetchData].
extension AppletParserFetch<T> on AppletParser<T> {
  Future<FetcherResponse<T>> fetch({bool forceRefresh = false}) async {
    await fetchData(forceRefresh: forceRefresh);
    return latestResponse!;
  }
}
