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

## Release pipeline

One Dart tool, `tool/release/`, with the same verbs on every OS: `tool\release\release.cmd <verb>` on Windows, `./tool/release/release <verb>` on macOS/Linux. Builds are incremental by default; add `--clean` for a cold one.

| Verb | Purpose |
| --- | --- |
| `build [--arm64] [--clean]` | build_runner + gen-l10n, then the obfuscated release APK → `build/app/outputs/flutter-apk/` |
| `install [-d <serial>]` | The same, built for the attached phone's ABI, then `adb install` (a phone beats a running emulator) |
| `doctor [--fix]` | Signing keystore, Firebase config, adb + device, Gradle daemons of other versions (`--fix` stops them) |
| `gen [--watch]` | build_runner once (plus gen-l10n), or keep watching |
| `clean` | `flutter clean`, drop `.dart_tool/`, `pub get` — after freeing the Windows file locks that make a clean fail |

A release build is refused when `android/key.properties` and `android/app/release-keystore.jks` are missing: both are gitignored, so copy them from the machine that has them, keeping the paths. A debug-signed APK cannot install over the release-signed app (and uninstalling it wipes its data); Gradle's `preReleaseBuild` enforces the same rule for a bare `flutter build apk --release`.

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
