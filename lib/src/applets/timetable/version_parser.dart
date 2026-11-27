import 'package:html/dom.dart';

import '../../models/timetable.dart';

/// Shared HTML helpers for multi-version `stundenplan.php` pages.
abstract final class TimetableVersionHelper {
  /// Parses selectable timetable versions from `select.date-select` inside
  /// [planRoot].
  ///
  /// Preserves the portal's option order (typically newest first) and ensures
  /// at most one version is marked [TimetableVersion.isSelected]:
  /// - When [planDate] is non-empty, only the option matching [planDate] is
  ///   selected (leaving selection unset if no option matches).
  /// - When [planDate] is absent/empty, the first option with a `selected`
  ///   attribute is selected.
  ///
  /// Returns an empty list when no `select.date-select` is present.
  static List<TimetableVersion> parseVersions(
    Element? planRoot, {
    String? planDate,
  }) {
    final select = planRoot?.querySelector('select.date-select');
    if (select == null) return const [];

    final normalizedPlanDate = planDate?.trim();
    final entries = <({String date, String label})>[];
    final indexByDate = <String, int>{};
    int? firstHtmlSelectedIndex;

    for (final opt in select.querySelectorAll('option')) {
      final date = opt.attributes['value']?.trim() ?? '';
      if (date.isEmpty) continue;
      final cleanedLabel = _cleanText(opt.text);
      final label = cleanedLabel.isNotEmpty ? cleanedLabel : date;
      final hasSelectedAttr = opt.attributes.containsKey('selected');

      final existingIndex = indexByDate[date];
      if (existingIndex != null) {
        if (hasSelectedAttr && firstHtmlSelectedIndex == null) {
          firstHtmlSelectedIndex = existingIndex;
        }
        continue;
      }

      final idx = entries.length;
      indexByDate[date] = idx;
      entries.add((date: date, label: label));
      if (hasSelectedAttr && firstHtmlSelectedIndex == null) {
        firstHtmlSelectedIndex = idx;
      }
    }

    if (entries.isEmpty) return const [];

    // When the rendered plan carries a data-date, select only the matching
    // option (leaving selection unset if absent so we never mislabel another
    // version). Fall back to HTML `selected` only when data-date is absent.
    final int? selectedIndex;
    if (normalizedPlanDate != null && normalizedPlanDate.isNotEmpty) {
      selectedIndex = indexByDate[normalizedPlanDate];
    } else {
      selectedIndex = firstHtmlSelectedIndex;
    }

    return List.unmodifiable([
      for (var i = 0; i < entries.length; i++)
        TimetableVersion(
          date: entries[i].date,
          label: entries[i].label,
          isSelected: i == selectedIndex,
        ),
    ]);
  }

  /// Extracts the "Stundenplan gültig ..." label from [planRoot], falling back
  /// to the selected version's label if the print-only span is omitted.
  static String? extractValidFrom(
    Element? planRoot, {
    List<TimetableVersion> versions = const [],
  }) {
    if (planRoot != null) {
      for (final span in planRoot.querySelectorAll('span')) {
        final t = _cleanText(span.text);
        if (t.startsWith('Stundenplan gültig')) {
          final rest = t.replaceFirst('Stundenplan gültig', '').trim();
          return rest.isEmpty ? t : rest;
        }
      }
    }
    for (final v in versions) {
      if (v.isSelected && v.label.isNotEmpty) return v.label;
    }
    return null;
  }

  static String _cleanText(String raw) =>
      raw.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
