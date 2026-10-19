---
name: markdown-engine
description: Invariants of ANTA's custom markdown engine - the preview pipeline, the live editor renderer, the one-grammar-per-syntax rule, the note editor page's controllers and the owned re_editor fork - with references holding each module's full contract. Load for any change to how note markdown is parsed or rendered (inline or line grammars, lists, money ledger lines, colours, ghost text, tags, callouts, wiki links), to the toolbar and its shortcuts, to the editor page or auto-save on the typing path, or to the re_editor fork. Load together with anta-context, plus ui-language for anything visual.
---

# Markdown Engine & Editor

The full invariant lists for the preview pipeline, chunking and lists are in `references/preview-pipeline.md`, ghost text and colours in `references/inline-syntaxes.md`.

## The one hard constraint

**Every rendered span keeps its exact source offset.** The recursive inline parser (`_parseInline`) routes every leaf text run through `_applyHighlighting` with its exact source offset so search highlights and editor↔preview scroll mapping survive nested emphasis, links, escaping, ghosts, tags, and lists. When adding inline syntax, never break this offset threading.

**One inline grammar.** `_parseInline` (preview) and `EditorInlineEmitter.append` (editor) are emitters over `MarkdownInlineGrammar.tokenize` — neither scans for emphasis, code, escapes, links, wiki links, colours, tags, URLs or ghosts itself, and the wrapper's tap zones resolve through `EditorInputPolicy`, which takes **one** `linksAndTags` descent per tap (the whole-line walker over the same tokenizer: every link, `[[wiki link]]` and tag `tokenize` renders, at any depth, outermost first) and reads link / wiki link / tag off it as the first token of that kind whose `containsStrict` holds — `linkAt`/`wikiLinkAt`/`tagAt` are that same rule in offset form (tests and other callers), `zonesOf` takes the whole list — one descent, so the forms cannot disagree; pass the line's ghost runs in when you already have them. A new inline construct is added to the tokenizer (one token class, one placement rule) and then emitted by both surfaces; the agreement suite `test/utils/markdown_inline_agreement_test.dart` fails when only one surface changes. Headings and horizontal rules come from `MarkdownLineShape.headingAt` / `isHorizontalRule` everywhere.

## Preview pipeline layering (keep intact)

Deprecated and off by default (`SettingsKeys.previewModeEnabled`): gate preview-touching code on `_canPreview` / `_showPreview`, never `_isPreviewMode` (`references/preview-layering.md`).

```
OptimizedNoteEditorPage
  -> MarkdownPreviewBloc -> MarkdownRenderService -> LineBasedMarkdownBuilder
       -> MarkdownChunker (block scan + chunk layout)
       -> MarkdownListSyntax (shared list grammar)
  -> MarkdownPreviewBlocView -> SourceMappedMarkdownView
```

- Bloc state is `Equatable`, primitives + `renderHandle: int` only. **Never put `InlineSpan` trees or builders in state** — widgets pull spans from `bloc.renderService.builder` on demand; heavy rebuilds are gated by `buildWhen` on `renderHandle` / `linesPerChunk` / `fontSize`.
- Content sync: `bloc.bindContentProvider(() => controller.text)` once in `initState`; `bloc.markContentDirty()` per keystroke; dispatch `PreviewContentRefreshRequested` for lazy/debounced refresh (500 ms, gated on `!_isLoading` and `state.hasTheme`); `PreviewContentChanged` only for eager pushes (toggle, checkbox, locale change, load). Never dispatch from `build()`.
- Theme dispatch (`PreviewThemeChanged`) only from `MarkdownPreviewBlocView` lifecycle hooks — never `build()`. Scroll progress bypasses the event queue via `bloc.scrollController.updateProgress(progress)`.
- Search sync: call `_searchController.updateContent(content)` from `_pushPreviewContent` / `_scheduleLivePreviewRefresh` when searching — never from `build()`.
- `MarkdownPreviewBlocView` binds its own `GlobalKey<SourceMappedMarkdownViewState>` into the bloc's scroll controller on mount (reusing one already bound, so a remount keeps targeting the live state); the page holds no preview key of its own (2026-09-04) and reads `scrollController.currentLineIndex` — never an inline anonymous key on the view.
- Chunks are **block-aligned with variable line counts** — never compute `lineIndex ~/ linesPerChunk`; use `chunkStartLine(i)`, `chunkIndexForLine(line)`, `MarkdownRenderService.chunkStartLineForLine(line)`.
- Toolbar: `_buildMarkdownBar()` is the only `MarkdownBar(...)` tree; new async render inputs join the `_isLoading` gate, never a post-mount refresh (`references/preview-layering.md`).
- Preview links: validate schemes (`http`, `https`, `mailto`, `tel`) before `launchUrl` in `LaunchMode.externalApplication`; localized errors via `CustomSnackbar.showError`.

## Single-source-of-truth grammars (never fork them)

- `MarkdownInlineGrammar` — the inline tokenizer; keep its `openers_bottom` bound (`references/grammar-modules.md`).
- `MarkdownLineShape` — headings, rules, table rows and their one cell splitter `nextTableCellPipe`, `isLineLedConstruct`; never re-scan hashes, rule markers or cell pipes (`references/grammar-modules.md`).
- `MarkdownChunker` (`lib/utils/markdown_chunker.dart`) — block model + chunk layout, shared by preview and the editor debug overlay. Multi-line blocks only (code fences, callouts); single-line content is implicit. New single-widget block types set `atomic: true`.
- `MarkdownListSyntax` (`lib/utils/markdown_list_syntax.dart`) — list grammar shared by editor (`MarkdownListUtils`: Enter-continuation, Tab/Shift-Tab) and renderer; `bulletGlyph(level)` is the one bullet-glyph function (`•`/`◦`/`▪` by `level % 3`, one code unit each) for the preview, the editor's list branch and both surfaces' bulleted money rows (2026-09-05). **Never reintroduce a second list regex** — extend `MarkdownListSyntax`.
- `GhostText` (`lib/utils/ghost_text.dart`) — `{{ … }}` placeholder scanning, consumed by preview renderer, editor span builder, tap handling, and the `default_ghost` shortcut. Markers are concealed in the editor (transparent + ~0 width) so caret offsets never desync; tapping selects the run, nothing is mutated.
- `MarkdownCalloutSyntax` — callouts and quotes; never re-scan `>` markers by hand (`references/grammar-modules.md`).
- `MarkdownTagSyntax` — `#tag` scanning for both surfaces (`references/grammar-modules.md`).
- `MarkdownMoneySyntax` — every fold steps through `MoneyFold`; run `flutter test test/utils/markdown_money_syntax_test.dart` after any money change (`references/grammar-modules.md`, `references/money-ledger.md`).
- `MarkdownColorSyntax` — colours; pure conceal in the editor, palette threaded like the money config (`references/grammar-modules.md`, `references/inline-syntaxes.md`).
- `MarkdownLinkPatterns` — links, bare URLs and `[[wiki links]]` (`references/grammar-modules.md`).
- `MarkdownConstants.calloutAccent` — callout accents and `inlineCodeScale`, read by both surfaces (`references/grammar-modules.md`).

## Live editor rendering (`lib/utils/markdown_editor_span_builder.dart`)

`MarkdownEditorSpanBuilder` (behind `SettingsKeys.liveMarkdownRendering`, routed by `EditorRenderController.buildSpan`): no `BuildContext` under `lib/utils/markdown_editor_*`, no emitter or closure allocated per line; its seven libraries: `references/live-editor-rendering.md`. Invariants:

- **Code-unit preservation** — the returned span always contains exactly the source line's UTF-16 code units. Markers are concealed (transparent + ~0.01 fontSize) or substituted 1:1 (`-`→`•`/`◦`/`▪` by depth, each `>`→`┃`, a task's `[`→the painted checkbox, a callout lead's `[`→the painted `EditorCalloutIconSpan`, an HTML entity's `&`→its decoded character); never insert or remove characters, or caret/selection/search offsets desync. Every 1:1 substitution is listed in the units suite's `_substitutions` table.
- **Span memo LRU** — built spans are cached per line text and returned as identical instances; the cache is cleared when the `EditorRenderContext` generation changes (style / baseColor / primary / isDark) and **must only be consulted after the fence check and the callout check** (fence status and callout membership are positional, not textual: `_route` goes fence → callout → money display → indeterminate task → text-keyed memo, and a callout line — lead or body — always returns through the positional memo keyed `(positionalCallout, packed role + type, text)`). Reveal (caret/selection) lines bypass the cache.
- **Caret-line reveal** — lines covered by the selection show raw dimmed markers **while the editor has focus or an in-note find session is active** (`MarkdownEditorSpanBuilder.revealsLine`, fed by `bindFocus` / `bindRevealWhenUnfocused` on `EditorRenderController`; an unfocused editor renders every line concealed and tappable, 2026-10-19), and a task's box stays painted and tappable on a revealed line unless the collapsed caret sits inside the marker (`taskMarkerRevealed`, half-open `[indent, contentStart)`); the tap policy reads the same predicate and the same caret offset, so render and taps never disagree. Only marker conceal/substitution may differ between reveal states, never line height (no vertical layout shift on caret moves).
- **Ghosts compose** — ghost regions are opaque to the inline scanner (no run opens or closes inside one) and all content is emitted through the ghost-aware `_emit`. Grammar comes from `MarkdownListSyntax` / `GhostText` — never fork them.
- Taps are claimed at tap-down by the fork's `CodeEditorTapInterceptor`; zone rules live only in the pure `EditorInputPolicy.resolveTap`, never the wrapper; keep every pass-through rule (**ghosts win**); a box tap is one atomic value change (`references/live-editor-rendering.md`).
- List lines with content return a `CodeHangingTextSpan` root (fork class): the paragraph provider lays out the marker prefix and content as two paragraphs so wrapped lines get a hanging indent. Never change a line's code units to achieve indent; the hanging span only tags the root.
- Ghost taps are modal; list Tab snaps to the fork's two-column grid; ordered lists are not renumbered on Enter/Tab, by design (`references/live-editor-rendering.md`).

## re_editor fork (`packages/re_editor/`)

- Owned (API is whatever the app needs; upstream watched, not tracked); the whole contract is in `references/fork-and-hot-path.md`.
- Keep its optimizations (2-slot `asString` cache, `_hashCache`, delta counts, binary-search lookups, 128-entry paragraph LRU, 50 ms highlight debounce); new `CodeLines` mutation paths call `cloneShallowDirty()`.
- One-line edits are `replaceLine` / `removeLine`, never `CodeLines.of([...])`; seeding is `loadText`, never `set text`; line-anchored geometry reads `lineHeightOfLine`; never rely on a notification at mount.

## Editor hot-path rules

No per-keystroke string copies, synchronous DB writes, or expensive rebuilds on the typing path. Auto-save (`auto_save_service.dart`) debounce/interval/lifecycle-flush/retry behavior must stay reliable. Adaptive chunk sizing lives in `MarkdownChunker.adaptiveChunkSize` (cap 100), applied by the render service.

## References

| File | Holds | Read when |
| --- | --- | --- |
| `references/grammar-modules.md` | the long module entries, verbatim | changing that module |
| `references/preview-layering.md` | the preview and loading gates, the old intro | preview code or the page's load |
| `references/live-editor-rendering.md` | the renderer's libraries, tap zones, ghost taps, list Tab/Enter | span builder, tap or list work |
| `references/fork-and-hot-path.md` | the fork's whole contract (paste, line heights, scrolling) | any fork or paste change |
| `references/preview-pipeline.md` | the preview pipeline, chunking and lists in full | preview, chunker or list work |
| `references/money-ledger.md` | the money ledger in full | any `$` line change |
| `references/inline-syntaxes.md` | colours and ghost text in full | colour or ghost work |
| `references/vocabulary-autocomplete.md` | vocabulary lists and the suggestion bar | autocomplete work |
| `references/re-editor-fork.md` | the fork's package notes, one bullet per optimization | changing an optimization |
| `docs/live-markdown-editor-roadmap.md` | live editor status, decisions, open gaps | planning rendering work |
| `docs/markdown-feature-ideas.md` | candidate features and fit analysis | proposing new syntax |
| `docs/tag-system-roadmap.md` | the tag feature plan | tag work |
