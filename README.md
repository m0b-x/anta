# Gym Notes

An offline-first Flutter app for tracking gym progress through folders, markdown notes, counters, and a calendar. It is a **training log first**, a generic notes app second — everything is tuned for fast, reliable capture during or right after a workout.

Local-only by design: all data lives in a local SQLite database with versioned backup/restore and import/export. Nothing leaves the device unless you share it.

## Features

- **Folders & notes** — nested folders for programs, weeks, or muscle groups; markdown notes for sessions, templates, and measurements. Pagination, sorting, manual reordering, swipe actions, move history.
- **Live markdown editor** — Obsidian-style rendering as you type (the caret line reveals raw markers), plus a separate preview/split mode. Built on a local performance-tuned fork of `re_editor` with a custom line-based renderer.
- **Markdown extensions built for a training log** — checkbox/task lists, callouts, `#tags`, ghost-text `{{ fill-in }}` placeholders for templates, named text/highlight colors, and a **money ledger** (`$+ 12.50 protein` style lines that fold into a running balance derived purely from note content).
- **Configurable toolbar** — custom markdown shortcuts with profiles, per-note toolbar assignment, and shortcuts that can bump counters as they insert text.
- **Counters** — global and per-note numeric counters with pinning and manual ordering, for reps, bodyweight, PRs, or anything repeated.
- **Calendar & events** — custom event categories, recurrence rules, public-holiday profiles, day bars and day summaries, note↔event links.
- **Search** — across notes (SQLite FTS + an app-level index) and within the active note, with regex and whole-word options.
- **Data ownership** — multi-database switching, JSON backup/restore, per-note and per-folder share/import as files or `.zip` archives, and CRDT metadata on records for future sync.
- **Localized** in English, German, and Romanian; Material 3 with light/dark/system themes.

## Repository layout

```
frontend/gym_notes_track_app/   the Flutter app (all development happens here)
```

There is no backend — the `frontend/` nesting exists to leave room for one.

## Getting started

Requires the Flutter SDK (Dart SDK `^3.10.4`). Android is the primary target; Windows desktop works for quick UI checks.

```bash
cd frontend/gym_notes_track_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate Drift code
flutter gen-l10n                                            # generate localizations
flutter run
```

See [frontend/gym_notes_track_app/README.md](frontend/gym_notes_track_app/README.md) for the full command reference, and [frontend/gym_notes_track_app/CLAUDE.md](frontend/gym_notes_track_app/CLAUDE.md) for architecture and contribution rules.

## Tech stack

Flutter · Material 3 · `flutter_bloc` · Drift (SQLite) · `get_it` · `table_calendar` · a local `re_editor` fork · Flutter `gen-l10n`
