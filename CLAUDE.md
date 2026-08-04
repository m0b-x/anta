# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo contains a single Flutter app, **Gym Notes** — an offline-first training log (folders, markdown notes, counters, calendar). There is no backend; the `frontend/` nesting exists to leave room for one.

**All work happens in [frontend/gym_notes_track_app/](frontend/gym_notes_track_app/).** Start there:

- [frontend/gym_notes_track_app/CLAUDE.md](frontend/gym_notes_track_app/CLAUDE.md) — commands, architecture, non-negotiable rules.
- [frontend/gym_notes_track_app/COPILOT_CONTEXT.md](frontend/gym_notes_track_app/COPILOT_CONTEXT.md) — canonical per-subsystem context.
- [frontend/gym_notes_track_app/.claude/skills/](frontend/gym_notes_track_app/.claude/skills/) — task-scoped skills (`gym-notes-context` first, then the area-specific ones).

Run every command from `frontend/gym_notes_track_app`, not from the repo root.
