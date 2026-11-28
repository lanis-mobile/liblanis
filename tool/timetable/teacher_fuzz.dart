/// Fuzz & capture teacher Stundenplan HTML views across plans, settings, and roles.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

const _csvHeader =
    'Id;Art;Lehrerkuerzel;Fach;Kurs;Raum;Wochentag;Stunde;Woche;Klassen';

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
    userAgent: 'liblanis-teacher-timetable-fuzz/0.1.0',
  );
  await client.login();
  return client;
}

String cb() => '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

String stundenplanUrl([String query = '']) {
  final parts = <String>[if (query.isNotEmpty) query, cb()];
  return 'https://start.schulportal.hessen.de/stundenplan.php?${parts.join('&')}';
}

Options get formOpts => Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (s) => s != null && s < 500,
      headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
    );

String formatDe(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String formatIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> deleteAllPlans(LanisSession session) async {
  await session.dio.post(
    stundenplanUrl(),
    data: {'a': 'delete', 'b': 'all'},
    options: formOpts,
  );
  await session.dio.post(
    stundenplanUrl(),
    data: {'a': 'delete', 'b': 'time', 'date': formatIso(DateTime.now())},
    options: formOpts,
  );
}

DateTime thisMonday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (now.weekday - 1));
}

Future<void> uploadCsvContent(
  LanisSession session,
  String filename,
  String content, {
  DateTime? validFrom,
}) async {
  final effectiveFrom = validFrom ?? thisMonday();
  final tmp = File(p.join(Directory.systemTemp.path, filename));
  await tmp.writeAsString(content, encoding: utf8);
  final form = FormData.fromMap({
    'a': 'import',
    'type': 'csv',
    'ab': formatDe(effectiveFrom),
    'file': await MultipartFile.fromFile(tmp.path, filename: filename),
  });
  final resp = await session.dio.post(
    stundenplanUrl(),
    data: form,
    options: Options(
      headers: {
        'Accept': '*/*',
        'Content-Type': 'multipart/form-data;',
        'Cache-Control': 'no-cache',
      },
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  stdout.writeln('  upload $filename (ab=${formatDe(effectiveFrom)}) -> HTTP ${resp.statusCode}');
  if (tmp.existsSync()) tmp.deleteSync();
}

Future<Map<String, Object?>> readAdminSettings(LanisSession session) async {
  final html = (await session.dio.get(stundenplanUrl('e=1&a=admin'))).data.toString();
  final doc = parse(html);
  String selVal(String name, String fallback) {
    final s = doc.querySelector('select[name="$name"]');
    return s?.querySelector('option[selected]')?.attributes['value'] ??
        s?.querySelector('option')?.attributes['value'] ??
        fallback;
  }

  return {
    'vonBisAusblenden': doc.querySelector('#VonBisAusblenden')?.attributes.containsKey('checked') ?? false,
    'kursnamenEinblenden': doc.querySelector('#KursnamenEinblenden')?.attributes.containsKey('checked') ?? false,
    'teacherCanSee': selVal('teacherCanSee', 'all'),
    'vplanEinbettung': selVal('vplanEinbettung', 'nein'),
    'rumbsButton': selVal('rumbsButton', 'nein'),
    'rumbsBuchungen': selVal('rumbsBuchungen', 'nein'),
    'hinweis': doc.querySelector('textarea[name="hinweis"]')?.text ?? '',
  };
}

Future<void> applySettings(
  LanisSession session, {
  bool? vonBisAusblenden,
  bool? kursnamenEinblenden,
  String? teacherCanSee,
  String? vplanEinbettung,
  String? hinweis,
}) async {
  if (vonBisAusblenden != null || kursnamenEinblenden != null) {
    final data = <String, dynamic>{
      'a': 'admin',
      'b': 'Anzeigeeinstellungen',
    };
    if (vonBisAusblenden == true) data['VonBisAusblenden'] = 'on';
    if (kursnamenEinblenden == true) data['KursnamenEinblenden'] = 'on';
    await session.dio.post(stundenplanUrl('a=admin'), data: data, options: formOpts);
  }
  if (teacherCanSee != null) {
    await session.dio.post(
      stundenplanUrl('a=admin'),
      data: {'a': 'admin', 'teacherCanSee': teacherCanSee},
      options: formOpts,
    );
  }
  if (vplanEinbettung != null) {
    await session.dio.post(
      stundenplanUrl('a=admin'),
      data: {'a': 'admin', 'vplanEinbettung': vplanEinbettung},
      options: formOpts,
    );
  }
  if (hinweis != null) {
    await session.dio.post(
      stundenplanUrl('a=admin'),
      data: {'a': 'admin', 'hinweis': hinweis},
      options: formOpts,
    );
  }
}

Future<(int?, String?, String)> fetchPage(LanisSession session, String query) async {
  final resp = await session.dio.get(
    stundenplanUrl(query),
    options: Options(
      headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  return (resp.statusCode, resp.headers.value('location'), resp.data.toString());
}

Future<void> save(Directory dir, String name, String html) async {
  await File(p.join(dir.path, '$name.html')).writeAsString(html);
}

// ---------------------------------------------------------------------------
// Test CSV plans
// ---------------------------------------------------------------------------

String richPlanCsv() => [
      _csvHeader,
      // Normal single & double lessons for CAP, CAP2, MUE
      'T1;Stunde;CAP;Mathe;1-M;R101;1;1+2;;1',
      'T2;Stunde;CAP2;Deutsch;1-D;R102;1;3;;1',
      'T3;Stunde;CAP;Physik;G1-Ph;Ph-Labor;2;1-3;A;G1',
      'T4;Stunde;CAP2;Chemie;G1-Ch;Ch-Labor;2;1+2;B;G1',
      'T5;Stunde;CAP2;Bio;10TEST-Bio;Bio 1;3;1, 2, 5;;10TEST',
      // Multi-class & stacked same slot (co-teaching / parallel courses)
      'T6;Stunde;CAP;Sport;1_2-Sp;Sporthalle 1;4;1+2;;1,2',
      'T7;Stunde;CAP2;Sport;1_2-Sp;Sporthalle 1;4;1+2;;1,2',
      // G/U parity weeks
      'T8;Stunde;CAP;Info;G1-Inf;PC-Raum;5;1+2;G;G1',
      'T9;Stunde;CAP2;Kunst;G1-Ku;Ku-Raum;5;1+2;U;G1',
      // Pausenaufsichten: integer hours + slash hours, places, weeks, teachers
      'P1;Pausenaufsicht;CAP;;;Großer Hof;1;2;;',
      'P2;Pausenaufsicht;CAP2;;;Großer Hof;1;2;;',
      'P3;Pausenaufsicht;CAP2;;;Großer Hof;2;3;A;',
      'P4;Pausenaufsicht;CAP;;;Großer Hof;2;3;B;',
      'P5;Pausenaufsicht;CAP2;;;Kantine & Aula;2;4/5;A;',
      'P6;Pausenaufsicht;CAP;;;Kantine & Aula;2;4/5;B;',
      'P7;Pausenaufsicht;CAP;;;Südhof / Eingang;3;1;;',
      'P8;Pausenaufsicht;CAP2;;;Südhof / Eingang;5;4;G;',
      // Missing optional fields (no room, no fach, no kurs)
      'T10;Stunde;CAP2;Vertretung;; ;4;4;;1',
      'T11;Stunde;CAP;;1-AG;R101;4;5;;1',
      // Another teacher code not in user list? Let's see how Lanis renders it
      'T12;Stunde;MUE;Englisch;2-E;R102;1;1;;2',
    ].join('\n');

String weekendAndRowspanCsv() => [
      _csvHeader,
      'W1;Stunde;CAP2;Blockseminar;G1-BS;Aula;1;1-6;;G1',
      'W2;Stunde;CAP;Projekt;G1-PR;R101;6;1+2;;G1',
      'W3;Stunde;CAP2;Sonntagskurs;G1-SO;R102;7;3-5;;G1',
      'WP1;Pausenaufsicht;CAP2;;;Schulhof;6;2/3;;',
    ].join('\n');

String futurePlanCsv() => [
      _csvHeader,
      'F1;Stunde;CAP2;ZukunftsMathe;1-ZM;R999;1;1+2;;1',
      'F2;Stunde;CAP;ZukunftsPhysik;G1-ZP;R998;2;3;;G1',
      'FP1;Pausenaufsicht;CAP2;;;Neuer Hof;1;2/3;;',
    ].join('\n');

String emptyPlanCsv() => '$_csvHeader\n';

Future<void> main() async {
  final outDir = Directory('tool/timetable/discovery/teacher_fuzz')
    ..createSync(recursive: true);

  final admin = await login('../.teacher.credentials.admin.env');
  final unpriv = await login('../.teacher.credentials.unpriv.env');
  Map<String, Object?>? initialSettings;

  final report = <String, Object?>{};

  try {
    initialSettings = await readAdminSettings(admin.session!);
    stdout.writeln('Initial settings: $initialSettings');

    // =========================================================================
    // Scenario 1: Rich plan + default settings (teacherCanSee=all, vonBis=off, kursnamen=off)
    // =========================================================================
    stdout.writeln('\n--- Scenario 1: rich_default ---');
    await deleteAllPlans(admin.session!);
    await uploadCsvContent(admin.session!, 'rich.csv', richPlanCsv());
    await applySettings(
      admin.session!,
      vonBisAusblenden: false,
      kursnamenEinblenden: false,
      teacherCanSee: 'all',
      vplanEinbettung: 'nein',
      hinweis: '',
    );
    await Future<void>.delayed(const Duration(seconds: 2));

    final s1Dir = Directory(p.join(outDir.path, '01_rich_default'))..createSync(recursive: true);
    for (final (role, sess) in [('admin', admin.session!), ('unpriv', unpriv.session!)]) {
      final (st0, loc0, html0) = await fetchPage(sess, '');
      await save(s1Dir, '${role}_overview', html0);
      final doc0 = parse(html0);
      final teacherLinks = doc0.querySelectorAll('#collapse1 a.list-group-item').map((a) => '${a.text.trim()} -> ${a.attributes['href']}').toList();
      final classLinks = doc0.querySelectorAll('#collapse2 a.list-group-item').map((a) => '${a.text.trim()} -> ${a.attributes['href']}').toList();
      final roomLinks = doc0.querySelectorAll('#collapse3 a.list-group-item').map((a) => '${a.text.trim()} -> ${a.attributes['href']}').toList();
      final pauseLinks = doc0.querySelectorAll('#collapse4 a.list-group-item').map((a) => '${a.text.trim()} -> ${a.attributes['href']}').toList();
      report['01_rich_default_$role'] = {
        'status': st0,
        'loc': loc0,
        'teachers': teacherLinks,
        'classes': classLinks,
        'rooms': roomLinks,
        'pauses': pauseLinks,
      };
      stdout.writeln('  [$role] overview: teachers=${teacherLinks.length} classes=${classLinks.length} rooms=${roomLinks.length} pauses=${pauseLinks.length}');
    }

    // Fetch detail pages as unpriv teacher
    for (final (name, q) in [
      ('unpriv_teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('unpriv_teacher_CAP', 'e=1&a=detail&t=CAP'),
      ('unpriv_teacher_MUE', 'e=1&a=detail&t=MUE'),
      ('unpriv_klasse_1', 'e=1&a=detail_klasse&k=1'),
      ('unpriv_klasse_G1', 'e=1&a=detail_klasse&k=G1'),
      ('unpriv_klasse_10TEST', 'e=1&a=detail_klasse&k=10TEST'),
      ('unpriv_raum_R101', 'e=1&a=detail_raum&r=R101'),
      ('unpriv_raum_Sporthalle1', 'e=1&a=detail_raum&r=${Uri.encodeQueryComponent('Sporthalle 1')}'),
      ('unpriv_pause_default', 'e=1&a=detail_pause'),
      ('unpriv_pause_GrosserHof', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Großer Hof')}'),
      ('unpriv_pause_KantineAula', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Kantine & Aula')}'),
      ('unpriv_pause_Suedhof', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Südhof / Eingang')}'),
      ('unpriv_multi_teacher', 'e=1&a=detail_multi&t[]=CAP&t[]=CAP2'),
    ]) {
      final (st, loc, h) = await fetchPage(unpriv.session!, q);
      await save(s1Dir, name, h);
      stdout.writeln('  GET $name -> $st (${h.length}b) loc=$loc');
    }

    // =========================================================================
    // Scenario 2: Rich plan + KursnamenEinblenden=on, VonBisAusblenden=on, hinweis=HTML
    // =========================================================================
    stdout.writeln('\n--- Scenario 2: rich_kursnamen_vonbis_hinweis ---');
    await applySettings(
      admin.session!,
      vonBisAusblenden: true,
      kursnamenEinblenden: true,
      teacherCanSee: 'all',
      hinweis: '<p><strong>Hinweis:</strong> Bitte Raumänderungen beachten!</p>',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final s2Dir = Directory(p.join(outDir.path, '02_rich_kursnamen_vonbis_hinweis'))..createSync(recursive: true);
    for (final (name, q) in [
      ('unpriv_overview', ''),
      ('unpriv_teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('unpriv_klasse_1', 'e=1&a=detail_klasse&k=1'),
      ('unpriv_klasse_G1', 'e=1&a=detail_klasse&k=G1'),
      ('unpriv_raum_R101', 'e=1&a=detail_raum&r=R101'),
      ('unpriv_pause_GrosserHof', 'e=1&a=detail_pause&p=${Uri.encodeQueryComponent('Großer Hof')}'),
    ]) {
      final (st, loc, h) = await fetchPage(unpriv.session!, q);
      await save(s2Dir, name, h);
      stdout.writeln('  GET $name -> $st (${h.length}b) loc=$loc');
    }

    // =========================================================================
    // Scenario 3: teacherCanSee=own (compare admin vs unpriv!)
    // =========================================================================
    stdout.writeln('\n--- Scenario 3: teacherCanSee=own ---');
    await applySettings(
      admin.session!,
      vonBisAusblenden: false,
      kursnamenEinblenden: false,
      teacherCanSee: 'own',
      hinweis: '',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final s3Dir = Directory(p.join(outDir.path, '03_teacher_can_see_own'))..createSync(recursive: true);
    for (final (role, sess) in [('admin', admin.session!), ('unpriv', unpriv.session!)]) {
      final (st0, loc0, h0) = await fetchPage(sess, '');
      await save(s3Dir, '${role}_overview', h0);
      final (st1, loc1, h1) = await fetchPage(sess, 'e=1&a=detail&t=CAP');
      await save(s3Dir, '${role}_teacher_CAP', h1);
      final (st2, loc2, h2) = await fetchPage(sess, 'e=1&a=detail&t=CAP2');
      await save(s3Dir, '${role}_teacher_CAP2', h2);
      final doc0 = parse(h0);
      report['03_own_$role'] = {
        'overview_status': st0,
        'overview_loc': loc0,
        'overview_teachers': doc0.querySelectorAll('#collapse1 a.list-group-item').map((a) => '${a.text.trim()} -> ${a.attributes['href']}').toList(),
        'get_CAP': '$st1 loc=$loc1 bytes=${h1.length}',
        'get_CAP2': '$st2 loc=$loc2 bytes=${h2.length}',
      };
      stdout.writeln('  [$role] own mode: overview_teachers=${(report['03_own_$role'] as Map)['overview_teachers']} CAP=$st1/$loc1 CAP2=$st2/$loc2');
    }

    // =========================================================================
    // Scenario 4: Multiple plans (current + future date)
    // =========================================================================
    stdout.writeln('\n--- Scenario 4: multi_date ---');
    await applySettings(admin.session!, teacherCanSee: 'all');
    final nextMonth = DateTime.now().add(const Duration(days: 14));
    await uploadCsvContent(admin.session!, 'future.csv', futurePlanCsv(), validFrom: nextMonth);
    await Future<void>.delayed(const Duration(seconds: 2));
    final s4Dir = Directory(p.join(outDir.path, '04_multi_date'))..createSync(recursive: true);
    for (final (name, q) in [
      ('unpriv_overview', ''),
      ('unpriv_teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('unpriv_teacher_CAP2_future', 'e=1&a=detail&t=CAP2&date=${formatIso(nextMonth)}'),
      ('unpriv_klasse_1', 'e=1&a=detail_klasse&k=1'),
    ]) {
      final (st, loc, h) = await fetchPage(unpriv.session!, q);
      await save(s4Dir, name, h);
      stdout.writeln('  GET $name -> $st (${h.length}b) loc=$loc');
    }

    // =========================================================================
    // Scenario 5: Weekend + long rowspan
    // =========================================================================
    stdout.writeln('\n--- Scenario 5: weekend_rowspan ---');
    await deleteAllPlans(admin.session!);
    await uploadCsvContent(admin.session!, 'weekend.csv', weekendAndRowspanCsv());
    await Future<void>.delayed(const Duration(seconds: 2));
    final s5Dir = Directory(p.join(outDir.path, '05_weekend_rowspan'))..createSync(recursive: true);
    for (final (name, q) in [
      ('unpriv_overview', ''),
      ('unpriv_teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('unpriv_klasse_G1', 'e=1&a=detail_klasse&k=G1'),
      ('unpriv_pause_Schulhof', 'e=1&a=detail_pause&p=Schulhof'),
    ]) {
      final (st, loc, h) = await fetchPage(unpriv.session!, q);
      await save(s5Dir, name, h);
      stdout.writeln('  GET $name -> $st (${h.length}b) loc=$loc');
    }

    // =========================================================================
    // Scenario 6: Empty plan
    // =========================================================================
    stdout.writeln('\n--- Scenario 6: empty ---');
    await deleteAllPlans(admin.session!);
    await uploadCsvContent(admin.session!, 'empty.csv', emptyPlanCsv());
    await Future<void>.delayed(const Duration(seconds: 2));
    final s6Dir = Directory(p.join(outDir.path, '06_empty'))..createSync(recursive: true);
    for (final (name, q) in [
      ('unpriv_overview', ''),
      ('unpriv_teacher_CAP2', 'e=1&a=detail&t=CAP2'),
      ('unpriv_klasse_none', 'e=1&a=detail_klasse'),
      ('unpriv_raum_none', 'e=1&a=detail_raum'),
      ('unpriv_pause_none', 'e=1&a=detail_pause'),
    ]) {
      final (st, loc, h) = await fetchPage(unpriv.session!, q);
      await save(s6Dir, name, h);
      stdout.writeln('  GET $name -> $st (${h.length}b) loc=$loc');
    }

    // =========================================================================
    // Restore rich plan so the test school isn't left empty, and restore settings
    // =========================================================================
    stdout.writeln('\n--- Restoring rich plan & initial settings ---');
    await deleteAllPlans(admin.session!);
    await uploadCsvContent(admin.session!, 'rich.csv', richPlanCsv());
    await applySettings(
      admin.session!,
      vonBisAusblenden: initialSettings['vonBisAusblenden'] as bool? ?? false,
      kursnamenEinblenden: initialSettings['kursnamenEinblenden'] as bool? ?? false,
      teacherCanSee: initialSettings['teacherCanSee'] as String? ?? 'all',
      vplanEinbettung: initialSettings['vplanEinbettung'] as String? ?? 'nein',
      hinweis: initialSettings['hinweis'] as String? ?? '',
    );

    await File(p.join(outDir.path, 'report.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
  } finally {
    await admin.logout();
    await admin.dispose();
    await unpriv.logout();
    await unpriv.dispose();
  }
  stdout.writeln('Fuzzing complete!');
}
