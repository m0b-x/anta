# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo contains a single Flutter app, **ANTA** — an offline-first personal tracker (folders, markdown notes, a money ledger, counters, calendar). There is no backend; the `frontend/` nesting exists to leave room for one.

The Dart package is named `anta`; the app id is `com.alexzamfir.anta`. The on-disk database directory is still `gym_notes` — a load-bearing runtime path, not branding. Never rename it: it is where every existing install's databases and `device_id` live.

**All work happens in [frontend/anta/](frontend/anta/).** Start there:

- [frontend/anta/CLAUDE.md](frontend/anta/CLAUDE.md) — commands, architecture, non-negotiable rules.
- [frontend/anta/COPILOT_CONTEXT.md](frontend/anta/COPILOT_CONTEXT.md) — canonical per-subsystem context.
- [frontend/anta/.claude/skills/](frontend/anta/.claude/skills/) — task-scoped skills (`anta-context` first, then the area-specific ones).

Run every command from `frontend/anta`, not from the repo root.
