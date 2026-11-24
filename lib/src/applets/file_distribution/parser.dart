import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';

import '../../cache/annotation.dart';
import '../../cache/types.dart';
import '../../exceptions.dart';
import '../../models/file_distribution.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';

part 'parser.g.dart';

class FileDistributionParser extends AppletParser<FileDistributionHome>
    with _$FileDistributionParserCache {
  static final Uri _base = Uri.parse(
    'https://start.schulportal.hessen.de/dateiverteilung.php',
  );
  static final DateFormat _germanDate = DateFormat('dd.MM.yyyy');
  static final RegExp _dateRangeRe = RegExp(
    r'(\d{2}\.\d{2}\.\d{4})\s*(?:bis|-)\s*(\d{2}\.\d{2}\.\d{4})',
  );
  static final RegExp _statusCountRe = RegExp(r'(\d+)\s*\(von\s*(\d+)\)');

  FileDistributionParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.fileDistribution,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  CacheRequest<FileDistributionHome> get homeCacheRequest =>
      FileDistributionParserCacheRequests.getHome();

  @override
  Future<MaybeCacheResult<FileDistributionHome>> loadCachedHome({
    CacheReadPolicy? policy,
  }) => cached.getHome(cachePolicy: policy);

  @Cacheable(
    operation: 'fileDistribution.home',
    applet: Applets.fileDistribution,
  )
  Future<FileDistributionHome> _getHome() => getHome();

  @override
  Future<FileDistributionHome> getHome() async {
    final response = await _get(_base);
    return parseHomeHtml(response.data.toString());
  }

  /// Marks a distribution as read (`POST a=user&b=read&v=<distributionId>`).
  Future<bool> markAsRead(int distributionId) async {
    final response = await _postForm({
      'a': 'user',
      'b': 'read',
      'v': '$distributionId',
    });
    return response.data?.toString().trim() == '1';
  }

  /// Builds the authenticated download URL for a distribution file.
  ///
  /// Pass the returned URL to `StorageManager.downloadFile(...)` or fetch it
  /// directly with `session.dio`.
  static Uri buildDownloadUrl(
    int distributionId,
    int fileIndex, {
    bool admin = false,
  }) {
    return _base.replace(
      queryParameters: {
        'a': admin ? 'admin' : 'user',
        'v': '$distributionId',
        'k': '$fileIndex',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tooladmin API
  // ---------------------------------------------------------------------------

  /// Lists all distributions from `GET dateiverteilung.php?a=admin`.
  Future<List<AdminFileDistributionSummary>> getAdminDistributions() async {
    final response = await _get(
      _base.replace(queryParameters: const {'a': 'admin'}),
    );
    final doc = parse(response.data.toString());
    _throwIfLoginPage(doc);
    if (doc.querySelector('#boards') == null) {
      throw NotSupportedException(
        'Account does not have Tooladmin access to dateiverteilung.php',
      );
    }
    return parseAdminListDocument(doc);
  }

  /// Fetches full JSON metadata via `POST a=admin&f=edit&v=<id>`.
  Future<AdminFileDistributionDetail> getAdminDistributionDetail(int id) async {
    final response = await _postForm({'a': 'admin', 'f': 'edit', 'v': '$id'});
    final raw = response.data;
    final dynamic decoded;
    if (raw is Map) {
      decoded = raw;
    } else {
      final text = raw.toString().trim();
      if (text.isEmpty) {
        throw UnknownException(
          'Empty admin detail response for distribution #$id',
        );
      }
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        _throwIfLoginPage(parse(text));
        throw UnknownException(
          'Invalid JSON in admin detail response for distribution #$id',
        );
      }
    }
    if (decoded is! Map) {
      throw UnknownException(
        'Unexpected admin detail response for distribution #$id',
      );
    }
    return parseAdminDetailJson(Map<String, dynamic>.from(decoded));
  }

  /// Fetches per-group retrieval statistics (`GET a=admin&f=chart&v=<id>`).
  Future<FileDistributionStats> getStatistics(int id) async {
    final response = await _get(
      _base.replace(queryParameters: {'a': 'admin', 'f': 'chart', 'v': '$id'}),
    );
    final doc = parse(response.data.toString());
    _throwIfLoginPage(doc);
    return parseStatisticsDocument(doc, distributionId: id);
  }

  /// Creates or updates a distribution (`POST a=admin&f=new&...`).
  /// Returns the distribution ID on success.
  Future<int> saveDistribution(FileDistributionDraft draft) async {
    final payload = <String, String>{
      'a': 'admin',
      'f': 'new',
      'Id': draft.id?.toString() ?? '',
      'Titel': draft.title,
      'Userart': draft.audience.portalValue,
      if (draft.gradeFrom != null) 'JahrgangsstufeVon': '${draft.gradeFrom}',
      if (draft.gradeUntil != null) 'JahrgangsstufeBis': '${draft.gradeUntil}',
      'Hinweis': draft.description,
      'Von': _germanDate.format(draft.validFrom),
      'Bis': _germanDate.format(draft.validUntil),
      'Einzeldatei': draft.mode.portalValue,
      'Dateinamenvorlage': draft.fileNameTemplate ?? '',
      'Startzahl': draft.startNumber?.toString() ?? '',
      'LinkUrl': draft.linkUrl?.toString() ?? '',
      'LinkTitel': draft.linkTitle ?? '',
    };
    final response = await _postForm(payload);
    final id = int.tryParse(response.data?.toString().trim() ?? '');
    if (id == null || id <= 0) {
      throw UnknownException(
        'Failed to save file distribution: ${response.data}',
      );
    }
    return id;
  }

  /// Uploads a file to a distribution (`POST multipart a=upload`).
  Future<bool> uploadFile(
    int distributionId, {
    required String fileName,
    required List<int> bytes,
  }) async {
    final formData = FormData.fromMap({
      'a': 'upload',
      'id': '$distributionId',
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await _request(
      () => ctx.session.dio.post(_base.toString(), data: formData),
    );
    return response.data?.toString().trim() == '1';
  }

  /// Deletes a distribution and its files/statistics (`POST a=admin&f=del`).
  Future<bool> deleteDistribution(int id) async {
    final response = await _postForm({'a': 'admin', 'f': 'del', 'v': '$id'});
    return response.data?.toString().trim() == '1';
  }

  Future<Response<dynamic>> _get(Uri uri) =>
      _request(() => ctx.session.dio.get(uri.toString()));

  Future<Response<dynamic>> _postForm(Map<String, String> data) => _request(
    () => ctx.session.dio.post(
      _base.toString(),
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    ),
  );

  Future<Response<dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    final Response<dynamic> response;
    try {
      response = await send();
    } on DioException catch (e, stack) {
      Error.throwWithStackTrace(NetworkException.fromError(e, stack), stack);
    }
    if (response.statusCode == 302 || _isAuthRedirect(response)) {
      throw UnauthorizedException('dateiverteilung.php request redirected');
    }
    if (response.data == null) {
      throw NetworkException('Empty response from dateiverteilung.php');
    }
    return response;
  }

  static bool _isAuthRedirect(Response<dynamic> response) {
    final location = response.headers.value('location') ?? '';
    if (location.contains('login.') || location.contains('index.php')) {
      return true;
    }
    final realUri = response.realUri;
    if (realUri.host.startsWith('login.') ||
        realUri.path.endsWith('/index.php')) {
      return true;
    }
    return false;
  }

  static void _throwIfLoginPage(Document document) {
    if (document.querySelector('input[type="password"], form[action*="login"]') !=
        null) {
      throw UnauthorizedException('Session expired: received login page');
    }
  }

  // ---------------------------------------------------------------------------
  // Static HTML / JSON parsers (testable without a session)
  // ---------------------------------------------------------------------------

  static FileDistributionHome parseHomeHtml(String html) =>
      parseHomeDocument(parse(html));

  static FileDistributionHome parseHomeDocument(Document document) {
    _throwIfLoginPage(document);
    if (document.querySelector('#content') == null) {
      throw UnknownException(
        'Unexpected dateiverteilung.php HTML: missing #content container',
      );
    }

    final isAdmin =
        document.querySelector('a[href*="dateiverteilung.php?a=admin"]') !=
        null;

    // Scope to `.panel.verteilung[data-id]` so Tooladmin sidebar `.verteilung`
    // entries inside `.panel-warning` are not mixed into recipient items.
    final cards = document.querySelectorAll('#content .panel.verteilung[data-id]');
    final items = <FileDistributionItem>[];
    for (final card in cards) {
      final parsed = _parseUserCard(card);
      if (parsed != null) items.add(parsed);
    }

    final sidebarCards = document.querySelectorAll(
      '#content .panel-warning .verteilung[data-id]',
    );
    final sidebarItems = <ToolAdminQuickDistribution>[];
    for (final block in sidebarCards) {
      final parsed = _parseAdminSidebarBlock(block);
      if (parsed != null) sidebarItems.add(parsed);
    }

    return FileDistributionHome(
      items: items,
      isAdmin: isAdmin,
      adminSidebarItems: sidebarItems,
    );
  }

  static FileDistributionItem? _parseUserCard(Element card) {
    final id = int.tryParse(card.attributes['data-id'] ?? '');
    if (id == null) return null;

    final heading = card.querySelector('.panel-heading.headline');
    final (validFrom, validUntil) = _parseDateRange(
      heading?.querySelector('small.pull-right')?.text ?? '',
    );
    final title = _extractCardTitle(heading);
    final isUnread = heading?.querySelector('.neu') != null;
    final canMarkAsRead = card.querySelector('.read') != null;

    final body = card.querySelector('.panel-body');
    final creatorSpan = body?.querySelector('small.pull-right span');
    final creatorName = _normalizeText(creatorSpan?.text);
    final description = _extractDescription(body);

    final footer = card.querySelector('.panel-footer');
    FileDistributionLink? infoLink;
    final linkEl = footer?.querySelector('a.btn-info[href]');
    if (linkEl != null) {
      final href = linkEl.attributes['href']?.trim() ?? '';
      final uri = Uri.tryParse(href);
      if (uri != null && href.isNotEmpty) {
        infoLink = FileDistributionLink(
          url: uri,
          title: _normalizeText(linkEl.text) ?? href,
        );
      }
    }

    final errorMessage = _normalizeText(
      footer?.querySelector('.label-danger')?.text,
    );

    final files = _parseFileEntries(
      footer,
      distributionId: id,
      admin: false,
      nestedButtonSelector: '.readAndDownload',
    );

    return FileDistributionItem(
      id: id,
      title: title,
      validFrom: validFrom,
      validUntil: validUntil,
      description: description,
      creatorName: creatorName,
      isUnread: isUnread,
      canMarkAsRead: canMarkAsRead,
      errorMessage: errorMessage,
      infoLink: infoLink,
      files: files,
    );
  }

  static ToolAdminQuickDistribution? _parseAdminSidebarBlock(Element block) {
    final id = int.tryParse(block.attributes['data-id'] ?? '');
    if (id == null) return null;

    final bold = block.querySelector('b');
    final audienceLabel = _normalizeText(bold?.querySelector('small')?.text);
    final title = _extractDirectText(bold) ?? '';

    final files = _parseFileEntries(block, distributionId: id, admin: true);

    return ToolAdminQuickDistribution(
      id: id,
      title: title,
      audienceLabel: audienceLabel,
      files: files,
    );
  }

  static List<FileDistributionFile> _parseFileEntries(
    Element? container, {
    required int distributionId,
    required bool admin,
    String? nestedButtonSelector,
  }) {
    if (container == null) return const [];
    final files = <FileDistributionFile>[];
    for (final multi in container.querySelectorAll('.verteilungmulti[data-id]')) {
      final k = int.tryParse(multi.attributes['data-id'] ?? '');
      if (k == null) continue;
      final target = nestedButtonSelector != null
          ? multi.querySelector(nestedButtonSelector)
          : multi;
      final rawTitle = target?.attributes['title']?.trim();
      final name = (rawTitle != null && rawTitle.isNotEmpty)
          ? rawTitle
          : (_normalizeText(target?.text) ?? '');
      if (name.isEmpty) continue;
      files.add(
        FileDistributionFile(
          index: k,
          name: name,
          downloadUrl: buildDownloadUrl(distributionId, k, admin: admin),
          isTemplate: target?.attributes['data-is-template'] == '1',
        ),
      );
    }
    return files;
  }

  static List<AdminFileDistributionSummary> parseAdminListHtml(String html) =>
      parseAdminListDocument(parse(html));

  static List<AdminFileDistributionSummary> parseAdminListDocument(
    Document document,
  ) {
    final rows = document.querySelectorAll('#boards tbody tr.verteilung');
    final results = <AdminFileDistributionSummary>[];
    for (final row in rows) {
      final id = int.tryParse(row.attributes['data-itemid'] ?? '');
      if (id == null) continue;
      final cells = row.querySelectorAll('td');
      if (cells.length < 8) continue;

      final title = _normalizeText(cells[0].text) ?? '';
      final (validFrom, validUntil) = _parseDateRange(cells[1].text);
      final audienceLabel = _normalizeText(cells[2].text) ?? '';
      final mode = DistributionMode.fromPortalValue(cells[3].text);

      var distributed = 0;
      var total = 0;
      final statusMatch = _statusCountRe.firstMatch(cells[4].text);
      if (statusMatch != null) {
        distributed = int.tryParse(statusMatch.group(1)!) ?? 0;
        total = int.tryParse(statusMatch.group(2)!) ?? 0;
      }

      final files = _parseFileEntries(
        cells[5],
        distributionId: id,
        admin: true,
      );
      final filesAvailable = cells[5].querySelector('.label-info') != null;

      final creatorSpan = cells[6].querySelector('span');
      final creatorShortName = _normalizeText(creatorSpan?.text);
      final creatorTitle = creatorSpan?.attributes['title']?.trim();
      final creatorName = creatorTitle?.replaceFirst(
        RegExp(r'^Erstellt durch\s+', caseSensitive: false),
        '',
      );

      final canUpload =
          cells[7].querySelector('[data-action="upload"]') != null;

      results.add(
        AdminFileDistributionSummary(
          id: id,
          title: title,
          validFrom: validFrom,
          validUntil: validUntil,
          audienceLabel: audienceLabel,
          mode: mode,
          distributedCount: distributed,
          totalRecipients: total,
          files: files,
          filesAvailable: filesAvailable,
          creatorName: creatorName,
          creatorShortName: creatorShortName,
          canUpload: canUpload,
        ),
      );
    }
    return results;
  }

  static AdminFileDistributionDetail parseAdminDetailJson(
    Map<String, dynamic> json,
  ) {
    final user = json['Userarray'] is Map
        ? Map<String, dynamic>.from(json['Userarray'] as Map)
        : null;
    final firstName = user?['Vorname']?.toString().trim() ?? '';
    final lastName = user?['Nachname']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();

    final linkUrlStr = json['LinkUrl']?.toString().trim() ?? '';
    final linkUri = linkUrlStr.isNotEmpty ? Uri.tryParse(linkUrlStr) : null;
    final linkTitle = json['LinkTitel']?.toString().trim() ?? '';

    final rawTemplates = json['Dateinamenvorlage'];
    final templates = <String>[];
    if (rawTemplates is List) {
      for (final t in rawTemplates) {
        if (t != null && t.toString().trim().isNotEmpty) {
          templates.add(t.toString().trim());
        }
      }
    } else if (rawTemplates is String && rawTemplates.trim().isNotEmpty) {
      templates.add(rawTemplates.trim());
    }

    final id = int.tryParse(json['Id']?.toString() ?? '');
    if (id == null) {
      throw UnknownException(
        'Missing or invalid Id in file distribution detail JSON',
      );
    }

    return AdminFileDistributionDetail(
      id: id,
      title: json['Titel']?.toString() ?? '',
      description: json['Hinweis']?.toString() ?? '',
      validFrom: _parseGermanDate(json['Von']?.toString()),
      validUntil: _parseGermanDate(json['Bis']?.toString()),
      filesDeleteAt: _parseIsoOrSqlDateTime(
        json['LoeschungDerDateien']?.toString(),
      ),
      audience: DistributionAudience.fromPortalValue(
        json['Userart']?.toString() ?? '',
      ),
      gradeFrom: int.tryParse(json['JahrgangsstufeVon']?.toString() ?? ''),
      gradeUntil: int.tryParse(json['JahrgangsstufeBis']?.toString() ?? ''),
      mode: DistributionMode.fromPortalValue(
        json['Einzeldatei']?.toString() ?? '',
      ),
      fileNameTemplates: templates,
      startNumber: int.tryParse(json['Startzahl']?.toString() ?? ''),
      infoLink: linkUri != null
          ? FileDistributionLink(
              url: linkUri,
              title: linkTitle.isNotEmpty ? linkTitle : linkUrlStr,
            )
          : null,
      fileCount: int.tryParse(json['Anzahl']?.toString() ?? '') ?? 0,
      consumedCount: int.tryParse(json['verbraucht']?.toString() ?? '') ?? 0,
      createdAt: _parseIsoOrSqlDateTime(json['Erstellt']?.toString()),
      creatorId: json['Ersteller']?.toString(),
      creatorName: fullName.isNotEmpty ? fullName : null,
      creatorShortName: user?['Kuerzel']?.toString().trim(),
    );
  }

  static FileDistributionStats parseStatisticsHtml(
    String html, {
    required int distributionId,
  }) => parseStatisticsDocument(parse(html), distributionId: distributionId);

  static FileDistributionStats parseStatisticsDocument(
    Document doc, {
    required int distributionId,
  }) {
    final rawHeading = _normalizeText(doc.querySelector('#content h2')?.text) ?? '';
    final title = rawHeading.replaceFirst(RegExp(r'\s*\(#\d+\)\s*$'), '').trim();

    final groups = <FileDistributionGroupStat>[];
    FileDistributionGroupStat? total;

    for (final row in doc.querySelectorAll('#content table tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;
      final group = _normalizeText(cells[0].text) ?? '';
      final retrieved = int.tryParse(cells[1].text.trim()) ?? 0;
      final pending = int.tryParse(cells[2].text.trim()) ?? 0;
      final pctStr = cells[3].text.trim().replaceAll('%', '').replaceAll(',', '.');
      final pct = double.tryParse(pctStr) ?? 0.0;
      final stat = FileDistributionGroupStat(
        group: group,
        retrieved: retrieved,
        pending: pending,
        completionPercent: pct,
      );
      if (group.toLowerCase() == 'summe') {
        total = stat;
      } else {
        groups.add(stat);
      }
    }

    return FileDistributionStats(
      distributionId: distributionId,
      title: title,
      groups: groups,
      total: total,
    );
  }

  @override
  FileDistributionHome typeFromJson(String json) {
    return FileDistributionHome.fromJson(
      Map<String, dynamic>.from(jsonDecode(json) as Map),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _extractCardTitle(Element? heading) {
    if (heading == null) return '';
    return _extractDirectText(heading) ?? '';
  }

  static String? _extractDirectText(Element? element) {
    if (element == null) return null;
    final buffer = StringBuffer();
    for (final node in element.nodes) {
      if (node.nodeType == Node.TEXT_NODE) {
        buffer.write(node.text);
      }
    }
    return _normalizeText(buffer.toString());
  }

  static String? _extractDescription(Element? body) {
    if (body == null) return null;
    final clone = body.clone(true);
    for (final small in clone.querySelectorAll('small.pull-right')) {
      small.remove();
    }
    // Preserve intentional line breaks from <br> while normalizing extra spaces.
    for (final br in clone.querySelectorAll('br')) {
      br.replaceWith(Text('\n'));
    }
    final lines = clone.text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .toList();
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    final joined = lines.join('\n').trim();
    return joined.isEmpty ? null : joined;
  }

  static (DateTime?, DateTime?) _parseDateRange(String text) {
    final match = _dateRangeRe.firstMatch(text);
    if (match == null) return (null, null);
    return (_parseGermanDate(match.group(1)), _parseGermanDate(match.group(2)));
  }

  static DateTime? _parseGermanDate(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static DateTime? _parseIsoOrSqlDateTime(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
  }

  static String? _normalizeText(String? raw) {
    if (raw == null) return null;
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }
}
