// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:path/path.dart' as path;

import '../ast.dart';
import '../generator.dart';
import '../generator_tools.dart';
import '../pigeon_lib.dart';

const String _codecSerializerName = '${classNamePrefix}CodecSerializer';

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
    return CppFfiOptions.fromMap(mergePigeonMaps(toMap(), options.toMap()));
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
    String? fallbackNamespace,
    Iterable<String>? copyrightHeader,
  }) : headerIncludePath = options.headerIncludePath ?? path.basename(cppFfiHeaderOut),
       apiHeaderIncludePath = options.apiHeaderIncludePath ?? fallbackApiHeaderIncludePath,
       namespace = options.namespace ?? fallbackNamespace,
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
  indent.writeln('#include <functional>');
  indent.writeln('#include <memory>');
  indent.writeln('#include <optional>');
  indent.writeln('#include <string>');
  indent.writeln('#include <vector>');
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

typedef void (*PigeonFfiReplyCallback)(int64_t reply_id, PigeonFfiBuffer* reply);
typedef void (*PigeonFfiEventCallback)(int64_t sink_id, PigeonFfiBuffer* event);
typedef void (*PigeonFfiDoneCallback)(int64_t sink_id);
''');
  indent.writeln('// Frees a buffer returned by a generated FFI function.');
  indent.writeln('PIGEON_FFI_EXPORT void pigeon_free_buffer(PigeonFfiBuffer* buffer);');
  indent.writeln(
    '// The caller owns request; the returned buffer must be freed with pigeon_free_buffer.',
  );
  for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
    for (final Method method in api.methods) {
      if (method.isAsynchronous || method.isAsynchronousCallback) {
        indent.writeln('PIGEON_FFI_EXPORT void ${_ffiFunctionName(api, method)}(');
        indent.nest(1, () {
          indent.writeln('PigeonFfiBuffer* request,');
          indent.writeln('int64_t reply_id,');
          indent.writeln('PigeonFfiReplyCallback on_reply);');
        });
      } else {
        indent.writeln(
          'PIGEON_FFI_EXPORT PigeonFfiBuffer* ${_ffiFunctionName(api, method)}(PigeonFfiBuffer* request);',
        );
      }
    }
  }
  for (final AstEventChannelApi api in root.apis.whereType<AstEventChannelApi>()) {
    for (final Method method in api.methods) {
      indent.writeln(
        'PIGEON_FFI_EXPORT PigeonFfiBuffer* ${_eventListenFunctionName(api, method)}(',
      );
      indent.nest(1, () {
        indent.writeln('PigeonFfiBuffer* request,');
        indent.writeln('int64_t sink_id,');
        indent.writeln('PigeonFfiEventCallback on_event,');
        indent.writeln('PigeonFfiEventCallback on_error,');
        indent.writeln('PigeonFfiDoneCallback on_done);');
      });
      indent.writeln(
        'PIGEON_FFI_EXPORT PigeonFfiBuffer* ${_eventCancelFunctionName(api, method)}(',
      );
      indent.nest(1, () {
        indent.writeln('PigeonFfiBuffer* request,');
        indent.writeln('int64_t sink_id);');
      });
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
  final List<AstHostApi> hostApis = root.apis.whereType<AstHostApi>().toList();
  final List<AstEventChannelApi> eventChannelApis = root.apis
      .whereType<AstEventChannelApi>()
      .toList();
  if (hostApis.isEmpty && eventChannelApis.isEmpty) {
    return;
  }

  void writeDeclarations() {
    indent.format(r'''
class PigeonFfiSyncDispatcher {
 public:
  virtual ~PigeonFfiSyncDispatcher() = default;
  virtual ::PigeonFfiBuffer* RunSync(
      std::function<::PigeonFfiBuffer*()> task) = 0;
};

''');
    for (final AstHostApi api in hostApis) {
      indent.writeln('void SetUp${api.name}Ffi(');
      indent.nest(1, () {
        indent.writeln('${api.name}* api,');
        indent.writeln('PigeonFfiSyncDispatcher* dispatcher = nullptr);');
      });
    }
    for (final AstEventChannelApi api in eventChannelApis) {
      for (final Method method in api.methods) {
        _writeEventChannelSetUpDeclaration(indent, api, method);
      }
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

void _writeEventChannelSetUpDeclaration(Indent indent, AstEventChannelApi api, Method method) {
  final HostDatatype eventType = getHostDatatype(method.returnType, _baseCppTypeForBuiltinDartType);
  final String sinkName = _eventSinkName(api, method);
  final String handlerName = _eventStreamHandlerName(api, method);
  indent.newln();
  indent.writeln('class $sinkName {');
  indent.nest(1, () {
    indent.writeln('public:');
    indent.nest(1, () {
      indent.writeln('virtual ~$sinkName() = default;');
      indent.writeln('virtual void Success(${_eventSinkParameterType(eventType)}) = 0;');
      indent.writeln('virtual void Error(const FlutterError& error) = 0;');
      indent.writeln('virtual void EndOfStream() = 0;');
    });
  });
  indent.writeln('};');
  indent.newln();
  indent.writeln('class $handlerName {');
  indent.nest(1, () {
    indent.writeln('public:');
    indent.nest(1, () {
      indent.writeln('virtual ~$handlerName() = default;');
      indent.writeln('virtual std::optional<FlutterError> OnListen(');
      indent.nest(1, () {
        indent.writeln('const std::string& instance_name,');
        indent.writeln('std::unique_ptr<$sinkName> sink) {');
      });
      indent.nest(1, () {
        indent.writeln('(void)instance_name;');
        indent.writeln('(void)sink;');
        indent.writeln('return std::nullopt;');
      });
      indent.writeln('}');
      indent.writeln('virtual std::optional<FlutterError> OnCancel(');
      indent.nest(1, () {
        indent.writeln('const std::string& instance_name) {');
      });
      indent.nest(1, () {
        indent.writeln('(void)instance_name;');
        indent.writeln('return std::nullopt;');
      });
      indent.writeln('}');
    });
  });
  indent.writeln('};');
  indent.newln();
  indent.writeln('void SetUp${api.name}${_methodName(method)}Ffi(');
  indent.nest(1, () {
    indent.writeln('$handlerName* handler,');
    indent.writeln('PigeonFfiSyncDispatcher* dispatcher = nullptr);');
  });
}

void _writeSource(InternalCppFfiOptions options, Root root, Indent indent) {
  indent.writeln('#include "${options.headerIncludePath}"');
  indent.newln();
  indent.writeln('#include <any>');
  indent.writeln('#include <cstring>');
  indent.writeln('#include <memory>');
  indent.writeln('#include <string>');
  indent.writeln('#include <utility>');
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

PigeonFfiBuffer* PigeonFfiEncodeErrorMessage(
    const ::flutter::StandardMessageCodec& codec,
    const std::string& message) {
  return PigeonFfiEncodeError(
      codec,
      ::flutter::EncodableValue(::flutter::EncodableList{
          ::flutter::EncodableValue("error"),
          ::flutter::EncodableValue(message),
          ::flutter::EncodableValue()}));
}

void PigeonFfiSendReply(
    int64_t reply_id,
    PigeonFfiReplyCallback on_reply,
    PigeonFfiBuffer* reply) {
  if (on_reply == nullptr) {
    pigeon_free_buffer(reply);
    return;
  }
  on_reply(reply_id, reply);
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
  if (root.apis.any((Api api) => api is AstEventChannelApi)) {
    _writeEventChannelUtilities(indent);
  }
  for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
    _writeApiSource(indent, api);
  }
  for (final AstEventChannelApi api in root.apis.whereType<AstEventChannelApi>()) {
    _writeEventChannelApiSource(indent, api);
  }
  if (options.namespace != null) {
    indent.writeln('}  // namespace ${options.namespace}');
    indent.newln();
  }

  for (final AstHostApi api in root.apis.whereType<AstHostApi>()) {
    for (final Method method in api.methods) {
      final String qualifiedHelper = options.namespace == null
          ? _ffiDispatchHelperName(api, method)
          : '${options.namespace}::${_ffiDispatchHelperName(api, method)}';
      if (method.isAsynchronous || method.isAsynchronousCallback) {
        indent.writeln('extern "C" void ${_ffiFunctionName(api, method)}(');
        indent.nest(1, () {
          indent.writeln('PigeonFfiBuffer* request,');
          indent.writeln('int64_t reply_id,');
          indent.writeln('PigeonFfiReplyCallback on_reply) {');
        });
        indent.nest(1, () {
          indent.writeln('$qualifiedHelper(request, reply_id, on_reply);');
        });
        indent.writeln('}');
        indent.newln();
      } else {
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
  for (final AstEventChannelApi api in root.apis.whereType<AstEventChannelApi>()) {
    for (final Method method in api.methods) {
      final String qualifiedListenHelper = options.namespace == null
          ? _eventListenDispatchHelperName(api, method)
          : '${options.namespace}::${_eventListenDispatchHelperName(api, method)}';
      indent.writeln('extern "C" PigeonFfiBuffer* ${_eventListenFunctionName(api, method)}(');
      indent.nest(1, () {
        indent.writeln('PigeonFfiBuffer* request,');
        indent.writeln('int64_t sink_id,');
        indent.writeln('PigeonFfiEventCallback on_event,');
        indent.writeln('PigeonFfiEventCallback on_error,');
        indent.writeln('PigeonFfiDoneCallback on_done) {');
      });
      indent.nest(1, () {
        indent.writeln(
          'return $qualifiedListenHelper(request, sink_id, on_event, on_error, on_done);',
        );
      });
      indent.writeln('}');
      indent.newln();

      final String qualifiedCancelHelper = options.namespace == null
          ? _eventCancelDispatchHelperName(api, method)
          : '${options.namespace}::${_eventCancelDispatchHelperName(api, method)}';
      indent.writeln('extern "C" PigeonFfiBuffer* ${_eventCancelFunctionName(api, method)}(');
      indent.nest(1, () {
        indent.writeln('PigeonFfiBuffer* request,');
        indent.writeln('int64_t sink_id) {');
      });
      indent.nest(1, () {
        indent.writeln('return $qualifiedCancelHelper(request, sink_id);');
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
    indent.writeln('PigeonFfiSyncDispatcher* ${_dispatcherVariable(api)} = nullptr;');
  });
  indent.writeln('}  // namespace');
  indent.newln();
  indent.writeln('void SetUp${api.name}Ffi(');
  indent.nest(1, () {
    indent.writeln('${api.name}* api,');
    indent.writeln('PigeonFfiSyncDispatcher* dispatcher) {');
  });
  indent.nest(1, () {
    indent.writeln('${_apiVariable(api)} = api;');
    indent.writeln('${_dispatcherVariable(api)} = dispatcher;');
  });
  indent.writeln('}');
  indent.newln();
  for (final Method method in api.methods) {
    if (method.isAsynchronous || method.isAsynchronousCallback) {
      _writeAsyncMethodSource(indent, api, method);
      _writeAsyncMethodDispatchSource(indent, api, method);
    } else {
      _writeMethodSource(indent, api, method);
      _writeMethodDispatchSource(indent, api, method);
    }
  }
}

void _writeEventChannelUtilities(Indent indent) {
  indent.newln();
  indent.format('''
const ::flutter::StandardMessageCodec& PigeonFfiGetCodec() {
\treturn ::flutter::StandardMessageCodec::GetInstance(
\t\t\t&$_codecSerializerName::GetInstance());
}

PigeonFfiBuffer* PigeonFfiEncodeFlutterError(
\t\tconst ::flutter::StandardMessageCodec& codec,
\t\tconst FlutterError& error) {
\treturn PigeonFfiEncodeError(
\t\t\tcodec,
\t\t\t::flutter::EncodableValue(::flutter::EncodableList{
\t\t\t\t\t::flutter::EncodableValue(error.code()),
\t\t\t\t\t::flutter::EncodableValue(error.message()),
\t\t\t\t\terror.details()}));
}

PigeonFfiBuffer* PigeonFfiDecodeInstanceName(
\t\tconst ::flutter::StandardMessageCodec& codec,
\t\tPigeonFfiBuffer* request,
\t\tstd::string* instance_name) {
\tif (request == nullptr || request->data == nullptr) {
\t\treturn PigeonFfiEncodeErrorMessage(codec, "Request buffer is null.");
\t}
\tstd::unique_ptr<::flutter::EncodableValue> message =
\t\t\tcodec.DecodeMessage(request->data, request->length);
\tif (!message) {
\t\treturn PigeonFfiEncodeErrorMessage(codec, "Unable to decode request.");
\t}
\tconst auto* args = std::get_if<::flutter::EncodableList>(message.get());
\tif (args == nullptr || args->size() != 1) {
\t\treturn PigeonFfiEncodeErrorMessage(
\t\t\t\tcodec, "Unexpected event channel listen arguments.");
\t}
\tconst auto* instance_name_arg = std::get_if<std::string>(&args->at(0));
\tif (instance_name_arg == nullptr) {
\t\treturn PigeonFfiEncodeErrorMessage(codec, "Instance name must be a string.");
\t}
\t*instance_name = *instance_name_arg;
\treturn nullptr;
}
''');
}

void _writeEventChannelApiSource(Indent indent, AstEventChannelApi api) {
  for (final Method method in api.methods) {
    _writeEventChannelMethodSource(indent, api, method);
  }
}

void _writeEventChannelMethodSource(Indent indent, AstEventChannelApi api, Method method) {
  final HostDatatype eventType = getHostDatatype(method.returnType, _baseCppTypeForBuiltinDartType);
  final String sinkName = _eventSinkName(api, method);
  final String sinkImplName = _eventSinkImplName(api, method);
  final String handlerName = _eventStreamHandlerName(api, method);
  final String handlerVariable = _eventHandlerVariable(api, method);
  final String dispatcherVariable = _eventDispatcherVariable(api, method);

  indent.newln();
  indent.writeln('namespace {');
  indent.nest(1, () {
    indent.writeln('$handlerName* $handlerVariable = nullptr;');
    indent.writeln('PigeonFfiSyncDispatcher* $dispatcherVariable = nullptr;');
  });
  indent.writeln('}  // namespace');
  indent.newln();
  indent.writeln('void SetUp${api.name}${_methodName(method)}Ffi(');
  indent.nest(1, () {
    indent.writeln('$handlerName* handler,');
    indent.writeln('PigeonFfiSyncDispatcher* dispatcher) {');
  });
  indent.nest(1, () {
    indent.writeln('$handlerVariable = handler;');
    indent.writeln('$dispatcherVariable = dispatcher;');
  });
  indent.writeln('}');
  indent.newln();

  _writeEventSinkImpl(indent, sinkName, sinkImplName, eventType);
  _writeEventListenSource(indent, api, method, sinkImplName, handlerVariable);
  _writeEventCancelSource(indent, api, method, handlerVariable);
  _writeEventListenDispatchSource(indent, api, method, dispatcherVariable);
  _writeEventCancelDispatchSource(indent, api, method, dispatcherVariable);
}

void _writeEventSinkImpl(
  Indent indent,
  String sinkName,
  String sinkImplName,
  HostDatatype eventType,
) {
  final String eventValueExpression = _eventEncodableValueExpression(eventType, 'event');
  final String nullableEventValueExpression = _eventEncodableValueExpression(eventType, '*event');
  indent.writeln('class $sinkImplName : public $sinkName {');
  indent.nest(1, () {
    indent.writeln('public:');
    indent.nest(1, () {
      indent.writeln(
        '$sinkImplName(int64_t sink_id, PigeonFfiEventCallback on_event, '
        'PigeonFfiEventCallback on_error, PigeonFfiDoneCallback on_done)',
      );
      indent.nest(2, () {
        indent.writeln(': sink_id_(sink_id),');
        indent.writeln('  on_event_(on_event),');
        indent.writeln('  on_error_(on_error),');
        indent.writeln('  on_done_(on_done) {}');
      });
      indent.newln();
      indent.writeln('void Success(${_eventSinkParameterType(eventType)}) override {');
      indent.nest(1, () {
        indent.writeScoped('if (on_event_ == nullptr) {', '}', () {
          indent.writeln('return;');
        });
        indent.writeln('const auto& codec = PigeonFfiGetCodec();');
        if (eventType.isNullable) {
          indent.writeScoped('if (event == nullptr) {', '}', () {
            indent.writeln(
              'on_event_(sink_id_, PigeonFfiEncodeMessage(codec, ::flutter::EncodableValue()));',
            );
            indent.writeln('return;');
          });
          indent.writeln(
            'on_event_(sink_id_, PigeonFfiEncodeMessage(codec, '
            '$nullableEventValueExpression));',
          );
        } else {
          indent.writeln(
            'on_event_(sink_id_, PigeonFfiEncodeMessage(codec, '
            '$eventValueExpression));',
          );
        }
      });
      indent.writeln('}');
      indent.newln();
      indent.writeln('void Error(const FlutterError& error) override {');
      indent.nest(1, () {
        indent.writeScoped('if (on_error_ == nullptr) {', '}', () {
          indent.writeln('return;');
        });
        indent.writeln(
          'on_error_(sink_id_, PigeonFfiEncodeFlutterError(PigeonFfiGetCodec(), error));',
        );
      });
      indent.writeln('}');
      indent.newln();
      indent.writeln('void EndOfStream() override {');
      indent.nest(1, () {
        indent.writeScoped('if (on_done_ != nullptr) {', '}', () {
          indent.writeln('on_done_(sink_id_);');
        });
      });
      indent.writeln('}');
      indent.newln();
      indent.writeln('private:');
      indent.nest(1, () {
        indent.writeln('int64_t sink_id_;');
        indent.writeln('PigeonFfiEventCallback on_event_;');
        indent.writeln('PigeonFfiEventCallback on_error_;');
        indent.writeln('PigeonFfiDoneCallback on_done_;');
      });
    });
  });
  indent.writeln('};');
  indent.newln();
}

void _writeEventListenSource(
  Indent indent,
  AstEventChannelApi api,
  Method method,
  String sinkImplName,
  String handlerVariable,
) {
  indent.writeln('PigeonFfiBuffer* ${_eventListenHelperName(api, method)}(');
  indent.nest(1, () {
    indent.writeln('PigeonFfiBuffer* request,');
    indent.writeln('int64_t sink_id,');
    indent.writeln('PigeonFfiEventCallback on_event,');
    indent.writeln('PigeonFfiEventCallback on_error,');
    indent.writeln('PigeonFfiDoneCallback on_done) {');
  });
  indent.nest(1, () {
    indent.writeln('const auto& codec = PigeonFfiGetCodec();');
    indent.writeScoped('if ($handlerVariable == nullptr) {', '}', () {
      indent.writeln(
        'return PigeonFfiEncodeErrorMessage(codec, "${api.name}.${method.name} has not been set up.");',
      );
    });
    indent.writeScoped('try {', '}', () {
      indent.writeln('std::string instance_name;');
      indent.writeln(
        'PigeonFfiBuffer* decode_error = PigeonFfiDecodeInstanceName(codec, request, &instance_name);',
      );
      indent.writeScoped('if (decode_error != nullptr) {', '}', () {
        indent.writeln('return decode_error;');
      });
      indent.writeln(
        'auto sink = std::make_unique<$sinkImplName>(sink_id, on_event, on_error, on_done);',
      );
      indent.writeln(
        'std::optional<FlutterError> output = $handlerVariable->OnListen(instance_name, std::move(sink));',
      );
      indent.writeScoped('if (output.has_value()) {', '}', () {
        indent.writeln('return PigeonFfiEncodeFlutterError(codec, output.value());');
      });
      _writeNullSuccess(indent);
    }, addTrailingNewline: false);
    indent.add(' catch (const std::exception& exception) ');
    indent.addScoped('{', '}', () {
      indent.writeln('return PigeonFfiEncodeErrorMessage(codec, exception.what());');
    });
  });
  indent.writeln('}');
  indent.newln();
}

void _writeEventCancelSource(
  Indent indent,
  AstEventChannelApi api,
  Method method,
  String handlerVariable,
) {
  indent.writeln(
    'PigeonFfiBuffer* ${_eventCancelHelperName(api, method)}(PigeonFfiBuffer* request, int64_t sink_id) {',
  );
  indent.nest(1, () {
    indent.writeln('(void)sink_id;');
    indent.writeln('const auto& codec = PigeonFfiGetCodec();');
    indent.writeScoped('if ($handlerVariable == nullptr) {', '}', () {
      indent.writeln(
        'return PigeonFfiEncodeErrorMessage(codec, "${api.name}.${method.name} has not been set up.");',
      );
    });
    indent.writeScoped('try {', '}', () {
      indent.writeln('std::string instance_name;');
      indent.writeln(
        'PigeonFfiBuffer* decode_error = PigeonFfiDecodeInstanceName(codec, request, &instance_name);',
      );
      indent.writeScoped('if (decode_error != nullptr) {', '}', () {
        indent.writeln('return decode_error;');
      });
      indent.writeln(
        'std::optional<FlutterError> output = $handlerVariable->OnCancel(instance_name);',
      );
      indent.writeScoped('if (output.has_value()) {', '}', () {
        indent.writeln('return PigeonFfiEncodeFlutterError(codec, output.value());');
      });
      _writeNullSuccess(indent);
    }, addTrailingNewline: false);
    indent.add(' catch (const std::exception& exception) ');
    indent.addScoped('{', '}', () {
      indent.writeln('return PigeonFfiEncodeErrorMessage(codec, exception.what());');
    });
  });
  indent.writeln('}');
  indent.newln();
}

void _writeEventListenDispatchSource(
  Indent indent,
  AstEventChannelApi api,
  Method method,
  String dispatcherVariable,
) {
  indent.writeln('PigeonFfiBuffer* ${_eventListenDispatchHelperName(api, method)}(');
  indent.nest(1, () {
    indent.writeln('PigeonFfiBuffer* request,');
    indent.writeln('int64_t sink_id,');
    indent.writeln('PigeonFfiEventCallback on_event,');
    indent.writeln('PigeonFfiEventCallback on_error,');
    indent.writeln('PigeonFfiDoneCallback on_done) {');
  });
  indent.nest(1, () {
    indent.writeScoped('if ($dispatcherVariable != nullptr) {', '}', () {
      indent.writeScoped('return $dispatcherVariable->RunSync([=]() {', '});', () {
        indent.writeln(
          'return ${_eventListenHelperName(api, method)}(request, sink_id, on_event, on_error, on_done);',
        );
      });
    });
    indent.writeln(
      'return ${_eventListenHelperName(api, method)}(request, sink_id, on_event, on_error, on_done);',
    );
  });
  indent.writeln('}');
  indent.newln();
}

void _writeEventCancelDispatchSource(
  Indent indent,
  AstEventChannelApi api,
  Method method,
  String dispatcherVariable,
) {
  indent.writeln(
    'PigeonFfiBuffer* ${_eventCancelDispatchHelperName(api, method)}(PigeonFfiBuffer* request, int64_t sink_id) {',
  );
  indent.nest(1, () {
    indent.writeScoped('if ($dispatcherVariable != nullptr) {', '}', () {
      indent.writeScoped('return $dispatcherVariable->RunSync([=]() {', '});', () {
        indent.writeln('return ${_eventCancelHelperName(api, method)}(request, sink_id);');
      });
    });
    indent.writeln('return ${_eventCancelHelperName(api, method)}(request, sink_id);');
  });
  indent.writeln('}');
  indent.newln();
}

void _writeMethodDispatchSource(Indent indent, AstHostApi api, Method method) {
  indent.writeln(
    'PigeonFfiBuffer* ${_ffiDispatchHelperName(api, method)}(PigeonFfiBuffer* request) {',
  );
  indent.nest(1, () {
    indent.writeScoped('if (${_dispatcherVariable(api)} != nullptr) {', '}', () {
      indent.writeScoped('return ${_dispatcherVariable(api)}->RunSync([request]() {', '});', () {
        indent.writeln('return ${_ffiHelperName(api, method)}(request);');
      });
    });
    indent.writeln('return ${_ffiHelperName(api, method)}(request);');
  });
  indent.writeln('}');
  indent.newln();
}

void _writeAsyncMethodDispatchSource(Indent indent, AstHostApi api, Method method) {
  indent.writeln('void ${_ffiDispatchHelperName(api, method)}(');
  indent.nest(1, () {
    indent.writeln('PigeonFfiBuffer* request,');
    indent.writeln('int64_t reply_id,');
    indent.writeln('PigeonFfiReplyCallback on_reply) {');
  });
  indent.nest(1, () {
    indent.writeScoped('if (${_dispatcherVariable(api)} != nullptr) {', '}', () {
      indent.writeScoped(
        'PigeonFfiBuffer* dispatch_error = ${_dispatcherVariable(api)}->RunSync([=]() {',
        '});',
        () {
          indent.writeln('${_ffiHelperName(api, method)}(request, reply_id, on_reply);');
          indent.writeln('return static_cast<PigeonFfiBuffer*>(nullptr);');
        },
      );
      indent.writeScoped('if (dispatch_error != nullptr) {', '}', () {
        indent.writeln('PigeonFfiSendReply(reply_id, on_reply, dispatch_error);');
      });
      indent.writeln('return;');
    });
    indent.writeln('${_ffiHelperName(api, method)}(request, reply_id, on_reply);');
  });
  indent.writeln('}');
  indent.newln();
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

void _writeAsyncMethodSource(Indent indent, AstHostApi api, Method method) {
  indent.writeln('void ${_ffiHelperName(api, method)}(');
  indent.nest(1, () {
    indent.writeln('PigeonFfiBuffer* request,');
    indent.writeln('int64_t reply_id,');
    indent.writeln('PigeonFfiReplyCallback on_reply) {');
  });
  indent.nest(1, () {
    indent.writeln('const auto& codec = ${api.name}::GetCodec();');
    indent.writeScoped('if (${_apiVariable(api)} == nullptr) {', '}', () {
      indent.writeln(
        'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, ${api.name}::WrapError("${api.name} has not been set up.")));',
      );
      indent.writeln('return;');
    });
    indent.writeScoped('try {', '}', () {
      final List<String> methodArguments = <String>[];
      if (method.parameters.isNotEmpty) {
        indent.writeScoped('if (request == nullptr || request->data == nullptr) {', '}', () {
          indent.writeln(
            'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, ${api.name}::WrapError("Request buffer is null.")));',
          );
          indent.writeln('return;');
        });
        indent.writeln(
          'std::unique_ptr<::flutter::EncodableValue> message = codec.DecodeMessage(request->data, request->length);',
        );
        indent.writeScoped('if (!message) {', '}', () {
          indent.writeln(
            'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, ${api.name}::WrapError("Unable to decode request.")));',
          );
          indent.writeln('return;');
        });
        indent.writeln('const auto* args = std::get_if<::flutter::EncodableList>(message.get());');
        indent.writeScoped(
          'if (args == nullptr || args->size() != ${method.parameters.length}) {',
          '}',
          () {
            indent.writeln(
              'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, ${api.name}::WrapError("Unexpected request arguments.")));',
            );
            indent.writeln('return;');
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
                'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, ${api.name}::WrapError("$argName unexpectedly null.")));',
              );
              indent.writeln('return;');
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
      indent.writeln('${_apiVariable(api)}->${_methodName(method)}(');
      indent.nest(1, () {
        for (final String argument in methodArguments) {
          indent.writeln('$argument,');
        }
        indent.writeln('[reply_id, on_reply]($returnTypeName&& output) {');
        indent.nest(1, () {
          indent.writeln('const auto& codec = ${api.name}::GetCodec();');
          _writeAsyncReplyEncoding(indent, method.returnType, returnType, api.name);
        });
        indent.writeln('});');
      });
    }, addTrailingNewline: false);
    indent.add(' catch (const std::exception& exception) ');
    indent.addScoped('{', '}', () {
      indent.writeln(
        'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, ${api.name}::WrapError(exception.what())));',
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
    indent.writeScoped('if (output.value()) {', '} else {', () {
      final encodedValue = '$wrapperType(output.value().value())';
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
    '$wrapperType(output.value())}));',
  );
}

void _writeAsyncReplyEncoding(
  Indent indent,
  TypeDeclaration dartReturnType,
  HostDatatype hostReturnType,
  String apiName,
) {
  if (dartReturnType.isVoid) {
    indent.writeScoped('if (output.has_value()) {', '}', () {
      indent.writeln(
        'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, $apiName::WrapError(output.value())));',
      );
      indent.writeln('return;');
    });
    indent.writeln(
      'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeMessage(codec, ::flutter::EncodableValue(::flutter::EncodableList{::flutter::EncodableValue()})));',
    );
    return;
  }

  indent.writeScoped('if (output.has_error()) {', '}', () {
    indent.writeln(
      'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeError(codec, $apiName::WrapError(output.error())));',
    );
    indent.writeln('return;');
  });
  final String wrapperType = hostReturnType.isBuiltin
      ? '::flutter::EncodableValue'
      : '::flutter::CustomEncodableValue';
  if (dartReturnType.isNullable) {
    indent.writeScoped('if (output.value()) {', '} else {', () {
      final encodedValue = '$wrapperType(output.value().value())';
      indent.writeln(
        'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeMessage(codec, '
        '::flutter::EncodableValue(::flutter::EncodableList{$encodedValue})));',
      );
    });
    indent.addScoped(null, '}', () {
      indent.writeln(
        'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeMessage(codec, ::flutter::EncodableValue(::flutter::EncodableList{::flutter::EncodableValue()})));',
      );
    });
    return;
  }
  indent.writeln(
    'PigeonFfiSendReply(reply_id, on_reply, PigeonFfiEncodeMessage(codec, '
    '::flutter::EncodableValue(::flutter::EncodableList{'
    '$wrapperType(output.value())})));',
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
        break;
      case AstFlutterApi():
        errors.add(Error(message: 'C++ FFI does not support FlutterApi "${api.name}"'));
      case AstEventChannelApi():
        for (final Method method in api.methods) {
          if (method.returnType.isVoid) {
            errors.add(
              Error(
                message: 'C++ FFI does not support void EventChannelApi method "${method.name}"',
              ),
            );
          }
        }
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

String _ffiDispatchHelperName(AstHostApi api, Method method) {
  return '${_ffiHelperName(api, method)}Dispatch';
}

String _apiVariable(AstHostApi api) => 'g_${_snakeCase(api.name)}_api';

String _dispatcherVariable(AstHostApi api) => 'g_${_snakeCase(api.name)}_dispatcher';

String _eventListenFunctionName(AstEventChannelApi api, Method method) {
  return 'pigeon_${_snakeCase(api.name)}_${_snakeCase(method.name)}_listen';
}

String _eventCancelFunctionName(AstEventChannelApi api, Method method) {
  return 'pigeon_${_snakeCase(api.name)}_${_snakeCase(method.name)}_cancel';
}

String _eventSinkName(AstEventChannelApi api, Method method) {
  return 'Pigeon${api.name}${_methodName(method)}EventSink';
}

String _eventSinkImplName(AstEventChannelApi api, Method method) {
  return '${_eventSinkName(api, method)}Impl';
}

String _eventStreamHandlerName(AstEventChannelApi api, Method method) {
  return 'Pigeon${api.name}${_methodName(method)}StreamHandler';
}

String _eventListenHelperName(AstEventChannelApi api, Method method) {
  return 'Pigeon${api.name}${_methodName(method)}ListenFfi';
}

String _eventCancelHelperName(AstEventChannelApi api, Method method) {
  return 'Pigeon${api.name}${_methodName(method)}CancelFfi';
}

String _eventListenDispatchHelperName(AstEventChannelApi api, Method method) {
  return '${_eventListenHelperName(api, method)}Dispatch';
}

String _eventCancelDispatchHelperName(AstEventChannelApi api, Method method) {
  return '${_eventCancelHelperName(api, method)}Dispatch';
}

String _eventHandlerVariable(AstEventChannelApi api, Method method) {
  return 'g_${_snakeCase(api.name)}_${_snakeCase(method.name)}_handler';
}

String _eventDispatcherVariable(AstEventChannelApi api, Method method) {
  return 'g_${_snakeCase(api.name)}_${_snakeCase(method.name)}_dispatcher';
}

String _eventSinkParameterType(HostDatatype type) {
  if (type.isNullable) {
    return 'const ${type.datatype}* event';
  }
  return 'const ${type.datatype}& event';
}

String _eventEncodableValueExpression(HostDatatype type, String value) {
  final String wrapperType = type.isBuiltin
      ? '::flutter::EncodableValue'
      : '::flutter::CustomEncodableValue';
  return '$wrapperType($value)';
}

String _snakeCase(String name) {
  return name.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (Match match) => '${match.start == 0 ? '' : '_'}${match[0]!.toLowerCase()}',
  );
}
