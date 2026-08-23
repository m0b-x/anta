# Tag System Roadmap — ANTA

Forward plan for the `#tag` feature. The **baseline is shipped**; this document
covers what's needed to make tagging a production-grade organizational backbone
for a training log. Read alongside `docs/markdown-feature-ideas.md` (item 2) and
the markdown-engine notes.

Hard constraint (unchanged): tags are **render-only** in the preview, so nothing
here touches the source-offset contract. The real work is data + discovery, not
rendering.

## Shipped baseline (do not redo)

- **Inline parsing** — `#tag` in `LineBasedMarkdownBuilder._tryParseTagAt`:
  letter-led, word-boundary (`_isWordBoundaryBefore`), body accepts ASCII
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

`FolderSearchService.quickSearch` scans **title + preview metadata only**, not
full note content. A tag placed past the preview cutoff of a long note **won't be
found** on tap. This is the app's existing quick-search behavior (a typed query
behaves identically), so it's consistent — but it makes tag filtering unreliable
on long notes. Everything below builds toward fixing that and turning tags into a
real cross-note filter.

---

## Tier 1 — Reliability: make tag search complete

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
