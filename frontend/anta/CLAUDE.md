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
| [docs/](docs/) | Feature references and roadmaps written per subsystem (`money-ledger-feature.md`, `live-markdown-editor-roadmap.md`, `calendar-events-feature.md`, `fasting-schedule-roadmap.md`, `presence-tracking-roadmap.md`, `calendar-cloud-readiness-roadmap.md`, `description-scope-roadmap.md`, `tag-system-roadmap.md`, `markdown-feature-ideas.md`, `re-editor-performance-2026-07.md`, `cloud-sync-roadmap.md` + its `cloud-sync-phase-*.md` implementation docs). Status headers say what shipped vs. what is planned. |

When a subsystem's behavior changes materially, update the matching `docs/` file and the relevant `COPILOT_CONTEXT.md` section in the same change — those files are the memory between sessions.

## Commands (PowerShell, Windows)

Run only what the change requires.

```powershell
dart analyze lib                                        # minimum bar for any Dart change
dart analyze packages/re_editor/lib                     # also, if the fork was touched
flutter gen-l10n                                        # after any lib/l10n/*.arb edit; then check untranslated.txt
dart run build_runner build --delete-conflicting-outputs # after Drift table/DAO/migration/annotation changes
flutter run                                             # Android is the primary target
flutter run -d windows                                  # quick desktop UI check
```

Tests (`test/` — the money-ledger grammar suite, the database suite, and the sync bloc suite):

```powershell
flutter test                                            # whole suite (benchmarks skipped)
flutter test test/utils/markdown_money_syntax_test.dart # single file
flutter test test/utils/markdown_money_syntax_test.dart --plain-name "substring of test name"
flutter test --tags benchmark --run-skipped             # seeded-volume DB timings
```

`test/database/` guards SQLite behaviour deterministically — query plans (index
usage), statement counts (no query-in-a-loop) and create-vs-migrate schema
parity. It runs against `NativeDatabase.memory()`, needs no setup, and asserts
no wall-clock times; see the `drift-migrations` skill for why.

Helper scripts (each wraps build_runner + gen-l10n + clean + build):

```powershell
.\generate_drift.bat            # or `generate_drift.bat watch`
.\build_release.bat arm64       # release APK -> build\app\outputs\flutter-apk\
.\install_to_device.bat arm64   # build + adb install
.\full_clean.bat                # when builds misbehave
```

Do not run `flutter analyze` on the whole workspace — platform shells add noise. `dart analyze lib` is the convention.

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
- **`packages/re_editor/`** is a local, perf-tuned fork of the editor. Treat it as part of the workspace for bug/perf fixes, but avoid API-breaking changes and preserve the optimizations listed in COPILOT_CONTEXT.md ("Generated And Local Package Notes").

The two pages that carry most of the app are [optimized_folder_content_page.dart](lib/pages/optimized_folder_content_page.dart) (browser) and [optimized_note_editor_page.dart](lib/pages/optimized_note_editor_page.dart) (editor: re_editor + toolbar + preview/split + auto-save + search).

### Markdown engine

The custom markdown engine is the most intricate part of the codebase and has two independent rendering surfaces that must agree:

- **Preview**: `MarkdownPreviewBloc` → `MarkdownRenderService` → `LineBasedMarkdownBuilder` → `MarkdownChunker` (block-aligned chunking) → rendered by `SourceMappedMarkdownView`.
- **Live editor**: `MarkdownEditorSpanBuilder` + `MarkdownEditorLineIndex` (incremental per-line passes), rendering Obsidian-style with the caret line revealing raw markers.

Every syntax has exactly one grammar module in `lib/utils/` that **both** surfaces consume — `markdown_list_syntax.dart`, `markdown_money_syntax.dart`, `markdown_color_syntax.dart`, `markdown_callout_syntax.dart`, `markdown_tag_syntax.dart`, `ghost_text.dart`. Never add a second regex for an existing construct; extend the grammar module. Editor rendering **conceals** markers (transparent, ~0 width) or substitutes them 1:1 — never adds or drops code units, or caret/search offsets desync.

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
