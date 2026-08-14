# Live Markdown Editor — Status & Roadmap

Obsidian-style live rendering inside the re_editor text mode: markdown renders
as you type, the caret line reveals raw markers, preview mode stays untouched.
This doc is the session-to-session ledger: what is built, the decisions behind
it, and what remains to reach a "perfect" Obsidian-like experience.

Invariants live in `.claude/skills/markdown-engine/SKILL.md` (Live editor
rendering + re_editor fork sections) — read those before touching anything
listed here.

---

## Architecture (as built)

```
Settings → Editor → "Live Markdown Rendering"  (SettingsKeys.liveMarkdownRendering, default ON)
  OptimizedNoteEditorPage._buildEditorSpan          — routing: markdown → ghost fallback
    MarkdownEditorSpanBuilder (lib/utils/markdown_editor_span_builder.dart)
      • per-line restyling, LRU span memo, fence index (+ public lineInFence),
        ghost composition, CodeHangingTextSpan roots for list items
    _buildGhostEditorSpan (page, top-level)          — plain ghost rendering when unhandled/off
  ModernEditorWrapper                                — ghost two-tap; tap interceptor
      • CodeEditorTapInterceptor: checkbox toggle + link open resolved from
        line text via shared grammars; page wires onOpenLink (_handleLinkTap)
        and isFenceLine (span builder)
  packages/re_editor fork
      • _code_paragraph.dart: root-span fontSize ⇒ per-line strut/line height;
        CodeHangingTextSpan ⇒ marker+content two-paragraph hanging indent
      • _code_field.dart: caret drawn at the paragraph's own line height;
        positionAt() non-mutating hit-test
      • _code_selection.dart: tapInterceptor claims taps at tap-down (no
        selection/focus), fires the action at tap-up
```

**The one hard rule:** rendered spans keep the source line's exact UTF-16
code-unit count. Markers are concealed (transparent + ~0.01 fontSize) or
substituted 1:1 (`-`→`•`, `[`→MaterialIcons glyph) — never inserted/removed.

**Performance model:** O(visible lines). Span memo LRU (1024, keyed by line
text, sentinel for raw lines) cleared on style/theme generation change;
consulted only *after* the fence check (fence status is positional). Fence
index rebuilds lazily on CodeLines identity change (O(n) prefix checks).
Long lines (>4096 chars) render raw. Reveal (selection) lines bypass the memo.

## Done

- [x] Headers `#`–`######` at preview scale factors (H1 2.0 / H2 1.5 / H3 1.25 /
      H4 1.125; H5–H6 clamped to 1.0, bold only) with real per-line heights
- [x] Bullets (`-*+•` → `•`), ordered-list marker tint, indent preserved
- [x] Task boxes as check glyphs (0.85× text size), checked content struck+dimmed
- [x] Inline: `**bold**`, `*italic*`, `__bold__`, `_italic_` (word-boundary
      guarded — snake_case safe), `~~strike~~`, `` `code` `` (bg tint, literal inside)
- [x] `==highlight==` — amber background matching preview (shared
      `MarkdownConstants.markBackground{Light,Dark}`)
- [x] Blockquotes `> ` — `>` substituted 1:1 with `┃` (preview's bar glyph),
      content italic + dimmed, inline styling composes inside
- [x] `#tag` tint — render-only, matches preview (primary color + 12% bg);
      grammar extracted to shared `MarkdownTagSyntax` (preview now delegates)
- [x] Horizontal rule `---` / `***` / `___` — each marker char substituted 1:1
      with `─`, dimmed, base line height kept
- [x] Links: `[text](url)` shows the text tinted + underlined with `[` and
      `](url)` concealed off-caret (dimmed on reveal); inline styling composes
      inside the text. Bare `http(s)://` / `www.` URLs tint in place
      (render-only, nothing concealed). Extent + trailing-punctuation grammar
      extracted to `MarkdownLinkPatterns.matchBareUrlEnd` (preview delegates)
- [x] Link construct grammar also shared: `MarkdownLinkPatterns
      .matchInlineLinkAt` drives preview parsing, editor rendering, and the
      wrapper's tap zones — one grammar, three consumers
- [x] Backslash escapes: `\*` renders a literal `*` with the `\` concealed
      (dimmed on reveal); the escaped char never opens a run/tag/link
- [x] Callout lead lines `> [!TIP] title`: quote bar + `[!TYPE]` token tinted
      with the type accent (palette moved to `MarkdownConstants.calloutAccent`,
      shared with preview); token stays tinted on reveal (nothing concealed)
- [x] Code fences: delimiter lines monospace + dimmed, interior monospace over
      the inline-code background tint; positional, so fence lines use their
      own role+text-keyed memo (identical instances keep re_editor's paragraph
      cache warm); ghosts still compose inside interiors
- [x] H5/H6: base size + bold kept, now blended toward primary (H6 muted) so
      they read as headings without breaking the line-height rule
- [x] Tap interception (fork `CodeEditorTapInterceptor`): taps on checkbox
      boxes and concealed links are claimed at tap-down inside the editor's
      own gesture pipeline — no caret move, no focus request (keyboard no
      longer rises on an unfocused editor), and re-taps on the same spot fire
      every time. Old selection-listener toggle scheme deleted
- [x] Link tap-to-open: tapping a concealed link opens it through the page's
      existing scheme-validated opener (`_handleLinkTap` — http/https/mailto/
      tel + localized errors); revealed lines pass through to editing
- [x] Hanging indent for wrapped list items: `CodeHangingTextSpan` root spans
      make the fork lay out marker prefix + content as two paragraphs
      (`_HangingParagraphImpl`), continuation lines align under content;
      caret/selection/hit-test/word/line-boundary geometry maps piecewise;
      falls back to a plain paragraph for degenerate splits
- [x] Ghost `{{ … }}` composition: markers concealed, inner dimmed, inherits
      surrounding style; ghost regions opaque to the inline scanner
- [x] Caret-line reveal (Obsidian-style): selection-covered lines show raw
      dimmed markers; line *height* never changes with reveal (no layout shift)
- [x] Code-fence awareness (mirrors MarkdownChunker's ``` rule); fence interior raw
- [x] Checkbox tap-to-toggle: atomic single value change, pre-tap selection
      restored — tapping the box never starts an editing session; ghosts win
- [x] Ghost two-tap: tap 1 selects run (type to replace), tap 2 on same
      unmodified ghost leaves the caret for in-place editing
- [x] Fork: caret fills scaled header lines (was floating at line top)
- [x] Fork: everything anchored to a line now uses that line's own height on
      scaled lines — selection-handle anchors + the handle widget's own
      geometry (the cupertino handle's vertical bar), drag-start
      center-of-line math, selection toolbar anchors, IME caret/composing
      rects, floating + preview cursors. New render APIs:
      `lineHeightOfLine(index)` / `lineHeightAtOffset(offset)`; handle
      overlays re-mark on selection changes so geometry tracks line height
- [x] General setting (default ON), l10n en/de/ro, reset-to-defaults wired;
      experimental dev option removed
- [x] `dart analyze` clean (only pre-existing repo findings)

### Decision log

- Reveal = selection covers line (multi-line selections reveal every covered line).
- Ghost markers stay concealed even on reveal lines (ghost UX is its own mode).
- Box-tap zone is `[indent.length, bracketStart+3]` — the marker region left
  of the box toggles too (fat-finger tolerance); indent columns keep caret
  placement, and the caret can still reach the box chars via arrow keys.
- Intercepted actions give haptic confirmation (lightImpact on toggle,
  selectionClick on link tap) because the caret/keyboard intentionally don't
  react — matches the toolbar's unconditional-haptics pattern.
- Editor link taps are confirm-first: a snackbar shows the target host with an
  Open action (`linkOpenPrompt`/`linkOpenAction`, wired to the page's
  `_handleEditorLinkTap`) so an accidental mid-workout tap never leaves the
  app; preview link taps keep instant open.
- H5/H6 don't shrink below base size — sub-base line heights buy nothing in an editor.
- Toolbar Italic inserts `_underscores_` → editor + preview both render them;
  intra-word `_` is never emphasis (matches preview).
- Quote bar/highlight colors depend on theme brightness → `_isDark` joined the
  span-cache generation check (style/baseColor/primary/isDark).
- Callout lines (`> [!TIP]`) get the plain-quote treatment in the editor for
  now; dedicated type-token tinting stays on the roadmap.
- Rule lines keep the base font size (same reasoning as H5/H6 — sub-base line
  heights buy nothing); the `─` run is only as wide as the source markers.
- Tags conceal nothing, so they stay tinted on reveal lines; editor tags are
  render-only (no tap) — tag taps remain a preview feature.
- A lone `#` (empty-header edge) stays raw — not a header (no space), not a
  tag (no letter-led body).
- `![image](url)` stays raw in the editor — a `[` preceded by `!` never opens
  a link (styling `!alt` as a link would misread; preview owns images).
- Bare URLs conceal nothing, so like tags they stay tinted on reveal lines.
- `matchBareUrlEnd` requires ≥1 char past the scheme after the punctuation
  trim — also fixes the preview linking a bare `www.` followed by punctuation.
- Tap-interception modality: off-caret concealed constructs are *objects*
  (checkbox toggles, link opens); a reveal (selection-covered) line shows raw
  markdown, so every tap there means editing and passes through. This also
  means a checkbox on the caret line is toggled via arrow keys/typing, not tap.
- Ghosts win over interception: taps inside a ghost run pass through so ghost
  engagement (which rides the selection change) keeps working; an intercepted
  tap disarms the ghost-tap check so the toggle's own notification can't
  activate a stale ghost.
- Bare URLs are NOT tap-to-open in the editor: they are fully visible source
  text, so tapping them places the caret (opening lives in preview). Only the
  partially-concealed `[text](url)` construct opens on tap.
- Wrapper tap zones re-resolve at tap-up, so a text change between down and up
  can never toggle the wrong line; zones derive from the shared grammar, so a
  literal `[x](y)` inside inline code (rendered literal, ultra-rare) would
  still open on tap — accepted divergence.
- Escapes vs ghosts: `\{{x}}` still renders as a ghost in the editor
  (GhostText owns `{{` scanning); the preview treats it as an escaped literal.
  Ghost UX wins in the editor; divergence accepted as a curiosity.
- Callout tint is lead-line-only: continuation lines keep the plain grey quote
  bar because the styling must stay purely textual for the span memo to be
  valid (block-scoped bar tint would need a positional index like fences).
- Hanging indent applies only to live-rendered list lines with content; the
  plain-text path (rendering off) keeps flat wrapping. On reveal the marker
  glyphs change width slightly (`•` vs `-`, box glyph vs `[x]`), so wrapped
  lines may shift horizontally by a few px — vertical stability is what the
  invariant protects.
- Review round of 2026-07-11 (xhigh, 6 finder angles) hardened the batch:
  - Tap zones: taps clamped to a line's end offset (blank space right of /
    below the text) always place the caret; link zones exclude their outermost
    boundary offsets; >4096-char (raw-rendered) lines never intercept;
    `_linkUrlAt` now skips escaped opens (backslash parity), brackets inside
    inline-code backtick runs, and ghost-straddling links. Residual accepted
    divergence: links clamped out by an emphasis-segment end still intercept
    (rare; full fidelity would mean running the inline scanner per tap).
  - Desktop pointer path: interception is primary-button-only, skips
    shift-clicks, is keyed to the claiming pointer id (multi-touch safe), uses
    precise-pointer slop for mice, clears the double-tap timestamps (an
    intercepted tap can't pair into a word-select), and suppresses the outer
    GestureDetector's `ensureInput` so a claimed tap never focuses. Known
    accepted gap: drag-select can't START on a checkbox/link zone on desktop.
  - Ghost interplay: the interceptor disarms the ghost-tap flag again in a
    microtask, beating the wrapper's outer Listener re-arm (desktop dispatch
    order is inner-before-outer).
  - Fences: delimiter lines now compose ghosts too; interior background tint
    dropped (an empty line can't paint one, which rendered striped blocks) —
    interior is plain monospace, delimiters dimmed monospace.
  - Hanging indent: marker width measured via `getBoxesForRange`'s right edge
    (longestLine drops the trailing-space advance); wrapped markers fall back
    to plain layout; `trucate`/`_dropPrefix` count placeholder lengths and
    keep children of text+children spans; `getSpanForPosition` resolves
    against the original root span so recognizer/annotation spans keep
    identity with `getRangeForSpan`.
  - Perf/reuse: bare-URL candidates require `ht`/`ww` pairs so the plain-prose
    quick-reject survives; `selectionCoversLine` and `isEscapablePunctuation`
    are now single-sourced (span builder static / `MarkdownConstants`).

## Not verified on device yet

- Perf batch of 2026-07-18 (incremental line index, paragraph identity
  cache, plain-span memo): typing latency on a 10k+ line note, checkbox
  indeterminate dots after rapid edits/undo across segment boundaries
  (256-line seams), fence styling after typing ``` mid-document

- Checkbox glyph optical size (`_checkboxGlyphScale = 0.85` is the knob)
- Toggle on a box far from the caret: confirm no scroll jump from selection restore
- Undo/redo of a checkbox toggle (selection state after undo)
- Header-heavy notes: scroll estimates use base line height and self-correct —
  watch for jitter on fast fling
- Search-highlight rects over substituted glyphs; IME composing on styled lines
- Line-numbers gutter alignment with variable-height lines (gutter is off by default)
- New in this pass: `==highlight==` contrast on both themes, `┃` quote bar
  glyph metrics, `─` rule appearance, tag tint readability on checked tasks
- Selection handles on/around H1–H4 lines: anchor at the line bottom, handle
  bar length, dragging a handle across mixed-height lines, toolbar position
  over a header selection
- Links: a long concealed URL reflows soft-wrapped lines on reveal (caret
  enters the line and the URL appears) — inherent to conceal, Obsidian-alike;
  underline + primary tint readability over checked/quote/highlight contexts
- Batch of 2026-07-11, rendering: fence interior/delimiter styling on both
  themes (monospace metrics under the base strut), callout bar + token tint
  per type, H5/H6 primary blend readability, escaped-`\` conceal width
- Batch of 2026-07-11, interaction: checkbox tap on unfocused editor (keyboard
  must NOT rise), re-tap re-toggle, haptic strength of toggle/link taps,
  link confirm snackbar (host shown, Open action) + snackbar on bad scheme,
  scroll-drag starting on a checkbox/link (must scroll, not fire), long-press
  on a box (should still select), double-tap on link text
- Batch of 2026-07-11, hanging indent (highest risk): caret x on wrapped list
  lines, selection rects across the marker/content seam and across wrapped
  lines, drag-select, IME composing on a wrapped item, word double-tap near
  the seam, Home/End on first and continuation visual lines, search-highlight
  rects, horizontal-scroll width with wordWrap off, deep-indent fallback

## Roadmap to "perfect Obsidian"

### Remaining gaps

- [ ] Callout *block* treatment: continuation lines keep the plain quote bar;
      a block-scoped accent bar needs a positional callout index (same lazy
      pattern as the fence index) plus a positional cache-bypass for quote
      lines — do it if callouts see real use
- [ ] Callout dedicated rendering (icon, band background) stays preview-only
      by design; revisit only if the tint proves insufficient

### Performance follow-ups (only if profiling says so)

- [x] Fence index is O(total lines) per text mutation → replaced by
      `MarkdownEditorLineIndex` (fence roles + indeterminate task parents in
      one shared incremental index). Exploits `cloneShallowDirty`'s
      structural sharing: per-segment backing-list identity is the dirty
      flag, so a keystroke resumes at the first changed segment (fence pass
      early-stops on a parity-matched unchanged segment; task pass revives
      the boundary frame-stack snapshot and rescans the suffix). Structural
      edits (Enter/paste/delete-line) fall back to a full rebuild, kept
      cheap by the allocation-free `MarkdownListSyntax.scanListShape`
      (charcode scan, no regexes, no MarkdownListItem allocation). Fence
      grammar single-sourced as `MarkdownChunker.isFenceDelimiter` (preview
      block scan + editor index share it; NBSP-indented fences now
      uniformly not fences — was a preview/editor divergence)
- [x] Provider paragraph-cache lookups deep-hash the span tree → fork's
      `_CodeParagraphProvider` got an identity-keyed L1 in front of the
      deep-equality LRU: the span builder's memo returns identical
      instances, so steady-state hits are one pointer hash instead of ~3
      full-tree hashes (lookup + LRU-touch remove/re-add). Also:
      `updateBaseStyle` short-circuits on the Flutter TextStyle before
      allocating a `ui.TextStyle` to compare (was per line per layout), and
      `_CodeHighlighter` memoizes the plain no-theme fallback span per line
      text — which also makes unhandled/plain lines identity-stable through
      the ghost builder's pass-through, so they ride the L1 too

### Product polish

- [ ] Consider surfacing "old system" naming in settings copy if users ask
      what the toggle means (currently: Live Markdown Rendering on/off)
- [ ] Onboarding/what's-new note for the new default behavior
- [ ] Eventually delete the plain-text path? Only after long bake time — it is
      currently the escape hatch and the A/B baseline
