import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;

  @override
  Future<bool> get connected async => true;
}

class _SearchAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  int statusCode = 200;
  String body = '[[],[]]';
  String contentType = 'application/json';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _SearchAdapter adapter;
  late LanisDatabase database;
  late LanisSession session;
  late DataStorageParser parser;

  setUp(() async {
    adapter = _SearchAdapter();
    database = LanisDatabase.open();
    const account = ClearTextAccount(
      localId: 1,
      schoolID: 1,
      username: 'test',
      password: 'test',
      schoolName: 'Test',
      accountType: AccountType.student,
    );
    session = LanisSession(
      account: account,
      config: LanisConfig(httpAdapter: adapter),
      connectionChecker: _OnlineChecker(),
    );
    await session.prepareDio();
    parser = DataStorageParser(
      AppletContext(
        session: session,
        database: database,
        account: account,
        accountSettings: TypedSettings.account(database, 1),
      ),
      isConnected: () async => true,
    );
  });

  tearDown(() async {
    parser.dispose();
    await session.dispose();
    session.connectionChecker.dispose();
    database.dispose();
  });

  test('searchFiles sends a bodyless GET request and returns first result list', () async {
    adapter.body = jsonEncode([
      [
        {'id': '42', 'text': 'undraw-work-chat-hc3y.svg'},
      ],
    ]);

    final results = await parser.searchFiles('undraw');

    expect(adapter.lastOptions?.method, 'GET');
    expect(adapter.lastOptions?.data, isNull);
    expect(adapter.lastOptions?.queryParameters, {
      'q': 'undraw',
      'a': 'searchFiles',
    });
    expect(results, [
      {'id': '42', 'text': 'undraw-work-chat-hc3y.svg'},
    ]);
  });

  test('searchFiles maps 302 redirect to UnauthorizedException', () async {
    adapter.statusCode = 302;
    adapter.body = '';
    await expectLater(
      parser.searchFiles('test'),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('searchFiles rejects unexpected JSON object payloads', () async {
    adapter.statusCode = 200;
    adapter.body = jsonEncode({'error': 'unexpected'});
    await expectLater(
      parser.searchFiles('test'),
      throwsA(isA<UnknownException>()),
    );
  });

  test('searchFiles returns empty list without requesting for queries under 2 chars', () async {
    expect(await parser.searchFiles(''), isEmpty);
    expect(await parser.searchFiles('a'), isEmpty);
    expect(adapter.lastOptions, isNull);
  });

  test('searchFiles returns empty list for server short-query response', () async {
    adapter.statusCode = 200;
    adapter.body = jsonEncode({
      'id': 0,
      'text': 'Bitte mindestens zwei Zeichen eingeben!',
    });
    expect(await parser.searchFiles('ab'), isEmpty);
  });

  test('searchFiles rejects unrelated id:0 JSON error objects', () async {
    adapter.statusCode = 200;
    adapter.body = jsonEncode({'id': 0, 'text': 'Zugriff verweigert'});
    await expectLater(
      parser.searchFiles('ab'),
      throwsA(isA<UnknownException>()),
    );
  });

  test('searchFiles returns empty list for empty array response', () async {
    adapter.statusCode = 200;
    adapter.body = '[[]]';
    expect(await parser.searchFiles('test'), isEmpty);
  });

  group('getNodeDetails & parseNodeHtml', () {
    const rootHtml = '''
<div id="content">
  <h1 data-folder="0">
    <i class="fa fa-folder-open"></i>
    Start
    <small><span class="fas fa-file-contract"></span> Dateispeicher</small>
  </h1>
  <ol class="breadcrumb">
    Ordner:
    <li><a href="#" data-dir="0"><i class="fa fa-folder-open"></i> Start</a></li>
  </ol>
  <div class="row">
    <div class="col-md-9">
      <div class="row dateispeicher-grid">
        <div class="col-md-4">
          <div class="thumbnail folder" data-id="27" data-name="Test" style="border-color: #1A2B3C;">
            <div class="caption">
              <h3><a href="#" data-dir="27" data-wx="yes" style="color: #1A2B3C;"><i class="far fa-folder"></i> Test</a></h3>
            </div>
            <p class="desc"><small>Nur ein test...</small></p>
            <div class="row">
              <div class="col-md-12">
                <small>
                  <span class="label label-info" title="Anzahl Ordner"><i class="far fa-folder"></i> 2 Ordner</span>
                  <span class="label label-info" title="Anzahl Dateien">3 Dateien</span>
                </small>
              </div>
            </div>
          </div>
        </div>
      </div>
      <table class="table" id="files">
        <thead>
          <tr>
            <th>#</th>
            <th></th>
            <th>Name</th>
            <th>Änderung</th>
            <th>Größe</th>
            <th>Optionen</th>
          </tr>
        </thead>
        <tbody>
          <tr data-id="381514" data-ext="svg" data-name="undraw-work-chat-hc3y.svg">
            <td>1</td>
            <td class="download"><i class="fa fa-file-o"></i></td>
            <td class="download">undraw-work-chat-hc3y.svg<br><small>Hinweis text</small></td>
            <td>30.06.2025 12:03:01</td>
            <td class="text-right">14,86 KB</td>
            <td></td>
          </tr>
        </tbody>
      </table>
    </div>
    <div class="col-md-3">
      <div class="thumbnail">
        <div class="caption"><h4 class="label label-danger">Neue Dateien</h4></div>
        <table class="table">
          <tbody>
            <tr data-id="538091" data-ext="png" data-name="Screenshot.png">
              <td class="download new_download"><i class="far fa-file-image"></i></td>
              <td class="download new_download">Screenshot.png<br><small>Im Ordner Test</small></td>
            </tr>
            <tr data-id="538090" data-ext="txt" data-name="merkblatt.txt">
              <td class="download new_download"><i class="far fa-file-text"></i></td>
              <td class="download new_download">merkblatt.txt<br><small></small></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
''';

    const nestedTeacherHtml = '''
<div id="content">
  <h1 data-folder="28">
    <i class="fa fa-folder-open"></i>
    test_dir2
    <small><span class="fas fa-file-contract"></span> Dateispeicher</small>
  </h1>
  <a href="dateispeicher.php?a=view&amp;folder=28&amp;admin=1" class="btn btn-default" id="adminView" data-admin="0">
    Admin-Ansicht
  </a>
  <ol class="breadcrumb">
    Ordner:
    <li><a href="#" data-dir="0"><i class="far fa-folder"></i> Start</a></li>
    <li><a href="#" data-dir="27"><i class="far fa-folder"></i> Test</a></li>
    <li><a href="#" data-dir="28"><i class="far fa-folder"></i> test_dir2</a></li>
  </ol>
  <div class="row dateispeicher-grid">
    <div class="col-md-4">
      <div class="thumbnail folder" data-id="29" data-name="Empty Folder" style="border-color: #000000;">
        <div class="caption">
          <h3><a href="#" data-dir="29" data-wx="no" style="color: #000000;">Empty Folder</a></h3>
        </div>
        <p class="desc"><small></small></p>
        <div class="row">
          <div class="col-md-12">
            <small><span style="visibility:hidden" class="label label-info">Keine Dateien</span></small>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
''';

    test('parseNodeHtml extracts root folders, files, breadcrumbs, and newFiles', () {
      final node = DataStorageParser.parseNodeHtml(rootHtml);

      expect(node.id, 0);
      expect(node.name, 'Start');
      expect(node.canAdminView, isFalse);
      expect(node.breadcrumbs, [const FolderBreadcrumb(id: 0, name: 'Start')]);
      expect(node.parentBreadcrumbs, isEmpty);

      expect(node.folders, hasLength(1));
      final folder = node.folders.single;
      expect(folder.id, 27);
      expect(folder.name, 'Test');
      expect(folder.desc, 'Nur ein test...');
      expect(folder.subfolders, 2);
      expect(folder.fileCount, 3);
      expect(folder.colorHex, '#1a2b3c');
      expect(folder.canWrite, isTrue);

      expect(node.files, hasLength(1));
      final file = node.files.single;
      expect(file.id, 381514);
      expect(file.folderID, 0);
      expect(file.name, 'undraw-work-chat-hc3y.svg');
      expect(file.extension, 'svg');
      expect(file.fileExtension, 'svg');
      expect(file.hinweis, 'Hinweis text');
      expect(file.groesse, '14,86 KB');
      expect(file.sizeBytes, (14.86 * 1024).round());
      expect(file.aenderung, '30.06.2025 12:03:01');
      expect(file.modifiedAt, DateTime(2025, 6, 30, 12, 3, 1));

      expect(node.newFiles, hasLength(2));
      expect(node.newFiles[0].id, 538091);
      expect(node.newFiles[0].name, 'Screenshot.png');
      expect(node.newFiles[0].extension, 'png');
      expect(node.newFiles[0].hinweis, 'Im Ordner Test');
      expect(node.newFiles[1].id, 538090);
      expect(node.newFiles[1].hinweis, isNull);
    });

    test('parseNodeHtml extracts nested breadcrumbs, parentBreadcrumbs, and admin flag', () {
      final node = DataStorageParser.parseNodeHtml(nestedTeacherHtml, fallbackNodeId: 28);

      expect(node.id, 28);
      expect(node.name, 'test_dir2');
      expect(node.canAdminView, isTrue);
      expect(node.breadcrumbs, const [
        FolderBreadcrumb(id: 0, name: 'Start'),
        FolderBreadcrumb(id: 27, name: 'Test'),
        FolderBreadcrumb(id: 28, name: 'test_dir2'),
      ]);
      expect(node.parentBreadcrumbs, const [
        FolderBreadcrumb(id: 0, name: 'Start'),
        FolderBreadcrumb(id: 27, name: 'Test'),
      ]);
      expect(node.files, isEmpty);
      expect(node.newFiles, isEmpty);
      expect(node.folders, hasLength(1));
      expect(node.folders.single.subfolders, 0);
      expect(node.folders.single.fileCount, isNull);
      expect(node.folders.single.canWrite, isFalse);
      expect(node.folders.single.colorHex, '#000000');
    });

    test('getNodeDetails fetches HTML and getNode remains backwards-compatible', () async {
      adapter.statusCode = 200;
      adapter.contentType = 'text/html; charset=utf-8';
      adapter.body = rootHtml;

      final details = await parser.getNodeDetails(0);
      expect(details.breadcrumbs, hasLength(1));
      expect(details.files, hasLength(1));
      expect(details.folders, hasLength(1));

      final (files, folders) = await parser.getNode(0);
      expect(files, hasLength(1));
      expect(folders, hasLength(1));
    });

    test('getNodeDetails maps 302 redirect to UnauthorizedException', () async {
      adapter.statusCode = 302;
      adapter.body = '';
      await expectLater(
        parser.getNodeDetails(27),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('parseNodeHtml ignores background-color and handles dot-decimal sizes', () {
      const edgeHtml = '''
<div id="content">
  <h1 data-folder="1">Edge</h1>
  <div class="thumbnail folder" data-id="2" data-name="Colored" style="background-color: #ffffff; border-color: #1565c0;">
    <div class="caption"><h3><a href="#" data-dir="2">Colored</a></h3></div>
  </div>
  <table id="files">
    <thead><tr><th>Name</th><th>Änderung</th><th>Größe</th></tr></thead>
    <tbody>
      <tr data-id="10" data-ext="txt" data-name="a.txt">
        <td>a.txt</td><td>26.11.2026</td><td>14.86 KB</td>
      </tr>
      <tr data-id="11" data-ext="txt" data-name="b.txt">
        <td>b.txt</td><td>26.11.2026</td><td>1.234,50 KB</td>
      </tr>
    </tbody>
  </table>
</div>
''';
      final node = DataStorageParser.parseNodeHtml(edgeHtml);
      expect(node.folders.single.colorHex, '#1565c0');
      expect(node.files[0].sizeBytes, (14.86 * 1024).round());
      expect(node.files[1].sizeBytes, (1234.5 * 1024).round());
    });
  });
}
