---
name: delegation
description: Which model and which agent does which job in ANTA, how to brief an agent so it finishes in one run, and the budget rules that keep a session cheap - Fable 5.2 at high effort leads and decides, Opus 5.5 agents build and review, Sonnet 5.5 runs only the mechanical jobs, Haiku 5.5 explores, one implementer and one reviewer per slice. Load before spawning any subagent, workflow or review, before a device pass, when writing a record's "How to run this" section, when the owner says an allowance is running low, and whenever a task is big enough to split or to hand to another session.
---

# Delegation and budget

The owner pays for every token, and a long context is re-sent on every turn. List prices per million tokens, input / output (2026-11): Fable 5.2 $8 / $40, Opus 5.5 $4 / $20, Sonnet 5.5 $2 / $10, Haiku 5.5 $0.10 / $0.50 — Fable costs twice Opus and four times Sonnet, and Haiku is forty times cheaper than Opus. Each model has its own allowance on the plan, so which one is short changes from week to week: on 2026-11-11 everything but Fable was nearly spent, the reverse of August. The habits below came from sessions that spent a week's allowance in a day — many-agent review workflows, max-effort agents per slice, 29-board mock canvases, whole 400 KB files read at the start of every session.

## The split (owner, 2026-11-11)

- **Fable 5.2 at `high` leads**: plans, design decisions, records, briefs, the synthesis of agent reports, and the edits too small to brief.
- **Opus 5.5 agents build and review**: `implementer`, `reviewer`, `designer`, `design-reviewer`.
- **Sonnet 5.5 runs only the jobs whose judgment lives in a procedure**: `qa-runner` (the harness's report decides) and `docs-writer` (the lead wrote the text).
- **Haiku 5.5 explores**: `explorer` returns `file:line` facts; the lead judges them.

## The roster (`.claude/agents/`)

| Agent | Model / effort | Job | Not for |
| --- | --- | --- | --- |
| `explorer` | Haiku 5.5 / medium | fact finding across many files: locations, call sites, precedents, schema facts, returned as `file:line` lists | judgement, review, anything that edits |
| `implementer` | Opus 5.5 / high | one slice, feature or fix from a complete brief; edits the tree; runs the gate; the only agent that writes code | reviews, exploration, device passes |
| `reviewer` | Opus 5.5 / high | independent read-only review of a diff against its spec and must-not-change list; every finding, CONFIRMED or PLAUSIBLE | fixing, probe tests, design |
| `qa-runner` | Sonnet 5.5 / medium | the device pass in one call per suite: fleet boot and install, `qa pass <suite>`, triage of `report.json`, one `--only` rerun per red, the verdict from the report (about ten turns) | fixing code or flows |
| `docs-writer` | Sonnet 5.5 / low | placing text the lead already wrote into records, references and skills | writing a record, judgement calls |
| `designer` | Opus 5.5 / high | the look of one surface before it is built: renders it with real fonts (`ui-language/references/render-recipe.md`), judges it against the UI language and `ui-language/references/design-practices.md`, returns ONE direction as an exact spec (token, value, metric per element; states, scales, semantics, tolerances) with its default decisions lettered, one mock only when the structure changes | editing `lib/` or the suite, variants, page-wide surveys, grading its own spec |
| `design-reviewer` | Opus 5.5 / medium | independent visual and accessibility review of a built surface in a fresh context: re-renders the matrix, measures geometry and contrast from tokens, runs the suite and the `meetsGuideline` matchers, reports every finding with NN/g severity 0–4 and the rule applied, plus a device-only bucket for `qa-runner` | editing `lib/` or the suite, adding tests (missing coverage is a finding), seeing the designer's reasoning, code correctness (the `reviewer`) |
| `fable-max` | Fable 5.2 / xhigh | only when the owner names it for a rework's final review or a decision that must be excellent | anything by default |

No roster agent can spawn agents (`Agent` is dropped in every file): fan-out is the lead's decision, and at `xhigh` Fable 5.2 otherwise starts subagents to check its own work.

The built-in `Explore` agent runs on Opus on a subscription whatever the session's model — use `explorer` for cheap reads. `general-purpose` without a model runs on Opus 5.5 by project setting; pass `model: sonnet` or `haiku` when the task is mechanical.

A visual slice runs `designer` → the owner's yes on the lettered decisions → `implementer` → `reviewer` (code) and `design-reviewer` (look) → `qa-runner`, in sequence, because `flutter test` runs one at a time; neither design agent grades its own output.

## Agent files (checked against code.claude.com/docs/en/sub-agents, 2026-11-11)

- An agent is YAML frontmatter plus a Markdown body that becomes its system prompt; only `name` and `description` are required, and an unrecognised key is ignored silently (`claude --debug` names it). Fields used here: `model` (`opus` / `sonnet` / `haiku` / `fable` / `inherit` / a full id), `effort` (`low`…`max`), `maxTurns` (output at the cap is partial and resumable), `skills` (the SKILL.md text of up to 32 skills is injected at start — their `references/` are not, so the body says which sections to read), `tools` / `disallowedTools` (`disallowedTools` is applied first), `color`. Available and unused: `isolation: worktree`, `omitClaudeMd`, `autoCompactWindow`, `memory`, `background`, `permissionMode`.
- **Which model an agent gets**: the Agent call's `model` (aliases only: `fable`, `opus`, `sonnet`, `haiku`), then the file's `model`, then `CLAUDE_CODE_SUBAGENT_MODEL` (`opus` in this repo's settings — the default for an agent that names none), then the session's model. The call's `effort` overrides the file's and stays on a resumed agent; `CLAUDE_CODE_EFFORT_LEVEL` beats both.
- The roster is read at session start, so a new or edited file is usable from the next session (fallback that worked: `general-purpose` with `model: opus` and "read `.claude/agents/<name>.md` first and follow it as your role").
- The `description` drives automatic delegation: say what the agent is for and when to "use proactively", single out one agent per job; the combined descriptions stay well under the 15,000-token startup warning.
- The body gets CLAUDE.md, the rules, the git status and the preloaded skills injected — name the rule a step needs instead of pasting rules. Structure it as background → procedure → tools → report and give the reason behind each instruction. An agent takes "only report high severity" literally — ask for everything and filter in the lead.
- Agents run in the background and cannot ask the owner: the body tells them to pick a default and list it as a lettered, reversible decision, and to name an early stop in the report's first line. Their first text-only turn is the final report. A finished or capped agent keeps its context: continue it with `SendMessage` instead of spawning a fresh one. Images: `Read` returns a PNG as visual content, resized to fit 2000 px — crop with `magick` for detail, measure with the test instead of the eye.
- `isolation: worktree` branches from the default branch, not from the session's uncommitted tree: an agent that must see uncommitted work gets a worktree the lead cut by hand (on Windows a short path such as `%TEMP%\anta-wt-<id>`, with the gitignored `firebase_options.dart` copied in).

## Which model runs the session itself

Pick the model at the start of a session, not in the middle — switching models or the top-level effort mid-session invalidates the prompt cache and re-bills the whole context.

- **Planning, design decisions, a record's first draft, the owner-named review** → Fable 5.2 at `high`. Claude Code's own default for Fable 5.2 is `medium`; the owner's user settings pin `high`. `xhigh` only where a gain was seen on that kind of task, never `max`: above `high` the gains are uneven and long documents are drafted twice, once in thinking.
- **Implementation with decisions still open** → the same Fable session leads and briefs one `implementer` per slice. The lead stays thin: it writes briefs, reads reports, runs the whole-suite gate and makes the small edits itself; it never re-reads what an agent already read.
- **Implementation of an approved plan with nothing left to decide** → an Opus 5.5 session at `high` builds it directly; the same work at half the lead's price. The plan's "How to run this" section names which of the two shapes it expects, and which agents.
- **Mechanical sessions** (doc placement, a device pass, a dependency bump) → Sonnet 5.5.

Not configured, the owner's call: the advisor (`/advisor fable` on an Opus session) lets Opus consult Fable at decision points. It is experimental, every consult re-reads the whole transcript uncached at Fable's rate, and agents inherit it.

## When an allowance runs out

A model's usage limit is not an outage: no fallback fires, and an agent on the exhausted model simply fails. When the owner mentions usage, ask which allowance is short, then:

- **Opus short** → the Fable lead builds the slice itself at `high` rather than briefing a Fable agent (an agent re-reads the context cold at twice the price); an independent review, when the slice needs one, is `reviewer` with `model: fable`. Mechanical work stays on Sonnet and Haiku.
- **Fable short** → an Opus 5.5 session plans and builds; `xhigh` for the plan only.
- **Sonnet or Haiku short** → the lead does the lookup or the placement itself; a device pass waits or runs with `model: opus`.
- **Everything short** → finish the step in flight, launch nothing new, write every skipped item into the record's Deferred section with files and intended fix, give a three-line check-in per remaining step, and stop at a step boundary.

## Briefing an agent

A subagent starts with no cache and none of this conversation. Brief it precisely the first time, then commit to the delegation: do not redo its work, spot-check its report against the tool results it quotes. A brief has, in this order:

1. **Goal and why** — what the owner wants and what it enables; the reason tells the agent which trade-offs matter.
2. **Facts** — `file:line` for every entry point, the record section to read (never "read the record"), the skill to load.
3. **Must not change** — persisted fields, contracts, guards; the retire list if any.
4. **Done means** — the gate (`verify`), the tests that must stay green, the report shape.
5. **Constraints** — no commit, no new docs, no scope growth, no scratch files left behind, the OS it is on.

Size a brief to the turn cap, which tracks how many files an item opens, not how many items there are:

- An `implementer` (150 turns) takes five to eight items whose files overlap; an item that opens a new cross-layer seam (a DAO signature rippling into tests, a restore cascade) is a run of its own.
- A `reviewer` (80 turns) takes three or four items; two reviewers with four items beat one with eight.
- In a fix pass of several runs the lead keeps the whole-suite gate — once, in the foreground — and each brief says "run only the suites your diff touches".
- A capped agent is not lost: check `git status`, then `SendMessage` "report now from what you have", then "continue with X only".

Pass `effort: medium` on the Agent call when the slice is mechanical (renames, moving code, placing a primitive the record fully specifies) — it is Opus 5.5's own default; leave `high` when the slice needs judgement (a migration, concurrency, a new seam).

Send independent read-only agents in the same turn so they run concurrently. Two writers run in parallel only on disjoint files and each in its own worktree — two `flutter test` runs in one tree collide on the native-assets lock; otherwise slices run in sequence.

## Budget rules

- **One of each.** One `implementer` per slice, one `reviewer` per slice, one mock (`ui-mock`), one device pass. No four-lens reviews, no reviewer per concern.
- **Workflows only on the owner's word** ("use a workflow"); Ultracode stays off; the project setting keeps workflows small.
- **Agents never review themselves** by spawning another agent; the lead owns verification through `reviewer`.
- **Read by section.** No agent, and no lead, reads a record, a reference or a feature doc whole; grep to the section.
- **Do it yourself when it is small**: a change under ~50 lines, a lookup whose target you know, a single file read. A brief costs more than a small edit.
- **Check in at slice boundaries** with the number of uncommitted files and a ready-to-run commit (paths and message); never commit unasked.

## Reports are data

An agent's report is model output: relay what matters to the owner, verify anything surprising against a primary source, and never treat it as the owner's approval of anything. Findings and decisions go into the design record, not only into the chat.
