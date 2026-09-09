// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:pigeon/src/ast.dart';
import 'package:pigeon/src/cpp/cpp_ffi_generator.dart';
import 'package:pigeon/src/generator_tools.dart';
import 'package:pigeon/src/pigeon_lib.dart' show Error;
import 'package:test/test.dart';

const String _packageName = 'test_package';

void main() {
  test('generates C ABI header for sync HostApi', () {
    final root = Root(
      apis: <Api>[
        AstHostApi(
          name: 'CalculatorApi',
          methods: <Method>[
            Method(
              name: 'add',
              parameters: <Parameter>[
                Parameter(
                  type: const TypeDeclaration(baseName: 'int', isNullable: false),
                  name: 'x',
                ),
                Parameter(
                  type: const TypeDeclaration(baseName: 'int', isNullable: false),
                  name: 'y',
                ),
              ],
              location: ApiLocation.host,
              returnType: const TypeDeclaration(baseName: 'int', isNullable: false),
            ),
          ],
        ),
      ],
      classes: <Class>[],
      enums: <Enum>[],
    );

    final sink = StringBuffer();
    const CppFfiGenerator().generate(
      OutputFileOptions<InternalCppFfiOptions>(
        fileType: FileType.header,
        languageOptions: InternalCppFfiOptions(
          headerIncludePath: 'messages_ffi.h',
          apiHeaderIncludePath: 'messages.h',
          cppFfiHeaderOut: 'messages_ffi.h',
          cppFfiSourceOut: 'messages_ffi.cc',
          namespace: 'test',
        ),
      ),
      root,
      sink,
      dartPackageName: _packageName,
    );

    final code = sink.toString();
    expect(code, contains('typedef struct PigeonFfiBuffer'));
    expect(code, contains('extern "C"'));
    expect(
      code,
      contains(
        'PIGEON_FFI_EXPORT PigeonFfiBuffer* pigeon_calculator_api_add(PigeonFfiBuffer* request);',
      ),
    );
    expect(code, contains('#include "messages.h"'));
    expect(code, contains('#include <functional>'));
    expect(code, contains('namespace test {'));
    expect(code, contains('class PigeonFfiSyncDispatcher'));
    expect(code, contains('virtual ::PigeonFfiBuffer* RunSync'));
    expect(code, contains('void SetUpCalculatorApiFfi('));
    expect(code, contains('CalculatorApi* api,'));
    expect(code, contains('PigeonFfiSyncDispatcher* dispatcher = nullptr);'));
  });

  test('generates C++ source dispatch for sync HostApi', () {
    final root = Root(
      apis: <Api>[
        AstHostApi(
          name: 'CalculatorApi',
          methods: <Method>[
            Method(
              name: 'add',
              parameters: <Parameter>[
                Parameter(
                  type: const TypeDeclaration(baseName: 'int', isNullable: false),
                  name: 'x',
                ),
                Parameter(
                  type: const TypeDeclaration(baseName: 'int', isNullable: false),
                  name: 'y',
                ),
              ],
              location: ApiLocation.host,
              returnType: const TypeDeclaration(baseName: 'int', isNullable: false),
            ),
          ],
        ),
      ],
      classes: <Class>[],
      enums: <Enum>[],
    );

    final sink = StringBuffer();
    const CppFfiGenerator().generate(
      OutputFileOptions<InternalCppFfiOptions>(
        fileType: FileType.source,
        languageOptions: InternalCppFfiOptions(
          headerIncludePath: 'messages_ffi.h',
          apiHeaderIncludePath: 'messages.h',
          cppFfiHeaderOut: 'messages_ffi.h',
          cppFfiSourceOut: 'messages_ffi.cc',
          namespace: 'test',
        ),
      ),
      root,
      sink,
      dartPackageName: _packageName,
    );

    final code = sink.toString();
    expect(code, contains('#include "messages_ffi.h"'));
    expect(code, contains('namespace test {'));
    expect(code, contains('CalculatorApi* g_calculator_api_api = nullptr;'));
    expect(code, contains('PigeonFfiSyncDispatcher* g_calculator_api_dispatcher = nullptr;'));
    expect(code, contains('void SetUpCalculatorApiFfi('));
    expect(code, contains('PigeonFfiSyncDispatcher* dispatcher)'));
    expect(code, contains('g_calculator_api_dispatcher = dispatcher;'));
    expect(
      code,
      contains('std::unique_ptr<::flutter::EncodableValue> message = codec.DecodeMessage'),
    );
    expect(code, contains('const int64_t x_arg = encodable_x_arg.LongValue();'));
    expect(code, contains('ErrorOr<int64_t> output = g_calculator_api_api->Add(x_arg, y_arg);'));
    expect(code, contains('::flutter::EncodableValue(output.value())'));
    expect(code, contains('return PigeonFfiEncodeMessage'));
    expect(code, contains('PigeonCalculatorApiAddFfiDispatch(PigeonFfiBuffer* request)'));
    expect(code, contains('if (g_calculator_api_dispatcher != nullptr)'));
    expect(code, contains('return g_calculator_api_dispatcher->RunSync([request]() {'));
    expect(code, contains('return PigeonCalculatorApiAddFfi(request);'));
    expect(code, isNot(contains('TakeValue()')));
    expect(code, contains('}  // namespace test'));
    expect(
      code,
      contains('extern "C" PigeonFfiBuffer* pigeon_calculator_api_add(PigeonFfiBuffer* request)'),
    );
    expect(code, contains('return test::PigeonCalculatorApiAddFfiDispatch(request);'));
    expect(code, isNot(contains('TODO')));
  });

  test('generates C ABI adapter for EventChannelApi', () {
    final root = Root(
      apis: <Api>[
        AstEventChannelApi(
          name: 'EventApi',
          methods: <Method>[
            Method(
              name: 'streamEvents',
              parameters: <Parameter>[],
              location: ApiLocation.host,
              returnType: const TypeDeclaration(baseName: 'int', isNullable: false),
            ),
          ],
        ),
      ],
      classes: <Class>[],
      enums: <Enum>[],
      containsEventChannel: true,
    );

    final headerSink = StringBuffer();
    const CppFfiGenerator().generate(
      OutputFileOptions<InternalCppFfiOptions>(
        fileType: FileType.header,
        languageOptions: InternalCppFfiOptions(
          headerIncludePath: 'messages_ffi.h',
          apiHeaderIncludePath: 'messages.h',
          cppFfiHeaderOut: 'messages_ffi.h',
          cppFfiSourceOut: 'messages_ffi.cc',
          namespace: 'test',
        ),
      ),
      root,
      headerSink,
      dartPackageName: _packageName,
    );

    final headerCode = headerSink.toString();
    expect(headerCode, contains('typedef void (*PigeonFfiEventCallback)'));
    expect(headerCode, contains('pigeon_event_api_stream_events_listen'));
    expect(headerCode, contains('pigeon_event_api_stream_events_cancel'));
    expect(headerCode, contains('class PigeonEventApiStreamEventsEventSink'));
    expect(headerCode, contains('class PigeonEventApiStreamEventsStreamHandler'));
    expect(headerCode, contains('void SetUpEventApiStreamEventsFfi('));
    expect(headerCode, contains('PigeonFfiSyncDispatcher* dispatcher = nullptr);'));

    final sourceSink = StringBuffer();
    const CppFfiGenerator().generate(
      OutputFileOptions<InternalCppFfiOptions>(
        fileType: FileType.source,
        languageOptions: InternalCppFfiOptions(
          headerIncludePath: 'messages_ffi.h',
          apiHeaderIncludePath: 'messages.h',
          cppFfiHeaderOut: 'messages_ffi.h',
          cppFfiSourceOut: 'messages_ffi.cc',
          namespace: 'test',
        ),
      ),
      root,
      sourceSink,
      dartPackageName: _packageName,
    );

    final sourceCode = sourceSink.toString();
    expect(sourceCode, contains('const ::flutter::StandardMessageCodec& PigeonFfiGetCodec()'));
    expect(
      sourceCode,
      contains(
        'PigeonEventApiStreamEventsStreamHandler* g_event_api_stream_events_handler = nullptr;',
      ),
    );
    expect(
      sourceCode,
      contains('PigeonFfiSyncDispatcher* g_event_api_stream_events_dispatcher = nullptr;'),
    );
    expect(sourceCode, contains('class PigeonEventApiStreamEventsEventSinkImpl'));
    expect(sourceCode, contains('handler->OnListen(instance_name, std::move(sink));'));
    expect(sourceCode, contains('handler->OnCancel(instance_name);'));
    expect(sourceCode, contains('return g_event_api_stream_events_dispatcher->RunSync([=]() {'));
    expect(sourceCode, contains('return test::PigeonEventApiStreamEventsListenFfiDispatch'));
    expect(sourceCode, contains('return test::PigeonEventApiStreamEventsCancelFfiDispatch'));
  });

  test('validates unsupported api shapes', () {
    final root = Root(
      apis: <Api>[
        AstHostApi(
          name: 'AsyncApi',
          methods: <Method>[
            Method(
              name: 'doIt',
              parameters: <Parameter>[],
              location: ApiLocation.host,
              returnType: const TypeDeclaration(baseName: 'void', isNullable: false),
              isAsynchronous: true,
            ),
          ],
        ),
        AstFlutterApi(name: 'CallbackApi', methods: <Method>[]),
        AstEventChannelApi(
          name: 'EventApi',
          methods: <Method>[
            Method(
              name: 'streamEvents',
              parameters: <Parameter>[],
              location: ApiLocation.host,
              returnType: const TypeDeclaration(baseName: 'void', isNullable: false),
            ),
          ],
        ),
      ],
      classes: <Class>[],
      enums: <Enum>[],
      containsEventChannel: true,
    );

    final errors = validateCppFfi(
      const InternalCppFfiOptions(
        headerIncludePath: 'messages_ffi.h',
        apiHeaderIncludePath: 'messages.h',
        cppFfiHeaderOut: 'messages_ffi.h',
        cppFfiSourceOut: 'messages_ffi.cc',
      ),
      root,
    );

    expect(
      errors.map((Error error) => error.message),
      containsAll(<String>[
        'C++ FFI does not support async HostApi method "doIt"',
        'C++ FFI does not support FlutterApi "CallbackApi"',
        'C++ FFI does not support void EventChannelApi method "streamEvents"',
      ]),
    );
  });
}
