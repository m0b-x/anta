# CLAUDE.md — ANTA

**ANTA** (Dart package `anta`, app id `com.alexzamfir.anta`) is an offline-first Flutter app for tracking the things you keep coming back to — training sessions, spending, appointments, and the notes around them. Folders and markdown notes are the substrate; the money ledger, the calendar and counters are built on top. It started as a training log, and that still sets the bar: capture must be fast and reliable in the middle of something else — no lost text, no layout shifts, minimal taps. When two designs are otherwise equal, pick the one that survives one-handed use.

Everything runs from `frontend/anta`. The on-disk `gym_notes` database directory is a load-bearing runtime path, not branding — never rename it.

## Which machine you are on

Read the `Platform` line of your environment before the first command; the app is developed on both machines and the same verbs exist on each.

- **`win32` — Windows 11.** PowerShell is the primary shell; the Bash tool is Git Bash. Wrappers: `tool\qa\qa.cmd`, `tool\release\release.cmd`. There is no `python`; never `perl -i` or `sed -i` — a `perl -i` once emptied an ARB; edit with Read/Edit/Write. Repo files are CRLF and Git Bash hides the `\r`: check with `tr -cd '\r' | wc -c` before any text surgery. `flutter run -d windows` needs the Visual Studio component "C++ ATL for latest v145 build tools". The Android emulator is `Pixel_9_Pro`; "Lost connection to device" means a degraded quick-boot snapshot — boot cold.
- **`darwin` — macOS.** zsh; wrappers `./tool/qa/qa`, `./tool/release/release`; `flutter run -d macos` and the iOS simulator are available. Release signing files (`android/key.properties`, `android/app/release-keystore.jks`) are gitignored and must be copied over from the machine that has them.

Android is the primary target; desktop builds are quick UI checks.

## Architecture — never bypass a layer

```
Page/Widget -> BLoC -> Service -> Repository -> DAO -> Drift (SQLite)
```

- BLoCs (`lib/bloc/`) stay thin: route events, hold loading/error state, delegate to services; sealed + `Equatable` where that is the local pattern.
- Services (`lib/services/`) own workflows; repositories (`lib/repositories/`) cache/stream over DAOs and invalidate after every write; DAOs (`lib/database/daos/`) own SQL, transactions, soft deletes, FTS and migrations.
- DI is `get_it` in `lib/core/di/injection.dart`. Constants live in `lib/constants/` — never magic values; a surface on the UI language reads `FormMetrics` / `RowMetrics` / `AppBarMetrics`, not the generic `AppSpacing` scale.
- `packages/re_editor/` and `packages/alarm/` are owned forks (upstream watched, not tracked); their rules load when you touch them.
- The two pages that carry the app: `lib/pages/optimized_folder_content_page.dart` (browser) and `optimized_note_editor_page.dart` (editor).

## Non-negotiable rules

- Every user-visible string goes through `AppLocalizations`: `app_en.arb`, `app_de.arb`, `app_ro.arb` together, then `flutter gen-l10n`, `untranslated.txt` empty.
- Never hand-edit generated files (`*.g.dart`, `app_localizations*.dart`).
- Drift schema changes need a migration; never reset user storage; DB-backed singletons follow the `DatabaseLifecycle` reset contract.
- Preserve data semantics: soft deletes, CRDT fields (`hlcTimestamp`, `deviceId`, `version`, `isDeleted`), positions, sort preferences, pinned counters, backup compatibility; global counter values use `noteId == ''`.
- Settings go through `SettingsService` + `SettingsKeys`, never raw `SharedPreferences` keys.
- Import/export UI only via `ImportExportBloc`; exports through `shareExport` (never `SharePlus` directly); `createX` stamps now, `importX` preserves; an archive version bump accepts the previous version.
- Comments carry the why, never the what: `///` on public members and on decisions a reader could not reconstruct; never narration, never a TODO left behind. No new markdown docs unless requested (a rework's design record counts as requested). Tests are welcome: new services, blocs and sheets ship with focused suites against fakes.
- Material 3, compact, touch-friendly, stable layouts; light/dark/system; en/de/ro.
- No new state-management, persistence or navigation patterns without a strong reason.
- Never commit unless the owner says so; then the gate first, then the commit, then report the hash. The owner commits to `main` — ask before creating a branch.

## Commands (from `frontend/anta`)

| Need | Run |
| --- | --- |
| Any Dart change | `dart analyze lib` (never `flutter analyze` on the whole workspace) |
| Tests | `flutter test` — the whole suite, one run at a time, never beside a QA `flutter run` |
| ARB edit | `flutter gen-l10n`, then check `untranslated.txt` |
| Drift change | `dart run build_runner build --delete-conflicting-outputs` |
| Run the app | `flutter run` (Android), `flutter run -d windows` / `-d macos` |
| Device pass | `qa <verb>` through the wrapper for your OS (`qa-emulator` skill) |
| Release | `release build --arm64` / `install` / `doctor` / `gen` / `clean` (`verify` skill) |

The gate for any change: analyze clean, whole suite green, gen-l10n when ARBs changed, must-not-change list re-read against the diff.

## How work runs here — the budget

- **Model per job.** Opus 5.5 is the workhorse: implementation sessions, the `implementer`, `reviewer`, `designer` and `design-reviewer` agents (the `designer` judges a surface from real-font renders and returns one exact visual spec before the build; the `design-reviewer` checks the built surface against it in a fresh context). Fable 5.1 is for design decisions, plans and the reviews the owner names. Sonnet 5.5 runs mechanical work (QA passes, doc placement); Sonnet or Haiku explores. The roster in `.claude/agents/` carries these; load the `delegation` skill before spawning anything.
- **Read by section, never whole.** Records, references and feature docs have tables of contents — grep to the section the task needs. No file over ~300 lines is read end to end unless the task is to rewrite it.
- **One of each.** One mock (`ui-mock`); one implementer and one reviewer per slice (`ui-revamp`); no workflow unless the owner says "use a workflow"; `fable-max` only when the owner names it.
- **Check in at boundaries.** At each slice boundary say how many files are uncommitted and offer a ready commit; when the owner signals low usage, finish the step, write what is left into the record's Deferred section, and stop.
- **Confirm before a large build.** When a request's visible behaviour can be read two ways, state your reading in one line and get a yes before dispatching more than a small change.

## Skills — rules in `SKILL.md`, facts in `references/`

| Working on | Load |
| --- | --- |
| Browser, counters, settings, backup, import/export, navigation, search, sync — any area without its own skill | `anta-context` |
| Calendar, events, alerts | `calendar-events` (+ `calendar-ui` and `ui-language` for visuals) |
| Editor, markdown, preview, the re_editor fork | `markdown-engine` |
| Schema, DAOs, migrations, backup compatibility | `drift-migrations` |
| Any user-visible string | `l10n` |
| Any sheet, page, row, menu, dialog | `ui-language`; `ui-mock` for a mock; `ui-revamp` for a rework |
| Running the app on a device | `qa-emulator` |
| Verifying, building, installing | `verify` |
| Dart/Flutter quality and performance | `flutter-principles` |
| Spawning agents, planning execution | `delegation` |

Path-scoped rules in `.claude/rules/` load themselves when you touch an area's files and name the skill to load. Read a skill's `references/` file only for the part the task needs.

## Docs

`docs/` holds design records and roadmaps; a status header says what shipped. The memory between sessions is the area skill's `references/` plus the docs — when a subsystem's behaviour changes materially, update both in the same change.

## Ask vs. act

Act without asking when the request is concrete and matches existing patterns. Ask only when a change would break persisted-data backward compatibility, change backup format semantics, or introduce a new architectural pattern.
