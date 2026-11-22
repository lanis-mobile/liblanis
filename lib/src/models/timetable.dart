import 'time_of_day.dart';

enum TimetableWeekParity { even, odd }

class TimetableSubject {
  // The ID is not nullable, to support legacy data where the ID was not present
  String? id;
  String? name;
  String? raum;
  String? lehrer;
  String? badge;

  /// Optional ISO calendar-week recurrence, independent of school week badges.
  TimetableWeekParity? calendarWeekParity;
  int duration;
  SphTimeOfDay startTime;
  SphTimeOfDay endTime;
  // Row index in the timetable
  int? stunde;

  TimetableSubject({
    required this.id,
    required this.name,
    required this.raum,
    required this.lehrer,
    required this.badge,
    this.calendarWeekParity,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.stunde,
  });

  @override
  String toString() {
    return '(Id: $id, Fach: $name, Raum: $raum, Lehrer: $lehrer, Badge: $badge, Dauer: $duration (${startTime.hour}:${startTime.minute}-${endTime.hour}:${endTime.minute}))';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'raum': raum,
      'lehrer': lehrer,
      'badge': badge,
      if (calendarWeekParity != null)
        'calendarWeekParity': calendarWeekParity!.name,
      'duration': duration,
      'startTime': [startTime.hour, startTime.minute],
      'endTime': [endTime.hour, endTime.minute],
      'stunde': stunde,
    };
  }

  factory TimetableSubject.fromJson(Map<String, dynamic> json) {
    return TimetableSubject(
      id: json['id'],
      name: json['name'],
      raum: json['raum'],
      lehrer: json['lehrer'],
      badge: json['badge'],
      calendarWeekParity: json['calendarWeekParity'] == null
          ? null
          : TimetableWeekParity.values.byName(json['calendarWeekParity']),
      duration: json['duration'],
      stunde: json['stunde'],
      startTime: SphTimeOfDay(
        hour: json['startTime'][0],
        minute: json['startTime'][1],
      ),
      endTime: SphTimeOfDay(
        hour: json['endTime'][0],
        minute: json['endTime'][1],
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is TimetableSubject) {
      return id == other.id &&
          name == other.name &&
          raum == other.raum &&
          lehrer == other.lehrer &&
          badge == other.badge &&
          calendarWeekParity == other.calendarWeekParity &&
          duration == other.duration &&
          stunde == other.stunde &&
          startTime == other.startTime &&
          endTime == other.endTime;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    raum,
    lehrer,
    badge,
    calendarWeekParity,
    duration,
    stunde,
    startTime,
    endTime,
  );
}

typedef TimetableDay = List<TimetableSubject>;

/// Week plan container. Naming stays `TimeTable` (not `Timetable`) to avoid a
/// wide rename across app + package; new types should use the `Timetable*` prefix.
enum TimeTableType { all, own }

class TimeTable {
  List<TimetableDay>? planForAll;
  List<TimetableDay>? planForOwn;
  List<TimeTableRow>? hours;
  String? weekBadge;

  TimeTable({this.planForAll, this.planForOwn, this.weekBadge, this.hours});

  TimeTable.fromJson(Map<String, dynamic> json) {
    planForAll = (json['planForAll'] as List?)
        ?.map(
          (day) => (day as List)
              .map(
                (fach) =>
                    TimetableSubject.fromJson(fach as Map<String, dynamic>),
              )
              .toList(),
        )
        .toList();
    planForOwn = (json['planForOwn'] as List?)
        ?.map(
          (day) => (day as List)
              .map(
                (fach) =>
                    TimetableSubject.fromJson(fach as Map<String, dynamic>),
              )
              .toList(),
        )
        .toList();
    hours = (json['hours'] as List?)
        ?.map((hour) => TimeTableRow.fromJson(hour as Map<String, dynamic>))
        .toList();
    weekBadge = json['weekBadge'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['planForAll'] = planForAll
        ?.map((day) => day.map((fach) => fach.toJson()).toList())
        .toList();
    data['planForOwn'] = planForOwn
        ?.map((day) => day.map((fach) => fach.toJson()).toList())
        .toList();
    data['hours'] = hours?.map((hour) => hour.toJson()).toList();
    data['weekBadge'] = weekBadge;
    return data;
  }
}

class TimeTableRow {
  final TimeTableRowType type;
  final SphTimeOfDay startTime;
  final SphTimeOfDay endTime;
  final String label;
  final int lessonIndex;

  TimeTableRow(
    this.type,
    this.startTime,
    this.endTime,
    this.label,
    this.lessonIndex,
  );

  @override
  String toString() {
    return 'TimeTableRow{type: $type, startTime: $startTime, endTime: $endTime, label: $label}';
  }

  @override
  bool operator ==(Object other) {
    if (other is TimeTableRow) {
      return type == other.type &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          lessonIndex == other.lessonIndex &&
          label == other.label;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(type, startTime, endTime, lessonIndex, label);

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
      'endTime': {'hour': endTime.hour, 'minute': endTime.minute},
      'label': label,
      'lessonIndex': lessonIndex,
    };
  }

  factory TimeTableRow.fromJson(Map<String, dynamic> json) {
    TimeTableRowType rowType = json['type'] == 'TimeTableRowType.lesson'
        ? TimeTableRowType.lesson
        : TimeTableRowType.pause;
    SphTimeOfDay start = SphTimeOfDay(
      hour: json['startTime']['hour'],
      minute: json['startTime']['minute'],
    );
    SphTimeOfDay end = SphTimeOfDay(
      hour: json['endTime']['hour'],
      minute: json['endTime']['minute'],
    );
    return TimeTableRow(
      rowType,
      start,
      end,
      json['label'],
      json['lessonIndex'],
    );
  }
}

class TimeTableData {
  final List<TimeTableRow> hours = [];
  late final String? weekBadge;
  List<TimetableDay> timetableDays = [];

  bool isCurrentWeek(TimetableSubject lesson, bool sameWeek) {
    return (weekBadge == null ||
            weekBadge == '' ||
            lesson.badge == null ||
            lesson.badge == '')
        ? true
        : sameWeek
        ? (weekBadge == lesson.badge)
        : (weekBadge != lesson.badge);
  }

  TimeTableData(
    List<TimetableDay> data,
    TimeTable timetable,
    Map<String, dynamic> settings,
    this.weekBadge,
  ) {
    final schoolHours = timetable.hours ?? const <TimeTableRow>[];
    for (var (index, hour) in schoolHours.indexed) {
      if (index > 0 && schoolHours[index - 1].endTime != hour.startTime) {
        if (schoolHours[index - 1].endTime.differenceInMinutes(hour.startTime) >
            10) {
          hours.add(
            TimeTableRow(
              TimeTableRowType.pause,
              schoolHours[index - 1].endTime,
              hour.startTime,
              'Pause',
              -1,
            ),
          );
        }
      }
      hours.add(hour);
    }

    List<dynamic>? hiddenLessons = settings['hidden-lessons'];
    for (var day in data) {
      List<TimetableSubject> dayData = [];
      for (var subject in day) {
        if (isCurrentWeek(subject, true) &&
            (hiddenLessons == null || !hiddenLessons.contains(subject.id))) {
          dayData.add(subject);
        }
      }
      timetableDays.add(dayData);
    }

    timetableDays = timetableDays
        .where((TimetableDay day) => day.isNotEmpty)
        .toList();
  }
}

enum TimeTableRowType { lesson, pause }
