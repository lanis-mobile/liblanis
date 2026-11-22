/// Whether [error] should be forwarded to [LanisConfig.onUnexpectedError].
///
/// True for [UnknownException] and any non-[LanisException] (parse/runtime
/// crashes). Typed SPH/client exceptions (network, auth, offline, …) are
/// expected and not reported.
bool isUnexpectedParserError(Object error) =>
    error is UnknownException || error is! LanisException;

/// Base exception for SPH / Lanis client errors.
///
/// Messages are static English only. Host apps should map types to l10n.
abstract class LanisException implements Exception {
  final String? _customCause;

  LanisException([this._customCause]);

  String get defaultMessage;

  String get cause => _customCause ?? defaultMessage;

  @override
  String toString() => cause;
}

class WrongCredentialsException extends LanisException {
  WrongCredentialsException([super.cause]);

  @override
  String get defaultMessage => 'Wrong credentials';
}

class ParentAccountWithoutLearnersException extends LanisException {
  @override
  String get defaultMessage => 'No learners are linked to this parent account.';
}

class AccountDisabledException extends LanisException {
  @override
  String get defaultMessage =>
      'This account has been disabled by the issuing school.';
}

class PasswordChangeRequiredException extends LanisException {
  @override
  String get defaultMessage =>
      'Change your password in Schulportal Hessen before logging in.';
}

class LanisDownException extends LanisException {
  LanisDownException([super.cause]);

  @override
  String get defaultMessage => 'Lanis is down';
}

class LoginTimeoutException extends LanisException {
  final String time;

  LoginTimeoutException(this.time, [String? cause]) : super(cause);

  @override
  String get defaultMessage => 'Login timeout: $time';
}

class CredentialsIncompleteException extends LanisException {
  CredentialsIncompleteException([super.cause]);

  @override
  String get defaultMessage => 'Credentials incomplete';
}

class NetworkException extends LanisException {
  final Object? originalError;
  final StackTrace? originalStack;

  NetworkException([super.cause]) : originalError = null, originalStack = null;

  NetworkException.fromError(Object error, StackTrace stack)
    : originalError = error,
      originalStack = stack,
      super('${error.runtimeType}: $error');

  @override
  String get defaultMessage => 'Network error';
}

class UnknownException extends LanisException {
  UnknownException([super.cause]);

  @override
  String get defaultMessage => 'Unknown error';
}

class UnauthorizedException extends LanisException {
  UnauthorizedException([super.cause]);

  @override
  String get defaultMessage => 'Unauthorized';
}

class EncryptionCheckFailedException extends LanisException {
  EncryptionCheckFailedException([super.cause]);

  @override
  String get defaultMessage => 'Encryption check failed';
}

class UnsaltedOrUnknownException extends LanisException {
  UnsaltedOrUnknownException([super.cause]);

  @override
  String get defaultMessage => 'Unsalted or unknown';
}

class NotSupportedException extends LanisException {
  NotSupportedException([super.cause]);

  @override
  String get defaultMessage => 'Not supported';
}

class NoConnectionException extends LanisException {
  NoConnectionException([super.cause]);

  @override
  String get defaultMessage => 'No connection';
}

class AccountAlreadyExistsException extends LanisException {
  AccountAlreadyExistsException([super.cause]);

  @override
  String get defaultMessage => 'Account already exists';
}

class ConfigurationException extends LanisException {
  ConfigurationException([super.cause]);

  @override
  String get defaultMessage => 'Invalid LanisClient configuration';
}

class StorageNotConfiguredException extends LanisException {
  StorageNotConfiguredException([super.cause]);

  @override
  String get defaultMessage =>
      'Document cache directory is required to use downloads';
}
