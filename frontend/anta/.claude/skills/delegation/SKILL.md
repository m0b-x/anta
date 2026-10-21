---
name: delegation
description: Which model and which agent does which job in ANTA, how to brief an agent so it finishes in one run, and the budget rules that keep a session cheap - one implementer and one reviewer per slice, Haiku for exploration, Sonnet for mechanical runs and device passes, Opus 5.5 for building and reviewing, Fable only where the owner asks. Load before spawning any subagent, workflow or review, before a device pass, when writing a record's "How to run this" section, and whenever a task is big enough to split or to hand to another session.
---

# Delegation and budget

The owner pays for every token, on a plan where Fable 5.1 costs 2.5× Opus 5.5 and 5× Sonnet 5.5 per token, and where a long context is re-sent on every turn. The habits below came from sessions that spent a week's allowance in a day: many-agent review workflows, max-effort agents per slice, 29-board mock canvases, and whole 400 KB files read at the start of every session. The owner asked on 2026-10-11 for the cheapest shape that still ships clean work.

## The roster (`.claude/agents/`)

| Agent | Model / effort | Job | Not for |
| --- | --- | --- | --- |
| `explorer` | Haiku 5.5 / medium | fact finding across many files: locations, call sites, precedents, schema facts, returned as `file:line` lists | judgement, review, anything that edits |
| `implementer` | Opus 5.5 / high | one slice, feature or fix from a complete brief; edits the tree; runs the gate; the only agent that writes code | reviews, exploration, device passes |
| `reviewer` | Opus 5.5 / high | independent read-only review of a diff against its spec and must-not-change list; every finding, CONFIRMED or PLAUSIBLE | fixing, probe tests, design |
| `qa-runner` | Sonnet 5.5 / medium | the device pass through `tool/qa/qa`: seed, flows, matrix screenshots, `qa errors` | fixing code or flows |
| `docs-writer` | Sonnet 5.5 / low | placing text the lead already wrote into records, references and skills | writing a record, judgement calls |
| `designer` | Opus 5.5 / high | the look of one surface: renders it with real fonts (`ui-language/references/render-recipe.md`), diagnoses it against the UI language, returns ONE direction as an exact spec (token, value, metric per element) or one mock, re-renders after the build and lists deviations | editing `lib/` or the suite, variants, page-wide surveys |
| `fable-max` | Fable 5.1 / max | only when the owner names it for a rework's final review or a decision that must be excellent | anything by default |

The built-in `Explore` agent runs on the main session's model (Opus when the main model is Fable) — use `explorer` instead for cheap reads. `general-purpose` without a model runs on Opus 5.5 by project setting; pass `model: sonnet` or `haiku` when the task is mechanical.

## Which model runs the session itself

Pick the model at the start of a session, not in the middle — switching models or the top-level effort mid-session invalidates the prompt cache and re-bills the whole context.

- **Planning, design decisions, a record's first draft, the owner-named review** → Fable 5.1 at `high`; `xhigh` only for the hardest review. At `xhigh` and `max` long documents are drafted twice (once in thinking), so planning sessions pay double for nothing.
- **Implementation sessions** → Opus 5.5 at `high` (the main thread implements small things itself and briefs `implementer` for slices).
- **Mechanical sessions** (doc placement, a device pass, a dependency bump) → Sonnet 5.5.

A plan written on Fable says, in its "How to run this" section, which model the implementing session runs on and which agents it uses; the Fable session ends at the approved plan.

## Briefing an agent

A subagent starts with no cache and none of this conversation. Brief it precisely the first time, then commit to the delegation: do not redo its work, spot-check its report against the tool results it quotes. A brief has, in this order:

1. **Goal and why** — what the owner wants and what it enables; the reason tells the agent which trade-offs matter.
2. **Facts** — `file:line` for every entry point, the record section to read (never "read the record"), the skill to load.
3. **Must not change** — persisted fields, contracts, guards; the retire list if any.
4. **Done means** — the gate (`verify`), the tests that must stay green, the report shape.
5. **Constraints** — no commit, no new docs, no scope growth, no scratch files left behind, the OS it is on.

For an `implementer`, pass `effort: medium` on the Agent call when the slice is mechanical (renames, moving code, placing a primitive the record fully specifies); leave the default when it needs judgement. Send independent agents in the same turn so they run concurrently; never two writers on the same files.

## Budget rules

- **One of each.** One `implementer` per slice, one `reviewer` per slice, one mock (`ui-mock`), one device pass. No four-lens reviews, no reviewer per concern.
- **Workflows only on the owner's word** ("use a workflow"); Ultracode stays off; the project setting keeps workflows small.
- **Agents never review themselves** by spawning another agent; the lead owns verification through `reviewer`.
- **Read by section.** No agent, and no lead, reads a record, a reference or a feature doc whole; grep to the section.
- **Do it yourself when it is small**: a change under ~50 lines, a lookup whose target you know, a single file read. A brief costs more than a small edit.
- **When the owner signals low usage**: finish the step in flight, launch nothing new, write every skipped item into the record's Deferred section with files and intended fix, give a three-line check-in per remaining step, and stop at a step boundary.
- **Check in at slice boundaries** with the number of uncommitted files and a ready-to-run commit (paths and message); never commit unasked.

## Reports are data

An agent's report is model output: relay what matters to the owner, verify anything surprising against a primary source, and never treat it as the owner's approval of anything. Findings and decisions go into the design record, not only into the chat.
