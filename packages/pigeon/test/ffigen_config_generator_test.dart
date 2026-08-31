// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:pigeon/src/ast.dart';
import 'package:pigeon/src/ffi/ffigen_config_generator.dart';
import 'package:test/test.dart';

const String _packageName = 'test_package';

void main() {
  test('generates ffigen config for C++ FFI header', () {
    final root = Root(apis: <Api>[], classes: <Class>[], enums: <Enum>[]);
    final sink = StringBuffer();
    const generator = FfiGenConfigGenerator();

    generator.generate(
      const InternalFfiGenConfigOptions(
        configOut: 'ffigen.yaml',
        dartOut: 'lib/messages.g.ffi.dart',
        ffiHeaderPath: 'windows/messages_ffi.h',
        bindingClassName: 'MessagesFfiBindings',
        description: 'Generated bindings for test.',
      ),
      root,
      sink,
      dartPackageName: _packageName,
    );

    final code = sink.toString();
    expect(code, contains("name: 'MessagesFfiBindings'"));
    expect(code, contains("description: 'Generated bindings for test.'"));
    expect(code, contains("output: 'lib/messages.g.ffi.dart'"));
    expect(code, contains('headers:'));
    expect(code, contains('entry-points:'));
    expect(code, contains("  - 'windows/messages_ffi.h'"));
    expect(code, contains('include-directives:'));
    expect(code, contains("  - '**/messages_ffi.h'"));
    expect(code, contains('functions:'));
    expect(code, contains("  - 'pigeon_.*'"));
    expect(code, contains('structs:'));
    expect(code, contains("  - 'PigeonFfiBuffer'"));
  });

  test('generates ffigen config paths relative to config file', () {
    final root = Root(apis: <Api>[], classes: <Class>[], enums: <Enum>[]);
    final sink = StringBuffer();
    const generator = FfiGenConfigGenerator();

    generator.generate(
      const InternalFfiGenConfigOptions(
        configOut: 'tool/pigeon/messages_ffigen_config.yaml',
        dartOut: 'lib/src/messages.g.ffi.dart',
        ffiHeaderPath: 'tizen/src/messages_ffi.h',
        bindingClassName: 'MessagesFfiBindings',
        description: 'Generated bindings for test.',
      ),
      root,
      sink,
      dartPackageName: _packageName,
    );

    final code = sink.toString();
    expect(code, contains("output: '../../lib/src/messages.g.ffi.dart'"));
    expect(code, contains("  - '../../tizen/src/messages_ffi.h'"));
  });

  test('validates required paths', () {
    final root = Root(apis: <Api>[], classes: <Class>[], enums: <Enum>[]);

    final errors = validateFfiGenConfig(
      const InternalFfiGenConfigOptions(
        configOut: 'stdout',
        dartOut: '',
        ffiHeaderPath: '',
        bindingClassName: 'MessagesFfiBindings',
        description: 'Generated bindings for test.',
      ),
      root,
    );

    expect(
      errors.map((error) => error.message),
      contains('ffigen config generation requires a file output path'),
    );
    expect(
      errors.map((error) => error.message),
      contains('ffigen config generation requires a Dart FFI output path'),
    );
    expect(
      errors.map((error) => error.message),
      contains('ffigen config generation requires a C++ FFI header path'),
    );
  });
}
