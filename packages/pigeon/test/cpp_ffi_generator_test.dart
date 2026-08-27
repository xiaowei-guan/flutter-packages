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
    expect(code, contains('namespace test {'));
    expect(code, contains('void SetUpCalculatorApiFfi(CalculatorApi* api);'));
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
    expect(code, contains('CalculatorApi* g_calculator_api_api = nullptr;'));
    expect(code, contains('void SetUpCalculatorApiFfi(CalculatorApi* api)'));
    expect(
      code,
      contains('std::unique_ptr<::flutter::EncodableValue> message = codec.DecodeMessage'),
    );
    expect(code, contains('const int64_t x_arg = encodable_x_arg.LongValue();'));
    expect(code, contains('ErrorOr<int64_t> output = g_calculator_api_api->Add(x_arg, y_arg);'));
    expect(code, contains('return PigeonFfiEncodeMessage'));
    expect(
      code,
      contains('extern "C" PigeonFfiBuffer* pigeon_calculator_api_add(PigeonFfiBuffer* request)'),
    );
    expect(code, isNot(contains('TODO')));
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
      ],
      classes: <Class>[],
      enums: <Enum>[],
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
      ]),
    );
  });
}
