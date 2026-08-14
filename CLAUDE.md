# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo contains a single Flutter app, **ANTA** — an offline-first personal tracker (folders, markdown notes, a money ledger, counters, calendar). There is no backend; the `frontend/` nesting exists to leave room for one.

The Dart package is named `anta`; the app id is `com.alexzamfir.anta`. The directory is still `frontend/gym_notes_track_app/` and the on-disk database directory is still `gym_notes` — both are load-bearing paths, not branding. Never rename the `gym_notes` data directory: it is where every existing install's databases and `device_id` live.

**All work happens in [frontend/gym_notes_track_app/](frontend/gym_notes_track_app/).** Start there:

- [frontend/gym_notes_track_app/CLAUDE.md](frontend/gym_notes_track_app/CLAUDE.md) — commands, architecture, non-negotiable rules.
- [frontend/gym_notes_track_app/COPILOT_CONTEXT.md](frontend/gym_notes_track_app/COPILOT_CONTEXT.md) — canonical per-subsystem context.
- [frontend/gym_notes_track_app/.claude/skills/](frontend/gym_notes_track_app/.claude/skills/) — task-scoped skills (`gym-notes-context` first, then the area-specific ones).

Run every command from `frontend/gym_notes_track_app`, not from the repo root.
