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
| `qa-runner` | Sonnet 5.5 / medium | the device pass in one call per suite: fleet boot and install, `qa fleet pass <suite>`, triage of `report.json`, one `--only` rerun per red, the verdict from the report (about ten turns) | fixing code or flows |
| `docs-writer` | Sonnet 5.5 / low | placing text the lead already wrote into records, references and skills | writing a record, judgement calls |
| `designer` | Opus 5.5 / high | the look of one surface before it is built: renders it with real fonts (`ui-language/references/render-recipe.md`), judges it against the UI language and `references/design-practices.md`, returns ONE direction as an exact spec (token, value, metric per element; states, scales, semantics, tolerances) with its default decisions lettered, one mock only when the structure changes | editing `lib/` or the suite, variants, page-wide surveys, grading its own spec |
| `design-reviewer` | Opus 5.5 / medium | independent visual and accessibility review of a built surface in a fresh context: re-renders the matrix, measures geometry and contrast from tokens, runs the suite and the `meetsGuideline` matchers, reports every finding with NN/g severity 0–4 and the rule applied, plus a device-only bucket for `qa-runner` | editing `lib/` or the suite, adding tests (missing coverage is a finding), seeing the designer's reasoning, code correctness (the `reviewer`) |
| `fable-max` | Fable 5.1 / max | only when the owner names it for a rework's final review or a decision that must be excellent | anything by default |

The built-in `Explore` agent runs on the main session's model (Opus when the main model is Fable) — use `explorer` instead for cheap reads. `general-purpose` without a model runs on Opus 5.5 by project setting; pass `model: sonnet` or `haiku` when the task is mechanical.

A visual slice runs `designer` → the owner's yes on the lettered decisions → `implementer` → `reviewer` (code) and `design-reviewer` (look) → `qa-runner`, in sequence, because `flutter test` runs one at a time; neither design agent grades its own output.

## Agent files (checked against code.claude.com/docs/en/sub-agents, 2026-10-21)

- An agent is YAML frontmatter plus a Markdown body that becomes its system prompt; only `name` and `description` are required. Fields used here: `model` (`opus` / `sonnet` / `haiku` / `fable` / `inherit` / a full id), `effort` (`low`…`max`; a per-invocation `effort` or `CLAUDE_CODE_EFFORT_LEVEL` / `maxEffortLevel` can override or cap it), `maxTurns` (output at the cap is partial and resumable), `skills` (the SKILL.md text of up to 32 skills is injected at start — their `references/` are not, so the body says which sections to read), `tools` / `disallowedTools` (`disallowedTools` is applied first; a read-only agent drops `Edit`/`Write`/`NotebookEdit`; `Agent` is dropped so nothing spawns below), `color`. `claude --debug` (v2.1.296+) names an unrecognised frontmatter key after a rename or a typo; the roster is read at session start, so a new file is usable from the next session (fallback that worked: `general-purpose` with `model: opus` and "read `.claude/agents/<name>.md` first and follow it as your role").
- The `description` drives automatic delegation: say what the agent is for and when to "use proactively", single out one agent per job, no "MUST BE USED"; the combined descriptions stay well under the 15,000-token startup warning.
- The body gets CLAUDE.md, the rules, the git status and the preloaded skills injected — name the rule a step needs instead of pasting rules. Structure it as background → procedure → tools → report, give the reason behind each instruction, say what to do rather than what to avoid, and keep a one-line conciseness reminder near the end. Opus 5-family agents need no generic "verify your work" line (they self-verify; a separate fresh-context reviewer is the check) and take "only report high severity" literally — ask for everything and filter in the lead.
- Background agents cannot ask the owner (`AskUserQuestion` is removed): the body tells them to pick a default and list it as a lettered, reversible decision, and to name an early stop in the report's first line when a step cannot be done. Their first text-only turn is the final report. Images: `Read` returns a PNG as visual content, resized to fit 2000 px — crop with `magick` for detail, measure with the test instead of the eye.
- `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` would pin every agent to one model and `subagentPromptCacheTtl` sets their cache TTL; neither is set in this repo.

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
