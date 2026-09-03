# Live Markdown Editor — Review & Consolidation Slices (2026-09-03)

**Status: Sessions 0, 1 and 2 DONE 2026-09-03 (§3). Sessions 0–1 are
committed as `38c7b50`; Session 2 and its same-day follow-up are
uncommitted on top. Sessions 3–10 PLANNED, not implemented.** Baseline commit `bf2e7ba`
(main). Line numbers below are as of that commit and will drift — re-grep
before editing. This doc is the ledger for making the Obsidian-style live
editor the app's only day-to-day markdown surface, retiring the read-only
preview behind a "Deprecated features" setting, and making the editor scale
to 10k-line notes on low-end phones.

Companion docs: `live-markdown-editor-roadmap.md` (what is built, decision
log, on-device checklist), `re-editor-performance-2026-07.md` (the previous
perf batch), `markdown-feature-ideas.md`. Invariants live in
`.claude/skills/markdown-engine/SKILL.md` and are not restated here.

Review method: seven independent read-only passes (renderer correctness,
hot-path performance, preview/editor parity, retirement surface, page
architecture, re_editor fork, test coverage), then the high-impact claims
were re-traced by hand. CONFIRMED = traced in code with a concrete input.
SUSPECTED = reasoned, not executed.

---

## 0. Verdict

**Features.** The live editor already covers everything a training / spending
/ appointments log needs day to day: headings, lists, tasks with atomic
toggles and indeterminate parents, emphasis, code, highlight, colours,
quotes, callout lead lines, links, tags, ghosts, the full money ledger. Its
tap model (claim at tap-down, never move the caret, never raise the
keyboard) is better than the preview's. What it lacks before the preview can
go dark by default is small: **tag tap → search** is the only High-value
preview-only interaction. Tables, callout blocks and bullet-depth glyphs are
Medium and can follow.

**Do the features work together?** Mostly yes; the interplay bugs are all in
the *page*, not the renderer. The keyboard-hidden auto-preview is checked
against the wrong flag in six places (blank screen on large notes, dead
checkbox refresh, replace field in the wrong state), position restore races
content load, settings changed on the main settings page do not apply until
the note is reopened, and a user with live rendering OFF gets the editor
remounted a frame after open. None of these is in the span builder.

**Performance.** The steady-state typing path (memo hit, identity paragraph
cache) is genuinely O(visible lines) and fine. The problem is the
*structural* path: `CodeLines.of` re-folds segment counts on every `add`
(O(256²) per segment ⇒ ~2.6 M closure calls ≈ 40–65 ms for 10k lines), and
the app rebuilds the **whole document** through it on the two most common
edits in a training log — Enter on a list line and a checkbox toggle. On top
of that the task and money index passes rescan to end-of-document on every
keystroke. These three items are the low-end ceiling; everything else is
second order.

**Architecture.** The layering rules hold except for one Page→DAO call
(font sizes). The span builder is correct but is a 2.4 k-line god-class, and
the emphasis/inline-code grammar is **forked** between preview and editor —
the only syntaxes without a shared module — with three confirmed visible
divergences. The editor page is a 2.5 k-line State with ~50 fields and 24
whole-page `setState`s. The fork's additions are well-built but have zero
tests and zero asserts; the fork's nested `.git` is a trap. **The whole live
rendering stack — span builder, line index, chunker, every grammar except
money — has no automated test.** That is the first thing to fix, because
every slice below is a hot-path or grammar change.

---

## 1. Findings

### 1.1 Performance (hot path) — CONFIRMED unless noted

| # | Where | What | Cost on a 10k-line note |
|---|---|---|---|
| P1 | `packages/re_editor/lib/src/_code_lines.dart:73-86`, `code_lines.dart:512-516` | `_CodeLineSegmentQuckLineCount.add` / `[]=` / `length=` recompute `super.lineCount` and `super.charCount`, which are `fold`s over the whole segment | `CodeLines.of` ≈ 2.6 M closure calls, 40–65 ms |
| P2 | `lib/pages/optimized_note_editor_page.dart:1509-1516` (Enter on list line), `lib/widgets/modern_editor_wrapper.dart:392-399` (checkbox toggle) | Rebuild the entire document via `CodeLines.of([...])` for a one-line change. Also breaks segment identity ⇒ line index falls back to `_rebuildAll`, and pins a full 10k-ref undo node | P1 + full index rebuild + ~80 KB per edit retained by undo |
| P3 | `lib/utils/markdown_editor_line_index.dart:274-350` (`_scanTasks`), `:~350+` (`_scanMoney`) | Both loop `for (s = first; s < n)` with no suffix proof (only `_scanFence` has one, `:238-244`). Runs inside `performLayout` on the first visible line after every keystroke | caret near top ⇒ 10k `scanListShape` + 10k `leadsWithMoney` per keystroke |
| P4 | `optimized_note_editor_page.dart:714-724` | Autosave `onChangeDetected` schedules an unguarded whole-page `setState` per keystroke; `_updateCachedStats` (`:865`) rebuilds Scaffold+editor+toolbar every ~300 ms to repaint two stats `Text`s; `_onContentFocusChanged` (`:274`) rebuilds everything for a bool | rebuild cost per keystroke, not layout |
| P5 | `lib/utils/markdown_editor_span_builder.dart:231-238` | `MarkdownMoneySyntax.parse` (≈400-line parser) runs *before* the positional cache lookup | per visible money line per layout pass |
| P6 | `packages/re_editor/lib/src/_code_paragraph.dart:568-643` | Hanging layout = two `ParagraphBuilder`+`layout` + `getBoxesForRange` + `getBoxesForPlaceholders` per list line on cache miss; still built when `wordWrap` is off (maxWidth ∞, `_code_field.dart:1461-1464`) | 40 fresh list lines ≈ 5–12 ms per fling frame |
| P7 | `lib/utils/paste_line_breaker.dart:80-125`, `editor_width_calculator.dart:104-108,172-176` | Paste: 4–5 full-document string passes + `TextPainter.layout` per line, synchronous in a controller notification | 500-line paste ≈ 0.3–1 s |
| P8 | `packages/re_editor/lib/src/_code_line.dart:1925-2000` | Undo history uncapped; each P2 event pins a full copy | 200 such edits ≈ 16 MB until dispose |
| P9 | `optimized_note_editor_page.dart:1624-1629` | On open: `'\n'.allMatches(content)` allocates 10k matches, then `_pushPreviewContent` runs the **full preview prepare synchronously** even in editor mode | 250–600 ms open, SUSPECTED range |
| P10 | `packages/re_editor/lib/src/_code_field.dart:1130-1172, 1179-1182, 1436-1438` | Scroll extent estimated at base line height; scaled headers + wrapped lists make it low ⇒ `correctBy` re-entry + recursive `_updateDisplayRenderParagraphs`; upward fling walks paragraphs backwards | jitter on header-heavy notes, SUSPECTED |
| P11 | `packages/re_editor/lib/src/_code_field.dart:276-283, 556-569` | `codes` setter calls `markNeedsSemanticsUpdate()`; `describeSemanticsConfiguration` sets `value` to the whole document via `asString`. Each keystroke produces a new `CodeLines`, so under TalkBack this is a full join + platform-channel send per keystroke | hard stall per keystroke with a screen reader on |

Not a problem (checked): no per-keystroke `controller.text` join on the
steady path; IME ships only the caret line; the highlight isolate never runs
(no `CodeHighlightTheme`); no `debugPrint` on hot paths; `markContentDirty`
and `updateContent` are cheap. Memory at steady state ≈ 6–9 MB above the raw
text for 10k lines (span LRU 1024, positional LRU 128, plain-span LRU 1024,
≤512 paragraph entries but **two native paragraphs per hanging entry**).

### 1.2 Correctness bugs — CONFIRMED

| # | Where | Bug |
|---|---|---|
| B1 | `optimized_note_editor_page.dart:1736-1741` vs `:1936`, `:1264`, `:1384`, `:1165`, `:1722`, `:1904` | `showPreview = _isPreviewMode \|\| (_previewWhenKeyboardHidden && !keyboardVisible)` is computed inline and never shared; six sites test `_isPreviewMode` instead. With the setting on and a >3000-line note the editor is offstage and `_buildPreview` returns `SizedBox.shrink()` ⇒ **blank screen when the keyboard drops**; checkbox toggles in auto-preview wait 500 ms (never repaint on large notes); double-tap-to-source dead; replace field and vocabulary bar in the wrong state; the whole tap-interceptor surface is under `IgnorePointer` whenever the keyboard is down |
| B2 | `:430-441` vs `:1629` | `_pendingPosition` is set by the async position-service init and consumed only in the content-loaded listener; nothing orders them. Content-first ⇒ restore silently lost, and `_isPreviewMode` flips by a late `setState` with no `_pushPreviewContent` |
| B3 | `:503` (only in `initState`), `:2377` | `_loadEditorSettings` runs once; every editor flag edited on `settings_page.dart` (live rendering, line numbers, wrap, cursor line, auto-break, keyboard-preview, scroll-cursor, scrollbar, chunk size, stats bar, swipe) applies only after reopening the note. `_openMarkdownSettings` does not call `_refreshVocabularies` although the vocabulary flag/trigger live on that page (`markdown_settings_page.dart:1322,1327`) |
| B4 | `:97`, `:2036` | Editor `ValueKey` derives from `_liveMarkdownRendering`, default `true`, corrected asynchronously ⇒ users with live rendering OFF get the `CodeEditor` **remounted a frame after mount** — the mid-init remount the comment at `:2029-2035` says crashed the controller-delegate handoff |
| B5 | `:443-479` | `_loadFontSizes` / `_saveFontSizes` call `AppDatabase.getInstance().userSettingsDao` directly — the only Page→DAO call in the app; `SettingsService` has no font-size accessor. Also two DAO writes per +/- tap, undebounced |
| B6 | `markdown_editor_span_builder.dart:922` | `concealCount` bounds on `text.length` instead of `layout.contentEnd`; `*$^ 2*` conceals the space and leaves the count `2` visible |
| B7 | `packages/re_editor/lib/src/_code_paragraph.dart:722` | `_HangingParagraphImpl.height => content.height` discards a marker that may be up to 1.5× taller (`:593`); only the app's `0.85` checkbox clamp (`span_builder:1412`) prevents line overlap — a fix in the wrong layer |
| B8 | `_code_paragraph.dart:616` vs `:812-822` | Seam x differs by ≤1 px between affinities (`ceilToDouble`), contradicting the class doc at `:700-702`. Cosmetic |
| B9 | `_code_highlight.dart:71-73` | `clearCache()` clears the paragraph provider but not `_plainSpans` |
| B10 | `_code_find.dart:232-249` | `goToMatch` early-returns when `target == result.index`, so tapping the current match never re-centres |
| B11 | `modern_editor_wrapper.dart:117,124` | `shouldIntercept` and `onTap` both run `_resolveTapAction`, so the grammars run twice per claimed tap |
| B12 | `lib/models/dev_options.dart:61-65` | `showPreviewLineNumbers` is defined and shown in developer options but consumed nowhere |

### 1.3 Grammar divergences (same source, different render) — CONFIRMED

Root cause: emphasis/inline-code have no shared grammar module.
`markdown_editor_span_builder.dart:1487-1990` (`_appendInline`, `_matchRun`)
vs `line_based_markdown_builder.dart:2044-2160` (`_tryParseEmphasisAt`,
`_countRun`, `_findClosingBacktick`). Also
`modern_editor_wrapper.dart:444-483` (`_inlineCodeRuns`,
`_oddBackslashRunBefore`) is a **third** hand-rolled copy of the
inline-code + escape rules, with a comment admitting it must "mirror" the
builder.

| Input | Preview | Editor | Documented? |
|---|---|---|---|
| `___bold___` | bold+italic | bold `_bold_` + stray `_` (`:1764-1778` has no `___`) | no |
| ``` ``a`b`` ``` | CommonMark matched-length fence | single backtick only | no |
| `*a **b** c*` | italic `a **b` + literal | garbage (first non-space-preceded closer wins) | no (both wrong) |
| `###` (no trailing space) | H3 (`line_based:665`) | plain (`span_builder:349`) | partially |
| Bullet depth | `• ◦ ▪` cycling (`_bulletForLevel:950`) | always `•` (`:1356`) | no |
| Nested list indent | `level * baseFontSize` padding | raw spaces | no |
| Inline code size | 0.9× | 1.0× | no |
| Blank lines | 0.5× height | full height | no |
| GFM tables | rendered | raw pipes | no |
| Rule width | 40 `─` | source width | yes |
| Callouts | icon + label + band + continuation bar | lead-line token tint only | yes |
| Images, `\{{x}}`, inline currency word, H6 size, >4096 lines | — | — | yes |

Other renderer notes: `_maxInlineDepth = 3` (`:73`) silently flattens deeper
nesting (loses the code chip); `_matchRun` reads `text.length` / `pos-1`
outside its `[start,end)` range (`:1970,1983`), harmless today;
`_buildQuote`'s `while (codeUnitAt(gt) != 0x3E) gt++` (`:1243`) is bounded
only by `isBlockquoteLine`'s contract; `TextPainter.layout()` per money-row
cache miss (`:1065,1143`) is a native paragraph per keystroke on display
rows (bounded by the 128 positional LRU); shared static `Paint`s mutated in
`paint()` (`:2292,2366`). The roadmap doc names `_checkboxGlyphScale = 0.85`;
the code uses `MarkdownConstants.editorCheckboxScale = 1.05` (`:1411`).

**The code-unit invariant and the cache generation contract were traced
end-to-end and are sound** (every substitution is 1 unit, `Δ=`/`Δ~` narrow
to `Δ` at the only substitution site `:791-795`, every positional input is
either in the key or bypasses the memo, reveal never changes the root
fontSize). They are just unguarded.

### 1.4 Architecture

- **Page** (`optimized_note_editor_page.dart`, 2472 lines): ~50 mutable
  fields across 12 concerns; `_togglePreviewMode` (`:872-1035`) touches 7
  concerns, `_loadEditorSettings` 5, `_onTextChanged` 4. Five ambient async
  singletons resolved in `initState` (AppDatabase, SettingsService,
  NotePositionService, DevOptionsService, VocabularyService) with no
  injection seam ⇒ not widget-testable.
- **The live editor has no BLoC — correct.** A BLoC on the typing path would
  add an event-queue microtask per keystroke; `_contentController` already is
  the model. Do not add one.
- **`MarkdownPreviewBloc`** becomes near-dead after retirement: its only
  live-editor dependency is `state.linesPerChunk` for the chunk debug
  overlay (`:184, :2060`) and `chunkStartLineForLine` for the preview→editor
  return path (`:1000`).
- **Wrapper** (`modern_editor_wrapper.dart`, 761 lines): a controller in a
  widget's clothes — 622-743 is the tree, the rest is input policy (tap
  zones, checkbox mutation, a third inline scanner, ghost two-tap, Tab
  indent). The tap-interceptor / ghost re-arm ordering depends on
  innermost-first pointer dispatch and is patched with a microtask
  (`:128-131`). `initState` binds `widget.controller` with no
  `didUpdateWidget` (latent).
- **Span builder**: `_buildMoneyLine` is 522 lines (`:529-1050`) with two
  closures mutating a captured list; `_appendInline` is 391 lines of
  if-chain. `build()` needs a `BuildContext` only for `Theme.of`, which is
  what blocks pure-Dart tests.
- Listener order on `_contentController`: vocabulary `_refresh` → page
  `_onTextChanged` → wrapper `_onControllerChanged`; Enter-on-list rewrites
  the line and re-notifies, so the fan-out runs twice per Enter (guarded,
  just wasteful).

### 1.5 re_editor fork

- Base `dfbca60` (2026-01-19), post-0.8.0 upstream main, upstream last
  fetched 2026-02-27; `a0094dd` deleted `example/` and `test/`. Delta ≈
  +1,200 net lines; 58 % of it in `_code_paragraph.dart`/`code_paragraph.dart`
  (fork-owned), the rest smeared through `_code_field`, `_code_selection`,
  `code_lines`, `_code_highlight`, `code_editor`. ~60 % of the raw diff is
  `dart format` reflow.
- **Nested `.git` trap (corrected severity: Medium).** `packages/re_editor/.git`
  shows 33 modified files against its own HEAD, but the **outer repo tracks
  all 36 `lib/` files as ordinary blobs and its status is clean** — the fork
  source is safely in ANTA's history. The nested repo is stale noise that a
  `git checkout`/`stash` inside it would use to revert the working tree.
  Delete it or commit into it; do not leave it half-alive. (Session 0
  verified every claim here on 2026-09-03 and found nothing local-only — §3.)
- Zero asserts in `_code_paragraph.dart`, `_code_selection.dart`,
  `code_lines.dart`; zero tests. Four undocumented couplings the app relies
  on: root-span `fontSize` ⇒ line height (`_code_paragraph.dart:542-550`);
  placeholder height ≤ strut (`code_paragraph.dart:49-51`); per-segment
  backing-list identity as the dirty flag (`code_lines.dart:180-268` — sound,
  but mutating a stale `CodeLines` would corrupt the index silently);
  identity-keyed paragraph cache requiring identical span instances (a
  silent perf cliff if either memo is disabled).
- Tap interceptor: state machine is sound on mobile (long-press, ancestor
  scroll, second finger all reach cancel). Desktop: second claim steals the
  first; claimed pointer cannot drag-select; right-click during a claimed
  press moves the caret. `render` getter (`_code_selection.dart:38-39`) is an
  unchecked cast now on the every-tap-down path (SUSPECTED crash class,
  cf. upstream `b19f746`).
- `getRangeForSpan` double-counts nested spans (upstream bug, hover cursor
  only); `_dropPrefix:664` dead branch; empty `TextSpan(text:'')` children
  retained.

### 1.6 Tests

Zero references anywhere in `test/` to: `MarkdownEditorSpanBuilder`,
`MarkdownEditorLineIndex`, `LineBasedMarkdownBuilder`, `MarkdownChunker`,
`MarkdownListSyntax`, `GhostText`, `MarkdownLinkPatterns`,
`MarkdownTagSyntax`, `MarkdownColorSyntax`, `MarkdownCalloutSyntax`,
`ListAwarePasteController`, `PasteLineBreaker`, `EditorWidthCalculator`,
`OptimizedNoteEditorPage`, `CodeHangingTextSpan`, `CodeEditorTapInterceptor`,
`CodeLines`, `MarkdownPreviewBloc`, `MarkdownRenderService`,
`AutoSaveService`, `NotePositionService`. Only the money grammar is tested,
through its own module. `packages/re_editor/test` does not exist.

Testability today: `MarkdownEditorLineIndex` (takes `CodeLines`, no context)
and `MarkdownChunker` are pure; `LineBasedMarkdownBuilder` needs only a
hand-built `LineMarkdownStyle`; `MarkdownEditorSpanBuilder.build` needs a
`BuildContext` (widget test with `Builder`) until §3 Session 5 gives it an
`EditorRenderContext`; `_HangingParagraphImpl` is library-private and needs
a `@visibleForTesting` factory; `CodeLines` is public.

### 1.7 Accessibility

`describeSemanticsConfiguration` (`_code_field.dart:556-569`) declares a
text field with **no `SemanticsAction`** (no `onTap`, `onSetSelection`,
`onSetText`, no `textSelection`), so under TalkBack/VoiceOver the editor
cannot be focused and no checkbox/link/money zone is reachable — the
interceptor is pointer-only. Combined with P11 this is the editor's whole
screen-reader story.

### 1.8 What retiring the preview loses

Preview-only, by value for this app:

| Capability | Value | Editor feasibility |
|---|---|---|
| `#tag` tap → global search (`line_based:1308`) | **High** | Easy: one more interceptor zone from `MarkdownTagSyntax`; tags conceal nothing |
| GFM tables (`_buildTableRow:1661`) | Medium | Real alignment impossible under the invariant; ship "tables-lite" (monospace row, tinted pipes, dimmed separator row) |
| Callout icon/label/band + continuation bar | Medium | Icon = 1:1 substitution of `[`; band + continuation bar needs a positional `c:` pass in the line index (already on the roadmap) |
| Bare-URL tap-to-open | Medium | Easy, deliberately excluded (fully visible text ⇒ tap = caret); consider long-press |
| Select/copy rendered text (`SelectionArea`) | Low | Impossible under the invariant; copying source is arguably better |
| Image alt tap, half-height blank lines, 40-char rules, fence `// lang` label | Low | Keep raw / accept |
| Double-tap-to-edit, preview-when-keyboard-hidden, preview scroll persistence | — | Self-cancelling |

**Nothing renders markdown for export** — `ImportExportService` writes raw
text, so no share path is lost. But the **editor's single-note share/export
button is reachable only through the preview toolbar** (`markdown_bar.dart:350`,
page `:1923`, `_showExportFormatDialog:2106`); it must be re-homed.

Consumers of `LineBasedMarkdownBuilder` that must keep working, all
independent of `_isPreviewMode` and of the preview settings:
`simple_markdown_preview.dart:8` (used by `event_detail_sheet.dart:640`,
`event_editor_sheet.dart:1533`, `shortcut_editor_page.dart:1986`),
`markdown_inline_text.dart:126` (used by `agenda_list_view.dart:1174`,
`day_summary_panel.dart:77`). Retirable layer = `MarkdownPreviewBloc` +
`MarkdownRenderService` + `SourceMappedMarkdownView` + `PreviewScrollController`
(gated, not deleted). `MarkdownChunker` also feeds the editor debug overlay.

Unrelated keys that must not be touched: `showNotePreview` (folder-list note
snippet), `toolbarSplitEnabled` (toolbar layout).

---

## 2. Decisions needed from the owner

1. **Fork git**: delete `packages/re_editor/.git` (outer repo holds the
   truth; optionally push the current tree to `m0b-x/re-editor` on an `anta`
   branch first for provenance) — recommended — or commit into the nested
   repo and keep two histories. **Session 0 (2026-09-03) went with the
   recommended delete** — the nested repo holds nothing local-only (§3), so
   no `anta` branch was pushed; provenance (base commit, both remotes) is
   recorded in COPILOT_CONTEXT "Generated And Local Package Notes".
2. **Backup allow-list**: add `liveMarkdownRendering` and the new
   `previewModeEnabled` to `backup_service.dart:183-222`? Additive (old
   backups still import), but it is a backup-content change, so it is your
   call. Recommended: yes, in Session 2.
3. **Screen-reader value** (P11): bound the announced value to the visible
   lines / a size cap, or keep whole-document semantics and only throttle?
   Flutter's own `EditableText` announces the whole value, so bounding is a
   deliberate divergence. Recommended: visible-window value + actions.
4. **Lite rendering tier** (Session 10): only if the Session 1 benchmarks
   and a real-device profile say the hanging layout or variable line heights
   dominate. Do not build it speculatively.
5. **Wiki links `[[note]]`** (Session 9): wanted at all? It is the one
   genuinely new feature in the plan.

---

## 3. Slices by session

Each session: implement with Opus/Sonnet, end with `dart analyze lib`
(+ `dart analyze packages/re_editor/lib` when the fork is touched), the
named tests, and a device check. Every session updates
`live-markdown-editor-roadmap.md` (Done / Decision log) and the relevant
`COPILOT_CONTEXT.md` section. Sessions 1–3 are the critical path; 4–7 can
reorder; 8–10 are post-retirement.

### Session 0 — fork git safety (15 min, before anything else; needs decision 1)

- Resolve the nested `.git` per decision 1. Verify afterwards that
  `git status` in the outer repo is clean and `packages/re_editor/lib` is
  still tracked (`git ls-files packages/re_editor/lib | wc -l` = 36).
- Exit: no second history under `packages/re_editor`.

**2026-09-03 — DONE.** Findings and the removal:

- Verified before touching anything: the outer repo tracks all 49 files
  under `packages/re_editor` (36 in `lib/`) as mode-100644 blobs — no
  gitlink, no `.gitmodules` — and `git diff HEAD -- frontend/anta/packages/
  re_editor` is empty (the committed tree equals the working tree).
- The nested repo: HEAD `dfbca60` on `main` = `origin/main`
  (`https://github.com/m0b-x/re-editor.git`); `upstream` =
  `https://github.com/reqable/re-editor.git`, whose `main` had moved
  `8a7dbc5` → `28d9fc0` by 2026-09-03 (the range Session 7 evaluates).
  `git log --all --not --remotes` is empty, no stash, one worktree, no
  untracked files, 11 tags (v0.0.1–v0.6.0), 5.7 MB. Its 33 "modified" files
  are the fork delta (3,348+ / 2,224−), which exists only in ANTA's history.
  Deleting loses nothing; a clone of `m0b-x/re-editor` at `dfbca60`
  restores it.
- The agent's `rm -rf` (and a fallback `mv` out of the tree) were refused by
  the tool permission policy, so the owner ran
  `Remove-Item -Recurse -Force packages\re_editor\.git` from `frontend/anta`.
  Verified afterwards: `git` inside `packages/re_editor` resolves to the
  outer repo, `git status --porcelain` shows only the docs entries,
  `git ls-files packages/re_editor/lib | wc -l` = 36 (49 for the whole
  package), `git diff HEAD -- frontend/anta/packages/re_editor` is empty, and
  no `.git` remains anywhere under `frontend/anta`. Exit criterion met.

### Session 1 — safety net + the cheapest structural win

Goal: make every later change measurable and guarded; land the one-line
fix that removes 40–65 ms from Enter/toggle/open/paste.

1. `test/utils/code_lines_sharing_test.dart` (pure Dart, fork public API):
   `CodeLines.from` shares every segment list by identity; one `[]=` changes
   exactly one segment's identity; `add`/`addAll`/`addFrom`/`sublines`
   preserve the others; no segment exceeds 256; `lineCount`/`charCount`
   agree with a naive fold after every mutation (this pins P1's fix).
2. `test/utils/markdown_editor_line_index_test.dart` (pure Dart): build a
   >600-line `CodeLines` training log (lists, tasks, fences, money rows);
   apply seeded random edits at and around 255/256/257/511/512 (edit-in-
   place, Enter, delete-line, fence toggled mid-document); after each, compare
   `fenceRoleAt`/`taskIndeterminate`/`moneyValueAt` of the incremental index
   against a fresh index on the same `CodeLines` for every line.
3. `test/utils/markdown_editor_span_builder_units_test.dart` (widget test:
   `pumpWidget` + `Builder` for the context; bind a real
   `CodeLineEditingController`): corpus of ~60 lines (every construct in
   §1.3 plus money kinds, ghosts inside emphasis/links, escapes, fences,
   >4096 raw, surrogate pairs, tabs) × reveal on/off × money on/off:
   `span.toPlainText(includePlaceholders: true).length == line.length` and
   code-unit equality after mapping known 1:1 substitutions back; identical
   instance on a repeat build (memo); root fontSize identical between reveal
   states.
4. `test/utils/markdown_chunker_test.dart`: block alignment (no chunk splits
   a fence/callout), unterminated fence to EOF, `chunkStartLine`/
   `chunkIndexForLine` round-trip, `adaptiveChunkSize` cap 100.
5. `test/services/auto_save_service_test.dart` (FakeAsync): debounce
   coalescing, 30 s interval, `forceSave` awaiting in-flight, retry ladder
   capped at 3, status transitions, no-op when unchanged.
6. Benchmarks (tag `benchmark`, skipped by default, same shape as the DB
   suite): `CodeLines.of` of 10k list lines; line-index keystroke cost with
   the edited segment at k ∈ {0, 20, 39}, money on/off; span build of 40
   cold list lines. Record baseline numbers in this doc.
7. **Fix P1**: in `_CodeLineSegmentQuckLineCount` maintain `_lineCount`/
   `_charCount` incrementally in `add`/`[]=`/`length=` (subtract old, add
   new) instead of re-folding. Re-run benchmark 6 and record.
8. **Fix P4 (guards only)**: equality guard on autosave `onChangeDetected`;
   move the stats bar and app-bar dirty dot onto `ValueNotifier`s +
   `ValueListenableBuilder` so `_updateCachedStats` / `_hasChanges` /
   `_onContentFocusChanged` stop rebuilding the page.
9. Add a debug `assert` in the span builder's `_emit`/`_emitClamped` path
   that spans appended for `[start,end)` total `end-start` code units.

Exit: all new suites green; benchmark file exists with before/after for P1;
no behaviour change visible to the user.

**Outcome — DONE 2026-09-03, uncommitted.** Full suite 2236 passing (6
benchmark cases skipped by default); `dart analyze lib` and
`dart analyze packages/re_editor/lib` clean. What landed, item by item:

1. `code_lines_sharing_test.dart` — 16 tests. Identity is observable through
   public members (`CodeLines.segments[i].codeLines`), so no
   `@visibleForTesting` hook was needed; the identity that matters is the
   **backing list**, not the segment object (`CodeLines.from` builds fresh
   dirty segments that share lists). `CodeLines` itself has no `removeAt`/
   `insert`/`length=` — those live on `CodeLineSegment`; `insert` is unusable
   (`ListMixin.insert` grows a non-nullable list and throws) and is not
   pinned. `sublines` shares whole segments and copies partial ones.
2. `markdown_editor_line_index_test.dart` — 25 tests, ~700-line corpus,
   seeded edits through the real controller (`selection` + `edit`,
   `applyNewLine`, `deleteSelectionLines`). **No divergence found.** Guard
   test pins that a same-line `edit` changes exactly one segment's list
   identity — without it the suite would silently exercise only
   `_rebuildAll`. Enter and delete-line are structural and always fall back
   to `_rebuildAll` (P2 territory); `applyNewLine` re-indents the split tail.
3. `markdown_editor_span_builder_units_test.dart` — 118 corpus lines × money
   off/on × reveal off/on + memo re-builds = 472 builds. **No invariant
   failure**, including `*$^ 2*` (B6 is visual only: every unit is still
   accounted for). Fence lines ignore reveal by design (branch precedes
   `selectionCoversLine`, memo key `d:`/`i:` + text). The 1:1 substitution
   table (`•`, `┃`, `─`, `Σ`, `◎`, `Δ`, `−`, `×`, `÷`, error `!`, U+FFFC for
   checkbox/money chip/label-first `:`) lives in the test's `_visible()`.
4. `markdown_chunker_test.dart` — 43 tests. Correction to the plan: fences
   and callouts are emitted `atomic: false` on purpose, so a block that
   straddles a chunk target **is** bisected (safe: fence styling is
   positional via `_lineInCodeFence`). The pinned contract is "a block that
   fits inside a chunk's window is never split". `chunkStartLine`/
   `chunkIndexForLine` live on `LineBasedMarkdownBuilder`, not the chunker.
5. `auto_save_service_test.dart` — 36 tests. Found and fixed a real crash:
   `_updateStatus` had no `_disposed` guard, so a `forceSave` still awaiting
   the DB when the page was popped threw "ValueNotifier used after being
   disposed" on completion, then threw again from the `catch` (reachable
   from `_saveOnLifecycleEvent` and the preview toggle). One-line guard
   added; the test is live, not skipped. Retry ladder is 1 initial + 3
   retries at 2/4/8 s. `fake_async` was promoted to a direct dev dependency.
6. Three benchmark files (`code_lines_benchmark_test.dart`,
   `markdown_editor_line_index_benchmark_test.dart`,
   `markdown_editor_span_builder_benchmark_test.dart`); numbers in §5.
7. **P1 fixed** in `_CodeLineSegmentQuckLineCount`: `add`/`[]=`/`length=`
   maintain the counts by delta; `addAll`/`addFrom`/`removeAt`/`removeLast`
   route through those three via `ListMixin`. Also a full-range `clone`
   override carries the cached counts instead of re-folding through
   `CodeLineSegment.of` — that is the per-keystroke `from()`+`[]=` path.
   `[]=` reads the old element before `super[]=` so a dirty-segment write
   still throws `UnimplementedError` with counters intact (tested).
8. **P4 guarded**: `_hasChanges` and the stats pair became
   `ValueNotifier<bool>` / `ValueNotifier<NoteEditorStats>` (a record, so
   equality is structural) in `lib/widgets/note_editor_chrome.dart`
   (`ValueListenableAppBar`, `NoteEditorStatsBar`); four whole-page
   `setState`s on the typing path are gone (autosave `onChangeDetected`,
   `_onTextChanged`, `_updateCachedStats`, the content-loaded stats write).
   `_onContentFocusChanged` keeps its guarded `setState` because
   `_contentHasFocus` gates keyboard-inset layout and the preview swap. One
   deliberate delta: the checkbox toggle and search-replace paths now
   repaint the dirty dot immediately instead of on the next unrelated
   rebuild. `isLargeNote` in `_buildPreview` reads the stats notifier
   without listening (mode switches already `setState`).
9. `_emit` is a checked wrapper over `_emitRange`; the assert counts
   appended units (placeholders = 1) inside `assert(() {...}())`, zero
   release cost. Proven live: `end - start + 1` fails 103/118 cases.

Test traps for later sessions: `toPlainText` needs `includePlaceholders:
true` or paint spans vanish; reveal-off must park the caret on a padding
line 0 (a collapsed `(0,0)` selection covers line 0); `configureMoney` on a
warm builder clears memos, so use a fresh builder per money state; the units
test contains a literal U+FFFC (grep treats it as binary, Edit cannot match
it); `debugPrint` under `FakeAsync` schedules real timers — swap it for a
no-op in `setUp`; `$` in money fixtures needs raw strings.

### Session 2 — retire the preview (the owner's ask) + editor tag tap

Goal: preview off by default behind "Deprecated features", editor is the
only default surface, nothing user-visible lost.

1. `SettingsKeys.previewModeEnabled = 'preview_mode_enabled'`, default
   `false` (name the feature, not "deprecated", so un-deprecating never
   churns storage). `SettingsService.getPreviewModeEnabled/set…`.
2. `settings_page.dart`: new `_sectionDeprecated = 'deprecated'`, last in
   `_buildSections`, standard `SettingsSectionData` with an `intro`; first
   row = the master toggle; move `previewWhenKeyboardHidden`,
   `showPreviewScrollbar`, `previewLinesPerChunk` into it (disabled while the
   master is off); delete `_previewSection`/`_sectionPreview`; extend
   `_resetToDefaults`. Keywords via the inline `keywords:` arg (no static
   index exists).
3. Editor page: load the flag in `_loadEditorSettings`; compute
   `canPreview = _previewModeEnabled || !_liveMarkdownRendering` (the
   `event_editor_sheet.dart:1426` precedent — with live rendering off the
   raw editor still needs a way to see rendered output). Gate: AppBar eye
   toggle, `_togglePreviewMode` early return, `_buildPreview`,
   `_pushPreviewContent` and `_scheduleLivePreviewRefresh` (no preview
   prepare on open when `!canPreview` — this also removes P9's synchronous
   prepare for everyone on the default path), `_previewWhenKeyboardHidden`
   forced false when `!canPreview`.
4. **Fix B1 while here**: compute one `showPreview` value once per build
   (or a getter over the last-known keyboard state) and pass it to
   `_buildPreview`, `_handleCheckboxToggle`, `_handleDoubleTapLine`,
   `_navigateToSearchMatch`, `NoteSearchBar.showReplaceField`,
   `MarkdownBar.isPreviewMode`.
5. Persisted positions: `_initializePositionService` applies
   `_isPreviewMode = canPreview && position.isPreviewMode`;
   `_restoreSavedPosition` skips the progress branch when `!canPreview`.
   No DB migration, no bulk rewrite (`note_position_*` rows self-heal on the
   next save and are not in backups).
6. **Share button**: `markdown_bar.dart:350` currently shows share only in
   preview; show it whenever `onShare != null` regardless of mode (utility
   section), so `_showExportFormatDialog` stays reachable.
7. **Editor tag tap → search**: add a tag zone to the wrapper's
   `_resolveTapAction` from `MarkdownTagSyntax` (same pass-through rules as
   links: reveal lines, fences, >4096, ghosts win), `onOpenTag` wired to the
   page → `AppNavigator.toSearch` with `#` preserved, `selectionClick`
   haptic. Decision log: tags are now tappable off-caret in the editor.
8. l10n en/de/ro: `deprecatedSection`, `deprecatedSectionIntro`,
   `previewModeEnabled`, `previewModeEnabledDesc`, `previewModeKeywords`;
   reword `appSettingsDesc` (drops "and preview") and `autoBreakLongLinesDesc`.
   `flutter gen-l10n`, check `untranslated.txt`.
9. Backup allow-list per decision 2. Remove dead `showPreviewLineNumbers`
   (B12) or wire it; remove is recommended.
10. Tests: `test/services/note_position_service_test.dart` (round-trip,
    `isPreviewMode` default on malformed JSON); `SettingsService` default for
    the new key; `MarkdownBar` exposes share outside preview mode; a
    tag-zone unit case in the tap-zone table (Session 6 extracts the pure
    resolver — until then, a widget test over `ModernEditorWrapper`).

Exit: fresh install never sees the eye button; existing install with a
note saved in preview mode opens in the editor; live-rendering-OFF users
keep the toggle; share works from the editor; tag tap searches. Docs:
roadmap "Done" + decision log; COPILOT_CONTEXT "Markdown Preview Pipeline"
gets a "deprecated, gated by `previewModeEnabled`" header.

**Outcome — DONE 2026-09-03, uncommitted.** Full suite 2264 passing;
`dart analyze lib` clean; `untranslated.txt` empty. Decision 2 was taken as
**yes** (additive, backup version stays 7). Item by item:

1. `SettingsKeys.previewModeEnabled` / `defaultPreviewModeEnabled = false`,
   `SettingsService.getPreviewModeEnabled` / `set…`.
2. `settings_page.dart`: "Deprecated features" section last, intro line,
   master toggle first, the three preview rows moved under it and greyed +
   disabled (`_switchRow`/`_sliderRow` gained `enabled`) while the master is
   off; old preview section deleted; reset-to-defaults covers the key.
3. Page: `_previewModeEnabled` loaded in `_loadEditorSettings`;
   `_canPreview = _previewModeEnabled || !_liveMarkdownRendering`; gated:
   eye button, `_togglePreviewMode`, `_buildPreview` (`SizedBox.shrink`),
   `_pushPreviewContent` (single choke point), `_scheduleLivePreviewRefresh`
   (before `markContentDirty`), `_previewWhenKeyboardHidden` forced false.
   `MarkdownPreviewBlocView` never mounts when `!_canPreview`, so no theme
   reaches the bloc and no prepare ever runs — P9 is gone from the default
   path.
4. **B1 fixed**: `_showPreview` getter = `_canPreview && (_isPreviewMode ||
   (_previewWhenKeyboardHidden && !_lastKeyboardVisible))`, where
   `_lastKeyboardVisible` is assigned once at the top of `build`; used by
   `_buildPreview`, `_handleCheckboxToggle`, `_handleDoubleTapLine`,
   `_navigateToSearchMatch`, `NoteSearchBar.showReplaceField`,
   `MarkdownBar.isPreviewMode` + `previewFontSize`, `_adjustFontSize`,
   `_scrollToEdge` (same bug class, not in the original list) and the
   Offstage/`IgnorePointer` pair. `_isPreviewMode` stays where it means the
   persisted mode (`_onPreviewProgressChanged`, `_saveCurrentPosition`, the
   toggle itself, the AppBar icon). Side effect: double-tap-to-source and
   ghost tap now work under auto-preview because focusing raises the
   keyboard, which flips `_showPreview`.
5. Positions: `_isPreviewMode = _canPreview && saved` is derived in
   `_initializePositionService` **and** re-derived by
   `_applySavedPreviewMode()` after settings load (whichever lands last
   wins; a late reveal seeds the preview with the current text).
   `_initializePositionService` deliberately does not await settings —
   that would widen B2's race. `_restoreSavedPosition` takes the progress
   branch only under `_canPreview`.
6. `markdown_bar.dart`: share shows whenever `onShare != null`; the four
   other `MarkdownBar` call sites pass no `onShare`.
7. Editor tag tap: `ModernEditorWrapper.onOpenTag(String tag)` zone from
   `MarkdownTagSyntax` with the link zone's pass-through rules (reveal line,
   fence, >4096, ghosts win; a heading line taps its `#tag`, never its
   hashes); page wires `onOpenTag: markdownRendering ? _handleTagTap : null`
   — the same handler the preview uses (`AppNavigator.toSearch(query: tag)`
   after saving the position).
8. l10n: `deprecatedSection`, `deprecatedSectionIntro`, `previewModeEnabled`,
   `previewModeEnabledDesc`, `previewModeKeywords`; `appSettingsDesc` and
   `autoBreakLongLinesDesc` reworded; `showPreviewLineNumbers*` strings
   removed; `previewSection` left in the ARBs unused.
9. Backup allow-list gained `liveMarkdownRendering` + `previewModeEnabled`
   (round-trip tested, stripped-key import tested). **B12 done**:
   `showPreviewLineNumbers` removed from `DevOptions` and the developer
   options page; a persisted value is ignored.
10. Tests: `test/services/preview_mode_setting_test.dart` (4),
    `backup_service_editor_settings_round_trip_test.dart` (2),
    `note_position_service_test.dart` (9 — note: a non-bool `isPreviewMode`
    in stored JSON drops the whole position to default, caret included;
    documented, not changed), `test/widgets/markdown_bar_share_test.dart`
    (4), `test/widgets/modern_editor_wrapper_tag_tap_test.dart` (9).

**Follow-up the same day (owner: "no leftovers before the commit").**

- **B2 fixed**: `_initializePositionService` now calls
  `_restoreSavedPosition()` itself after storing `_pendingPosition`, and
  the content-loaded listener still does — last one wins, and the
  `_pendingPosition = null` on consume keeps it single-shot. The editor
  branch (line/column + `makeCenterIfInvisible`) and the preview branch
  were both being lost when content landed first; neither is a fork issue.
- **B3 fixed**: the page is `RouteAware` on `AppNavigator.routeObserver`
  (the calendar page's pattern). `_loadEditorSettings` and a new
  `_reloadEditorSettings` share `_applyEditorSettings(initial:)`;
  `didPopNext` runs the reload, which re-reads every flag but deliberately
  does **not** call `_applySavedPreviewMode` (that would undo a toggle made
  during the session) and only forces the preview off when `_canPreview`
  just became false. Toggling live rendering on the settings page remounts
  the editor on return via its `ValueKey`, as intended. Sheets are
  `PopupRoute`s and do not trigger it. `_openMarkdownSettings` now also
  calls `_refreshVocabularies`.
- **B11 fixed**: `ModernEditorWrapper` memoises the tap-down claim
  (`_TapClaim`: index, offset, line text, selection, fence flag, action);
  `_consumeTapAction` at tap-up reuses it when none of those moved and
  re-resolves otherwise; the memo is dropped either way so an abandoned
  claim can never fire later.
- `NotePositionData.fromJson` falls back per field on malformed values
  instead of dropping the whole position (caret included).
- The unused `previewSection` ARB key is gone from all three locales.
- Tests: `test/widgets/optimized_note_editor_page_test.dart` (5 — the first
  page-level test: content-before-position, position-before-content,
  single-shot restore, no saved position, B3 flag picked up on pop);
  `modern_editor_wrapper_tag_tap_test.dart` 9 → 11 (one grammar pass per
  claimed tap via `ModernEditorWrapper.debugTapResolveCount`);
  `note_position_service_test.dart` 9 → 11. Whole suite 2273 passing.
- **Page-test harness, reuse it** (Session 6 will need it): temp dir +
  `SharedPreferences.setMockInitialValues` + a mock `path_provider`
  channel make `AppDatabase.getInstance()` real, so every service binds to
  one in-memory-backed DB and nothing below the service layer is faked.
  Build services and BLoCs in `setUpAll`, never inside `testWidgets` —
  drift's `createInBackground` deadlocks under `FakeAsync`; DB writes go
  through `tester.runAsync`. Close BLoCs in `tearDownAll`, not per test
  (the page dispatches to `CounterBloc`/`MarkdownBarBloc` from `dispose`
  and the binding unmounts leftovers at the start of the next test).
  `_TestNoteBloc` swallows `LoadNoteContent` and exposes
  `emitContentLoaded`/`reset()` so the test owns when content lands;
  `find.byType(..., skipOffstage: false)` once a route is pushed above.
- Pre-existing flake seen once under full-suite load:
  `test/database/event_occurrence_crdt_test.dart` "stamping an edit …
  moves the HLC" (two writes on one HLC stamp); passes standalone.
- Test trap (fork): `_CodeCursorBlinkController.startBlink` schedules an
  unguarded 100 ms `Future.delayed` on mobile platforms, so a widget test
  that mounts the editor must flush ~200 ms while the tree is alive before
  pumping it away; a pass-through tap moves the caret and turns that line
  into the reveal line, so re-park the caret before the next "does fire"
  assertion. No settings-gated haptic helper exists — all four editor tap
  zones call `HapticFeedback` directly.

### Session 3 — structural-edit performance (Enter, toggle, index)

Goal: Enter on a list line and a checkbox toggle cost O(one segment), not
O(document); the index never rescans an unchanged suffix.

1. Fork helper `CodeLines.replaceLine(int index, CodeLine line)` built on
   `CodeLines.from` + segment `[]=` (clone-on-write keeps every other
   segment's identity). Guarded by the Session 1 sharing test.
2. **P2**: `_handleTextChange` (page `:1509`) and `_toggleTaskLine`
   (wrapper `:392`) use it instead of `CodeLines.of([...])`. Keep the
   undo-merge semantics (direct `value =` for Enter continuation,
   `runRevocableOp` for the toggle) and the selection-untouched contract.
3. **P3**: give `_scanTasks` and `_scanMoney` a suffix proof mirroring
   `_scanFence`: stop when re-entering an unchanged segment whose recomputed
   entry state equals the stored snapshot (task: frame stack + result count;
   money: balance + history length + anchor length + period start + target
   scalars). State flows strictly downward, so equal entry state ⇒ identical
   suffix. The Session 1 equivalence test must stay green; add seam cases
   where the entry state changes vs. stays equal.
4. **P5**: in `build()`, consult the positional memo before running
   `MarkdownMoneySyntax.parse` (key on text + balance as today), or memoize
   `parse` behind a small text-keyed LRU.
5. **P8**: cap `_CodeLineEditingCache` at N nodes (e.g. 200), evicting the
   oldest.
6. Drop the redundant `maxScannedLineLength` guard for the money pass
   (`parse` already guards at 4096) or keep and document — one of the two.

Exit: benchmarks show Enter/toggle no longer proportional to document size;
index keystroke cost at k=0 ≈ k=39; equivalence test green.

### Session 4 — one inline grammar for both surfaces

Goal: emphasis / inline-code / escape rules live in one module; the three
scanners consume it; the §1.3 divergences disappear.

1. New `lib/utils/markdown_inline_grammar.dart`: pure tokenizer over a
   `[start,end)` range returning `InlineToken{start,end,kind,innerStart,
   innerEnd}` with CommonMark-ish flanking (`canOpen/canClose`, delimiter
   runs, matched-length backtick fences, `___`), ghost- and escape-aware
   (ghost regions opaque; odd backslash run escapes). Port
   `_tryParseEmphasisAt`/`_countRun`/`_findClosingBacktick` from the preview
   as the reference behaviour.
2. Preview `_parseInline` and editor `_appendInline` consume tokens and keep
   their own emission (drop vs conceal). `_matchRun` deleted.
3. Wrapper `_inlineCodeRuns` / `_oddBackslashRunBefore` deleted in favour of
   the module; `_linkUrlAt` uses it.
4. Heading detection: single predicate (`#…` + space-or-EOL) shared by both
   (`###` alone becomes a heading in the editor, matching the preview).
   Horizontal-rule regex single-sourced.
5. Fix B6 (`concealCount` vs `contentEnd`). Raise `_maxInlineDepth` or make
   flattening explicit.
6. Tests: `test/utils/markdown_inline_grammar_test.dart` (the §1.3 inputs +
   the roadmap's known-good cases: `***x***`, `**a *b* c**`, `_a_b_`,
   snake_case, unmatched openers, markers at EOL, `[#tag](url)`,
   `**[a](b)**`, `\*`, emphasis across a ghost); a preview-vs-editor
   agreement corpus (both surfaces classify each line identically); the
   Session 1 code-unit suite stays green.

Exit: `___`, multi-backtick and `*a **b** c*` render identically on both
surfaces; wrapper has no grammar of its own.

### Session 5 — span builder decomposition + fork paragraph hardening

Goal: the renderer is pure-Dart testable, the fork's paragraph layer
enforces its contracts, list-line layout is cheaper.

1. `EditorRenderContext{style, baseColor, primary, isDark, onAccent, palette,
   moneyConfig}` replaces `BuildContext` inside the builder; the page builds
   it once per generation. Session 1's widget-test suite becomes pure Dart.
2. Split `markdown_editor_span_builder.dart` (no behaviour change):
   `markdown_editor_emitter.dart` (`_emit`/`_emitClamped`/`_plainSpan`/
   conceal+dim styles + the Session 1 assert), `markdown_editor_money_row.dart`
   (`_buildMoneyLine` and helpers), `markdown_editor_span_cache.dart` (two
   LRUs + generation key), `markdown_editor_paint_spans.dart` (the three
   `CodeInlinePaintSpan` subclasses). `build()` becomes ~40 lines of routing.
3. Fork: `_HangingParagraphImpl.height = max(marker.height, content.height)`
   (B7); assert root style differs from base only in `fontSize`; assert
   placeholder height ≤ strut; bail out of `_buildHanging` when `maxWidth`
   is infinite (wordWrap off); cache marker measurement per
   `(markerText, fontSize)` (P6); `clearCache` also clears `_plainSpans`
   (B9); fix `goToMatch` re-centre (B10); remove `_dropPrefix` dead branch
   and empty children; document the seam ±1 px (B8) or fix with `floor`.
4. `@visibleForTesting` factory for the hanging paragraph +
   `test/re_editor/hanging_paragraph_test.dart`: `getPosition(getOffset(p))
   == p` for every offset; `getRangeRects` covers marker + rows in visual
   order with no gaps; `height >= marker.height`; `trucate`/`_dropPrefix`
   identity + `marker.toPlainText() + content.toPlainText() ==
   span.toPlainText()` for every split.
5. Benchmark 6 (40 cold list lines) before/after the marker cache.

Exit: no `BuildContext` in the renderer; fork asserts fire in debug on
contract violations; scroll benchmark improved.

### Session 6 — editor page controllers

Goal: settings apply without reopening, restore is deterministic, no
Page→DAO, no remount-on-open, paste is incremental.

1. `EditorSettingsController` (plain `ChangeNotifier`, page-owned): the
   nine editor flags + toolbar ratio/split/utilities + `linesPerChunk`;
   `reload()` reads `SettingsService` in one pass; called in `initState` and
   after every settings push (await-then-reload at each push site, matching
   `_openMarkdownSettings`); `_refreshVocabularies` included (B3).
2. First `CodeEditor` mount waits for `reload()` (the loading skeleton
   already exists) so the `ValueKey` is stable (B4).
3. `SettingsService.get/setEditorFontSize`, `get/setPreviewFontSize`;
   delete the DAO calls; debounce writes; only write the size that changed
   (B5).
4. `NoteEditorPositionController`: owns `_pendingPosition`,
   `_savedEditorSelection`, timers; `restoreWhenReady()` joins the position
   future and the content-loaded event explicitly (B2). Widget test: content
   before position, position before content — both restore.
5. `EditorInputPolicy` extracted from the wrapper: `_resolveTapAction`
   (pure half: line text + offset → action), ghost engagement state machine,
   Tab/Shift-Tab. Table test of every pass-through rule (reveal, fence,
   >4096, offset ≥ length, link boundaries, `![img]`, `\[`, code runs, ghost
   wins, money display zones, tag zones). Run `_resolveTapAction` once per
   claimed tap (B11). Add `didUpdateWidget` rebind.
6. **P7**: `PasteLineBreaker` splices only the pasted range through
   `CodeLines` mutation (no `controller.text` + `join` + `.codeLines`);
   pre-filter `measureTextWidth` by character count.
7. Leave `MarkdownPreviewBloc` in place (deprecated mode still uses it) but
   construct its render work lazily behind `canPreview`.

Exit: page State under ~25 fields; toggling any editor setting on the
settings page applies on return; restore never lost; `flutter test` green.

### Session 7 — accessibility + fork tests + upstream evaluation

1. Semantics per decision 3: bounded `value` (visible window or size cap)
   and a throttle so P11 cannot stall typing; add `onTap`/`onSetSelection`/
   `onDidGainAccessibilityFocus` actions so the editor can be focused and
   the interceptor zones become reachable (an a11y tap on a zone should
   perform the same action as a pointer tap).
2. `render` getter null-safety on tap-down (SUSPECTED crash class).
3. Desktop interceptor: refuse a second claim while one is live; allow
   drag-select to start from a zone (or document that it can't).
4. `test/re_editor/tap_interceptor_test.dart` (widget test over a real
   `CodeEditor`): claim→cancel via long-press; claim→pointer-cancel;
   claim→up fires once and leaves `selection` identical; two consecutive taps
   both fire; a claimed tap never focuses.
5. Paragraph cache identity fast path test: same span instance twice ⇒
   identical `IParagraph`, `hashCode` never invoked (counting subclass).
6. Upstream: fetch `reqable/re-editor`, format the base commit with the
   same `dart format` to get a semantic diff, list upstream fixes since
   `8a7dbc5` worth cherry-picking, write the fork delta as a patch list in
   `re-editor-performance-2026-07.md` (or a new "fork delta" section there).
   Cherry-pick only bug fixes; no API changes.

### Session 8 — rendering parity features

1. Bullet glyph by depth (`•`/`◦`/`▪` from `item.level`, 1:1, text-keyed).
2. Callout blocks: a positional `c:` pass in `MarkdownEditorLineIndex`
   (same lazy pattern as fences), continuation lines get the accent bar,
   lead line gets the icon via a 1:1 substitution of `[` with a painted
   glyph; band background only if the empty-line striping problem has a fix
   (an empty line cannot paint a background — same reason the fence tint
   was dropped). Extend the equivalence test.
3. Tables-lite: rows matching `_MarkdownPatterns.tableRow` render monospace
   with tinted `|`; separator rows dimmed. No alignment.
4. Nested `>>` quote depth (1:1 per `>`); inline code 0.9× only if it does
   not change line height (it must not — root fontSize rule).

### Session 9 — wiki links `[[note]]` (decision 5)

Same conceal pattern as `[text](url)`: `[[` and `]]` concealed off-caret,
title tinted; tap zone via the interceptor → resolve title through
`NoteRepository` (filter `isDeleted`, like the calendar's linked-note
resolution) → `AppNavigator`; unresolved titles muted. Preview: add the
token to the shared link grammar so `SimpleMarkdownPreview` renders it too.
Grammar in `MarkdownLinkPatterns`. Tests: grammar + tap-zone table +
navigation.

### Session 10 — lite rendering tier (conditional, decision 4)

Only if profiling on the target device (see §5) shows the hanging layout or
variable line heights dominate. Setting under Editor ("Reduced rendering
for slow devices"): headers bold at base size (uniform line height ⇒ no
`correctBy` storms, no backward walk), single-paragraph list lines, money
display rows plain. None of it touches the code-unit invariant.

---

## 4. Deferred / rejected

- **Ordered-list renumbering as a render** — rejected: `9.`→`10.` changes
  the unit count. Only viable as an Enter-continuation edit.
- **Heading folding** — high value for long logs but needs a `CodeLines`
  view in the fork that hides lines; large; revisit after Session 7's
  upstream evaluation.
- **Inline images** — a thumbnail must substitute exactly one source char
  and makes reveal/edit awkward; keep raw.
- **Select/copy rendered text**, **half-height blank lines**, **40-char
  rules** — impossible or pointless under the invariant.
- **A BLoC for the live editor** — wrong layer for per-keystroke state.
- **Deleting the plain-text (live rendering OFF) path** — it is the escape
  hatch and the A/B baseline; keep.

---

## 5. Measurement recipe

- DevTools Timeline: `LAYOUT`/`PERFORMLAYOUT` under `_CodeFieldRender` vs
  `PAINT` and raster in the frame chart; wrap `_buildHanging` in
  `Timeline.timeSync('hangingBuild')`; count `ViewportOffset.correctBy`
  calls and `_updateDisplayRenderParagraphs` re-entries per frame.
- `adb shell dumpsys gfxinfo com.alexzamfir.anta framestats` during (a)
  typing on a 10k-line list note with the caret near the top, (b) a
  header-heavy fling, (c) a 500-line paste.
- `adb shell dumpsys meminfo com.alexzamfir.anta` with the paragraph cache
  at 512 vs 128 while scrolling a 10k-line note.
- The Session 1 benchmark file for the pure-Dart costs (`CodeLines.of`,
  index keystroke at k ∈ {0,20,39}, 40 cold list lines).

Baseline numbers (Session 1, 2026-09-03, debug-mode Dart VM on the owner's
Windows box — compare only against re-runs on the same machine; run with
`flutter test --tags benchmark --run-skipped <file>`):

`CodeLines` (`code_lines_benchmark_test.dart`, 10k lines of
`- [ ] squat 5x5 @100kg`, best of 3):

| Operation | Before P1 | After P1 |
|---|---|---|
| `CodeLines.of` (10k lines) | 14,335 µs | 375 µs |
| `add` one line, per op | 1.73 µs | 0.32 µs |
| `from()` + `[]=` mid-doc, per op (keystroke shape) | 6.49 µs | 0.90 µs |
| `[]=` mid-doc in place, per op | 2.78 µs | 0.07 µs |

Line index (`markdown_editor_line_index_benchmark_test.dart`, 10,240 lines
= 40 full segments, 200 keystrokes, µs per keystroke; `index` = `_ensure`
plus a 40-line visible-window query on all three passes; `mutate` is the
P1 surface):

| money | k | mutate | index |
|---|---|---|---|
| off | 0 | 4.4 | 159.5 |
| off | 20 | 3.3 | 82.1 |
| off | 39 | 1.5 | 20.6 |
| on | 0 | 2.4 | 236.8 |
| on | 20 | 1.9 | 125.9 |
| on | 39 | 1.3 | 23.1 |

Cold full index build: 181–375 µs. The k gradient is P3 exactly — cost is
linear in the segments *below* the caret (≈8× top vs bottom, ≈11× with
money); after Session 3's suffix proof the k=0 row should approach k=39.

Span builder (`markdown_editor_span_builder_benchmark_test.dart`, 40 list
lines × 40 passes; cold = both span memos cleared by alternating
`configureColors`, index left warm):

| Path | per pass | per line |
|---|---|---|
| cold | 476.8 µs | 11.9 µs |
| warm (memo hit) | 73.7 µs | 1.8 µs |
