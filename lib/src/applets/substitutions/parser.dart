import 'dart:convert';
import 'dart:io';

import 'package:dart_date/dart_date.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:intl/intl.dart';

import '../../exceptions.dart';
import '../../models/substitution.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import '../../cache/annotation.dart';
import '../../cache/types.dart';

part 'parser.g.dart';

class SubstitutionsParser extends AppletParser<SubstitutionPlan>
    with _$SubstitutionsParserCache {
  final DateFormat entryFormat = DateFormat('dd_MM_yyyy');

  SubstitutionsParser(AppletContext ctx, {Future<bool> Function()? isConnected})
    : super(
        ctx,
        Applets.substitutions,
        isConnected:
            isConnected ?? () => ctx.session.connectionChecker.connected,
      );

  SubstitutionFilter localFilter = {};

  void saveFilterToStorage() {
    ctx.accountSettings.setJsonMap(
      'vertretungsplan.php/filter',
      Map<String, dynamic>.from(localFilter),
    );
  }

  void loadFilterFromStorage() {
    localFilter =
        ctx.accountSettings
            .getJsonMap('vertretungsplan.php/filter')
            ?.map(
              (key, value) => MapEntry(
                key,
                (value as Map<String, dynamic>).map(
                  (k, v) =>
                      MapEntry(k, v is List ? v.cast<String>() : v as bool),
                ),
              ),
            ) ??
        {};
  }

  @override
  SubstitutionPlan typeFromJson(String json) {
    return SubstitutionPlan.fromJson(jsonDecode(json));
  }

  @override
  CacheRequest<SubstitutionPlan> get homeCacheRequest =>
      SubstitutionsParserCacheRequests.getHome();

  @override
  Future<MaybeCacheResult<SubstitutionPlan>> loadCachedHome({
    CacheReadPolicy? policy,
  }) => cached.getHome(cachePolicy: policy);

  @override
  Future<SubstitutionPlan> getHome() async =>
      presentCachedHome(await _getHome());

  @override
  SubstitutionPlan presentCachedHome(SubstitutionPlan value) {
    loadFilterFromStorage();
    return SubstitutionPlan.fromJson(value.toJson())..filterAll(localFilter);
  }

  @Cacheable(operation: 'substitutions.home', applet: Applets.substitutions)
  Future<SubstitutionPlan> _getHome() async {
    final document = await getSubstitutionPlanDocument();
    final dates = getSubstitutionDates(document);
    final ajaxByDate = <String, String>{};
    for (final date in dates) {
      ajaxByDate[date] = await fetchSubstitutionsAjaxBody(date);
    }
    final plan = parseDocumentHtml(document, ajaxByDate: ajaxByDate);
    return plan;
  }

  /// Offline entry: parse shell HTML plus optional AJAX day bodies.
  ///
  /// Uses the AJAX path when the shell exposes `data-tag="dd.MM.yyyy"` **and**
  /// [ajaxByDate] supplies a body for at least one of those dates. Otherwise
  /// falls back to non-AJAX `#tagDD_MM_YYYY` / `#vtable…` table parsing
  /// (personal plan when "Zugriff auf den gesamten Plan" is off).
  static SubstitutionPlan parseDocumentHtml(
    String html, {
    Map<String, String>? ajaxByDate,
  }) {
    final lastEdit = parseLastEditDate(html);
    final dates = getSubstitutionDates(html);
    final parsedDocument = parse(html);

    final hasAjaxPayload =
        ajaxByDate != null && dates.any((d) => ajaxByDate.containsKey(d));

    if (dates.isEmpty || !hasAjaxPayload) {
      final plan = parseSubstitutionsNonAJAX(parsedDocument);
      plan.lastUpdated = lastEdit ?? DateTime.now();
      return plan;
    }

    final fullPlan = SubstitutionPlan(lastUpdated: lastEdit);
    for (final date in dates) {
      final body = ajaxByDate[date];
      if (body == null) continue;
      final day = parseAjaxDayJson(body, date);
      final tagId = 'tag${DateFormat('dd_MM_yyyy').format(day.dateTime)}';
      final tagEl = parsedDocument.getElementById(tagId);
      final infos = tagEl == null
          ? <SubstitutionInfo>[]
          : parseInformationTables(tagEl);
      fullPlan.add(day.withDayInfo(infos));
    }
    fullPlan.removeEmptyDays();
    return fullPlan;
  }

  /// Parse one getSubstitutions AJAX response body for [date] (`dd.MM.yyyy`).
  ///
  /// SPH may return a JSON list, or a sentinel like `-1` when empty/invalid.
  /// Non-list JSON / HTML is thrown for the caller (or global handler).
  static SubstitutionDay parseAjaxDayJson(String body, String date) {
    final trimmed = body.trim();
    if (trimmed.startsWith('<') ||
        trimmed.toLowerCase().startsWith('<!doctype')) {
      throw FormatException(
        'Substitution AJAX body is HTML, not a JSON list',
        trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw FormatException(
        'Substitution AJAX body is not valid JSON',
        e.message,
      );
    }
    if (decoded is! List) {
      // Sentinel empty / error codes → empty day rather than false crash.
      if (decoded is num) {
        return SubstitutionDay(parsedDate: date, substitutions: []);
      }
      throw FormatException(
        'Substitution AJAX body is not a JSON list',
        body.length > 80 ? '${body.substring(0, 80)}…' : body,
      );
    }

    return SubstitutionDay(
      parsedDate: date,
      substitutions: [
        for (final e in decoded)
          if (e is Map)
            Substitution(
              tag: '${e['Tag'] ?? date}',
              tag_en: '${e['Tag_en'] ?? ''}',
              stunde: parseHours('${e['Stunde'] ?? ''}'),
              vertreter: e['Vertreter']?.toString(),
              lehrer: e['Lehrer']?.toString(),
              klasse: e['Klasse']?.toString(),
              klasse_alt: e['Klasse_alt']?.toString(),
              fach: e['Fach']?.toString(),
              fach_alt: e['Fach_alt']?.toString(),
              raum: e['Raum']?.toString(),
              raum_alt: e['Raum_alt']?.toString(),
              hinweis: e['Hinweis']?.toString(),
              hinweis2: e['Hinweis2']?.toString(),
              art: e['Art']?.toString(),
              Lehrerkuerzel: e['Lehrerkuerzel']?.toString(),
              Vertreterkuerzel: e['Vertreterkuerzel']?.toString(),
              lerngruppe: e['Lerngruppe'],
              hervorgehoben: e['_hervorgehoben'] is List
                  ? e['_hervorgehoben'] as List
                  : null,
            ),
      ],
    );
  }

  Future<String> getSubstitutionPlanDocument() async {
    try {
      final response = await ctx.session.dio.get(
        'https://start.schulportal.hessen.de/vertretungsplan.php',
      );
      return response.data.toString();
    } on SocketException catch (error, stack) {
      Error.throwWithStackTrace(
        NetworkException.fromError(error, stack),
        stack,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<String> fetchSubstitutionsAjaxBody(String date) async {
    try {
      final response = await ctx.session.dio.post(
        'https://start.schulportal.hessen.de/vertretungsplan.php',
        queryParameters: {'a': 'my'},
        data: {'tag': date, 'ganzerPlan': 'true'},
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
      return response.data.toString();
    } on SocketException catch (error, stack) {
      Error.throwWithStackTrace(
        NetworkException.fromError(error, stack),
        stack,
      );
    }
  }

  static SubstitutionPlan parseSubstitutionsNonAJAX(Document document) {
    final entryFormat = DateFormat('dd_MM_yyyy');
    final fullPlan = SubstitutionPlan();
    final dateKeys = <String>{};

    for (final element in document.querySelectorAll('[data-tag]')) {
      final raw = element.attributes['data-tag'];
      if (raw == null || raw.isEmpty) continue;
      final key = normalizeSubstitutionDateKey(raw);
      if (key != null) dateKeys.add(key);
    }
    // Personal-plan shells often omit data-tag and only expose #tagDD_MM_YYYY.
    final panelId = RegExp(r'^tag(\d{2})_(\d{2})_(\d{4})$');
    for (final element in document.querySelectorAll('[id^=tag]')) {
      final m = panelId.firstMatch(element.id);
      if (m != null) {
        dateKeys.add('${m.group(1)}.${m.group(2)}.${m.group(3)}');
      }
    }

    for (final date in dateKeys) {
      final DateTime parsedDate;
      try {
        parsedDate = date.contains('.')
            ? DateFormat('dd.MM.yyyy').parse(date)
            : entryFormat.parse(date);
      } catch (_) {
        continue;
      }
      final idKey = entryFormat.format(parsedDate);
      final tagEl =
          document.getElementById('tag$idKey') ??
          document.getElementById('tag$date');
      if (tagEl == null) continue;

      final substitutionDay = SubstitutionDay(
        parsedDate: parsedDate.format('dd.MM.yyyy'),
        infos: parseInformationTables(tagEl),
      );
      final vtable =
          document.querySelector('#vtable$idKey') ??
          document.querySelector('#vtable$date') ??
          tagEl.querySelector('table[id^=vtable]');
      if (vtable == null) {
        // Keep infos-only days instead of aborting the whole plan.
        fullPlan.add(substitutionDay);
        continue;
      }

      final headers = <String>[];
      for (final th in vtable.querySelectorAll('th')) {
        final field = th.attributes['data-field'];
        if (field != null) headers.add(field);
      }
      final stundeIdx = headers.indexOf('Stunde');
      if (stundeIdx < 0) {
        // Unreadable table shape — keep day infos, skip rows.
        fullPlan.add(substitutionDay);
        continue;
      }

      for (final row
          in vtable
              .querySelectorAll('tbody tr')
              .where(
                (element) => element.querySelectorAll('td[colspan]').isEmpty,
              )) {
        final fields = row.querySelectorAll('td');
        if (fields.length <= stundeIdx) continue;
        String? col(String name) {
          final i = headers.indexOf(name);
          if (i < 0 || i >= fields.length) return null;
          final text = fields[i].text.trim();
          return text.isEmpty ? null : text;
        }

        substitutionDay.add(
          Substitution(
            tag: parsedDate.format('dd.MM.yyyy'),
            tag_en: idKey,
            stunde: parseHours(fields[stundeIdx].text.trim()),
            fach: col('Fach'),
            fach_alt: col('Fach_alt'),
            art: col('Art'),
            raum: col('Raum'),
            raum_alt: col('Raum_alt'),
            hinweis: col('Hinweis'),
            hinweis2: col('Hinweis2'),
            lehrer: col('Lehrer'),
            vertreter: col('Vertreter'),
            klasse: col('Klasse'),
            klasse_alt: col('Klasse_alt'),
          ),
        );
      }
      fullPlan.add(substitutionDay);
    }
    fullPlan.removeEmptyDays();
    return fullPlan;
  }

  /// Normalizes SPH date keys (`dd.MM.yyyy` or `dd_MM_yyyy`) to `dd.MM.yyyy`.
  ///
  /// Personal-plan shells put underscore tags on day buttons and dotted
  /// (or panel-id) forms on the same calendar day. Treating those as distinct
  /// keys duplicates days.
  static String? normalizeSubstitutionDateKey(String raw) {
    try {
      final parsed = raw.contains('.')
          ? DateFormat('dd.MM.yyyy').parse(raw)
          : DateFormat('dd_MM_yyyy').parse(raw);
      return parsed.format('dd.MM.yyyy');
    } catch (_) {
      return null;
    }
  }

  /// Returns unique dates (`dd.MM.yyyy`) for the AJAX path.
  ///
  /// Empty list means empty plan or non-AJAX format.
  static List<String> getSubstitutionDates(String document) {
    if (document.contains('Fehler - Schulportal Hessen - ')) {
      throw UnauthorizedException();
    }
    final datePattern = RegExp(r'data-tag="(\d{2})\.(\d{2})\.(\d{4})"');
    final uniqueDates = <String>[];
    for (final match in datePattern.allMatches(document)) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      final dateString = DateTime(year, month, day).format('dd.MM.yyyy');
      if (!uniqueDates.contains(dateString)) {
        uniqueDates.add(dateString);
      }
    }
    return uniqueDates;
  }

  /// Parses "Letzte Aktualisierung: 08.05.2024 um 13:35:30 Uhr".
  static DateTime? parseLastEditDate(String document) {
    final lastEditPattern = RegExp(
      r'Letzte\s+Aktualisierung:\s*(\d{2})\.(\d{2})\.(\d{4})\s+um\s+(\d{2}):(\d{2}):(\d{2})\s+Uhr',
      caseSensitive: false,
    );
    final match = lastEditPattern.firstMatch(document);
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  static String parseHours(String hours) {
    final numbers = RegExp(
      r'\d+',
    ).allMatches(hours).map((m) => m.group(0)!).toList();
    if (numbers.isEmpty || numbers.length > 2) return hours;
    return numbers.length == 2 ? '${numbers[0]} - ${numbers[1]}' : numbers[0];
  }

  static List<SubstitutionInfo> parseInformationTables(Element element) {
    final infos = <SubstitutionInfo>[];
    final tables = element.getElementsByClassName('infos');
    if (tables.isEmpty) return [];
    final table = tables[0];

    final rows = table.querySelectorAll('tr');
    var isHeader = false;
    SubstitutionInfo? tmpInfo;
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;
      if (row.classes.join(',').contains('header')) isHeader = true;
      if (isHeader) {
        if (tmpInfo != null) {
          infos.add(tmpInfo);
        }
        tmpInfo = SubstitutionInfo(header: cells[0].text.trim(), values: []);
      } else {
        tmpInfo?.values.add(cells[0].innerHtml.trim());
      }
      isHeader = false;
    }
    if (tmpInfo != null) {
      infos.add(tmpInfo);
    }
    return infos;
  }
}
