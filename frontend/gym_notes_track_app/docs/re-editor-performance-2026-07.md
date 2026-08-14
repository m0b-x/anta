# re_editor Live-Rendering Performance Batch — 2026-07-18

Fixes four hot-path issues in the Obsidian-style live markdown rendering
(`MarkdownEditorSpanBuilder` + the `packages/re_editor` fork). Full
before/after reasoning lives in the conversation that produced this batch;
this is the short reference.

## What was wrong

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

## What changed

| File | Change |
| --- | --- |
| `packages/re_editor/lib/src/_code_paragraph.dart` | Identity-keyed L1 (`LinkedHashMap.identity()`) in front of the equality LRU — steady-state hits are one pointer hash. `updateBaseStyle` short-circuits on the Flutter `TextStyle` before allocating a `ui.TextStyle` to compare. |
| `packages/re_editor/lib/src/_code_highlight.dart` | Plain no-highlight-theme span memoized per line text (bounded LRU), so unhandled/plain lines are both allocation-free and identity-stable into the paragraph cache. |
| `lib/utils/markdown_chunker.dart` | `isFenceDelimiter` extracted as the one shared fence grammar; the preview's block scan now calls it too. |
| `lib/utils/markdown_list_syntax.dart` | `scanListShape` — allocation-free charcode scan returning a packed int (kind/checked/level), used by the index instead of the regex-based `parse()` + `MarkdownListItem` allocation. |
| `lib/utils/markdown_editor_line_index.dart` (new) | `MarkdownEditorLineIndex` — fuses fence-role and task-indeterminate tracking into one incremental index. |
| `lib/utils/markdown_editor_span_builder.dart` | Delegates positional queries to the new index; ~120 lines of per-instance rebuild logic deleted. Public API unchanged. |

## Why the incremental index works

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

## Verify

```
dart analyze lib
dart analyze packages\re_editor
```

Both clean (only pre-existing findings: deprecated `onReorder` callback,
fork debug-trace unused-element warnings).

## Not yet verified on a real device

- Typing latency on a 10k+ line note (the case this batch targets).
- Checkbox indeterminate-dot correctness after rapid edits/undo that land
  on opposite sides of a 256-line segment seam.
- Fence styling immediately after typing a ` ``` ` fence mid-document
  (exercises the resume-scan boundary).

See `docs/live-markdown-editor-roadmap.md` → "Not verified on device yet"
for the standing checklist this batch was appended to.
