# Markdown Feature Ideas — ANTA Builder

Candidate features for the custom markdown engine (`lib/utils/line_based_markdown_builder.dart`
+ `markdown_chunker.dart` + `markdown_list_syntax.dart`), chosen for a **gym /
workout-tracking** log rather than a generic notes app.

These intentionally **exclude** items already planned or shipped: lists/tasks
(done), tables, code blocks, images, embedded media, collapsible sections,
equations, and find-&-replace (already exists).

## How to read this

Each feature notes:

- **Why (gym)** — the training-log value, not generic appeal.
- **Fit** — how it lands on the current line/block parser without breaking the
  hard constraint: **every rendered span must keep its exact source offset** so
  search highlighting and editor↔preview scroll mapping stay correct.
- **Effort** — rough, relative.
- **Offset risk** — whether it threatens the source-offset contract.

Tiers are by value-to-effort for this app specifically.

---

## Tier 1 — High value, gym-specific, cheap on the line parser

### 1. Highlight / mark — `==PR==`
- **Why (gym):** mark personal records, working weights, "today's target" so they
  pop in a dense log. The single most-wanted inline style after bold/italic.
- **Fit:** one more branch in the recursive inline parser (`_parseInline`),
  exactly like strikethrough `~~`. Leaf text still flows through
  `_applyHighlighting`.
- **Effort:** XS. **Offset risk:** none.

### 2. Tags — `#legday`, `#pr`, `#deload` — ✅ SHIPPED (baseline)
- **Status:** the inline `#tag` token, tappable render, and tap → global
  diacritic-insensitive search are shipped. Body is Unicode-aware (accents, NFD,
  non-ASCII digits). Next steps (full-content search, tag index, autocomplete,
  browser) are tracked in **`docs/tag-system-roadmap.md`**.
- **Why (gym):** the highest-leverage organizational feature for a training log —
  tag sessions by split, mesocycle, or feeling, then filter/search across notes.
- **Fit:** inline token in `_parseInline` (word-boundary `#` + identifier),
  rendered as a tappable chip. Tap → run the existing app search for that tag.
  Feeds the existing FTS/app-level index, so cross-note filtering is mostly wiring.
- **Effort:** M (rendering XS; the index/filter UI is the real work).
- **Offset risk:** none for rendering.

### 3. Callouts / admonitions — `> [!TIP]`, `> [!WARNING]`, `> [!PR]` — ✅ SHIPPED
- **Status:** the first real customer of the block model after code fences.
  `MarkdownBlockKind.callout` (non-atomic) + the shared
  `lib/utils/markdown_callout_syntax.dart` grammar; each line renders a colored
  left bar + tint, with an icon + label/title header on the lead line. Types:
  `note, tip, important, warning, caution, success, pr` (5 GitHub + 2 gym).
  Preview-only; per-line offsets unchanged; search highlights compose inside.
- **Why (gym):** form cues, injury warnings, coach notes, deload reminders — a
  blockquote that actually stands out with an icon + tint.
- **Effort:** M. **Offset risk:** low (block-aligned; per-line offsets unchanged).

### 4. Auto-renumber ordered lists (editor companion)
- **Why (gym):** reorder exercises and the numbers fix themselves instead of
  reading `1. 1. 1.` or `1. 3. 2.`.
- **Fit:** pure editor-side, no renderer change. On edit within an ordered run,
  renumber sequentially through `MarkdownListSyntax` (already the source of truth
  for ordered items + delimiter). Lives next to the Tab/Shift-Tab handler in
  `ModernEditorWrapper`.
- **Effort:** M. **Offset risk:** none (editor text op, undo-merged).

### 5. Set / shorthand smart tokens — `5x5@100kg`, `{1rm:100x5}`
- **Why (gym):** the core domain win. Type sets the way lifters actually write
  them and render a clean summary; estimate 1RM (Epley/Brzycki) inline from
  `weight x reps`.
- **Fit:** inline token recognizers in `_parseInline`. `5x5@100kg` →
  styled "5 sets × 5 reps @ 100 kg"; `{1rm:…}` → computed value (read-only render,
  source stays literal so it's still searchable/editable). Unit awareness ties
  into a `SettingsKeys` kg/lb preference.
- **Effort:** M–L. **Offset risk:** none (render-only; source text unchanged).

---

## Tier 2 — Strong quality-of-life

### 6. Wiki-links between notes — `[[Squat Progression]]`
- **Why (gym):** link today's session to a program, a previous PR day, or an
  exercise's technique note. Turns a flat log into a connected training journal.
- **Fit:** inline token in `_parseInline`; resolve the title via `NoteRepository`
  (filter `is_deleted`, like the calendar's linked-note resolution), tap →
  `AppNavigator`. Unresolved titles render in a muted "broken link" style.
- **Effort:** M. **Offset risk:** none.

### 7. Table of contents — `[[toc]]` or auto for long notes
- **Why (gym):** jump nav for long-running logs ("Week 1 … Week 8") or a master
  template with many exercise sections.
- **Fit:** a pre-pass over headings (already detected in `buildLine`) builds a
  list of `(level, text, lineIndex)`; render a tappable outline that uses the
  existing `scrollToLineIndex`. Could also be a slide-out outline rather than
  inline.
- **Effort:** M. **Offset risk:** none (uses existing line→scroll mapping).

### 8. Note front-matter / metadata header
- **Why (gym):** capture bodyweight, date, sleep, soreness, or session RPE at the
  top of a note and render it as a compact chip row instead of raw `key: value`.
- **Fit:** detect a leading `---` … `---` fenced block (new
  `MarkdownBlockKind.frontMatter`, `atomic: true`), parse `key: value` lines,
  render a small header. Pairs naturally with ghost text for templates.
- **Effort:** M. **Offset risk:** low (atomic block; isolated region).

### 9. Inline rest timer — `[timer:90s]`
- **Why (gym):** tap a rest-timer token between sets and get a live countdown
  without leaving the note. Uniquely valuable mid-workout.
- **Fit:** inline token → tappable widget span that starts a local countdown
  (no persistence needed; ephemeral UI state). Mirrors the checkbox/ghost tap
  plumbing (`onGhostTap`-style callback).
- **Effort:** M. **Offset risk:** none (render-only token).

### 10. Definition lists — `Exercise : cue or description`
- **Why (gym):** a lightweight exercise glossary or cue sheet (`RDL : hinge, soft
  knees, neutral spine`).
- **Fit:** line-level detection (term line followed by `: definition`), rendered
  with a bold term + indented body. Two-line lookahead via the block model.
- **Effort:** M. **Offset risk:** low.

---

## Tier 3 — General markdown completeness

### 11. Footnotes — `[^cue]`
- **Why (gym):** attach form cues or references without cluttering the set line.
- **Fit:** inline reference + a collected footnotes block at the end. Needs a
  document-level pre-pass to resolve `[^id]` → definitions.
- **Effort:** M–L. **Offset risk:** medium (two-pass; keep ref offsets exact).

### 12. Superscript / subscript — `cm^2^`, `H~2~O`
- **Why (gym):** units and measurements (cm², body-fat notation, etc.).
- **Fit:** inline parser branches with `PlaceholderAlignment` font scaling.
- **Effort:** S. **Offset risk:** none.

### 13. Emoji shortcodes — `:muscle:`, `:fire:`
- **Why (gym):** fast visual markers for PRs/streaks; lighter than picking from a
  keyboard mid-set.
- **Fit:** inline token → emoji glyph via a static shortcode map.
- **Effort:** S. **Offset risk:** none (single-glyph substitution; keep source
  literal for search).

### 14. Reference-style links — `[text][ref]` + `[ref]: url`
- **Why:** cleaner long notes with repeated links.
- **Fit:** document-level link-definition pass feeding `_parseInline`.
- **Effort:** M. **Offset risk:** medium (resolution pass).

---

## Editor / UX features (not rendering)

### 15. Slash-command menu — `/`
- **Why (gym):** `/` → insert an exercise table, a set template, a callout, a
  timer, a ghost-text placeholder. Faster than hunting the toolbar mid-workout.
- **Fit:** trigger a menu on `/` at line start (re_editor caret hooks), insert via
  the existing shortcut/ghost insert paths.
- **Effort:** M–L.

### 16. Workout-table smart paste
- **Why (gym):** paste sets copied from a spreadsheet/app and auto-format to a
  markdown table.
- **Fit:** extend the existing paste handler (`PasteLineBreaker` lives there) to
  detect tab/comma-delimited rows and emit a table. Depends on Tier-2 tables
  landing first.
- **Effort:** M.

### 17. Selection formatting bar
- **Why (gym):** select text → quick Bold / Highlight(`==`) / link, instead of
  toolbar round-trips.
- **Fit:** extend `ModernEditorWrapper`'s existing mobile selection toolbar
  (`_buildSelectionToolbar`) with markdown actions.
- **Effort:** S–M.

---

## Suggested ordering

1. **Highlight `==`** (XS, immediate polish) →
2. **Tags `#`** (organizational backbone, ties into search) →
3. **Callouts** (proves the block model beyond code fences) →
4. **Set shorthand / 1RM** (the signature gym feature) →
5. **Wiki-links** + **TOC** (connected journal) → then Tier 3 / UX as desired.

Everything here preserves the source-offset contract except where flagged
"medium" (footnotes, reference links) — those need a document-level resolution
pass and should keep ref/leaf offsets exact, verified with an offset harness like
the ones used for Batch 0 and the list work.
