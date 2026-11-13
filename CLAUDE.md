# CLAUDE.md

This repo contains a single Flutter app, **ANTA** — an offline-first personal tracker (folders, markdown notes, a money ledger, counters, calendar). The app holds its own data; the one server-side piece is [backend/push-relay/](backend/push-relay/) — a Cloudflare Worker that turns "something a pair shares has changed" into a data message for the partner's phone. It stores nothing and reads no user data; its contract, tests and deploy steps are in `frontend/anta/docs/cloud-shared-freshness.md` §7–§9 (`node --test` from that directory).

The Dart package is named `anta`; the app id is `com.alexzamfir.anta`. The on-disk database directory is still `gym_notes` — a load-bearing runtime path, not branding. Never rename it: it is where every existing install's databases and `device_id` live.

**All work happens in [frontend/anta/](frontend/anta/).** Start there:

- [frontend/anta/CLAUDE.md](frontend/anta/CLAUDE.md) — the machine you are on, architecture, non-negotiable rules, commands, how work is budgeted, the skill map.
- [frontend/anta/.claude/rules/](frontend/anta/.claude/rules/) — path-scoped rules that load themselves when you touch an area's files.
- [frontend/anta/.claude/skills/](frontend/anta/.claude/skills/) — per-area skills: `SKILL.md` is the rulebook, `references/` the facts, read by section.
- [frontend/anta/.claude/agents/](frontend/anta/.claude/agents/) — the agent roster (explorer, implementer, reviewer, designer, design-reviewer, qa-runner, docs-writer, fable-max) and the `delegation` skill that says who does what.

Run every command from `frontend/anta`, not from the repo root.
