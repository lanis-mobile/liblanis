import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:uuid/uuid.dart';

import '../../cache/annotation.dart';
import '../../cache/service.dart';
import '../../cache/types.dart';
import '../../exceptions.dart';
import '../../models/time_of_day.dart';
import '../../models/timetable.dart';
import '../../models/timetable_teacher.dart';
import '../../models/timetable_url.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import 'version_parser.dart';

part 'teacher_parser.g.dart';

/// Teacher `stundenplan.php` parser supporting:
/// - Overview of teachers, classes, rooms, and break supervisions ("Pausenaufsichten")
/// - Plan lookup by teacher (`detail`), class (`detail_klasse`), room (`detail_raum`),
///   and break supervision location (`detail_pause`)
/// - Embedded substitutions (`vplanEinbettung`) and Räume & Medien (`rumbsButton`/`rumbsBuchungen`)
/// - Free room search (`a=freeRoom`)
class TimetableTeacherParser extends AppletParser<TeacherTimetableOverview>
    with _$TimetableTeacherParserCache {
  static final Uri _base = Uri.parse('https://start.schulportal.hessen.de/');

  static const _weekdayNames = <String, int>{
    'montag': 0,
    'dienstag': 1,
    'mittwoch': 2,
    'donnerstag': 3,
    'freitag': 4,
    'samstag': 5,
    'sonntag': 6,
  };

  TimetableTeacherParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.timetable,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  CacheRequest<TeacherTimetableOverview> get homeCacheRequest =>
      TimetableTeacherParserCacheRequests.getHome();

  @override
  Future<MaybeCacheResult<TeacherTimetableOverview>> loadCachedHome({
    CacheReadPolicy? policy,
  }) => cached.getHome(cachePolicy: policy);

  @Cacheable(operation: 'timetable.teacher.home', applet: Applets.timetable)
  Future<TeacherTimetableOverview> _getHome() => getHome();

  @Cacheable(operation: 'timetable.teacher.plan', applet: Applets.timetable)
  Future<TeacherTimetablePlan> _getTimetable(
    TeacherTimetableReference reference,
  ) => getTimetable(reference);

  @override
  Future<TeacherTimetableOverview> getHome() async {
    try {
      final response = await ctx.session.dio.get(
        _base.resolve('stundenplan.php').toString(),
      );
      _assertOkResponse(response, 'Teacher timetable overview');
      return parseOverviewDocument(parse(response.data));
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
          'Teacher timetable overview: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }

  /// Load a plan using a [TeacherTimetableReference] from [getHome] or [TeacherTimetablePlan.availableTargets].
  Future<TeacherTimetablePlan> getTimetable(
    TeacherTimetableReference reference,
  ) async {
    final uri = _validatePortalUrl(
      _base.resolveUri(reference.url),
      category: reference.category,
    );
    return _fetchPlan(uri, reference.category, reference.id);
  }

  /// Load the logged-in teacher's own timetable (`a=detail` without `t`).
  Future<TeacherTimetablePlan> getOwnTimetable({
    String? date,
    String? exemplar,
  }) {
    final uri = _buildDetailUri(
      action: 'detail',
      date: date,
      exemplar: exemplar,
    );
    return _fetchPlan(uri, TeacherTimetableCategory.teacher, '');
  }

  /// Load a teacher's timetable by teacher code (`a=detail&t=<teacherCode>`).
  ///
  /// Throws [UnauthorizedException] if the school restricts `teacherCanSee=own`
  /// and [teacherCode] belongs to another teacher.
  Future<TeacherTimetablePlan> getTeacherTimetable(
    String teacherCode, {
    String? date,
    String? exemplar,
  }) {
    final uri = _buildDetailUri(
      action: 'detail',
      paramName: 't',
      paramValue: teacherCode,
      date: date,
      exemplar: exemplar,
    );
    return _fetchPlan(uri, TeacherTimetableCategory.teacher, teacherCode);
  }

  /// Load a class/course timetable by class name (`a=detail_klasse&k=<className>`).
  Future<TeacherTimetablePlan> getClassTimetable(
    String className, {
    String? date,
    String? exemplar,
  }) {
    final uri = _buildDetailUri(
      action: 'detail_klasse',
      paramName: 'k',
      paramValue: className,
      date: date,
      exemplar: exemplar,
    );
    return _fetchPlan(uri, TeacherTimetableCategory.schoolClass, className);
  }

  /// Load a room timetable by room name (`a=detail_raum&r=<roomName>`).
  Future<TeacherTimetablePlan> getRoomTimetable(
    String roomName, {
    String? date,
    String? exemplar,
  }) {
    final uri = _buildDetailUri(
      action: 'detail_raum',
      paramName: 'r',
      paramValue: roomName,
      date: date,
      exemplar: exemplar,
    );
    return _fetchPlan(uri, TeacherTimetableCategory.room, roomName);
  }

  /// Load a break supervision ("Pausenaufsicht") timetable by location (`a=detail_pause&p=<location>`).
  Future<TeacherTimetablePlan> getBreakSupervisionTimetable(
    String location, {
    String? date,
    String? exemplar,
  }) {
    final uri = _buildDetailUri(
      action: 'detail_pause',
      paramName: 'p',
      paramValue: location,
      date: date,
      exemplar: exemplar,
    );
    return _fetchPlan(uri, TeacherTimetableCategory.breakSupervision, location);
  }

  /// Search for free rooms (`stundenplan.php?a=freeRoom`).
  ///
  /// When [weekday] (1 = Monday .. 7 = Sunday) and [hours] are omitted,
  /// performs a GET request and returns the portal's default selection.
  /// When provided, submits a POST request for that weekday and period set.
  Future<TeacherFreeRoomsResult> getFreeRooms({
    int? weekday,
    List<int>? hours,
  }) async {
    if (weekday != null) {
      RangeError.checkValueInInterval(weekday, 1, 7, 'weekday');
    }
    try {
      final url = _base.resolve('stundenplan.php?a=freeRoom').toString();
      final Response<dynamic> response;
      if (weekday == null && (hours == null || hours.isEmpty)) {
        response = await ctx.session.dio.get(url);
      } else {
        final effectiveWeekday = weekday ?? DateTime.now().weekday;
        final parts = <String>[
          'tag=$effectiveWeekday',
          for (final h in hours ?? const <int>[]) 'stunde%5B%5D=$h',
        ];
        response = await ctx.session.dio.post(
          url,
          data: parts.join('&'),
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      }
      _assertOkResponse(response, 'Teacher free rooms');
      return parseFreeRoomsDocument(parse(response.data));
    } catch (error, stack) {
      if (error is LanisException) rethrow;
      if (CacheService.isTransportFailure(error)) {
        Error.throwWithStackTrace(
          NetworkException.fromError(error, stack),
          stack,
        );
      }
      Error.throwWithStackTrace(
        UnknownException('Teacher free rooms: ${error.runtimeType}: $error'),
        stack,
      );
    }
  }

  Future<TeacherTimetablePlan> _fetchPlan(
    Uri uri,
    TeacherTimetableCategory category,
    String targetId,
  ) async {
    try {
      final response = await ctx.session.dio.getUri(uri);
      _assertOkResponse(response, 'Teacher timetable detail');
      final plan = parsePlanDocument(
        parse(response.data),
        category: category,
        targetId: targetId,
      );
      final requestedDate = TimetableUrlHelper.readDateParam(uri);
      if (requestedDate != null &&
          plan.planDate != null &&
          plan.planDate != requestedDate) {
        throw UnknownException(
          'Requested teacher timetable date "$requestedDate", but portal returned "${plan.planDate}"',
        );
      }
      return plan;
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
          'Teacher timetable detail: ${error.runtimeType}: $error',
        ),
        stack,
      );
    }
  }

  static void _assertOkResponse(Response<dynamic> response, String context) {
    final code = response.statusCode ?? 200;
    if (code >= 300 && code < 400) {
      final location = response.headers.value('location') ?? '';
      if (location.toLowerCase().contains('login') ||
          location.toLowerCase().contains('index.php')) {
        throw UnauthorizedException('$context: redirected to $location');
      }
      throw UnknownException('$context: unexpected HTTP $code redirect');
    }
    if (code == 503) {
      throw LanisDownException();
    }
    if (code < 200 || code >= 300) {
      throw UnknownException('$context: unexpected HTTP $code');
    }
  }

  static Uri _buildDetailUri({
    required String action,
    String? paramName,
    String? paramValue,
    String? date,
    String? exemplar,
  }) {
    final trimmedExemplar = exemplar?.trim();
    final trimmedDate = date?.trim();
    final query = <String, String>{
      if (trimmedExemplar != null && trimmedExemplar.isNotEmpty)
        'e': trimmedExemplar,
      'a': action,
      if (paramName != null && paramValue != null) paramName: paramValue,
      if (trimmedDate != null && trimmedDate.isNotEmpty) 'date': trimmedDate,
    };
    return _base.replace(path: '/stundenplan.php', queryParameters: query);
  }

  static String _expectedAction(TeacherTimetableCategory category) =>
      switch (category) {
        TeacherTimetableCategory.teacher => 'detail',
        TeacherTimetableCategory.schoolClass => 'detail_klasse',
        TeacherTimetableCategory.room => 'detail_raum',
        TeacherTimetableCategory.breakSupervision => 'detail_pause',
      };

  static Uri _validatePortalUrl(
    Uri url, {
    TeacherTimetableCategory? category,
  }) {
    if (url.scheme != _base.scheme ||
        url.host != _base.host ||
        url.port != _base.port ||
        url.path != '/stundenplan.php') {
      throw ConfigurationException(
        'Teacher timetable URL must stay on ${_base.origin}/stundenplan.php',
      );
    }
    final params = _safeQueryParameters(url);
    if (params.containsKey('pdf')) {
      throw ConfigurationException(
        'Teacher timetable URL must not request PDF output',
      );
    }
    if (category != null) {
      final expected = _expectedAction(category);
      final actual = params['a'];
      if (actual != expected) {
        throw ConfigurationException(
          'Teacher timetable URL action "$actual" does not match $category (expected "$expected")',
        );
      }
    }
    return url;
  }

  static Uri? _tryResolve(String? href) {
    final trimmed = href?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    return _base.resolveUri(parsed);
  }

  static Map<String, String> _safeQueryParameters(Uri uri) {
    try {
      return uri.queryParameters;
    } on FormatException {
      final result = <String, String>{};
      for (final part in uri.query.split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        if (eq < 0) {
          result[_safeDecode(part)] = '';
        } else {
          result[_safeDecode(part.substring(0, eq))] = _safeDecode(
            part.substring(eq + 1),
          );
        }
      }
      return result;
    }
  }

  static Iterable<Element> _linksWithAction(Element root, String action) sync* {
    for (final a in root.querySelectorAll('a[href]')) {
      final resolved = _tryResolve(a.attributes['href']);
      if (resolved != null && _safeQueryParameters(resolved)['a'] == action) {
        yield a;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Static offline / fixture HTML parsers
  // ---------------------------------------------------------------------------

  /// Parse raw `stundenplan.php` teacher overview HTML.
  static TeacherTimetableOverview parseOverviewHtml(String html) =>
      parseOverviewDocument(parse(html));

  /// Parse teacher overview [Document].
  static TeacherTimetableOverview parseOverviewDocument(Document document) {
    _checkErrorPage(document);
    final content = document.getElementById('content') ?? document.body;
    if (content == null) {
      throw UnknownException('Missing teacher timetable content');
    }

    Uri? ownUrl;
    for (final a in content.querySelectorAll('a.btn[href]')) {
      final resolved = _tryResolve(a.attributes['href']);
      if (resolved != null &&
          resolved.path == '/stundenplan.php' &&
          _safeQueryParameters(resolved)['a'] == 'detail') {
        ownUrl = resolved;
        break;
      }
    }

    final accordion = content.querySelector('#accordion');
    if (accordion == null) {
      throw UnknownException('Missing teacher timetable overview (#accordion)');
    }

    final teachers = <TeacherTimetableReference>[];
    final classes = <TeacherTimetableReference>[];
    final rooms = <TeacherTimetableReference>[];
    final breakSupervisions = <TeacherTimetableReference>[];
    var hasTeachersPanel = false;
    Uri? freeRoomsUrl;

    for (final panel in accordion.querySelectorAll('.panel')) {
      final heading =
          panel.querySelector('.panel-title')?.text.trim().toLowerCase() ?? '';
      if (heading.contains('lehrkr')) {
        hasTeachersPanel = true;
      }

      for (final freeLink in _linksWithAction(panel, 'freeRoom')) {
        final resolved = _tryResolve(freeLink.attributes['href']);
        if (resolved != null) {
          freeRoomsUrl = resolved;
          break;
        }
      }

      for (final link in panel.querySelectorAll('a.list-group-item[href]')) {
        final resolved = _tryResolve(link.attributes['href']);
        if (resolved == null) continue;
        final params = _safeQueryParameters(resolved);
        final action = params['a'];
        final label = _cleanText(link.text);

        switch (action) {
          case 'detail':
            final id = params['t'] ?? '';
            if (id.isNotEmpty) {
              teachers.add(
                TeacherTimetableReference(
                  category: TeacherTimetableCategory.teacher,
                  id: id,
                  label: label,
                  url: resolved,
                ),
              );
            }
          case 'detail_klasse':
            final id = params['k'] ?? '';
            if (id.isNotEmpty) {
              classes.add(
                TeacherTimetableReference(
                  category: TeacherTimetableCategory.schoolClass,
                  id: id,
                  label: label,
                  url: resolved,
                ),
              );
            }
          case 'detail_raum':
            final id = params['r'] ?? '';
            if (id.isNotEmpty) {
              rooms.add(
                TeacherTimetableReference(
                  category: TeacherTimetableCategory.room,
                  id: id,
                  label: label,
                  url: resolved,
                ),
              );
            }
          case 'detail_pause':
            final id = params['p'] ?? '';
            if (id.isNotEmpty) {
              breakSupervisions.add(
                TeacherTimetableReference(
                  category: TeacherTimetableCategory.breakSupervision,
                  id: id,
                  label: label,
                  url: resolved,
                ),
              );
            }
        }
      }
    }

    final noticeHtml = _extractNoticeHtml(content);

    return TeacherTimetableOverview(
      ownTimetableUrl: ownUrl,
      teachers: teachers,
      classes: classes,
      rooms: rooms,
      breakSupervisions: breakSupervisions,
      canViewOtherTeachers: hasTeachersPanel,
      freeRoomsUrl: freeRoomsUrl,
      noticeHtml: noticeHtml,
    );
  }

  /// Parse raw detail HTML (`detail`, `detail_klasse`, `detail_raum`, or `detail_pause`).
  static TeacherTimetablePlan parsePlanHtml(
    String html, {
    required TeacherTimetableCategory category,
    String targetId = '',
  }) => parsePlanDocument(
    parse(html),
    category: category,
    targetId: targetId,
  );

  /// Parse detail [Document] for a teacher, class, room, or break supervision view.
  static TeacherTimetablePlan parsePlanDocument(
    Document document, {
    required TeacherTimetableCategory category,
    String targetId = '',
  }) {
    _checkErrorPage(document);
    final content = document.getElementById('content') ?? document.body;
    if (content == null) {
      throw UnknownException('Missing teacher timetable content');
    }

    final h1 = content.querySelector('h1');
    final exemplar = h1?.attributes['data-exemplar']?.trim();
    final timesHidden =
        (h1?.attributes['data-vonbisausblenden']?.trim().toLowerCase() ?? '') ==
        'on';
    final title = _extractTitle(h1);

    final planRoot = content.querySelector('.plan');
    if (planRoot == null) {
      throw UnknownException('Missing teacher timetable plan (.plan)');
    }
    final rawPlanDate = planRoot.attributes['data-date']?.trim();
    final availableVersions = TimetableVersionHelper.parseVersions(
      planRoot,
      planDate: rawPlanDate,
    );
    var planDate = (rawPlanDate != null && rawPlanDate.isNotEmpty)
        ? rawPlanDate
        : null;
    if (planDate == null) {
      for (final v in availableVersions) {
        if (v.isSelected) {
          planDate = v.date;
          break;
        }
      }
    }
    final validFromLabel = TimetableVersionHelper.extractValidFrom(
      planRoot,
      versions: availableVersions,
    );
    final weekBadge = document.querySelector('#aktuelleWoche')?.text.trim();
    final noticeHtml = _extractNoticeHtml(content);

    // Räume und Medien button ("buchbar in Räume und Medien") on detail_raum.
    Uri? rumbsUrl;
    for (final a in content.querySelectorAll('a[href*="raeumeundmedien.php"]')) {
      if (_hasAncestor(a, (el) => el.classes.contains('plan'))) continue;
      final resolved = _tryResolve(a.attributes['href']);
      if (resolved != null) {
        rumbsUrl = resolved;
        break;
      }
    }

    final (roomTeachers, roomContacts) = _extractRoomTeachersAndContacts(
      content,
    );

    final availableTargets = _extractSelectTargets(
      content,
      category: category,
      exemplar: exemplar,
      planDate: planDate,
    );

    // Infer targetId from selected option or title when omitted (e.g., own plan).
    var resolvedTargetId = targetId;
    if (resolvedTargetId.isEmpty) {
      final selected = content.querySelector(
        'select.select2-class option[selected]',
      );
      final rawVal = selected?.attributes['value']?.trim();
      if (rawVal != null && rawVal.isNotEmpty) {
        resolvedTargetId = _safeDecode(rawVal);
      } else if (category == TeacherTimetableCategory.teacher) {
        final codeMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(title);
        resolvedTargetId = codeMatch?.group(1)?.trim() ?? title;
      } else {
        resolvedTargetId = title;
      }
    }

    final table = planRoot.querySelector('table');
    final tbody = table?.querySelector('tbody');
    if (table == null || tbody == null) {
      return TeacherTimetablePlan(
        category: category,
        targetId: resolvedTargetId,
        title: title,
        validFromLabel: validFromLabel,
        planDate: planDate,
        exemplar: exemplar,
        timesHidden: timesHidden,
        weekBadge: weekBadge,
        noticeHtml: noticeHtml,
        bookableInRumbs: rumbsUrl != null,
        rumbsUrl: rumbsUrl,
        roomTeachers: roomTeachers,
        roomTeacherContacts: roomContacts,
        availableTargets: availableTargets,
        availableVersions: availableVersions,
        weekdayIndices: const [],
        hours: const [],
        days: const [],
      );
    }

    final weekdayIndices = _parseWeekdayIndices(table, tbody);
    final hours = _parseRows(tbody);
    final days = _parseGrid(
      tbody,
      dayCount: weekdayIndices.length,
      category: category,
      pageTitle: title,
      pageTargetId: resolvedTargetId,
    );

    return TeacherTimetablePlan(
      category: category,
      targetId: resolvedTargetId,
      title: title,
      validFromLabel: validFromLabel,
      planDate: planDate,
      exemplar: exemplar,
      timesHidden: timesHidden,
      weekBadge: weekBadge,
      noticeHtml: noticeHtml,
      bookableInRumbs: rumbsUrl != null,
      rumbsUrl: rumbsUrl,
      roomTeachers: roomTeachers,
      roomTeacherContacts: roomContacts,
      availableTargets: availableTargets,
      availableVersions: availableVersions,
      weekdayIndices: weekdayIndices,
      hours: hours,
      days: days,
    );
  }

  /// Parse raw `stundenplan.php?a=freeRoom` HTML.
  static TeacherFreeRoomsResult parseFreeRoomsHtml(String html) =>
      parseFreeRoomsDocument(parse(html));

  /// Parse `stundenplan.php?a=freeRoom` [Document].
  static TeacherFreeRoomsResult parseFreeRoomsDocument(Document document) {
    _checkErrorPage(document);
    final content = document.getElementById('content') ?? document.body;
    if (content == null) {
      throw UnknownException('Missing free rooms content');
    }

    final tagSelect = content.querySelector('select#tag, select[name="tag"]');
    if (tagSelect == null) {
      throw UnknownException('Missing free rooms form (select#tag)');
    }
    final selectedTag =
        tagSelect.querySelector('option[selected]')?.attributes['value'] ??
        tagSelect.querySelector('option')?.attributes['value'];
    final weekday = int.tryParse(selectedTag ?? '') ?? 1;

    final availableHours = <int>[];
    final selectedHours = <int>[];
    for (final cb in content.querySelectorAll('input[name="stunde[]"]')) {
      final h = int.tryParse(cb.attributes['value'] ?? '');
      if (h == null) continue;
      availableHours.add(h);
      if (cb.attributes.containsKey('checked')) {
        selectedHours.add(h);
      }
    }

    final rooms = <TeacherTimetableReference>[];
    for (final link in content.querySelectorAll('ul li a[href]')) {
      final resolved = _tryResolve(link.attributes['href']);
      if (resolved == null) continue;
      final params = _safeQueryParameters(resolved);
      if (params['a'] != 'detail_raum') continue;
      final id = params['r'] ?? _cleanText(link.text);
      if (id.isEmpty) continue;
      rooms.add(
        TeacherTimetableReference(
          category: TeacherTimetableCategory.room,
          id: id,
          label: _cleanText(link.text),
          url: resolved,
        ),
      );
    }

    return TeacherFreeRoomsResult(
      weekday: weekday,
      selectedHours: selectedHours,
      availableHours: availableHours,
      rooms: rooms,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal parsing helpers
  // ---------------------------------------------------------------------------

  static void _checkErrorPage(Document document) {
    final err = document.querySelector(
      '#content .error-wrapper .alert-danger, #content .jumbotron.alert-danger',
    );
    if (err == null) return;
    final text = _cleanText(err.text);
    final lower = text.toLowerCase();
    if (lower.contains('nicht erlaubt') ||
        lower.contains('keine berechtigung') ||
        lower.contains('kein zugriff') ||
        lower.contains('zugriff verweigert')) {
      throw UnauthorizedException(text);
    }
    throw UnknownException(text.isEmpty ? 'Teacher timetable error' : text);
  }

  static String _extractTitle(Element? h1) {
    if (h1 == null) return '';
    final clone = h1.clone(true);
    for (final small in clone.querySelectorAll('small')) {
      small.remove();
    }
    return _cleanText(clone.text);
  }

  static String? _extractNoticeHtml(Element content) {
    for (final alert in content.querySelectorAll('.alert.alert-warning')) {
      // Skip only the multi-version date-picker wrapper, not genuine notices.
      if (alert.querySelector('select.date-select') != null) {
        continue;
      }
      // Skip the static freeRoom warning banner.
      final text = _cleanText(alert.text);
      if (text.startsWith('Es können nur Räume gefunden werden')) continue;
      final html = alert.innerHtml.trim();
      if (html.isNotEmpty) return html;
    }
    return null;
  }

  static (List<String>, List<TeacherTimetableContact>)
  _extractRoomTeachersAndContacts(Element content) {
    final teacherCodes = <String>[];
    final contacts = <TeacherTimetableContact>[];

    for (final alert in content.querySelectorAll('.alert.alert-info')) {
      if (alert.classes.contains('mailInfo')) {
        for (final mail in alert.querySelectorAll('a[href^="mailto:"], a[href^="MAILTO:"]')) {
          final href = mail.attributes['href'] ?? '';
          final email = href
              .replaceFirst(RegExp(r'^mailto:\s*', caseSensitive: false), '')
              .split('?')
              .first
              .trim();
          final text = _cleanText(mail.text);
          // Format: "Max Mustermann (MUM)" <max.mustermann@example.org>
          final match = RegExp(
            r'"?([^"(<]+?)\s*\(([^)]+)\)"?',
          ).firstMatch(text);
          final code = match?.group(2)?.trim() ?? '';
          final name = match?.group(1)?.trim();
          if (code.isNotEmpty || email.isNotEmpty) {
            contacts.add(
              TeacherTimetableContact(
                teacherCode: code.isNotEmpty ? code : email,
                displayName: (name != null && name.isNotEmpty) ? name : null,
                email: email.isNotEmpty ? email : null,
              ),
            );
          }
        }
      } else {
        final heading = alert.querySelector('b')?.text.trim() ?? '';
        if (heading.startsWith('Lehrkräfte')) {
          final spanText =
              alert.querySelector('.copyToClipboard')?.text ?? '';
          for (final part in spanText.split(',')) {
            final code = part.trim();
            if (code.isNotEmpty) teacherCodes.add(code);
          }
        }
      }
    }

    return (teacherCodes, contacts);
  }

  static List<TeacherTimetableReference> _extractSelectTargets(
    Element content, {
    required TeacherTimetableCategory category,
    String? exemplar,
    String? planDate,
  }) {
    final select = content.querySelector('select.select2-class');
    if (select == null) return const [];

    final (action, paramName) = switch (category) {
      TeacherTimetableCategory.teacher => ('detail', 't'),
      TeacherTimetableCategory.schoolClass => ('detail_klasse', 'k'),
      TeacherTimetableCategory.room => ('detail_raum', 'r'),
      TeacherTimetableCategory.breakSupervision => ('detail_pause', 'p'),
    };

    final refs = <TeacherTimetableReference>[];
    for (final opt in select.querySelectorAll('option')) {
      final rawVal = opt.attributes['value']?.trim();
      if (rawVal == null || rawVal.isEmpty) continue;
      final id = _safeDecode(rawVal);
      final label = _cleanText(opt.text);
      final uri = _buildDetailUri(
        action: action,
        paramName: paramName,
        paramValue: id,
        date: planDate,
        exemplar: exemplar,
      );
      refs.add(
        TeacherTimetableReference(
          category: category,
          id: id,
          label: label.isNotEmpty ? label : id,
          url: uri,
        ),
      );
    }
    return refs;
  }

  static List<int> _parseWeekdayIndices(Element table, Element tbody) {
    final theadRows = table.querySelectorAll('thead tr');
    if (theadRows.isNotEmpty) {
      // Use the LAST row of thead because vplanEinbettung=ja prepends a VPlan
      // summary row before the weekday header row.
      final headerCells = theadRows.last.querySelectorAll('th, td');
      if (headerCells.length > 1) {
        final indices = <int>[];
        for (var i = 1; i < headerCells.length; i++) {
          final name = _cleanText(headerCells[i].text).toLowerCase();
          final mapped = _weekdayNames[name];
          indices.add(mapped ?? (i - 1));
        }
        return indices;
      }
    }
    if (tbody.children.isEmpty) return const [];
    final dayCount = tbody.children.first.children.length - 1;
    if (dayCount <= 0) return const [];
    return List.generate(dayCount, (i) => i);
  }

  static List<TimeTableRow> _parseRows(Element tbody) {
    final result = <TimeTableRow>[];
    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue;
      if (rowElement.children.isEmpty) continue;
      final firstCell = rowElement.children.first;
      final labelRoot = firstCell.querySelector('.print-show');
      if (labelRoot == null) continue;
      final label = _cleanText(
        (labelRoot.querySelector('b') ?? labelRoot).text,
      );
      final vonBis = firstCell.querySelector('.VonBis');
      final slot = vonBis == null ? null : _parseVonBis(vonBis);
      result.add(
        TimeTableRow(
          TimeTableRowType.lesson,
          slot?.$1 ?? const SphTimeOfDay(hour: 0, minute: 0),
          slot?.$2 ?? const SphTimeOfDay(hour: 0, minute: 0),
          label,
          rowIndex,
        ),
      );
    }
    return result;
  }

  static List<List<TeacherTimetableEntry>> _parseGrid(
    Element tbody, {
    required int dayCount,
    required TeacherTimetableCategory category,
    required String pageTitle,
    required String pageTargetId,
  }) {
    if (tbody.children.isEmpty || dayCount <= 0) return const [];

    final result = List.generate(dayCount, (_) => <TeacherTimetableEntry>[]);

    final timeSlots = <(SphTimeOfDay, SphTimeOfDay)?>[];
    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue;
      final vonBis = rowElement.children.isEmpty
          ? null
          : rowElement.children.first.querySelector('.VonBis');
      timeSlots.add(vonBis == null ? null : _parseVonBis(vonBis));
    }

    final alreadyParsed = List.generate(
      tbody.children.length + 32,
      (_) => List.generate(dayCount, (_) => false),
    );

    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue;
      for (var (colIndex, colElement) in rowElement.children.indexed) {
        if (colIndex == 0) continue;
        final rawSpan =
            int.tryParse(colElement.attributes['rowspan'] ?? '1') ?? 1;
        final rowSpan = rawSpan < 1 ? 1 : rawSpan;

        var actualDay = colIndex - 1;
        while (actualDay < dayCount && alreadyParsed[rowIndex][actualDay]) {
          actualDay++;
        }
        if (actualDay >= dayCount) continue;

        for (var i = 0; i < rowSpan; i++) {
          final r = rowIndex + i;
          if (r >= alreadyParsed.length) break;
          if (actualDay < alreadyParsed[r].length) {
            alreadyParsed[r][actualDay] = true;
          }
        }

        result[actualDay].addAll(
          _parseCell(
            colElement,
            rowIndex: rowIndex,
            rowSpan: rowSpan,
            timeSlots: timeSlots,
            dayIndex: actualDay,
            category: category,
            pageTitle: pageTitle,
            pageTargetId: pageTargetId,
          ),
        );
      }
    }

    return result;
  }

  static List<TeacherTimetableEntry> _parseCell(
    Element cell, {
    required int rowIndex,
    required int rowSpan,
    required List<(SphTimeOfDay, SphTimeOfDay)?> timeSlots,
    required int dayIndex,
    required TeacherTimetableCategory category,
    required String pageTitle,
    required String pageTargetId,
  }) {
    final entries = <TeacherTimetableEntry>[];
    final (startTime, endTime) = _resolveTimeRange(
      timeSlots,
      rowIndex: rowIndex,
      duration: rowSpan,
    );

    // 1. Direct child `.pausenaufsicht` divs (rendered as siblings of `.stunde`
    //    on teacher plans `a=detail`).
    var childIndex = 0;
    for (final child in cell.children) {
      if (child.classes.contains('pausenaufsicht')) {
        entries.add(
          _parseBreakSupervisionElement(
            child,
            category: category,
            pageTitle: pageTitle,
            pageTargetId: pageTargetId,
            dayIndex: dayIndex,
            rowIndex: rowIndex,
            itemIndex: childIndex++,
            startTime: startTime,
            endTime: endTime,
          ),
        );
      } else if (child.classes.contains('stunde')) {
        // On `detail_pause`, `.pausenaufsicht` is wrapped INSIDE `.stunde`.
        final nestedPause = child.querySelector('.pausenaufsicht');
        if (nestedPause != null) {
          entries.add(
            _parseBreakSupervisionElement(
              nestedPause,
              category: category,
              pageTitle: pageTitle,
              pageTargetId: pageTargetId,
              dayIndex: dayIndex,
              rowIndex: rowIndex,
              itemIndex: childIndex++,
              startTime: startTime,
              endTime: endTime,
            ),
          );
        } else {
          entries.add(
            _parseStundeElement(
              child,
              category: category,
              pageTargetId: pageTargetId,
              dayIndex: dayIndex,
              rowIndex: rowIndex,
              rowSpan: rowSpan,
              itemIndex: childIndex++,
              startTime: startTime,
              endTime: endTime,
            ),
          );
        }
      }
    }

    return entries;
  }

  static TeacherTimetableEntry _parseBreakSupervisionElement(
    Element el, {
    required TeacherTimetableCategory category,
    required String pageTitle,
    required String pageTargetId,
    required int dayIndex,
    required int rowIndex,
    required int itemIndex,
    required SphTimeOfDay startTime,
    required SphTimeOfDay endTime,
  }) {
    final teachers = <String>[];
    String? location;

    final teacherLink = _linksWithAction(el, 'detail').firstOrNull;
    final pauseLink = _linksWithAction(el, 'detail_pause').firstOrNull;

    if (category == TeacherTimetableCategory.breakSupervision) {
      location = pageTitle.isNotEmpty ? pageTitle : pageTargetId;
      final teacherText = _cleanText(teacherLink?.text ?? el.text);
      if (teacherText.isNotEmpty) teachers.add(teacherText);
    } else {
      location = _cleanText(pauseLink?.text ?? el.text);
      if (category == TeacherTimetableCategory.teacher &&
          pageTargetId.isNotEmpty) {
        teachers.add(pageTargetId);
      }
    }

    final seed =
        'pause:$location:${teachers.join(',')}:$dayIndex:$rowIndex:$itemIndex';
    final id = const Uuid().v5(Namespace.url.value, seed).replaceAll('-', '');

    return TeacherTimetableEntry(
      id: id,
      kind: TeacherTimetableEntryKind.breakSupervision,
      teachers: teachers,
      supervisionLocation: location.isNotEmpty ? location : null,
      tooltip: el.attributes['title']?.trim(),
      duration: 1,
      startTime: startTime,
      endTime: endTime,
      hourIndex: rowIndex,
    );
  }

  static TeacherTimetableEntry _parseStundeElement(
    Element row, {
    required TeacherTimetableCategory category,
    required String pageTargetId,
    required int dayIndex,
    required int rowIndex,
    required int rowSpan,
    required int itemIndex,
    required SphTimeOfDay startTime,
    required SphTimeOfDay endTime,
  }) {
    // Detect embedded Vertretungsplan or Räume & Medien entries.
    final labelEl = row.querySelector('span.label');
    final labelTitle = labelEl?.attributes['title']?.trim() ?? '';
    final embeddedDate = labelEl == null ? null : _cleanText(labelEl.text);
    final vplanLink = row.querySelector('a[href*="vertretungsplan.php"]');
    final rumbsLink = row.querySelector('a[href*="raeumeundmedien.php"]');
    final subCreateLink = row.querySelector(
      'a[href*="meinunterricht.php"][href*="vertretung"]',
    );

    final TeacherTimetableEntryKind kind;
    Uri? externalUrl;
    if (rumbsLink != null ||
        labelTitle.toLowerCase().contains('räume und medien')) {
      kind = TeacherTimetableEntryKind.roomBooking;
      externalUrl = _tryResolve(rumbsLink?.attributes['href']);
    } else if (vplanLink != null ||
        labelTitle.toLowerCase().contains('vertretungsplan')) {
      kind = (labelEl?.classes.contains('label-danger') ?? false)
          ? TeacherTimetableEntryKind.substitutionChanged
          : TeacherTimetableEntryKind.substitutionAdded;
      externalUrl = _tryResolve(vplanLink?.attributes['href']);
    } else {
      kind = TeacherTimetableEntryKind.regular;
    }

    final substitutionCreateUrl = _tryResolve(
      subCreateLink?.attributes['href'],
    );

    // Subject: first <b> outside <small> (note: on detail_raum, <small> also has a <b> for teacher).
    String? subject;
    for (final b in row.querySelectorAll('b')) {
      if (_hasAncestor(b, (el) => el.localName == 'small')) continue;
      final t = _cleanText(b.text);
      if (t.isNotEmpty) {
        subject = t;
        break;
      }
    }

    // Badge (A, B, G, U, ...).
    final badgeText = _cleanText(row.querySelector('.badge')?.text ?? '');
    final badge = badgeText.isEmpty ? null : badgeText;

    // Course name ("LUSD-Name der Lerngruppe") from explicit span or title="(kurs)".
    String? course;
    final lusdSpan = row.querySelector('span[title="LUSD-Name der Lerngruppe"]');
    if (lusdSpan != null) {
      final t = _cleanText(lusdSpan.text);
      if (t.isNotEmpty) course = t;
    }
    final tooltip = row.attributes['title']?.trim();
    if (course == null && tooltip != null && tooltip.isNotEmpty) {
      final m = RegExp(r'\(([^()]+)\)\s*$').firstMatch(tooltip);
      final candidate = m?.group(1)?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        course = candidate;
      }
    }

    // Classes from `a[href]` with `a=detail_klasse`.
    final classes = <String>[];
    for (final a in _linksWithAction(row, 'detail_klasse')) {
      final t = _cleanText(a.text);
      if (t.isNotEmpty && !classes.contains(t)) {
        classes.add(t);
      }
    }
    if (classes.isEmpty &&
        category == TeacherTimetableCategory.schoolClass &&
        pageTargetId.isNotEmpty) {
      classes.add(pageTargetId);
    }

    // Room from `a[href]` with `a=detail_raum`, or plain text `in <room>` inside `<small>`,
    // or pageTargetId when on `detail_raum`.
    String? room;
    final roomLink = _linksWithAction(row, 'detail_raum').firstOrNull;
    if (roomLink != null) {
      final t = _cleanText(roomLink.text);
      if (t.isNotEmpty) room = t;
    }
    if (room == null) {
      for (final small in row.querySelectorAll('small')) {
        if (_hasAncestor(
          small,
          (el) =>
              el.localName == 'span' &&
              el.attributes['title'] == 'LUSD-Name der Lerngruppe',
        )) {
          continue;
        }
        final smallText = _cleanTextWithoutBadges(small);
        final inMatch = RegExp(r'^in\s+(.+)$').firstMatch(smallText);
        if (inMatch != null) {
          final candidate = inMatch.group(1)!.trim();
          if (candidate.isNotEmpty) {
            room = candidate;
            break;
          }
        }
      }
    }
    if (room == null &&
        category == TeacherTimetableCategory.room &&
        pageTargetId.isNotEmpty) {
      room = pageTargetId;
    }

    // Teachers from `a[href]` with `a=detail`, or plain text inside `<small>` on
    // `detail_klasse` / `<small><b>...</b>` on `detail_raum` when `teacherCanSee=own`.
    final teachers = <String>[];
    for (final a in _linksWithAction(row, 'detail')) {
      final t = _cleanText(a.text);
      if (t.isNotEmpty && !teachers.contains(t)) {
        teachers.add(t);
      }
    }
    if (teachers.isEmpty) {
      if (category == TeacherTimetableCategory.schoolClass) {
        final small = _primarySmall(row);
        if (small != null) {
          final t = _cleanTextWithoutBadges(small);
          if (t.isNotEmpty && !t.startsWith('in ')) {
            teachers.add(t);
          }
        }
      } else if (category == TeacherTimetableCategory.room) {
        final smallB = _primarySmall(row)?.querySelector('b');
        final t = _cleanText(smallB?.text ?? '');
        if (t.isNotEmpty) teachers.add(t);
      } else if (category == TeacherTimetableCategory.teacher &&
          pageTargetId.isNotEmpty) {
        teachers.add(pageTargetId);
      }
    }

    var rawId = row.attributes['data-mix']?.trim();
    if (rawId == null || rawId.isEmpty) {
      final seed =
          '${kind.name}:${subject ?? ''}:${room ?? ''}:${teachers.join(',')}:${classes.join(',')}:${embeddedDate ?? ''}:$itemIndex';
      rawId = const Uuid().v5(Namespace.url.value, seed).replaceAll('-', '');
    }

    return TeacherTimetableEntry(
      id: '$rawId-$dayIndex-$rowIndex-${startTime.hour}-${startTime.minute}',
      kind: kind,
      subject: subject,
      course: course,
      room: room,
      teachers: teachers,
      classes: classes,
      badge: badge,
      embeddedDate: (embeddedDate != null && embeddedDate.isNotEmpty)
          ? embeddedDate
          : null,
      tooltip: (tooltip != null && tooltip.isNotEmpty) ? tooltip : null,
      duration: rowSpan,
      startTime: startTime,
      endTime: endTime,
      hourIndex: rowIndex,
      substitutionCreateUrl: substitutionCreateUrl,
      externalUrl: externalUrl,
    );
  }

  static String _cleanTextWithoutBadges(Element element) {
    final clone = element.clone(true);
    for (final b in clone.querySelectorAll('.badge')) {
      b.remove();
    }
    return _cleanText(clone.text);
  }

  static Element? _primarySmall(Element row) {
    for (final small in row.querySelectorAll('small')) {
      if (_hasAncestor(
        small,
        (el) =>
            el.localName == 'span' &&
            el.attributes['title'] == 'LUSD-Name der Lerngruppe',
      )) {
        continue;
      }
      return small;
    }
    return null;
  }

  static bool _hasAncestor(Element element, bool Function(Element) predicate) {
    var current = element.parent;
    while (current != null) {
      if (predicate(current)) return true;
      current = current.parent;
    }
    return false;
  }

  static (SphTimeOfDay, SphTimeOfDay) _resolveTimeRange(
    List<(SphTimeOfDay, SphTimeOfDay)?> timeSlots, {
    required int rowIndex,
    required int duration,
  }) {
    final startIdx = rowIndex - 1;
    final endIdx = startIdx + duration - 1;
    if (startIdx >= 0 &&
        endIdx >= 0 &&
        startIdx < timeSlots.length &&
        endIdx < timeSlots.length) {
      final startSlot = timeSlots[startIdx];
      final endSlot = timeSlots[endIdx];
      if (startSlot != null && endSlot != null) {
        return (startSlot.$1, endSlot.$2);
      }
    }
    return (
      const SphTimeOfDay(hour: 0, minute: 0),
      const SphTimeOfDay(hour: 0, minute: 0),
    );
  }

  static (SphTimeOfDay, SphTimeOfDay)? _parseVonBis(Element e) {
    final timeString = e.text.trim();
    final parts = timeString.split(' - ');
    if (parts.length != 2) return null;
    final a = parts[0].split(':');
    final b = parts[1].split(':');
    if (a.length < 2 || b.length < 2) return null;
    final aH = int.tryParse(a[0].trim());
    final aM = int.tryParse(a[1].trim());
    final bH = int.tryParse(b[0].trim());
    final bM = int.tryParse(b[1].trim());
    if (aH == null || aM == null || bH == null || bM == null) return null;
    return (
      SphTimeOfDay(hour: aH, minute: aM),
      SphTimeOfDay(hour: bH, minute: bM),
    );
  }

  static String _cleanText(String raw) =>
      raw.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _safeDecode(String raw) {
    try {
      return Uri.decodeQueryComponent(raw);
    } on FormatException {
      return raw;
    } on ArgumentError {
      return raw;
    }
  }

  @override
  TeacherTimetableOverview typeFromJson(String json) =>
      TeacherTimetableOverview.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
}
