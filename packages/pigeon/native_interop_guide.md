<?code-excerpt path-base="."?>
# Pigeon Native Interop (FFI & JNI) Guide

This guide describes Pigeon's Native Interop feature, which allows for direct, high-performance communication between Dart and native code using **FFI (Foreign Function Interface)** for Swift (iOS/macOS) and **JNI (Java Native Interface)** for Kotlin (Android).

---

## 1. Overview

Pigeon Native Interop allows Dart code to make direct function calls into native platform code, and vice versa, without the overhead of platform-channel-based message passing. Instead of serializing data into binary buffers, Native Interop establishes direct memory-bound bridges using native pointers and JVM references.
For a detailed comparison between platform-channel-based communication and Native Interop—including advantages, limitations, and recommended use cases—see the [Pigeon README](./README.md#communication-options-platform-channels-vs-native-interop).

### Threading & Isolates Model

Native Interop calls are direct in-process function calls across the C ABI (FFI) or JNI boundary rather than asynchronous messages queued through the Flutter engine:

* **Host APIs (Dart → Native)**:
  * **Execution Thread**: Host methods run directly on the OS thread of the calling Dart isolate. Calls from Flutter's root isolate run on the platform's main UI thread (unless the application developer has opted out of thread merging, which [is still possible on macOS](https://github.com/flutter/flutter/issues/181874)).
  * **Background Isolates**: Host APIs can be called directly from worker isolates (e.g., via `Isolate.run`) without requiring `BackgroundIsolateBinaryMessenger` or engine tokens. Callers must ensure the isolate stays alive while there are pending asynchronous calls, as attempting to execute a callback after the isolate has terminated will cause a crash.
  * **Synchronous Calls Block**: Synchronous methods block the calling isolate until native execution returns. Avoid long-running synchronous calls on the main UI isolate.
  * **Platform UI Affinity**: Native APIs that manipulate UI (such as UIKit views or Android `Activity`/views) must run on the platform's main thread. If invoked from a background isolate, native code must explicitly dispatch to the main thread (`DispatchQueue.main.async` in Swift, `Handler(Looper.getMainLooper()).post` in Kotlin) before interacting with UI APIs.
* **Flutter APIs (Native → Dart)**:
  * Synchronous callbacks into Dart are isolate-local and must be invoked from the isolate that registered them.
* **`@TaskQueue` Not Supported**:
  * Platform channels queue work onto engine background threads; Native Interop executes directly on the caller thread. Specifying `@TaskQueue` results in a code generation error.
  * To run host operations on background threads, annotate the method with `@async` in the Pigeon file and implement it using Swift `async` or Kotlin `suspend` functions (with `DispatchQueue.global` or `Dispatchers.IO`).

---

## 2. End-to-End Workflow

Using Native Interop in pigeon follows the standard pigeon workflow, with a few additional configuration and compilation steps. The complete end-to-end process is:

1. **Add Dependencies**: Add required interop packages to your `pubspec.yaml` (see [Step 1: Add Dependencies](#step-1-add-dependencies) below).
2. **Define the Interface**: Create a Dart definition file outlining your `HostApi` and `FlutterApi` declarations (refer to the [Pigeon README](./README.md#rules-for-defining-your-communication-interface) for syntax and rules).
3. **Configure Options**: Configure `kotlinOptions.useJni` or `swiftOptions.useFfi` in your `PigeonOptions` (see [Step 2: Configure Pigeon Options](#step-2-configure-pigeon-options) below).
4. **Prerequisites**: Ensure your local environment meets the toolchain prerequisites for `jnigen` and `ffigen` (see [Section 3: Prerequisites](#3-prerequisites) below).
5. **Run Code Generation**: Run the `pigeon` tool to generate the native bridge code and interop bindings (see [Step 3: Run Code Generation](#step-3-run-code-generation) below).
6. **Configure Build Systems**: For Swift FFI, configure CocoaPods or Swift Package Manager (SwiftPM) to compile the intermediate Objective-C bridge files (see [Step 4: iOS/macOS Build System Configuration (FFI)](#step-4-iosmacos-build-system-configuration-ffi) below).
7. **Implement and Call**: Implement the generated protocol/class interface in your native codebase and call the generated Dart methods from your Flutter application.

---

## 3. Prerequisites

To use Native Interop, your development environment and the corresponding external tools must be configured:

### Android (JNI / JNIgen)
- **Java 17**: Required specifically by the Android build tools and JNIgen.
- **Android SDK**: Must be installed and configured in your path.
- **Kotlin Version (`<= 2.1.0`)**: JNIgen uses `kotlinx-metadata-jvm` to parse Kotlin class metadata. It currently supports Kotlin metadata versions up to **2.1.0**. If the Android Gradle project uses a higher Kotlin plugin version (e.g. Kotlin 2.4.0), JNIgen will throw `IllegalArgumentException: Provided Metadata instance has version ... while maximum supported version is ...`. Ensure `settings.gradle.kts` sets Kotlin to `2.1.0`:
  ```kotlin
  id("org.jetbrains.kotlin.android") version "2.1.0" apply false
  ```

### iOS/macOS (FFI / FFIgen)
- **LLVM (version 9+) / Xcode Command Line Tools**: Required by FFIgen to parse C/Objective-C headers (`xcode-select --install`).

---

## 4. Implementation Steps

### Step 1: Add Dependencies

Add the required runtime dependencies to `dependencies` and code generators to `dev_dependencies`. Using `flutter pub add` ensures runtime packages resolve to the latest compatible versions:

```bash
# Add Pigeon:
flutter pub add dev:pigeon

# For iOS/macOS Swift FFI:
flutter pub add ffi
flutter pub add objective_c
# Pigeon requires this specific version for compatibility with its generated FFIgen configuration:
flutter pub add dev:ffigen@21.0.0

# For Android Kotlin JNI:
flutter pub add jni
# Pigeon requires this specific version for compatibility with its generated JNIgen configuration:
flutter pub add dev:jnigen@1.0.0
```

### Step 2: Configure Pigeon Options

Enable Native Interop for your target platforms by setting the configuration options in your Pigeon file:

<?code-excerpt "example/native_interop_app/pigeons/native_interop_example.dart (config)"?>
```dart
@ConfigurePigeon(
  PigeonOptions(
    // (Recommended) Path to the compiled application directory (where pubspec.yaml resides)
    appDirectory: './',
    dartOptions: DartOptions(),
    kotlinOptions: KotlinOptions(
      useJni: true,
      // Optional: Paths to search for compiled local classes (primarily needed for standalone apps)
      jniClassPaths: <String>['build/app/tmp/kotlin-classes/release'],
    ),
    swiftOptions: SwiftOptions(useFfi: true, ffiModuleName: 'Runner'),
  ),
)
```

#### General Options
* **`appDirectory`**: The path to the compiled Flutter **application** directory (e.g., `example/` when developing a plugin, or `./` for a standalone application). FFIgen and JNIgen require a compiled application context to locate class files and build outputs. If omitted when running Pigeon from an app root, it defaults to `./`.
  - *CLI Equivalent*: `--app_directory <path>`.

#### Kotlin Options for JNI
* **`useJni`**: Set to `true` to enable Kotlin JNI code generation and automated JNIgen orchestration.
* **`jniClassPaths`**: (Optional) A list of paths to directories or `.jar` files containing compiled Kotlin/Java classes. This is primarily required for standalone Flutter Applications, as their own local compiled classes are not automatically resolved by JNIgen's default dependency scanner. If omitted, it defaults to the standard Flutter release build output directory (`build/app/tmp/kotlin-classes/release`).
  - *Note*: If you are building a Flutter Plugin, this option is generally not needed because JNIgen automatically resolves classes defined inside plugin packages via standard Gradle dependency classpaths.
  - *CLI Equivalent*: `--kotlin_jni_classpaths <path>` (can be specified multiple times).
* **`appDirectory`**: (Optional) Overrides the target application directory specifically for Kotlin and JNIgen.
  - *CLI Equivalent*: `--kotlin_app_directory <path>`.

#### Swift Options for FFI
* **`useFfi`**: Set to `true` to enable Swift FFI code generation and automated FFIgen orchestration.
* **`ffiModuleName`**: The module name that generated Swift FFI classes and Objective-C bridge files will use.
  - *CLI Equivalent*: `--swift_use_ffi`, `--swift_ffi_module_name <name>`.
* **`appDirectory`**: (Optional) Overrides the target application directory specifically for Swift and FFIgen.
  - *CLI Equivalent*: `--swift_app_directory <path>`.

### Step 3: Run Code Generation

Run the `pigeon` tool to generate the native bridge code and interop bindings:

```bash
dart run pigeon --input <path/to/pigeon_file.dart>
```

#### How Automated Interop Generation Works

When Native Interop options (`useJni` or `useFfi`) are enabled, Pigeon automatically orchestrates running `jnigen` and `ffigen` as part of the generation process:

- **Android (JNI)**: When `kotlinOptions.useJni` is enabled:
  1. Generates the JNI-compatible Kotlin bridge and the `jnigen_config.dart` script in `tool/pigeon/`.
  2. Runs `jnigen` via the config script to parse the Kotlin bridge and produce Dart JNI bindings.
  3. Generates the final pigeon Dart output that wraps and imports those JNI bindings.
- **iOS/macOS (FFI)**: When `swiftOptions.useFfi` is enabled:
  1. Generates the Objective-C compatible Swift bridge and the `ffigen_config.dart` script in `tool/pigeon/`.
  2. Runs `ffigen` via the config script to parse the Objective-C bridge and produce Dart FFI bindings.
  3. Generates the final pigeon Dart output that wraps and imports those FFI bindings.

### Step 4: iOS/macOS Build System Configuration (FFI)

Because Dart FFI cannot directly call Swift symbols, the FFI toolchain generates intermediate Objective-C bridging files in a subdirectory named `<swift_output_dir>_objc_gen`:
- **`.h` (Headers)**: Always generated to declare module interfaces and types.
- **`.m` (Bridging Implementation)**: Generated when the schema contains callbacks, closures, Flutter APIs, or Objective-C blocks requiring trampoline implementations.
- **`.o` (Temporary Object Files)**: Intermediate binary files generated during `ffigen`/`swiftgen` AST extraction. These are **not** needed after code generation and must **not** be committed to version control.

To compile the generated Objective-C files alongside your Swift code, you must configure your iOS/macOS build systems:

#### CocoaPods Configuration
Ensure your `.podspec` file matches Swift, Objective-C implementations (`.m`), and headers (`.h`):
```ruby
s.source_files = 'Sources/**/*.{swift,m,h}'
```
This allows CocoaPods to automatically compile the generated Objective-C bridging files into the framework.

#### Swift Package Manager (SwiftPM) Configuration
Because Swift and Objective-C files cannot reside within the same SwiftPM target, you must define two separate targets in your `Package.swift` file:
1. An Objective-C target for the generated bridge files (e.g., `my_plugin_objc_gen`).
2. The main Swift target that depends on the Objective-C target.

Example configuration:
<?code-excerpt "platform_tests/test_plugin/darwin/test_plugin/Package.swift (swiftpm-targets)"?>
```swift
targets: [
  .target(
    name: "test_plugin_objc_gen",
    dependencies: [],
    publicHeadersPath: "."
  ),
  .target(
    name: "test_plugin",
    dependencies: ["test_plugin_objc_gen"]
  ),
]
```

#### Standalone Applications & Example Apps

When implementing Native Interop host APIs directly in an application target rather than a plugin package:

* **Swift Module Name Configuration (`ffiModuleName`)**:
  Swift namespaces `@objc` classes with the module name (`<module>.<class>`). Set `ffiModuleName` in `SwiftOptions` to match your application's Swift module name (which defaults to `'Runner'`).

  If iOS and macOS share the same generated Dart FFI file, both platforms must compile under that same module name. Because Flutter's macOS template defaults to using the app name instead of `Runner`, you can unify them by setting `PRODUCT_MODULE_NAME` in `macos/Runner/Configs/AppInfo.xcconfig` to match `ffiModuleName`:
  ```xcconfig
  PRODUCT_MODULE_NAME = Runner // or your custom ffiModuleName
  ```
  *(Note: If iOS and macOS use separate Pigeon generation outputs or you only target one platform, unifying module names between platforms is not required.)*

* **Native Registration in macOS (`MainFlutterWindow.swift`)**:
  While iOS registers the host implementation in `AppDelegate.swift` within `didInitializeImplicitFlutterEngine`, macOS applications should register it in `MainFlutterWindow.swift` within `awakeFromNib()`:
  ```swift
  RegisterGeneratedPlugins(registry: flutterViewController)

  let api = PigeonApiImplementation()
  MyApiSetup.register(api: api)
  ```
  Calling `register(api:)` in native code also prevents the Xcode linker (`-dead_strip`) from stripping the setup class from the compiled binary.

---

## 5. Troubleshooting Automated Generation

If `dart run pigeon` encounters errors while running `jnigen` or `ffigen`, review the following troubleshooting steps:

### 5.1 Unupdated Native Implementation or Uncompiled Code (JNI)

JNIgen parses compiled bytecode (`.class` files). If you changed your Pigeon schema and haven't yet updated or compiled your native Kotlin/Java code, JNIgen will fail.

- **Solution**: Build/compile your native code first so that the compiled class files are up-to-date:
  ```bash
  cd android && ./gradlew compileReleaseKotlin
  ```
  Then re-run `dart run pigeon --input <path/to/pigeon_file.dart>`.

### 5.2 Missing Class Files or Non-Standard Build Directory (JNI)

For standalone Flutter Applications, JNIgen defaults to searching `build/app/tmp/kotlin-classes/release`. If your build output directory is different or the project has not been built, JNIgen will fail to find class definitions.

- **Solution**: Ensure the project has been built at least once, or specify custom class paths via `jniClassPaths`:
  ```dart
  kotlinOptions: KotlinOptions(
    useJni: true,
    jniClassPaths: <String>['build/app/tmp/kotlin-classes/debug'],
  )
  ```

### 5.3 Manual Configuration Script Execution

Pigeon writes the interop configuration scripts to `tool/pigeon/jnigen_config.dart` and `tool/pigeon/ffigen_config.dart`.

- **Solution**: Run the generated config scripts directly to view verbose stderr logs and diagnose toolchain errors:
  ```bash
  # Debug JNIgen (Android):
  dart run tool/pigeon/jnigen_config.dart

  # Debug FFIgen (iOS/macOS):
  dart run tool/pigeon/ffigen_config.dart
  ```

### 5.4 Failed to Load Objective-C Class (`<ffiModuleName>.<Api>Setup`)

If your app crashes at startup with `FailedToLoadClassException: Failed to load Objective-C class`:
- **Module Name Mismatch**: Ensure `ffiModuleName` matches your app's Swift module name. If iOS and macOS share the same generated Dart FFI file, ensure both platforms use the same module name (e.g., align macOS by setting `PRODUCT_MODULE_NAME` in `macos/Runner/Configs/AppInfo.xcconfig`).
- **Linker Dead-Code Stripping**: Ensure your native host code instantiates and registers the implementation (e.g. `MyApiSetup.register(api: api)` in `MainFlutterWindow.swift` on macOS or `AppDelegate.swift` on iOS) so the linker does not strip the class.

---

## 6. Migration from Platform Channels

If you are migrating an existing Pigeon plugin from the platform-channel-based model to the Native Interop model, see the [Native Interop Migration Guide](./native_interop_migration_guide.md) for a complete comparison of the API models and transition examples.
# Native Interop Guide

This guide describes the experimental C++ FFI generation path for Pigeon.

## C++ FFI

C++ FFI lets Dart call generated C ABI functions directly through `dart:ffi`
instead of sending calls through `BasicMessageChannel`. The public Dart API is
still the normal Pigeon HostApi class generated in `messages.g.dart`; callers do
not need to call native pointers directly.

The generated call path is:

```text
Dart caller
  -> messages.g.dart
  -> messages.g.ffi.dart
  -> messages_ffi.cc
  -> optional PigeonFfiSyncDispatcher
  -> hand-written C++ HostApi implementation
```

## Requirements

Add `ffi` as a dependency and `ffigen` as a dev dependency in the package that
runs Pigeon:

```sh
dart pub add ffi
dart pub add dev:ffigen
```

The package should then have entries similar to:

```yaml
dependencies:
  ffi: ...

dev_dependencies:
  ffigen: ...
```

The generated C++ sources must also be compiled into the native library that
Dart opens with FFI.

## Pigeon Configuration

Configure both the regular C++ generator and the C++ FFI generator. The regular
C++ files provide the typed HostApi interface and codec helpers; the FFI files
provide exported C ABI functions that ffigen can read.
`cppFfiHeaderOut` and `cppFfiSourceOut` must be configured together.

```dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartFfiOut: 'lib/src/messages.g.ffi.dart',
    configDirectory: 'tool/pigeon',
    dartOptions: DartOptions(
      ffiOptions: DartFfiOptions(
        bindingClassName: 'MessagesFfiBindings',
        nativeLibraryExpression: 'ffi.DynamicLibrary.process()',
      ),
    ),
    cppHeaderOut: 'tizen/messages.h',
    cppSourceOut: 'tizen/messages.cc',
    cppOptions: CppOptions(namespace: 'my_plugin'),
    cppFfiHeaderOut: 'tizen/messages_ffi.h',
    cppFfiSourceOut: 'tizen/messages_ffi.cc',
    dartPackageName: 'my_plugin',
  ),
)
@HostApi()
abstract class VideoPlayerApi {
  int create(String uri);

  void dispose(int playerId);
}
```

If the generated FFI header cannot include the generated C++ API header by file
name alone, set `cppFfiOptions.apiHeaderIncludePath` explicitly:

```dart
cppFfiOptions: CppFfiOptions(
  apiHeaderIncludePath: 'path/visible/to/messages.h',
),
```

The C++ FFI adapter uses `cppOptions.namespace` by default so that
`SetUpMyApiFfi` and the generated C++ API classes live in the same namespace.
Set `cppFfiOptions.namespace` only if the FFI adapter must use a different
namespace from the regular generated C++ API.

If the target C++ toolchain cannot compile `std::visit` with
`flutter::EncodableValue`, disable it for the regular C++ generator:

```dart
cppOptions: CppOptions(
  namespace: 'my_plugin',
  useStdVisit: false,
),
```

Run Pigeon from the package root:

```sh
dart run pigeon --input pigeons/messages.dart
```

When `dartFfiOut`, `cppFfiHeaderOut`, and `cppFfiSourceOut` are set, Pigeon
will generate the ffigen config file and then run ffigen automatically. By
default, the config file is written under `tool/pigeon`. You can change that
directory with `configDirectory` or `--config_dir`.
For example, `pigeons/messages.dart` produces
`tool/pigeon/messages_ffigen_config.yaml`.
Paths inside that config are written relative to the config file, so the Dart
FFI output may appear as `../../lib/src/messages.g.ffi.dart`.
Running from the package root lets `dart run ffigen` resolve the package's
`pubspec.yaml` and dev dependencies.

Set `dartFfiConfigOut` or `--dart_ffi_config_out` only when you need to override
the exact ffigen config file path.

The same paths can also be passed on the command line:

```sh
dart run pigeon \
  --input pigeons/messages.dart \
  --dart_out lib/src/messages.g.dart \
  --dart_ffi_out lib/src/messages.g.ffi.dart \
  --config_dir tool/pigeon \
  --dart_ffi_binding_class MessagesFfiBindings \
  --dart_ffi_native_library 'ffi.DynamicLibrary.process()' \
  --cpp_header_out tizen/messages.h \
  --cpp_source_out tizen/messages.cc \
  --cpp_namespace my_plugin \
  --cpp_ffi_header_out tizen/messages_ffi.h \
  --cpp_ffi_source_out tizen/messages_ffi.cc
```

## Generated Files

With the configuration above, Pigeon generates:

* `lib/src/messages.g.dart`: the high-level Dart HostApi wrapper.
* `lib/src/messages.g.ffi.dart`: the low-level Dart FFI binding generated by
  ffigen.
* `tizen/messages.h` and `tizen/messages.cc`: the regular generated C++ API and
  codec support.
* `tizen/messages_ffi.h` and `tizen/messages_ffi.cc`: the generated C ABI
  adapter used by FFI.
* `tool/pigeon/messages_ffigen_config.yaml`: the ffigen configuration that
  Pigeon uses for the automatic ffigen step.

## Native Setup

Implement the generated C++ HostApi class as usual, then register that
implementation with the generated FFI setup function:

```cpp
#include "messages.h"
#include "messages_ffi.h"

namespace my_plugin {

class VideoPlayerApiImpl : public VideoPlayerApi {
 public:
  ErrorOr<int64_t> Create(const std::string& uri) override {
    return 1;
  }

  std::optional<FlutterError> Dispose(int64_t player_id) override {
    return std::nullopt;
  }
};

void RegisterVideoPlayerApiFfi(VideoPlayerApiImpl* api) {
  SetUpVideoPlayerApiFfi(api);
}

}  // namespace my_plugin
```

If a HostApi method touches platform-thread-only APIs, such as a
`BinaryMessenger`, event channel, texture registrar, or platform media APIs,
pass a dispatcher when setting up the FFI API:

```cpp
namespace my_plugin {

class PlatformThreadDispatcher : public PigeonFfiSyncDispatcher {
 public:
  ::PigeonFfiBuffer* RunSync(
      std::function<::PigeonFfiBuffer*()> task) override {
    // If already on the platform thread, run task immediately. Otherwise post
    // it to the platform thread and block until it returns.
    return task();
  }
};

void RegisterVideoPlayerApiFfi(
    VideoPlayerApiImpl* api,
    PlatformThreadDispatcher* dispatcher) {
  SetUpVideoPlayerApiFfi(api, dispatcher);
}

}  // namespace my_plugin
```

`RunSync` must complete synchronously before returning to Dart. Implementations
should avoid deadlocks by running the task inline when already on the platform
thread. The `api` and `dispatcher` pointers passed to `SetUpVideoPlayerApiFfi`
must remain valid for as long as Dart can make FFI calls.

Make sure both `messages.cc` and `messages_ffi.cc` are included in the native
build.

## Limitations

The C++ FFI generator currently supports synchronous HostApi methods only.
Asynchronous HostApi methods, FlutterApi, EventChannelApi, and ProxyApi are not
supported by this C++ FFI path.
