/// Phase 2 fuzzing for teacher Stundenplan:
/// - Pausenaufsichten (adds 0/1, 2/3, 4/5 pauses to Stundenraster)
/// - Embedded substitutions (vplanEinbettung=ja)
/// - Räume und Medien (rumbsButton=ja, rumbsBuchungen=ja)
/// - Freie Räume (GET & POST a=freeRoom)
/// - teacherCanSee=own on detail_klasse & detail_raum
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

Map<String, String> loadDotEnv(String path) {
  final map = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final i = line.indexOf('=');
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    map[line.substring(0, i).trim().toLowerCase()] = v;
  }
  return map;
}

Future<EasyLanisClient> login(String envPath) async {
  final env = loadDotEnv(envPath);
  final client = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['schoolid']!),
    username: env['username']!,
    password: env['password']!,
    userAgent: 'liblanis-teacher-timetable-fuzz2/0.1.0',
  );
  await client.login();
  return client;
}

String cb() => '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

Options get formOpts => Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (s) => s != null && s < 500,
      headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
    );

String formatDe(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

DateTime thisMonday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (now.weekday - 1));
}

Future<void> ensureStundenrasterPauses(LanisSession admin) async {
  final r = await admin.dio.get(
    'https://start.schulportal.hessen.de/verwaltung.php?_type=stundentafel&_action=search&a=stundenraster&limit=50',
  );
  final data = r.data is String ? jsonDecode(r.data as String) : r.data;
  final rows = (data['rows'] as List? ?? const []).cast<Map<String, dynamic>>();
  final existingKurz = rows.map((e) => (e['Kurzform'] ?? '').toString().trim()).toSet();
  stdout.writeln('Existing Stundenraster Kurzformen: $existingKurz');

  final pausesToAdd = [
    ('Frühaufsicht', '0/1', '07:45', '08:00'),
    ('1. Pause', '2/3', '09:45', '10:00'),
    ('2. Pause', '4/5', '11:45', '12:00'),
  ];
  for (final (stunde, kurz, von, bis) in pausesToAdd) {
    if (existingKurz.contains(kurz)) continue;
    final resp = await admin.dio.post(
      'https://start.schulportal.hessen.de/verwaltung.php',
      data: {
        '_type': 'stundentafel',
        '_action': 'addsave',
        'Stunde': stunde,
        'Kurzform': kurz,
        'Von': von,
        'Bis': bis,
      },
      options: formOpts,
    );
    stdout.writeln('  Added pause $kurz ($von-$bis) -> HTTP ${resp.statusCode}');
  }
}

Future<void> uploadTimetableCsv(LanisSession admin, String csv) async {
  await admin.dio.post(
    'https://start.schulportal.hessen.de/stundenplan.php?${cb()}',
    data: {'a': 'delete', 'b': 'all'},
    options: formOpts,
  );
  final form = FormData.fromMap({
    'a': 'import',
    'type': 'csv',
    'ab': formatDe(thisMonday()),
    'file': MultipartFile.fromBytes(utf8.encode(csv), filename: 'rich_pauses.csv'),
  });
  final resp = await admin.dio.post(
    'https://start.schulportal.hessen.de/stundenplan.php?${cb()}',
    data: form,
    options: Options(validateStatus: (s) => s != null && s < 500),
  );
  stdout.writeln('  Uploaded timetable CSV -> HTTP ${resp.statusCode}');
}

Future<void> uploadVplanCsv(LanisSession admin, String csv) async {
  const url = 'https://start.schulportal.hessen.de/vertretungsplan.php';
  const art = 'csv-kuerzel';
  Future<String> step(Map<String, dynamic> data) async {
    final r = await admin.dio.post('$url?${cb()}', data: data, options: formOpts);
    return '${r.data}'.trim();
  }

  final reset = await step({'a': 'upload', 'manuell': '1', 'reset': '1', 'art': art, 'upload': '1'});
  final up = await admin.dio.post(
    '$url?${cb()}',
    data: FormData.fromMap({
      'a': 'upload',
      'manuell': '1',
      'art': art,
      'd': MultipartFile.fromBytes(utf8.encode(csv), filename: 'vplan_embed.csv'),
    }),
    options: Options(validateStatus: (_) => true),
  );
  final unlock = await step({'a': 'upload', 'manuell': '1', 'unlock': '1', 'art': art, 'upload': '1'});
  stdout.writeln('  Uploaded vplan CSV: reset=$reset file=${up.data} unlock=$unlock');
}

Future<void> save(Directory dir, String name, String html) async {
  await File(p.join(dir.path, '$name.html')).writeAsString(html);
}

Future<void> main() async {
  final outDir = Directory('tool/timetable/discovery/teacher_fuzz_extras')
    ..createSync(recursive: true);

  final admin = await login('../.teacher.credentials.admin.env');
  final unpriv = await login('../.teacher.credentials.unpriv.env');

  try {
    // 1. Add pauses to Stundenraster
    stdout.writeln('--- 1. Ensure Stundenraster pauses ---');
    await ensureStundenrasterPauses(admin.session!);

    // 2. Upload rich plan with Pausenaufsichten matching 0/1, 2/3, 4/5
    stdout.writeln('--- 2. Upload rich plan with Pausenaufsichten ---');
    final csv = [
      'Id;Art;Lehrerkuerzel;Fach;Kurs;Raum;Wochentag;Stunde;Woche;Klassen',
      'T1;Stunde;CAP;Mathe;1-M;R101;1;1+2;;1',
      'T2;Stunde;CAP2;Deutsch;1-D;R102;1;3;;1',
      'T3;Stunde;CAP;Physik;G1-Ph;Ph-Labor;2;1-3;A;G1',
      'T4;Stunde;CAP2;Chemie;G1-Ch;Ch-Labor;2;1+2;B;G1',
      'T5;Stunde;CAP2;Bio;10TEST-Bio;Bio 1;3;1, 2, 5;;10TEST',
      'T6;Stunde;CAP;Sport;1_2-Sp;Sporthalle 1;4;1+2;;1,2',
      'T7;Stunde;CAP2;Sport;1_2-Sp;Sporthalle 1;4;1+2;;1,2',
      'T8;Stunde;CAP;Info;G1-Inf;PC-Raum;5;1+2;G;G1',
      'T9;Stunde;CAP2;Kunst;G1-Ku;Ku-Raum;5;1+2;U;G1',
      // Pausenaufsichten matching 0/1, 2/3, 4/5 (note: KB 621 says single hour "3" = before 3rd = 2/3, or "2/3")
      'P1;Pausenaufsicht;CAP;;;Großer Hof;1;2/3;;',
      'P2;Pausenaufsicht;CAP2;;;Großer Hof;1;2/3;;',
      'P3;Pausenaufsicht;CAP2;;;Großer Hof;2;3;;',
      'P4;Pausenaufsicht;CAP;;;Kantine & Aula;2;4/5;;',
      'P5;Pausenaufsicht;CAP2;;;Kantine & Aula;4;4/5;;',
      'P6;Pausenaufsicht;CAP;;;Südhof / Eingang;3;0/1;;',
      'P7;Pausenaufsicht;CAP2;;;Südhof / Eingang;5;1;;',
    ].join('\n');
    await uploadTimetableCsv(admin.session!, '$csv\n');
    await Future<void>.delayed(const Duration(seconds: 2));

    // 3. Capture Pausenaufsichten & teacher plans
    stdout.writeln('--- 3. Capture Pausenaufsichten ---');
    final pDir = Directory(p.join(outDir.path, '01_pausenaufsichten'))..createSync(recursive: true);
    for (final (name, q) in [
      ('overview', ''),
      ('teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('teacher_CAP', 'e=1&a=detail&t=CAP'),
      ('pause_GrosserHof', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Großer Hof')}'),
      ('pause_KantineAula', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Kantine & Aula')}'),
      ('pause_Suedhof', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Südhof / Eingang')}'),
    ]) {
      final h = (await unpriv.session!.dio.get('https://start.schulportal.hessen.de/stundenplan.php?$q&${cb()}')).data.toString();
      await save(pDir, name, h);
      final doc = parse(h);
      stdout.writeln('  $name -> ${h.length}b, stunde=${doc.querySelectorAll('.stunde').length}, tbody_trs=${doc.querySelectorAll('tbody tr').length}');
    }

    // 4. Enable vplanEinbettung=ja + upload today's substitutions
    stdout.writeln('--- 4. Embedded substitutions (vplanEinbettung=ja) ---');
    await admin.session!.dio.post(
      'https://start.schulportal.hessen.de/stundenplan.php?a=admin&${cb()}',
      data: {'a': 'admin', 'vplanEinbettung': 'ja'},
      options: formOpts,
    );
    final now = DateTime.now();
    final todayIso =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final vplanCsv = [
      'Tag;Lehrer;Stunde;Klasse;Art;Vertreter;Fach;Raum;Hinweis;Raum_alt;Fach_alt;Klasse_alt;Hinweis2',
      '$todayIso;CAP2;1 - 2;1,2;Vertretung;CAP;Sport;Sporthalle 1;Halle geteilt;Sporthalle 1;Sport;;',
      '$todayIso;CAP;1;1;Raumwechsel;CAP2;Mathe;R102;Umzug in R102;R101;Mathe;;',
      '$todayIso;CAP2;3;1;Entfall;;Deutsch;R102;Fällt aus;R102;Deutsch;;',
    ].join('\n');
    await uploadVplanCsv(admin.session!, '$vplanCsv\n');
    await Future<void>.delayed(const Duration(seconds: 2));

    final vDir = Directory(p.join(outDir.path, '02_vplan_einbettung'))..createSync(recursive: true);
    for (final (name, q) in [
      ('teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('teacher_CAP', 'e=1&a=detail&t=CAP'),
      ('raum_R101', 'e=1&a=detail_raum&r=R101'),
      ('raum_R102', 'e=1&a=detail_raum&r=R102'),
      ('raum_Sporthalle1', 'e=1&a=detail_raum&r=${Uri.encodeQueryComponent('Sporthalle 1')}'),
      ('klasse_1', 'e=1&a=detail_klasse&k=1'),
    ]) {
      final h = (await unpriv.session!.dio.get('https://start.schulportal.hessen.de/stundenplan.php?$q&${cb()}')).data.toString();
      await save(vDir, name, h);
      final doc = parse(h);
      stdout.writeln('  vplan $name -> ${h.length}b, stunde=${doc.querySelectorAll('.stunde').length}');
    }

    // 5. Enable rumbsButton=ja & rumbsBuchungen=ja and check rumbs/raeume
    stdout.writeln('--- 5. Räume und Medien (rumbsButton & rumbsBuchungen) ---');
    await admin.session!.dio.post(
      'https://start.schulportal.hessen.de/stundenplan.php?a=admin&${cb()}',
      data: {'a': 'admin', 'rumbsButton': 'ja', 'rumbsBuchungen': 'ja'},
      options: formOpts,
    );
    // Check export_rumbs to see what rooms exist in Räume & Medien!
    final rumbsExport = (await admin.session!.dio.get('https://start.schulportal.hessen.de/stundenplan.php?e=1&a=export_rumbs&${cb()}')).data.toString();
    final rDir = Directory(p.join(outDir.path, '03_rumbs'))..createSync(recursive: true);
    await save(rDir, 'admin_export_rumbs', rumbsExport);
    // Also check raeume.php / rumbs.php if accessible
    for (final applet in ['raeume.php', 'rumbs.php', 'ressourcen.php']) {
      final r = await admin.session!.dio.get(
        'https://start.schulportal.hessen.de/$applet?${cb()}',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      stdout.writeln('  GET $applet -> ${r.statusCode} (${r.data.toString().length}b) loc=${r.headers.value('location')}');
      if (r.statusCode == 200 && r.data.toString().length > 1000) {
        await save(rDir, 'applet_$applet', r.data.toString());
      }
    }
    for (final (name, q) in [
      ('teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('raum_R101', 'e=1&a=detail_raum&r=R101'),
    ]) {
      final h = (await unpriv.session!.dio.get('https://start.schulportal.hessen.de/stundenplan.php?$q&${cb()}')).data.toString();
      await save(rDir, name, h);
    }

    // 6. Freie Räume (GET & POST)
    stdout.writeln('--- 6. Freie Räume ---');
    final fDir = Directory(p.join(outDir.path, '04_free_room'))..createSync(recursive: true);
    final frGet = (await unpriv.session!.dio.get('https://start.schulportal.hessen.de/stundenplan.php?a=freeRoom&${cb()}')).data.toString();
    await save(fDir, 'get_default', frGet);
    final frPost = await unpriv.session!.dio.post(
      'https://start.schulportal.hessen.de/stundenplan.php?a=freeRoom',
      data: 'tag=1&stunde%5B%5D=1&stunde%5B%5D=2',
      options: formOpts,
    );
    await save(fDir, 'post_mon_1_2', frPost.data.toString());
    stdout.writeln('  freeRoom POST mon 1,2 -> ${frPost.statusCode} (${frPost.data.toString().length}b)');

    // 7. teacherCanSee=own on detail_klasse & detail_raum
    stdout.writeln('--- 7. teacherCanSee=own on detail_klasse & detail_raum ---');
    await admin.session!.dio.post(
      'https://start.schulportal.hessen.de/stundenplan.php?a=admin&${cb()}',
      data: {'a': 'admin', 'teacherCanSee': 'own'},
      options: formOpts,
    );
    final oDir = Directory(p.join(outDir.path, '05_teacher_own'))..createSync(recursive: true);
    for (final (name, q) in [
      ('klasse_1', 'e=1&a=detail_klasse&k=1'),
      ('raum_R101', 'e=1&a=detail_raum&r=R101'),
      ('pause_GrosserHof', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Großer Hof')}'),
    ]) {
      final h = (await unpriv.session!.dio.get('https://start.schulportal.hessen.de/stundenplan.php?$q&${cb()}')).data.toString();
      await save(oDir, name, h);
    }

    // Restore teacherCanSee=all
    await admin.session!.dio.post(
      'https://start.schulportal.hessen.de/stundenplan.php?a=admin&${cb()}',
      data: {'a': 'admin', 'teacherCanSee': 'all'},
      options: formOpts,
    );
  } finally {
    await admin.logout();
    await admin.dispose();
    await unpriv.logout();
    await unpriv.dispose();
  }
  stdout.writeln('Phase 2 fuzzing complete!');
}
