import '../models/account_types.dart';

/// Dart-only applet metadata (no Flutter icons/widgets).
class AppletMeta {
  final String appletPhpUrl;
  final List<AccountType> supportedAccountTypes;
  final bool allowOffline;
  final Duration refreshInterval;
  final Map<String, dynamic> settingsDefaults;

  const AppletMeta({
    required this.appletPhpUrl,
    required this.supportedAccountTypes,
    required this.refreshInterval,
    this.settingsDefaults = const {},
    this.allowOffline = false,
  });
}

/// Built-in applet identifiers and defaults used by parsers.
class Applets {
  static const substitutions = AppletMeta(
    appletPhpUrl: 'vertretungsplan.php',
    supportedAccountTypes: [
      AccountType.student,
      AccountType.teacher,
      AccountType.parent,
    ],
    refreshInterval: Duration(minutes: 10),
    allowOffline: true,
  );

  static const calendar = AppletMeta(
    appletPhpUrl: 'kalender.php',
    supportedAccountTypes: [
      AccountType.student,
      AccountType.teacher,
      AccountType.parent,
    ],
    refreshInterval: Duration(hours: 1),
  );

  static const timetable = AppletMeta(
    appletPhpUrl: 'stundenplan.php',
    supportedAccountTypes: [AccountType.student, AccountType.parent],
    refreshInterval: Duration(hours: 1),
    allowOffline: true,
  );

  static const conversations = AppletMeta(
    appletPhpUrl: 'nachrichten.php',
    supportedAccountTypes: [
      AccountType.student,
      AccountType.teacher,
      AccountType.parent,
    ],
    refreshInterval: Duration(minutes: 2),
  );

  static const lessons = AppletMeta(
    appletPhpUrl: 'meinunterricht.php',
    supportedAccountTypes: [
      AccountType.student,
      AccountType.teacher,
      AccountType.parent,
    ],
    refreshInterval: Duration(minutes: 15),
  );

  static const dataStorage = AppletMeta(
    appletPhpUrl: 'dateispeicher.php',
    supportedAccountTypes: [
      AccountType.student,
      AccountType.teacher,
      AccountType.parent,
    ],
    refreshInterval: Duration(minutes: 5),
  );

  static const studyGroups = AppletMeta(
    appletPhpUrl: 'lerngruppen.php',
    supportedAccountTypes: [AccountType.student],
    refreshInterval: Duration(minutes: 15),
  );

  static const fileDistribution = AppletMeta(
    appletPhpUrl: 'dateiverteilung.php',
    supportedAccountTypes: [
      AccountType.student,
      AccountType.teacher,
      AccountType.parent,
    ],
    refreshInterval: Duration(minutes: 15),
    allowOffline: true,
  );

  static const all = [
    substitutions,
    calendar,
    timetable,
    conversations,
    lessons,
    dataStorage,
    studyGroups,
    fileDistribution,
  ];

  static AppletMeta byPhpUrl(String phpUrl) {
    return all.firstWhere((a) => a.appletPhpUrl == phpUrl);
  }
}
