# Copilot instructions

This repository is maintained with Claude Code; its rules live in one place so no tool reads a stale copy.

- Read [CLAUDE.md](../CLAUDE.md) first: what the app is, the architecture flow, the non-negotiable rules, the commands per OS.
- The per-area rules and facts are the skills under [.claude/skills/](../.claude/skills/) — each `SKILL.md` is the rulebook, its `references/` the facts. Read the one for the area you touch.
- Design records and roadmaps are in [docs/](../docs/).

Everything runs from `frontend/anta`. Never bypass `Page → BLoC → Service → Repository → DAO → Drift`; every user-visible string goes through `AppLocalizations` in all three ARB files; never hand-edit generated files; Drift schema changes need a migration.
