# 多 ID / 中继服务器选择 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Windows、macOS、Linux 桌面端增加多服务器档案管理、按远程 ID 选择/记忆服务器，并让每个新会话隔离地使用所选 ID/Relay/API/Key 配置。

**Architecture:** Flutter 侧维护版本化服务器档案 JSON 和默认档案 ID，首次读取时从旧的全局 `ServerConfig` 迁移；设备偏好只在 `PeerConfig.options` 中保存档案 ID。连接页解析纯远程 ID的偏好并把所选档案的完整快照沿着多窗口参数和 `sessionAddSync` 传入 Rust；Rust 在 `LoginConfigHandler` 中固定服务器上下文，`Client` 的 rendezvous、relay、key、health-check 和审计 URL 都从该上下文读取，而不修改全局 `Config`。认证完成后由桌面 Dart 会话事件写回偏好。

**Tech Stack:** Rust 2021、Flutter/Dart、flutter_rust_bridge 1.80 手写边界、现有 `PeerConfig`/local option 持久化、Flutter widget tests、Rust unit tests。

**Spec:** `docs/superpowers/specs/2026-11-11-multi-id-relay-server-design.md`

## Global Constraints

- 仅支持 Flutter 桌面端 Windows、macOS、Linux；移动端和 Web 不新增此功能路径。
- `AGENTS.md` 是 Rust/Tokio/FFI/测试/本地化规则的权威来源；不要运行 `flutter_rust_bridge_codegen`，不要提交生成的 bridge 文件。
- 不修改外部 URI、命令行参数和现有 `id@server` 连接语法；显式 `id@server` 优先于档案选择，并且成功后不覆盖纯 ID 偏好。
- 服务器档案包含名称、稳定档案 ID、ID Server、Relay Server、API Server、Key；默认档案继续驱动既有未指定档案的全局行为。
- 服务器选择不能通过修改全局 Rust `Config` 实现；已有会话和其重连必须继续使用启动时捕获的上下文。
- 只有会话完成认证并收到远程设备信息后才保存设备偏好；失败、取消和连接尚未成功时不保存。
- 复用现有服务器校验、导入/导出和 `PeerConfig` 机制；不做无关重构或格式化。
- Rust 测试放在邻近 `#[cfg(test)]` 模块；Flutter 测试只放在 `flutter/test/*_test.dart`。

## Review Focus

- 旧全局配置、缺少/损坏档案 JSON、重复档案 ID、缺失默认项和删除默认档案必须确定性迁移/回退，而不能让用户失去连接配置。→ Task 1 migration tests。
- `id@server`、`id/r` 和 IP/domain:port 等显式连接格式不能被档案下拉框或纯 ID 偏好错误改写。→ Task 4 normalization tests。
- 同一 ID 并发连接使用不同档案时，只有认证成功事件能写偏好，并以最后成功事件为准；连接失败和早期 transport-ready 不能写。→ Task 6 lifecycle tests。
- 档案切换、编辑、删除不能改变已有会话、重连或 relay fallback 的 rendezvous/relay/key/API 上下文。→ Task 5 Rust context tests。
- 多窗口、历史/收藏/设备卡片、远程桌面/文件传输/终端/端口转发/RDP/摄像头必须传递同一档案上下文，且移动/Web 路径不被桌面改动破坏。→ Task 4/7 propagation tests。

---

## 文件结构与职责

- **Create:** `flutter/lib/models/server_config.dart` — 桌面可复用的服务器档案模型、版本化 JSON 编解码、迁移/回退和档案选择纯函数；不依赖 widget。
- **Modify:** `flutter/lib/common.dart` — 导出模型（或保留兼容类型别名）、连接上下文解析、连接参数分发和连接成功后的偏好保存辅助函数。
- **Modify:** `flutter/lib/desktop/pages/desktop_setting_page.dart` — 桌面“设置 → 网络”档案列表/编辑/删除/默认 UI。
- **Modify:** `flutter/lib/mobile/widgets/dialog.dart` — 复用现有服务器字段表单和校验能力，但让导入/编辑可由桌面档案管理器调用；不在移动设置页启用多档案 UI。
- **Modify:** `flutter/lib/desktop/pages/connection_page.dart` — 桌面主连接页的服务器下拉框、按 ID 加载偏好和向所有连接类型传递选中档案。
- **Modify:** `flutter/lib/common/widgets/peer_card.dart` — 其他桌面设备入口使用设备偏好解析，不增加选择控件。
- **Modify:** `flutter/lib/utils/multi_window_manager.dart` — 序列化/转发 `serverProfile` 快照到新窗口和复用窗口调用。
- **Modify:** `flutter/lib/desktop/pages/desktop_home_page.dart` — 主窗口处理器转发服务器快照。
- **Modify:** `flutter/lib/desktop/pages/{remote_tab_page,file_manager_tab_page,view_camera_tab_page,port_forward_tab_page,terminal_tab_page}.dart` — 从窗口参数读取并传给 `FFI.start`；tab 移窗复用既有 session 时不重新解析。
- **Modify:** `flutter/lib/desktop/pages/{remote_page,file_manager_page,view_camera_page,port_forward_page,terminal_page}.dart` — 保存/传递会话参数类型，保持已有页面调用链。
- **Modify:** `flutter/lib/models/model.dart` — `FFI.start` 接收服务器快照，扩展 `sessionAddSync` 调用，认证成功事件写设备偏好，连接上下文跨 session 生命周期保留。
- **Modify:** `flutter/lib/models/platform_model.dart` — 仅在需要时补充桌面/生成桥接口调用；保持 conditional import。
- **Modify:** `flutter/lib/web/bridge.dart` — 保持签名同步但让 Web 使用旧参数/空上下文默认，避免新增桌面参数导致 Dart 接口不一致；不启用档案 UI。
- **Modify:** `src/flutter_ffi.rs` — `session_add_sync` 增加可选服务器快照参数，传入 Rust session；手写 FFI 入口，不改生成文件。
- **Modify:** `src/flutter.rs` — `session_add` 和 Flutter session 初始化传递服务器上下文；在需要时暴露当前档案/认证成功事件信息。
- **Modify:** `src/ui_session_interface.rs` — `Session` / `LoginConfigHandler` 保存不可变服务器上下文，审计 API 从 session 配置读取。
- **Modify:** `src/client.rs` — `LoginConfigHandler::initialize` 接收 context，`Client` rendezvous、relay fallback、health-check 和 key 使用 session context；保留 `id@server` 旧路径优先级。
- **Modify:** `src/client/io_loop.rs` — 认证完成后触发足够的 UI 成功事件/元数据，确保偏好保存时机晚于认证而早于后续 UI 依赖。
- **Modify:** `src/rendezvous_mediator.rs` — 仅检查 server-side 全局路径不被 outbound session 改动破坏；如 relay 服务器需要上下文，使用连接 session 传入而非全局读取。
- **Create:** `flutter/test/server_config_profile_test.dart` — 档案模型、迁移、回退和设备偏好选择测试。
- **Modify:** `flutter/test/server_settings_dialog_test.dart` — 档案编辑表单字段/校验回归。
- **Create:** `flutter/test/server_selection_connection_test.dart` — 连接页选择、参数传播和成功/失败保存行为测试。
- **Modify:** `src/client.rs` 或 `src/ui_session_interface.rs` 附近测试模块 — session server context、显式服务器优先级、重连/relay context 测试。

---

### Task 1: 建立服务器档案模型与旧配置迁移

**Files:**
- Create: `flutter/lib/models/server_config.dart`
- Modify: `flutter/lib/common.dart:imports and existing ServerConfig`
- Create: `flutter/test/server_config_profile_test.dart`

**Interfaces:**
- Produces `ServerProfile` with `id`, `name`, `idServer`, `relayServer`, `apiServer`, `key` fields and JSON conversion.
- Produces `ServerProfileStore` with versioned decode/encode, `fromLegacy(ServerConfig)`, `defaultProfile`, `profileForPeer`, and CRUD/default-selection pure operations.
- Produces a serialized `ServerProfileSnapshot`/map representation safe to pass through `jsonEncode` into multi-window and FFI.
- Uses existing `ServerConfig.encode/decode` field semantics and `bind.mainGetOption/mainSetOption` only in a later persistence adapter; model tests remain pure.

- [ ] **Step 1: Write failing pure model tests**

Add tests for:

- decoding an empty/new store creates exactly one profile named `Default`/translated default label, with a stable generated ID and default ID set;
- migrating legacy `custom-rendezvous-server`, `relay-server`, `api-server`, and `key` copies all four values exactly once;
- a second decode with a valid versioned store does not add another migrated profile;
- invalid JSON, duplicate profile IDs, missing default ID, and a missing peer profile ID fall back deterministically to the first valid/default profile;
- renaming/editing preserves profile ID; deleting a non-last profile clears references and returns default fallback; deleting the default requires another profile to become default first;
- snapshot round-trip preserves all fields including literal keys and empty relay/API values.

- [ ] **Step 2: Run the focused Flutter test and verify it fails**

Run from `flutter/`:

```sh
flutter test test/server_config_profile_test.dart
```

Expected: FAIL because the profile model and operations are not defined.

- [ ] **Step 3: Implement the pure profile model**

Use a versioned top-level JSON object such as `{version, defaultProfileId, profiles}` and UUID-like stable IDs generated only when creating a new profile. Treat missing/invalid profiles as unusable, preserve valid entries, and choose a deterministic first valid profile when default metadata is bad. Keep the model independent of Flutter widgets and do not store per-peer preferences in this collection.

- [ ] **Step 4: Add the persistence adapter in `common.dart`**

Define desktop-only helpers around `bind.mainGetLocalOption`/`mainSetLocalOption` using one dedicated local option key for the profile store. On first read, load legacy global options through `mainGetOptions`, create the migrated default profile, persist the versioned store, and thereafter never reconstruct profiles from legacy fields. Add helpers to read/write only the peer profile ID via `mainGetPeerOption`/`mainSetPeerOption`, clearing it when deleting a profile. Keep a compatibility `ServerConfig` view for the existing form and import/export code.

- [ ] **Step 5: Run focused tests and verify they pass**

```sh
flutter test test/server_config_profile_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```sh
git add flutter/lib/models/server_config.dart flutter/lib/common.dart flutter/test/server_config_profile_test.dart
git commit -m "feat: add desktop server profile storage"
```

---

### Task 2: Convert desktop Network settings to profile management

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_setting_page.dart:1801-1980`
- Modify: `flutter/lib/mobile/widgets/dialog.dart:57-222`
- Modify: `flutter/lib/common/widgets/setting_widgets.dart:181-213`
- Modify: `flutter/test/server_settings_dialog_test.dart`

**Interfaces:**
- Consumes Task 1 `ServerProfileStore` persistence helpers and `ServerProfile` snapshots.
- Produces desktop UI actions: add profile, edit profile, set default, delete profile, and refresh the Network card after each operation.
- Preserves the existing `ServerConfig` validation contract: ID/relay server test calls, API URL validation, key literal handling, import/export.

- [ ] **Step 1: Extend widget tests for profile editing behavior**

Pin that the profile form:

- preserves literal key text and existing no-autocorrect/password-field behavior;
- validates ID and relay through the existing server validator before saving;
- keeps API URL validation;
- supports loading a profile into the same four-field form and returns the edited name plus `ServerConfig` without mutating the original profile until Save.

- [ ] **Step 2: Run the focused widget test and verify the new assertions fail**

```sh
flutter test test/server_settings_dialog_test.dart
```

Expected: FAIL for the new profile form behavior.

- [ ] **Step 3: Implement profile editor/list UI**

Refactor only the desktop Network tile action: show a profile list dialog/page with name, ID server summary, default marker, edit/delete/default actions, and Add. Reuse `showServerSettingsWithValue`/`setServerConfig` validation by extending the form with a name field and returning a profile candidate; do not expose this list from mobile settings. Prevent deleting the last profile and require a different default before deleting the current default. Keep import/export attached to the selected profile form.

- [ ] **Step 4: Preserve legacy settings entry points**

Keep mobile `showServerSettings` editing the effective global/default profile through the old single-form path, or route only its saved values through the profile store without adding list UI. Deep-link/import paths remain legacy and must update the default profile only when they target global settings; they must not silently overwrite a non-default profile.

- [ ] **Step 5: Run settings tests and static formatting**

```sh
flutter test test/server_settings_dialog_test.dart
 dart format --output=none --set-exit-if-changed lib
```

Expected: PASS and no formatting changes required.

- [ ] **Step 6: Commit**

```sh
git add flutter/lib/desktop/pages/desktop_setting_page.dart flutter/lib/mobile/widgets/dialog.dart flutter/lib/common/widgets/setting_widgets.dart flutter/test/server_settings_dialog_test.dart
git commit -m "feat: manage multiple desktop server profiles"
```

---

### Task 3: Add connection-context types and desktop profile resolution

**Files:**
- Modify: `flutter/lib/common.dart:connect/connectMainDesktop`
- Modify: `flutter/lib/desktop/pages/connection_page.dart:190-664`
- Modify: `flutter/lib/common/widgets/peer_card.dart:1567-1609`
- Create: `flutter/test/server_selection_connection_test.dart`

**Interfaces:**
- Consumes `ServerProfileSnapshot` and `loadServerProfileStore()` from Task 1.
- Produces `Future<ServerProfileSnapshot?> resolveDesktopServerProfile(String rawId)`; explicit `id@server` returns null/legacy mode, while a pure ID returns peer preference or default.
- Extends `connect(..., {ServerProfileSnapshot? serverProfile})` and `connectMainDesktop(..., {ServerProfileSnapshot? serverProfile})` without changing mobile call semantics.
- Produces a context map field named `serverProfile` for multi-window JSON; the snapshot is complete and immutable for the new session.

- [ ] **Step 1: Write failing connection-resolution tests**

Test:

- pure ID with no peer preference resolves the global default profile;
- pure ID with a valid peer profile resolves that profile;
- a missing/deleted peer profile falls back to default and clears stale preference only through the explicit cleanup path;
- `123/r` and `123@server`/other explicit server forms bypass profile selection;
- selecting a profile changes only the returned snapshot and does not write peer preference;
- profile snapshots passed to desktop connection functions contain ID/relay/API/key/name/profile ID.

- [ ] **Step 2: Run focused test and verify failure**

```sh
flutter test test/server_selection_connection_test.dart
```

Expected: FAIL because resolution and the `serverProfile` connection parameter are absent.

- [ ] **Step 3: Implement pure-ID normalization and resolution**

Normalize only for lookup using the same server-side semantics as `mainHandleRelayId`; retain the user’s explicit server syntax for the legacy path. Do not parse arbitrary `@` content into a profile. Load the profile store, read the peer profile ID, return a valid snapshot or the default snapshot, and never persist selection here.

- [ ] **Step 4: Add the desktop dropdown and selection state**

In `ConnectionPage`, load profiles after the remote ID changes/selection and initialize the selection to peer preference/default. Add the A-layout dropdown near the ID field; changing it updates local state only. Pass the selected snapshot to Connect, file transfer, camera, terminal, TCP tunnel, RDP, and request-approval actions. Ensure submitted ID and autocomplete selection refresh the selected profile.

- [ ] **Step 5: Propagate profile resolution to other desktop entry points**

Update `connect` and `connectMainDesktop` so desktop history/favorite/device-card calls resolve the saved profile automatically when they do not provide an explicit context. `connectInPeerTab` needs no new UI; it must inherit resolution by calling the shared function. URI/command-line and mobile paths continue without profile resolution.

- [ ] **Step 6: Run focused tests and format**

```sh
flutter test test/server_selection_connection_test.dart
 dart format --output=none --set-exit-if-changed lib
```

Expected: PASS and clean formatting.

- [ ] **Step 7: Commit**

```sh
git add flutter/lib/common.dart flutter/lib/desktop/pages/connection_page.dart flutter/lib/common/widgets/peer_card.dart flutter/test/server_selection_connection_test.dart
git commit -m "feat: select server profiles for desktop connections"
```

---

### Task 4: Propagate server snapshots through desktop windows and FFI

**Files:**
- Modify: `flutter/lib/utils/multi_window_manager.dart:182-400`
- Modify: `flutter/lib/desktop/pages/desktop_home_page.dart:796-808`
- Modify: `flutter/lib/desktop/pages/{remote_tab_page,file_manager_tab_page,view_camera_tab_page,port_forward_tab_page,terminal_tab_page}.dart`
- Modify: `flutter/lib/desktop/pages/{remote_page,file_manager_page,view_camera_page,port_forward_page,terminal_page}.dart`
- Modify: `flutter/lib/models/model.dart:4111-4217`
- Modify: `src/flutter_ffi.rs:137-190`
- Modify: `src/flutter.rs:1306-1386`
- Modify: `flutter/lib/web/bridge.dart:139-166`

**Interfaces:**
- Consumes `serverProfile` map from Task 3.
- Produces `sessionAddSync(..., serverProfile: Option<String>)` in the native generated interface; the manual Rust FFI function accepts an optional JSON string and ignores it on mobile/legacy calls.
- `FFI.start(..., {Map<String,dynamic>? serverProfile})` carries the same snapshot to the session.
- Existing tab-to-window moves pass no new snapshot because they reuse an existing Rust session.

- [ ] **Step 1: Add propagation tests/fixtures**

Extend `server_selection_connection_test.dart` with a fake multi-window call assertion that all six desktop connection types serialize the same profile JSON and that the main window handler forwards it. Add a test that a tab move payload uses `tab_window_id/session_id` only and does not create a second profile context.

- [ ] **Step 2: Run test and verify failure**

```sh
flutter test test/server_selection_connection_test.dart
```

Expected: FAIL because the window parameters and FFI signatures do not carry `serverProfile`.

- [ ] **Step 3: Extend Dart window/page parameter plumbing**

Add `Map<String,dynamic>? serverProfile` to `newSession`, `newRemoteDesktop`, `newFileTransfer`, `newViewCamera`, `newPortForward`, and `newTerminal`; JSON encode it under `serverProfile`. Forward it through `desktop_home_page.dart`, tab page constructors/argument readers, and page calls to `FFI.start`. Keep existing connToken/login/password/forceRelay handling unchanged.

- [ ] **Step 4: Extend native session creation signatures**

Add `server_profile: Option<String>` after the existing connection token/login parameters in the Rust `session_add_sync` chain. Parse the JSON into a validated Rust server-context struct; reject malformed context with a normal connection-add error rather than silently using another profile. Pass it through `flutter_ffi.rs::session_add_sync` → `flutter.rs::session_add` → `LoginConfigHandler::initialize`. Update only the ignored generated Dart/native bridge locally if required for compilation; do not commit generated files.

- [ ] **Step 5: Keep Web and non-profile callers compiling**

Update `flutter/lib/web/bridge.dart` to accept the optional argument and preserve the existing Web behavior, returning the old JS session call without attempting profile routing. All mobile and URI/CLI calls omit the optional argument.

- [ ] **Step 6: Run propagation tests and targeted compile checks**

```sh
flutter test test/server_selection_connection_test.dart
cargo check --locked --lib --features flutter
```

Expected: PASS; Cargo check succeeds without requiring generated bridge files to be committed.

- [ ] **Step 7: Commit**

```sh
git add flutter/lib/utils/multi_window_manager.dart flutter/lib/desktop/pages flutter/lib/models/model.dart src/flutter_ffi.rs src/flutter.rs flutter/lib/web/bridge.dart flutter/test/server_selection_connection_test.dart
git commit -m "feat: pass server profiles into desktop sessions"
```

---

### Task 5: Make Rust outbound connection behavior session-scoped

**Files:**
- Modify: `src/client.rs:2831-3020, 3700-3960, 4930-5030, 5270-5300`
- Modify: `src/ui_session_interface.rs:61-85, 581-600, 1788-1900`
- Modify: `src/client/io_loop.rs:187-290`
- Modify: `src/rendezvous_mediator.rs` only if the outbound context requires a helper boundary; never change incoming global mediator semantics.
- Modify: nearest Rust test modules in `src/client.rs`/`src/ui_session_interface.rs`

**Interfaces:**
- Consumes validated `ServerProfileContext { profile_id, name, rendezvous_server, relay_server, api_server, key }` from Task 4.
- `LoginConfigHandler` stores `server_profile: Option<ServerProfileContext>` as an immutable session snapshot and exposes helpers such as `rendezvous_server()`, `relay_server()`, `api_server()`, and `key()` for outbound paths.
- `Client::_start` uses the session context for rendezvous selection; explicit `other_server` remains higher priority.
- `io_loop` passes the session-selected key and rendezvous server into health-check rather than global `get_key`/`get_rendezvous_server`.

- [ ] **Step 1: Write failing Rust tests for context isolation**

Add unit tests for:

- a session context supplies its own ID server, relay server, API server, and key;
- no context preserves current global behavior;
- editing/replacing global options after session initialization does not change the session snapshot;
- explicit `id@server`/`other_server` takes precedence over profile rendezvous/key semantics and does not use the profile as a hidden override;
- relay fallback and health-check helper receive the same rendezvous/relay context.

- [ ] **Step 2: Run focused tests and verify failure**

```sh
cargo test --locked --lib server_profile --features flutter
```

Expected: FAIL because the context type and session-scoped helpers do not exist.

- [ ] **Step 3: Implement the Rust context type and initialization**

Define a serde-deserializable context with non-empty profile ID and normalized server strings where required. Store it in `LoginConfigHandler` at initialization, before loading connection state. Keep `other_server` parsing first-class: if the ID contains the existing explicit form, use that path and mark the profile context as non-authoritative for rendezvous/key selection.

- [ ] **Step 4: Replace outbound global reads with context-aware helpers**

In `Client::_start`, choose the session rendezvous server/backup list from context when present, otherwise call the existing global helper. Pass the selected context relay into all `request_relay`/`create_relay` and WebRTC fallback paths. Use context key for secure TCP, secure connection, and login-related rendezvous messages. Do not change server-side `RendezvousMediator::start_all` or `get_relay_server` behavior for incoming sessions.

- [ ] **Step 5: Preserve API/audit and health-check semantics per session**

Make `LoginConfigHandler::get_audit_server` use its context API/rendezvous fields when the profile is authoritative. Pass the session rendezvous/key into `hc_connection`; only no-context sessions use global `get_key`/global rendezvous. Keep global account/settings APIs driven by the default profile outside a session.

- [ ] **Step 6: Run targeted Rust tests and compile**

```sh
cargo test --locked --lib server_profile --features flutter
cargo check --locked --lib --features flutter
```

Expected: PASS and successful compile.

- [ ] **Step 7: Commit**

```sh
git add src/client.rs src/client/io_loop.rs src/ui_session_interface.rs src/rendezvous_mediator.rs
 git commit -m "feat: scope outbound connections to server profiles"
```

---

### Task 6: Save per-device preference only after authenticated success

**Files:**
- Modify: `src/ui_session_interface.rs`/`src/flutter.rs` if the success event needs profile metadata.
- Modify: `flutter/lib/models/model.dart:267-350, 888-980`
- Modify: `flutter/lib/common.dart` preference helper.
- Modify: `flutter/test/server_selection_connection_test.dart`
- Modify: nearest Rust tests if event payload is changed.

**Interfaces:**
- Consumes the session’s profile ID and pure remote ID.
- Produces a Dart success event containing enough information to write `{peerId -> profileId}` only after `handle_peer_info`/`on_connected`, not merely transport `connection_ready`.
- Uses `savePeerServerProfileId(peerId, profileId)` with validation that profile ID still exists.

- [ ] **Step 1: Write failing lifecycle tests**

Pin that:

- a transport-ready/`connection_ready` event alone does not write a peer preference;
- authenticated remote peer info writes the selected profile ID;
- a failed connection, cancellation, rejected insecure connection, or missing profile does not write;
- duplicate success events are idempotent;
- two successful sessions for the same pure ID update the preference in event order (last success wins);
- explicit `id@server` success never writes the pure-ID preference.

- [ ] **Step 2: Run focused test and verify failure**

```sh
flutter test test/server_selection_connection_test.dart
```

Expected: FAIL because success events do not carry/profile-save context.

- [ ] **Step 3: Emit authenticated success metadata**

At the existing `handle_peer_info`/`on_connected` point, emit a session event or extend the success event with `peer_id`, `server_profile_id`, and an explicit-server flag. Do not use the earlier `set_connection_type` transport event for persistence. Keep Sciter behavior unchanged; gate the added metadata/handler under Flutter where appropriate.

- [ ] **Step 4: Save and validate preference in Dart**

Handle the authenticated success event in `FfiModel.startEventListener`, validate that the profile still exists in the current store, then write the peer option only for a pure remote ID. If the profile was deleted after session start, do not write a dangling ID; the existing session continues with its snapshot and future lookups use default.

- [ ] **Step 5: Run lifecycle tests and formatting**

```sh
flutter test test/server_selection_connection_test.dart
 dart format --output=none --set-exit-if-changed lib
cargo test --locked --lib server_profile --features flutter
```

Expected: PASS and clean formatting.

- [ ] **Step 6: Commit**

```sh
git add src/ui_session_interface.rs src/flutter.rs flutter/lib/models/model.dart flutter/lib/common.dart flutter/test/server_selection_connection_test.dart
git commit -m "feat: remember the server profile after connection success"
```

---

### Task 7: Verify all desktop entry points and regressions

**Files:**
- Modify: `flutter/lib/common.dart`, `flutter/lib/common/widgets/peer_card.dart`, and any desktop page files only if propagation gaps remain.
- Modify: `flutter/test/server_selection_connection_test.dart` for integration-shaped widget/unit coverage.
- Modify: `src/client.rs`/`src/ui_session_interface.rs` tests only for uncovered context paths.

**Interfaces:**
- Consumes completed profile store, desktop propagation, Rust context, and success persistence APIs from Tasks 1–6.
- Produces no new public API; this task closes the specified entry-point matrix and regression checks.

- [ ] **Step 1: Add matrix tests**

Cover desktop connections from main page, recent/favorite/device card, request approval, and toolbar “Transfer file/View camera/Terminal/TCP tunneling”; assert that all non-explicit paths resolve the same peer profile and all explicit paths preserve legacy behavior. Cover RDP and camera through their existing window parameter routes.

- [ ] **Step 2: Run full focused Flutter tests**

```sh
flutter test --timeout 60s test/server_config_profile_test.dart test/server_settings_dialog_test.dart test/server_selection_connection_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Rust formatting/checks and feature tests**

```sh
cargo fmt --all -- --check
cargo test --locked --lib --features flutter
cargo test --locked --workspace
```

Expected: PASS; if platform/native dependencies prevent a local command, record the exact failure rather than claiming success.

- [ ] **Step 4: Inspect the final diff for regression surface**

Verify that mobile/Web UI is unchanged except optional bridge compatibility signatures, URI/CLI and `id@server` paths remain on legacy behavior, incoming server mediator behavior remains global, generated bridge files are not staged, and existing sessions use only their captured context.

- [ ] **Step 5: Commit final test adjustments**

```sh
git add flutter/test/server_selection_connection_test.dart flutter/lib src
 git commit -m "test: cover desktop server profile connection paths"
```

---

## Self-review checklist

- **Spec coverage:** Tasks 1–2 cover profile CRUD/migration; Task 3 covers A-layout selection and other desktop entry-point resolution; Task 4 covers all desktop window/FFI propagation; Task 5 covers session isolation/rendezvous/relay/key/API; Task 6 covers authenticated-only persistence and concurrency; Task 7 covers regression matrix and verification.
- **Type consistency:** `ServerProfileSnapshot`/`serverProfile` is introduced in Task 1/3, propagated in Task 4, decoded as `ServerProfileContext` in Task 5, and saved by profile ID in Task 6.
- **Review focus coverage:** Every line in Review Focus names its owning task and corresponding test condition.
- **Regression surface:** Existing global behavior remains the default; only explicitly selected desktop sessions use a non-default context; explicit server syntax and non-desktop paths retain their old route.
- **Proportion:** The plan specifies files, interfaces, tests, and decisions without prescribing unrelated implementation details; builders may choose the exact JSON key names and dialog layout within the approved boundaries.
