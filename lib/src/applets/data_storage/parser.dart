import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:intl/intl.dart';
import '../../exceptions.dart';
import '../../models/datastorage.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';

class DataStorageParser
    extends AppletParser<(List<FileNode>, List<FolderNode>)> {
  static final RegExp _intRe = RegExp(r'\d+');
  static final RegExp _sizeRe = RegExp(
    r'^([\d.,]+)\s*(B|KB|MB|GB|TB)$',
    caseSensitive: false,
  );
  static final RegExp _hiddenStyleRe = RegExp(
    r'(?:visibility\s*:\s*hidden|display\s*:\s*none)',
    caseSensitive: false,
  );
  static final RegExp _hexColorRe = RegExp(
    r'(?:^|[;\s])(?:border-)?color\s*:\s*(#[0-9a-fA-F]{3,8})',
    caseSensitive: false,
  );
  static final List<DateFormat> _modifiedFormats = [
    DateFormat('dd.MM.yyyy HH:mm:ss'),
    DateFormat('dd.MM.yyyy HH:mm'),
    DateFormat('dd.MM.yyyy'),
  ];

  DataStorageParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.dataStorage,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  Future<(List<FileNode>, List<FolderNode>)> getHome() {
    return getRoot();
  }

  Future<dynamic> searchFiles(String query) async {
    if (query.trim().length < 2) {
      return const <dynamic>[];
    }
    final Response<dynamic> response;
    try {
      response = await ctx.session.dio.get(
        'https://start.schulportal.hessen.de/dateispeicher.php',
        queryParameters: {'q': query, 'a': 'searchFiles'},
      );
    } on DioException catch (e, stack) {
      Error.throwWithStackTrace(NetworkException.fromError(e, stack), stack);
    }
    if (response.statusCode == 302) {
      throw UnauthorizedException('Data storage search redirected');
    }
    final dynamic data;
    if (response.data is List || response.data is Map) {
      data = response.data;
    } else {
      final body = response.data?.toString() ?? '';
      if (body.trim().isEmpty) {
        throw UnknownException('Empty data storage search response');
      }
      data = jsonDecode(body);
    }
    if (data is Map &&
        data['id'] == 0 &&
        data['text'] is String &&
        (data['text'] as String).contains('mindestens zwei Zeichen')) {
      return const <dynamic>[];
    }
    if (data is! List) {
      throw UnknownException('Unexpected data storage search response');
    }
    if (data.isEmpty) return const <dynamic>[];
    if (data[0] is! List) {
      throw UnknownException('Unexpected data storage search results');
    }
    return data[0];
  }

  /// Fetches and parses the full [DataStorageNode] (files, folders,
  /// breadcrumbs, recent files sidebar, and admin flag) for [nodeID].
  Future<DataStorageNode> getNodeDetails(int nodeID) async {
    final Response<dynamic> response;
    try {
      response = await ctx.session.dio.get(
        'https://start.schulportal.hessen.de/dateispeicher.php?a=view&folder=$nodeID',
      );
    } on DioException catch (e, stack) {
      Error.throwWithStackTrace(NetworkException.fromError(e, stack), stack);
    } catch (_) {
      throw NoConnectionException();
    }
    if (response.statusCode == 302) {
      throw UnauthorizedException('Data storage view redirected');
    }
    return parseNodeHtml(response.data?.toString() ?? '', fallbackNodeId: nodeID);
  }

  /// Convenience wrapper around [getNodeDetails] for the root folder (`0`).
  Future<DataStorageNode> getRootDetails() => getNodeDetails(0);

  /// Parses raw `dateispeicher.php?a=view&folder=<id>` HTML into a [DataStorageNode].
  static DataStorageNode parseNodeHtml(String html, {int fallbackNodeId = 0}) {
    final document = parse(html);

    final heading = document.querySelector('#content h1[data-folder]') ??
        document.querySelector('h1[data-folder]') ??
        document.querySelector('#content h1');
    final nodeId =
        int.tryParse(heading?.attributes['data-folder']?.trim() ?? '') ??
        fallbackNodeId;

    final breadcrumbs = _parseBreadcrumbs(document);
    final headingName = _extractHeadingName(heading);
    final nodeName = headingName.isNotEmpty
        ? headingName
        : (breadcrumbs.isNotEmpty ? breadcrumbs.last.name : '');

    final files = _parseFiles(document, nodeId);
    final folders = _parseFolders(document);
    final newFiles = _parseNewFiles(document);
    final canAdminView = document.querySelector('#adminView') != null;

    return DataStorageNode(
      id: nodeId,
      name: nodeName,
      breadcrumbs: breadcrumbs,
      files: files,
      folders: folders,
      newFiles: newFiles,
      canAdminView: canAdminView,
    );
  }

  Future<(List<FileNode>, List<FolderNode>)> getNode(int nodeID) async {
    final node = await getNodeDetails(nodeID);
    return (node.files, node.folders);
  }

  Future<(List<FileNode>, List<FolderNode>)> getRoot() async {
    return await getNode(0);
  }

  static List<FolderBreadcrumb> _parseBreadcrumbs(Document document) {
    final result = <FolderBreadcrumb>[];
    for (final link in document.querySelectorAll('ol.breadcrumb li a[data-dir]')) {
      final id = int.tryParse(link.attributes['data-dir']?.trim() ?? '');
      final name = link.text.trim();
      if (id != null && name.isNotEmpty) {
        result.add(FolderBreadcrumb(id: id, name: name));
      }
    }
    return result;
  }

  static String _extractHeadingName(Element? heading) {
    if (heading == null) return '';
    final buffer = StringBuffer();
    for (final node in heading.nodes) {
      if (node.nodeType == Node.TEXT_NODE) {
        buffer.write(node.text ?? '');
      }
    }
    return buffer.toString().trim();
  }

  static List<FileNode> _parseFiles(Document document, int nodeId) {
    final files = <FileNode>[];
    final headers = document
        .querySelectorAll('table#files thead th')
        .map((e) => e.text.trim())
        .toList();
    final nameIdx = headers.indexOf('Name');
    final aenderungIdx = headers.indexOf('Änderung');
    final groesseIdx = headers.indexOf('Größe');

    for (final file in document.querySelectorAll('table#files tbody tr')) {
      final id = int.tryParse(file.attributes['data-id']?.trim() ?? '');
      if (id == null) continue;

      final fields = file.querySelectorAll('td');
      final nameCell =
          nameIdx >= 0 && nameIdx < fields.length ? fields[nameIdx] : null;
      final rawHinweis = nameCell?.querySelector('small')?.text.trim();
      final hinweis =
          rawHinweis != null && rawHinweis.isNotEmpty ? rawHinweis : null;

      String name = file.attributes['data-name']?.trim() ?? '';
      if (name.isEmpty && nameCell != null) {
        if (rawHinweis != null) {
          nameCell.querySelector('small')?.text = '';
        }
        name = nameCell.text.trim();
      }

      final aenderung = aenderungIdx >= 0 && aenderungIdx < fields.length
          ? fields[aenderungIdx].text.trim()
          : '';
      final groesse = groesseIdx >= 0 && groesseIdx < fields.length
          ? fields[groesseIdx].text.trim()
          : '';
      final rawExt = file.attributes['data-ext']?.trim();
      final extension = rawExt != null && rawExt.isNotEmpty ? rawExt : null;

      files.add(
        FileNode(
          name: name,
          id: id,
          folderID: nodeId,
          downloadUrl:
              'https://start.schulportal.hessen.de/dateispeicher.php?a=download&f=$id',
          aenderung: aenderung,
          groesse: groesse,
          hinweis: hinweis,
          extension: extension,
          modifiedAt: _parseModifiedAt(aenderung),
          sizeBytes: _parseSizeBytes(groesse),
        ),
      );
    }
    return files;
  }

  static List<FolderNode> _parseFolders(Document document) {
    final folders = <FolderNode>[];
    for (final folder in document.querySelectorAll('.folder')) {
      final id = int.tryParse(folder.attributes['data-id']?.trim() ?? '');
      if (id == null) continue;

      final attrName = folder.attributes['data-name']?.trim() ?? '';
      final name = attrName.isNotEmpty
          ? attrName
          : (folder.querySelector('.caption')?.text.trim() ?? '');
      final desc = folder.querySelector('.desc')?.text.trim() ?? '';
      final subfolders = _parseCount(
            folder.querySelector('[title="Anzahl Ordner"]')?.text,
          ) ??
          0;
      final fileCount = _parseFolderFileCount(folder);
      final colorHex = _parseColorHex(folder);
      final wx = folder
          .querySelector('a[data-wx]')
          ?.attributes['data-wx']
          ?.trim()
          .toLowerCase();
      final canWrite = wx == 'yes' || wx == '1' || wx == 'true';

      folders.add(
        FolderNode(
          name,
          id,
          subfolders,
          desc,
          fileCount: fileCount,
          colorHex: colorHex,
          canWrite: canWrite,
        ),
      );
    }
    return folders;
  }

  static List<FileNode> _parseNewFiles(Document document) {
    final result = <FileNode>[];
    final seenIds = <int>{};
    for (final row in document.querySelectorAll('table tbody tr[data-id]')) {
      if (row.querySelector('.new_download') == null) continue;
      final id = int.tryParse(row.attributes['data-id']?.trim() ?? '');
      if (id == null || !seenIds.add(id)) continue;

      final rawExt = row.attributes['data-ext']?.trim();
      final extension = rawExt != null && rawExt.isNotEmpty ? rawExt : null;
      final rawHinweis = row.querySelector('small')?.text.trim();
      final hinweis =
          rawHinweis != null && rawHinweis.isNotEmpty ? rawHinweis : null;

      String name = row.attributes['data-name']?.trim() ?? '';
      if (name.isEmpty) {
        final cells = row.querySelectorAll('td.new_download');
        if (cells.isNotEmpty) {
          final textCell = cells.last;
          final buffer = StringBuffer();
          for (final node in textCell.nodes) {
            if (node.nodeType == Node.TEXT_NODE) {
              buffer.write(node.text ?? '');
            }
          }
          name = buffer.toString().trim();
        }
      }

      result.add(
        FileNode(
          name: name,
          id: id,
          downloadUrl:
              'https://start.schulportal.hessen.de/dateispeicher.php?a=download&f=$id',
          hinweis: hinweis,
          extension: extension,
        ),
      );
    }
    return result;
  }

  static int? _parseCount(String? text) {
    if (text == null) return null;
    final match = _intRe.firstMatch(text.trim());
    return match != null ? int.tryParse(match.group(0)!) : null;
  }

  static int? _parseFolderFileCount(Element folder) {
    final byTitleEl = folder.querySelector('[title="Anzahl Dateien"]');
    if (byTitleEl != null && !_isHidden(byTitleEl)) {
      final parsedByTitle = _parseCount(byTitleEl.text);
      if (parsedByTitle != null) return parsedByTitle;
    }

    for (final label in folder.querySelectorAll('.label')) {
      if (_isHidden(label)) continue;
      final text = label.text.trim();
      if (text.toLowerCase().contains('keine dateien')) return 0;
      if (text.toLowerCase().contains('datei')) {
        final count = _parseCount(text);
        if (count != null) return count;
      }
    }
    return null;
  }

  static bool _isHidden(Element element) {
    final style = element.attributes['style'];
    return style != null && _hiddenStyleRe.hasMatch(style);
  }

  static int? _parseSizeBytes(String raw) {
    final match = _sizeRe.firstMatch(raw.trim());
    if (match == null) return null;
    final rawNum = match.group(1)!;
    final normalized = rawNum.contains(',')
        ? rawNum.replaceAll('.', '').replaceAll(',', '.')
        : rawNum;
    final value = double.tryParse(normalized);
    if (value == null) return null;
    final multiplier = switch (match.group(2)!.toUpperCase()) {
      'B' => 1,
      'KB' => 1024,
      'MB' => 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (value * multiplier).round();
  }

  static String? _parseColorHex(Element folder) {
    final folderStyle = folder.attributes['style'];
    if (folderStyle != null) {
      final match = _hexColorRe.firstMatch(folderStyle);
      if (match != null) return match.group(1)!.toLowerCase();
    }
    final linkStyle = folder.querySelector('.caption a')?.attributes['style'];
    if (linkStyle != null) {
      final match = _hexColorRe.firstMatch(linkStyle);
      if (match != null) return match.group(1)!.toLowerCase();
    }
    return null;
  }

  static DateTime? _parseModifiedAt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    for (final format in _modifiedFormats) {
      try {
        return format.parseStrict(trimmed);
      } catch (_) {}
    }
    return null;
  }
}
