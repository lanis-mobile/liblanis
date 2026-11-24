import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:liblanis/easy_client.dart';
import 'package:test/test.dart';

class _OnlineChecker extends ConnectionChecker {
  @override
  Future<bool> testConnection() async => true;

  @override
  Future<bool> get connected async => true;
}

class _StubAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  int statusCode = 200;
  String body = '';
  Map<String, List<String>> headers = {
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
  };
  Object? errorToThrow;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return ResponseBody.fromString(body, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('FileDistributionParser.parseHomeHtml', () {
    test('parses empty state for non-admin account', () {
      const html = '''
        <div id="content">
          <h1><span class="fa fa-files-o"></span> Dateiverteilung</h1>
          <div class="alert alert-error" role="alert">
            Derzeit stehen für diesen Account keine Dateien zum Download zur Verfügung.
          </div>
        </div>
      ''';

      final home = FileDistributionParser.parseHomeHtml(html);
      expect(home.isAdmin, isFalse);
      expect(home.items, isEmpty);
      expect(home.adminSidebarItems, isEmpty);
    });

    test('parses unread, read, multi-file, link, and error cards', () {
      const html = '''
        <div id="content">
          <div class="panel panel-primary verteilung" data-id="1">
            <div class="panel-heading headline">
              <small class="pull-right"><i class="fa fa-calendar"></i>24.11.2026 bis 01.12.2026</small>
              <i class="fa fa-file fa-fw"></i> Elternbrief Herbst
              <div class="neu">
                <span class="label label-danger"><i class="fa fa-star"></i> Neu</span>
                <span class="label label-default hidden read"><i class="fa fa-check"></i> als gelesen markieren</span>
              </div>
            </div>
            <div class="panel-body">
              Hallo Elisa Bauer.<br />Bitte lesen.
              <br /><br />
              <small class="pull-right"><i><span title="Erstellt durch alessio caputo"><i class="fa fa-user"></i> alessio caputo</span></i></small>
            </div>
            <div class="panel-footer">
              <a href="https://example.org/info" class="btn btn-info"><i class="fa fa-external-link fa-fw"></i> Weitere Infos</a>
              <p class="verteilungmulti" data-id="0">
                <button class="btn btn-primary readAndDownload" data-is-template="1" title="elternbrief.pdf">
                  <i class="fa fa-download fa-fw"></i> elternbrief.pdf
                </button>
              </p>
              <p class="verteilungmulti" data-id="1">
                <button class="btn btn-primary readAndDownload" data-is-template="1" title="anlage.txt">
                  <i class="fa fa-download fa-fw"></i> anlage.txt
                </button>
              </p>
            </div>
          </div>

          <div class="panel panel-primary verteilung" data-id="2">
            <div class="panel-heading headline">
              <small class="pull-right"><i class="fa fa-calendar"></i>24.11.2026 bis 01.12.2026</small>
              <i class="fa fa-file fa-fw"></i> Bereits gelesen
            </div>
            <div class="panel-body">
              Kurze Mitteilung.
              <small class="pull-right"><i><span>alessio caputo</span></i></small>
            </div>
            <div class="panel-footer"></div>
          </div>

          <div class="panel panel-primary verteilung" data-id="3">
            <div class="panel-heading headline">
              <small class="pull-right"><i class="fa fa-calendar"></i>24.11.2026 bis 01.12.2026</small>
              <i class="fa fa-file fa-fw"></i> Fehlende Vorlage
              <div class="neu">
                <span class="label label-danger"><i class="fa fa-star"></i> Neu</span>
              </div>
            </div>
            <div class="panel-body">
              Zugangscode
            </div>
            <div class="panel-footer">
              <span class="label label-danger">Dateivorlage fehlt oder Dateiname falsch</span>
            </div>
          </div>
        </div>
      ''';

      final home = FileDistributionParser.parseHomeHtml(html);
      expect(home.isAdmin, isFalse);
      expect(home.items, hasLength(3));

      final first = home.items[0];
      expect(first.id, 1);
      expect(first.title, 'Elternbrief Herbst');
      expect(first.validFrom, DateTime(2026, 11, 24));
      expect(first.validUntil, DateTime(2026, 12, 1));
      expect(first.isUnread, isTrue);
      expect(first.canMarkAsRead, isTrue);
      expect(first.description, 'Hallo Elisa Bauer.\nBitte lesen.');
      expect(first.creatorName, 'alessio caputo');
      expect(first.infoLink?.url, Uri.parse('https://example.org/info'));
      expect(first.infoLink?.title, 'Weitere Infos');
      expect(first.files, hasLength(2));
      expect(first.files[0].index, 0);
      expect(first.files[0].name, 'elternbrief.pdf');
      expect(first.files[0].fileExtension, 'pdf');
      expect(first.files[0].isTemplate, isTrue);
      expect(
        first.files[0].downloadUrl,
        Uri.parse(
          'https://start.schulportal.hessen.de/dateiverteilung.php?a=user&v=1&k=0',
        ),
      );

      final second = home.items[1];
      expect(second.id, 2);
      expect(second.isUnread, isFalse);
      expect(second.canMarkAsRead, isFalse);
      expect(second.files, isEmpty);

      final third = home.items[2];
      expect(third.id, 3);
      expect(third.isUnread, isTrue);
      expect(third.canMarkAsRead, isFalse);
      expect(third.errorMessage, 'Dateivorlage fehlt oder Dateiname falsch');
    });

    test('separates Tooladmin sidebar items from recipient cards', () {
      const html = '''
        <div id="content">
          <div class="row">
            <div class="col-md-8">
              <div class="panel panel-primary verteilung" data-id="3">
                <div class="panel-heading headline">
                  <small class="pull-right">24.11.2026 bis 01.12.2026</small>
                  Lehrer-Info
                </div>
                <div class="panel-body">Hallo CAP</div>
                <div class="panel-footer"></div>
              </div>
            </div>
            <div class="col-md-4">
              <div class="panel panel-warning">
                <div class="panel-heading headline">
                  <a href="dateiverteilung.php?a=admin" class="btn btn-success"></a>
                  Dateien <small>für Tooladmins</small>
                </div>
                <div class="panel-body">
                  <div class="verteilung" data-id="1">
                    <b>Schueler-Paket <small>Lernende (1 - 12)</small></b>
                    <div class="verteilungmulti readAndDownload" title="info.txt" data-id="0">
                      <i class="fa fa-download"></i> info.txt
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      ''';

      final home = FileDistributionParser.parseHomeHtml(html);
      expect(home.isAdmin, isTrue);
      expect(home.items, hasLength(1));
      expect(home.items.single.id, 3);
      expect(home.items.single.title, 'Lehrer-Info');

      expect(home.adminSidebarItems, hasLength(1));
      final sidebar = home.adminSidebarItems.single;
      expect(sidebar.id, 1);
      expect(sidebar.title, 'Schueler-Paket');
      expect(sidebar.audienceLabel, 'Lernende (1 - 12)');
      expect(sidebar.files, hasLength(1));
      expect(sidebar.files.single.name, 'info.txt');
      expect(
        sidebar.files.single.downloadUrl,
        Uri.parse(
          'https://start.schulportal.hessen.de/dateiverteilung.php?a=admin&v=1&k=0',
        ),
      );
    });

    test('round-trips FileDistributionHome via JSON for cache storage', () {
      final home = FileDistributionHome(
        isAdmin: true,
        items: [
          FileDistributionItem(
            id: 7,
            title: 'Test',
            validFrom: DateTime(2026, 11, 24),
            validUntil: DateTime(2026, 12, 1),
            description: 'Desc',
            creatorName: 'Admin',
            isUnread: true,
            canMarkAsRead: true,
            infoLink: FileDistributionLink(
              url: Uri.parse('https://example.org'),
              title: 'Link',
            ),
            files: [
              FileDistributionFile(
                index: 0,
                name: 'doc.pdf',
                downloadUrl: FileDistributionParser.buildDownloadUrl(7, 0),
                isTemplate: true,
              ),
            ],
          ),
        ],
        adminSidebarItems: [
          ToolAdminQuickDistribution(
            id: 8,
            title: 'Sidebar',
            audienceLabel: 'Lernende (1 - 12)',
            files: [
              FileDistributionFile(
                index: 0,
                name: 'side.txt',
                downloadUrl: FileDistributionParser.buildDownloadUrl(
                  8,
                  0,
                  admin: true,
                ),
              ),
            ],
          ),
        ],
      );

      final decoded = FileDistributionHome.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(home)) as Map),
      );
      expect(decoded.isAdmin, isTrue);
      expect(decoded.items.single.id, 7);
      expect(decoded.items.single.files.single.name, 'doc.pdf');
      expect(decoded.adminSidebarItems.single.id, 8);
    });
  });

  group('FileDistributionParser admin parsers', () {
    test('parses admin list table', () {
      const html = '''
        <table id="boards">
          <tbody>
            <tr id="r1" data-itemid="1" class="verteilung">
              <td>Probe WithFiles</td>
              <td>24.11.2026 - 01.12.2026</td>
              <td>Lernende (1 - 12)</td>
              <td>nein</td>
              <td>5 (von 83) verteilt</td>
              <td>
                <div class="verteilungmulti readAndDownload" title="info.txt" data-id="0">info.txt</div>
                <span class="label label-info">Datei(en) noch vorhanden</span>
              </td>
              <td><span title="Erstellt durch alessio caputo">CAP</span></td>
              <td class="actionBar">
                <span data-action="edit"></span>
                <span data-action="upload"></span>
                <span data-action="chart"></span>
                <span data-action="delete"></span>
              </td>
            </tr>
          </tbody>
        </table>
      ''';

      final list = FileDistributionParser.parseAdminListHtml(html);
      expect(list, hasLength(1));
      final row = list.single;
      expect(row.id, 1);
      expect(row.title, 'Probe WithFiles');
      expect(row.mode, DistributionMode.sharedFiles);
      expect(row.distributedCount, 5);
      expect(row.totalRecipients, 83);
      expect(row.files.single.name, 'info.txt');
      expect(row.filesAvailable, isTrue);
      expect(row.creatorName, 'alessio caputo');
      expect(row.creatorShortName, 'CAP');
      expect(row.canUpload, isTrue);
    });

    test('parses admin detail JSON', () {
      final detail = FileDistributionParser.parseAdminDetailJson({
        'Id': '4',
        'Titel': 'Zugangscodes',
        'Hinweis': 'Hallo %Vorname%',
        'Von': '24.11.2026',
        'Bis': '01.12.2026',
        'LoeschungDerDateien': '2026-12-21 00:00:00',
        'Userart': 'SchuelerEltern',
        'JahrgangsstufeVon': '1',
        'JahrgangsstufeBis': '12',
        'Einzeldatei': 'nein',
        'Dateinamenvorlage': ['info.txt', 'merkblatt.txt'],
        'Startzahl': null,
        'LinkUrl': 'https://example.org/files',
        'LinkTitel': 'Begleitseite',
        'Anzahl': '2',
        'verbraucht': 1,
        'Ersteller': '316983',
        'Erstellt': '2026-11-24 19:16:09',
        'Userarray': {
          'Vorname': 'alessio',
          'Nachname': 'caputo',
          'Kuerzel': 'CAP',
        },
      });

      expect(detail.id, 4);
      expect(detail.audience, DistributionAudience.studentsAndParents);
      expect(detail.mode, DistributionMode.sharedFiles);
      expect(detail.gradeFrom, 1);
      expect(detail.gradeUntil, 12);
      expect(detail.fileNameTemplates, ['info.txt', 'merkblatt.txt']);
      expect(detail.fileCount, 2);
      expect(detail.consumedCount, 1);
      expect(detail.creatorName, 'alessio caputo');
      expect(detail.creatorShortName, 'CAP');
    });

    test('parses statistics HTML table', () {
      const html = '''
        <div id="content">
          <h2>Probe WithFiles (#1)</h2>
          <table class="table table-striped">
            <tbody>
              <tr><td>1</td><td>2</td><td>22</td><td>8,33%</td></tr>
              <tr><td>Summe</td><td>2</td><td>81</td><td>2,41%</td></tr>
            </tbody>
          </table>
        </div>
      ''';

      final stats = FileDistributionParser.parseStatisticsHtml(
        html,
        distributionId: 1,
      );
      expect(stats.distributionId, 1);
      expect(stats.title, 'Probe WithFiles');
      expect(stats.groups, hasLength(1));
      expect(stats.groups.single.group, '1');
      expect(stats.groups.single.retrieved, 2);
      expect(stats.groups.single.pending, 22);
      expect(stats.groups.single.completionPercent, closeTo(8.33, 0.001));
      expect(stats.total?.retrieved, 2);
      expect(stats.total?.pending, 81);
    });
  });

  group('FileDistributionParser cache registration', () {
    test('registers cached home for all account types', () {
      for (final type in AccountType.values) {
        final home = CachedAppletHomes.find('dateiverteilung.php', type);
        expect(home, isNotNull);
        expect(home!.request().operation, 'fileDistribution.home');
      }
    });
  });

  group('FileDistributionParser edge cases', () {
    test('throws UnauthorizedException when login page HTML is returned', () {
      const loginHtml = '''
        <html><body>
          <form action="https://login.schulportal.hessen.de/" method="post">
            <input type="text" name="user" />
            <input type="password" name="password" />
          </form>
        </body></html>
      ''';
      expect(
        () => FileDistributionParser.parseHomeHtml(loginHtml),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnknownException when #content container is missing', () {
      expect(
        () => FileDistributionParser.parseHomeHtml('<html><body>oops</body></html>'),
        throwsA(isA<UnknownException>()),
      );
    });

    test('detects isAdmin with relative or absolute admin links', () {
      const html = '''
        <div id="content">
          <a href="./dateiverteilung.php?a=admin">Administration</a>
        </div>
      ''';
      expect(FileDistributionParser.parseHomeHtml(html).isAdmin, isTrue);
    });

    test('throws UnknownException when admin detail JSON has missing or null Id', () {
      expect(
        () => FileDistributionParser.parseAdminDetailJson({'Titel': 'No Id'}),
        throwsA(isA<UnknownException>()),
      );
      expect(
        () => FileDistributionParser.parseAdminDetailJson({'Id': null}),
        throwsA(isA<UnknownException>()),
      );
    });
  });

  group('FileDistributionParser HTTP and EasyParsers integration', () {
    late _StubAdapter adapter;
    late LanisDatabase database;
    late LanisSession session;
    late AppletContext ctx;
    late FileDistributionParser parser;

    setUp(() async {
      adapter = _StubAdapter();
      database = LanisDatabase.open();
      const account = ClearTextAccount(
        localId: 1,
        schoolID: 5690,
        username: 'test',
        password: 'secret',
        schoolName: 'Test',
        accountType: AccountType.student,
      );
      session = LanisSession(
        account: account,
        config: LanisConfig(httpAdapter: adapter),
        connectionChecker: _OnlineChecker(),
      );
      await session.prepareDio();
      ctx = AppletContext(
        session: session,
        database: database,
        account: account,
        accountSettings: TypedSettings.account(database, 1),
      );
      parser = FileDistributionParser(ctx, isConnected: () async => true);
    });

    tearDown(() async {
      parser.dispose();
      await session.dispose();
      session.connectionChecker.dispose();
      database.dispose();
    });

    test('wraps DioException in NetworkException', () async {
      adapter.errorToThrow = DioException.connectionError(
        requestOptions: RequestOptions(path: '/dateiverteilung.php'),
        reason: 'offline',
      );
      await expectLater(parser.getHome(), throwsA(isA<NetworkException>()));
    });

    test('throws UnauthorizedException on 302 redirect', () async {
      adapter.statusCode = 302;
      adapter.headers = {
        'location': ['https://login.schulportal.hessen.de/'],
      };
      await expectLater(
        parser.getHome(),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('markAsRead sends form payload and returns true on "1"', () async {
      adapter.body = '1';
      final ok = await parser.markAsRead(42);
      expect(ok, isTrue);
      expect(adapter.lastOptions?.method, 'POST');
      expect(adapter.lastOptions?.data, {'a': 'user', 'b': 'read', 'v': '42'});
    });

    test('getAdminDistributions throws NotSupportedException for non-admins', () async {
      adapter.body = '<div id="content"><h1>Dateiverteilung</h1></div>';
      await expectLater(
        parser.getAdminDistributions(),
        throwsA(isA<NotSupportedException>()),
      );
    });

    test('getAdminDistributionDetail throws UnknownException on non-JSON HTML', () async {
      adapter.body = '<div id="content">Keine Berechtigung</div>';
      await expectLater(
        parser.getAdminDistributionDetail(1),
        throwsA(isA<UnknownException>()),
      );
    });

    test('saveDistribution encodes draft and returns created ID', () async {
      adapter.body = '17';
      final id = await parser.saveDistribution(
        FileDistributionDraft(
          title: 'Elternbrief',
          audience: DistributionAudience.parents,
          gradeFrom: 5,
          gradeUntil: 10,
          description: 'Hinweis',
          validFrom: DateTime(2026, 11, 24),
          validUntil: DateTime(2026, 12, 1),
          mode: DistributionMode.sharedFiles,
        ),
      );
      expect(id, 17);
      final sent = adapter.lastOptions?.data as Map<String, String>;
      expect(sent['a'], 'admin');
      expect(sent['f'], 'new');
      expect(sent['Userart'], 'Eltern');
      expect(sent['Einzeldatei'], 'nein');
      expect(sent['Von'], '24.11.2026');
      expect(sent['Bis'], '01.12.2026');
      expect(sent['JahrgangsstufeVon'], '5');
      expect(sent['JahrgangsstufeBis'], '10');
    });

    test('deleteDistribution sends admin del payload', () async {
      adapter.body = '1';
      expect(await parser.deleteDistribution(9), isTrue);
      expect(adapter.lastOptions?.data, {'a': 'admin', 'f': 'del', 'v': '9'});
    });

    test('EasyParsers routes dateiverteilung.php and disposes cleanly', () {
      final easyParsers = EasyParsers(ctx: ctx, isConnected: () async => true);
      final routed = easyParsers.forApplet('dateiverteilung.php');
      expect(routed, isA<FileDistributionParser>());
      expect(identical(routed, easyParsers.fileDistribution), isTrue);
      easyParsers.disposeAll();
    });
  });
}
