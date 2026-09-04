# re_editor Fork — Provenance, Delta & Performance Reference

## Provenance (corrected 2026-09-04)

Two upstream bases, used for different purposes:

- **`8a7dbc5`** = merge-base(`m0b-x/re-editor` `main`, `reqable/re-editor` `main`). This is the base for **enumerating upstream commits** — every commit `reqable/main` has picked up since the two trees diverged.
- **`dfbca60`** = `m0b-x/re-editor` `main` = `8a7dbc5` + `a0094dd` (deleted `example/` and `test/`) + `dfbca60` itself ("re-activated cursor on android", fork-only code, not upstream). This is the base for **diffing the tree** — it does not exist in `reqable/re-editor`.

Upstream HEAD is **`28d9fc0`** (2026-08-21) — still current as of 2026-09-04, the date this reference was last evaluated against it. The base pubspec version is `0.8.0`; upstream has since moved to `0.10.0`; **the fork's `pubspec.yaml` stays frozen at `0.8.0`** — deliberately, and not part of any sync.

The fork's `packages/re_editor/lib/` tree is currently: `dfbca60` + the 19-file patch list below (the delta ANTA had already accumulated) + the Session 7a upstream sync (2026-09-04) — four clean cherry-picks (`dc27ee5`, `4f3cb30`, `6bd7151`, `512ba8d`) and a hand-port of `04b240d` (conflicted on `_code_field.dart`, so it could not be cherry-picked directly). A fifth candidate, `10fdbc1`, was already present in the fork's own delta before 7a — see the candidates table below. 37 tracked `lib/` files, no nested `.git` — `packages/re_editor/.git` was deleted 2026-09-03 (Session 0); ANTA's repo is the fork's only history now. Never `git init` or clone a repo under `packages/re_editor/`.

**Reproducing the diff**: `dart format` (Dart 3.12.2) BOTH the base tree at `dfbca60` and the fork's `lib/` BEFORE diffing — the fork tree is not format-clean on its own, so an unformatted diff is dominated by reflow noise. Compare the two formatted trees with `git diff --no-index --diff-algorithm=histogram` (or `diff --strip-trailing-cr -ruN`) — the fork's files carry CRLF line endings on a Windows checkout, and a plain `diff -ruN` without stripping them (or an algorithm other than histogram/patience) inflates every count with line-ending and alignment noise. Counting method for both raw and semantic line counts below: changed lines (insertions + deletions) of that diff, summed per file.

- **Raw** (no formatting either side): 34 files, +3,718/−2,244 lines (5,962 total).
- **Semantic** (both sides formatted first): 19 files. Histogram gives +1,876/−133; Myers/patience give +1,877/−134 (within one line of histogram) — cited as +1,877/−134 below, matching the ledger's original figures.
- Reflow is therefore 1 − (1,877+134)/(3,718+2,244) = 1 − 2,011/5,962 ≈ **66 %** of the raw churn.
- 15 files carry raw diff but zero semantic diff — pure `dart format` reflow, no logic change: `lib/re_editor.dart`, `lib/src/_code_autocomplete.dart`, `lib/src/_code_editable.dart`, `lib/src/_code_formatter.dart`, `lib/src/_code_indicator.dart`, `lib/src/_code_scroll.dart`, `lib/src/_code_span.dart`, `lib/src/code_autocomplete.dart`, `lib/src/code_formatter.dart`, `lib/src/code_indicator.dart`, `lib/src/code_scroll.dart`, `lib/src/code_shortcuts.dart`, `lib/src/code_span.dart`, `lib/src/code_theme.dart`, `lib/src/code_toolbar.dart`.

## Fork delta — 19-file patch list

One entry per file that survives formatting-both-sides, derived from the semantic diff. `+`/`−` are the per-file line counts defined above.

| File | +/− | What the fork changed |
| --- | --- | --- |
| `_code_extensions.dart` | +5/−1 | `InlineSpan.length` now counts a placeholder as its one U+FFFC code unit (matching `toPlainText()`'s own accounting) instead of `toPlainText(includePlaceholders: false).length`, so truncation/prefix-drop/range math doesn't desync on span trees containing `CodeInlinePaintSpan` boxes. |
| `_code_field.dart` | +138/−36 | `markNeedsSemanticsUpdate()` on the `codes`/`hasFocus`/`readOnly` setters, plus a `describeSemanticsConfiguration` override announcing the editor as a multiline text field (value from the `CodeLines.asString` cache) — previously the raw-canvas render had no semantics at all. New `lineHeightOfLine`/`lineHeightAtOffset` on `_CodeFieldRender`; caret, floating/preview cursor, selection handles and the IME composing rect all switched from the flat base line height to these, so they size correctly against lines the span builder scaled (markdown headers). `findDisplayParagraphByLineIndex` and the hit-test `_findDisplayRenderParagraph` rewritten from O(n) linear scans to binary search. New `positionAt()` non-mutating hit test for the tap interceptor. `Color.alpha == 0` (int) checks migrated to `Color.a == 0.0` (double), a Flutter Color API update. |
| `_code_find.dart` | +25/−0 | `CodeFindController` impl gains `goToMatch(int index)`: clamps into range, updates `CodeFindValue.result.index` only when the target differs (no-op re-targets push no new value), always re-centers the match via `makePositionCenterIfInvisible` — backs a "jump to match N" UI without stepping through `nextMatch()`. |
| `_code_highlight.dart` | +75/−2 | `_plainSpans`: a bounded (1,024-entry) LRU memoizing the no-highlight-theme `TextSpan` per line text, so plain/unhandled lines get the SAME span instance every layout (feeds the paragraph provider's identity cache); cleared together with `clearCache()`. `_CodeHighlightEngine` gains a 50 ms debounce (`Timer` + `_flush`) coalescing rapid keystroke-triggered highlight requests into one isolate job instead of one per keystroke. |
| `_code_input.dart` | +6/−2 | `onFocusReceived() => false` forward-compat override for Flutter master's `TextInputClient`; composing-rect and caret-rect height read `render.lineHeightOfLine(...)` instead of the flat `render.lineHeight`. |
| `_code_line.dart` | +58/−6 | `_kInitialCodeLines` can no longer be `const` (its `CodeLines` now carries cache fields), so it's built with `List.unmodifiable` at both list levels to keep throw-on-mutation. `CodeLineEditingValue` gains `textLength` (O(segments), not O(chars)). `_CodeLineEditingCache` (undo) gains a `depth` per node and `_evictBeyondCap()`, capping the chain at `_kMaxUndoHistory` steps behind current instead of growing unboundedly; `_markNewRecord` is reset on both `_appendNewNode()` call sites. |
| `_code_lines.dart` | +92/−3 | `_CodeLineSegmentQuckLineCount` (the internal quick-count segment) adds `_charCount` alongside `_lineCount`, a cached `hashCode`, and a short-circuiting `==` (length/dirty/lineCount/charCount before `listEquals`). `length=`/`add`/`[]=` now maintain both counts by delta instead of re-folding via `super.lineCount`/`super.charCount`. A full-range `clone()` override carries the cached counts forward. |
| `_code_paragraph.dart` | +714/−25 | Effectively a rewrite. `_ParagraphImpl.draw()` resolves and paints `_decorPaints` (background chips for `CodeDecoratedTextSpan`, before the text) and `_inlinePaints` (`CodeInlinePaintSpan` boxes, after the text), both lazy and cached. `_CodeParagraphProvider` gains `_kMaxCacheSize = 128` (bounding a previously-unbounded LRU), an identity-keyed L1 cache in front of the equality LRU (a repeat hit for the same span instance costs one pointer hash instead of a deep `TextSpan` hash/equality), `_scaledLineStyles` (per-fontSize cached paragraph style/line height for headers), and `_markerMeasurements` (a 128-entry LRU of laid-out list-marker paragraphs). New `_buildHanging`/`_HangingParagraphImpl`: a two-part paragraph giving list items a hanging indent (marker pinned left, content laid out at the marker's floored advance width so wrapped lines align under it), with every geometry query split piecewise across marker/content, and a fallback to a plain paragraph when word-wrap is off, the prefix is degenerate, or the marker is too wide or itself wraps. `trucate`/`_dropPrefix` now keep untouched subtrees by identity and never emit empty `TextSpan('')`. Two debug asserts guard the couplings the app relies on (root-span fontSize scaling keeps the base style's strut inputs; `CodeInlinePaintSpan.height` fits the line). |
| `_code_selection.dart` | +148/−5 | `CodeEditorTapInterceptor` plumbing: `_tryInterceptTap`/`_finishInterceptedTap`/`_cancelInterceptedTap` implement a claim-at-tap-down/fire-at-tap-up state machine, wired into both the mobile (`onTapDown`/`onTapUp`/`onTapCancel`) and desktop (`Listener` pointer-event) gesture paths, pointer-id-scoped on desktop. Double-tap pairing state is now cleared after a double-tap fires (previously every OTHER double-tap landed on a bare caret). `extendPositionTo`'s `anchor` is always `_anchorSelection` now (was `null` on mobile) — "fix half word selection bug". Selection handles size against `lineHeightOfLine` instead of the flat `lineHeight`. |
| `_consts.dart` | +5/−0 | Adds `_kMaxUndoHistory = 200`. |
| `code_chunk.dart` | +33/−10 | The isolate tasker is now nullable and skipped entirely when the chunk analyzer is a no-op (`NonCodeChunkAnalyzer`) — no isolate spawned, saving a platform thread + Dart heap on low-end Android. `findByIndex` converted from linear scan to binary search. |
| `code_editor.dart` | +81/−5 | New public `CodeEditorTapInterceptor` class and `CodeEditor.tapInterceptor` parameter. `Focus.onKey` (deprecated) replaced with `onKeyEvent` gated to `KeyDownEvent` only — the old `event.isKeyPressed(...)` global-tracker check could get stuck on a missed key-up during auto-repeat, leaking backspace into subsequent keystrokes. Adds a Tab/Shift-Tab handler (respects `readOnly`, checks `shortcutOverrideActions` first, else `applyIndent`/`applyOutdent`) and `numpadEnter` alongside `enter`. `withOpacity` migrated to `withValues(alpha:)`. |
| `code_find.dart` | +2/−0 | Adds `goToMatch(int index)` to the abstract `CodeFindController` interface. |
| `code_line.dart` | +8/−3 | `CodeLineEditingController`'s factory `codeLines` parameter becomes `CodeLines?` (defaulted inside the body, since `_kInitialCodeLines` is no longer `const`-usable as a parameter default); adds the public `textLength` getter; `CodeLineEditingValue.empty()` is no longer `const`. |
| `code_lines.dart` | +257/−35 | The public `CodeLines` class gains lazy caches for `length`/`lineCount`/`charCount`, a `_segmentEnds` prefix-sum index (binary search for `operator []`/`[]=`, replacing linear segment scan), a last-hit-segment fast path for sequential access, and two round-robin `asString` cache slots (the editor calls it with both `expandChunks` values per keystroke; one slot would thrash). Two invalidation levels: `_invalidateLineContent()` (counts + asString only, for an in-place same-length line write) vs. `_invalidate()` (everything, for structural mutation). New `replaceLine`/`removeLine` — targeted single-line edits that clone-on-write only the affected segment, keeping every other segment shared by identity. `CodeLineSegment` gains `charCount` and `cloneShallowDirty()`; `hashCode` now hashes `codeLines.length` instead of the whole list. |
| `code_paragraph.dart` | +187/−0 | New public symbols only (no removals): `CodeHangingTextSpan` (the hanging-indent root span), `CodeInlinePaintSpan` (an abstract self-painting placeholder span — one U+FFFC code unit, must not exceed line height), `CodeTextDecoration` + `CodeDecoratedTextSpan` (a rounded background chip painted behind a text run, no layout space reserved). |
| `code_paragraph_testing.dart` | +39/−0 | New file (the fork's only added file). `CodeParagraphProviderForTesting`, a `@visibleForTesting` wrapper exposing the library-private `_CodeParagraphProvider` to tests, since the app owns exactly one provider (inside the highlighter) and no app code should construct a second with a different style. |
| `debug/_trace.dart` | +2/−0 | Adds `// ignore_for_file: unused_element`. |
| `re_editor.dart` | +1/−0 | Adds `part 'code_paragraph_testing.dart';`. |

## Upstream candidates `8a7dbc5..28d9fc0`

18 non-merge commits touch `lib/` between the two bases (28 commits total including 10 merges, which carry nothing of their own). Session 7a (2026-09-04) evaluated all 18 against ANTA's usage:

| Commit | Date | Subject | Verdict | Why |
| --- | --- | --- | --- | --- |
| `04b240d` | 2026-08-20 | Keep layout from looping and the scroll offset from leaving its range | **Hand-ported** | Fixes a layout-loop hard freeze in `_updateDisplayRenderParagraphs` (the plan expected four recursive sites in the fork; there are three self-calls — document shrank below the first shown line, empty rebuild, top-gap check — plus the two entry points `forceRepaint` and `performLayout`; a cycle counter is threaded through all three, `_kMaxLayoutCycles = 10`, and the top-gap recursion is skipped when line 0 is already first), a `makePositionVisible` overshoot (was counted from `first.index`, must be `last.index`), and clamps `jumpTo` to the viewport. Real fixes, but conflicted in `_code_field.dart` against the fork's own edits, so it was hand-ported (with a new regression test in `test/re_editor/`) rather than cherry-picked. |
| `febb8eb` | 2026-08-20 | Implement moveCursorToPageUp/Down and bind PageUp/PageDown to them | Declined | New public API (`moveCursorToPageUp/Down`) — the sync takes no API changes. |
| `bf2e2b7` | 2026-08-20 | Do not fail highlighting when the theme declares no languages | Declined | Guards `modes.isEmpty`; unreachable in ANTA, which passes no `CodeHighlightTheme`. |
| `4b34f7d` | 2026-08-10 | Revert "Use overlay context for toolbar builder" | Declined | Net-zero with `880c4ed` — reverts it. |
| `880c4ed` | 2026-08-10 | Use overlay context for toolbar builder | Declined | Net-zero with `4b34f7d` — reverted two commits later upstream. |
| `90ed36e` | 2026-08-06 | Fixed shortcut keys on windows and linux | Declined | Re-maps existing shortcut bindings on Windows/Linux (e.g. Ctrl+Delete → Shift+Delete) — a behaviour change, not a fix. |
| `367192d` | 2026-07-23 | Remove paste long text check | Declined | Net-zero with `5e9cfa1` — removes the check it added. |
| `5e9cfa1` | 2026-07-19 | Disable paste if the text is too long to render in a single line, to avoid performance issues | Declined | Net-zero with `367192d` — removed 4 days later upstream. |
| `dc27ee5` | 2026-07-17 | fix: guard delayed drag autoscroll after dispose | **Taken (clean)** | Guards the delayed drag-autoscroll after dispose and replaces the unchecked `render` getter cast (`_code_selection.dart:38-39`) with `findRenderObject() is! _CodeFieldRender` checks plus a `mounted` guard — the general fix behind the crash class flagged in `docs/live-editor-review-and-slices-2026-09.md` §1.5 (distinct from upstream `b19f746`, which is issue #68's mobile-handle fix and was already an ancestor of `8a7dbc5`). |
| `6bd7151` | 2026-07-01 | Fix keyboard appearance issue #115 | **Taken (clean)** | `keyboardAppearance` follows theme brightness — additive parameter, no API break. |
| `4f3cb30` | 2026-07-01 | Check whether the viewport is still valid before auto scrolling | **Taken (clean)** | Adds a viewport-still-valid check before the post-frame retry in `makePositionVisible`/`makePositionCenterIfInvisible`. |
| `20e4b11` | 2026-07-01 | Opt range check code in method _isWrapedByClosureSymbol | Declined | Logically identical rewrite of the range check — no behaviour change. |
| `830fad1` | 2026-07-01 | Fix a compiler error | Declined | Reflow-only conflict on a path ANTA does not use (built-in autocomplete), paired with `000d8c3`. |
| `000d8c3` | 2026-07-01 | Ignore the error when _CodeAutocompleteState is disposed | Declined | Built-in autocomplete — unused in ANTA. |
| `93db119` | 2026-06-29 | Fixed a typo issue | Declined | New public API — `sperator` → `leadingDivider` rename; the sync takes no API changes. |
| `512ba8d` | 2026-05-31 | Add "Enter (keypad)" key to newLine | **Taken (clean)** | Binds `numpadEnter` to `newLine`; no API change. The fork's mobile bare-`Focus.onKeyEvent` path already handled `numpadEnter`, but `512ba8d` adds it to the desktop `Shortcuts` activator tables in `code_shortcuts.dart`, which the fork had not done — a real, desktop-only change. |
| `5526c38` | 2026-05-15 | Fix stale CodeEditor findController listener swap | Declined | Fixes `findController:` swap handling — ANTA uses `findBuilder`, not `findController`. |
| `10fdbc1` | 2026-04-20 | Add onFocusReceived for Flutter master TextInputClient | **No-op** | `onFocusReceived() => false` — already present in the fork tree; the pick produced a duplicate definition and was dropped. `bool onFocusReceived() => false;` was part of the fork's own delta in `_code_input.dart` before 7a; the cherry-pick applied without a textual conflict but duplicated the method, so it was discarded rather than taken. |

## re_editor Live-Rendering Performance Batch — 2026-07-18

Fixes four hot-path issues in the Obsidian-style live markdown rendering
(`MarkdownEditorSpanBuilder` + the `packages/re_editor` fork). Full
before/after reasoning lives in the conversation that produced this batch;
this is the short reference.

### What was wrong

1. **Paragraph cache deep-hashed every span tree, three times per hit.**
   `_CodeParagraphProvider` keyed its LRU as `Map<TextSpan, IParagraph>`.
   `TextSpan.hashCode` recurses through every child and every child's
   `TextStyle`. A styled line (~10-12 spans) cost ~300 hash ops per lookup,
   and the LRU "touch" (remove + re-insert) made every **hit** pay it three
   times — on every layout pass, i.e. every keystroke and scroll frame.
2. **Two full-document O(n) rebuilds on every keystroke.** The span builder
   recomputed its code-fence index and its task-indeterminate index from
   scratch whenever the `CodeLines` instance changed — which is every text
   mutation. The task pass also ran three regexes per candidate line via
   `MarkdownListSyntax.parse`, and notes here are mostly list lines, so the
   cheap pre-filter barely helped.
3. **A wasted TextSpan allocation per line per layout.** `_CodeHighlighter`
   always built a plain `TextSpan(text, style)` to hand to the span-builder
   chain, even though the markdown builder discards it whenever it handles
   the line (the common case).
4. **Fence detection was forked.** `MarkdownChunker` (preview) and
   `MarkdownEditorSpanBuilder` (editor) each had their own independent
   ```-detection code, with no guarantee they agreed (they didn't, on
   NBSP-indented fences).

### What changed

| File | Change |
| --- | --- |
| `packages/re_editor/lib/src/_code_paragraph.dart` | Identity-keyed L1 (`LinkedHashMap.identity()`) in front of the equality LRU — steady-state hits are one pointer hash. `updateBaseStyle` short-circuits on the Flutter `TextStyle` before allocating a `ui.TextStyle` to compare. |
| `packages/re_editor/lib/src/_code_highlight.dart` | Plain no-highlight-theme span memoized per line text (bounded LRU), so unhandled/plain lines are both allocation-free and identity-stable into the paragraph cache. |
| `lib/utils/markdown_chunker.dart` | `isFenceDelimiter` extracted as the one shared fence grammar; the preview's block scan now calls it too. |
| `lib/utils/markdown_list_syntax.dart` | `scanListShape` — allocation-free charcode scan returning a packed int (kind/checked/level), used by the index instead of the regex-based `parse()` + `MarkdownListItem` allocation. |
| `lib/utils/markdown_editor_line_index.dart` (new) | `MarkdownEditorLineIndex` — fuses fence-role and task-indeterminate tracking into one incremental index. |
| `lib/utils/markdown_editor_span_builder.dart` | Delegates positional queries to the new index; ~120 lines of per-instance rebuild logic deleted. Public API unchanged. |

### Why the incremental index works

`CodeLines.from()` clones each segment via `cloneShallowDirty()`, which
shares the segment's backing `List<CodeLine>` **by reference**; only the
segment(s) actually edited get a fresh list (`code_lines.dart`, `[]=`/`add`
clone-on-write). So per-segment (256-line) backing-list identity is a
precise dirty flag across an edit.

- **Fence pass** resumes at the first changed segment carrying the stored
  entry parity (in/out of fence), and stops as soon as it re-enters an
  unchanged segment whose entry parity still matches — the rest of the
  document is provably unaffected.
- **Task pass** can't short-circuit the same way (a subtree's indeterminate
  state can depend on lines below it), so it revives the open-frame stack
  snapshot recorded at the first changed segment and rescans to the end —
  but that rescan is now the cheap charcode scanner, not three regexes.
- **Structural edits** (Enter, paste, line delete/insert) change segment
  lengths, which is detected and falls back to a full rebuild — still fast
  because the per-line scan has no regex or allocation.

### Verify

```
dart analyze lib
dart analyze packages\re_editor
```

Both clean (only pre-existing findings: deprecated `onReorder` callback,
fork debug-trace unused-element warnings).

### Not yet verified on a real device

- Typing latency on a 10k+ line note (the case this batch targets).
- Checkbox indeterminate-dot correctness after rapid edits/undo that land
  on opposite sides of a 256-line segment seam.
- Fence styling immediately after typing a ` ``` ` fence mid-document
  (exercises the resume-scan boundary).

See `docs/live-markdown-editor-roadmap.md` → "Not verified on device yet"
for the standing checklist this batch was appended to.
