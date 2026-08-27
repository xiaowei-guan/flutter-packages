// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:path/path.dart' as path;

import '../ast.dart';
import '../generator.dart';
import '../generator_tools.dart';
import '../pigeon_lib.dart';

/// Options that control how C++ FFI adapter code will be generated.
class CppFfiOptions {
  /// Creates a [CppFfiOptions] object.
  const CppFfiOptions({
    this.headerIncludePath,
    this.apiHeaderIncludePath,
    this.namespace,
    this.copyrightHeader,
  });

  /// The generated FFI header include path used by the generated FFI source.
  final String? headerIncludePath;

  /// The generated C++ API header include path used by the generated FFI header.
  final String? apiHeaderIncludePath;

  /// The namespace where the generated C++ API lives.
  final String? namespace;

  /// A copyright header that will get prepended to generated code.
  final Iterable<String>? copyrightHeader;

  /// Creates a [CppFfiOptions] from a Map representation where:
  /// `x = CppFfiOptions.fromMap(x.toMap())`.
  static CppFfiOptions fromMap(Map<String, Object> map) {
    return CppFfiOptions(
      headerIncludePath: map['headerIncludePath'] as String?,
      apiHeaderIncludePath: map['apiHeaderIncludePath'] as String?,
      namespace: map['namespace'] as String?,
      copyrightHeader: map['copyrightHeader'] as Iterable<String>?,
    );
  }

  /// Converts a [CppFfiOptions] to a Map representation where:
  /// `x = CppFfiOptions.fromMap(x.toMap())`.
  Map<String, Object> toMap() {
    return <String, Object>{
      if (headerIncludePath != null) 'headerIncludePath': headerIncludePath!,
      if (apiHeaderIncludePath != null) 'apiHeaderIncludePath': apiHeaderIncludePath!,
      if (namespace != null) 'namespace': namespace!,
      if (copyrightHeader != null) 'copyrightHeader': copyrightHeader!,
    };
  }

  /// Overrides any non-null parameters from [options] into this to make a new
  /// [CppFfiOptions].
  CppFfiOptions merge(CppFfiOptions options) {
    return CppFfiOptions.fromMap(mergeMaps(toMap(), options.toMap()));
  }
}

/// Options that control how C++ FFI adapter code will be generated.
///
/// For internal use only.
class InternalCppFfiOptions extends InternalOptions {
  /// Creates an [InternalCppFfiOptions] object.
  const InternalCppFfiOptions({
    required this.headerIncludePath,
    required this.apiHeaderIncludePath,
    required this.cppFfiHeaderOut,
    required this.cppFfiSourceOut,
    this.namespace,
    this.copyrightHeader,
  });

  /// Creates [InternalCppFfiOptions] from [CppFfiOptions].
  InternalCppFfiOptions.fromCppFfiOptions(
    CppFfiOptions options, {
    required this.cppFfiHeaderOut,
    required this.cppFfiSourceOut,
    required String fallbackApiHeaderIncludePath,
    Iterable<String>? copyrightHeader,
  }) : headerIncludePath = options.headerIncludePath ?? path.basename(cppFfiHeaderOut),
       apiHeaderIncludePath = options.apiHeaderIncludePath ?? fallbackApiHeaderIncludePath,
       namespace = options.namespace,
       copyrightHeader = options.copyrightHeader ?? copyrightHeader;

  /// The generated FFI header include path used by the generated FFI source.
  final String headerIncludePath;

  /// The generated C++ API header include path used by the generated FFI header.
  final String apiHeaderIncludePath;

  /// Path to the ".h" C++ FFI adapter file that will be generated.
  final String cppFfiHeaderOut;

  /// Path to the ".cpp" C++ FFI adapter file that will be generated.
  final String cppFfiSourceOut;

  /// The namespace where the generated C++ API lives.
  final String? namespace;

  /// A copyright header that will get prepended to generated code.
  final Iterable<String>? copyrightHeader;
}

/// Class that manages all C++ FFI adapter code generation.
class CppFfiGenerator extends Generator<OutputFileOptions<InternalCppFfiOptions>> {
  /// Constructor.
  const CppFfiGenerator();

  /// Generates C++ FFI adapter file of type specified in [generatorOptions].
  @override
  void generate(
    OutputFileOptions<InternalCppFfiOptions> generatorOptions,
    Root root,
    StringSink sink, {
    required String dartPackageName,
  }) {
    assert(
      generatorOptions.fileType == FileType.header || generatorOptions.fileType == FileType.source,
    );

    final indent = Indent();
    _writeFilePrologue(generatorOptions.languageOptions, indent);
    if (generatorOptions.fileType == FileType.header) {
      _writeHeader(generatorOptions.languageOptions, root, indent);
    } else {
      _writeSource(generatorOptions.languageOptions, root, indent);
    }
    sink.write(indent.toString());
  }
}

void _writeFilePrologue(InternalCppFfiOptions generatorOptions, Indent indent) {
  if (generatorOptions.copyrightHeader != null) {
    addLines(indent, generatorOptions.copyrightHeader!, linePrefix: '// ');
  }
  indent.writeln('// ${getGeneratedCodeWarning()}');
  indent.writeln('// $seeAlsoWarning');
  indent.newln();
}

void _writeHeader(InternalCppFfiOptions options, Root root, Indent indent) {
  final String guardName = _getGuardName(options.headerIncludePath);
  indent.writeln('#ifndef $guardName');
  indent.writeln('#define $guardName');
  indent.newln();
  indent.writeln('#include <stddef.h>');
  indent.writeln('#include <stdint.h>');
  indent.newln();
  indent.writeln('#ifdef __cplusplus');
  indent.writeln('#include "${options.apiHeaderIncludePath}"');
  indent.writeln('#endif');
  indent.newln();
  indent.format(r'''
#if defined(_WIN32)
#define PIGEON_FFI_EXPORT __declspec(dllexport)
#else
#define PIGEON_FFI_EXPORT __attribute__((visibility("default")))
#endif
''');
  indent.writeln('#ifdef __cplusplus');
  indent.writeln('extern "C" {');
  indent.writeln('#endif');
  indent.newln();
  indent.format(r'''
typedef struct PigeonFfiBuffer {
  uint8_t* data;
  size_t length;
} PigeonFfiBuffer;
''');
  indent.writeln('// Frees a buffer returned by a generated FFI function.');
  indent.writeln('PIGEON_FFI_EXPORT void pigeon_free_buffer(PigeonFfiBuffer* buffer);');
  indent.writeln(
    '// The caller owns request; the returned buffer must be freed with pigeon_free_buffer.',
  );
  for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
    for (final Method method in api.methods) {
      indent.writeln(
        'PIGEON_FFI_EXPORT PigeonFfiBuffer* ${_ffiFunctionName(api, method)}(PigeonFfiBuffer* request);',
      );
    }
  }
  indent.newln();
  indent.writeln('#ifdef __cplusplus');
  indent.writeln('}');
  indent.writeln('#endif');
  indent.newln();
  indent.writeln('#ifdef __cplusplus');
  _writeCppSetUpDeclarations(options, root, indent);
  indent.writeln('#endif');
  indent.newln();
  indent.writeln('#endif  // $guardName');
}

void _writeCppSetUpDeclarations(InternalCppFfiOptions options, Root root, Indent indent) {
  void writeDeclarations() {
    for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
      indent.writeln('void SetUp${api.name}Ffi(${api.name}* api);');
    }
  }

  if (options.namespace == null) {
    writeDeclarations();
    return;
  }
  indent.writeln('namespace ${options.namespace} {');
  indent.nest(1, writeDeclarations);
  indent.writeln('}  // namespace ${options.namespace}');
}

void _writeSource(InternalCppFfiOptions options, Root root, Indent indent) {
  indent.writeln('#include "${options.headerIncludePath}"');
  indent.newln();
  indent.writeln('#include <any>');
  indent.writeln('#include <cstring>');
  indent.writeln('#include <memory>');
  indent.writeln('#include <string>');
  indent.writeln('#include <vector>');
  indent.newln();
  indent.writeln('namespace {');
  indent.nest(1, () {
    indent.format(r'''
PigeonFfiBuffer* PigeonFfiMakeBuffer(const std::vector<uint8_t>& message) {
  auto* buffer = new PigeonFfiBuffer();
  buffer->length = message.size();
  buffer->data = nullptr;
  if (!message.empty()) {
    buffer->data = new uint8_t[message.size()];
    std::memcpy(buffer->data, message.data(), message.size());
  }
  return buffer;
}

PigeonFfiBuffer* PigeonFfiEncodeMessage(
    const ::flutter::StandardMessageCodec& codec,
    const ::flutter::EncodableValue& value) {
  std::unique_ptr<std::vector<uint8_t>> message = codec.EncodeMessage(value);
  return PigeonFfiMakeBuffer(*message);
}

PigeonFfiBuffer* PigeonFfiEncodeError(
    const ::flutter::StandardMessageCodec& codec,
    const ::flutter::EncodableValue& error) {
  return PigeonFfiEncodeMessage(codec, error);
}
''');
  });
  indent.writeln('}  // namespace');
  indent.newln();
  indent.format(r'''
void pigeon_free_buffer(PigeonFfiBuffer* buffer) {
  if (buffer == nullptr) {
    return;
  }
  delete[] buffer->data;
  delete buffer;
}
''');

  if (options.namespace != null) {
    indent.writeln('namespace ${options.namespace} {');
  }
  for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
    _writeApiSource(indent, api);
  }
  if (options.namespace != null) {
    indent.writeln('}  // namespace ${options.namespace}');
    indent.newln();
  }

  for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
    for (final Method method in api.methods) {
      final String qualifiedHelper = options.namespace == null
          ? _ffiHelperName(api, method)
          : '${options.namespace}::${_ffiHelperName(api, method)}';
      indent.writeln(
        'extern "C" PigeonFfiBuffer* ${_ffiFunctionName(api, method)}(PigeonFfiBuffer* request) {',
      );
      indent.nest(1, () {
        indent.writeln('return $qualifiedHelper(request);');
      });
      indent.writeln('}');
      indent.newln();
    }
  }
}

void _writeApiSource(Indent indent, AstHostApi api) {
  indent.newln();
  indent.writeln('namespace {');
  indent.nest(1, () {
    indent.writeln('${api.name}* ${_apiVariable(api)} = nullptr;');
  });
  indent.writeln('}  // namespace');
  indent.newln();
  indent.writeln('void SetUp${api.name}Ffi(${api.name}* api) {');
  indent.nest(1, () {
    indent.writeln('${_apiVariable(api)} = api;');
  });
  indent.writeln('}');
  indent.newln();
  for (final Method method in api.methods) {
    _writeMethodSource(indent, api, method);
  }
}

void _writeMethodSource(Indent indent, AstHostApi api, Method method) {
  indent.writeln('PigeonFfiBuffer* ${_ffiHelperName(api, method)}(PigeonFfiBuffer* request) {');
  indent.nest(1, () {
    indent.writeln('const auto& codec = ${api.name}::GetCodec();');
    indent.writeScoped('if (${_apiVariable(api)} == nullptr) {', '}', () {
      indent.writeln(
        'return PigeonFfiEncodeError(codec, ${api.name}::WrapError("${api.name} has not been set up."));',
      );
    });
    indent.writeScoped('try {', '}', () {
      final List<String> methodArguments = <String>[];
      if (method.parameters.isNotEmpty) {
        indent.writeScoped('if (request == nullptr || request->data == nullptr) {', '}', () {
          indent.writeln(
            'return PigeonFfiEncodeError(codec, ${api.name}::WrapError("Request buffer is null."));',
          );
        });
        indent.writeln(
          'std::unique_ptr<::flutter::EncodableValue> message = codec.DecodeMessage(request->data, request->length);',
        );
        indent.writeScoped('if (!message) {', '}', () {
          indent.writeln(
            'return PigeonFfiEncodeError(codec, ${api.name}::WrapError("Unable to decode request."));',
          );
        });
        indent.writeln('const auto* args = std::get_if<::flutter::EncodableList>(message.get());');
        indent.writeScoped(
          'if (args == nullptr || args->size() != ${method.parameters.length}) {',
          '}',
          () {
            indent.writeln(
              'return PigeonFfiEncodeError(codec, ${api.name}::WrapError("Unexpected request arguments."));',
            );
          },
        );
        for (var index = 0; index < method.parameters.length; index++) {
          final Parameter parameter = method.parameters[index];
          final HostDatatype hostType = getHostDatatype(
            parameter.type,
            _baseCppTypeForBuiltinDartType,
          );
          final String argName = _safeArgumentName(index, parameter);
          final String encodableArgName = 'encodable_$argName';
          indent.writeln('const auto& $encodableArgName = args->at($index);');
          if (!parameter.type.isNullable) {
            indent.writeScoped('if ($encodableArgName.IsNull()) {', '}', () {
              indent.writeln(
                'return PigeonFfiEncodeError(codec, ${api.name}::WrapError("$argName unexpectedly null."));',
              );
            });
          }
          _writeEncodableValueArgumentUnwrapping(
            indent,
            hostType,
            argName: argName,
            encodableArgName: encodableArgName,
          );
          methodArguments.add(argName);
        }
      }

      final HostDatatype returnType = getHostDatatype(
        method.returnType,
        _baseCppTypeForBuiltinDartType,
      );
      final String returnTypeName = _hostApiReturnType(returnType);
      final String call =
          '${_apiVariable(api)}->${_methodName(method)}(${methodArguments.join(', ')})';
      indent.writeln('$returnTypeName output = $call;');
      _writeReturnEncoding(indent, method.returnType, returnType, api.name);
    }, addTrailingNewline: false);
    indent.add(' catch (const std::exception& exception) ');
    indent.addScoped('{', '}', () {
      indent.writeln(
        'return PigeonFfiEncodeError(codec, ${api.name}::WrapError(exception.what()));',
      );
    });
  });
  indent.writeln('}');
  indent.newln();
}

void _writeReturnEncoding(
  Indent indent,
  TypeDeclaration dartReturnType,
  HostDatatype hostReturnType,
  String apiName,
) {
  if (dartReturnType.isVoid) {
    indent.writeScoped('if (output.has_value()) {', '}', () {
      indent.writeln('return PigeonFfiEncodeError(codec, $apiName::WrapError(output.value()));');
    });
    _writeNullSuccess(indent);
    return;
  }

  indent.writeScoped('if (output.has_error()) {', '}', () {
    indent.writeln('return PigeonFfiEncodeError(codec, $apiName::WrapError(output.error()));');
  });
  final String wrapperType = hostReturnType.isBuiltin
      ? '::flutter::EncodableValue'
      : '::flutter::CustomEncodableValue';
  if (dartReturnType.isNullable) {
    indent.writeln('auto output_optional = std::move(output).TakeValue();');
    indent.writeScoped('if (output_optional) {', '} else {', () {
      final encodedValue = '$wrapperType(std::move(output_optional).value())';
      indent.writeln(
        'return PigeonFfiEncodeMessage(codec, '
        '::flutter::EncodableValue(::flutter::EncodableList{$encodedValue}));',
      );
    });
    indent.addScoped(null, '}', () {
      _writeNullSuccess(indent);
    });
    return;
  }
  indent.writeln(
    'return PigeonFfiEncodeMessage(codec, '
    '::flutter::EncodableValue(::flutter::EncodableList{'
    '$wrapperType(std::move(output).TakeValue())}));',
  );
}

void _writeNullSuccess(Indent indent) {
  indent.writeln(
    'return PigeonFfiEncodeMessage(codec, '
    '::flutter::EncodableValue(::flutter::EncodableList{::flutter::EncodableValue()}));',
  );
}

void _writeEncodableValueArgumentUnwrapping(
  Indent indent,
  HostDatatype hostType, {
  required String argName,
  required String encodableArgName,
}) {
  if (hostType.isNullable) {
    if (hostType.datatype == '::flutter::EncodableValue') {
      indent.writeln('const auto* $argName = &$encodableArgName;');
    } else if (hostType.isBuiltin) {
      indent.writeln(
        'const auto* $argName = std::get_if<${hostType.datatype}>(&$encodableArgName);',
      );
    } else if (hostType.isEnum) {
      indent.format('''
${hostType.datatype} ${argName}_value;
const ${hostType.datatype}* $argName = nullptr;
if (!$encodableArgName.IsNull()) {
  ${argName}_value = static_cast<${hostType.datatype}>($encodableArgName.LongValue());
  $argName = &${argName}_value;
}''');
    } else {
      final castExpression =
          'std::any_cast<const ${hostType.datatype}&>('
          'std::get<::flutter::CustomEncodableValue>($encodableArgName))';
      indent.writeln(
        'const auto* $argName = $encodableArgName.IsNull() ? nullptr : &($castExpression);',
      );
    }
    return;
  }

  if (hostType.datatype == 'int64_t') {
    indent.writeln('const int64_t $argName = $encodableArgName.LongValue();');
  } else if (hostType.datatype == '::flutter::EncodableValue') {
    indent.writeln('const auto& $argName = $encodableArgName;');
  } else if (hostType.isBuiltin) {
    indent.writeln('const auto& $argName = std::get<${hostType.datatype}>($encodableArgName);');
  } else if (hostType.isEnum) {
    indent.writeln(
      'const auto $argName = static_cast<${hostType.datatype}>($encodableArgName.LongValue());',
    );
  } else {
    final castExpression =
        'std::any_cast<const ${hostType.datatype}&>('
        'std::get<::flutter::CustomEncodableValue>($encodableArgName))';
    indent.writeln('const auto& $argName = $castExpression;');
  }
}

/// Validates whether the C++ FFI generator can support [root].
List<Error> validateCppFfi(InternalCppFfiOptions options, Root root) {
  final errors = <Error>[];
  if (options.apiHeaderIncludePath.isEmpty) {
    errors.add(
      Error(
        message:
            'C++ FFI requires cppHeaderOut or cppFfiOptions.apiHeaderIncludePath '
            'so the adapter can include the generated C++ API header',
      ),
    );
  }
  for (final Api api in root.apis) {
    switch (api) {
      case AstHostApi():
        for (final Method method in api.methods) {
          if (method.isAsynchronous) {
            errors.add(
              Error(message: 'C++ FFI does not support async HostApi method "${method.name}"'),
            );
          }
        }
      case AstFlutterApi():
        errors.add(Error(message: 'C++ FFI does not support FlutterApi "${api.name}"'));
      case AstEventChannelApi():
        errors.add(Error(message: 'C++ FFI does not support EventChannelApi "${api.name}"'));
      case AstProxyApi():
        errors.add(Error(message: 'C++ FFI does not support ProxyApi "${api.name}"'));
    }
  }
  return errors;
}

String _getGuardName(String headerFileName) {
  return 'PIGEON_${headerFileName.replaceAll('.', '_').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_').toUpperCase()}_';
}

String? _baseCppTypeForBuiltinDartType(TypeDeclaration type) {
  const cppTypeForDartTypeMap = <String, String>{
    'void': 'void',
    'bool': 'bool',
    'int': 'int64_t',
    'String': 'std::string',
    'double': 'double',
    'Uint8List': 'std::vector<uint8_t>',
    'Int32List': 'std::vector<int32_t>',
    'Int64List': 'std::vector<int64_t>',
    'Float64List': 'std::vector<double>',
    'Map': '::flutter::EncodableMap',
    'List': '::flutter::EncodableList',
    'Object': '::flutter::EncodableValue',
  };
  return cppTypeForDartTypeMap[type.baseName];
}

String _hostApiReturnType(HostDatatype type) {
  if (type.datatype == 'void') {
    return 'std::optional<FlutterError>';
  }
  var valueType = type.datatype;
  if (type.isNullable) {
    valueType = 'std::optional<$valueType>';
  }
  return 'ErrorOr<$valueType>';
}

String _methodName(Method method) => method.name[0].toUpperCase() + method.name.substring(1);

String _safeArgumentName(int count, NamedType argument) {
  final name = argument.name.isEmpty ? 'arg$count' : _makeVariableName(argument.name);
  return '${name}_arg';
}

String _makeVariableName(String name) {
  return name.replaceAllMapped(RegExp(r'[A-Z]'), (Match match) => '_${match[0]!.toLowerCase()}');
}

String _ffiFunctionName(AstHostApi api, Method method) {
  return 'pigeon_${_snakeCase(api.name)}_${_snakeCase(method.name)}';
}

String _ffiHelperName(AstHostApi api, Method method) {
  return 'Pigeon${api.name}${_methodName(method)}Ffi';
}

String _apiVariable(AstHostApi api) => 'g_${_snakeCase(api.name)}_api';

String _snakeCase(String name) {
  return name.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (Match match) => '${match.start == 0 ? '' : '_'}${match[0]!.toLowerCase()}',
  );
}
