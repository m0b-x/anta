---
name: verify
description: How to validate and run ANTA changes end-to-end on Windows - which generators/analysis to run per change type, and how to launch or install the Flutter app. USE FOR - verifying a change works, running the app, building a release, or installing to a device.
---

# Verifying Changes in ANTA

All commands run from the app root (`frontend/anta`) in PowerShell. Run **only what the change requires**, in this order.

## 1. Regenerate (when applicable)

| If the change touched... | Run first |
| --- | --- |
| Drift tables / DAOs / migrations / DB annotations | `dart run build_runner build --delete-conflicting-outputs` (or `.\generate_drift.bat`) |
| ARB files (`lib/l10n/*.arb`) | `flutter gen-l10n` — then check `untranslated.txt` for missing de/ro keys |

## 2. Static analysis (always)

```powershell
dart analyze lib
```

This is the minimum bar for any Dart change. Also analyze `packages/re_editor` if the fork was touched: `dart analyze packages/re_editor/lib`.

## 3. Tests

```powershell
flutter test                                             # whole suite (~4,600 tests, benchmarks skipped)
flutter test test/utils/markdown_money_syntax_test.dart  # single file
flutter test test/qa --plain-name "escaping"             # single case
flutter test --tags benchmark --run-skipped              # seeded-volume DB timings
```

Tests are welcome (standing permission, 2026-08-16): new services and blocs ship with focused suites against fakes — see `test/bloc/sync_bloc_test.dart` for the pattern. Known noise: `test/database/vocabulary_crdt_test.dart` "moves the HLC" is a flake, and a `sqlite3.dll` lock crash is transient — rerun before investigating.

## 4. Run the app (behavioral verification)

```powershell
flutter run
```

Launches on the connected device/emulator (Android is the primary target; Windows desktop works for quick UI checks: `flutter run -d windows`). Hot reload with `r`, hot restart with `R` in the run console.

**The Windows build needs the Visual Studio component "C++ ATL for latest v145 build tools (x86 & x64)"** (`Microsoft.VisualStudio.Component.VC.ATL`), installed once on this machine. `flutter_local_notifications_windows` is an FFI plugin CMake compiles regardless of any Dart-side platform guard, and its `plugin.cpp` includes `atlbase.h`; without the component the build fails with `error C1083: Cannot open include file: 'atlbase.h'`.

**For a device pass, load the `qa-emulator` skill instead of driving adb or `xcrun simctl` by hand.** It covers booting a simulator or emulator, running against an isolated QA database (`./tool/qa/qa run --fresh --seed …`, `-d macos` for the desktop build), screenshots, tapping and typing by label through the in-app agent, the Dart MCP / Flutter Driver layer, and the trap list.

Release / device helpers:

```powershell
.\build_release.bat arm64      # release APK
.\install_to_device.bat arm64  # build + install to connected device
.\full_clean.bat               # nuke build artifacts when builds misbehave
```

## What to check per feature area

- **Editor/preview changes**: type in a note, toggle preview/split, confirm no lost text, search highlighting alignment, and editor↔preview scroll mapping on toggle.
- **Drift/migration changes**: launch with an existing database (never a wiped one) to prove the migration path; then create/edit data and hot-restart to prove persistence.
- **l10n changes**: switch app language between English, German, Romanian in settings and confirm the new strings render (no raw keys, plurals correct in Romanian).
- **Backup/import-export changes**: export, then re-import, and confirm timestamps/sort orders round-trip; verify an old-version backup still imports.
- **Multi-database changes**: switch databases in settings and confirm no stale singleton state (see the drift-migrations skill's `DatabaseLifecycle` contract).

## Notes

- Do not use `flutter analyze` on the whole workspace (platform shells add noise); `dart analyze lib` is the convention. Add `packages/re_editor/lib` when the fork changed, and `tool test_driver` when the QA harness changed.
- A device pass is not optional for UI work that changes layout, gestures or navigation — and it goes through the `qa-emulator` skill so the recipe stays in one place.
