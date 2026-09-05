# Live Markdown Editor — Review & Consolidation Slices (2026-09-03)

**Status: Sessions 0–7 DONE (§3; 7c on 2026-09-05). Sessions 0–1 are committed as
`38c7b50`, Session 2 and its same-day follow-up as `c716225`, Session 3 as
`a183f11`, Session 4 as `1ed4a60`, Session 5 as `4cad6ec`, Session 6 as
`b5fcdbd`, Session 7a as `fcfe704` (sync) + `72401b8` (format) +
`684b553` (ownership rule), Session 7b as `d9621bb`, Session 7c as
`3866ef2`, `e403a35`, `12dad1e`, `f602056`, `be24f73`, `8cb585d` plus
`b1da783` (docs). Session 7 was re-sized against the
code and split into 7a/7b/7c on 2026-09-04, all three now shipped and
reviewed (2026-09-05, see the review block under Session 7); Sessions
8–9 and 11 PLANNED, not implemented; Session 10 DROPPED (decision 4). All six §2
decisions are taken (6, fork ownership, added 2026-09-04).** Baseline commit `bf2e7ba`
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
whole-page `setState`s. **As of the 2026-09-03 review — all three closed
since (Sessions 0, 1, 5, 7a):** the fork's additions are well-built but have zero
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

- Base `dfbca60` = `8a7dbc5` (merge-base of `m0b-x/main` and `reqable/main`)
  + `a0094dd` (deleted `example/` and `test/`) + `dfbca60` itself
  ("re-activated cursor on android", fork-only). Evaluated 2026-09-04
  against upstream HEAD `28d9fc0` (2026-08-21, unchanged since). Base
  pubspec is `0.8.0`; upstream is at `0.10.0`; the fork stays frozen at
  `0.8.0`. Delta, formatting both sides (Dart 3.12) then diffing with
  `git diff --no-index --diff-algorithm=histogram` (plain `diff -ruN`
  without stripping CRLF inflates every count): +1,877/−134 lines across
  19 files (changed-lines method); `_code_paragraph.dart`+
  `code_paragraph.dart` (fork-owned) are 926/2,011 ≈ **46 %** of it — the
  ledger's original figure, confirmed. The rest is smeared through
  `_code_field`, `_code_selection`, `code_lines`, `_code_highlight`,
  `code_editor`. Raw (unformatted) diff is +3,718/−2,244; reflow is
  therefore 1 − 2,011/5,962 ≈ **66 %** of the raw churn. Full breakdown in
  `docs/re-editor-performance-2026-07.md`.
- **Nested `.git` trap (corrected severity: Medium).** `packages/re_editor/.git`
  shows 33 modified files against its own HEAD, but the **outer repo tracks
  all 37 `lib/` files as ordinary blobs and its status is clean** — the fork
  source is safely in ANTA's history. The nested repo is stale noise that a
  `git checkout`/`stash` inside it would use to revert the working tree.
  Session 0 deleted it on 2026-09-03; the standing rule (COPILOT_CONTEXT,
  `re-editor-performance-2026-07.md`) is that no repo is ever created
  under `packages/re_editor/` again. (Session 0
  verified every claim here on 2026-09-03 and found nothing local-only — §3.)
- At review time: zero asserts in `_code_paragraph.dart`,
  `_code_selection.dart`, `code_lines.dart`, and zero tests. Sessions 5
  and 7a closed both — `_code_paragraph.dart` carries the two documented
  debug asserts (five `assert` sites in all), `code_lines.dart` one
  invariant assert (a second `assert` block guards the 7c debug counter),
  and `test/re_editor/` is 11 suites. Four undocumented couplings the app relies
  on: root-span `fontSize` ⇒ line height (`_code_paragraph.dart:542-550`);
  placeholder height ≤ strut (`code_paragraph.dart:49-51`); per-segment
  backing-list identity as the dirty flag (`code_lines.dart:180-268` — sound,
  but mutating a stale `CodeLines` would corrupt the index silently);
  identity-keyed paragraph cache requiring identical span instances (a
  silent perf cliff if either memo is disabled).
- Tap interceptor: state machine is sound on mobile (long-press, ancestor
  scroll, second finger all reach cancel). Desktop, at review time: second
  claim steals the first; claimed pointer cannot drag-select; right-click
  during a claimed press moves the caret. Session 7b (`d9621bb`) closed
  the first two — exactly one claim is live at a time, and the claiming
  pointer past the slop releases into an ordinary drag; right-click is
  unchanged. The `render` getter (then `_code_selection.dart:38-39`) was an
  unchecked cast on the every-tap-down path; Session 7a (`fcfe704`) made
  both getters nullable type-checks, deleted `ensureRender` and left zero
  casts in that file (upstream `dc27ee5`; `b19f746` is issue #68's
  mobile-handle fix, already in the base); the 2026-09-05 review replaced
  the six `as _CodeFieldRender?` casts in the other fork files the same
  way.
- `getRangeForSpan` double-counts nested spans (upstream bug, hover cursor
  only); `_dropPrefix:664` dead branch; empty `TextSpan(text:'')` children
  retained.

### 1.6 Tests

**Review snapshot (2026-09-03); closed by Sessions 1–7c — see §3.** Zero
references anywhere in `test/` to: `MarkdownEditorSpanBuilder`,
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
screen-reader story. **Resolved by Session 7c (2026-09-05, §3):** the
node announces the visible window, carries `onTap` /
`onDidGainAccessibilityFocus` / `onSetSelection` / `textSelection`, and
hangs one labelled child per zone off the field.

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
   **Decided 2026-09-04: visible-window value + actions.** The announced
   `value` is the lines currently on screen (O(viewport) per keystroke),
   and the render gains `onTap` / `onSetSelection` /
   `onDidGainAccessibilityFocus` so the editor can be focused and an a11y
   tap on an interceptor zone performs the same action as a pointer tap.
   Same day, for Session 7 item 3: a desktop drag that starts on a claimed
   zone **releases the claim past the touch slop and becomes a normal
   drag selection** (not documented away). Session 7 was planned as one
   whole session after Session 6, then split on 2026-09-04 into 7a
   (upstream sync, items 6/2/5), 7b (interceptor, items 3/4) and 7c
   (this decision, item 1) — see §3; 7a and 7b shipped 2026-09-04
   (`fcfe704`, `d9621bb`), 7c on 2026-09-05 (`3866ef2`…`8cb585d`).
4. **Lite rendering tier** (Session 10): only if the Session 1 benchmarks
   and a real-device profile say the hanging layout or variable line heights
   dominate. Do not build it speculatively. **Decided 2026-09-04: dropped.**
   After Session 5 a cold list line lays out in 40–43 µs and the paragraph
   cache is bounded at 128, so nothing measured points at it; the block
   moved to §4 with its reopen trigger (a real low-end device profile).
5. **Wiki links `[[note]]`** (Session 9): wanted at all? It is the one
   genuinely new feature in the plan. **Decided 2026-09-04: yes, Session 9
   stays as planned.**
6. **Fork ownership** (raised while splitting Session 7): after the 7a
   sync, keep tracking `reqable/re-editor` or declare the fork owned?
   The evidence: 28 upstream commits in eight months, four worth taking
   after removing net-zero pairs, no-ops (`10fdbc1` was already present
   in the fork), API renames and paths the app does not use; the fork's
   largest delta (the paragraph and lines files)
   has zero upstream commits; the app uses a narrow slice (no built-in
   autocomplete, no shortcut remaps, find via `findBuilder`), and Session
   11 makes the chunk machinery fork-specific. **Decided 2026-09-04:
   owned after 7a.** Concretely: watch, do not sync (the 7a provenance +
   patch list keep a one-off cherry-pick cheap; no tracking branch, no
   scheduled syncs); format the fork tree once as its own commit right
   after 7a (measured at planning time as 32 of 37 files — that count
   came from pubspec-less copies; under the fork's own `>=2.17.3` SDK
   floor the tree was already clean and `72401b8` reflowed two lines);
   keep the
   package name, import paths and frozen pubspec version; and **retire
   the "avoid API-breaking changes" rule** for the fork in CLAUDE.md and
   COPILOT_CONTEXT — the fork's API is whatever the app needs, which
   Session 11 uses immediately. The preserved-optimizations list stays.

Also settled 2026-09-04 while planning: Session 8 callouts render the
accent bar only (no background band — an empty line cannot paint one, the
same reason the fence tint went); heading folding leaves §4 and is planned
as Session 11 (planning only, after Session 7a's upstream review and
Session 7b's interceptor harness).

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

**Outcome — DONE 2026-09-03, uncommitted.** `dart analyze lib` and
`dart analyze packages/re_editor/lib` clean (the fork's two pre-existing
`avoid_print` infos in `debug/_trace.dart` aside). Numbers in §5. Item by
item, plus everything the implementation surfaced and the owner asked to
close in the same change ("make sure this is final"):

1. Fork `CodeLines.replaceLine(index, line)` (`from` + `[]=`: one segment
   re-owns its list, every other segment stays shared by identity) and
   `CodeLines.removeLine(index)` (`sublines` + `addFrom`; an empty result
   must go through the controller's `codeLines` setter). `[]=` now locates
   the segment with the same binary search as `operator []` and
   invalidates only what a same-length replacement can change (line/char
   counts, `asString` slots) instead of everything; `sublines` asserts it
   never emits an empty segment. Pinned in `code_lines_sharing_test.dart`
   (incl. "`replaceLine` ≡ `CodeLines.of` rebuild" and the exact
   `addFrom` merge rule for `removeLine`).
2. **P2 fixed** at all three app sites — page `_handleTextChange` (Enter
   continuation → `replaceLine`; Enter on an empty item → `removeLine`
   instead of a full-text `replaceRange` + re-parse), wrapper
   `_toggleTaskLine` and `_tryListIndent` (→ `replaceLine`). `grep
   "CodeLines.of(" lib/` is empty. Undo-merge semantics (direct `value =`
   for the continuation, `runRevocableOp` for toggle/indent), the
   selection-untouched contract and the `_previousTextLength` resync are
   unchanged; `copyWith(text:)` keeps chunks. Page test
   (`optimized_note_editor_page_test.dart`, +4: continuation, empty item,
   both undo-merges, untouched segments identical by reference) and a new
   `modern_editor_wrapper_toggle_test.dart` (toggle + Tab/Shift-Tab on
   Android; selection untouched, identity, one undo step).
3. **P3 fixed, and more than planned.** The eleven parallel per-segment
   arrays became one `List<_SegmentState>` holding the state at segment
   *entry*, and `_ensure` is one splice: identity-matched prefix/suffix
   kept (line numbers in the kept suffix shifted by `delta`, task-snapshot
   frames that pointed into the replaced region marked unmappable), the
   middle rescanned, every pass run from the first replaced segment with an
   explicit entry state and stopped at the first seam whose entry state is
   proven equal. So keystroke, Enter, delete-line, paste and undo all take
   the same path — the full rebuild is the same splice with an empty prefix
   and only runs when nothing is shared. Proofs: fence = parity (as
   before); tasks = frame stack element-wise, with the result count
   *excluded* and reconciled by a shift (a count-inclusive proof would
   never fire on a child toggle); money = the six `MoneyFold` scalars
   **plus** element-wise equality of the regenerated entry/checkpoint
   history slices against the old ones — the plan's "equal entry state ⇒
   identical suffix" was unsound for money because `$^ N` and `$~ N` read
   back into the histories (two counter-examples are now tests). A fence
   pass that runs to the end pins the other two passes to the end (a fence
   opened above turns every row below inert — the plan missed this and the
   equivalence suite caught it). `_resultOrder`/`_moneyLines`/`_moneyValues`
   are rescanned into scratch lists and landed with one `replaceRange`;
   the indeterminate set is maintained incrementally on keystrokes and
   rebuilt only after a renumbering (a shifted suffix result can transiently
   collide with a stale middle result, so removal-by-value is unsafe there);
   uniqueness of result lines is asserted in debug. `debugLastScan` /
   `debugIndeterminate(lines)` expose it to tests. `_ensure` drops `_lines`
   before touching state and re-assigns it only on success, so a throwing
   pass degrades to a full rebuild instead of serving stale answers. The
   money stashes are reusable buffers cleared after each pass (their size
   is bounded by the ledger's entry count below the caret; a shorter stash
   is impossible because a seam can fail on `periodStart` alone and prove
   several segments later). Suite 25 → 43, incl. the three splice branches
   an adversarial review found uncovered (empty new middle, tail
   truncation `p == n < m`, one backing list at two segment indexes); that
   review also fuzzed 4,617 mixed edit/Enter/delete/paste/undo/redo steps
   across 8 seeds against a fresh index with zero mismatches.
4. **P5 fixed**: a 256-entry text-keyed memo (`_moneyParseMemo`, const
   `_notMoney` sentinel for negative results) in front of
   `MarkdownMoneySyntax.parse` at both call sites; never cleared, because
   the parse is a pure function of the line text and the LRU bounds it
   (a first cut cleared it in `configureMoney` and pinned that with a test
   — review caught it as pinning a non-requirement, both removed).
   `debugMoneyParseCount` (debug builds only) pins one parse per distinct
   text (units suite 118 → 119). While there: `LruCache.get`
   went from three `LinkedHashMap` probes to two, `V extends Object` makes
   the non-null contract compiler-enforced, and the three duplicated
   memo-clearing sites became `_clearSpanMemos()`. New
   `test/utils/lru_cache_test.dart` (14).
5. **P8 fixed**: `_kMaxUndoHistory = 200` (`_consts.dart`); the cache keeps
   a root pointer and per-node depth so eviction is O(1) — the oldest
   survivor's `pre` is cut, `canUndo` turns false there. A hard bound, not
   a coalescing window. `test/re_editor/undo_history_cap_test.dart` (the
   first fork test file — that folder is the planned home).
6. The money pass's length guard is now `MarkdownMoneySyntax.maxLineLength`
   itself (one source of truth for what a money line can be, and it stays
   a single integer compare — dropping it entirely made `leadsWithMoney`
   walk the leading whitespace of every over-long line); the constructor's
   `maxScannedLineLength` is task-only; a test pins
   `maxStyledLineLength == maxLineLength`.
7. **Found and fixed on the way**: Tab / Shift-Tab list indent was dead on
   Android/iOS — the fork mounts a bare `Focus.onKeyEvent` there (Backspace
   and Enter only), so `shortcutOverrideActions` never fired and an ignored
   Tab fell through to focus traversal. The touch branch now routes Tab
   through the override actions (or `applyIndent`/`applyOutdent`), and its
   Backspace/Enter arms respect `readOnly` like the desktop branch (they
   did not — pre-existing, closed in the same change). Widget
   tests run as Android by default; the desktop `Shortcuts` path is pinned
   separately in `modern_editor_wrapper_desktop_indent_test.dart` with the
   platform override set in `setUpAll` (the `kIsAndroid`/`kIsIOS` finals
   resolve once per process — a trap).

Exit criterion met: Enter and toggle cost O(one segment) in both the
`CodeLines` mutation and the index (see §5: index work per Enter ≈ 22–38 µs
regardless of position, was 194–284 µs; keystroke index work at k=0 ≈ k=39).
One deliberate non-goal: `_ensure` still recomputes `_segStarts` (40 ints)
and, after a renumbering only, rebuilds the indeterminate set — both are
bounded by segment count / result count, not line count.

Test traps: the first benchmark row printed in a run carries JIT warm-up
(reverse `segmentsUnderTest` before blaming `k`); a two-line
`replaceSelection` is needed to change money history entries without moving
the seam balance (a trailing `$=` makes `$^ N` clamp to the period and hides
the difference); `expectMatchesFresh` only queries `[0, n)`, so stale set
entries pushed past the end by a delete need the set-for-set check.

#### Session 3 review — 2026-09-05

Three read-only passes over the *current* structural-edit code (A: the
line index and its seam proofs; B: the fork's `CodeLines` mutation paths
and the undo cap; C: the app-side callers — `EditorEditTracker`, every
`replaceLine`/`removeLine` site, the Android key path), then two
implementation passes plus one fork-only pass. Nothing committed; the
working tree sits on `8c1bf28`. The class of bug the Outcome block named —
a seam accepted on scalar equality while a regenerated slice differs — was
hunted on all three passes and **not found**: fence parity is complete
(the delimiter predicate is pure parity), the task proof compares all five
frame fields and orphaned snapshots can never survive past a proven seam,
and `MoneyFold` has exactly the six scalars plus the two histories the
proof already covers. The line index and `CodeLines` came out with no
bugs; the four real bugs were all in the **callers**.

**C, callers.** C1 (bug): the Enter detector keyed on caret position
alone — caret at the item above's indent column, on a line starting with
that indent — so any growth that parked the caret there grew a list
marker: a Tab indent at column 0 below a `  - item` produced `  - - x`
(the wrapper's `_tryListIndent` runs `runRevocableOp` with no tracker to
guard through), a second space typed on a blank line below a nested item
produced `  - `, a space at column 1 of ` x` produced `  - x`, and a
paste of `abc\n` (under the 20-unit paste threshold) at the end of a list
line grew a marker on the blank line the list-aware paste transform had
deliberately left bare. Fix: an Enter is recognised by its exact growth,
`textLengthDiff == 1 + autoIndent` (one line break plus the indentation
`applyNewLine` copies — `alignIndent` counts spaces only, matching
`_autoIndentLength`), which nothing else produces. Seven tracker cases
pin it; five fail against the old code. C2 (bug): undo/redo growth over
the threshold was reflowed as a paste — `PasteLineBreaker` writes
`controller.value` directly (so the reflow merges into the paste's node),
which after an undo is a write in the middle of the chain and **drops
the redo branch**; restoring a deleted 200-character typed line rewrapped
it and lost redo. Fix: the fork's controller raises `isRestoringHistory`
around `undo`/`redo` (interface + delegate), and the tracker returns —
after adopting the length — while it is up. A listener-driven test
proves it (a listener called after `undo()` returns never sees the flag —
a harness trap). C3 (bug, half withdrawn): `ShortcutApplier.apply` is
`async` and awaits before `replaceSelection` for every insert type but
`header`, so the insert landed in a microtask after both
`_edits.runGuarded` and `runRevocableOp` had returned: the tracker diffed
it unguarded (a one-newline shortcut at the end of a list line grew a
marker — the page test that pins it fails against the old code) and
`reformatInserted` measured an unchanged length and was dead. The "merges
into the previous undo node" half did **not** reproduce:
`replaceSelection` opens its own revocable op. Fix: `ShortcutApplier`
split into async `resolve` (returns the text, `null` for `header`) and
sync `applyHeader`; the page resolves first, then inserts synchronously
inside guard + revocable op; `apply` stays as a wrapper for the two event
sheets (which still call it inside `runRevocableOp` — harmless there, no
tracker, noted as follow-up). `applyHeader` now reads the level from
`MarkdownLineShape.headingAt` instead of a private `^(#{1,6})\s` regex
(house rule: one heading predicate); indented headings keep their indent,
a bare `###` cycles to `#### `. C4 (bug, adjacent scope, found by the
`controller.text` audit): `NoteSaveCoordinator._createNewNoteEarly`
raised `_isCreatingNewNote` only after `await _titleExists`, so every
keystroke during the lookup dispatched its own `CreateOptimizedNote` —
one editor, several notes (three creates for three keystrokes in the
test). The flag is raised before the await; because `saveBeforeExit`
returned on that flag, a pop mid-lookup would then have dropped the
create, so the in-flight future is kept in `_pendingCreate` and awaited
there. C5 (debt): the Android/iOS `Focus.onKeyEvent` dropped
`KeyRepeatEvent`, so a held Backspace/Enter/Tab did nothing past the
first press while the desktop `Shortcuts` path repeats; repeats are
honoured now (the stuck-key hazard the comment describes is about
`isKeyPressed`, not the event type). C6 (doc-drift): the page comment at
the content load claimed the tracker had been notified with a document's
worth of growth; the wrapper is the only caller and is not mounted while
loading, so it never was — `syncLength()` is still needed, the reason is
now the true one.

**A, line index.** A1 (debt): `_ensure` captured `entry = _states[p]` by
reference before the `replaceRange`; with an empty old middle (a whole
segment prepended: old `[A, B]`, new `[X, A, B]`) nothing is removed and
the captured object survives in `_states` where the renumbering loop and
the three passes write through it — benign only because every pass copies
its fields out before its loop and the passes write disjoint fields. It
is a `_SegmentState.copy` now, and the prepend case has a test (the only
one reaching that branch). A2: the three scratch lists are cleared at
pass exit as the stashes already were. A3: `configureMoney` no longer
invalidates the whole index for a start-balance change while the pass is
off. A4–A5 (deliberately not changed, documented): a structural edit
renumbers and rebuilds all indeterminate results rather than those below
the edit, and the money pass copies the whole history tail below the
caret into the stash on every edit — both bounded by result/entry counts,
not lines; a write-cursor `MoneyFold` would remove the copy but changes
`resume`'s contract. Test shapes added (43 → 52): whole-segment prepend,
**a suffix seam where only the anchors slice differs** (neutering the
anchor loop in `_moneyProven` fails exactly this one test and no other —
it is that loop's sole guard), a multi-line paste starting inside a fence
interior, `$=` inserted by Enter above `$~ N` rows, a delete of a whole
fence, shrink to one and to zero lines, task frames orphaned into the
replaced region, deterministic last-line delete/replace, and the
disabled-pass reseed pin. `configureColors` never touched the index; the
task brief's claim that it reseeds was the drift.

**B, fork.** No bug. B1: `CodeLines.hashCode` was the segment list's
identity hash while `==` is structural, and the base `CodeLineSegment`
hashed three fields where the counting subclass hashes four — equal
documents hashed unequal (latent: no `Set`/`Map` keys on them). Both are
structural now (`Object.hashAll(segments)`, four fields), which also
makes the segment `_hashCache` live rather than dead. B2: the grow branch
of the counting segment's length setter was unreachable (growing a
non-nullable list through `length=` throws) and folded the whole segment;
it is an assert. B3: `sublines` never rejected a negative start and threw
the wrong bound for an exclusive end; it, `replaceLine` and `removeLine`
use the SDK's `RangeError` helpers. B4: `CodeLines.of`/`addAll` used
`elementAt(i)` in an index loop (O(n²) on a lazy iterable). B5: `[]=`
leaves the last-hit window on the segment it located. B6: the
controller's `value` setter maps an empty document onto the initial blank
line exactly like the `codeLines` setter, so `removeLine`'s "guarantee a
survivor" caveat is gone (the app's only `removeLine` site wrote through
`value`, and was safe only by the `currentLineIndex <= 0` return). B7
(doc): the two-slot `asString` rationale named a concurrent highlight
consumer that is never live here (no highlighter configured) — the
comment says so now; the slot stays. Deliberately not changed: the
`from`-copy precondition (a source is never written after a copy) stays
unenforced — writing dirty clones back over the source would change the
source's own `[]=` contract that a test pins — every write site was
traced clean; `copyWith` on segments is dead API and stays; the partial
`clone` still folds (bounded by the 256-line segment cap — the ledger's
"no fold on any mutation path" carries that qualifier now). The undo cap
traced correct on every axis (off-by-one, redo after eviction, branch
discard, coalescing).

Traps (the review's own): a fork flag that is only up during a call must
be observed from a controller **listener**, not after the call returns;
`replaceSelection` runs its own `runRevocableOp`, so "merged into the
previous undo node" claims need a direct `value =` write to be true; two
`CodeLines.from` copies compare `==` but a copy is never `==` its source
(dirtiness is part of segment equality); the Bash heredoc trap holds —
Dart with backslashes goes through the Edit tool; the two index files
were unformatted at HEAD, so the touched-file format gate reflowed them
(mostly the test file).

Numbers: `editor_edit_tracker_test.dart` 36 → 43,
`markdown_editor_line_index_test.dart` 43 → 52,
`code_lines_sharing_test.dart` +6, `modern_editor_wrapper_toggle_test.dart`
+1, `optimized_note_editor_page_test.dart` 11 → 14,
`note_save_coordinator_test.dart` 25 → 27, new
`shortcut_applier_test.dart` (11) and
`test/re_editor/controller_empty_document_test.dart` (3). Full suite
**3,176** passing (7 benchmark cases skipped), up 42 from 3,134; `dart
analyze lib`, `dart analyze test` and `dart analyze packages/re_editor/lib`
clean apart from the fork's two pre-existing `avoid_print` infos; `dart
format --set-exit-if-changed` over all 18 touched files changes nothing.
Nothing committed.

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

**Outcome — DONE 2026-09-04, uncommitted on a183f11.** Full suite 2702 passing (5 benchmark cases skipped by default);
`dart analyze lib test` clean. What landed, item by item:

1. `lib/utils/markdown_inline_grammar.dart` — `MarkdownInlineGrammar.tokenize`
   over a `[start, end)` range that reads nothing outside it (range edges
   are line edges), so the preview's substrings and the editor's ranges
   agree by construction; a pure function of the substring plus the line's
   ghost runs. Phase 1 atoms (escape unless it would escape a ghost's `{{`
   — ghosts win on both surfaces now; ghost; backtick fence closed by a run
   of exactly the same length, unclosed runs literal, no "no space inside"
   rule — CommonMark's `` ` a ` `` is code), phase 2 constructs (image /
   link — structural chars outside atoms, colour, tag, bare URL clamped to
   the next atom, delimiter runs of `*` `_` `~~` `==` with flanking:
   opener followed by non-space, closer preceded by non-space, `_` also
   needs a non-word char or the range edge outside — word = ASCII
   alphanumeric, `_`, anything > 0x7F, so `ș_a_` stays plain like
   `snake_case`), phase 3 CommonMark "process emphasis" (nearest same-char
   opener, rule of three, delimiters between a pair drop out, opener spends
   from the end of its run and closer from the start — `***a**` is `*` +
   bold, `~~`/`==` two at a time, three-on-three is one `boldItalic`),
   phase 4 sort + cover sweep so only top-level tokens return. Consumers
   recurse into `InlineEmphasis.contentStart..innerEnd` (the tinted
   `==name:` prefix is chrome), link text and colour inner with
   `depth + 1`; past `maxNestingDepth = 8` the tokenizer returns nothing,
   so both surfaces flatten at the same depth (the editor's silent
   `_maxInlineDepth = 3` cut is gone). `hasCandidates` is the one-pass
   quick reject in front of it and the editor's paragraph pre-check (the
   units suite pins it as a superset of what tokenizes). `linkAt`/`tagAt`
   walk the token tree for the wrapper. Cost: 0.03 µs for a construct-free
   line, 0.3–0.6 µs for the benchmark's list lines.
2. Preview `_parseInline` and editor `_appendInline` are emitters over the
   tokens (exhaustive `switch` on the sealed `InlineToken`); the preview
   drops what the editor conceals. Deleted: `_matchRun`, `_InlineRun`,
   `_matchTag`, `_matchLink`, `_matchBareUrl`, `_isWordChar`, `_ghostAt`,
   `_inGhost` (editor); `_tryParseEmphasisAt`, `_countRun`,
   `_findClosingBacktick`, `_canOpen/CloseEmphasis`, `_tryParseLinkAt`,
   `_tryParseBareUrlAt`, `_InlineEmphasis`, `_InlineAutoLink`,
   `_EmphasisKind`, eleven `_k*` constants, `_MarkdownPatterns
   .horizontalRule` (preview). Editor chrome the grammar guarantees
   ghost-free (delimiter runs, fences, `{name:`/`}`) goes through
   `_emitChrome` — one span, no ghost split, no debug inventory walk.
3. Wrapper `_linkUrlAt`/`_tagAt` are one-liners over `linkAt`/`tagAt`;
   `_inlineCodeRuns`, `_oddBackslashRunBefore`, `_inRanges`, `_inGhosts`
   deleted. `ModernEditorWrapper.colorPalette` (page passes
   `_colorPalette`) so zones resolve `{name:…}` nesting exactly as drawn.
   The roadmap's "links clamped out by an emphasis-segment end still
   intercept" residual is closed.
4. `MarkdownLineShape.headingAt` / `isHorizontalRule` are the heading and
   rule predicates for the preview, the editor, the line-height calculator
   and the paste policies (four hand-scans and two regexes collapsed).
   `###` alone is an empty heading on both surfaces; `-*-` is no longer a
   rule anywhere (the preview's old `[-*_]{3,}` accepted mixed markers).
   Found on the way: the preview's heading `contentOffset` was off by the
   extra spaces of `#   x` (search highlights and preview→editor mapping
   landed wrong there) — content now keeps its leading spaces at the exact
   offset; and `isLineLedConstruct(r'##$$')` was `false` (the space-less
   money heading was neither a heading nor reached the money fallback),
   now protected.
5. **B6 fixed**: `keep` in the `concealCount` branch bounds on
   `layout.contentEnd`, so `*$^ 2*` conceals the count.
6. Tests: `markdown_inline_grammar_test.dart` (158: every §1.3 row, the
   roadmap's known-good cases, atoms/precedence, rule of three, leftovers,
   `_` rules incl. non-ASCII, ghost opacity, depth, the range-edge
   property over a 38-line corpus × sub-ranges, `linkAt`/`tagAt`),
   `markdown_inline_agreement_test.dart` (117: 96 lines rendered through
   BOTH builders and compared as visible text + per-code-unit style with
   inherited `TextStyle`s — concealed editor leaves dropped, code chip ↔
   monospace and tag chip ↔ tag background normalised; plus 18
   preview-offset sweeps that highlight every source offset and require the
   painted units to reconstruct the visible line in order, a bijection
   proof of the offset threading; three self-checks keep the comparator
   honest), `markdown_line_shape_test.dart` (18), units suite 119 → 142
   (17 corpus lines + a "visible rendering" group + the candidate-superset
   property), wrapper tap suite 11 → 19 (link in bold / code / colour /
   emphasis, escaped and double-escaped opens, image, tag in bold,
   boundary offset). Pinned, documented divergences in the agreement
   suite (asserted to still reproduce): the whole-line image (preview
   `🖼` + link, editor raw — a line-level branch, mid-line `![a](b)`
   agrees), and the two whitespace-only heading shapes (indent and
   trailing blanks: the editor may never drop a code unit). Closed on the
   way: a ghost inside a code span rendered monospace in the preview and
   plain in the editor — the preview now keeps the prose style there like
   the editor's chip gap.
7. Benchmark (`markdown_editor_span_builder_benchmark_test.dart`, same
   machine, A/B via stash on a quiet box): the cold list-line pass went
   from 528 µs (old code) to 598–608 µs (13.2 → 15.0 µs per line, +14 %),
   of which the tokenizer itself is 0.3–0.6 µs per line — the rest is the
   emitter's extra `_emit` calls, which carry the debug-only code-unit
   inventory assert (release builds pay none of that). The warm memo-hit
   row also moved (80 → 125–142 µs per pass) although the path before the
   memo is byte-identical; a warm-only variant with a single cold pass
   ahead of it reads 172–208 µs, so that row tracks JIT warm-up, not the
   memo. The display-money row is unchanged (74–83 µs). Accepted: the
   cold path is the after-a-theme-change / first-render path, and the
   trade is one grammar for two hand-rolled scanners.

Behaviour deltas, all deliberate: `___x___` bold-italic, matched-length
backtick fences, `*a **b** c*` nests, `###` is a heading in the editor,
`-*-` is not a rule, `\{{x}}` is a ghost in the preview, `` ` a ` `` is
code in the editor, an image's URL no longer picks up a bare-URL tint in
the editor, and `~~~x~~~` is `~` + strike + `~` on both surfaces.

Test traps: on Android the selection handle hangs one line box under the
caret after a tap, so a widget-test pass-through tap straight below the
parking column lands on the handle and the caret never moves — park the
caret in a different column; `dart format` rewraps agent-written lines, so
text-anchored scripted edits must run after formatting; benchmark rows are
useless while another `flutter test` runs on the machine.

#### Session 4 review — 2026-09-05

Three read-only passes over the shipped inline grammar as it stands today
(the tokenizer; the two emitters; the line-shape module and every caller)
plus a grep sweep re-verifying each claim in the Outcome block above,
then two implementation passes on disjoint files. Nothing committed; the
tree sits on `2dd0667`. Three findings are bugs (A1, A2, B1), one of them
a regression Session 4 itself introduced.

**A. Tokenizer.** A1 (bug, regression):
`MarkdownLinkPatterns.isTrailingPunctuation` trimmed `. , ; : ! ? ) ] ' "`
but not `*` `_` `~`, so a bare URL inside emphasis swallowed its closer —
`*https://a.com*` was a literal `*` plus a link whose href ended in `*`,
identically on both surfaces (`hrefOf` included the marker). Before
Session 4 the preview tried emphasis at the opener before its URL branch,
so this is a deviation the Outcome's "behaviour deltas, all deliberate"
list missed. The three GFM trailing characters are trimmed now; `=`
deliberately is not (base64 padding in a query string is real, pinned).
A2 (bug): the depth cutoff returned nothing at all, so a ghost nested
eight containers deep rendered raw `{{g}}` in the preview and concealed
in the editor (`EditorSpanEmitter.emit` splits ghosts on every path, the
preview's no-token fallback prints the source). `tokenize` now returns
only the range's ghost runs past `maxNestingDepth` (`_ghostsOnly`):
placeholders are never styling, so they survive the cut. A3 (debt):
`_pairDelimiters` had no `openers_bottom`, so every closer rescanned every
earlier delimiter and a failed search recorded nothing — 0.8–1.2 ms per
call on 4,095 chars of `a* ` repeats, on the caret line the editor
rebuilds each keystroke with the memo bypassed. CommonMark's bound is in
(24 slots: char × original run length mod 3 × closer-can-open; a failed
search sets the slot to `ci - 1` and deactivates a closer that cannot
open), allocated lazily on the first failed search so a cleanly pairing
line allocates nothing; 44 hand-written pairing lines captured from the
old code before the change pin that tokenization is unchanged, and a
400-closer storm case pins the bound. A4 (debt): `_findFence` probed
`_inGhost` from index 0 per backtick run and `_inAtom` scanned atoms from
0 for every link/colour probe; both take the caller's cursor now (the
atom loop's `gi`, the main loop's `ai` — atoms below it end at or before
`p`, every probe lies at or after `p`). A5 (nit): `linkAt`/`tagAt` gained
`ghosts`; `EditorInputPolicy.resolveTap` scans the line's runs once, uses
them for its own ghost-at-offset check and hands them to both zones.

**B. Emitters.** B1 (bug): the preview's `_attachRecognizer` rebuilt every
`TextSpan` with the link's recognizer, so tapping `{{ what }}` inside
`[see {{ what }}](u)` opened the link — the editor's `EditorInputPolicy`
says ghosts win over every zone. A `_ghostRecognizers` set marks ghost
subtrees, which the wrapper now leaves untouched; a `#tag` inside link
text still yields to the link (the editor's precedence: checkbox, link,
money, tag). The set is kept in step on chunk eviction and `clearCache`.
B2 (debt): `EditorSpanEmitter._emitRange` split a ghost out of concealed
chrome and painted its inner text in the ghost colour at 0.01 px —
`[docs]({{ url }})` showed a coloured sliver the preview never had, and
the agreement projection counted it as visible text. A concealed style
(`_isConcealed`: transparent + `concealedFontSize`) now emits one
invisible span; reveal lines use `dimStyle`, so their split is unchanged.
B3 (debt): `_applyHighlighting` duplicated text on overlapping or nested
`searchHighlights` (`pos` advanced unconditionally, an overlapping range
re-emitted `[range.start, pos)`) — latent, since the page's literal search
matches never overlap. The sort is deterministic now (start, end
descending, current match first) and each range paints only its
unpainted part. B4 (debt): link recognizer keys (`'$offset:$url'`) never
matched the chunk-eviction prune's prefix list (`'$chunkIndex:'`, `img:`,
`tag:`, `ghost:`), so they survived every eviction until `clearCache`;
they are `link:`-prefixed now and the dead `'$chunkIndex:'` prefix is
gone — nothing produced such keys. B5 (doc-drift): the Outcome's
"mid-line `![a](b)` agrees" was false — the preview renders `!` plus a
tappable link on the alt text, the editor keeps the source raw. That is
by design (the preview owns images; the editor keeps the source
editable) and is pinned as an expected divergence in the corpus now.

**C. Line shapes.** Nothing to fix. Every heading/rule decision in `lib/`
goes through `MarkdownLineShape` (the only other hash regex is the colour
picker's hex pattern); the two dispatches agree in order (money → heading
→ list → quote → rule; the preview's image/table checks between money
and heading have no editor counterpart and cannot disagree). The
`MarkdownLineHeightCalculator` ratios (H6 0.875, rule and empty line 0.5,
fence 0.9) describe the preview — its only caller is the preview's
`getLineHeightScales`, and the preview's own branches use the same
constants — while the editor renders all of those at the base size; its
class doc now says so, names `lineHeightOfLine` as the editor's source,
and records that `flattenHeadings` is not applied. Predicate tests added:
`#\tfoo` is prose (tab after the hashes — CommonMark accepts it, both
surfaces agree, a product decision), bare `#` is an empty H1, four-space
indent still heads, `- - -` / `* * *` / `_ _ _` are not rules,
`---\t` / `\t---` are.

**Not changed, on purpose.** A `{` or `}` inside a code span inside
`{name:…}` still kills the colour run on both surfaces
(`MarkdownColorSyntax._findClose` is atom-blind: `{red:a `}` b}` rejects
the match at the concealed `}`, `{red:a `{` b}` never closes) — the fix
needs the close search to skip atoms, i.e. the brace placement rule
moving into the tokenizer; recorded as open debt, both surfaces agree.
`matchBareUrlEnd` reads past `limit` before clamping — unobservable
(2,132 exhaustive sub-ranges of a 44-line corpus and 60,000 random lines
found no range-vs-substring mismatch). `hrefOf`'s `toLowerCase()` is dead
(`www.` matches case-sensitively and `hasCandidates` agrees). Money
recognizer keys (`'money:$lineIndex'`) are still not pruned on chunk
eviction — a line index, not an offset, so the prune's range test does
not apply. The preview's `buildLine` has no length cap
(`maxStyledLineLength` is editor-only) — a deprecated surface. The
Outcome's item 3 names wrapper members (`_linkUrlAt`, `_tagAt`) that
Sessions 6/7c replaced with `EditorInputPolicy.resolveTap`/`zonesOf`, and
item 1's "`linkAt`/`tagAt` walk the token tree for the wrapper" is true
of the policy now — historical, left as written. Item 1's cost figures
(0.03 µs construct-free, 0.3–0.6 µs list line) do not reproduce from
`tokenize` directly (1.2 µs and 1.1–3.1 µs in the test VM); the number
that mattered, the quadratic ceiling, was never recorded — it is now.

Traps (the review's own): an all-unpairable line makes the span builder
return `null` (nothing styled), so a benchmark row for the pairing bound
must end each line with a real `**b**`; the LRU eviction path of the
preview is reachable from outside with `linesPerChunk: 1` and more chunks
than `_maxCachedChunks` (50), so the recognizer-prune test drives a real
eviction rather than `clearCache`; the Bash heredoc ate a backslash again
while capturing the pairing corpus (the Session 7 trap, re-confirmed);
concurrent `flutter test` runs from a second worker skew micro-timings by
about 1.5× — the before/after pairs below were taken in one sitting.

Numbers. `tokenize` µs per call (200 iterations, debug VM, one sitting):
`a* ` × 1365 (4,095 chars) 796 → 64; `a_ ` × 1365 787 → 46; `` `a` [b](c)
`` × 400 (4,400 chars) 452 → 222; `{{g}} `a` ` × 200 (2,000 chars) 33 →
21; 2,015 distinct unclosed backtick runs 72 → 72 (`_findFence`'s own
forward scan, untouched); typical list line 1.1 → 1.2; construct-free
44-char line 1.2 → 1.2. New benchmark row `span build of 20
unpairable-delimiter lines, cold`: 63 µs per 4,087-char line. Tests:
`markdown_inline_grammar_test.dart` 158 → 212, the agreement suite 117 →
126 (five corpus lines incl. two pinned divergences, four offset-sweep
lines), `markdown_line_shape_test.dart` 18 → 23, new
`line_based_markdown_builder_test.dart` 10 (ghost/link/tag recognizer
precedence, five highlight-overlap shapes, eviction and `clearCache`
pruning), the benchmark file 2 → 3 rows (skipped by default),
`editor_input_policy_test.dart` 174 and the units suite 144 unchanged.
Full suite: **3,176** before (the Session 3 review's figure, tree clean
on `2dd0667`) → **3,254** after (7 benchmark cases skipped), +78 — exactly
the per-file deltas. `dart analyze lib`,
`dart analyze test` and `dart analyze packages/re_editor/lib` (untouched:
the two pre-existing `avoid_print` infos) clean; `dart format
--set-exit-if-changed` over every touched file changes nothing. Nothing
committed.

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

**Outcome — DONE 2026-09-04, uncommitted on 1ed4a60.** Full suite 2722
passing (6 benchmark cases skipped by default); `dart analyze lib test
packages/re_editor/lib` clean. Owner decisions applied: B8 fixed with
`floor` (not documented away); the paragraph cache was measured at 512 vs
128 and lowered to 128 because the meminfo delta was a clear 15 MB (§5).
What landed, item by item:

1. `lib/utils/editor_render_context.dart` — `EditorRenderContext{style,
   baseColor, primary, isDark, onAccent}` (value-equal on the first four;
   `onAccent` derived from `primary`; `fromTheme(ThemeData, TextStyle)` is
   the one derivation) and `EditorRenderContextCache.of(theme, style)`,
   which hands back the same instance until `Theme.of`'s `ThemeData`
   instance or the fork's line style changes — one cache per surface
   that owns an editor (the page, the event description sheet, the event
   editor sheet), so the per-line cost is one `Theme.of` plus two
   identity checks. `MarkdownEditorSpanBuilder.build({context:
   EditorRenderContext, index, codeLine})` — no `style` parameter and no
   `BuildContext` anywhere under `lib/utils/markdown_editor_*`; the
   builder adopts an unequal context by dropping both span memos, so the
   context IS the generation key. The page's ghost fallback takes
   `baseColor` from the same context. Deliberate deviation from the plan's
   field list: the colour palette and the money config are NOT in the
   context — `configureColors`/`configureMoney` stay, because they also
   seed the line index and carry their own invalidation rule (a
   start-balance change skips the memo clear).
2. Split, no behaviour change, seven libraries with one responsibility
   each (callers still import `markdown_editor_span_builder.dart` alone):
   `markdown_editor_span_builder.dart` 2266 → 750 lines (`build()`'s
   routing, `_buildLine`, the header / quote / rule / list-item / fence
   shapes, the two positional predicates); `markdown_editor_span_cache.dart`
   136 (`EditorSpanCache`: text-keyed LRU 1024, positional LRU 128, money
   parse memo 256 with its sentinel, `adoptContext`);
   `markdown_editor_emitter.dart` 210 (`EditorSpanEmitter`: `emit`,
   `emitChrome`, `concealStyle`/`dimStyle`, the debug code-unit inventory
   assert); `markdown_editor_inline_emitter.dart` 380
   (`EditorInlineEmitter.append` over `MarkdownInlineGrammar` tokens + the
   inline styles — the plan left this cut open; without it the builder
   stayed at ~1,080 lines); `markdown_editor_money_row.dart` 800
   (`EditorMoneyRowBuilder.build`); `markdown_editor_paint_spans.dart` 178
   (`EditorMoneyTotalSpan`, `EditorCheckboxSpan`, `EditorCheckboxVisual`);
   `editor_render_context.dart` 95. Every emitter is static — the build
   path allocates no emitter object and captures no closure per line.
   Two design values with consumers in two libraries moved to
   `MarkdownConstants` (`editorHeaderScale(level)`,
   `editorChipBackgroundAlpha`); the rest of the alphas stayed private
   where they are used. `build()` is ~90 lines rather than the plan's 40
   because each of its four cache branches kept its doc comment.
3. Fork (`_code_paragraph.dart` unless noted): **B7** — hanging `height`
   and `lineCount` are the max over marker and content (both parts share
   one `preferredLineHeight`, so `height == lineCount *
   preferredLineHeight` still holds; nothing outside `_ParagraphImpl`
   reads `IParagraph.lineCount`). **B8** — `indent =
   markerRight.floorToDouble()` and the boundary offset is answered by
   the content side for BOTH affinities, so the seam resolves to exactly
   `indent`; flooring makes the marker's selection/search rects overlap
   the content's by under a pixel instead of leaving a gap. Two
   debug-only asserts: a root span that scales `fontSize` must keep the
   base style's strut inputs (`fontFamily`, `height`; the plan's "differs
   only in fontSize" would have fired on every bold heading root), and
   every `CodeInlinePaintSpan` box must be ≤ the line's preferred height.
   `_buildHanging` returns null before any paragraph work when `maxWidth`
   is infinite (word wrap off). **P6** — `_markerMeasurements`, a 128-entry
   insertion-ordered LRU keyed by the marker `TextSpan` by value (not the
   plan's `(markerText, fontSize)`: the style is part of what is
   measured, and the marker span carries the root style so equal keys
   imply the same scaled paragraph style), holding the laid-out marker
   `_ParagraphImpl` and its floored indent; a hit skips a
   `ParagraphBuilder`, a layout and both `getBoxes` calls, and sharing
   one marker paragraph across lines is safe because its lazy memos are
   pure functions of its own paragraph; cleared by `clearCache()`. The
   1.5× wrapping-marker rejection stays uncached. `trucate`/`_dropPrefix`
   no longer emit empty `TextSpan('')` nodes and the dead
   `remaining <= 0` branch is gone. **B9** — `_CodeHighlighter.clearCache`
   also clears `_plainSpans`. **B10** — `goToMatch` on the current match
   skips the value push and still re-centres.
4. `code_paragraph_testing.dart` — `@visibleForTesting
   CodeParagraphProviderForTesting` (build / updateBaseStyle / clearCache /
   truncate / dropPrefix / isHanging / markerCacheLength).
   `test/re_editor/hanging_paragraph_test.dart` (17): round trip
   `getPosition(getOffset(p)) == p` on seven realistic lines (offsets at a
   soft-wrap boundary have two visual locations and are skipped, with at
   least half the offsets required to be checked — the plan's "every
   offset" is not provable there), seam x identical for both affinities,
   `getRangeRects` covering marker + rows in order with no gap including
   a fractional-advance case (13.7 px glyphs — with the test font's
   integral advances floor and ceil are indistinguishable), `height >=
   marker.height` and the line-height identity, infinite width never
   hanging, split identity / no empty children / plain-text
   concatenation at every split point, marker-cache dedupe + clear, and
   both asserts firing. `re_editor_search_controller_test.dart` gained
   the observable half of B10 (no value push on the current match; the
   scroll half needs a mounted editor). Units suite 142 → 144 (a
   generation group); the units, agreement and span-builder benchmark
   suites are plain `test()` now (the binding is initialised, nothing is
   pumped). No `expectedDivergence` entry was added.
5. Benchmarks in §5: `test/re_editor/hanging_paragraph_benchmark_test.dart`
   is new and the marker cache cut the cold list-line layout by a
   quarter; the span-builder rows did not regress.

Traps: a `git worktree` under the scratchpad exceeds Windows' 260-char
path limit inside `ios/Flutter/ephemeral` and the flutter tool crashes —
map the scratchpad to a drive letter with `subst` first; the pre-session
worktree also needs the untracked `ios/macos/Flutter/ephemeral` folders
copied in; `@visibleForTesting` on a cache field makes the builder's
delegating getter a lint error — annotate the public getter the tests
read; under `BoxHeightStyle.max` with `height: 1.4` the first rect's top
is 0.4, not 0; `dart format` leaves the fork package in the old style
(its own language version) — do not "fix" it to match the app.

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

**Outcome — DONE 2026-09-04, uncommitted on 4cad6ec.** Full suite 2,978
passing (7 benchmark cases skipped by default); `dart analyze lib test
packages/re_editor/lib` clean apart from the fork's two pre-existing
`avoid_print` infos in `debug/_trace.dart` (untouched). Owner decisions
applied as stated: plain page-owned controllers, no BLoC on the typing
path; font sizes on `SettingsService` with debounced writes; the first
`CodeEditor` mount waits for the bundle; `EditorInputPolicy` table-tested;
`PasteLineBreaker` splices; absolute line numbers for the position record.
The page went from 2,520 lines / ~60 instance fields to 2,068 lines /
**26 fields** (the 25th and 26th are `_previousKeyboardHeight` and
`_lastKeyboardVisible`; folding the latter would mean reading
`MediaQuery` from non-build callbacks, so 26 is the honest count). What
landed, item by item:

1. `EditorSettings` (`lib/models/editor_settings.dart`, Equatable, 19
   fields incl. both font sizes, `canPreview`, an unmodifiable utility
   list) + `SettingsService.getEditorSettings()` — **one** keyed
   `getValuesFor` statement, decoded by the same static decoders the
   single-row getters now share (`_decodeDouble`, `_decodeVocabularyTrigger`,
   `_decodeUtilityConfig`; a corrupt `toolbar_utility_config` row falls
   back to the default toolbar instead of throwing out of the page open,
   which the old getter did). `EditorSettingsController` (`lib/controllers/`,
   `ChangeNotifier`): `value`, `loaded`, `canPreview`, `reload()` (notifies
   on change or first load), `adjustEditorFontSize/adjustPreviewFontSize`,
   `setToolbarUtilityConfig`, `flushPendingWrites`; a late `reload()` after
   `dispose()` never notifies. The page calls `_reloadSettings()` (bundle +
   money config + palette) from `initState` and `didPopNext`;
   `_openMarkdownSettings` no longer re-reads on return (that push is a
   `MaterialPageRoute`, so `didPopNext` already covers it — it was a
   double read). One bundle read replaces the seventeen sequential
   single-row awaits plus two raw DAO reads the old `initState` issued.
2. **B4**: `_isLoading => !_contentLoaded || !_editorSettings.loaded`. The
   skeleton stays up until both landed, so the editor's `ValueKey`
   (`editor-md` / `editor`) is final on first build; the page test pins the
   wrapper's `State` identity across a further settle in both key states.
   Consequence accepted: a failing settings read keeps the skeleton up
   (the read is one local statement with per-field fallbacks, so that
   case is the database being unreadable, where the content load fails too).
3. **B5**: `_loadFontSizes`/`_saveFontSizes` and every `AppDatabase`/
   `userSettingsDao` use in the page are gone. `setEditorFontSize` /
   `setPreviewFontSize` are debounced (`defaultWriteDebounce` 400 ms, one
   timer, per-key pending map) and write only their own row;
   `flushPendingWrites()` is public (the page flushes on lifecycle pause
   and on dispose; `getEditorSettings` flushes before reading so a size
   adjusted a moment before returning from settings never reads back
   stale); `SettingsService.reset()` drops pending writes rather than
   flushing them into the next database. Deviation from the old page: the
   deprecated preview's font size now defaults to
   `FontConstants.defaultFontSize` (16) like the editor's instead of the
   bloc's 14 when no row exists — the two surfaces share one default.
4. **B2**: `NoteEditorPositionController` owns the record, the
   `savedEditorSelection`, and both timers (restore scroll, preview
   progress save). `restoreWhenReady()` is the explicit join — fires
   `onRestore` exactly once when both the position and "editor ready"
   have landed, whichever came last — and "editor ready" is only signalled
   once `!_isLoading`, so the restore can never target an editor that
   does not exist yet. `_applySavedPreviewMode` moved into the restore
   callback (the only point where the position record, the content and
   the settings bundle are all guaranteed present). Positions are saved
   through `controller.index2lineIndex` and restored through
   `lineIndex2Index(...).index` — **absolute line numbers**; the unit test
   collapses a chunk and pins that a caret on visible line 3 saves as
   absolute line 8 and restores to the visible parent, which is Session
   11's contract in advance. Position saves during preview scrolling now
   record `isPreviewMode: false` if the user left preview within the
   500 ms debounce (was silently dropped).
5. `EditorInputPolicy` (`lib/utils/editor_input_policy.dart`): the sealed
   `EditorTapAction` family, `EditorTapZones`, `resolveTap` (every
   pass-through rule verbatim, precedence checkbox → link → money → tag),
   `toggledTaskLine`, `listIndent`, and the `GhostEngagement` two-tap
   state machine with its `GhostEngagementDecision`s. The wrapper is the
   adapter: it builds the zones from its flags, maps actions to haptics
   plus page callbacks, keeps the `_TapClaim` memo (one grammar pass per
   claimed tap, B11 stays fixed), keeps the expiry timer and the
   activation microtask, and gained `didUpdateWidget` (listener moves to
   a swapped controller, claim and ghost state dropped, a swapped search
   controller unbound). `test/utils/editor_input_policy_test.dart` is the
   table: 82 rows (52 `resolveTap`, 9 toggle, 5 indent, 16 ghost);
   `modern_editor_wrapper_rebind_test.dart` (2) pins the rebind. The
   three existing wrapper suites, the agreement suite and the units suite
   are unchanged and green; no `expectedDivergence` entry was added.
6. **P7**: `PasteLineBreaker.run({controller, calculator, availableWidth,
   pasteEnd, pastedLength})` finds the pasted range by walking back over
   line lengths from the caret (no flat offsets, no `controller.text`, no
   `TextPositionUtils`), breaks only `[start, end]`, splices with
   `sublines` + `add` + `addFrom` (the fork's own `_replaceRange` shape, so
   every segment outside the range keeps its backing-list identity), and
   still assigns `controller.value` directly so paste + reflow stay one
   undo step; a debug assert refuses to rebuild a collapsed-chunk parent
   (Session 11's data-loss guard, always true today). The caller
   measures the width (`getAvailableTextWidth`, null ⇒ no reflow).
   `EditorWidthCalculator.lineExceedsWidth` gained a per-glyph ASCII
   advance table (measured once per `(fontSize, lineHeight, fontFamily)`,
   filled lazily per glyph, ≤ 8 tables): an all-printable-ASCII line whose
   summed advances fit is settled with zero layouts, anything else falls
   through to the painter (sound because shaping never widens a run past
   the sum of its isolated advances except for positive kerning, which
   `safetyMargin` absorbs; both sides use the same painter and style).
   The same table seeds `findBreakPoint`'s binary search with a prefix
   that provably fits (exact answer unchanged — a 300-string property test
   pins it against the unseeded search), and the redundant whole-line
   layout on entry to the break loop is gone. `CodeLineOffsetUtils` kept
   only `lineStartOffset` (the debug overlay); `offsetFromPosition` is
   deleted. `test/utils/paste_line_breaker_test.dart` (17): range splice
   with prefix/suffix segment identity on a 700-line note, fence and
   line-led lines untouched, multi-line and mid-line start detection,
   single undo step, pre-filter layout counts, byte-identical golden
   output. Numbers in §5.
7. Preview bloc laziness (item 7) confirmed rather than changed: the bloc
   is still built in `initState`, but `MarkdownRenderService` allocates
   nothing until `prepare`, `_emitPrepared` no-ops until
   `PreviewThemeChanged`, and that event's only source is
   `MarkdownPreviewBlocView`, which `_buildPreview` mounts only under
   `_canPreview`. The view now binds its own key (its `viewKey`
   parameter is deleted along with the page's `_previewViewKey`).

Beyond the plan's list, reaching the field budget honestly took four more
page-owned extractions, each with its own suite: `NoteSaveCoordinator`
(`lib/controllers/note_save_coordinator.dart`, 25 tests — auto-save,
early create, duplicate-title rules with the one-shot warning,
`hasChanges` deferred past a running frame via `SchedulerBinding
.schedulerPhase`, lifecycle flush; `saveBeforeExit` now **awaits** the
early create, closing a race where a colliding title's lookup finished
after the page popped and the create was dropped; `forceSave` guards on
a persisted id so it can never clear `hasChanges` for a note that was
never written), `EditorEditTracker` (`editor_edit_tracker.dart`, 36 — the
paste heuristic, `reformatInserted` for the shortcut path, and
`runGuarded` which replaces the guard-on / op / guard-off / resync dance
at every programmatic insert site incl. the two ghost inserts),
`NoteEditorStatsTracker` (13 — the 300 ms debounce and the delta
threshold; `set` on content load also moves the baseline, so the first
keystroke in a >500-char note no longer forces an immediate recount) and
`EditorRenderController` (32 — span builder + `EditorRenderContextCache`
+ money config + palette, `buildSpan` routing, the static `ghostSpan`
with its code-unit inventory pinned). `_bar` (`MarkdownBarLoaded?`)
replaced `_allShortcuts` + `_activeBarProfileId`; `_previewController`
is a getter; `_emptyPreviewPlaceholder` and `_contentHasFocus` are
derived on demand.

**Behaviour fix found on the way (nested lists).** Enter on an indented
list item never continued the list: the fork's `applyNewLine` copies the
line's leading spaces onto the new line and parks the caret after them,
so the page's `baseOffset == 0` gate never fired and `  - nested` + Enter
produced a bare `  `. The tracker's gate is now "caret exactly after the
copied auto-indent, and the line starts with it"; continuation strips
the copy before prepending `getListPrefix` (which carries the indent —
this is what its doc comment had promised all along), and Enter on an
empty nested item drops the item and leaves a bare line, exactly like
the top-level case. Tab-indented items follow the fork's space-only
auto-indent rule. Pinned by 11 cases (bullet, task, ordered, mid-item
split, empty item, undo as one step with the Enter, tab indent, plain
indented prose untouched, two guard cases).

Tests: page suite 10 → 11 (B4 no-remount in both key states, B5 one-row
font write; B2/P2/B3 unchanged); `test/services/editor_settings_test.dart`
(14), `test/controllers/` gained six suites (editor settings 13, position
20, stats 13, edits 36, saves 25, render 32); whole suite 2,722 → 2,978.
Docs: `COPILOT_CONTEXT.md` (feature area, preview key, tap policy, ghost
span, the event-sheet clause), both skills, the companion roadmap's
architecture block and Done list.

Traps: `SettingsService`'s debounce `Timer` is created inside
`testWidgets`' `FakeAsync` zone, so a `runAsync` delay never fires it —
pump past `defaultWriteDebounce` first, then settle for the drift isolate;
`TextPainter.width` is **not** rounded to the pixel grid on Flutter 3.44
(`_contentWidthFor` clamps a raw double), so never argue soundness from
integer widths; a `Get-Content | Set-Content` round trip in PowerShell
mangles em-dashes and emoji in test files — use the editor tools;
`SettingsService.forTesting` returns the existing singleton when one is
bound, so per-file `reset()` in `tearDown` is what gives each suite its
own database.

### Session 7 — fork sync, interceptor hardening, accessibility (split 2026-09-04)

Originally six items in one session. Re-sized on 2026-09-04 against the
code (three read-only passes: interceptor + cache, semantics, upstream)
and split into **7a → 7b → 7c**, in that order. The six original items
keep their numbers below so earlier references stay valid. The measured
sizes: 7a ≈ 3–4 h, 7b ≈ 3 h, 7c ≈ 4–6 h — 7c alone is the largest and
the only one that leaves the fork (app policy + wrapper + l10n). If only
two sittings are available, run 7a and 7b together; 7c always stands
alone.

Why this order and not another:

- Upstream first, because `dc27ee5` (upstream, 2026-07-17, "guard delayed
  drag-autoscroll after dispose") **is** item 2 — it replaces the
  unchecked `render` getter with a `findRenderObject() is! _CodeFieldRender`
  check at three call sites plus a `mounted` guard, and cherry-picks clean.
  Writing item 2 by hand and then taking `dc27ee5` writes the same guard
  twice. And `04b240d` (upstream, 2026-08-20) fixes a hard-freeze layout
  loop in `_code_field.dart` that the fork still carries verbatim; landing
  it before 7b/7c edit that file keeps the merge to one place.
- Interceptor second, because item 4's widget harness (a bare
  `CodeEditor` with a fake zone) is what 7c's semantics tests and Session
  11's folding tests both reuse — whoever lands first pays the scaffolding.
- Accessibility last, because its largest part (zones reachable to a
  screen reader) adds a member to `CodeEditorTapInterceptor`, the class
  item 3 edits, and needs the harness.

#### Session 7a — upstream sync + fork test debt (items 6, 2, 5)

Facts established 2026-09-04 (both remotes reachable; upstream HEAD
`28d9fc0` unchanged since 2026-08-21, so the range is closed):

- Two bases, both correct for different things. `8a7dbc5` is
  `merge-base(m0b-x/main, reqable/main)` — the base for **enumerating
  upstream commits**. `dfbca60` is `m0b-x/re-editor` `main` = `8a7dbc5` +
  `a0094dd` (deleted `example/`, `test/`) + `dfbca60` ("re-activated
  cursor on android", fork-only code) — the base for **diffing the tree**.
  `dfbca60` does not exist in `reqable/re-editor`. §1.5's "post-0.8.0
  upstream main" and "last fetched 2026-02-27" are both stale; the base
  pubspec says 0.8.0, upstream is at 0.10.0, the fork pubspec still says
  0.8.0.
- `b19f746` (§1.5) is issue #68's fix and is **already an ancestor of
  `8a7dbc5`** — it fixed the mobile-handle facet of the `Null is not
  _CodeFieldRender` crash, not the getter. The commit that attacks the
  getter is `dc27ee5`.
- **The fork tree is not `dart format`-clean under Dart 3.12** (32 of 37
  files reflow), so "format the base commit" alone makes the diff
  *larger* (35 files, +3,399/−2,285). Format **both** sides. Then: raw
  diff 34 files +3,722/−2,248; semantic diff **19 files +1,877/−134**; 15
  of the 34 files are 100 % reflow (`re_editor.dart`, `_code_autocomplete`,
  `_code_editable`, `_code_formatter`, `_code_indicator`, `_code_scroll`,
  `_code_span`, `code_autocomplete`, `code_formatter`, `code_indicator`,
  `code_scroll`, `code_shortcuts`, `code_span`, `code_theme`,
  `code_toolbar`). Reflow is 66 % of raw churn. `_code_paragraph.dart` +
  `code_paragraph.dart` are 46 % of the semantic delta (not 58 %) and have
  **zero upstream commits** in range; same for `code_lines.dart`,
  `_code_lines.dart`, `code_chunk.dart`, `_code_find.dart`.
- 28 upstream commits since `8a7dbc5`, 18 non-merge touching `lib`,
  each trial-applied with `cherry-pick -n -X patience` onto the fork:

  | Take | Commit | Why |
  |---|---|---|
  | **hand-port + test** | `04b240d` | layout-loop hard freeze (`_updateDisplayRenderParagraphs` self-recursion at `_code_field.dart:1196-1200` gets an `index > 0` guard + `_kMaxLayoutCycles = 10`; the fork has 4 recursive sites vs upstream's 3, thread the counter by hand), `makePositionVisible` overshoot (`:687-691` counts from `first.index`, must be `last.index`), and `jumpTo` clamped to the viewport. The search bar's `goToMatch` drives exactly these paths. Conflicts in `_code_field.dart`. |
  | clean | `dc27ee5` | = item 2, see above |
  | clean | `4f3cb30` | viewport-still-valid check before the post-frame retry in `makePositionVisible` / `makePositionCenterIfInvisible` |
  | clean | `6bd7151` | `keyboardAppearance` follows theme brightness (additive param) |
  | clean | `512ba8d` | `numpadEnter` on `newLine`; no API change — the fork's mobile `Focus.onKeyEvent` path already had it, but not the desktop `Shortcuts` activator tables in `code_shortcuts.dart` |
  | no-op | `10fdbc1` | `onFocusReceived() => false` — already present in the fork tree (added to `_code_input.dart` before 7a); the pick applied without a textual conflict but duplicated the method, so it was dropped |
  | skip | `5e9cfa1`+`367192d`, `880c4ed`+`4b34f7d` | net-zero pairs |
  | skip | `20e4b11` | logically identical rewrite |
  | skip | `bf2e2b7` | `modes.isEmpty` guard; unreachable here (no `CodeHighlightTheme` passed) |
  | skip | `febb8eb`, `93db119` | new public API (`moveCursorToPageUp/Down`, `sperator`→`leadingDivider`) — rule |
  | skip | `90ed36e` | re-maps existing shortcut bindings (Ctrl+Delete → Shift+Delete etc.) — behaviour change, not a fix |
  | skip | `000d8c3`+`830fad1`, `5526c38` | reflow-only conflicts for paths ANTA does not use (built-in autocomplete; `findController:` — the app uses `findBuilder`) — record as declined |

  Four of the seven conflicts are pure formatting (`code_shortcuts.dart`,
  `_code_editable.dart` have zero fork delta); only `04b240d` and the two
  `code_editor.dart` commits collide with code the fork owns.

Work:

1. Item 6: the semantic diff as above; write the **fork delta as a
   19-entry patch list** (1–3 lines each) plus the upstream-candidate
   table and a corrected provenance block into
   `re-editor-performance-2026-07.md` (currently 81 lines, names only 2 of
   the 19 files, no provenance). Fix the §1.5 stale claims here and in
   COPILOT_CONTEXT ("36 files" → 37: `code_paragraph_testing.dart` is the
   fork's only added file).
2. Cherry-pick the "clean" four (`10fdbc1` is a no-op — already present);
   hand-port `04b240d` with a regression
   test in `test/re_editor/` (a viewport that would have recursed:
   assert layout terminates and `first.index == 0` is not re-entered).
3. Item 2, finished: `dc27ee5` covers three sites; extend the nullable
   pattern (`_code_selection.dart:781-813` already has it) to the rest of
   the every-tap-down path — `_tryInterceptTap:73`, mobile `onTapDown:179`,
   desktop `onPointerDown:252`, `_selectPosition:479/483`,
   `_extendSelection:453/457`, `_autoScrollWhenDragging:525` (100 ms
   `Future.delayed` loop with no mounted check) and `ensureRender:816`.
   ~12 sites, ~60 lines, one file.
4. Item 5: `test/re_editor/paragraph_cache_identity_test.dart` (or
   appended to `hanging_paragraph_test.dart`) over the existing
   `CodeParagraphProviderForTesting` — zero production change. A
   `_CountingSpan extends TextSpan` (override `==` too, `hash_and_equals`):
   same instance twice ⇒ `identical(p1, p2)` and the count unchanged after
   the first build; a value-equal distinct instance ⇒ same `IParagraph`
   via the L2 map, count incremented; `clearCache()` empties both. Traps:
   `updateBaseStyle` before `build`; same `maxWidth` on both calls
   (`_code_paragraph.dart:463-466` clears on width change); count only
   from after the first build; needs
   `TestWidgetsFlutterBinding.ensureInitialized()` (a `TextPainter` is
   built).
5. Decision 6, ownership (after everything above is green and
   committed): run `dart format packages/re_editor/lib` and commit the
   reflow **alone**, with no semantic change in the same commit, so the
   patch list written in item 1 stays the last diff that needed
   format-both-sides. Then, in a third commit, retire the "avoid
   API-breaking changes" sentence for the fork in `CLAUDE.md`
   (Architecture, the `packages/re_editor/` bullet) and in
   COPILOT_CONTEXT "Generated And Local Package Notes", replacing it with
   the ownership statement: fork owned as of the 7a sync, upstream HEAD
   `28d9fc0` the last evaluated, cherry-picks one-off and by decision,
   the optimizations list still binding.

Exit: `dart analyze packages/re_editor/lib` clean, `test/re_editor/`
green (3 existing + 2 new), a device scroll-and-search check for
`04b240d`, fork pubspec unchanged (version is not part of the sync),
three commits (sync, format, ownership rule).

**Outcome — DONE 2026-09-04 (the sync commit only; work items 1–4 of
this block), on b5fcdbd.** Full suite 2,978 → **2,988** passing (7
benchmark cases skipped by default); `test/re_editor/` is five files (3
existing + `layout_loop_test.dart` 6 cases + `paragraph_cache_identity_test.dart`
4 cases), 36 passing + 1 skipped; `dart analyze lib`, `dart analyze
test/re_editor` and `dart analyze packages/re_editor/lib` clean apart
from the fork's two pre-existing `avoid_print` infos in `debug/_trace.dart`.
Fork pubspec untouched (0.8.0). What landed, item by item:

1. Item 6: both upstreams cloned into the scratchpad only; a scratch git
   repo carried `dfbca60` + the fork tree as one commit with `reqable`
   fetched, so every cherry-pick ran outside ANTA's repo and only files
   were copied back. Format-both-sides diff (Dart 3.12.2) reproduced the
   plan's semantic figures exactly and its raw figures within four lines
   once measured with `git diff --no-index`: 19 files +1,877/−134
   semantic; the authoritative raw count is 34 files +3,718/−2,244 (the
   plan's +3,722/−2,248 was the pre-sync measurement), as recorded in
   `re-editor-performance-2026-07.md`. Reflow 66 %
   of raw churn, the paragraph pair 926/2,011 = 46 % of the semantic
   delta — the plan's "46 % not 58 %" stands. `re-editor-performance-2026-07.md`
   is now the fork reference: provenance block, the 19-entry patch list
   with per-file counts, the 18-row upstream candidates table with
   verdicts and reasons, the old 2026-07-18 batch kept under its own
   heading. §1.5 and COPILOT_CONTEXT corrected (37 files, HEAD `28d9fc0`,
   pubspec frozen at 0.8.0, format-both-sides recipe).
2. Cherry-picks: **four** landed clean — `512ba8d` (numpadEnter in the
   desktop `Shortcuts` tables; the mobile `Focus.onKeyEvent` path already
   had it), `4f3cb30`, `6bd7151` (`keyboardAppearance`, additive),
   `dc27ee5`. `10fdbc1` was a **no-op**: `onFocusReceived() => false` is
   part of the fork's own delta, the pick applied without a textual
   conflict and produced a duplicate method definition, so it was
   dropped. Every skip row was trial-applied and recorded: six apply
   clean but stay declined for the plan's reasons (the two net-zero pairs,
   `20e4b11`'s identical rewrite, `bf2e2b7`'s unreachable guard), six
   conflict (`febb8eb`, `93db119`, `90ed36e`, `000d8c3`, `830fad1`,
   `5526c38`). The four comment lines the picks carried were stripped
   (repo rule); the code is verbatim.
3. `04b240d` hand-port: the fork has **three** self-calls of
   `_updateDisplayRenderParagraphs`, not four (document shrank below the
   first shown line; empty rebuild; the top-gap check) — `forceRepaint`
   and `performLayout` are entry points and stay at cycle 0.
   `_kMaxLayoutCycles = 10`, `[int cycle = 0]`, the top-gap recursion
   gated on `first.index > 0`, `_jumpVerticallyTo` clamping all four
   vertical jumps in `makePositionVisible` to `[0, _verticalViewportSize]`,
   and the below-viewport distance counted from `last.index`.
   `makePositionCenterIfInvisible`'s own clamp, `_alignTopEdge` /
   `_alignBottomEdge` and the horizontal jumps untouched. The regression
   test drives the public API only (a bare `CodeEditor`, the display
   window read through `indicatorBuilder`'s `CodeIndicatorValueNotifier`,
   the offset through `CodeScrollController.verticalScroller.position`):
   "an offset a hair above the first line does not loop layout" fails on
   the pre-port file with `StackOverflowError` inside `performLayout` and
   the offset frozen at −1.0 forever; post-port the spring walks it back
   to exactly 0.0. The other five (near-end jump lands, below-viewport
   jump stays in range, centering stays in range, jump to line 0 is
   exactly 0.0, twenty resting frames at the top never re-layout) pass on
   both and stand as forward guards.
4. Item 2, whole file: both `render` getters in `_code_selection.dart`
   are nullable type-checks (`is _CodeFieldRender ? … : null`, the State's
   with a `mounted` guard in front), `ensureRender` is deleted,
   `lineHeight` / `_lineHeightAt` / `attached` collapsed onto the getter,
   and every caller early-returns — tap interception, mobile/desktop
   tap-down, long-press, double-tap, secondary tap, `_extendSelection`,
   `_selectPosition`, the drag-autoscroll loop (stops rescheduling once
   unmounted), toolbar, handles, handle drags and both handle-autoscroll
   loops. `_getHandleDy` takes the render as a parameter (a 0 fallback
   would divide by zero); `init()` leaves `_inited` false when detached so
   a later `showHandle` retries. Zero `as _CodeFieldRender`
   casts remain. Interceptor state machine untouched (7b's). (The
   handle-drag guards were *not* safe as shipped — two of the three
   start-handle fields were assigned after the guard; the 2026-09-05
   review dropped `late` from all six handle-drag fields
   (`_startHandleDragPositionToCenterOfLine`,
   `_startHandleDragLastPosition`, `_startHandleDragPosition` and the
   end-handle twins) and gave them defaults, so a detached render at drag
   start can never leave one unassigned.)
5. Item 5: `paragraph_cache_identity_test.dart` over
   `CodeParagraphProviderForTesting` with a `_CountingSpan extends
   TextSpan` counting `==`/`hashCode`: same instance twice ⇒ identical
   paragraph and zero calls after the first build; distinct value-equal
   instance ⇒ the same `IParagraph` with `hashCode` called (L2
   fall-through); `clearCache()` and a `maxWidth` change ⇒ a new instance.
   Zero production change.

Work item 5 followed on 2026-09-05 as its own two commits: `72401b8`
(format-only — **two lines**, not 32 files: the plan's "32 of 37 reflow"
was measured on pubspec-less copies, which the formatter treats as the
newest language version and reflows in the tall style; under the fork's
own `>=2.17.3` SDK floor `dart format` uses the short style and the tree
was already clean apart from the two cherry-picked `4f3cb30` lines) and
the ownership-rule commit that follows it (CLAUDE.md fork bullet,
COPILOT_CONTEXT fork-notes bullet, the markdown-engine skill sentence).

Deviations from the plan: four picks, not five (`10fdbc1`); three
recursive sites, not four; item 2 covered the whole file rather than the
listed dozen sites (the nullable getter forced every caller); the plan's
own 7a table row for `10fdbc1` was rewritten to "no-op" so the doc does
not contradict the reference; the picks' comments were removed.

Device pass (emulator-5554, Android 16, 74-line note, keyboard up so the
viewport is ~14 lines): search `12` (41 matches), jump to match 39 from
the match sheet — scrolled into view, no freeze; next twice to 41 — the
last line, scrollbar at the range end, no bounce; next wraps to 1 — the
true top (a further drag moves nothing); DTD reports no runtime errors.

Traps: on a Windows checkout the fork's files carry CRLF, so `diff -ruN`
over-counts every line — use `git diff --no-index` (or
`--strip-trailing-cr`); a cherry-pick of a change the fork already
carries can apply with **no conflict** and leave a duplicate member — a
compile error, not a merge marker — so `dart analyze` after every pick;
the app does not compile in `flutter_driver`'s extension, so device
checks go through `adb shell input tap/text/swipe` + `exec-out screencap`
with a DTD connection for runtime errors; `LinkedHashMap.identity()`
never calls a key's `==`/`hashCode` (it is `identical`/`identityHashCode`
by construction), so a counting span measures only the L2 fall-through;
a `const` constructor on a `TextSpan` subclass that is only ever invoked
non-const keeps instances distinct and satisfies
`prefer_const_constructors_in_immutables` without an ignore; post-port
`makePositionVisible` can no longer produce an out-of-range offset, so
the only way to reach the old loop from a test is a raw
`position.jumpTo(-1.0)`; two workers editing two fork files in parallel
break each other's compile mid-edit (`ensureRender` vanished under the
port worker) — sequence them or have the second poll until the analyzer
is clean.

#### Session 7b — interceptor hardening + harness (items 3, 4)

The state machine is five fields and three methods on
`_CodeSelectionGestureDetectorState` (`_code_selection.dart:41-114`);
there is no `onPointerMove` on the desktop `Listener` at all, and a
successful second `_tryInterceptTap` overwrites all four claim fields
unconditionally (`:77-80`).

1. Item 3, in `_code_selection.dart` only (~40 lines): a guard at the top
   of `_tryInterceptTap` (`if (_interceptedTapPosition != null) return
   false;` — mobile needs it too, `_interceptedTapPointer` is always null
   there); a desktop `onPointerMove` that, for the claiming pointer past
   the mouse/touch slop (same rule as `:100-101`), cancels the claim and
   starts the drag. **The hidden decision**: `_onDesktopTapDown` was
   skipped at claim time (`:249` returns before `:255`), so
   `_anchorSelection`, `_pointerTapTimestamp` and the caret were never set
   — replay `_onDesktopTapDown(downOffset)` before flipping `_tapping`, or
   the drag extends from a stale selection. Update the doc comments at
   `:43-52` and `:60-63`.
2. Item 4 as **two files**, because `kIsAndroid`/`kIsIOS` are top-level
   finals fixed for the whole test process
   (`modern_editor_wrapper_desktop_indent_test.dart:20-37` — override in
   `setUpAll` before the first editor builds): `test/re_editor/
   tap_interceptor_test.dart` on the default platform (claim→up fires once
   and leaves `selection` identical; two consecutive taps both fire; a
   claimed tap never focuses; claim→cancel via long-press against
   `onTapCancel`) and `tap_interceptor_desktop_test.dart` (claim→
   `gesture.cancel()` against `Listener.onPointerCancel:266`; second claim
   refused; move past slop → claim released, drag selection extends). Build
   a bare `CodeEditor(padding: EdgeInsets.zero, tapInterceptor:
   CodeEditorTapInterceptor(...))` with a fake zone — both types are
   public, no fork change needed; borrow `positionOf` / `pumpEditor` /
   `teardownEditor` from `modern_editor_wrapper_tag_tap_test.dart:20-96`
   (cursor-blink timers: pump 200 ms, `pumpWidget(SizedBox.shrink())`,
   `pump()`, never `pumpAndSettle` after teardown; the Android selection
   handle hangs one line box under the caret, park follow-up taps at
   column 9; desktop focus is a deferred `Future`, pump once before
   asserting). ~380 lines total; the first `startGesture`-style tests
   against the editor.

Exit: both suites green, `dart analyze packages/re_editor/lib` clean, a
desktop run (`flutter run -d windows`) confirming click-drag from a
checkbox selects text and a click on it still toggles. Unblocks Session
11's harness dependency.

**Outcome — DONE 2026-09-04, on fcfe704 (the 7a sync).** Full suite
2,988 → **2,998** passing (7 benchmark cases skipped by default);
`test/re_editor/` is seven files, 46 passing + 1 skipped; `dart analyze
lib` and `dart analyze packages/re_editor/lib` clean apart from the
fork's two pre-existing `avoid_print` infos. One fork file changed
(`_code_selection.dart`, +35/−6), two test files added, no wrapper or
policy change. What landed:

1. Item 3: `_tryInterceptTap` refuses a claim while one is live (first
   statement, before the interceptor null-check; a desktop rule — on
   mobile it is unreachable, because `_tryInterceptTap` runs only from
   `GestureDetector.onTapDown`, which a tap recognizer sends at most once
   per gesture and always follows with `onTapUp` or `onTapCancel`); a
   refused press writes nothing and takes the plain path exactly like a
   non-zone tap. Desktop `Listener.onPointerMove`: for the claiming
   pointer only, past the slop (`kPrecisePointerHitSlop` mouse /
   `kTouchSlop` touch, `<=` keeps the claim so the rule mirrors
   `_finishInterceptedTap`'s `>`), it replays `_onDesktopTapDown` at the
   ORIGINAL down offset (caret + pairing state as a plain press would have
   set them; `_tryInterceptTap` had nulled the pairing state, so no
   accidental double-click), flips `_tapping`, cancels the claim and
   schedules the same deferred `ensureInput`. The `Listener` sees the
   move before the wrapping `GestureDetector`'s recognizers (deepest
   first), so the drag recognizer's own acceptance on that or the next
   move finds `_tapping` already true and `onVerticalDragStart` /
   `_onDrag` → `_extendSelection(drag)` run unchanged; `onPointerUp`
   then finds no claim and runs the plain `_onDesktopTapUp`. The two doc
   comments (claim fields, `_tryInterceptTap`) now state the one-claim
   rule and the release-into-drag. No mobile `onPointerMove` (long-press /
   tap-cancel already release there). **Three rules corrected by the
   2026-09-05 review**: the slop test is per-axis through
   `computeHitSlop(kind, MediaQuery.maybeGestureSettingsOf(context))` (a
   private `_withinHitSlop`) at BOTH the move-release rule and
   `_finishInterceptedTap`, so a claimed press either fires or becomes a
   drag exactly where the drag recognizers would accept — the euclidean
   rule above had a window (mouse jitter under 1 px per axis) that
   released the claim, moved the caret and focused the editor while
   firing nothing; a stranded claim (the claiming pointer's up/cancel
   never reaching the `Listener` — capture steal, `PointerRemovedEvent`)
   is recovered on the next primary press from the same mouse device
   (`_interceptedTapDevice`); and both deferred `Future(ensureInput)`
   sites are `mounted`-guarded.
2. Item 4, two files as planned. `tap_interceptor_test.dart` (Android
   path, 5): claim→up fires once with the selection identical; two
   consecutive claims both fire (400 ms apart so they never pair); a
   claimed tap never focuses while a plain tap does; a held zone press
   past `kLongPressTimeout` never fires; a non-zone tap moves the caret.
   `tap_interceptor_desktop_test.dart` (5, `debugDefaultTargetPlatformOverride`
   = linux resolved in `setUpAll` and cleared at once): `gesture.cancel()`
   never fires and a fresh tap fires afterwards; a second mouse press
   while a claim is live is refused and behaves as a plain press (caret
   moves to it) while the first claim still fires on its own up; moving
   past the slop releases into a drag whose base is line 0 offset 1 (the
   down cell) and extent line 1 offset 6, with focus after the deferred
   Future; a move inside the slop keeps the claim; a plain click fires,
   selection untouched, no focus. Both suites mount a bare `CodeEditor`
   with a fake zone (`index == 0 && offset < 3`) and read line geometry
   from the editor's own `CodeIndicatorValueNotifier`.

Docs: the markdown-engine skill's tap-policy sentence and a new
COPILOT_CONTEXT fork-notes bullet carry the one-claim / release rules;
the roadmap Done list.

Desktop pass (`flutter run -d windows`, fresh workspace, a note with two
task lines, a `[link](…)` line and two plain lines, driven by
`SetCursorPos` + `mouse_event`): click-drag from the first checkbox
selects from the line start through line 4 and the box stays `[ ]`; a
plain click on the second box toggles it to `[x]`; a press on the first
box released over the link becomes a selection through `[link` — the
link does not open and the box does not toggle; DTD reports no runtime
errors.

Traps: `Future(ensureInput)` is a zero-duration `Timer`, and a bare
`tester.pump()` only flushes microtasks — assert desktop focus after
`pump(Duration.zero)`; the desktop suite's platform override must be
resolved and cleared inside `setUpAll` (the finals cache on first read,
and a debug variable left set fails the test); in PowerShell `Type` is
the `Get-Content` alias, so a UI helper of that name reads a file instead
of typing — name it `SendText`; `SendKeys` needs `{[}` `{]}` `{(}` `{)}`
for the markdown brackets; a mouse cannot press a second zone while one
is held (single pointer), so "a click on a link while another zone is
pressed" is exercised on desktop as press-move-release, which the
release rule turns into a selection — the two-pointer refusal is proven
by the widget test, not the device.

#### Session 7c — accessibility (item 1, decision 3)

`describeSemanticsConfiguration` (`_code_field.dart:549-569`) sets
`value = _codes.asString(...)` and no action. `flushSemantics` runs after
layout, so `_displayParagraphs` (`:151`, rebuilt in
`_updateDisplayRenderParagraphs:1105-1206`, exactly the on-screen window,
sorted by `index`) is never stale when it is read there — but it carries
layout only (`IParagraph` has no text getter), so the value is rebuilt
from `_codes[p.index].text`, which is the same per-line text `asString`
uses (chunks not expanded either way). Four parts, in size order:

1. **(A) visible-window value** — `_code_field.dart` only, ~20 lines:
   loop over `_displayParagraphs`, join with `\n`, `isEmpty` guard, and
   rewrite the doc comment at `:549-554` (it advertises the `asString`
   cache, which becomes wrong). Closes P11.
2. **(B1) `onTap` + `onDidGainAccessibilityFocus`** — widget layer, not
   the render (the render has no controller and no focus node; Flutter
   does the same split — `RenderEditable` never sets these,
   `material/text_field.dart:1807-1830` does). A `Semantics` wrapper at
   `code_editor.dart:588-600` where `_editingController`,
   `_inputController`, `_focusNode` are all in scope; both `Focus` widgets
   there already pass `includeSemantics: false`. `onTap` →
   `ensureInput()` with a collapsed-selection fallback when the selection
   is invalid. ~30 lines.
3. **(B2) `onSetSelection` + `textSelection`** — coupled to (A): the
   platform sends flat offsets into whatever string was announced, so a
   window-relative value forces a window-relative
   `CodeLinePosition ⟷ flat offset` mapping (new helper on the render, the
   only place with both `_displayParagraphs` and `_codes`;
   `index2lineIndex` is document-wide and does not help). Route the
   result through the controller the way `_selectPosition:498-501` does.
   ~60 lines. Ship with (A) or not at all.
4. **(C) zones reachable** — the large part. "Performs the same action"
   needs no state-machine change: `CodeEditorTapInterceptor` is
   `CodeLinePosition`-only and `EditorInputPolicy.resolveTap` is a pure
   function, so a semantics handler calls `shouldIntercept(pos)` then
   `onTap(pos)` back to back and the wrapper's claim memo accepts it
   unchanged (`modern_editor_wrapper.dart:325-362`). "Reachable" is the
   cost: `resolveTap` answers "what does offset N do", nothing enumerates
   "which ranges on this line are zones". So: `explicitChildNodes = true`
   + an `assembleSemanticsNode` override in `_code_field.dart` producing
   one child per zone rect via `CodeLineRenderParagraph.getRangeRects`
   (`code_line.dart:1054`) with a keyed node cache for stable ids
   (Flutter's `editable.dart:1418-1540` is the template; ~90 lines
   without bidi/placeholders); a third member on `CodeEditorTapInterceptor`
   (`List<(TextRange, String)> Function(int lineIndex)`) plumbed from
   `_CodeSelectionGestureDetector` down through `_CodeEditable` to
   `_CodeField` (the interceptor stops above `_CodeEditable` today,
   `code_editor.dart:588-596`; ~30 lines); a range-enumerating sibling of
   `resolveTap` in `editor_input_policy.dart` (checkbox from
   `MarkdownListSyntax`, links from `MarkdownInlineGrammar`, money from
   `MarkdownMoneySyntax`, tags — ~80 lines) with an **agreement test**
   that every enumerated cell resolves to the same action through
   `resolveTap` and every non-enumerated cell to none; wrapper wiring
   (~20 lines); four zone labels in the three ARBs.

**Execution order (added 2026-09-04) — four commits, each green, so a
window that runs out mid-way loses nothing.** Steps 1–3 are ~110 lines in
two fork files and can share one sitting; step 4 is the one to start
fresh.

0. **Five-minute risk check before any code.** `RenderEditable` never
   combines a text-field `value` with `explicitChildNodes` — it drops the
   value when it has child nodes (`editable.dart:1337-1346`). Step 4
   wants both. Build a throwaway config in a widget test
   (`isTextField`, `value`, `explicitChildNodes = true`, one child from
   `assembleSemanticsNode`) and confirm the semantics binding does not
   assert. If it does, the children go on a sibling `Semantics` container
   above the field (a `Semantics(container: true)` wrapping a
   `CustomPaint`-sized box per zone is the fallback) — decide this before
   writing step 4, not after.
1. **(A) + the P11 proof.** Rewrite the value; add
   `@visibleForTesting static int debugAsStringCalls` incremented in
   `CodeLines.asString` (`code_lines.dart:437`; pattern:
   `ModernEditorWrapper.debugTapResolveCount`). Check: with a
   `tester.ensureSemantics()` handle, `find.semantics.byValue(...)` matches
   the joined visible lines and nothing more on a 200-line note in a
   short viewport; scroll, pump, the value is the new window; type one
   character, the counter has not moved. Dispose the handle before
   `teardownEditor`.
2. **(B1).** Check: `tester.semantics.performAction(find.semantics
   .byAction(SemanticsAction.tap), SemanticsAction.tap)` → the focus node
   has focus after one pump (the ensure-input `Future`), the selection is
   valid; a second tap does not reset the caret.
   `didGainAccessibilityFocus` → focus requested without opening the
   keyboard (mirror `text_field.dart`).
3. **(B2).** The platform sends `args = {'base': int, 'extent': int}`
   (`semantics.dart:5613-5617`) — offsets into the announced string, so
   window-relative. Check: `performAction(..., SemanticsAction.setSelection,
   args: {'base': 3, 'extent': 3})` on a window starting at document
   line 40 puts the controller caret at line 40 offset 3; a base/extent
   spanning a `\n` becomes a two-line `CodeLineSelection`; the node's
   `textSelection` equals the controller selection mapped back. When the
   caret is off-screen, **omit `textSelection`** rather than clamp — do
   not announce a position that is not in the value. Test both.
4. **(C).** Land in this order, each with its test: the enumerator in
   `editor_input_policy.dart` + the agreement table (reuse the Session 6
   `EditorInputPolicy` fixture lines: for every line and every offset,
   `resolveTap(offset) != null` ⇔ some enumerated range contains the
   offset, and the action type matches the range's label kind; caret-line
   reveal and fence lines enumerate nothing, exactly like `resolveTap`) →
   the third `CodeEditorTapInterceptor` member + plumbing → the child
   nodes with a **keyed node cache** (without stable ids TalkBack focus
   jumps on every rebuild) → wrapper wiring → four labels in the three
   ARBs + `flutter gen-l10n`. Checks: `find.semantics.byLabel(<toggle
   label>)` finds one node per checkbox on visible lines; its rect equals
   `getRangeRects` for the `[ ]` cells; `tester.semantics.tap(...)` on it
   turns `- [ ]` into `- [x]` in `controller.text` and the caret does not
   move; the link node's tap fires `onOpenLink` with the URL; the nodes on
   the caret line are absent (a11y focus is not the caret, so the reveal
   rule holds unchanged); `tester.semantics.simulatedAccessibilityTraversal()`
   with `containsAllInOrder` reads the field value first, then the zones in
   line order.

**Why widget tests, not `integration_test/`.** The repo has no
`integration_test` dependency or directory, and adding one buys nothing
here: an integration test drives the same `SemanticsOwner` a widget test
drives (`performAction` calls `node.owner!.performAction` — the exact
entry point the platform uses), and TalkBack itself cannot be scripted
from either. Everything above is therefore a real proof of the contract
the screen reader consumes: tree shape, labels, value, actions, and what
each action does to the controller. The only things a widget test cannot
prove are TalkBack's own reading behaviour, explore-by-touch focusability
of the child nodes on Android, and the platform-channel cost behind P11.
For the cost, if a number is wanted, use the §5 recipe (`gfxinfo
framestats` while typing with TalkBack on) — a benchmark, not a gate.

**Device pass (five minutes, owner, after the suites are green).**
TalkBack on, open a long note with a checkbox and a link, caret at the
top: (1) swipe to the editor — it reads the visible lines, not the whole
note; (2) double-tap — keyboard opens; (3) type three characters — no
stall (this was the P11 freeze); (4) swipe forward — "toggle task" is
reachable, double-tap flips it, the text under it now shows `[x]`;
(5) scroll a screen and swipe back to the field — the value has moved.
Anything that fails here but passed the suites is a platform-layer
issue, not a fork bug — record it, do not iterate on the fork for it.

Exit: the four commits above, the suites green, `dart analyze lib` + fork
clean, the device pass recorded in this block.

**Outcome — DONE 2026-09-05, six commits on top of 7b's `d9621bb` (after
7a's deferred `72401b8` format + `684b553` ownership commits).** Full
suite 2,998 → **3,102** passing (7 benchmark cases skipped);
`test/re_editor/` is 11 suites, 72 passing + 1 skipped; `dart analyze
lib`, `dart analyze test` and `dart analyze packages/re_editor/lib`
clean apart from the fork's two pre-existing `avoid_print` infos.
Commits, in landing order: `3866ef2` (A), `e403a35` (C1: enumerator +
agreement suite + labels), `12dad1e` (B1), `f602056` (B2), `be24f73`
(C2: child nodes + wrapper wiring), `8cb585d` (C3: the teardown fix the
device pass forced, below), then the docs commit. The review block below
carries the post-review numbers. What landed, in plan order:

0. **Risk check: passes on the same node.** A throwaway render with
   `isTextField` + `value` + `explicitChildNodes` + one
   `assembleSemanticsNode` child asserted nothing on Flutter 3.44.2,
   `byValue` and `byLabel` both found their nodes, and traversal read
   the field before the child. `RenderEditable`'s value-vs-children
   exclusion is a choice in its own `describeSemanticsConfiguration`,
   not a framework rule, so the sibling-container fallback was never
   built.
1. **(A)** `describeSemanticsConfiguration` announces
   `_visibleWindowText()` — `_displayParagraphs` lines from `_codes`
   joined by `\n`, out-of-range indices skipped, `''` for an empty
   window; the doc comment that advertised the `asString` cache was
   rewritten. `CodeLines.debugAsStringCalls` is the P11 proof:
   `semantics_value_test.dart` (4) pins the window value, the window
   after a scroll, an edit through the controller with the counter still
   at **0** (nothing else on a bare editor's edit path calls
   `asString`), and the empty document.
2. **(B1) — the plan's widget shape does not work; the render carries
   the actions.** A `Semantics` wrapper above the boundary render sends
   its actions *up* (configs merge child → node-forming ancestor only;
   `MergeSemantics` merely flags the child `isMergedIntoParent`, and
   `byFlag(isTextField)` still lands on the render's node), and dropping
   the boundary would remove `assembleSemanticsNode` — which (C) needs.
   Verified with the failing output `Bad state: The given node does not
   support SemanticsAction.tap` before switching. So the handlers stay
   in `code_editor.dart` (controller/input/focus in scope) and reach the
   render through explicit callbacks plumbed `_CodeEditable` →
   `_CodeField` → render setters that `markNeedsSemanticsUpdate()`.
   `onTap`: collapse an out-of-document selection to 0/0, then
   `ensureInput()` (read-only is handled by `ensureInput` itself, which
   never opens the IME then — better than `text_field.dart`, which sets
   no `onTap` when read-only). `onDidGainAccessibilityFocus`:
   `requestFocus()` **plus `consumeKeyboardToken()`** — the fork's focus
   listener opens the IME whenever the token is unconsumed, so the SDK's
   bare `requestFocus` *does* raise the keyboard here (test 3 fails
   without that line). No `onDidLoseAccessibilityFocus`: the SDK's
   one-liner would unfocus the editor the moment TalkBack steps onto a
   zone child. `semantics_actions_test.dart` (5, 6 after the review),
   watching `SystemChannels.textInput` for `TextInput.show` / `setClient`.
   **Corrected by the 2026-09-05 review**: the a11y-focus handler is
   plumbed only when `defaultTargetPlatform == TargetPlatform.macOS`,
   mirroring Material's `text_field.dart`, which sets
   `onDidGainAccessibilityFocus` / `onDidLoseAccessibilityFocus` only
   under macOS and neither on Android/iOS — the 7c version fired on
   Android, where a TalkBack sweep across the editor would take keyboard
   focus and never release it. `requestFocus()` + `consumeKeyboardToken()`
   remain the focus-without-keyboard idiom for macOS; there is still no
   lose handler. The 7c device pass never depended on it (double-tap →
   `onTap` opens the keyboard).
3. **(B2)** `positionForWindowOffset` / `windowOffsetForPosition` on the
   render (per displayed line `length + 1`; a separator offset resolves
   to the end of the line before it — falls out of the arithmetic;
   negative clamps to the window start, past-the-end to the last visible
   line's end; empty window → null). `textSelection` is set only when
   both ends map, **omitted** otherwise; `onSetSelection` maps
   base/extent independently (reversed stays reversed) and hands a
   `CodeLineSelection` to `onSemanticsSetSelection`, which mirrors
   `_selectPosition`'s identity early-return, `value.copyWith(selection:,
   composing: TextRange.empty)` and `makeCursorVisible()` and skips its
   chunk-indicator, hit-test and pointer-bookkeeping branches;
   `ensureInput` is not called (it lives in `_onMobileTapUp`, not in
   `_selectPosition`). (`RenderObject.layout()` marks semantics after
   every `performLayout`, so the setter's own `markNeedsSemanticsUpdate()`
   was redundant and the review removed it.)
   `semantics_selection_test.dart` (8, 10 after the review).
4. **(C)** `EditorInputPolicy.zonesOf` + `EditorTapZone` (start, end,
   action) — grammar-driven, not offset-scanning: candidates from
   `MarkdownListSyntax.parse`, a new thin `MarkdownInlineGrammar.linksAndTags`
   walker (the whole-line form of `linkAt`/`tagAt` — since the 2026-09-05
   review `linkAt`/`tagAt` are expressed over it (first `InlineLink` /
   `InlineTag` with `containsStrict`), so one descent exists; it takes
   the line's ghost runs from the caller), `MarkdownMoneySyntax.parse`;
   precedence and clipping by a
   per-offset owner array (first claim wins, ghost runs cleared last),
   equal-owner runs coalesced — since the review the claim table spans
   only `[min candidate start, max candidate end)`, not the whole line.
   The agreement group runs every fixture row
   × every offset (`resolveTap` ⇔ a covering range, same action);
   `editor_input_policy_test.dart` 66 → 154 with three ghost-in-link
   fixtures added (174 after the review). `CodeEditorTapInterceptor.zonesOf` +
   `CodeEditorSemanticsZone` (start/end/label) on the fork; the render
   gets `semanticsZonesOf` and `onSemanticsPerformZone` (the tap-down /
   tap-up pair at the zone start, which the wrapper's claim memo accepts
   unchanged); `explicitChildNodes` only when `zonesOf` is set;
   `assembleSemanticsNode` builds one keyed child per zone per visible
   line (rect = `getRangeRects` union shifted by `paragraph.offset −
   paintOffset`, clipped to the viewport; `OrdinalSortKey` in line
   order; `ValueKey('$line:$start:$end:$label')` cache). Wrapper: labels
   resolved once in `didChangeDependencies`, the enabled-zone set shared
   by both paths, action type → label switch. `semantics_zones_test.dart`
   (6 + 3; 11 after the review) and
   `modern_editor_wrapper_semantics_test.dart` (6; 9 after the review).
   Four things the 2026-09-05 review pinned or changed here: node ids are
   keyed by line index, so an edit that shifts a zone's line renumbers
   its semantics node (a TalkBack focus-continuity cost, now pinned as
   the contract by `semantics_zones_test.dart` alongside a stability case
   that proves ids survive a plain rebuild); the `attached`/`parent`
   reuse guard is defensive with no known trigger; `zonesOf` ran a full
   grammar parse per visible line on every layout while semantics were
   enabled, so the wrapper now memoises zone lists per line text
   (`LruCache`, 256 entries; revealed, fence, over-length and empty lines
   return `const []` before the memo; cleared when the enabled-zone set
   or the four labels change — `didChangeDependencies` compares the
   resolved labels for that; `debugZoneResolveCount` is the proof
   counter); and the fork's `set semanticsZonesOf` is unreachable from
   the app because `CodeEditor` forwards its own bound method, so any
   app-side cache of labelled zones must invalidate itself.
   `CodeLines.debugAsStringCalls` increments only under `assert`.
5. **C3 — found by the device, not the suites.** `uiautomator dump`
   enables semantics per dump; on the second dump the reused cached
   `SemanticsNode`s belonged to the disposed owner: `semantics.dart:3270
   'owner!._nodes.containsKey(id)'`, then `:3008 '!child.attached'`,
   then `object.dart:5713 'node.built'` on every frame and a tree that
   collapsed to the root. Fix = `RenderParagraph`'s shape: a
   `clearSemantics()` override nulling the cache (the hook
   `RendererBinding` calls on owner disposal) plus an `attached`/`parent`
   guard on reuse. No widget-test harness tears the owner down
   (`ensureSemantics().dispose()` and `semanticsEnabledTestValue` both
   leave the tree standing), so the regression test drives
   `renderObject.clearSemantics()` directly and asserts the rebuilt
   node ids are disjoint from the old ones — fails pre-fix with
   `Expected: empty, Actual: Set:[6, 7]`.

Device pass (emulator-5554, Android 16, TalkBack from the Android
Accessibility Suite, the app's own debug build; taps under TalkBack are
explore-by-touch, so single tap = focus, double tap = activate;
`uiautomator dump` reads the platform accessibility tree): (1) the
`EditText` node's text is the on-screen lines only — 30 of the note's
78 — and moves with a scroll; (2) double-tap on the field opens the
keyboard (B1 `onTap`); (3) `input text abc` lands in 128 ms with the
value updated and no error — the P11 stall is gone; (4) each visible
task line exposes a `Toggle task` node with box-sized bounds
(`[96,1235][158,1307]` at 1280 px), a link line an `Open link` node and
a tag line a `Search tag` node starting after the `#` cell; single-tap
then double-tap on the first task node turns its line into `- [x]` while
the other two stay `[ ]` and the caret does not move; (5) the caret line
contributes no node; DTD reports no runtime errors after the whole
sequence (post-C3). TalkBack was switched off again afterwards. Not
provable from here: TalkBack's spoken output.

Deviations: B1 on the render, not a widget (above); a `consumeKeyboardToken`
that the plan did not foresee, plumbed on macOS only since the
2026-09-05 review; six commits instead of four (C split into
enumerator / nodes / teardown fix); the enumerator gained a grammar
walker (`linksAndTags`) rather than scanning offsets; `didChangeDependencies`
label resolution instead of a per-build interceptor; the "stable ids"
the plan asked for are stable per line index, not per zone identity — an
edit that shifts a zone's line renumbers its node, an accepted TalkBack
focus-continuity cost now pinned as the contract.

Traps: a `Semantics` widget never merges into a boundary render on this
SDK — declare actions on the render; `FocusNode.requestFocus()` alone
opens the IME in this fork — `consumeKeyboardToken()` right after it is
the "focus without keyboard" idiom, but the handler carrying it belongs
on macOS only (the 2026-09-05 review: on Android a TalkBack sweep takes
keyboard focus and no lose handler gives it back, which is why Material
sets neither there); keyed semantics child caches must be
dropped in `clearSemantics()` or the second platform enable reuses
nodes of a dead owner; the test binding cannot reproduce that teardown —
call `clearSemantics()` on the render yourself; `uiautomator dump` needs
`MSYS_NO_PATHCONV=1` under Git Bash (the `/sdcard` path gets rewritten)
and `grep -c '<node'` counts lines of a one-line XML; TalkBack's first
enable pops a notification-permission dialog that steals every tap —
`pm grant … POST_NOTIFICATIONS` first; the device shell eats `(`, `)`
and `#` in `adb shell input text` — double-quote a single-quoted
string; `settings put secure enabled_accessibility_services ""` is "Bad
arguments" — use `settings delete`.

#### Session 7 review — 2026-09-05

Five read-only passes over the shipped 7a/7b/7c code (7a fork sync, 7b
interceptor, 7c fork semantics, 7c app policy/wrapper/l10n, docs drift),
then two implementation passes applying what they found. Nothing
committed; the working tree sits on `b1da783`. Two of the findings are
real bugs (A1, B1), one of them a regression against 7a's own guard work.

**7a.** A1 (bug): all six mobile handle-drag fields were `late`, and two
of the three start-handle ones were assigned *after* the detached-render
guard, so a drag start on a detached editor traded the cast crash for a
`LateInitializationError` — 7a's outcome block claimed the opposite. All
six are plain fields with defaults now. A2: the drag-autoscroll loop and
both handle-autoscroll loops returned on a single null-render tick,
ending the loop for good;
they now skip that tick and reschedule. A3: `dispose()` looked the render
up again to detach its viewport listeners and returned early when it was
already gone — it stores the two `ValueListenable`s at `init()` time,
detaches from those, and resets `_inited`. A4: the six remaining
`as _CodeFieldRender?` casts outside `_code_selection.dart`
(`_code_editable.dart`, `_code_input.dart` ×3, `_code_line.dart`,
`code_scroll.dart`) became nullable `is` type-checks behind a private
`_render` getter — the shape 7a gave the selection layer. A5:
`showHandle` bails when `init()` left `_inited` false. A6: the top-gap
recursion in `_updateDisplayRenderParagraphs` was the one self-call
`04b240d`'s counter did not gate, so it could re-enter forever; it now
publishes on the capped frame. A7: a `makePositionVisible` test asserted
against the `first.index` formula the port replaced — it fails on the
`last.index` one and was rewritten. A8: the paragraph-cache `maxWidth`
case never changed the width it claimed to change (vacuous pass).

**7b.** B1 (bug, and a regression against 7a): `_finishInterceptedTap`
and the move-release rule compared euclidean distance against a
hand-picked `kPrecisePointerHitSlop`/`kTouchSlop`, which is stricter than
what the drag recognizers accept — a diagonal mouse jitter under one
pixel per axis released the claim, moved the caret and focused the editor
while firing neither the zone action nor a drag. Both sites now use a
private `_withinHitSlop`, per axis, through
`computeHitSlop(kind, MediaQuery.maybeGestureSettingsOf(context))`. B2: a
claim whose pointer's up/cancel never reaches the `Listener` (capture
steal, `PointerRemovedEvent`) stranded the interceptor — the next primary
press from the same mouse device (`_interceptedTapDevice`) drops it
first, because one mouse cannot hold two primary presses. B3: both
deferred `Future(ensureInput)` sites are `mounted`-guarded. B4–B6, tests:
the long-press case proves the release by tapping a *different* column
(the old assertion passed on an unchanged selection either way);
`pump(Duration.zero)` before every desktop focus assertion; a cancel from
a non-claiming pointer leaves the live claim alone; and the same-device
recovery case — where the "second press refused" test needed a genuinely
different device, since two mouse `TestGesture`s share device 1, so it
hand-builds a `PointerDownEvent` with `device: 2`. B7: the claim-field
and `_tryInterceptTap` doc comments now say what is true (the one-claim
refusal is a desktop rule mobile cannot reach; the replay produces the
caret and pairing state a plain press would have). B8: the eleven
`test/re_editor/` suites share `support/editor_test_support.dart` instead
of copying the harness — `teardownEditor`, `settle`, `flushDeferredWork`,
`watchTextInput`, `textField` / `textFieldNode`, `displayedParagraphs` /
`displayedIndices` / `expectedWindow`, `pumpZoneEditor` + `zoneCellOf` +
`expectSameSelection`, `kTestFontSize`, modelled on
`test/database/support/db_test_support.dart`.

**7c.** C1 (bug): `onDidGainAccessibilityFocus` was plumbed on every
platform; Material's `text_field.dart` sets it only under macOS, and on
Android a TalkBack sweep across the editor took keyboard focus that no
lose handler gave back. It is macOS-only now. C2: the `selection` setter's
`markNeedsSemanticsUpdate()` was redundant — `RenderObject.layout()`
already marks semantics after `performLayout` — and is gone. C3:
`CodeLines.debugAsStringCalls` incremented in release too; it is inside
an `assert` block now. C4: zone-node ids are keyed by line index, so an
edit that shifts a zone's line renumbers its node — the accepted cost is
now a test, beside a stability case proving ids survive a plain rebuild.
C5: `semantics_selection_test.dart` gained the one-end-off-screen case
and a select-all that shrinks to the window.

**App side.** `linkAt`/`tagAt` are expressed over `linksAndTags` (first
`InlineLink`/`InlineTag` whose `containsStrict` holds), so one descent
exists rather than two that can disagree; `linksAndTags` takes the
line's ghost runs from the caller. `zonesOf`'s per-offset claim table is
allocated over `[min candidate start, max candidate end)` instead of the
whole line. The wrapper memoises zone lists per line text (`LruCache`,
256) behind the three pass-through rules, holds the enabled-zone set as a
field, drops the memo when that set or any of the four labels changes,
and counts misses in `debugZoneResolveCount`. Tests: the money zone is
exercised with a real `onMoneyTap` and a `$$ balance` line, an en→de
locale switch re-labels every node, a repeat flush resolves zero lines,
and ten agreement rows were added (bare URL, unclosed link,
`{red:[docs](u)}`, `*[docs](u)*`, both halves of `[a](b)[c](d)`,
`- $$ total` plus its marker, both halves of `- [ ] [docs](u)`). The
German labels were wrong in sense: `editorZoneOpenMoney` is
"Kassenbuchdetails öffnen" and `editorZoneSearchTag` "Schlagwort suchen"
— the app has no hashtag-sense "Tag" precedent, every German "Tag" in the
ARB is the calendar day.

**Not changed, on purpose.** `_getHandleDy` still quantises by the flat
`lineHeight`, so a handle drag over scaled headers steps by the base
line — pre-existing, and a design decision, not a fix. `_zoneRect` unions
the range rects across soft wraps with no 4 px padding, which is the
shape Flutter's own `RenderParagraph` produces. Zone coalescing keys on
candidate index rather than action, so two adjacent candidates with the
same action stay two zones — only reachable if `valueSlot == amountStart`,
which the money grammar rules out. `keyboardAppearance` is read once per
input connection (upstream parity). The reviewers' "no code comments"
flags were withdrawn: `///` doc comments are house style here (about
19,100 doc-comment lines under `lib/`, 2,500 under `test/`), so Session
7's test headers stayed and earlier suites were not touched.
`dart format test/re_editor` also reflowed five lines of
`undo_history_cap_test.dart`.

Traps (the review's own): `debugDefaultTargetPlatformOverride` must be
reset inside the test body (try/finally) — the binding's invariant check
runs before `addTearDown`; two mouse `TestGesture`s share device 1, so a
concurrent-press test needs `createGesture` + `downWithCustomEvent` with
an explicit device; `SemanticsConfiguration.onDidGainAccessibilityFocus`
force-unwraps its value, so guard the assignment instead of assigning
null; a caret move always costs one zone-memo miss (the line the caret
leaves was never memoised while revealed), so a zero-miss proof needs a
caret round trip plus a non-vacuity guard (a toggle-node count flipping
2 → 1 → 2); the Bash heredoc eats one level of backslash, so Dart source
gets patched with the Edit tool, never a heredoc.

Numbers: `test/re_editor/` is 81 passing + 1 skipped across 11 suites
plus the shared harness (layout_loop 7, paragraph_cache_identity 4,
tap_interceptor 5, tap_interceptor_desktop 8, semantics_value 4,
semantics_actions 6, semantics_selection 10, semantics_zones 11, plus the
two hanging-paragraph suites); `editor_input_policy_test.dart` is 174 and
`modern_editor_wrapper_semantics_test.dart` 9; the full suite is
**3,134** passing (7 benchmark cases skipped), up 32 from 7c's 3,102;
`dart analyze lib`, `dart analyze
test` and `dart analyze packages/re_editor/lib` clean apart from the
fork's two pre-existing `avoid_print` infos; `dart format
--set-exit-if-changed` over the fork, `test/re_editor` and the touched
`lib`/`test` files changes nothing. Nothing committed.

### Session 8 — rendering parity features

1. Bullet glyph by depth (`•`/`◦`/`▪` from `item.level`, 1:1, text-keyed).
2. Callout blocks: a positional `c:` pass in `MarkdownEditorLineIndex`
   (same lazy pattern as fences), continuation lines get the accent bar,
   lead line gets the icon via a 1:1 substitution of `[` with a painted
   glyph; **accent bar only, no background band** (decided 2026-09-04: an
   empty line cannot paint a background — same reason the fence tint was
   dropped — so a band would stripe). Extend the equivalence test.
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

### Session 10 — lite rendering tier (DROPPED 2026-09-04, decision 4)

Moved to §4 Deferred with its reopen trigger. The number kept its slot so
earlier references stay valid.

### Session 11 — heading folding (planned 2026-09-04, after Sessions 7a and 7b)

Goal: tap a heading, its section collapses to the heading line; tap again,
it expands. Session-only state in v1. Nothing about the code-unit
invariant changes: folding hides whole lines, never characters.
**Opt-in behind a settings toggle** (decided 2026-09-04, item 7): a tap
on a heading's concealed `#` cells places the caret today, and folding
changes what that tap does, so the feature ships off by default and the
owner turns it on.

Mechanism — the fork already has it. §4 deferred this as "needs a
`CodeLines` view that hides lines", but `code_chunk.dart` ships
`CodeChunkController` + `CodeChunkAnalyzer` (upstream's brace folding),
and the app merely switches it off with `NonCodeChunkAnalyzer`
(`modern_editor_wrapper.dart`). `collapseChunk(start, end)` moves lines
`start+1..end-1` into `codeLines[start].chunks` (the parent `CodeLine`
keeps them; `asString`/`text`/`lineCount` still include them, so autosave
and backup content are untouched), and `expandChunk` splices them back;
both remap the selection. Search already expands a collapsed chunk that
holds a match (`_expandChunkIfNeeded`). So the session is an analyzer, a
tap surface, and making the app's positional machinery chunk-aware.

1. `MarkdownHeadingChunkAnalyzer implements CodeChunkAnalyzer`
   (`lib/utils/markdown_heading_chunks.dart`): a section runs from a
   heading (`MarkdownLineShape.headingAt`, the shared predicate) to the
   line before the next heading of the same or a shallower level, or EOF;
   sections nest (an h2 chunk inside an h1 chunk — the controller supports
   nested chunks, the indicator shows the innermost). Headings inside a
   code fence are not headings — read fence roles from the span builder's
   `lineInFence` (the line index), never a second scan. Trailing blank
   lines stay inside the section. A section with nothing under it
   (`canCollapse == false`) gets no chunk. Runs on the controller's value
   like upstream's analyzer; it is O(lines) per run, so debounce it the
   way the highlighter is (50 ms) and skip it entirely while
   `liveMarkdownRendering` is off **or `headingFolding` (item 7) is off**
   — off means `NonCodeChunkAnalyzer` exactly as today, no chevron zone,
   nothing collapsible, and a note that was folded when the flag is
   turned off reopens flat (v1 never persists fold state, so there is
   nothing to migrate).
2. Tap surface: not the gutter (one-handed use; line numbers are off by
   default). A **fifth interceptor zone** on heading lines, after tag in
   precedence: the concealed `#` run's cells, `[0, contentStart)`. Off-caret
   the leading `#` is substituted 1:1 by a painted chevron
   (`CodeInlinePaintSpan`, same mechanism as the checkbox; `▸` when
   collapsed, `▾` when expandable, nothing when the section is empty);
   reveal lines show raw hashes and pass through, like every zone. The
   chevron's collapsed/expandable facet is positional (it depends on the
   chunk list), so it goes through the positional memo with the state in
   the key, exactly like indeterminate task parents.
3. The line index must keep seeing the whole document. Every pass in
   `MarkdownEditorLineIndex` (fence, tasks, money) walks visible lines;
   under a collapse the hidden lines vanish from `CodeLines` and a `$$`
   below a collapsed section would fold without its entries. Rule: passes
   step through `codeLines[i].chunks` (recursively) after line `i`,
   advancing fold state without emitting results — results stay keyed by
   visible index because that is what renders. Guard with an equivalence
   test: fold every money/task/fence result with and without a collapse
   and require identical values on the visible lines. Collapse/expand
   rebuild `CodeLines` through `sublines` + `add` + `addFrom`, which breaks
   segment identity from the fold point down — accept the full rescan
   (rare, user-initiated), but confirm the splice path handles it rather
   than the dirty-flag path.
4. **Data-loss guard.** The app rebuilds single lines from text in six
   places (Enter continuation, checkbox toggle, Tab/Shift-Tab indent,
   `PasteLineBreaker`, `ListAwarePasteController`, the money/ghost
   helpers): a `CodeLine(text)` built for a chunk parent silently drops its
   `chunks` — the collapsed section is deleted on the next keystroke.
   Rule: app code never mutates a chunk-parent line; every structural
   edit on a heading line first expands it (`expandChunk`) and
   `CodeLines.replaceLine`/`removeLine` assert `!old.chunkParent` in
   debug. Widget test per path: collapse, edit the heading, expand,
   content identical.
5. Position restore saves visible indexes today. Save and restore in
   absolute (chunk-flattened) line numbers — the fork's `lineCount`
   arithmetic in `code_lines.dart` already counts chunks — so a note saved
   while folded reopens at the right line unfolded (v1 does not persist
   fold state; the position controller from Session 6 owns the mapping).
   `EditorChunkOverlay` (the debug overlay) and the search bar's match
   list use visible indexes and are fine as long as they read the same
   `CodeLines` the render does.
6. Tests: analyzer table (levels, nesting, fence-shadowed `#`, `#tag`,
   `##$$` money heading, trailing blanks, heading at EOF, empty section);
   index equivalence under collapse (item 3); the six edit paths (item
   4); restore mapping (item 5); interceptor zone precedence (a `#tag` or
   link on the heading line still wins at its own cells); agreement
   suite unchanged (folding is not rendering).
7. **The setting**, following the `liveMarkdownRendering` /
   `previewModeEnabled` pattern end to end, nothing new: a
   `SettingsKeys.headingFolding` constant (`settings_keys.dart:33-41`
   neighbourhood); `getHeadingFolding` / `setHeadingFolding` on
   `SettingsService` next to the live-rendering pair (`:412-429`),
   default `false`; the key added to `_editorSettingsKeys` (`:568-587`)
   and a `headingFolding` field on the `EditorSettings` record decoded
   in the same one-pass read, so `EditorSettingsController.reload()`
   picks it up without another round trip; the page passes it to
   `ModernEditorWrapper` beside `checkboxTapToggle`
   (`optimized_note_editor_page.dart:1744`), and the wrapper chooses the
   analyzer and enables the chevron zone from it (`didUpdateWidget`
   rebind, like the other flags — toggling the setting must not remount
   the editor, B4); a tile on the settings page in the editor group,
   right under Live Markdown Rendering (`settings_page.dart:313-319`
   pattern), with `headingFolding` / `headingFoldingDesc` /
   `headingFoldingKeywords` in all three ARBs (the keywords key feeds
   settings search; Live Markdown's is at `app_en.arb:5246`); and the key
   appended to the backup allow-list (`backup_service.dart:227-228`) —
   additive like decision 2, old backups still import. Tests: the
   `editor_settings_test.dart` round trip gains the key; the page suite
   gains "toggle folding on, no remount"; the analyzer suite gains "flag
   off ⇒ zero chunks on a heading-rich note".

Depends on Session 6 (position controller), Session 7a (the upstream
sync — `04b240d` rewrites `_updateDisplayRenderParagraphs`, which chunk
collapse drives) and Session 7b (interceptor test harness); 7c is not a
prerequisite. Size: about one and a half days. Out of scope for v1:
persisted fold state, fold-all/unfold-all, folding list subtrees.

---

## 4. Deferred / rejected

- **Ordered-list renumbering as a render** — rejected: `9.`→`10.` changes
  the unit count. Only viable as an Enter-continuation edit.
- **Heading folding** — high value for long logs; was deferred as "needs a
  `CodeLines` view that hides lines". Planned as Session 11 on 2026-09-04
  (planning only); see that block for the mechanism actually available.
- **Lite rendering tier** (was Session 10, dropped 2026-09-04): a
  "Reduced rendering for slow devices" setting — headers bold at base size
  (uniform line height ⇒ no `correctBy` storms, no backward walk),
  single-paragraph list lines, money display rows plain. Reopen only if a
  real low-end device profile (§5 recipe, `gfxinfo framestats` on a
  header-heavy fling) shows the hanging layout or variable line heights
  dominating a frame; after Session 5 nothing measured does.
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

Session 3 numbers (2026-09-03, same machine, same commands; each benchmark
file gained rows for the shapes Session 3 changed, so "before" rows were
measured with the new rows on the old code, in the same run shape):

`CodeLines` (`code_lines_benchmark_test.dart`, 10k lines, per op):

| Operation | Before Session 3 | After |
|---|---|---|
| `CodeLines.of` (10k lines) — the old Enter/toggle rebuild | 320 µs | unchanged (no longer on any app path) |
| `from()` + `[]=` (keystroke shape) | 0.83 µs | 0.85 µs |
| `replaceLine` (Enter continuation, toggle, indent) | 0.86 µs | 0.72–0.76 µs |
| `removeLine` (Enter on an empty item; was a full text join + re-parse) | 4.19 µs | 4.08–4.40 µs |
| `[]=` in place | 0.074 µs | 0.071 µs |

So a list Enter's continuation went from ~320 µs of `CodeLines` work (plus
a whole-document undo pin) to under 1 µs, a toggle likewise. `[]=` no
longer discards `_segmentEnds`/`_lengthCache`, so the first `operator []`
after a keystroke no longer rebuilds the prefix-sum index — the
microbenchmark does not show that; the paint loop pays it.

Line index (`markdown_editor_line_index_benchmark_test.dart`, 10,240 lines,
µs per keystroke of index work — the `index` column of the Session 1 table):

| money | k | Session 1 | Session 3 |
|---|---|---|---|
| off | 0 | 159.5 | 6.7–15.8 |
| off | 20 | 82.1 | 6.9 |
| off | 39 | 20.6 | 6.7 |
| on | 0 | 236.8 | 10.3–29.7 |
| on | 20 | 125.9 | 13.4 |
| on | 39 | 23.1 | 10.3 |

The k gradient is gone (the higher end of the k=0 range is JIT warm-up on
whichever row prints first — reverse `segmentsUnderTest` to see it move).
New structural rows (Enter mid-segment followed by the 40-line layout query,
then the delete that undoes it; µs of index work per edit). "Before" was
measured on a fence-free corpus; the corpus gained a ``` pair every 200
lines afterwards, so "after" includes the per-line fence array's
`replaceRange` memmove (≈10–15 µs on 10k lines) that "before" could not
see:

| money | k | Enter, before | Enter, after | delete, before | delete, after |
|---|---|---|---|---|---|
| off | 0 | 194.5 | 37.4 | 190.5 | 34.4 |
| off | 20 | 201.7 | 34.7 | 183.0 | 29.6 |
| off | 39 | 193.9 | 21.4 | 185.6 | 21.9 |
| on | 0 | 274.5 | 49.6 | 276.3 | 45.0 |
| on | 20 | 284.7 | 38.5 | 271.9 | 34.3 |
| on | 39 | 276.4 | 38.0 | 267.1 | 36.8 |

"Before" is the whole-document `_rebuildAll`; "after" is the splice plus,
for structural edits only, the indeterminate-set rebuild (bounded by result
count, ~1,000 on this corpus) and the fence-array memmove (bounded by line
count, one `replaceRange`; making fence roles segment-relative would remove
it and is the one remaining O(lines) term on a structural edit — a storage
shape change, deliberately not done here). Keystroke cost is bounded by the
ledger's entry count below the caret (the money stash), not by line count.
Cold full build is unchanged (≈200–460 µs).

Span builder (`markdown_editor_span_builder_benchmark_test.dart`, new row:
40 display-money lines × 40 warm passes, positional memo hot):

| Path | Before P5 | After P5 |
|---|---|---|
| display-money warm, per pass | 122–125 µs | 76–87 µs |
| per line | 3.1 µs | 2.0–2.2 µs |

The list-line rows (cold 471–549 µs, warm 69–94 µs per pass) are unchanged
within noise.

Session 5 numbers (2026-09-04, same machine, quiet box, three runs each).

Hanging paragraphs (`test/re_editor/hanging_paragraph_benchmark_test.dart`,
new: 40 mixed list lines — `• `, `1. `, checkbox placeholder, nested
`    • `, a few wrapping at 360 px — × 40 passes through
`CodeParagraphProviderForTesting`; "before" is the pre-session fork at
`1ed4a60` in a detached worktree with the test seam grafted in):

| Path | Before P6 | After P6 |
|---|---|---|
| cold (paragraph cache cleared per pass), per pass | 2,095–2,236 µs | 1,598–1,711 µs |
| per line | 52–56 µs | 40–43 µs |
| warm (identity hit), per pass | 18–21 µs | 23–25 µs (noise) |

So a fling into 40 fresh list lines pays ~25 % less layout; the marker
paragraph is built once per distinct marker span and the content
paragraph is the remaining cost.

Span builder (`markdown_editor_span_builder_benchmark_test.dart`, rows and
bounds unchanged; the harness moved from `testWidgets` to `test()`, so
the environment moved with the code — read this as "no regression from
the decomposition", not as a speed-up claim; the warm row was already
known to track JIT warm-up):

| Path | Before Session 5 | After |
|---|---|---|
| cold (memo cleared), per pass | 618–632 µs | 491–523 µs |
| warm (memo hit), per pass | 136–140 µs | 27–31 µs |
| display-money warm, per pass | 76–81 µs | 50 µs |

Paragraph cache size (`adb shell dumpsys meminfo` on the x86_64 API 36
emulator, profile build of a throwaway `flutter run -t` entrypoint that
mounts `CodeEditor` + `MarkdownEditorSpanBuilder` over a generated
10k-line list note and walks 4,000 lines in viewport steps, then parks):

| `_kMaxCacheSize` | Native Heap | TOTAL PSS |
|---|---|---|
| 512 (three samples) | 55.0–56.7 MB | 160.0–162.0 MB |
| 128 (three samples) | 40.8–40.9 MB | 145.1–145.9 MB |

≈ 15 MB for 384 extra entries, ≈ 39 KB per retained list-line paragraph
(the content paragraph plus its boxes; the marker is shared by P6). That
is the "clear win" the decision rule asked for, so the paragraph cache
is now **128** (both the equality LRU and the identity L1). Cost side:
128 entries cover 3–5 phone viewports, a miss on a list line is the
40–43 µs cold row above, so a page that scrolled out of the cache costs
1–2 ms to come back — inside one frame. The absolute numbers are an
emulator's and the harness's content is all list lines; the delta is
what matters.

Session 6 numbers (2026-09-04, same machine, quiet box — no agent or
suite running — two runs each, best-of-20 / median-of-20 per run).

Paste reflow (`test/utils/paste_line_breaker_benchmark_test.dart`, new:
a 10,000-line task-list note, a 500-line paste ending at line 5,499,
360 px at 16 pt, `PasteLineBreaker.run` alone; "before" is `4cad6ec` in a
detached worktree with the benchmark ported to the old flat-offset
signature and two throwaway seams grafted in — a fixed available width,
since the old breaker measured it off a mounted widget, and the layout
counter). "20 % over-long" means every fifth pasted line is wider than
the editor; "layouts" is the number of `TextPainter.layout` calls:

| Path | Before P7 (best / median / layouts) | After (best / median / layouts) |
|---|---|---|
| nothing to break | 5,069–5,229 µs / 6,679–6,771 µs / 500 | 86–88 µs / 164–174 µs / 0 |
| 20 % over-long | 22,927–23,245 µs / 24,023–24,291 µs / 2,018 | 15,093–15,211 µs / 16,529–17,711 µs / 1,200 |

The common case — a paste whose lines all fit — is ~58× cheaper: the four
whole-document string passes (`controller.text`, two
`TextPositionUtils` scans, the `join` + `.codeLines` re-parse) are gone,
and the ASCII advance table settles all 500 lines without a single
layout. The breaking case keeps the per-break binary search (the exact
answer is required — a 300-string property test pins it against the
unseeded search), so it improves by a third: the document passes and the
redundant whole-line layouts went, the table seeds each search, and the
remaining cost is the ~12 layouts a genuinely over-long line needs. Not
in either column: the page used to compute the flat paste offsets with
an O(lines) loop before calling the breaker; that loop no longer exists.
