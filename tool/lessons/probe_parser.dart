import 'dart:io';
import 'package:html/parser.dart';
import 'package:liblanis/liblanis.dart';

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'test/fixtures/lessons' : args.first);
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.html') &&
                f.path.split('/').last.startsWith('student_'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  var checked = 0;
  var failed = 0;
  for (final file in files) {
    final doc = parse(file.readAsStringSync());
    final name = file.path.split('/').last;
    try {
      if (name.endsWith('_overview.html')) {
        final result = LessonsStudentParser.parseOverviewDocument(doc);
        print('$name: ${result.length} courses');
      } else if (name.endsWith('_detail.html')) {
        final result = LessonsStudentParser.parseDetailedDocument(
          doc,
          courseID: '20',
        );
        print(
          '$name: ${result.history.length} history entries, ${result.teachers.length} teachers',
        );
      } else if (name.endsWith('_upload.html')) {
        final result = LessonsStudentParser.parseUploadDocument(doc);
        print(
          '$name: ${(result['own_files'] as List).length} own files, multiple=${result['upload_multiple_files']}, repeat=${result['upload_any_number_of_times']}',
        );
      } else if (name.endsWith('_status.html')) {
        final result = LessonsStudentParser.parseUploadStatusDocument(doc);
        print('$name: ${result.map((s) => s.status).join(',')}');
      } else {
        continue;
      }
      checked++;
    } catch (error, stack) {
      checked++;
      failed++;
      stderr.writeln(
        '$name: $error\n${stack.toString().split('\n').take(3).join('\n')}',
      );
    }
  }
  print('$checked fixtures checked; $failed failures');
  if (failed != 0 || checked == 0) exitCode = 1;
}
