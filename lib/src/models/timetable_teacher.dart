import 'time_of_day.dart';
import 'timetable.dart';

/// The four lookup categories available in the teacher `stundenplan.php` view.
enum TeacherTimetableCategory {
  teacher,
  schoolClass,
  room,
  breakSupervision,
}

/// Kind of entry rendered inside a teacher timetable cell.
enum TeacherTimetableEntryKind {
  regular,
  breakSupervision,
  substitutionAdded,
  substitutionChanged,
  roomBooking,
}

/// Reference to a teacher, class, room, or break supervision timetable.
class TeacherTimetableReference {
  final TeacherTimetableCategory category;
  final String id;
  final String label;
  final Uri url;

  const TeacherTimetableReference({
    required this.category,
    required this.id,
    required this.label,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'id': id,
    'label': label,
    'url': url.toString(),
  };

  factory TeacherTimetableReference.fromJson(Map<String, dynamic> json) =>
      TeacherTimetableReference(
        category: TeacherTimetableCategory.values.byName(
          json['category'] as String,
        ),
        id: json['id'] as String,
        label: json['label'] as String,
        url: Uri.parse(json['url'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is TeacherTimetableReference &&
      category == other.category &&
      id == other.id &&
      label == other.label &&
      url == other.url;

  @override
  int get hashCode => Object.hash(category, id, label, url);

  @override
  String toString() =>
      'TeacherTimetableReference(category: $category, id: $id, label: $label)';
}

/// Overview returned by `stundenplan.php` for teacher accounts.
class TeacherTimetableOverview {
  /// Direct link to the logged-in teacher's own plan ("eigener Stundenplan"), if shown.
  final Uri? ownTimetableUrl;

  /// Available teacher plans. Empty when the school restricts `teacherCanSee=own`.
  final List<TeacherTimetableReference> teachers;

  /// Available class/course plans (`a=detail_klasse`).
  final List<TeacherTimetableReference> classes;

  /// Available room plans (`a=detail_raum`).
  final List<TeacherTimetableReference> rooms;

  /// Available break supervision ("Pausenaufsichten") plans (`a=detail_pause`).
  final List<TeacherTimetableReference> breakSupervisions;

  /// Whether the "Lehrkräfte" panel is shown (false when `teacherCanSee=own`).
  final bool canViewOtherTeachers;

  /// Link to the free-room finder (`a=freeRoom`), if present.
  final Uri? freeRoomsUrl;

  /// Optional admin-configured HTML notice (`hinweis`).
  final String? noticeHtml;

  TeacherTimetableOverview({
    this.ownTimetableUrl,
    required List<TeacherTimetableReference> teachers,
    required List<TeacherTimetableReference> classes,
    required List<TeacherTimetableReference> rooms,
    required List<TeacherTimetableReference> breakSupervisions,
    required this.canViewOtherTeachers,
    this.freeRoomsUrl,
    this.noticeHtml,
  }) : teachers = List.unmodifiable(teachers),
       classes = List.unmodifiable(classes),
       rooms = List.unmodifiable(rooms),
       breakSupervisions = List.unmodifiable(breakSupervisions);

  Map<String, dynamic> toJson() => {
    if (ownTimetableUrl != null) 'ownTimetableUrl': ownTimetableUrl.toString(),
    'teachers': teachers.map((e) => e.toJson()).toList(),
    'classes': classes.map((e) => e.toJson()).toList(),
    'rooms': rooms.map((e) => e.toJson()).toList(),
    'breakSupervisions': breakSupervisions.map((e) => e.toJson()).toList(),
    'canViewOtherTeachers': canViewOtherTeachers,
    if (freeRoomsUrl != null) 'freeRoomsUrl': freeRoomsUrl.toString(),
    if (noticeHtml != null) 'noticeHtml': noticeHtml,
  };

  factory TeacherTimetableOverview.fromJson(Map<String, dynamic> json) =>
      TeacherTimetableOverview(
        ownTimetableUrl: json['ownTimetableUrl'] == null
            ? null
            : Uri.parse(json['ownTimetableUrl'] as String),
        teachers: _refList(json['teachers']),
        classes: _refList(json['classes']),
        rooms: _refList(json['rooms']),
        breakSupervisions: _refList(json['breakSupervisions']),
        canViewOtherTeachers: json['canViewOtherTeachers'] as bool? ?? true,
        freeRoomsUrl: json['freeRoomsUrl'] == null
            ? null
            : Uri.parse(json['freeRoomsUrl'] as String),
        noticeHtml: json['noticeHtml'] as String?,
      );

  static List<TeacherTimetableReference> _refList(Object? raw) =>
      (raw as List? ?? const [])
          .map(
            (e) =>
                TeacherTimetableReference.fromJson(e as Map<String, dynamic>),
          )
          .toList();
}

/// Teacher contact entry parsed from the room-plan teacher summary (`detail_raum`).
class TeacherTimetableContact {
  final String teacherCode;
  final String? displayName;
  final String? email;

  const TeacherTimetableContact({
    required this.teacherCode,
    this.displayName,
    this.email,
  });

  Map<String, dynamic> toJson() => {
    'teacherCode': teacherCode,
    if (displayName != null) 'displayName': displayName,
    if (email != null) 'email': email,
  };

  factory TeacherTimetableContact.fromJson(Map<String, dynamic> json) =>
      TeacherTimetableContact(
        teacherCode: json['teacherCode'] as String,
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is TeacherTimetableContact &&
      teacherCode == other.teacherCode &&
      displayName == other.displayName &&
      email == other.email;

  @override
  int get hashCode => Object.hash(teacherCode, displayName, email);
}

/// A single lesson, break supervision, embedded substitution, or room booking entry.
class TeacherTimetableEntry {
  final String id;
  final TeacherTimetableEntryKind kind;
  final String? subject;
  final String? course;
  final String? room;
  final List<String> teachers;
  final List<String> classes;
  final String? supervisionLocation;
  final String? badge;
  final String? embeddedDate;
  final String? tooltip;
  final int duration;
  final SphTimeOfDay startTime;
  final SphTimeOfDay endTime;
  final int? hourIndex;
  final Uri? substitutionCreateUrl;
  final Uri? externalUrl;

  TeacherTimetableEntry({
    required this.id,
    required this.kind,
    this.subject,
    this.course,
    this.room,
    List<String> teachers = const [],
    List<String> classes = const [],
    this.supervisionLocation,
    this.badge,
    this.embeddedDate,
    this.tooltip,
    required this.duration,
    required this.startTime,
    required this.endTime,
    this.hourIndex,
    this.substitutionCreateUrl,
    this.externalUrl,
  }) : teachers = List.unmodifiable(teachers),
       classes = List.unmodifiable(classes);

  bool get isEmbeddedSubstitution =>
      kind == TeacherTimetableEntryKind.substitutionAdded ||
      kind == TeacherTimetableEntryKind.substitutionChanged;

  bool get isRoomBooking => kind == TeacherTimetableEntryKind.roomBooking;

  bool get isBreakSupervision =>
      kind == TeacherTimetableEntryKind.breakSupervision;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (subject != null) 'subject': subject,
    if (course != null) 'course': course,
    if (room != null) 'room': room,
    if (teachers.isNotEmpty) 'teachers': teachers,
    if (classes.isNotEmpty) 'classes': classes,
    if (supervisionLocation != null) 'supervisionLocation': supervisionLocation,
    if (badge != null) 'badge': badge,
    if (embeddedDate != null) 'embeddedDate': embeddedDate,
    if (tooltip != null) 'tooltip': tooltip,
    'duration': duration,
    'startTime': [startTime.hour, startTime.minute],
    'endTime': [endTime.hour, endTime.minute],
    if (hourIndex != null) 'hourIndex': hourIndex,
    if (substitutionCreateUrl != null)
      'substitutionCreateUrl': substitutionCreateUrl.toString(),
    if (externalUrl != null) 'externalUrl': externalUrl.toString(),
  };

  factory TeacherTimetableEntry.fromJson(Map<String, dynamic> json) {
    final start = json['startTime'] as List;
    final end = json['endTime'] as List;
    return TeacherTimetableEntry(
      id: json['id'] as String,
      kind: TeacherTimetableEntryKind.values.byName(json['kind'] as String),
      subject: json['subject'] as String?,
      course: json['course'] as String?,
      room: json['room'] as String?,
      teachers: (json['teachers'] as List? ?? const []).cast<String>(),
      classes: (json['classes'] as List? ?? const []).cast<String>(),
      supervisionLocation: json['supervisionLocation'] as String?,
      badge: json['badge'] as String?,
      embeddedDate: json['embeddedDate'] as String?,
      tooltip: json['tooltip'] as String?,
      duration: json['duration'] as int,
      startTime: SphTimeOfDay(hour: start[0] as int, minute: start[1] as int),
      endTime: SphTimeOfDay(hour: end[0] as int, minute: end[1] as int),
      hourIndex: json['hourIndex'] as int?,
      substitutionCreateUrl: json['substitutionCreateUrl'] == null
          ? null
          : Uri.parse(json['substitutionCreateUrl'] as String),
      externalUrl: json['externalUrl'] == null
          ? null
          : Uri.parse(json['externalUrl'] as String),
    );
  }

  @override
  String toString() =>
      'TeacherTimetableEntry($kind, subject=$subject, room=$room, teachers=$teachers, classes=$classes, supervision=$supervisionLocation, badge=$badge, date=$embeddedDate)';
}

/// Parsed detail timetable for a teacher, class, room, or break supervision location.
class TeacherTimetablePlan {
  final TeacherTimetableCategory category;
  final String targetId;
  final String title;
  final String? validFromLabel;
  final String? planDate;
  final String? exemplar;
  final bool timesHidden;
  final String? weekBadge;
  final String? noticeHtml;
  final bool bookableInRumbs;
  final Uri? rumbsUrl;
  final List<String> roomTeachers;
  final List<TeacherTimetableContact> roomTeacherContacts;
  final List<TeacherTimetableReference> availableTargets;

  /// Weekday indices (0 = Monday .. 6 = Sunday), parallel to [days].
  final List<int> weekdayIndices;

  /// Period rows parsed from the first column of the plan table.
  final List<TimeTableRow> hours;

  /// Entries per weekday column, parallel to [weekdayIndices].
  final List<List<TeacherTimetableEntry>> days;

  TeacherTimetablePlan({
    required this.category,
    required this.targetId,
    required this.title,
    this.validFromLabel,
    this.planDate,
    this.exemplar,
    this.timesHidden = false,
    this.weekBadge,
    this.noticeHtml,
    this.bookableInRumbs = false,
    this.rumbsUrl,
    List<String> roomTeachers = const [],
    List<TeacherTimetableContact> roomTeacherContacts = const [],
    List<TeacherTimetableReference> availableTargets = const [],
    required List<int> weekdayIndices,
    required List<TimeTableRow> hours,
    required List<List<TeacherTimetableEntry>> days,
  }) : roomTeachers = List.unmodifiable(roomTeachers),
       roomTeacherContacts = List.unmodifiable(roomTeacherContacts),
       availableTargets = List.unmodifiable(availableTargets),
       weekdayIndices = List.unmodifiable(weekdayIndices),
       hours = List.unmodifiable(hours),
       days = List.unmodifiable(
         days.map((d) => List<TeacherTimetableEntry>.unmodifiable(d)),
       );

  bool get hasEmbeddedSubstitutions =>
      days.any((d) => d.any((e) => e.isEmbeddedSubstitution));

  bool get hasRoomBookings => days.any((d) => d.any((e) => e.isRoomBooking));

  bool get hasBreakSupervisions =>
      days.any((d) => d.any((e) => e.isBreakSupervision));

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'targetId': targetId,
    'title': title,
    if (validFromLabel != null) 'validFromLabel': validFromLabel,
    if (planDate != null) 'planDate': planDate,
    if (exemplar != null) 'exemplar': exemplar,
    'timesHidden': timesHidden,
    if (weekBadge != null) 'weekBadge': weekBadge,
    if (noticeHtml != null) 'noticeHtml': noticeHtml,
    'bookableInRumbs': bookableInRumbs,
    if (rumbsUrl != null) 'rumbsUrl': rumbsUrl.toString(),
    if (roomTeachers.isNotEmpty) 'roomTeachers': roomTeachers,
    if (roomTeacherContacts.isNotEmpty)
      'roomTeacherContacts': roomTeacherContacts
          .map((e) => e.toJson())
          .toList(),
    if (availableTargets.isNotEmpty)
      'availableTargets': availableTargets.map((e) => e.toJson()).toList(),
    'weekdayIndices': weekdayIndices,
    'hours': hours.map((h) => h.toJson()).toList(),
    'days': days.map((d) => d.map((e) => e.toJson()).toList()).toList(),
  };

  factory TeacherTimetablePlan.fromJson(Map<String, dynamic> json) =>
      TeacherTimetablePlan(
        category: TeacherTimetableCategory.values.byName(
          json['category'] as String,
        ),
        targetId: json['targetId'] as String,
        title: json['title'] as String,
        validFromLabel: json['validFromLabel'] as String?,
        planDate: json['planDate'] as String?,
        exemplar: json['exemplar'] as String?,
        timesHidden: json['timesHidden'] as bool? ?? false,
        weekBadge: json['weekBadge'] as String?,
        noticeHtml: json['noticeHtml'] as String?,
        bookableInRumbs: json['bookableInRumbs'] as bool? ?? false,
        rumbsUrl: json['rumbsUrl'] == null
            ? null
            : Uri.parse(json['rumbsUrl'] as String),
        roomTeachers: (json['roomTeachers'] as List? ?? const [])
            .cast<String>(),
        roomTeacherContacts: (json['roomTeacherContacts'] as List? ?? const [])
            .map(
              (e) =>
                  TeacherTimetableContact.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        availableTargets: (json['availableTargets'] as List? ?? const [])
            .map(
              (e) =>
                  TeacherTimetableReference.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        weekdayIndices: (json['weekdayIndices'] as List).cast<int>(),
        hours: (json['hours'] as List)
            .map((e) => TimeTableRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        days: (json['days'] as List)
            .map(
              (d) => (d as List)
                  .map(
                    (e) => TeacherTimetableEntry.fromJson(
                      e as Map<String, dynamic>,
                    ),
                  )
                  .toList(),
            )
            .toList(),
      );
}

/// Result of `stundenplan.php?a=freeRoom` (GET or POST).
class TeacherFreeRoomsResult {
  /// Selected weekday (1 = Monday .. 7 = Sunday).
  final int weekday;

  /// Selected period numbers (`stunde[]`).
  final List<int> selectedHours;

  /// All selectable period numbers offered by the form.
  final List<int> availableHours;

  /// Free rooms matching the query.
  final List<TeacherTimetableReference> rooms;

  TeacherFreeRoomsResult({
    required this.weekday,
    required List<int> selectedHours,
    required List<int> availableHours,
    required List<TeacherTimetableReference> rooms,
  }) : selectedHours = List.unmodifiable(selectedHours),
       availableHours = List.unmodifiable(availableHours),
       rooms = List.unmodifiable(rooms);

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'selectedHours': selectedHours,
    'availableHours': availableHours,
    'rooms': rooms.map((r) => r.toJson()).toList(),
  };

  factory TeacherFreeRoomsResult.fromJson(Map<String, dynamic> json) =>
      TeacherFreeRoomsResult(
        weekday: json['weekday'] as int,
        selectedHours: (json['selectedHours'] as List).cast<int>(),
        availableHours: (json['availableHours'] as List).cast<int>(),
        rooms: (json['rooms'] as List)
            .map(
              (e) =>
                  TeacherTimetableReference.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
}
