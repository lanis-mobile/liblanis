import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../applets/definition.dart';
import '../config.dart';
import '../connection/connection_checker.dart';
import '../exceptions.dart';
import '../models/account.dart';
import '../models/account_types.dart';
import 'cryptor.dart';

/// Authenticated SPH HTTP session for one account.
class LanisSession {
  final ClearTextAccount account;
  final LanisConfig config;
  final ConnectionChecker connectionChecker;

  late Cryptor cryptor = Cryptor();
  late CookieJar jar;
  final Dio dio = Dio();
  Timer? preventLogoutTimer;
  Future<void>? _authentication;

  Map<String, String> userData = {};
  AccountType? _accountType;
  List<dynamic> travelMenu = [];

  AccountType? get accountTypeOrNull => _accountType ?? account.accountType;

  AccountType get accountType => accountTypeOrNull!;

  LanisSession({
    required this.account,
    required this.config,
    required this.connectionChecker,
  });

  Future<void> prepareDio() async {
    jar = CookieJar();

    if (config.httpAdapter != null) {
      dio.httpClientAdapter = config.httpAdapter!;
    }
    dio.interceptors.add(CookieManager(jar));
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          if (response.data != null) {
            connectionChecker.status = ConnectionStatus.connected;
          } else {
            connectionChecker.status = ConnectionStatus.disconnected;
          }
          return handler.next(response);
        },
        onError: (error, handler) {
          if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout) {
            connectionChecker.status = ConnectionStatus.disconnected;
          }
          return handler.next(error);
        },
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          if (response.data is String) {
            final contentType = response.headers.value('content-type');
            if (contentType != null && contentType.contains('text/html')) {
              response.data = cryptor.decryptEncodedTags(response.data);
            }
          }
          return handler.next(response);
        },
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll({'User-Agent': config.userAgent});
          return handler.next(options);
        },
      ),
    );
    dio.options.followRedirects = false;
    dio.options.connectTimeout = const Duration(seconds: 8);
    dio.options.validateStatus = (status) =>
        status != null && (status == 200 || status == 302 || status == 503);
  }

  Future<void> authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    // Authentication changes the shared cookies and encryption key. Keep each
    // call intact, including its options, until the previous call has finished.
    while (_authentication != null) {
      try {
        await _authentication;
      } catch (_) {
        // A previous caller's failure must not prevent this caller from retrying.
      }
    }
    final authentication = _authenticate(
      withoutData: withoutData,
      withLoginUrl: withLoginUrl,
    );
    _authentication = authentication;
    try {
      await authentication;
    } on LanisException {
      rethrow;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw NoConnectionException();
      }
      throw UnknownException(e.message ?? e.toString());
    } finally {
      _authentication = null;
    }
  }

  Future<void> _authenticate({
    bool withoutData = false,
    String? withLoginUrl,
  }) async {
    if (!(await connectionChecker.connected)) {
      throw NoConnectionException();
    }

    jar.deleteAll();
    dio.options.validateStatus = (status) =>
        status != null && (status == 200 || status == 302 || status == 503);

    final downCheckResponse = await dio.get(
      'https://start.schulportal.hessen.de/',
    );
    if (downCheckResponse.statusCode == 503 ||
        downCheckResponse.data.toString().contains(
          'Der Bereich der pädagogischen Organisation steht Ihnen aktuell nicht zur Verfügung.',
        )) {
      throw LanisDownException();
    }

    final loginURL = withLoginUrl ?? await getLoginURL(account, config);
    await dio.get(loginURL);

    preventLogoutTimer?.cancel();
    preventLogoutTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => preventLogout(),
    );

    travelMenu = await getFastTravelMenu();
    if (!withoutData) {
      final response = await dio.get(
        'https://start.schulportal.hessen.de/benutzerverwaltung.php?a=userData',
      );
      userData = parseUserData(parse(response.data));
      _accountType = parseAccountType(parse(response.data));
    }

    await cryptor.initialize(dio);
  }

  Future<void> deAuthenticate() async {
    preventLogoutTimer?.cancel();
    try {
      await dio.get('https://start.schulportal.hessen.de/index.php?logout=all');
    } catch (_) {}
    jar.deleteAll();
  }

  static Future<String> getLoginURL(
    ClearTextAccount acc,
    LanisConfig config,
  ) async {
    final dioHttp = Dio();
    final cookieJar = CookieJar(ignoreExpires: true);
    if (config.httpAdapter != null) {
      dioHttp.httpClientAdapter = config.httpAdapter!;
    }

    try {
      dioHttp.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            response.headers.forEach((name, values) {
              if (name.toLowerCase() == 'set-cookie') {
                for (var i = 0; i < values.length; i++) {
                  values[i] = values[i].replaceAll('HttpOnly=1', 'HttpOnly');
                }
              }
            });
            return handler.next(response);
          },
        ),
      );
      dioHttp.interceptors.add(CookieManager(cookieJar));
      dioHttp.options.followRedirects = false;
      dioHttp.options.connectTimeout = const Duration(seconds: 8);
      dioHttp.options.receiveTimeout = const Duration(seconds: 8);
      dioHttp.options.validateStatus = (status) =>
          status != null && (status == 200 || status == 302 || status == 503);

      final response1 = await dioHttp.post(
        'https://login.schulportal.hessen.de/?i=${acc.schoolID}',
        data: {
          'user': '${acc.schoolID}.${acc.username}',
          'user2': acc.username,
          'password': acc.password,
        },
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          headers: {'User-Agent': config.userAgent},
        ),
      );

      if (response1.statusCode == 503) {
        throw LanisDownException();
      }

      final loginTimeout = parse(
        response1.data,
      ).getElementById('authErrorLocktime');

      if (response1.headers.value(HttpHeaders.locationHeader) != null) {
        final response2 = await dioHttp.get(
          'https://connect.schulportal.hessen.de',
        );
        return response2.headers.value(HttpHeaders.locationHeader) ?? '';
      } else if (loginTimeout != null) {
        throw LoginTimeoutException(
          loginTimeout.text,
          'Too many failed logins. Wait ${loginTimeout.text}s before retrying.',
        );
      } else {
        throw WrongCredentialsException();
      }
    } finally {
      _closeDioWithoutSharedAdapter(dioHttp, config.httpAdapter);
    }
  }

  Future<void> preventLogout() async {
    final uri = Uri.parse('https://start.schulportal.hessen.de/ajax_login.php');
    String sid;
    try {
      sid = (await jar.loadForRequest(
        uri,
      )).firstWhere((element) => element.name == 'sid').value;
    } on StateError {
      return;
    }
    try {
      final response = await dio.post(
        'https://start.schulportal.hessen.de/ajax_login.php',
        data: 'name=${Uri.encodeComponent(sid)}',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          headers: {'x-requested-with': 'XMLHttpRequest'},
        ),
      );
      if (response.statusCode == 503) {
        connectionChecker.status = ConnectionStatus.disconnected;
      }
    } on DioException {
      return;
    }
  }

  Future<List<dynamic>> getFastTravelMenu() async {
    final response = await dio.get(
      'https://start.schulportal.hessen.de/startseite.php?a=ajax&f=apps',
    );
    return jsonDecode(response.data.toString())['entrys'] as List<dynamic>;
  }

  Map<String, String> parseUserData(Document document) {
    final userDataTableBody = document.querySelector(
      'div.col-md-12 table.table.table-striped tbody',
    );

    if (userDataTableBody == null) return {};

    final result = <String, String>{};
    for (final row in userDataTableBody.querySelectorAll('tr')) {
      var key = row.children[0].text.trim();
      final value = row.children[1].text.trim();
      key = key.substring(0, key.length - 1).toLowerCase();
      result[key] = value;
    }
    return result;
  }

  AccountType parseAccountType(Document document) {
    final iconClassList = document
        .querySelector('.nav.navbar-nav.navbar-right>li>a>i')!
        .classes;
    if (iconClassList.contains('fa-child')) {
      return AccountType.student;
    } else if (iconClassList.contains('fa-user-circle')) {
      return AccountType.parent;
    } else if (iconClassList.contains('fa-user')) {
      return AccountType.teacher;
    }
    throw UnknownException('Unknown account type');
  }

  bool doesSupportFeature(
    AppletMeta applet, {
    AccountType? overrideAccountType,
  }) {
    final app = travelMenu
        .where((element) => element['link'].toString() == applet.appletPhpUrl)
        .singleOrNull;
    if (app == null) return false;
    return applet.supportedAccountTypes.contains(
      overrideAccountType ?? accountTypeOrNull ?? AccountType.student,
    );
  }

  Future<void> dispose() async {
    preventLogoutTimer?.cancel();
    _closeDioWithoutSharedAdapter(dio, config.httpAdapter);
  }

  /// [LanisConfig.httpAdapter] (e.g. Flutter Cronet) is shared across
  /// sessions. [Dio.close] closes the adapter — swap it out first.
  static void _closeDioWithoutSharedAdapter(
    Dio dio,
    HttpClientAdapter? shared,
  ) {
    if (shared != null && identical(dio.httpClientAdapter, shared)) {
      dio.httpClientAdapter = IOHttpClientAdapter();
    }
    dio.close(force: true);
  }
}
