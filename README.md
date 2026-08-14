# ANTA

An offline-first Flutter app for tracking the things you keep coming back to — training sessions, spending, appointments, and the notes around them. Folders and markdown notes are the substrate; a money ledger, a calendar with real recurrence, and numeric counters are built on top of them.

Local-only by design: all data lives in a local SQLite database with versioned backup/restore and import/export. Nothing leaves the device unless you share it.

It started as a training log, and that origin still sets the bar: capture has to be fast and reliable in the middle of something else — no lost text, no layout shifts, minimal taps. When two designs are otherwise equal, the one that survives one-handed use wins.

## Features

- **Folders & notes** — nested folders for any hierarchy you like; markdown notes for sessions, templates, records, and measurements. Pagination, sorting, manual reordering, swipe actions, move history.
- **Live markdown editor** — Obsidian-style rendering as you type (the caret line reveals raw markers), plus a separate preview/split mode. Built on a local performance-tuned fork of `re_editor` with a custom line-based renderer.
- **Money ledger** — `$+ 12.50 protein` style lines that fold into a running balance derived purely from note content, with value-colour overrides, entry diffs, net-worth rows, and budget targets. No separate finance screen to keep in sync.
- **Markdown extensions** — checkbox/task lists, callouts, `#tags`, ghost-text `{{ fill-in }}` placeholders for templates, and named text/highlight colors.
- **Configurable toolbar** — custom markdown shortcuts with profiles, per-note toolbar assignment, and shortcuts that can bump counters as they insert text.
- **Counters** — global and per-note numeric counters with pinning and manual ordering, for reps, bodyweight, PRs, or anything repeated.
- **Calendar & events** — custom event categories, recurrence rules, computed public holidays and religious fasting calendars, day bars and day summaries, markdown event descriptions, note↔event links.
- **Search** — across notes (SQLite FTS + an app-level index) and within the active note, with regex and whole-word options.
- **Data ownership** — multi-database switching, JSON backup/restore, per-note and per-folder share/import as files or `.zip` archives, and CRDT metadata on records for future sync.
- **Localized** in English, German, and Romanian; Material 3 with light/dark/system themes.

## Repository layout

```
frontend/anta/   the Flutter app (all development happens here)
```

There is no backend — the `frontend/` nesting exists to leave room for one.

## Getting started

Requires the Flutter SDK (Dart SDK `^3.10.4`). Android is the primary target; Windows desktop works for quick UI checks.

```bash
cd frontend/anta
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate Drift code
flutter gen-l10n                                            # generate localizations
flutter run
```

See [frontend/anta/README.md](frontend/anta/README.md) for the full command reference, and [frontend/anta/CLAUDE.md](frontend/anta/CLAUDE.md) for architecture and contribution rules.

## Tech stack

Flutter · Material 3 · `flutter_bloc` · Drift (SQLite) · `get_it` · `table_calendar` · a local `re_editor` fork · Flutter `gen-l10n`
