import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../applets/applet_context.dart';
import '../applets/calendar/parser.dart';
import '../applets/conversations/parser.dart';
import '../applets/data_storage/parser.dart';
import '../applets/lessons/student_parser.dart';
import '../applets/lessons/parent_parser.dart';
import '../applets/lessons/teacher_parser.dart';
import '../applets/study_groups/parser.dart';
import '../applets/substitutions/parser.dart';
import '../applets/timetable/parser.dart';
import '../exceptions.dart';
import '../settings/typed_settings.dart';
import 'core_providers.dart';

part 'applet_providers.g.dart';

/// Builds only when [sessionProvider] has a ready [LanisSession].
/// Watches [activeAccountIdProvider] (not the full account) so accountType
/// [ActiveAccount.replace] does not recreate parsers.
@Riverpod(keepAlive: true)
AppletContext appletContext(Ref ref) {
  final accountId = ref.watch(activeAccountIdProvider);
  final session = ref.watch(sessionProvider).asData?.value;
  final account = ref.read(activeAccountProvider);
  if (accountId == null ||
      session == null ||
      account == null ||
      account.localId != accountId) {
    throw ConfigurationException(
      'AppletContext requires an active authenticated session',
    );
  }
  final db = ref.watch(lanisDatabaseProvider);
  return AppletContext(
    session: session,
    database: db,
    account: account,
    accountSettings: TypedSettings.account(db, account.localId),
  );
}

Future<bool> _connected(Ref ref) =>
    ref.read(connectionCheckerProvider).connected;

@Riverpod(keepAlive: true)
SubstitutionsParser substitutionsParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = SubstitutionsParser(ctx, isConnected: () => _connected(ref));
  parser.loadFilterFromStorage();
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
TimetableStudentParser timetableParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = TimetableStudentParser(
    ctx,
    isConnected: () => _connected(ref),
  );
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
CalendarParser calendarParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = CalendarParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
ConversationsParser conversationsParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = ConversationsParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
LessonsStudentParser lessonsStudentParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = LessonsStudentParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
LessonsParentParser lessonsParentParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = LessonsParentParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
LessonsTeacherParser lessonsTeacherParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = LessonsTeacherParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
DataStorageParser dataStorageParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = DataStorageParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
StudyGroupsStudentParser studyGroupsParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = StudyGroupsStudentParser(
    ctx,
    isConnected: () => _connected(ref),
  );
  ref.onDispose(parser.dispose);
  return parser;
}
