import 'timetable.dart';
import 'timetable_url.dart';

/// The parent portal either offers a choice or opens one child's plan.
sealed class ParentTimetableHome {
  const ParentTimetableHome();

  Map<String, dynamic> toJson();

  factory ParentTimetableHome.fromJson(
    Map<String, dynamic> json,
  ) => switch (json['type']) {
    'selection' => ParentTimetableSelection(
      timetables: (json['timetables'] as List)
          .map(
            (item) =>
                ParentTimetableReference.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    ),
    'loaded' => ParentTimetableLoaded(
      pupilId: json['pupilId'] as String,
      pupilName: json['pupilName'] as String?,
      timetable: TimeTable.fromJson(json['timetable'] as Map<String, dynamic>),
    ),
    _ => throw FormatException('Unknown parent timetable result type'),
  };
}

/// Available children. No child timetable has been requested yet.
final class ParentTimetableSelection extends ParentTimetableHome {
  final List<ParentTimetableReference> timetables;

  ParentTimetableSelection({required List<ParentTimetableReference> timetables})
    : timetables = List.unmodifiable(timetables);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'selection',
    'timetables': timetables.map((reference) => reference.toJson()).toList(),
  };
}

/// A parsed plan with the identity of the child it belongs to.
final class ParentTimetableLoaded extends ParentTimetableHome {
  final String pupilId;
  final TimeTable timetable;
  final String? pupilName;

  const ParentTimetableLoaded({
    required this.pupilId,
    required this.timetable,
    this.pupilName,
  });

  factory ParentTimetableLoaded.fromJson(Map<String, dynamic> json) =>
      ParentTimetableHome.fromJson(json) as ParentTimetableLoaded;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'loaded',
    if (pupilName != null) 'pupilName': pupilName,
    'pupilId': pupilId,
    'timetable': timetable.toJson(),
  };
}

/// A child's timetable, loaded only when explicitly requested.
class ParentTimetableReference {
  final String pupilId;
  final String pupilName;
  final String className;
  final Uri url;

  const ParentTimetableReference({
    required this.pupilId,
    required this.pupilName,
    required this.className,
    required this.url,
  });

  /// The `date` query parameter encoded in [url], if any.
  String? get date => TimetableUrlHelper.readDateParam(url);

  /// Returns a copy of this reference targeting [date] (or removing `date`
  /// when null/blank), suitable for passing to `getTimetable` / `cached.getTimetable`.
  ParentTimetableReference withDate(String? date) => ParentTimetableReference(
    pupilId: pupilId,
    pupilName: pupilName,
    className: className,
    url: TimetableUrlHelper.withDateParam(url, date),
  );

  Map<String, dynamic> toJson() => {
    'pupilId': pupilId,
    'pupilName': pupilName,
    'className': className,
    'url': url.toString(),
  };

  factory ParentTimetableReference.fromJson(Map<String, dynamic> json) =>
      ParentTimetableReference(
        pupilId: json['pupilId'] as String,
        pupilName: json['pupilName'] as String,
        className: json['className'] as String,
        url: Uri.parse(json['url'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is ParentTimetableReference &&
      pupilId == other.pupilId &&
      pupilName == other.pupilName &&
      className == other.className &&
      url == other.url;

  @override
  int get hashCode => Object.hash(pupilId, pupilName, className, url);
}
