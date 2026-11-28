/// Pure Dart Lanis (Schulportal Hessen) client.
///
/// Configure with [LanisClient.configure], apply [LanisClient.overrides] to a
/// Riverpod [ProviderScope]/[ProviderContainer], then use the exported providers.
library;

export 'src/applets/applet_context.dart';
export 'src/applets/applet_parser.dart';
export 'src/applets/definition.dart';
export 'src/applets/calendar/parser.dart';
export 'src/applets/conversations/parser.dart';
export 'src/applets/data_storage/parser.dart';
export 'src/applets/file_distribution/parser.dart';
export 'src/applets/lessons/student_parser.dart';
export 'src/applets/lessons/parent_parser.dart';
export 'src/applets/lessons/teacher_parser.dart';
export 'src/applets/study_groups/parser.dart';
export 'src/applets/substitutions/parser.dart';
export 'src/applets/timetable/parser.dart';
export 'src/applets/timetable/parent_parser.dart';
export 'src/applets/timetable/teacher_parser.dart';
export 'src/config.dart';
export 'src/connection/connection_checker.dart';
export 'src/database/database.dart';
export 'src/exceptions.dart';
export 'src/models/account.dart';
export 'src/models/account_types.dart';
export 'src/models/calendar_event.dart';
export 'src/models/conversations.dart';
export 'src/models/datastorage.dart';
export 'src/models/file_distribution.dart';
export 'src/models/file_info.dart';
export 'src/models/lessons.dart';
export 'src/models/lessons_teacher.dart';
export 'src/models/study_groups.dart';
export 'src/models/substitution.dart';
export 'src/models/time_of_day.dart';
export 'src/models/timetable.dart';
export 'src/models/timetable_parent.dart';
export 'src/models/timetable_teacher.dart';
export 'src/providers/applet_providers.dart';
export 'src/providers/core_providers.dart';
export 'src/secret_store.dart';
export 'src/session/session.dart';
export 'src/settings/typed_settings.dart';
export 'src/lanis_client.dart';
export 'src/storage/storage_manager.dart';

export 'src/cache/types.dart';
export 'src/cache/store.dart';
export 'src/cache/service.dart';
export 'src/cache/annotation.dart';
export 'src/cache/catalog.dart';
export 'src/providers/cache_providers.dart';
