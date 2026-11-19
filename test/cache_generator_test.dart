import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';
import 'package:liblanis_cache_generator/builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

class _Step implements BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<String> generate(String method) async {
  final directory = Directory(
    'test/.cache_generator_${DateTime.now().microsecondsSinceEpoch}',
  ).absolute..createSync();
  final file = File('${directory.path}/input.dart')
    ..writeAsStringSync('''
import 'package:liblanis/easy_client.dart';
class Example {
  $method
}
''');
  final collection = AnalysisContextCollection(includedPaths: [file.path]);
  try {
    final result = await collection
        .contextFor(file.path)
        .currentSession
        .getResolvedLibrary(file.path);
    if (result is! ResolvedLibraryResult) {
      throw StateError('Could not resolve fixture');
    }
    return CacheGenerator().generate(LibraryReader(result.element), _Step());
  } finally {
    await collection.dispose();
    directory.deleteSync(recursive: true);
  }
}

void main() {
  test(
    'generates matching typed wrappers and detached descriptors with default arguments',
    () async {
      final output = await generate(
        '''@Cacheable(operation:'example.read',applet:Applets.timetable)
Future<int> _read(Uri url, {String? tag, bool visible=true}) async=>1;''',
      );
      expect(output, contains('class ExampleCacheRequests'));
      expect(output, contains('Future<MaybeCacheResult<int>> read'));
      expect(
        output,
        contains('load:()=>_owner._read(url,tag:tag,visible:visible)'),
      );
      expect(output, contains('url.toString()'));
      expect(output, contains('Duration(microseconds:3600000000)'));
      expect(output, contains('bool visible = true'));
      expect(output, contains("operation:'example.read'"));
    },
  );

  test(
    'nullable results generate a nullable codec rather than an untyped lookup',
    () async {
      final output = await generate(
        '@Cacheable() Future<int?> _read(int? id) async=>null;',
      );
      expect(output, contains('MaybeCacheResult<int?>'));
      expect(output, contains('json == null ? null : json as int'));
    },
  );

  for (final entry in <String, String>{
    'public method': '@Cacheable() Future<int> read() async=>1;',
    'sync method': '@Cacheable() int _read()=>1;',
    'void result': '@Cacheable() Future<void> _read() async {}',
    'unsupported argument':
        '@Cacheable() Future<int> _read(Object callback) async=>1;',
    'callback':
        '@Cacheable() Future<int> _read(void Function() callback) async=>1;',
    'optional positional':
        '@Cacheable() Future<int> _read([int count=1]) async=>1;',
    'reserved control':
        '@Cacheable() Future<int> _read({String? cachePolicy}) async=>1;',
    'generic method': '@Cacheable() Future<T> _read<T>(T value) async=>value;',
    'invalid age':
        '@Cacheable(maxAge:Duration.zero) Future<int> _read() async=>1;',
  }.entries) {
    test('rejects ${entry.key} during generation', () async {
      await expectLater(
        generate(entry.value),
        throwsA(isA<InvalidGenerationSource>()),
      );
    });
  }
}
