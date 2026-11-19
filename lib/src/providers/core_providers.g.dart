// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'core_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lanisConfig)
final lanisConfigProvider = LanisConfigProvider._();

final class LanisConfigProvider
    extends $FunctionalProvider<LanisConfig, LanisConfig, LanisConfig>
    with $Provider<LanisConfig> {
  LanisConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lanisConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lanisConfigHash();

  @$internal
  @override
  $ProviderElement<LanisConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LanisConfig create(Ref ref) {
    return lanisConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanisConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanisConfig>(value),
    );
  }
}

String _$lanisConfigHash() => r'665bf76b7088ff625b58f6b855051719d9fb7a8a';

@ProviderFor(lanisDatabase)
final lanisDatabaseProvider = LanisDatabaseProvider._();

final class LanisDatabaseProvider
    extends $FunctionalProvider<LanisDatabase, LanisDatabase, LanisDatabase>
    with $Provider<LanisDatabase> {
  LanisDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lanisDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lanisDatabaseHash();

  @$internal
  @override
  $ProviderElement<LanisDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LanisDatabase create(Ref ref) {
    return lanisDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanisDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanisDatabase>(value),
    );
  }
}

String _$lanisDatabaseHash() => r'abc0473bf5057e3193ce7ec94ceb489e64541f9a';

@ProviderFor(connectionChecker)
final connectionCheckerProvider = ConnectionCheckerProvider._();

final class ConnectionCheckerProvider
    extends
        $FunctionalProvider<
          ConnectionChecker,
          ConnectionChecker,
          ConnectionChecker
        >
    with $Provider<ConnectionChecker> {
  ConnectionCheckerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionCheckerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionCheckerHash();

  @$internal
  @override
  $ProviderElement<ConnectionChecker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectionChecker create(Ref ref) {
    return connectionChecker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionChecker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionChecker>(value),
    );
  }
}

String _$connectionCheckerHash() => r'9eea29957861b0fef35e88fd51eeb49c96156451';

@ProviderFor(connectionStatus)
final connectionStatusProvider = ConnectionStatusProvider._();

final class ConnectionStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionStatus>,
          ConnectionStatus,
          Stream<ConnectionStatus>
        >
    with $FutureModifier<ConnectionStatus>, $StreamProvider<ConnectionStatus> {
  ConnectionStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionStatusHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionStatus> create(Ref ref) {
    return connectionStatus(ref);
  }
}

String _$connectionStatusHash() => r'd5e2383da9553faa3b8db642e81da9d846ac56ce';

@ProviderFor(Accounts)
final accountsProvider = AccountsProvider._();

final class AccountsProvider
    extends $AsyncNotifierProvider<Accounts, List<AccountSummary>> {
  AccountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountsHash();

  @$internal
  @override
  Accounts create() => Accounts();
}

String _$accountsHash() => r'476aa21a4818d56dd1daffbcbf4ef2e465fdc8c0';

abstract class _$Accounts extends $AsyncNotifier<List<AccountSummary>> {
  FutureOr<List<AccountSummary>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<AccountSummary>>, List<AccountSummary>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AccountSummary>>,
                List<AccountSummary>
              >,
              AsyncValue<List<AccountSummary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.

@ProviderFor(ActiveAccountId)
final activeAccountIdProvider = ActiveAccountIdProvider._();

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.
final class ActiveAccountIdProvider
    extends $NotifierProvider<ActiveAccountId, int?> {
  /// Identity of the active account. [Session] watches this (not the full
  /// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.
  ActiveAccountIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeAccountIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeAccountIdHash();

  @$internal
  @override
  ActiveAccountId create() => ActiveAccountId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$activeAccountIdHash() => r'8010b04405e01d08389999c6a262d7708d89180b';

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.

abstract class _$ActiveAccountId extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ActiveAccount)
final activeAccountProvider = ActiveAccountProvider._();

final class ActiveAccountProvider
    extends $NotifierProvider<ActiveAccount, ClearTextAccount?> {
  ActiveAccountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeAccountProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeAccountHash();

  @$internal
  @override
  ActiveAccount create() => ActiveAccount();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClearTextAccount? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClearTextAccount?>(value),
    );
  }
}

String _$activeAccountHash() => r'4ee5f6247507a488e3738a9fe3cd43128ebb4797';

abstract class _$ActiveAccount extends $Notifier<ClearTextAccount?> {
  ClearTextAccount? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClearTextAccount?, ClearTextAccount?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClearTextAccount?, ClearTextAccount?>,
              ClearTextAccount?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Session)
final sessionProvider = SessionProvider._();

final class SessionProvider
    extends $AsyncNotifierProvider<Session, LanisSession?> {
  SessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionHash();

  @$internal
  @override
  Session create() => Session();
}

String _$sessionHash() => r'741efdfbcd2a2f37b8f58f9ed40b65ef71c1f4cd';

abstract class _$Session extends $AsyncNotifier<LanisSession?> {
  FutureOr<LanisSession?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<LanisSession?>, LanisSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<LanisSession?>, LanisSession?>,
              AsyncValue<LanisSession?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(sharedOverAccountSettings)
final sharedOverAccountSettingsProvider = SharedOverAccountSettingsProvider._();

final class SharedOverAccountSettingsProvider
    extends $FunctionalProvider<TypedSettings, TypedSettings, TypedSettings>
    with $Provider<TypedSettings> {
  SharedOverAccountSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sharedOverAccountSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sharedOverAccountSettingsHash();

  @$internal
  @override
  $ProviderElement<TypedSettings> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TypedSettings create(Ref ref) {
    return sharedOverAccountSettings(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TypedSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TypedSettings>(value),
    );
  }
}

String _$sharedOverAccountSettingsHash() =>
    r'21a0615830a1f7e00765e02c10f42a1fa27ec910';

@ProviderFor(accountSpecificSettings)
final accountSpecificSettingsProvider = AccountSpecificSettingsProvider._();

final class AccountSpecificSettingsProvider
    extends $FunctionalProvider<TypedSettings?, TypedSettings?, TypedSettings?>
    with $Provider<TypedSettings?> {
  AccountSpecificSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountSpecificSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountSpecificSettingsHash();

  @$internal
  @override
  $ProviderElement<TypedSettings?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TypedSettings? create(Ref ref) {
    return accountSpecificSettings(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TypedSettings? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TypedSettings?>(value),
    );
  }
}

String _$accountSpecificSettingsHash() =>
    r'2d45be0868664822fc72e1c92af6f22327522a26';

@ProviderFor(storageManager)
final storageManagerProvider = StorageManagerProvider._();

final class StorageManagerProvider
    extends
        $FunctionalProvider<StorageManager?, StorageManager?, StorageManager?>
    with $Provider<StorageManager?> {
  StorageManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageManagerHash();

  @$internal
  @override
  $ProviderElement<StorageManager?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StorageManager? create(Ref ref) {
    return storageManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StorageManager? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StorageManager?>(value),
    );
  }
}

String _$storageManagerHash() => r'0c7a22ab7ce89a1b86173d3d6a1dc7d1776dece9';

/// Bumped after [Session.authenticate] mutates travelMenu in place so
/// [supportedAppletPhpUrls] refreshes without invalidating mid-rebuild.

@ProviderFor(SessionFeatureEpoch)
final sessionFeatureEpochProvider = SessionFeatureEpochProvider._();

/// Bumped after [Session.authenticate] mutates travelMenu in place so
/// [supportedAppletPhpUrls] refreshes without invalidating mid-rebuild.
final class SessionFeatureEpochProvider
    extends $NotifierProvider<SessionFeatureEpoch, int> {
  /// Bumped after [Session.authenticate] mutates travelMenu in place so
  /// [supportedAppletPhpUrls] refreshes without invalidating mid-rebuild.
  SessionFeatureEpochProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionFeatureEpochProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionFeatureEpochHash();

  @$internal
  @override
  SessionFeatureEpoch create() => SessionFeatureEpoch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$sessionFeatureEpochHash() =>
    r'05e5f29fa0e306c557a665a26e2585627f3c91fa';

/// Bumped after [Session.authenticate] mutates travelMenu in place so
/// [supportedAppletPhpUrls] refreshes without invalidating mid-rebuild.

abstract class _$SessionFeatureEpoch extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// PHP applet URLs supported by the current authenticated session + account type.

@ProviderFor(supportedAppletPhpUrls)
final supportedAppletPhpUrlsProvider = SupportedAppletPhpUrlsProvider._();

/// PHP applet URLs supported by the current authenticated session + account type.

final class SupportedAppletPhpUrlsProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// PHP applet URLs supported by the current authenticated session + account type.
  SupportedAppletPhpUrlsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'supportedAppletPhpUrlsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$supportedAppletPhpUrlsHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return supportedAppletPhpUrls(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$supportedAppletPhpUrlsHash() =>
    r'389c1df8e74ea31855f6d453c271db4ba61e639a';
