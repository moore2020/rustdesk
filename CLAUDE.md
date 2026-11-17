# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository instructions

- Read `AGENTS.md` before changing code. It contains the detailed Rust, Tokio, Flutter Rust Bridge, testing, localization, and regression-surface rules for this repository.
- Keep `AGENTS.md` authoritative when this file and it differ. In particular, do not run `flutter_rust_bridge_codegen` locally; generated native bridge files are ignored and normally produced by CI.
- The repository is a cross-platform remote-desktop application. Changes often have platform-specific compile gates, native dependencies, and Flutter/Rust FFI implications; check the relevant target-specific code and workflow before changing shared code.

## Build prerequisites and setup

- Initialize the shared server/client submodule before building:

  ```sh
  git submodule update --init --recursive
  ```

- The Rust package requires Rust `1.75` as its baseline (`Cargo.toml`). Flutter desktop CI uses the pinned versions in `.github/workflows/flutter-build.yml`; do not casually upgrade Flutter or Rust because the native bridge, Sciter ABI, and platform builds have version-specific constraints.
- Native builds need a C/C++ toolchain and vcpkg. Set `VCPKG_ROOT` and install the manifest dependencies from the repository root:

  ```sh
  export VCPKG_ROOT="$HOME/vcpkg"
  "$VCPKG_ROOT/vcpkg" install --x-install-root="$VCPKG_ROOT/installed"
  ```

  Linux system packages are listed in `README.md` and `.github/workflows/ci.yml`. Platform packaging may require additional SDKs, signing tools, CocoaPods, Android tooling, or Visual Studio tooling.
- Run build and packaging commands from the repository root. `build.py` changes directory internally and assumes that starting location.

## Common commands

### Rust development

```sh
# Compile the default desktop/legacy-UI configuration.
cargo build --locked

# Run the legacy Sciter desktop application from the repository root.
# A platform-appropriate Sciter shared library must be available as described in README.md.
cargo run

# Build the Rust library used by Flutter.
cargo build --locked --lib --features flutter

# Run the normal Linux workspace test suite (the main CI configuration).
cargo test --locked --workspace

# Run root-package library tests, optionally with the feature set under development.
cargo test --locked --lib
cargo test --locked --lib --features flutter

# Run one test by name or one workspace crate's tests.
cargo test --locked --lib test_name
cargo test --locked -p clipboard test_name

# Formatting and local static checks.
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked
```

The repository's CI does not use one universal feature set: Windows/macOS Flutter jobs test the release feature set, Linux has separate DRM and clipboard commands, and some platform-gated workspace tests only run when their crate is named explicitly. Match the relevant workflow command when testing a platform-specific change. A feature-specific test filter that matches no tests can still exit successfully; use an explicit test count check when reproducing the DRM workflow behavior.

### Flutter development

From `flutter/`:

```sh
flutter pub get
flutter analyze
flutter test --timeout 60s

# Run one file or one named test.
flutter test test/id_formatter_test.dart
flutter test test/id_formatter_test.dart -n "test name"

# Apply Dart formatting; use --set-exit-if-changed for a check.
dart format lib test
dart format --output=none --set-exit-if-changed lib test
```

The current desktop UI can be launched with `flutter run` after the Rust Flutter library and the bridge artifacts for the target are available. `flutter/run.sh` is a legacy convenience script that invokes bridge code generation; do not use it as a reason to regenerate the bridge locally. For normal builds use `build.py` and the same pinned toolchain/bridge artifacts as CI.

### Cross-platform builds and packaging

`build.py` is the main packaging entry point. Common flags include `--flutter`, `--hwcodec`, `--vram`, `--portable`, `--unix-file-copy-paste`, `--drm`, `--screencapturekit`, `--skip-cargo`, and `--print-features`.

```sh
# Build the current host's Flutter package with hardware codec support.
./build.py --flutter --hwcodec

# Print the exact Cargo feature list selected by a build invocation.
./build.py --flutter --hwcodec --print-features

# Package already-built artifacts without rebuilding Cargo (packaging/CI use only).
./build.py --flutter --skip-cargo
```

`--drm` is Linux-only and intentionally restricted by `build.py` to the Debian packaging path. It builds the unattended Wayland variant, bundles a pinned `libdrmtap`, and requires the DRM-specific test/build flow in `.github/workflows/flutter-build.yml`; do not treat it as an ordinary local feature toggle.

The build script selects the package format from the host (`deb`, `rpm`, Arch, macOS DMG, or Windows artifacts). CI is the source of truth for platform-specific build arguments, pinned Flutter versions, cross-compilation, signing, and release packaging.

### Python helper tests

The update-metadata helpers have standalone Python tests used by CI:

```sh
python3 -m unittest \
  res/update/test_generate_update_metadata.py \
  res/update/test_update_metadata_cli.py \
  res/update/test_macos_update_scripts.py
```

## High-level architecture

### Native Rust core

- The root Cargo package builds `librustdesk` as `cdylib`, `staticlib`, and `rlib`, plus the `naming` and `service` binaries. `src/main.rs` is the desktop entry point; `src/core_main.rs` performs common startup, command-line handling, service/tray startup, and decides whether to launch a UI or exit.
- `src/client.rs` is the outgoing remote-desktop client and session manager. It coordinates authentication, direct/relay/WebRTC transport selection, video/audio, clipboard, input, file transfer, terminal, and port-forwarding behavior. `src/rendezvous_mediator.rs` communicates with the rendezvous/relay server and coordinates connection establishment.
- `src/server/` is the incoming host side: connection/authentication handling, authorization limits, display capture, video, audio, input, clipboard, terminal, printer, and port-forward services. `src/ipc.rs` and `src/hbbs_http/` provide local IPC and HTTP/account/update integrations.
- `src/platform/` and the platform-specific modules under `src/privacy_mode/`, `src/whiteboard/`, and `src/server/` isolate Windows, macOS, Linux, Android, and iOS integration. Preserve `cfg` boundaries when changing shared modules.
- Security-sensitive state and flows are spread across `src/server/connection.rs`, `src/trusted_devices/`, `src/auth_2fa.rs`, `src/privacy_mode/`, `src/ipc/`, and the platform modules. Trace both the client and host paths for authentication, authorization, credentials, or privacy-mode changes.

### Workspace libraries and shared protocol code

- `libs/hbb_common` is a git submodule shared with the RustDesk server. It owns common configuration, rendezvous protobufs, socket/network wrappers, logging, and shared utilities. Changes there are submodule changes and must be considered separately from client-only work.
- `libs/base` (`base`) contains client-only configuration keys, message protobufs, filesystem/file-transfer support, and platform helpers. `base::config::keys` is the common import path for option keys.
- `libs/scrap` provides platform screen capture and codec-related capture support; `libs/enigo` provides keyboard/mouse simulation; `libs/clipboard` provides cross-platform clipboard/file-copy-paste support.
- `libs/virtual_display`, `libs/remote_printer`, and `libs/portable` provide Windows virtual-display, printer, and portable-wrapper/packer functionality. The remaining workspace crates are platform/build support and should be changed only when the feature needs them.

### Flutter UI and FFI

- `flutter/lib/main.dart` is the Flutter entry point. It dispatches desktop main, connection-manager, install, and multi-window modes; remote desktop, file transfer, camera, port-forward, and terminal windows are separate screens.
- Shared state, models, platform abstraction, and common widgets live under `flutter/lib/common/`, `flutter/lib/models/`, `flutter/lib/native/`, `flutter/lib/utils/`, and the desktop/mobile subtrees. Use the existing platform-conditional imports rather than spreading target checks through shared widgets.
- Native Flutter targets use Rust for session/runtime behavior. `src/flutter_ffi.rs` exposes FFI functions and event streams, `src/flutter.rs` implements the Flutter session/rendering handlers, and Dart calls them through the generated bridge. `flutter/lib/generated_bridge.dart`, `src/bridge_generated.rs`, and `src/bridge_generated.io.rs` are ignored/generated artifacts; follow `AGENTS.md` for adding FFI functions.
- Flutter Web is a separate runtime: Rust does not compile for the web. The hand-written Dart/JavaScript boundary is `flutter/lib/web/bridge.dart`, while the JS/TypeScript client under `flutter/web/js/` owns web connection, codec, keyboard, clipboard, and related runtime behavior. Keep web-specific calls behind the bridge.
- `src/ui/` is the deprecated Sciter UI. New UI work normally belongs in Flutter unless the request explicitly targets the legacy path.

### Tests and localization

- Rust unit tests are generally `#[cfg(test)]` modules beside the implementation. Flutter tests belong only in `flutter/test/*_test.dart`; web core tests, when present, live under `flutter/web/js/src/*.test.ts` and use that web client repository's Jest setup.
- Localization files under `src/lang/` are keyed maps. `template.rs` defines the complete key set; `en.rs` contains English values that differ from keys; other languages carry the full set. For translation work, fill only empty values and preserve placeholders/technical tokens. See `AGENTS.md` before adding keys.

## Change-scope constraints

- Prefer a feature-local/platform-local function plus a thin hook in shared code over changing widely used traits, structs, or signatures.
- Keep disabled-feature behavior on the existing path where practical, and avoid unrelated refactors or formatting-only changes.
- For every implementation, inspect the final diff for unnecessary existing-file/path changes and state the unavoidable regression surface in the final report. Detailed logging, Tokio, import, comment, and test rules are in `AGENTS.md`.
