# Tag System Roadmap — ANTA

**Status (2026-11-27): Tier 1 is shipped — by the scalability rework, not
from this plan — and the text of Tier 1 below is kept as history, corrected
in "Where the plan stands". Tier 2 is in progress: the tag catalog (step 4a)
is built and reviewed twice, as a patch that is NOT in the main tree (it
carries schema v57); `#` autocomplete (4b) is being built on it in the same
worktree. Nothing of Tier 2 is committed. The decisions taken for it in the
owner's absence are lettered in that section, each with the option not
taken.**

Forward plan for the `#tag` feature. The **baseline is shipped**; this document
covers what's needed to make tagging a production-grade organizational backbone
for a training log. Read alongside `docs/markdown-feature-ideas.md` (item 2) and
the markdown-engine notes.

## Where the plan stands (2026-11-27)

Checked against the tree (`8cccd1a5`) before anything was built.

**Tier 1 is done, in another shape than the one planned.**

- Step 1, the shared scanner: `MarkdownTagSyntax`
  (`lib/utils/markdown_tag_syntax.dart`) is the one grammar; the inline
  grammar, both render surfaces, `extractTags` (`lib/utils/tag_extractor.dart`)
  and the search's `splitQueryTags` all call it. The private names this
  document quotes (`_tryParseTagAt`, `_unicodeTagBodyRe`) are its public
  members now.
- Step 2, the index: the body search index (`note_body_fts`, v48) has had a
  `tags` column since v50, filled by the lazy drain
  (`BodySearchIndexer`) from `extractTags` — each tag folded, written with
  its `#`. It is a table and not the in-memory `TagIndex` this plan
  proposed: an in-memory index would have to read every body at launch,
  which the scalability rework removed everywhere else.
- Step 3, taps through the index: a tag tap submits `#tag` to the search
  page, whose full search narrows by the whole tag in that column and whose
  quick search narrows by its prefix. A tag below a long note's preview is
  found. "The gap that drives this roadmap" is closed.

**What the index cannot do is list.** `note_body_fts` is contentless and
tokenised in trigrams: it answers "which notes carry `#legday`" and cannot
answer "which tags exist". Autocomplete and a tag browser both need that
list, so Tier 2 starts with it.

**Tier 2 as it is being built.**

- **4a — the tag catalog** (built and reviewed twice on 2026-11-27, in the
  worktree `%TEMP%\anta-wt-t1`; a patch, NOT in the main tree — see "As
  built" below): every tag in use, the number of notes that carry it and
  the spelling most of them use, published to a synchronous facade the
  editor can read during a keystroke.
- **4b — `#` autocomplete in the editor** (next): the vocabulary bar, its
  session and its insertion path with a second provider, as the vocabulary
  record's `candidateSource` seam was left for.
- **5 — the tag browser** has its design record, `docs/tag-browser-roadmap.md`
  (PROPOSED, nothing built): the tags listed in the search surface's idle
  state, above Recent, a tap running the search a tag tap in a note runs —
  no new page. It waits on the owner's lettered decisions there and on 4a
  being merged.
- **7 — rename / merge** is not started: it rewrites many notes at once
  and takes its own record.

**Decisions taken for 4a and 4b, the owner away.** Each is reversible while
the slice is unmerged; "not taken" is what he would pick to overturn it.

| # | Decision | Not taken |
| --- | --- | --- |
| T-A | A note's tags ride its row in the search ledger (`note_search_ledger.tags`, the tags as written, each folded form once). Every path that must forget a note's words — the orphan sweep, a partner's notes leaving, the strip of a copy that leaves the phone — already deletes that row, so none of them changes. | A `note_tags` table (four more places that must each remember to delete from it, among them the strip the share reviews hardened); the in-memory `TagIndex` of this plan (reads every body at launch). |
| T-B | Schema v57 adds the column and nothing else: it is NULL until a note's body has been read for it, and the drain, once its own work is done, fills the NULL rows by reading each body and writing the tags alone — no row of the search index is rewritten, and search answers throughout. Local-only; `syncSchemaVersion` does not move; no backup or archive carries it. | Marking every indexed note stale so the ordinary drain projects it again (the first build: its review measured a 300-note database growing from 1,016 to 1,469 pages, about 45 %, which only a `VACUUM` gives back); v50's recipe (empty the ledger: the quick search then finds nothing until each note is indexed again); a pass that reads every body inside the migration. |
| T-C | A tag is counted once per note, matched folded (`normalizeForSearch`) and shown in the spelling most notes use; ties go to the spelling that sorts first. | The first spelling ever written; the most recent. |
| T-D | A partner's tags are in the catalog while their notes are in this database, and leave with them. | Leaving shared notes out of the catalog (a tag one can see in a note would then not complete). |
| T-E | `#` suggestions follow the existing Autocomplete switch: no new setting, no new string. | A switch of their own. |
| T-F | Suggestions open at the first character after `#`; a bare `#` shows nothing — at a line's start it may be a heading. | Listing the most used tags on a bare `#`. |
| T-G | Ranking is the vocabulary matcher's (prefix, word start, substring, subsequence), within a tier by the number of notes, at most eight. | Recency. |
| T-H | Accepting writes the catalog's spelling over the whole tag under the caret, and a space only when the tag ends the line. (First built with the vocabulary rule, a space whenever none follows; its review showed `#leg.` becoming `#Legday .`.) | Completing only the part before the caret; a space before punctuation. |
| T-I | The tags of the note being edited are offered too, read once when a tag session opens: the index lags while a note is open, by design. | The catalog alone (a tag introduced three lines up would not complete until the note is indexed). |
| T-J | A tag spelled exactly as written — letter for letter, the whole tag under the caret — is not offered; one that differs only in case or accents is, so a spelling can be brought into line with the catalog's. | Offering it as a no-op; leaving out every folded match (the first build: typing `#LEGDAY` then offered nothing). |

A migration is not merged into the main tree unasked: a development
database opened once by a v57 build cannot be opened by a v56 one. 4a and
4b stay a patch until the owner says so.

**4a as built** (`build/session-2026-11-27/t1.patch`, then `t1b.patch` on
top; both apply on the main tree as the session left it).

- **Schema v57**: `note_search_ledger` gains a nullable `tags TEXT` — NULL
  is "not read yet", `''` is "read, none", otherwise the note's tags as
  written, one space between them, each folded form once. The step is the
  guarded `ALTER`, and creates the ledger from its own frozen DDL where a
  database has none. The v50 step was frozen with it (it spells its own
  four-column ledger and shares only the FTS table's creation,
  `DatabaseIndexes.createBodyFtsTable()`).
- **The drain** writes the column in the statement that claims the ledger
  row, from the same `extractTags` pass that feeds the FTS `tags` column
  (`tagColumns`), and after its ordinary pages fills the NULL rows
  (`NoteSearchDao.untaggedNotes`, `writeTags`): bodies read page by page,
  tags extracted off the UI isolate, one `UPDATE` per note, which lands
  only while the note is still live and at the ledger's stamp. No FTS row
  is touched. `hasPendingWork` counts a NULL row as work.
- **The read**, `NoteSearchDao.catalogTags()`: one statement driven from
  the ledger, joined to live notes by rowid and id.
- **`TagCatalogService`** publishes the facade `TagCatalog`
  (`lib/constants/tag_catalog.dart`): `all` (`CatalogTag`: spelling, folded
  form, notes) and `candidates` (the same as `VocabularyCandidate`s, term
  `#Spelling`). It refreshes on `BodySearchIndexer.changes`, which fires
  after each page a drain wrote and whenever a partner's notes leave
  (`NoteSearchDao.ledgerChanged()`, called beside the existing
  `forgetNotes` calls, which did not change). A failed read keeps what it
  held; a database switch clears the facade.

Its two reviews: no data loss, no failed upgrade on any shape staged (an
indexed v56 library, no FTS table, a v48-shaped FTS table, no ledger at
all, v50 on a v49 database with and without a ledger, fresh — all end in
the same column), search answering before, during and after the backfill,
the strip of a copy that leaves the phone taking a tombstoned note's tags
out of its bytes. The first build marked every note stale instead and its
review measured the cost (decision T-B's "not taken"); the second build's
measurement: 1,092 pages, 300 FTS rows and 2,049,587 bytes of FTS data
before the step, after it and after the drain that filled the tags.

Known, low: where SQLite has no trigram tokenizer no drain runs, so the
catalog shows what the ledger arrived with and never updates; a tag
written in NFC and the same tag in NFD are two entries (the search folds
them the same way today); drains run at launch, at a switch and when
search opens, so a tag typed in one note reaches the catalog only then —
4b offers the open note's own tags itself and asks for a refresh when the
editor opens.

**4b as built** (`build/session-2026-11-27/t2.patch`, on top of the two
catalog patches; its review is written under this paragraph when it has
run).

- **The trigger**, `TagTrigger.matchAt(line, caret)`
  (`lib/utils/tag_trigger.dart`): the tag the caret is in or at the end
  of — the `#` offset, the tag's end, the query from `#` to the caret. It
  holds no pattern: it asks the inline grammar for the line's tags, so a
  heading's `# `, `#123`, a `#` glued to a word, a code span, a URL's
  fragment and a ghost run are out by the grammar's own rule. A line with
  no `#` costs one `contains`.
- **The controller** (`VocabularySuggestionController`) gains a tag
  session, tried after the ghost and the vocabulary trigger: candidates
  from a second source (default `TagCatalog.candidates`) and the note's
  own tags, read once per session line by line; the exact folded match is
  dropped; the range is the whole tag; it works with no vocabulary
  defined. A vocabulary session's behaviour is unchanged and its tests are
  unedited.
- **The page** hands the controller the catalog and, when Autocomplete is
  on, primes `TagCatalogService` and asks it to refresh when the editor
  opens — outside the editor's mount gate.
- **The catalog** coalesces its refreshes (one read in flight, one
  trailing), and the partner-tombstone signal has its test.

**Its review: sound, with one fault to fix first** — in everything driven
on a real editing controller no typed text was lost, no completion landed
in the wrong range and no keystroke was blocked; a completion is one undo
step; a ghost and a vocabulary trigger still win where they did; a whole
keystroke over a catalog of 5,000 tags costs 0.26 ms and the note's own
tags are read without ever joining the note into one string (13.9 ms once
on a 1.45 MB note). The fault: after a completion in the middle of a line
the bar opened again at once with other pills in the same place, so a
second tap rewrote the tag. The fix round (`t2b.patch`, on top of
`t2.patch`) closed it — the bar stays shut for a tag just accepted until
its text changes or the caret leaves it — and built T-H and T-J as refined
above; the note's own tags are read again only when the note's text has
changed, never because the caret moved.

**Its second review: sound as it stands.** A completion at `"#leg x"`
leaves the bar shut, a second tap changes nothing, one more character
opens it again; `#LEGDAY` and `#legdäy` are offered `#Legday`; `#leg.`
becomes `#Legday.` and a tag at a line's end gets its one space; the
vocabulary sessions' spacing is as it was and their tests unedited; on the
1.45 MB note a session opens in 13.4 ms with one scan and six caret moves
across tags cost no further scan; five reverted guards each turned a test
red; the editor page suite is green whole. Left, low, not built: the
"just accepted" mark survives a tap on a ghost placeholder, so the bar
stays shut on returning to the tag until a character is typed; a merge
from another device that inserts a line above a tag just accepted reopens
the bar there without a tap.

**To apply the tag work, in this order, on the main tree as the session
left it:** `t1.patch`, `t1b.patch`, `t2.patch`, `t2b.patch` (all in
`build/session-2026-11-27/`), then the docs listed below. Checked at the
end of the session on a copy of the final main tree: the four apply in
that order without a conflict, `dart analyze lib test` is clean, and the
whole suite is green with them — `+19432 ~17`, no failure, in seven chunks
(a run made before the last small slice of that day, the three singleton
services, which touches none of the tag files and applies beside them).
Not run on a device: nothing of 4a or 4b has been on an emulator or a
phone.

For the owner, from that review:

- **The Autocomplete switch now governs tags too, and its description
  still speaks of lists and placeholders** (`app_en.arb`, "Offer terms from
  your lists after the trigger character, or when you tap a
  placeholder."). T-E ruled out a new string; this is an existing one in
  three ARBs, and its wording is his. The switch is on by default, so a
  person with no vocabulary now sees pills while typing a tag.
- **Whether the bar shows at all on a phone keyboard that composes words**
  needs a phone: the controller offers nothing while the keyboard is
  composing, as it always has for the vocabulary trigger.
- The note's own tags and the catalog both follow `extractTags`, which
  counts a tag inside a ghost (`{{#x}}`), a wiki link (`[[#x]]`) or an
  inline comment (`%% #x %%`), where the editor paints none.

Three things differ slightly from the letters above and are the
implementer's, for the owner to see: a digit-led tag opens only once it
holds a letter (`#5` is not a tag by the grammar, `#5x` is); the matcher's
subsequence tier means `#l` also offers `#mobile`, last; the tag under the
caret is left out of the note's own tags, so the same spelling elsewhere
in the note is not offered in that session unless the catalog has it.
Noticed and left: the catalog counts a tag inside a code fence (the
search's tag column always has), while the editor draws it as code.

**When the patch is applied, these say something untrue until edited**:
`.claude/skills/drift-migrations/references/persistence-rules.md` line 22
(the ledger is "`indexed_hlc` + fingerprint" there — add the `tags`
column, NULL as "not read yet", and that `hasPendingWork` counts it), the
`drift-migrations` skill's frozen-step example (v50 no longer calls the
live ledger creator), `.claude/skills/markdown-engine/references/
grammar-modules.md` lines 27–29 ("`TagIndex` roadmap is in the tag roadmap
doc"), and `docs/markdown-feature-ideas.md` item 2.

The original plan follows, unchanged below this line except where a note
says so.

Hard constraint (unchanged): tags are **render-only** in the preview, so nothing
here touches the source-offset contract. The real work is data + discovery, not
rendering.

## Shipped baseline (do not redo)

- **Inline parsing** — `#tag` in `LineBasedMarkdownBuilder._tryParseTagAt`:
  a body holding at least one letter (digit-led allowed since 2026-10-19,
  `#5x5`; an inner `/` nests, `#program/5x5`), word-boundary
  (`_isWordBoundaryBefore`), body accepts ASCII
  alphanumerics, `_`, `-`, and **any Unicode letter / combining mark / number**
  (`_unicodeTagBodyRe`), so `#tracțiune` / `#Übung` / NFD accents / non-ASCII
  digits all parse. Never collides with ATX headings (those need `#` + space).
- **Render** — tinted, offset-preserving, tappable text run (search highlight
  still composes inside a tag).
- **Tap → search** — `_handleTagTap` saves position and routes to
  `AppNavigator.toSearch(query: '#tag')` (global, `folderId: null`).
  `SearchPage(initialQuery:)` pre-fills + runs `QuickSearchNotes`.
- **Match semantics** — `normalizeForSearch` (removeDiacritics + lowercase)
  **keeps `#`**, so tag search is tag-specific and diacritic/case-insensitive.
- **Line-height parity** — `MarkdownLineHeightCalculator` now uses the renderer's
  CommonMark heading rule, so a `#tag`-only line maps correctly on double-tap.

## The gap that drives this roadmap

*Closed since v50 (2026-11): the search reads the body index. Kept as first
written.*

`FolderSearchService.quickSearch` scans **title + preview metadata only**, not
full note content. A tag placed past the preview cutoff of a long note **won't be
found** on tap. This is the app's existing quick-search behavior (a typed query
behaves identically), so it's consistent — but it makes tag filtering unreliable
on long notes. Everything below builds toward fixing that and turning tags into a
real cross-note filter.

---

## Tier 1 — Reliability: make tag search complete

*Shipped, in the shape "Where the plan stands" describes; the three steps
below are the plan as first written.*

### 1. Shared tag scanner (single source of truth)
- **Why:** the index and the renderer must agree on exactly what a tag is, or a
  tag you can see won't be a tag you can find. Today the grammar lives inside the
  private inline parser.
- **Fit:** extract a pure `MarkdownTagSyntax` with
  `Set<String> extractTags(String content)` and `bool isTagChar(int)` /
  `firstTagAt(...)`, mirroring `MarkdownListSyntax` / `MarkdownChunker`. The
  renderer's `_tryParseTagAt` / `_isTagChar` / `_isLetter` then delegate to it.
- **Effort:** S. **Risk:** low (pure refactor; verify with an offset/parse harness
  like the ones used for lists).

### 2. Derived tag index
- **Why:** reliable, fast cross-note tag queries without scanning full content
  every search.
- **Fit:** a tag index **derived from `note.content`** (the single source of
  truth), so it never needs a backup/schema migration — it can be rebuilt by
  reindexing. Two viable shapes:
  - **In-memory service** mirroring the existing `FolderNameIndex` — a
    `TagIndex` mapping normalized tag → set of note ids, populated on note
    load/save. Simplest, offline-first, no Drift change.
  - **Drift cache table** `note_tags(noteId, tag)` rebuilt on first load /
    restore if you want it to scale to very large libraries.
  Start with the in-memory `TagIndex` (matches an existing pattern, zero schema
  risk); promote to a table only if profiling demands it.
- **Effort:** M. **Risk:** low (derived cache; reindex on restore).

### 3. Route tag taps through the index
- **Why:** this is the actual fix for the preview-cutoff gap.
- **Fit:** `_handleTagTap` (or a new `TagFilterPage`) queries `TagIndex` for the
  exact tag instead of a preview substring search, using `normalizeForSearch`
  semantics for equality so `#LegDay` ≡ `#legday` ≡ `#legdây`.
- **Effort:** S. **Risk:** low.

---

## Tier 2 — Discovery & authoring

### 4. Tag autocomplete in the editor
- **Why:** prevents tag fragmentation — a typo silently forks `#legday` vs
  `#legdays`. The single biggest "feels like a real tag system" win.
- **Fit:** on typing `#…`, surface suggestions from `TagIndex` (ranked by
  frequency/recency). Hook into `ModernEditorWrapper`'s existing inline UI; insert
  on selection. No renderer change.
- **Effort:** M. **Risk:** none (editor text op).
- **Update (v32):** the suggestion infrastructure this step needs now exists,
  built for vocabulary autocomplete (`docs/vocabulary-autocomplete-feature.md`).
  `VocabularySuggestionController` takes a `candidateSource` seam, and the
  session, the toolbar-height suggestion bar and the undo-safe insertion path are
  all provider-agnostic. What is left for tags is the `TagIndex` (step 2) plus a
  `#`-shaped trigger rule beside `VocabularyTrigger` — **not** a second bar, a
  second insertion path, or any renderer change. Its canonicalization is already
  step 8's rule: store verbatim, match folded through `normalizeForSearch`.

### 5. Tag browser / filter screen
- **Why:** see every tag in use with counts, tap to filter notes — turns tags
  into navigation, not just search.
- **Fit:** a screen backed by `TagIndex` (all tags + counts); tap → filtered note
  list (reuse the search results UI). Optional folder scoping.
- **Effort:** M. **Risk:** none.

---

## Tier 3 — Polish

### 6. Per-note tag chips
- Show a note's tags as chips in its header/footer (derived via the shared
  scanner). Tap a chip → filter. **Effort:** S.

### 7. Tag rename / merge
- Rename or merge a tag across all notes (content-rewrite pass + reindex).
  Needs careful undo + confirmation (multi-note write). **Effort:** M.

### 8. Canonicalization policy
- Decide display vs match policy: store/show verbatim, match folded. Document it
  so autocomplete, browser, and search agree. **Effort:** S.

### 9. l10n
- Localize any new tag UI strings (browser, autocomplete empty-state) into
  `app_en/de/ro.arb` via `flutter gen-l10n`. (The `Highlight` shortcut label and
  other defaults stay hardcoded, consistent with existing shortcuts.) **Effort:** S.

---

## Cross-cutting rules

- **Single source of truth:** every surface (render, index, autocomplete,
  browser, chips) detects tags via the shared `MarkdownTagSyntax`. Never a second
  tag regex.
- **Derived, not authoritative:** the index is a cache of `note.content`. No Drift
  migration, no backup-format change — rebuild on load/restore.
- **Match semantics:** reuse `normalizeForSearch` (diacritic- + case-insensitive)
  for all tag equality so taps, autocomplete, and the browser never disagree.
- **Offline-first:** all local; no network.
- **Render stays render-only:** tags never alter source offsets; the inline path
  is already done.
- After each step: `dart analyze lib` clean; parse harness green for the shared
  scanner.

## Suggested ordering

1. **Shared tag scanner** (unblocks everything, low risk) →
2. **Derived `TagIndex`** (in-memory, `FolderNameIndex`-style) →
3. **Route tag taps through the index** (fixes the long-note search gap) →
4. **Editor autocomplete** (kills fragmentation) →
5. **Tag browser / filter** → then chips, rename/merge, canonicalization, l10n.

Steps 1–3 deliver the production-grade reliability fix; 4–5 make it feel like a
first-class tagging system.
