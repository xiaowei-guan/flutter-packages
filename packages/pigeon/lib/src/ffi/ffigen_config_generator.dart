// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:path/path.dart' as path;

import '../ast.dart';
import '../generator.dart';
import '../generator_tools.dart';
import '../pigeon_lib.dart';

/// Options that control how the ffigen config file will be generated.
///
/// For internal use only.
class InternalFfiGenConfigOptions extends InternalOptions {
  /// Creates an [InternalFfiGenConfigOptions].
  const InternalFfiGenConfigOptions({
    required this.configOut,
    required this.dartOut,
    required this.ffiHeaderPath,
    required this.bindingClassName,
    required this.description,
    this.copyrightHeader,
  });

  /// Path to the generated ffigen config file used to run ffigen.
  final String configOut;

  /// Path to the ffigen-generated Dart binding file.
  final String dartOut;

  /// Path to the generated C ABI header consumed by ffigen.
  final String ffiHeaderPath;

  /// Name of the ffigen-generated binding class.
  final String bindingClassName;

  /// Description for the ffigen-generated binding library.
  final String description;

  /// A copyright header that will get prepended to generated code.
  final Iterable<String>? copyrightHeader;
}

/// Generates a YAML config file for ffigen.
class FfiGenConfigGenerator extends Generator<InternalFfiGenConfigOptions> {
  /// Instantiates a ffigen config generator.
  const FfiGenConfigGenerator();

  @override
  void generate(
    InternalFfiGenConfigOptions generatorOptions,
    Root root,
    StringSink sink, {
    required String dartPackageName,
  }) {
    final indent = Indent();
    if (generatorOptions.copyrightHeader != null) {
      addLines(indent, generatorOptions.copyrightHeader!, linePrefix: '# ');
    }
    final dartOut = _pathRelativeToConfig(generatorOptions.configOut, generatorOptions.dartOut);
    final ffiHeaderPath = _pathRelativeToConfig(
      generatorOptions.configOut,
      generatorOptions.ffiHeaderPath,
    );
    indent.writeln('# ${getGeneratedCodeWarning()}');
    indent.writeln('# $seeAlsoWarning');
    indent.newln();
    indent.writeln('name: ${_yamlQuote(generatorOptions.bindingClassName)}');
    indent.writeln('description: ${_yamlQuote(generatorOptions.description)}');
    indent.writeln('output: ${_yamlQuote(dartOut)}');
    indent.writeln('headers:');
    indent.nest(1, () {
      indent.writeln('entry-points:');
      indent.nest(1, () {
        indent.writeln('- ${_yamlQuote(ffiHeaderPath)}');
      });
      indent.writeln('include-directives:');
      indent.nest(1, () {
        indent.writeln('- ${_yamlQuote('**/${_fileName(generatorOptions.ffiHeaderPath)}')}');
      });
    });
    indent.writeln('functions:');
    indent.nest(1, () {
      indent.writeln('include:');
      indent.nest(1, () {
        indent.writeln("- 'pigeon_.*'");
      });
    });
    indent.writeln('structs:');
    indent.nest(1, () {
      indent.writeln('include:');
      indent.nest(1, () {
        indent.writeln("- 'PigeonFfiBuffer'");
      });
    });
    sink.write(indent.toString());
  }
}

/// Validates ffigen config generation options.
List<Error> validateFfiGenConfig(InternalFfiGenConfigOptions options, Root root) {
  final errors = <Error>[];
  if (options.configOut == 'stdout') {
    errors.add(Error(message: 'ffigen config generation requires a file output path'));
  }
  if (options.dartOut.isEmpty) {
    errors.add(Error(message: 'ffigen config generation requires a Dart FFI output path'));
  }
  if (options.ffiHeaderPath.isEmpty) {
    errors.add(Error(message: 'ffigen config generation requires a C++ FFI header path'));
  }
  return errors;
}

String _normalizePath(String path) => path.replaceAll(r'\', '/');

String _pathRelativeToConfig(String configOut, String targetPath) {
  final normalizedTargetPath = _normalizePath(targetPath);
  if (_isAbsolutePath(normalizedTargetPath)) {
    return normalizedTargetPath;
  }

  final configDirectory = path.posix.dirname(_normalizePath(configOut));
  if (configDirectory == '.' || configDirectory.isEmpty) {
    return normalizedTargetPath;
  }
  return path.posix.relative(normalizedTargetPath, from: configDirectory);
}

bool _isAbsolutePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(path);
}

String _fileName(String path) => _normalizePath(path).split('/').last;

String _yamlQuote(String value) {
  return "'${value.replaceAll("'", "''")}'";
}
