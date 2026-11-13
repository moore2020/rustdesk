# SDD ledger — plan: docs/superpowers/plans/2026-11-12-multi-id-relay-server-plan.md

Reconstructed 2026-11-12 22:06 +0800. The previous workspace/ledger was deleted when the
plan finished (user chose "Keep the branch as-is"); git history is authoritative for tasks.

Task 1: complete (commit 4c4247ed6, reconstructed; tests unavailable locally at the time)
Task 2: complete (commit f6e837edc, reconstructed; tests unavailable locally at the time)
Task 3: complete (commit d0f8849bd, reconstructed; tests unavailable locally at the time)
Task 4: complete (commit 918e0265e, reconstructed; tests unavailable locally at the time)
Task 5: complete (commit f6453c4bc, reconstructed; tests unavailable locally at the time)
Task 6: complete (commit 5eb3587cf, reconstructed; tests unavailable locally at the time)
Task 7: complete (commit 9d3054b83, reconstructed; tests unavailable locally at the time)
Final review: self-review (no subagent tool at the time); fixes in 4b5dc93ae and 8c8dd6054.
Ruling carried from prior ledger (D13): no local Flutter/Rust toolchains; tests were authored but not executed.

Resume 2026-11-12: a Docker toolchain (rustdesk-flutter-builder image) was later built and the
release deb compiled successfully. Outstanding gap: the plan's Task 7 verification commands were
never run. Completing them now in Docker.

Resume verification 2026-11-12 (Docker rustdesk-flutter-builder, Flutter 3.24.5, Rust 1.99.1):
- flutter test focused (server_config_profile, server_settings_dialog, server_selection_connection) -> 34/34 pass, exit 0.
  Found and fixed one test-only bug: the pure-render profile form test left CustomAlertDialog's
  zero-duration focus timer pending; added `await tester.pump(Duration.zero)`.
- flutter test full suite -> 206 pass, 1 skipped, exit 0.
- dart format --output=none --set-exit-if-changed lib test -> exit 1, 51 files flagged including
  untouched master files (repo uses newer Dart tall style; container pins Flutter 3.24.5's formatter).
  Ruling: do not reformat; our files follow the repo's prevailing style. Cost if wrong: style-only churn.
- cargo fmt --all -- --check -> reports diffs only in untouched files (libs/*, src/naming.rs) plus missing
  generated src/ui/inline.rs; CI's fmt job is commented out. Ruling: pre-existing toolchain mismatch.
- cargo test --locked --lib --features flutter server_profile -> running.

Windows CI build 2026-11-12:
- Local Flutter Windows build is unsupported on Linux: `"build windows" only supported on Windows hosts.`
- User chose GitHub Actions and explicitly authorized pushing to moore2020/rustdesk.
- Dedicated SSH key ~/.ssh/id_ed25519_rustdesk_ci added by the user as a write deploy key on the fork.
- Pushed branch worktree-zazzy-spinning-robin @ 3fe426961 (includes the test timer fix).
- Pushed tag v1.5.3-1: Flutter Tag Build run 43242321831 -> startup_failure, because the fork's
  Actions token is read-only while flutter-build.yml jobs request contents: write.
- Added fork-only branch ci/windows-preview @ ed38f0774 (based on 3fe426961) carrying the fork's
  existing Windows-only workflow adapted to trigger on that branch; pushed.
  Windows preview build run 43242705984 in progress (x86_64-pc-windows-msvc; unsigned artifacts).

Rust verification 2026-11-12 (Docker, features flutter,linux-pkg-config):
- cargo test --lib server_profile -> 5/5 pass. Required fixing a real test compile break:
  src/client/login_method.rs called session_add_sync with the old 13-arg signature; the
  release build skips cfg(test), so only the lib test target caught it. Commit 33756a4e5.
- cargo test --lib (full) -> 237 passed, 2 failed:
  * request_approval_preserves_saved_password: passes in isolation -> parallel/global-state flake.
  * alt_only_shortcut_neutralizes_windows_menu: fails in isolation with "kbd context error";
    src/keyboard/shortcuts.rs is untouched by this branch (pre-existing/platform-specific).
  Ruling: neither failure is caused by the branch; recorded rather than claimed green.
