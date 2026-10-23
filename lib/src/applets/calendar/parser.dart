import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../exceptions.dart';
import '../../models/calendar_event.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';

class CalendarParser extends AppletParser<List<CalendarEvent>> {
  CalendarParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.calendar,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  Future<List<CalendarEvent>> getHome() async {
    return getCalendar(
      startDate: DateTime.now().subtract(Duration(days: 120)),
      endDate: DateTime.now().add(Duration(days: 356)),
    );
  }

  /// Extract categories from kalender.php HTML.
  ///
  /// Tolerates missing `groups` markers and odd color values so a usable
  /// category list (or an empty one) is returned whenever the page is readable.
  static List<CalendarEventCategory> parseCategoriesHtml(String html) {
    final categories = <CalendarEventCategory>[];
    final pushRe = RegExp(r'categories\.push\(\s*(\{[^}]+\})\s*\)');
    for (final match in pushRe.allMatches(html)) {
      try {
        final trueJson = match
            .group(1)!
            .replaceAllMapped(RegExp(r'(\w+):'), (m) => '"${m[1]}":')
            .replaceAll("'", '"');
        final category = jsonDecode(trueJson) as Map<String, dynamic>;
        final id = category['id'];
        final idInt = id is int ? id : int.tryParse('$id');
        if (idInt == null) continue;
        categories.add(
          CalendarEventCategory(
            id: idInt,
            colorArgb: _parseCategoryColor(category['color']),
            name: '${category['name'] ?? ''}',
          ),
        );
      } catch (_) {
        // Skip a single malformed push line; keep the rest.
      }
    }
    return categories;
  }

  /// Parse the getEvents JSON body into [CalendarEvent]s.
  ///
  /// Throws [FormatException] / [TypeError] when the body is not a JSON list
  /// (auth HTML, error objects, …) — those stay for the caller's global path.
  /// Individual unreadable rows are skipped so one bad event does not wipe the
  /// whole calendar.
  static List<CalendarEvent> parseEventsJson(
    String body,
    List<CalendarEventCategory> categories,
  ) {
    final data = jsonDecode(body);
    if (data is! List) {
      throw FormatException(
        'getEvents response is not a JSON list',
        body.length > 80 ? '${body.substring(0, 80)}…' : body,
      );
    }

    final events = <CalendarEvent>[];
    for (final item in data) {
      if (item is! Map) continue;
      try {
        events.add(
          CalendarEvent.fromLanisJson(
            Map<String, dynamic>.from(item),
            categories,
          ),
        );
      } catch (_) {
        // Skip unreadable rows; keep the rest of the calendar.
      }
    }
    return events;
  }

  static int _parseCategoryColor(dynamic color) {
    const fallback = 0xFF4242FC;
    if (color is! String || color.isEmpty) return fallback;

    var hex = color.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);

    // Expand #RGB → #RRGGBB (SPH occasionally emits short colors).
    if (hex.length == 3 && RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex)) {
      hex = hex.split('').map((c) => '$c$c').join();
    }

    if (hex.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return fallback;
    }
    return int.parse(hex, radix: 16) + 0xFF000000;
  }

  Future<List<CalendarEvent>> getCalendar({
    required DateTime startDate,
    required DateTime endDate,
    String searchQuery = '',
  }) async {
    final formatter = DateFormat('yyyy-MM-dd');
    final start = formatter.format(startDate);
    final end = formatter.format(endDate);

    try {
      final docResponse = await ctx.session.dio.get(
        'https://start.schulportal.hessen.de/kalender.php',
      );
      final categories = parseCategoriesHtml('${docResponse.data}');

      final response = await ctx.session.dio.post(
        'https://start.schulportal.hessen.de/kalender.php',
        queryParameters: {
          'f': 'getEvents',
          's': searchQuery,
          'start': start,
          'end': end,
        },
        data: 'f=getEvents&start=$start&end=$end&s=$searchQuery',
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        ),
      );

      return parseEventsJson('${response.data}', categories);
    } on SocketException {
      throw NetworkException();
    } catch (e, stack) {
      Error.throwWithStackTrace(UnknownException(e.runtimeType.toString()), stack);
    }
  }

  Future<Map<String, dynamic>?> getEvent(String id) async {
    if (!(await isConnected())) {
      throw NoConnectionException();
    }

    try {
      final response = await ctx.session.dio.post(
        'https://start.schulportal.hessen.de/kalender.php',
        data: {'f': 'getEvent', 'id': id},
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        ),
      );
      final data = jsonDecode('${response.data}');
      if (data is! Map) return null;
      if (data['id'] == '' || data['id'] == null) return null;

      return Map<String, dynamic>.from(data);
    } on SocketException {
      throw NetworkException();
    } catch (e) {
      throw UnknownException();
    }
  }

  Future<({Set<int> years, String subscriptionLink})> getExports() async {
    final response = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/kalender.php',
    );

    final Set<int> years = {};

    final regex = RegExp(r'year=(\d\d\d\d)');
    final matches = regex.allMatches(response.data);
    for (var match in matches) {
      years.add(int.parse(match.group(1)!));
    }

    final iCalSubLink = await ctx.session.dio.post(
      'https://start.schulportal.hessen.de/kalender.php',
      data: {'f': 'iCalAbo'},
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
      ),
    );

    return (years: years, subscriptionLink: iCalSubLink.data as String);
  }
}
