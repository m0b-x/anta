---
name: verify
description: How to validate and run ANTA changes end-to-end - the gate every change passes (analyze, the whole test suite, gen-l10n), which generators to run per change type, and how to launch, drive or install the Flutter app on macOS or Windows. USE FOR - verifying a change works, running the app, a device pass, building a release, or installing to a device.
---

# Verifying Changes in ANTA

All commands run from the app root (`frontend/anta`): zsh on the owner's Mac (the primary machine since 2026-09), PowerShell on Windows. The Dart tools take the same verbs on both — `./tool/release/release` / `tool\release\release.cmd`, `./tool/qa/qa` / `tool\qa\qa.cmd`. Run **only what the change requires**, in this order.

## 0. The gate

A change is done when all of these hold; a rework's slice is done only when they hold (the `ui-revamp` skill):

1. `dart analyze lib` is clean — `dart analyze lib test` when tests changed; add `packages/re_editor/lib`, `packages/alarm/lib` or `tool test_driver` when those changed.
2. `flutter test` is green — the **whole** suite, not only the files you touched. **One `flutter test` at a time**, and never while a QA `flutter run` is up: two Flutter processes race on `build/native_assets` and kill each other.
3. If an ARB changed, `flutter gen-l10n` has run and `untranslated.txt` is empty.
4. If the change carried a must-not-change list, it was re-read against the diff.

## 1. Regenerate (when applicable)

| If the change touched... | Run first |
| --- | --- |
| Drift tables / DAOs / migrations / DB annotations | `dart run build_runner build --delete-conflicting-outputs` (or `./tool/release/release gen`) |
| ARB files (`lib/l10n/*.arb`) | `flutter gen-l10n` — then check `untranslated.txt` for missing de/ro keys |
| The alarm fork's Kotlin | `cd android && ./gradlew :alarm:testDebugUnitTest` |

## 2. Static analysis (always)

```zsh
dart analyze lib
```

This is the minimum bar for any Dart change. Also analyze `packages/re_editor/lib` if the fork was touched, and `packages/alarm/lib` for the alarm fork.

## 3. Tests

```zsh
flutter test                                             # whole suite (~5,900 tests, benchmarks skipped, ~75 s on the Mac)
flutter test test/utils/markdown_money_syntax_test.dart  # single file
flutter test test/qa --plain-name "escaping"             # single case
flutter test --tags benchmark --run-skipped              # seeded-volume DB timings
```

Tests are welcome (standing permission, 2026-08-16): new services, blocs and sheets ship with focused suites against fakes — `test/bloc/sync_bloc_test.dart` for a bloc, `test/widgets/event_look_sheet_test.dart` for a sheet. Known noise: a `sqlite3` lock crash is transient — rerun before investigating. The "moves the HLC" DAO tests flaked once from a precision bug in `HybridLogicalClock`, fixed 2026-09-22; if one flakes again suspect `hlc.dart`, not the test.

## 4. Run the app (behavioral verification)

```zsh
flutter run                      # Android is the primary target
flutter run -d macos             # desktop check on the Mac
flutter run -d windows           # desktop check on Windows (needs the ATL component below)
./tool/qa/qa <verb>              # a device pass against an isolated QA database
```

Hot reload with `r`, hot restart with `R` in the run console.

**The Windows build needs the Visual Studio component "C++ ATL for latest v145 build tools (x86 & x64)"** (`Microsoft.VisualStudio.Component.VC.ATL`), installed once on that machine. `flutter_local_notifications_windows` is an FFI plugin CMake compiles regardless of any Dart-side platform guard, and its `plugin.cpp` includes `atlbase.h`; without the component the build fails with `error C1083: Cannot open include file: 'atlbase.h'`.

**A device pass is not optional for UI work that changes layout, gestures or navigation, and it goes through the `qa-emulator` skill** — never `adb` or `xcrun simctl` by hand. It covers booting a simulator or emulator, running against an isolated QA database (`./tool/qa/qa run --fresh --seed …`, `-d macos` for the desktop build), screenshots, tapping and typing by label through the in-app agent, the Dart MCP / Flutter Driver layer, and the trap list.

Release pipeline (`./tool/release/release` on macOS, `tool\release\release.cmd` on Windows):

```zsh
./tool/release/release build --arm64   # release APK (incremental; --clean for a cold build)
./tool/release/release install         # build for the attached phone's ABI + adb install
./tool/release/release doctor          # keystore, Firebase config, adb, stale Gradle daemons
./tool/release/release clean           # nuke build artifacts when builds misbehave
```

Release builds are refused without the gitignored `android/key.properties` + `android/app/release-keystore.jks` — a debug-signed APK cannot install over the release-signed app on the phone.

## What to check per feature area

- **Editor/preview changes**: type in a note, toggle preview/split, confirm no lost text, search highlighting alignment, and editor↔preview scroll mapping on toggle.
- **Calendar UI changes**: the `calendar-ui` skill's test list and device pass — light and dark, en / de / ro, text scale 2.0, both phone sizes, the bottom-clearance test.
- **Drift/migration changes**: launch with an existing database (never a wiped one) to prove the migration path; then create/edit data and hot-restart to prove persistence.
- **l10n changes**: switch app language between English, German, Romanian in settings and confirm the new strings render (no raw keys, plurals correct in Romanian).
- **Backup/import-export changes**: export, then re-import, and confirm timestamps/sort orders round-trip; verify an old-version backup still imports.
- **Multi-database changes**: switch databases in settings and confirm no stale singleton state (see the drift-migrations skill's `DatabaseLifecycle` contract).

## Notes

- Do not use `flutter analyze` on the whole workspace (platform shells add noise); `dart analyze lib` is the convention. Add `packages/re_editor/lib` when the fork changed, and `tool test_driver` when the QA harness changed.
