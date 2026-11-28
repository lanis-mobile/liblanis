import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../../exceptions.dart';
import '../../models/timetable_parent.dart';
import '../../models/timetable_url.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import '../../cache/annotation.dart';
import '../../cache/types.dart';
import '../../cache/service.dart';
import 'parser.dart';

part 'parent_parser.g.dart';

/// Parent timetable overview and explicit loading of an individual child's plan.
class TimetableParentParser extends AppletParser<ParentTimetableHome>
    with _$TimetableParentParserCache {
  static final _base = Uri.parse('https://start.schulportal.hessen.de/');

  TimetableParentParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.timetable,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  CacheRequest<ParentTimetableHome> get homeCacheRequest =>
      TimetableParentParserCacheRequests.getHome();

  @override
  Future<MaybeCacheResult<ParentTimetableHome>> loadCachedHome({
    CacheReadPolicy? policy,
  }) => cached.getHome(cachePolicy: policy);

  @Cacheable(operation: 'timetable.parent.home', applet: Applets.timetable)
  Future<ParentTimetableHome> _getHome() => getHome();

  @Cacheable(operation: 'timetable.parent.plan', applet: Applets.timetable)
  Future<ParentTimetableLoaded> _getTimetable(
    ParentTimetableReference reference,
  ) => getTimetable(reference);

  @Cacheable(
    operation: 'timetable.parent.pupil_version',
    applet: Applets.timetable,
  )
  Future<ParentTimetableLoaded> _getTimetableForPupil(
    String pupilId,
    String date,
  ) {
    final trimmedPupil = pupilId.trim();
    if (trimmedPupil.isEmpty || trimmedPupil != pupilId) {
      throw ArgumentError.value(
        pupilId,
        'pupilId',
        'Must be non-empty and trimmed for cache key consistency',
      );
    }
    final trimmedDate = date.trim();
    if (trimmedDate.isEmpty || trimmedDate != date) {
      throw ArgumentError.value(
        date,
        'date',
        'Must be non-empty and trimmed for cache key consistency',
      );
    }
    return getTimetableForPupil(trimmedPupil, date: trimmedDate);
  }

  /// Cached entry point for a specific child's timetable version that
  /// normalizes [pupilId] and [date] before constructing the cache key.
  Future<MaybeCacheResult<ParentTimetableLoaded>> loadCachedTimetableForPupil(
    String pupilId,
    String date, {
    CacheReadPolicy? policy,
  }) {
    final trimmedPupil = pupilId.trim();
    if (trimmedPupil.isEmpty) {
      throw ArgumentError.value(pupilId, 'pupilId', 'Must not be empty');
    }
    final trimmedDate = date.trim();
    if (trimmedDate.isEmpty) {
      throw ArgumentError.value(date, 'date', 'Must not be empty');
    }
    return cached.getTimetableForPupil(
      trimmedPupil,
      trimmedDate,
      cachePolicy: policy,
    );
  }

  /// Return a selection, or follow the single-child redirect and load its plan.
  /// A selection takes one request. A redirected plan takes two.
  @override
  Future<ParentTimetableHome> getHome() async {
    try {
      final response = await ctx.session.dio.get(
        _base.resolve('stundenplan.php').toString(),
      );
      if (response.statusCode == 503) {
        throw LanisDownException();
      }
      if (response.statusCode == 302) {
        final location = response.headers.value('location');
        if (location == null || location.isEmpty) {
          throw UnknownException('Missing parent timetable redirect location');
        }
        final lower = location.toLowerCase();
        if (lower.contains('login') || lower.contains('index.php')) {
          throw UnauthorizedException(
            'Parent timetable overview: redirected to $location',
          );
        }
        return await _loadPlan(_planUrl(response.realUri.resolve(location)));
      }
      final document = parse(response.data);
      if (document.querySelector('#all tbody, #own tbody') != null) {
        return parseLoadedDocument(
          document,
          pupilId: _pupilId(response.realUri, document),
        );
      }
      return parseSelectionDocument(document);
    } catch (error, stack) {
      if (error is LanisException) rethrow;
      if (CacheService.isTransportFailure(error)) {
        Error.throwWithStackTrace(
          NetworkException.fromError(error, stack),
          stack,
        );
      }
      Error.throwWithStackTrace(
        UnknownException(
          'Parent timetable overview: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }

  static ParentTimetableSelection parseSelectionDocument(Document document) {
    try {
      final accordion = document.querySelector('#content #accordion');
      if (accordion == null) {
        throw UnknownException(
          'Missing parent timetable overview (#accordion)',
        );
      }
      final references = <ParentTimetableReference>[];
      for (final link in accordion.querySelectorAll(
        'a.list-group-item[href]',
      )) {
        final url = Uri.parse(link.attributes['href']!);
        final parameters = url.queryParameters;
        if (parameters['a'] != 'detail_klasse') continue;
        final pupilId = parameters['p'];
        if (pupilId == null || pupilId.isEmpty) {
          throw UnknownException('Missing pupil in parent timetable link');
        }
        final label = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final classStart = label.lastIndexOf(' (');
        if (classStart <= 0 || !label.endsWith(')')) {
          throw UnknownException(
            'Missing pupil name or class in parent timetable link',
          );
        }
        final reference = ParentTimetableReference(
          pupilId: pupilId,
          pupilName: label.substring(0, classStart).trim(),
          className: label.substring(classStart + 2, label.length - 1).trim(),
          url: url,
        );
        _referenceUrl(reference);
        references.add(reference);
      }
      return ParentTimetableSelection(timetables: references);
    } catch (error, stack) {
      if (error is LanisException) rethrow;
      if (CacheService.isTransportFailure(error)) {
        Error.throwWithStackTrace(
          NetworkException.fromError(error, stack),
          stack,
        );
      }
      Error.throwWithStackTrace(
        UnknownException(
          'Parent timetable overview: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }

  /// Load exactly the selected child's URL, retaining all portal parameters.
  Future<ParentTimetableLoaded> getTimetable(
    ParentTimetableReference reference,
  ) async => _loadPlan(_referenceUrl(reference));

  /// Load a specific child's timetable by [pupilId] and optional [date].
  ///
  /// Useful for single-child parent accounts (where [getHome] returned
  /// [ParentTimetableLoaded] directly without a [ParentTimetableReference])
  /// when switching between [TimeTable.availableVersions].
  Future<ParentTimetableLoaded> getTimetableForPupil(
    String pupilId, {
    String? date,
  }) async {
    final trimmedPupil = pupilId.trim();
    if (trimmedPupil.isEmpty) {
      throw ArgumentError.value(pupilId, 'pupilId', 'Must not be empty');
    }
    final trimmedDate = date?.trim();
    final hasDate = trimmedDate != null && trimmedDate.isNotEmpty;
    final uri = _base.replace(
      path: '/stundenplan.php',
      queryParameters: {
        'a': 'detail_klasse',
        'p': trimmedPupil,
        if (hasDate) 'date': trimmedDate,
      },
    );
    return _loadPlan(uri);
  }

  Future<ParentTimetableLoaded> _loadPlan(Uri url) async {
    try {
      final response = await ctx.session.dio.get(url.toString());
      final code = response.statusCode ?? 200;
      if (code == 503) {
        throw LanisDownException();
      }
      if (code >= 300 && code < 400) {
        final location = response.headers.value('location') ?? '';
        final lower = location.toLowerCase();
        if (lower.contains('login') || lower.contains('index.php')) {
          throw UnauthorizedException(
            'Parent timetable detail: redirected to $location',
          );
        }
        throw UnknownException(
          'Parent timetable detail: unexpected HTTP $code redirect',
        );
      }
      if (code < 200 || code >= 300) {
        throw UnknownException('Parent timetable detail: unexpected HTTP $code');
      }
      final loaded = parseLoadedDocument(
        parse(response.data),
        pupilId: url.queryParameters['p']!,
      );
      final requestedDate = TimetableUrlHelper.readDateParam(url);
      if (requestedDate != null &&
          loaded.timetable.planDate != null &&
          loaded.timetable.planDate != requestedDate) {
        throw UnknownException(
          'Requested parent timetable date "$requestedDate", but portal returned "${loaded.timetable.planDate}"',
        );
      }
      return loaded;
    } catch (error, stack) {
      if (error is LanisException) rethrow;
      if (CacheService.isTransportFailure(error)) {
        Error.throwWithStackTrace(
          NetworkException.fromError(error, stack),
          stack,
        );
      }
      Error.throwWithStackTrace(
        UnknownException(
          'Parent timetable detail: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }

  static ParentTimetableLoaded parseLoadedDocument(
    Document document, {
    required String pupilId,
  }) {
    if (pupilId.isEmpty) {
      throw UnknownException('Missing parent timetable pupil');
    }
    if (document.querySelector('#all tbody, #own tbody') == null) {
      throw UnknownException('Missing parent timetable table');
    }
    return ParentTimetableLoaded(
      pupilId: pupilId,
      pupilName: _pupilName(document, pupilId),
      timetable: TimetableStudentParser.parseDocumentHtml(document),
    );
  }

  static String? _pupilName(Document document, String pupilId) {
    for (final link in document.querySelectorAll('a[href]')) {
      final url = _base.resolve(link.attributes['href']!);
      if (url.path != '/stundenplan.php' ||
          url.queryParameters['a'] != 'detail_klasse' ||
          url.queryParameters['p'] != pupilId ||
          url.queryParameters.containsKey('pdf')) {
        continue;
      }
      final label = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final classStart = label.lastIndexOf(' (');
      if (classStart > 0 && label.endsWith(')')) {
        return label.substring(0, classStart).trim();
      }
    }
    return null;
  }

  static String _pupilId(Uri source, Document document) {
    final fromUrl = source.queryParameters['p'];
    if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
    // Some responses already contain the plan. Only use a child ID if the
    // timetable's own links identify exactly one child.
    final ids = <String>{};
    for (final link in document.querySelectorAll('#content a[href]')) {
      final uri = _base.resolve(link.attributes['href']!);
      if (uri.path == '/stundenplan.php' &&
          uri.queryParameters['a'] == 'detail_klasse') {
        final id = uri.queryParameters['p'];
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    if (ids.length != 1) {
      throw UnknownException('Cannot identify parent timetable pupil');
    }
    return ids.single;
  }

  static Uri _referenceUrl(ParentTimetableReference reference) {
    final url = _planUrl(_base.resolveUri(reference.url));
    if (url.queryParameters['p'] != reference.pupilId) {
      throw ConfigurationException(
        'Timetable reference requires a matching pupil',
      );
    }
    return url;
  }

  static Uri _planUrl(Uri url) {
    if (url.scheme != _base.scheme ||
        url.host != _base.host ||
        url.port != _base.port ||
        url.path != '/stundenplan.php' ||
        url.queryParameters['a'] != 'detail_klasse' ||
        (url.queryParameters['p']?.isEmpty ?? true)) {
      throw ConfigurationException(
        'Parent timetable URL requires a pupil and portal detail URL',
      );
    }
    return url;
  }

  @override
  ParentTimetableHome typeFromJson(String json) =>
      ParentTimetableHome.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
