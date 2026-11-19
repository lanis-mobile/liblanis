import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder cacheBuilder(BuilderOptions options) =>
    SharedPartBuilder([CacheGenerator()], 'cache');

class CacheGenerator extends Generator {
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    final output = StringBuffer();
    for (final owner in library.classes) {
      final methods = <(MethodElement, ConstantReader)>[];
      for (final method in owner.methods) {
        for (final annotation in method.metadata.annotations) {
          final value = annotation.computeConstantValue();
          final type = value?.type;
          if (type is InterfaceType &&
              type.element.name == 'Cacheable' &&
              type.element.library.uri.toString() ==
                  'package:liblanis/src/cache/annotation.dart') {
            methods.add((method, ConstantReader(value)));
          }
        }
      }
      if (methods.isEmpty) continue;
      if (owner.typeParameters.isNotEmpty) {
        throw InvalidGenerationSource(
          'Generic cache hosts are not yet supported',
          element: owner,
        );
      }
      final name = owner.name!;
      output.writeln('mixin _\$${name}Cache on CacheHost {');
      output.writeln(
        '  _${name}Cached get cached => _${name}Cached(this as $name);',
      );
      output.writeln('}');
      output.writeln(
        'class _${name}Cached { final $name _owner; _${name}Cached(this._owner);',
      );
      for (final (method, _) in methods) {
        _validate(method);
        final result =
            (method.returnType as InterfaceType).typeArguments.single;
        final resultName = result.getDisplayString();
        final public = method.name!.substring(1);
        final signature = _signature(method, withPolicy: true);
        final args = _arguments(method);
        output.writeln(
          'Future<MaybeCacheResult<$resultName>> $public($signature) => _owner.cacheService.execute(',
        );
        output.writeln(
          'accountId:_owner.cacheAccountId, request:${name}CacheRequests.$public(${args.join(',')}),',
        );
        output.writeln(
          'load:()=>_owner.${method.name}(${args.join(',')}), policy:cachePolicy);',
        );
      }
      output.writeln('}');
      output.writeln('abstract final class ${name}CacheRequests {');
      for (final (method, annotation) in methods) {
        final result =
            (method.returnType as InterfaceType).typeArguments.single;
        final resultName = result.getDisplayString();
        final public = method.name!.substring(1);
        final operation = annotation.read('operation').isNull
            ? '${library.element.uri}#$name.$public'
            : annotation.read('operation').stringValue;
        final version = annotation.read('version').intValue;
        if (version < 1) {
          throw InvalidGenerationSource(
            'Cache versions must be positive',
            element: method,
          );
        }
        final age = _duration(annotation.read('maxAge'));
        final applet = annotation.read('applet');
        final limit = applet.isNull
            ? null
            : _duration(applet.read('refreshInterval'));
        // Validate every input codec too; query construction must not depend on a live instance.
        final params = method.formalParameters;
        final encoded = params
            .map(
              (p) =>
                  "'${p.name}': {'type':${_quote(_typeId(p.type))},'value':${_encode(p.type, p.name!)}}",
            )
            .join(',');
        output.writeln(
          'static CacheRequest<$resultName> $public(${_signature(method)}) => CacheRequest(',
        );
        output.writeln(
          'operation:${_quote(operation)}, version:$version, arguments:{$encoded},',
        );
        if (age != null) output.writeln('maxAge:Duration(microseconds:$age),');
        if (limit != null) {
          output.writeln('appletLimit:Duration(microseconds:$limit),');
        }
        output.writeln(
          'codec:CacheCodec<$resultName>(id:${_quote('${_typeId(result)}@$version')},',
        );
        output.writeln(
          'encode:(value)=>${_encode(result, 'value')}, decode:(json)=>${_decode(result, 'json')}));',
        );
      }
      output.writeln('}');
    }
    return output.toString();
  }

  void _validate(MethodElement method) {
    if (!method.isPrivate ||
        method.isStatic ||
        method.typeParameters.isNotEmpty ||
        method.returnType is! InterfaceType ||
        (method.returnType as InterfaceType).element.name != 'Future') {
      throw InvalidGenerationSource(
        '@Cacheable requires a private instance method returning Future<T> without method type parameters',
        element: method,
      );
    }
    if (method.formalParameters.any(
      (p) => p.name == 'cachePolicy' || p.isOptionalPositional,
    )) {
      throw InvalidGenerationSource(
        'cachePolicy is reserved; use named optional parameters instead of optional positional parameters',
        element: method,
      );
    }
  }

  String _signature(MethodElement method, {bool withPolicy = false}) {
    String declaration(FormalParameterElement p) =>
        '${p.isRequiredNamed ? "required " : ""}${p.type.getDisplayString()} ${p.name}${p.defaultValueCode == null ? "" : " = ${p.defaultValueCode}"}';
    final positional = method.formalParameters
        .where((p) => p.isRequiredPositional)
        .map(declaration)
        .toList();
    final named = method.formalParameters
        .where((p) => p.isNamed)
        .map(declaration)
        .toList();
    if (withPolicy) named.add('CacheReadPolicy? cachePolicy');
    return [
      ...positional,
      if (named.isNotEmpty) '{${named.join(',')}}',
    ].join(',');
  }

  List<String> _arguments(MethodElement method) => method.formalParameters
      .map((p) => p.isNamed ? '${p.name}:${p.name}' : p.name!)
      .toList();
  int? _duration(ConstantReader reader) {
    if (reader.isNull) return null;
    final duration =
        (reader.objectValue.getField('inMicroseconds') ??
                reader.objectValue.getField('_duration'))
            ?.toIntValue();
    if (duration == null || duration <= 0) {
      throw InvalidGenerationSource(
        'Cache durations must be positive compile-time Durations',
      );
    }
    return duration;
  }

  String _quote(String value) =>
      "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

  String _encode(DartType type, String value, {bool nullable = true}) {
    if (nullable && type.nullabilitySuffix == NullabilitySuffix.question) {
      return '$value == null ? null : ${_encode(type, '$value!', nullable: false)}';
    }
    final t = _interface(type);
    final name = t.element.name;
    if (['String', 'int', 'double', 'bool', 'num'].contains(name)) return value;
    if (name == 'Uri') return '$value.toString()';
    if (name == 'DateTime') return '$value.toUtc().toIso8601String()';
    if (t.element is EnumElement) return '$value.name';
    if (name == 'List') {
      return '$value.map((item)=>${_encode(t.typeArguments.single, 'item')}).toList()';
    }
    if (name == 'Map' && t.typeArguments.first.isDartCoreString) {
      return '$value.map((key,item)=>MapEntry(key,${_encode(t.typeArguments.last, 'item')}))';
    }
    if (t.element.getMethod('toJson') != null &&
        t.element.getNamedConstructor('fromJson') != null) {
      return '$value.toJson()';
    }
    throw InvalidGenerationSource(
      'Cache type ${type.getDisplayString()} needs supported JSON types or toJson/fromJson codecs',
    );
  }

  String _decode(DartType type, String value, {bool nullable = true}) {
    if (nullable && type.nullabilitySuffix == NullabilitySuffix.question) {
      return '$value == null ? null : ${_decode(type, value, nullable: false)}';
    }
    final t = _interface(type);
    final name = t.element.name;
    final display = t.getDisplayString().replaceFirst(RegExp(r'\?$'), '');
    if (['String', 'int', 'double', 'bool', 'num'].contains(name)) {
      return '$value as $display';
    }
    if (name == 'Uri') return 'Uri.parse($value as String)';
    if (name == 'DateTime') return 'DateTime.parse($value as String).toUtc()';
    if (t.element is EnumElement) {
      return '$display.values.byName($value as String)';
    }
    if (name == 'List') {
      return '($value as List).map((item)=>${_decode(t.typeArguments.single, 'item')}).toList()';
    }
    if (name == 'Map' && t.typeArguments.first.isDartCoreString) {
      return '($value as Map<String,dynamic>).map((key,item)=>MapEntry(key,${_decode(t.typeArguments.last, 'item')}))';
    }
    if (t.element.getMethod('toJson') != null &&
        t.element.getNamedConstructor('fromJson') != null) {
      return '$display.fromJson($value as Map<String,dynamic>)';
    }
    throw InvalidGenerationSource(
      'Cache type ${type.getDisplayString()} needs a JSON codec',
    );
  }

  String _typeId(DartType type) {
    if (type is! InterfaceType) return type.getDisplayString();
    return '${type.element.library.uri}#${type.element.name}<${type.typeArguments.map(_typeId).join(',')}>${type.nullabilitySuffix == NullabilitySuffix.question ? '?' : ''}';
  }

  InterfaceType _interface(DartType type) {
    if (type is! InterfaceType) {
      throw InvalidGenerationSource(
        'Unsupported cache type ${type.getDisplayString()}',
      );
    }
    return type;
  }
}
