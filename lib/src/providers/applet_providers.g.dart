// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'applet_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Builds only when [sessionProvider] has a ready [LanisSession].
/// Watches [activeAccountIdProvider] (not the full account) so accountType
/// [ActiveAccount.replace] does not recreate parsers.

@ProviderFor(appletContext)
const appletContextProvider = AppletContextProvider._();

/// Builds only when [sessionProvider] has a ready [LanisSession].
/// Watches [activeAccountIdProvider] (not the full account) so accountType
/// [ActiveAccount.replace] does not recreate parsers.

final class AppletContextProvider
    extends $FunctionalProvider<AppletContext, AppletContext, AppletContext>
    with $Provider<AppletContext> {
  /// Builds only when [sessionProvider] has a ready [LanisSession].
  /// Watches [activeAccountIdProvider] (not the full account) so accountType
  /// [ActiveAccount.replace] does not recreate parsers.
  const AppletContextProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appletContextProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appletContextHash();

  @$internal
  @override
  $ProviderElement<AppletContext> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppletContext create(Ref ref) {
    return appletContext(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppletContext value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppletContext>(value),
    );
  }
}

String _$appletContextHash() => r'f46766b33a3da3c9ed3bab77ba283e312ffded6f';

@ProviderFor(substitutionsParser)
const substitutionsParserProvider = SubstitutionsParserProvider._();

final class SubstitutionsParserProvider
    extends
        $FunctionalProvider<
          SubstitutionsParser,
          SubstitutionsParser,
          SubstitutionsParser
        >
    with $Provider<SubstitutionsParser> {
  const SubstitutionsParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'substitutionsParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$substitutionsParserHash();

  @$internal
  @override
  $ProviderElement<SubstitutionsParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SubstitutionsParser create(Ref ref) {
    return substitutionsParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SubstitutionsParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SubstitutionsParser>(value),
    );
  }
}

String _$substitutionsParserHash() =>
    r'd18734f963a79b44ed43c3f69f5a4592f2b8cecb';

@ProviderFor(timetableParser)
const timetableParserProvider = TimetableParserProvider._();

final class TimetableParserProvider
    extends
        $FunctionalProvider<
          TimetableStudentParser,
          TimetableStudentParser,
          TimetableStudentParser
        >
    with $Provider<TimetableStudentParser> {
  const TimetableParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timetableParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timetableParserHash();

  @$internal
  @override
  $ProviderElement<TimetableStudentParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TimetableStudentParser create(Ref ref) {
    return timetableParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TimetableStudentParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TimetableStudentParser>(value),
    );
  }
}

String _$timetableParserHash() => r'950c93a03b2fbe0a920bb7fd66073f1db1296bbf';

@ProviderFor(calendarParser)
const calendarParserProvider = CalendarParserProvider._();

final class CalendarParserProvider
    extends $FunctionalProvider<CalendarParser, CalendarParser, CalendarParser>
    with $Provider<CalendarParser> {
  const CalendarParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'calendarParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$calendarParserHash();

  @$internal
  @override
  $ProviderElement<CalendarParser> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CalendarParser create(Ref ref) {
    return calendarParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CalendarParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CalendarParser>(value),
    );
  }
}

String _$calendarParserHash() => r'4f504992f16f31e7075192df0d4e02d8a66979ea';

@ProviderFor(conversationsParser)
const conversationsParserProvider = ConversationsParserProvider._();

final class ConversationsParserProvider
    extends
        $FunctionalProvider<
          ConversationsParser,
          ConversationsParser,
          ConversationsParser
        >
    with $Provider<ConversationsParser> {
  const ConversationsParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conversationsParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conversationsParserHash();

  @$internal
  @override
  $ProviderElement<ConversationsParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConversationsParser create(Ref ref) {
    return conversationsParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationsParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationsParser>(value),
    );
  }
}

String _$conversationsParserHash() =>
    r'ffd16d58c82e86b499649b19e82d800e2b27a707';

@ProviderFor(lessonsStudentParser)
const lessonsStudentParserProvider = LessonsStudentParserProvider._();

final class LessonsStudentParserProvider
    extends
        $FunctionalProvider<
          LessonsStudentParser,
          LessonsStudentParser,
          LessonsStudentParser
        >
    with $Provider<LessonsStudentParser> {
  const LessonsStudentParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lessonsStudentParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lessonsStudentParserHash();

  @$internal
  @override
  $ProviderElement<LessonsStudentParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LessonsStudentParser create(Ref ref) {
    return lessonsStudentParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LessonsStudentParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LessonsStudentParser>(value),
    );
  }
}

String _$lessonsStudentParserHash() =>
    r'47dec66b6e12c0d8e459d9df8258aaa6ee738d74';

@ProviderFor(lessonsParentParser)
const lessonsParentParserProvider = LessonsParentParserProvider._();

final class LessonsParentParserProvider
    extends
        $FunctionalProvider<
          LessonsParentParser,
          LessonsParentParser,
          LessonsParentParser
        >
    with $Provider<LessonsParentParser> {
  const LessonsParentParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lessonsParentParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lessonsParentParserHash();

  @$internal
  @override
  $ProviderElement<LessonsParentParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LessonsParentParser create(Ref ref) {
    return lessonsParentParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LessonsParentParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LessonsParentParser>(value),
    );
  }
}

String _$lessonsParentParserHash() =>
    r'2699d74c7e95e59286a09167c326b58e001c13ba';

@ProviderFor(lessonsTeacherParser)
const lessonsTeacherParserProvider = LessonsTeacherParserProvider._();

final class LessonsTeacherParserProvider
    extends
        $FunctionalProvider<
          LessonsTeacherParser,
          LessonsTeacherParser,
          LessonsTeacherParser
        >
    with $Provider<LessonsTeacherParser> {
  const LessonsTeacherParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lessonsTeacherParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lessonsTeacherParserHash();

  @$internal
  @override
  $ProviderElement<LessonsTeacherParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LessonsTeacherParser create(Ref ref) {
    return lessonsTeacherParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LessonsTeacherParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LessonsTeacherParser>(value),
    );
  }
}

String _$lessonsTeacherParserHash() =>
    r'68fd992f1b5b6770ddcb717da65dfbed65a2348b';

@ProviderFor(dataStorageParser)
const dataStorageParserProvider = DataStorageParserProvider._();

final class DataStorageParserProvider
    extends
        $FunctionalProvider<
          DataStorageParser,
          DataStorageParser,
          DataStorageParser
        >
    with $Provider<DataStorageParser> {
  const DataStorageParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dataStorageParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dataStorageParserHash();

  @$internal
  @override
  $ProviderElement<DataStorageParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DataStorageParser create(Ref ref) {
    return dataStorageParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DataStorageParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DataStorageParser>(value),
    );
  }
}

String _$dataStorageParserHash() => r'e747fc2f4120f92cc11af0b7db9c728d06bde31d';

@ProviderFor(studyGroupsParser)
const studyGroupsParserProvider = StudyGroupsParserProvider._();

final class StudyGroupsParserProvider
    extends
        $FunctionalProvider<
          StudyGroupsStudentParser,
          StudyGroupsStudentParser,
          StudyGroupsStudentParser
        >
    with $Provider<StudyGroupsStudentParser> {
  const StudyGroupsParserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studyGroupsParserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studyGroupsParserHash();

  @$internal
  @override
  $ProviderElement<StudyGroupsStudentParser> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudyGroupsStudentParser create(Ref ref) {
    return studyGroupsParser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudyGroupsStudentParser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudyGroupsStudentParser>(value),
    );
  }
}

String _$studyGroupsParserHash() => r'2de96ddc09376d2ea33582f371e195539166f0d6';
