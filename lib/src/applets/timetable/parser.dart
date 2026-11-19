import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:uuid/uuid.dart';

import '../../exceptions.dart';
import '../../models/time_of_day.dart';
import '../../models/timetable.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import '../../cache/annotation.dart';
import '../../cache/types.dart';

part 'parser.g.dart';

class TimetableStudentParser extends AppletParser<TimeTable>
    with _$TimetableStudentParserCache {
  TimetableStudentParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.timetable,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  CacheRequest<TimeTable> get homeCacheRequest =>
      TimetableStudentParserCacheRequests.getHome();

  @override
  Future<MaybeCacheResult<TimeTable>> loadCachedHome({
    CacheReadPolicy? policy,
  }) => cached.getHome(cachePolicy: policy);

  @Cacheable(operation: 'timetable.student.home', applet: Applets.timetable)
  Future<TimeTable> _getHome() => getHome();

  @override
  Future<TimeTable> getHome() async {
    final Document? document = await getTimetableDocument();
    if (document == null) throw NetworkException();
    return parseDocument(document);
  }

  /// Offline/fixture entry point used by tests and [getHome].
  TimeTable parseDocument(Document document) => parseDocumentHtml(document);

  /// Parse a raw `stundenplan.php` HTML body (fixtures / offline).
  TimeTable parseHtml(String html) => parseDocumentHtml(parse(html));

  /// Static HTML parse path for unit tests (no session required).
  static TimeTable parseDocumentHtml(Document document) {
    final tbodyAll = document.querySelector('#all tbody');
    final tbodyOwn = document.querySelector('#own tbody');
    final String? weekBadge = document
        .querySelector('#aktuelleWoche')
        ?.text
        .trim();

    // Missing full plan table: return empty rather than crashing (LANIS-MOBILE-I).
    if (tbodyAll == null) {
      return TimeTable(
        planForAll: const [],
        planForOwn: tbodyOwn == null ? null : parseRoomPlan(tbodyOwn),
        hours: const [],
        weekBadge: weekBadge,
      );
    }

    return TimeTable(
      planForAll: parseRoomPlan(tbodyAll),
      planForOwn: tbodyOwn == null ? null : parseRoomPlan(tbodyOwn),
      hours: parseRows(tbodyAll),
      weekBadge: weekBadge,
    );
  }

  @override
  TimeTable typeFromJson(String json) {
    return TimeTable.fromJson(jsonDecode(json));
  }

  Future<Document?> getTimetableDocument() async {
    // On the website, the user is redirected every time, if they do not have the query parameter set.
    // However, the data is still loaded correctly without redirection, so we avoid it here to save traffic.

    final response1 = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/stundenplan.php',
    );

    if (response1.data.toString().trim().isNotEmpty) {
      final document = parse(response1.data);
      if (document.getElementById('all') != null) {
        return document;
      }
    }

    if (response1.headers['location'] == null) {
      return null;
    }

    final response2 = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/${response1.headers['location']?[0]}',
    );
    return parse(response2.data);
  }

  Future<Element?> getTableBody(
    Document document, {
    TimeTableType timeTableType = TimeTableType.all,
  }) async {
    switch (timeTableType) {
      case TimeTableType.all:
        return document.querySelector('#all tbody');
      case TimeTableType.own:
        return document.querySelector('#own tbody');
    }
  }

  static List<TimetableDay> parseRoomPlan(Element tbody) {
    if (tbody.children.isEmpty) return const [];

    final dayCount = tbody.children[0].children.length - 1;
    if (dayCount <= 0) return const [];

    final List<TimetableDay> result = List.generate(dayCount, (_) => []);

    final List<(SphTimeOfDay, SphTimeOfDay)> timeSlots = tbody
        .querySelectorAll('.VonBis')
        .map(_parseVonBis)
        .whereType<(SphTimeOfDay, SphTimeOfDay)>()
        .toList();

    // Cover all table rows; + buffer for aggressive rowspan values.
    final List<List<bool>> alreadyParsed = List.generate(
      tbody.children.length + 32,
      (_) => List.generate(dayCount, (_) => false),
    );

    final bool timeslotOffsetFirstRow =
        tbody.children[0].children.isNotEmpty &&
        tbody.children[0].children[0].text.trim() != '';

    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue; // skip first empty/header row
      for (var (colIndex, colElement) in rowElement.children.indexed) {
        if (colIndex == 0) continue; // skip first column
        final int rowSpan =
            int.tryParse(colElement.attributes['rowspan'] ?? '1') ?? 1;

        var actualDay = colIndex - 1;
        while (actualDay < dayCount && alreadyParsed[rowIndex][actualDay]) {
          actualDay++;
        }
        // LANIS-MOBILE-3/7: rowspan layout walked past the last day column.
        if (actualDay >= dayCount) continue;

        // LANIS-MOBILE-M: rowspan extending past tracked rows.
        for (var i = 0; i < rowSpan; i++) {
          final r = rowIndex + i;
          if (r >= alreadyParsed.length) break;
          if (actualDay < alreadyParsed[r].length) {
            alreadyParsed[r][actualDay] = true;
          }
        }

        result[actualDay].addAll(
          parseSingeHour(
            colElement,
            rowIndex,
            timeSlots,
            timeslotOffsetFirstRow,
            actualDay,
          ),
        );
      }
    }
    return result;
  }

  static List<TimeTableRow> parseRows(Element tbody) {
    final List<TimeTableRow> result = [];
    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue;
      for (final colElement in rowElement.children) {
        final Element? e = colElement.querySelector('.VonBis');
        if (e == null) break;
        final Element? labelRoot = colElement.querySelector('.print-show');
        if (labelRoot == null) break;
        final label = labelRoot.querySelector('b') ?? labelRoot;
        final slot = _parseVonBis(e);
        if (slot == null) break;
        result.add(
          TimeTableRow(
            TimeTableRowType.lesson,
            slot.$1,
            slot.$2,
            label.text.trim(),
            rowIndex,
          ),
        );
        break;
      }
    }
    return result;
  }

  static List<TimetableSubject> parseSingeHour(
    Element cell,
    int y,
    List<(SphTimeOfDay, SphTimeOfDay)> timeSlots,
    bool timeslotOffsetFirstRow,
    int day,
  ) {
    final List<TimetableSubject> result = [];
    for (final row in cell.querySelectorAll('.stunde')) {
      final name = row.querySelector('b')?.text.trim();
      final raum = row.nodes
          .map((node) => node.nodeType == 3 ? node.text!.trim() : '')
          .join();
      final lehrer = row.querySelector('small')?.text.trim();
      final badge = row.querySelector('.badge')?.text.trim();
      final duration =
          int.tryParse(row.parent?.attributes['rowspan'] ?? '1') ?? 1;

      final startIndex = timeslotOffsetFirstRow ? y : y - 1;
      final endIndex = timeslotOffsetFirstRow
          ? y + duration - 1
          : y - 1 + duration - 1;

      // When VonBis is hidden (admin setting) or rowspan exceeds known slots,
      // still keep the lesson — clock times are best-effort / zeroed.
      final SphTimeOfDay startTime;
      final SphTimeOfDay endTime;
      if (timeSlots.isNotEmpty &&
          startIndex >= 0 &&
          endIndex >= 0 &&
          startIndex < timeSlots.length &&
          endIndex < timeSlots.length) {
        startTime = timeSlots[startIndex].$1;
        endTime = timeSlots[endIndex].$2;
      } else {
        startTime = const SphTimeOfDay(hour: 0, minute: 0);
        endTime = const SphTimeOfDay(hour: 0, minute: 0);
      }

      var id = row.attributes['data-mix'];
      if (id == null || id.isEmpty) {
        id = Uuid().v5(Namespace.url.value, name ?? raum).replaceAll('-', '');
      }

      result.add(
        TimetableSubject(
          id: '$id-$day-${startTime.hour}-${startTime.minute}',
          name: name,
          raum: raum,
          lehrer: lehrer,
          badge: badge,
          duration: duration,
          startTime: startTime,
          endTime: endTime,
          stunde: y,
        ),
      );
    }
    return result;
  }

  static (SphTimeOfDay, SphTimeOfDay)? _parseVonBis(Element e) {
    final timeString = e.text.trim();
    final s = timeString.split(' - ');
    if (s.length != 2) return null;
    final splitA = s[0].split(':');
    final splitB = s[1].split(':');
    if (splitA.length < 2 || splitB.length < 2) return null;
    final aHour = int.tryParse(splitA[0]);
    final aMin = int.tryParse(splitA[1]);
    final bHour = int.tryParse(splitB[0]);
    final bMin = int.tryParse(splitB[1]);
    if (aHour == null || aMin == null || bHour == null || bMin == null) {
      return null;
    }
    return (
      SphTimeOfDay(hour: aHour, minute: aMin),
      SphTimeOfDay(hour: bHour, minute: bMin),
    );
  }
}
