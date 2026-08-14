# anta

The ANTA Flutter app — an offline-first personal tracker built on folders, markdown notes, a money ledger, counters, and a calendar. See the [repository README](../../README.md) for the feature overview.

## Setup

Requires the Flutter SDK (Dart SDK `^3.10.4`).

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift generated code
flutter gen-l10n                                            # localizations from lib/l10n/*.arb
```

Both generation steps are required before the first build — `lib/database/database.g.dart` and `lib/l10n/app_localizations*.dart` are generated outputs and must never be hand-edited.

## Everyday commands

```powershell
flutter run                     # run on the connected device/emulator (Android is primary)
flutter run -d windows          # quick desktop UI check
dart analyze lib                # static analysis — the minimum bar for any Dart change
flutter test                    # run the test suite
```

Re-run `dart run build_runner build --delete-conflicting-outputs` after changing Drift tables, DAOs, migrations, or database annotations, and `flutter gen-l10n` after editing any `lib/l10n/*.arb` file (then check `untranslated.txt` for missing German/Romanian keys).

## Helper scripts

`.bat` for Windows, `.sh` for Unix shells. The release/install scripts run code generation, localization, and `flutter clean` before building.

| Script | Purpose |
| --- | --- |
| `generate_drift.bat` | Run build_runner once, or `generate_drift.bat watch` to watch |
| `build_release.bat [arm64]` | Obfuscated release APK → `build\app\outputs\flutter-apk\` |
| `install_to_device.bat [arm64]` | Build a release APK and `adb install` it |
| `full_clean.bat` | Nuke `build/`, `.dart_tool/`, and re-run `pub get` |

## Project layout

```
lib/
  bloc/          BLoCs (thin: route events, hold state, delegate to services)
  services/      app workflows — storage, auto-save, counters, settings, backup, import/export, calendar, rendering
  repositories/  cached/reactive access over DAOs
  database/      Drift schema, DAOs, migrations, CRDT metadata
  pages/         screens (the folder browser and note editor carry most of the app)
  widgets/       shared UI, markdown toolbar, preview views, editor wrapper, sheets
  utils/         markdown grammars + renderers (one grammar module per syntax, shared by preview and editor)
  models/ constants/ config/ controllers/ handlers/ factories/ core/  supporting layers
  l10n/          app_en.arb (source), app_de.arb, app_ro.arb
packages/re_editor/   local performance-tuned editor fork
docs/                 per-subsystem feature references and roadmaps
test/                 unit tests
```

## Contributing

Read [CLAUDE.md](CLAUDE.md) for the architecture rules and [COPILOT_CONTEXT.md](COPILOT_CONTEXT.md) for the canonical, per-subsystem context before making changes. In short: never bypass the `Page → BLoC → Service → Repository → DAO → Drift` flow, localize every user-visible string across all three ARB files, keep persisted-data semantics and backup compatibility intact, and add a migration rather than resetting storage.
