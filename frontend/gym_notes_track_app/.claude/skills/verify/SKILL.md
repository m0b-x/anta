---
name: verify
description: How to validate and run ANTA changes end-to-end on Windows - which generators/analysis to run per change type, and how to launch or install the Flutter app. USE FOR - verifying a change works, running the app, building a release, or installing to a device.
---

# Verifying Changes in ANTA

All commands run from the app root (`frontend/gym_notes_track_app`) in PowerShell. Run **only what the change requires**, in this order.

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

## 3. Run the app (behavioral verification)

```powershell
flutter run
```

Launches on the connected device/emulator (Android is the primary target; Windows desktop works for quick UI checks: `flutter run -d windows`). Hot reload with `r`, hot restart with `R` in the run console.

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

- The test suite is small and targeted (`test/` — currently the money-ledger grammar in `test/utils/markdown_money_syntax_test.dart`). Run `flutter test` when the change touches covered code; a single file is `flutter test test/utils/markdown_money_syntax_test.dart`, a single case adds `--plain-name "<substring>"`. Otherwise verification is analyzer + running the app, and the project convention remains **no new tests unless explicitly requested**.
- Do not use `flutter analyze` on the whole workspace (platform shells add noise); `dart analyze lib` is the convention.
