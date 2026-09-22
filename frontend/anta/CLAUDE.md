# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**ANTA** (Dart package `anta`, app id `com.alexzamfir.anta`) — an offline-first Flutter app for tracking the things you keep coming back to: training sessions, spending, appointments, and the notes around them. Folders and markdown notes are the substrate; the money ledger, the calendar, and counters are built on top of them.

It started as a training log, and that origin still sets the bar: capture must be fast and reliable in the middle of something else — no lost text, no layout shifts, minimal taps. When two designs are otherwise equal, pick the one that survives one-handed use.

The app lives at `frontend/anta/`; all commands below run from there. The on-disk `gym_notes` database directory is a load-bearing runtime path, not branding — never rename it.

## Documentation map — read before editing

| Source | Use for |
| --- | --- |
| [COPILOT_CONTEXT.md](COPILOT_CONTEXT.md) | **Canonical context.** Product purpose, stack, architecture, per-subsystem invariants (markdown preview pipeline, chunking, lists, money ledger, colors, ghost text), persistence rules, import/export rules, re_editor fork notes. Read the relevant section before planning. Do not restate it back to the user — follow it. |
| [.claude/skills/](.claude/skills/) | Task-scoped skills: `anta-context` (load first), then `markdown-engine`, `drift-migrations`, `calendar-events`, `l10n`, `verify` as the task demands. |
| [.claude/skills/qa-emulator/](.claude/skills/qa-emulator/) | Driving the app on the iOS simulator, the macOS desktop build or the Android emulator: `tool/qa/qa` (boot, run in an isolated QA database, screenshot, dump the accessibility tree, tap/type by label through the in-app agent), the Flutter Driver layer through the Dart MCP, and the device traps. Load for any device pass. See also [docs/qa-harness.md](docs/qa-harness.md). |
| [docs/](docs/) | Feature references and roadmaps written per subsystem (`money-ledger-feature.md`, `live-markdown-editor-roadmap.md`, `calendar-events-feature.md`, `event-alerts-roadmap.md` + its `event-alerts-os-integration-roadmap.md` follow-up (alarm-clock semantics through the `alarm` fork in `packages/alarm/` — shipped in OS-1 — then native snooze, upcoming notice, alarm log, session chip, AlarmKit), `fasting-schedule-roadmap.md`, `presence-tracking-roadmap.md`, `calendar-cloud-readiness-roadmap.md`, `description-scope-roadmap.md`, `tag-system-roadmap.md`, `vocabulary-autocomplete-feature.md`, `colour-labels-roadmap.md` + its `colour-labels-next-slices.md` checklist, `markdown-feature-ideas.md`, `re-editor-performance-2026-07.md`, `calendar-perf-followups-2026-09.md`, `cloud-sync-roadmap.md` + its `cloud-sync-phase-*.md` implementation docs). Status headers say what shipped vs. what is planned. |

When a subsystem's behavior changes materially, update the matching `docs/` file and the relevant `COPILOT_CONTEXT.md` section in the same change — those files are the memory between sessions.

## Commands (PowerShell, Windows)

Run only what the change requires.

```powershell
dart analyze lib                                        # minimum bar for any Dart change
dart analyze packages/re_editor/lib                     # also, if the fork was touched
dart analyze packages/alarm/lib                         # also, if the alarm fork was touched
cd android && ./gradlew :alarm:testDebugUnitTest        # the alarm fork's own Kotlin tests, after any Kotlin change there
flutter gen-l10n                                        # after any lib/l10n/*.arb edit; then check untranslated.txt
dart run build_runner build --delete-conflicting-outputs # after Drift table/DAO/migration/annotation changes
flutter run                                             # Android is the primary target
flutter run -d windows                                  # quick desktop UI check (needs the VS "C++ ATL" component, below)
./tool/qa/qa <verb>                                     # drive a simulator, the desktop build or the emulator (see the qa-emulator skill; tool\qa\qa.cmd on Windows)
```

`flutter run -d windows` / `flutter build windows` need the Visual Studio
component **C++ ATL for latest v145 build tools (x86 & x64)**
(`Microsoft.VisualStudio.Component.VC.ATL`), installed once on this machine:
`flutter_local_notifications_windows` is an FFI plugin that CMake compiles
whatever the Dart side does, and its `plugin.cpp` includes `atlbase.h`.

Tests (`test/` — the money-ledger grammar suite, the database suite, and the sync bloc suite):

```powershell
flutter test                                            # whole suite (benchmarks skipped)
flutter test test/utils/markdown_money_syntax_test.dart # single file
flutter test test/utils/markdown_money_syntax_test.dart --plain-name "substring of test name"
flutter test --tags benchmark --run-skipped             # seeded-volume DB timings
```

`test/database/` guards SQLite behaviour deterministically — query plans (index
usage), statement counts (no query-in-a-loop), create-vs-migrate schema
parity, and the whole upgrade chain from the oldest schema
(`upgrade_chain_test.dart`). It runs against `NativeDatabase.memory()`, needs no setup, and asserts
no wall-clock times; see the `drift-migrations` skill for why.

Release pipeline — one Dart tool with the same verbs on every OS
(`tool\release\release.cmd` on Windows, `./tool/release/release` on macOS/Linux):

```powershell
tool\release\release.cmd build --arm64   # build_runner + gen-l10n + obfuscated release APK -> build\app\outputs\flutter-apk\
tool\release\release.cmd install         # same, built for the attached phone's ABI, then adb install (-d <serial> if several)
tool\release\release.cmd doctor          # signing keystore, Firebase config, adb + device, stale Gradle daemons
tool\release\release.cmd gen [--watch]   # build_runner (+ gen-l10n)
tool\release\release.cmd clean           # flutter clean + .dart_tool + pub get; `build --clean` for a one-off cold build
```

Builds are incremental by default (warm Gradle daemon; add `--clean` for a cold
one). A release build is **refused** when `android/key.properties` and
`android/app/release-keystore.jks` are missing — both are gitignored, so copy
them from the machine that has them, at the same relative paths. A
debug-signed APK cannot install over the release-signed app, and the guard
lives in Gradle's `preReleaseBuild` too, so a bare `flutter build apk --release`
is refused as well (`--allow-debug-signing` / `-PantaAllowDebugSigning=true`
for a throwaway build).

Do not run `flutter analyze` on the whole workspace — platform shells add noise. `dart analyze lib` is the convention (add `tool test_driver` when the QA harness changed).

The QA device harness (`./tool/qa/qa <verb>` on macOS/Linux, `tool\qa\qa.cmd` on Windows) drives the iOS simulator, the macOS desktop build and the Android emulator from the command line against an isolated QA database — load the `qa-emulator` skill for a device pass; never drive `adb` or `xcrun simctl` by hand.

## Architecture

Never bypass a layer:

```
Page/Widget -> BLoC -> Service -> Repository -> DAO -> Drift (SQLite)
```

- **BLoCs** (`lib/bloc/`) stay thin: route events, hold loading/error state, delegate to services. Sealed + `Equatable` where that is the local pattern.
- **Services** (`lib/services/`) own workflows — note/folder storage, auto-save, counters, settings, backup, import/export, calendar events, search indexing, markdown rendering, database switching.
- **Repositories** (`lib/repositories/`) cache/stream over DAOs — invalidate after create/update/delete/move/reorder.
- **DAOs** (`lib/database/daos/`) own all SQL, transactions, soft deletes, FTS, migrations.
- **DI** is `get_it`, configured in `lib/core/di/injection.dart`; `main.dart` calls `configureDependencies()` then registers app-wide BLoCs.
- **Constants** live in `lib/constants/` (spacing, text styles, icon sizes, colors, JSON keys, settings keys) — never magic values.
- **`packages/re_editor/`** is a local, perf-tuned fork of the editor, **owned** since the Session 7a upstream sync (2026-09-04): its API is whatever the app needs, so add, rename or remove fork members when a feature calls for it, and treat it as part of the workspace for bug/perf fixes. Upstream is watched, not tracked (last evaluated commit `28d9fc0`; cherry-picks are one-off decisions recorded in `docs/re-editor-performance-2026-07.md`). Preserve the optimizations listed in COPILOT_CONTEXT.md ("Generated And Local Package Notes").
- **`packages/alarm/`** is a local fork of the `alarm` plugin (base 5.13.2, forked 2026-09-22 in event-alerts session OS-1) on the same rule: owned, upstream watched, cherry-picks recorded in `docs/event-alerts-os-integration-roadmap.md`. It carries two Kotlin patches and nothing else — `AlarmScheduler.setExactAlarm` arms with `AlarmManager.setAlarmClock` (the phone treats an ANTA alarm as an alarm: Doze-exempt, status-bar icon, lock-screen line, a show intent opening the Alerts hub) and `AudioService.playAudio` plays a `content://` sound directly, falling back to the phone's default when the device cannot open it. The Pigeon-generated bindings are untouched; the fork's Kotlin tests run through `cd android && ./gradlew :alarm:testDebugUnitTest`. Only the Alarm tier reaches this plugin — the Reminder tier stays on `flutter_local_notifications`.

The two pages that carry most of the app are [optimized_folder_content_page.dart](lib/pages/optimized_folder_content_page.dart) (browser) and [optimized_note_editor_page.dart](lib/pages/optimized_note_editor_page.dart) (editor: re_editor + toolbar + preview/split + auto-save + search).

### Markdown engine

The custom markdown engine is the most intricate part of the codebase and has two independent rendering surfaces that must agree:

- **Preview**: `MarkdownPreviewBloc` → `MarkdownRenderService` → `LineBasedMarkdownBuilder` → `MarkdownChunker` (block-aligned chunking) → rendered by `SourceMappedMarkdownView`.
- **Live editor**: `MarkdownEditorSpanBuilder` + `MarkdownEditorLineIndex` (incremental per-line passes), rendering Obsidian-style with the caret line revealing raw markers.

Every syntax has exactly one grammar module in `lib/utils/` that **both** surfaces consume — `markdown_inline_grammar.dart` (emphasis, strikethrough, highlight, inline code, escapes, and the placement of every other inline construct — the wrapper's tap zones resolve through it too), `markdown_list_syntax.dart`, `markdown_money_syntax.dart`, `markdown_color_syntax.dart`, `markdown_callout_syntax.dart`, `markdown_tag_syntax.dart`, `markdown_link_patterns.dart`, `ghost_text.dart`, and `markdown_line_shape.dart` for line shapes (headings, horizontal rules, line-led constructs). Never add a second regex or scanner for an existing construct; extend the grammar module. Editor rendering **conceals** markers (transparent, ~0 width) or substitutes them 1:1 — never adds or drops code units, or caret/search offsets desync.

Read the `markdown-engine` skill and the corresponding COPILOT_CONTEXT.md sections before touching any of this.

## Non-negotiable rules

- Every user-visible string goes through `AppLocalizations`. Update `lib/l10n/app_en.arb`, `app_de.arb`, `app_ro.arb` **together**, then run `flutter gen-l10n`.
- Never hand-edit generated files (`lib/database/database.g.dart`, `lib/database/daos/*.g.dart`, `lib/l10n/app_localizations*.dart`).
- Drift schema changes need a migration; never reset user storage. Any DB-backed singleton must follow the `DatabaseLifecycle` reset contract (multi-database switching).
- **No code comments, no new markdown docs unless explicitly requested.** Tests are welcome (standing permission, 2026-08-16): new services and blocs ship with focused suites against fakes — see `test/bloc/sync_bloc_test.dart` for the pattern.
- Preserve data semantics: soft deletes, CRDT fields (`hlcTimestamp`, `deviceId`, `version`, `isDeleted`), positions, sort preferences, pinned counters, backup format compatibility. Global counter values use `noteId == ''`.
- Settings go through `SettingsService` + `SettingsKeys` — never raw `SharedPreferences` keys.
- Import/export: UI only via `ImportExportBloc`; exports funnel through `shareExport` (never `SharePlus` directly); `createX` stamps timestamps to now, `importX` preserves caller timestamps; bumping the archive schema means bumping `ImportExportService.archiveVersion` and accepting the previous version.
- Material 3, compact, touch-friendly, stable layouts; light/dark/system themes; locales en/de/ro.
- No new state-management, persistence, or navigation patterns without a strong reason.

## Ask vs. act

Act without asking when the request is concrete and matches existing patterns. Ask only when a change would break persisted-data backward compatibility, change backup format semantics, or introduce a new architectural pattern.
