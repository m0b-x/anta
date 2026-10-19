# Markdown features — the Obsidian audit (2026-10-19)

**Status: PROPOSED 2026-10-19 — nothing implemented.** The owner asked, after
the editor quality-of-life pass (`docs/editor-qol-review-2026-10-19.md`),
whether the markdown features themselves work the way Obsidian's do and are
in good shape. Three sources: one read-only review (Opus 5.5) of every
grammar module and both renderers against an Obsidian Flavored Markdown
matrix (60 constructs, §3); the lead's own probe of the grammar modules over
a corpus note (every line tokenized and shaped — the corpus is now the QA
fixture `tool/qa/fixtures/markdown_corpus.json`, two notes, kept as the
regression corpus for any grammar change); and a screenshot series of that
corpus rendered live on the Pixel_9_Pro emulator in both themes, read by the
lead (`build/qa/shots/20261019_19*`, light `corpus_light_01…07`, dark
`corpus_dark_01…09`, three caret-reveal shots and the front-matter note).
The list is §2; the owner accepts rows one at a time, or says "all".
Line numbers are from the tree after the quality-of-life pass — re-grep
before editing.

Contents: §0 How to run this · §1 What holds · §2 The list · §3 The matrix ·
§4 Declined, deferred, catalogued elsewhere · §5 Ledger.

## 0. How to run this

The implementing session runs on **Opus 5.5 at high**; it loads
`markdown-engine` (SKILL.md whole, then `references/grammar-modules.md` and
`references/inline-syntaxes.md` by section), `flutter-principles`, `verify`,
`l10n` for any string (callout titles, F10). One `implementer` per slice,
one `reviewer` per slice, the corpus fixture re-shot on the emulator by a
`qa-runner` at the end (the steps are in the §5 ledger). The gate after
every slice: `dart analyze lib test` (plus `packages/re_editor/lib` if the
fork is touched), the **whole** `flutter test` in one run (on Windows the
known failure is `test/qa/host_devices_test.dart` "MacosDevice locate…"),
`flutter gen-l10n` + `untranslated.txt` `{}` when an ARB changed, and the
rules below re-read against `git diff`.

### 0.1 Must not change

- **One grammar per syntax** (`lib/utils/markdown_*_syntax.dart`,
  `markdown_inline_grammar.dart`, `markdown_line_shape.dart`,
  `markdown_link_patterns.dart`, `markdown_chunker.dart`): a construct
  changes in its module and both surfaces follow; the agreement suite
  `test/utils/markdown_inline_agreement_test.dart` must stay meaningful.
- **Code-unit preservation** in the editor: every fix conceals or
  substitutes 1:1, never inserts or drops units; the units suite's
  `_substitutions` table lists every substitution.
- The money ledger (`MarkdownMoneySyntax`) keeps its line-led grammar; a
  fold is never forked.
- The owner decisions on record: no ordered renumbering, no `1. [ ]`,
  tables-lite is the ceiling (no column alignment), inline images stay
  raw as images (a glyph for the chrome is allowed, F21), the plain-text
  path stays, callout band backgrounds stay preview-only.
- `MarkdownPlainText` (share/export, note previews) follows every grammar
  change in the same slice.

## 1. What holds (seen on the device and pinned by tests)

ATX headings with graded sizes; `#tag` vs heading at line start; bold,
italic, bold-italic, nesting both ways, `snake_case` safe, CommonMark's
intraword `*`; strike, highlight and their combination; code spans with
matched backtick runs and inner backticks; backslash escapes with the
backslash concealed; inline links concealed and tappable, emphasis around
and inside them; bare URLs trimmed of trailing `.`/`)`; `[[wiki links]]`;
`-`/`*`/`+` bullets cycling `•◦▪`, 2-space and tab nesting, `1.`/`1)`
numbering as typed, tasks `[ ]`/`[x]`/`[X]` with tappable boxes and
indeterminate parents, loose items; quotes and nested quotes with 1:1
bars; callouts with icon and accent title; fences (indented, unclosed to
EOF); `---`/`***`/`___`/`----` rules; tags with dashes and non-ASCII
letters; ghosts, colours, money rows; dark theme consistent (amber
highlight, transparent conceal). The caret-line reveal shows the raw
markers dimmed and keeps the task box painted.

## 2. The list

Accept, skip or pick an option per row. Size: S under ~50 lines, M a
focused slice, L a rework. "Source" is the reviewer's finding (§3) or the
lead's device read.

### 2.1 Tier 1 — wrong renderings that ordinary notes hit

| ID | Source | What | Recommended fix | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| F1 | M1, M10 | A one-line ```` ```code``` ```` (a pasted chat snippet) or a ```` ```js ```` closer opens a fence to the end of the note: everything after it goes monospace, tags and links die, money rows go inert, the plain-text preview drops the rest; `~~~` fences are not fences at all | `MarkdownChunker`: an opener with a length and an info string without backticks, a closer at least as long with no info string; `~~~` the same way; the fence role carried by the line index, `isLineLedConstruct` and `MarkdownPlainText` | M | |
| F2 | M2 | `[t](url "title")` opens `url "title"`; `[t](…/Foo_(bar))` cuts the URL at the first `)` and shows a stray `)` | CommonMark destination parsing in `MarkdownLinkPatterns.matchInlineLinkAt`: balanced parens, `<…>` form, optional title; `urlOf` returns the destination only; concealed range unchanged | S–M | |
| F3 | M3 | A bare URL with parentheses (`…/wiki/Squat_(exercise)`) is cut short and opens the wrong page | Balanced-paren extension in `matchBareUrlEnd`; trailing `)` trimmed only when unbalanced | S | |
| F4 | M4 | `[[Note#heading]]`, `[[Note^id]]`, `[[Note.md]]` say "not found" although Note exists | Split the title at the first `#`/`^`, strip `.md` before resolving (page and `EventSheetsFlow`); option B also scrolls to the heading through `MarkdownLineShape.headingAt` | S (B: M) | |
| F5 | M5 | `\|` inside a table cell splits the cell on all three surfaces and shows the `\` | One cell-boundary helper in `MarkdownLineShape` that skips escaped pipes, used by the editor, the preview and the plain text | S | |
| F6 | M9 | `#program/5x5` tags only `#program`; `#5x5`, `#531`, `#1rm` are not tags | Allow inner `/` and digit-led bodies that contain a letter (all-digit stays plain); check `normalizeForSearch` and the tag search | S | |
| F7 | M11 | `- - -` and `* * *` render as a bullet instead of a rule | Spaced runs in `isHorizontalRule`, tested before the list grammar in both dispatchers; one pinned test changes | S | |
| F8 | M12 | `_italic_` after non-ASCII punctuation stays literal: `„_foarte greu_“`, `—_x_` (Romanian and German quotes) | Above 0x7F count only letters and digits as word characters in the inline grammar's flanking test | S | |
| F9 | M6 | A foldable callout `> [!WARNING]- Knee` shows the title "- Knee" | `parseLead` records the `-`/`+` marker; the editor conceals it, the preview drops it (folding itself stays out) | S | |
| F10 | device, M14 | A callout lead with no title shows the raw `[!WARNING]` in colour; Obsidian shows "Warning" as the title. Only 7 types are known; `[!info]`, `[!example]`, `[!question]`, `[!danger]`, `[!bug]`, `[!todo]`, `[!quote]`, `[!abstract]`, `[!failure]` and aliases (`hint`, `check`, `done`, `faq`, `error`) fall back to a dim quote with the raw token | The type name becomes the default title (localized en/de/ro); an alias map onto the existing kinds plus a `note`-styled fallback for any `[!word]`, label from the token; new kinds only if the packed role+type field in the line index has room | S (aliases) · M (new kinds) | |
| F11 | M19 | Closing hashes `## Week 3 ##` stay visible | `contentEnd` on `MarkdownHeadingMatch` dropping a closing run after a space; the editor conceals it | S | |
| F12 | M18 | `<https://x.y>` keeps its angle brackets; `<mailto:a@b.c>` is plain | A tokenizer construct: brackets concealed in the editor, dropped in the preview, the URL tappable | S | |
| F13 | 5l (#6) | `[[Note\|alias]]` is literal — the most common wiki-link form in Obsidian vaults | Alias in the wiki-link token: display the alias, open Note; the preview and plain text show the alias | S | |

### 2.2 Tier 2 — constructs people type that ANTA does not render

| ID | Source | What | Recommended fix | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| F14 | M8 | Custom task states `- [-]`, `[/]`, `[>]`, `[?]` render as a bullet with raw brackets; a skipped set would read well as `[-]` | Widen the task class in both list regexes (lockstep, pinned); the box paints a state glyph (dash, half, arrow, question); decision: a tap on a custom state cycles back to `[ ]` (A) or does nothing (B) | M | |
| F15 | M13, device | A list, task or heading inside a quote or callout is literal: `> - [ ] warm-up` has no box | Run `MarkdownListSyntax` and `headingAt` on the quote remainder with shifted offsets on both surfaces; the tap policy and the task index learn quoted boxes | M–L | |
| F16 | 1d, device | Setext headings (`Title` + `===` / `---`) are literal and the `---` line is a rule | A: support setext (a `---` directly under a text line becomes an H2 underline, as in Obsidian — changes today's rule-under-text) · B: leave | M | |
| F17 | M15 | `%%comments%%` are visible and land in note previews and exports | An inline atom (dim in the editor, dropped in the preview and plain text) and a `%%` block in the chunker | M | |
| F18 | M7, device | A list nested with 4 spaces (GitHub, VS Code, an Obsidian vault with spaces) shows two levels per step | A: accept and document (recommended now) · B: positional nesting from the parent's content column in the line index | L | |
| F19 | 4b | `&amp;`, `&copy;`, `&nbsp;` show raw | Decode the common named and numeric entities 1:1 where possible, else leave; raw HTML tags stay raw (note) | S | |
| F20 | 5h, 5n | `![alt](url)` and `![[file]]` show their whole chrome | Conceal the chrome and show the alt text with a picture glyph; no image is loaded (the inline-images decision stands) | S | |
| F21 | 10b | A trailing `\` hard break shows the backslash | Conceal a trailing backslash on a line with a following line | S | |
| F22 | 8d | A table without outer pipes (`a \| b` over `--- \| ---`) is plain text | Recognise it only when the next line is a delimiter row | S–M | |
| F23 | M17 | Deprecated preview: an indented table row or image line shifts search offsets by the indent | Add the indent to `lineStart` | XS | |

### 2.3 Tier 3 — divergences to decide, not bugs

| ID | Source | What | Recommended | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| F24 | review | `Squat 3*10, Bench 3*8` italicises "10, Bench 3" — correct per CommonMark and Obsidian, wrong for a gym log | A: a documented deviation — a `*` flanked by digits on both sides never opens or closes emphasis (`_` already behaves so) · B: keep CommonMark | S | |
| F25 | M20 | `**Note:**100kg` is bold in ANTA, literal in CommonMark | Keep ANTA's lenient flanking (it helps); record it | XS | |
| F26 | M16 | With the ledger on, a `$$` math delimiter line reads as a ledger total | Nothing now (equations are catalogued, the ledger is off by default); settle precedence if math ever lands | — | |
| F27 | 1f, 6f, 7b | Headings inside list items, lazy continuation lines for lists and quotes | Leave: the editor is line-based by design | — | |

## 3. The matrix (reviewer, read-only; C = pinned test or traced input, P = reading only)

| # | Construct | Obsidian | ANTA editor | ANTA preview | Verdict | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1a | ATX `#`..`######` + space; `#tag` | heading / tag | scaled, `# ` concealed; tag tinted | scaled | OK | `markdown_line_shape.dart:64-91` (C) |
| 1b | `#\tTitle`, 4-space `# x` | heading; code block | not a heading; heading | same | PARTIAL (deliberate) | line_shape_test:75-96 (C) |
| 1c | `## Title ##` | `##` hidden | visible | visible | PARTIAL | F11 |
| 1d | Setext | H1 / H2 | literal / rule | same | MISSING | F16 |
| 1f | `- # H` | heading | bullet + literal | same | PARTIAL | F27 |
| 2a | `**` `__` `*` `_` `***x***`, nesting | CommonMark | concealed, styled | markers dropped | OK | grammar_test:82-131 (C) |
| 2b | `snake_case_x`, `intra*word*`, `2*3*4` | no / italic / italic | same | same | OK | grammar_test:114,126 (C); F24 |
| 2c | `„_x_“`, `—_x_` | italic | literal | literal | WRONG | `markdown_inline_grammar.dart:409-414` (C); F8 |
| 2d | `**Squat:**100` | literal | bold | bold | lenient | `:219-220` (C); F25 |
| 2e | Unclosed markers | literal | literal | literal | OK | grammar_test:229,237 |
| 2f | `~~s~~`, `==h==`, `**==b==**` | yes | yes | yes | OK | device |
| 2g | `**[t](u)**`, `[**b**](u)` | yes | yes | yes | OK | `:141-146` (C) |
| 3a | code spans, inner backticks, `*` inside | yes | chip | yes | OK | `_findFence` (C) |
| 3b | ``` `` `x` `` ``` space stripping | stripped | kept | kept | PARTIAL (cosmetic) | P |
| 3c | ```` ```lang ```` | highlighted | monospace, label dimmed | `// lang` | PARTIAL (no highlighting, by design) | builder:1603 |
| 3d | `~~~` | fence | not a fence | same | MISSING | F1 |
| 3e | Fence in a list item | yes | yes | yes | OK | chunker:106-111 |
| 3f | 4-space code block | code | plain | plain | MISSING (deliberate) | — |
| 3g | Unclosed fence | to EOF | to EOF | to EOF | OK | chunker:156-158 |
| 3h | One-line ```` ```x``` ````, ```` ```js ```` closer | inline code / not a closer | fence to EOF | same | WRONG | chunker:112 (C); F1 |
| 4a | Escapes | yes | `\` concealed | dropped | OK | grammar_test:272,276 |
| 4b | Entities | decoded | raw | raw | MISSING | F19 |
| 4c | Raw HTML | rendered | raw | raw | MISSING (leave) | — |
| 5a | `[t](url)` | link | concealed, tap opens | tappable | OK | device |
| 5b | `[t](url "title")` | title tooltip | display OK, **tap gets the title too** | same | WRONG | `markdown_link_patterns.dart:99` (C); F2 |
| 5c | `(…/Foo_(bar))` | balanced | cut, stray `)` | same | WRONG | F2, device |
| 5d | `<https://x.y>` | brackets hidden | `<>` visible | same | PARTIAL | F12, device |
| 5e | Bare URL, trailing `.` | trimmed | trimmed, tint only (no tap, by design) | tappable | OK | `:206-246` |
| 5f | Bare URL with `(…)` | balanced | cut | wrong page | WRONG | F3 |
| 5g | `[m](mailto:)`, `tel:`; bare `mailto:` | link; unsure | link; plain | same | OK / unsure | page:1421-1443 |
| 5h | `![alt](url)` | image | raw | `🖼 alt` whole-line only | MISSING (catalogued) | F20 |
| 5i | `[t][1]` + `[1]: u` | link | literal | literal | MISSING (#14) | §4 |
| 5j | `[^1]` | footnote | literal | literal | MISSING (#11) | §4 |
| 5k | `[[Note]]` | link | tappable | tappable | OK | device |
| 5l | `[[Note\|alias]]` | alias | literal | literal | MISSING | F13, device |
| 5m | `[[Note#h]]`, `[[Note^id]]`, `[[Note.md]]` | opens Note | renders, tap "not found" | same | WRONG | page:1560-1570 (C); F4 |
| 5n | `![[file]]` | embed | `!` + link | same | MISSING | F20, device |
| 5o | `^blockid` | hidden | literal | literal | MISSING (leave) | — |
| 6a | `-` `*` `+`, empty `- ` | bullets | `•◦▪` 1:1 | same | OK | device |
| 6b | 2-space / tab nesting | one level | one level | same | OK | device |
| 6c | 4-space nesting | one level | two levels | same | WRONG | `markdown_list_syntax.dart:273-286` (C); F18 |
| 6d | `1.` `1)`, start ≠ 1 | as typed | as typed | same | OK | device |
| 6e | Loose vs tight | yes | line-based | spacer | OK | device |
| 6f | Lazy continuation | joins | indented plain | same | PARTIAL | F27 |
| 6g | `[ ]` `[x]` `[X]` | task | box | ☐/☒ | OK | device |
| 6h | `[-]` `[/]` `[>]` `[?]` | task | bullet + raw | same | PARTIAL | `:81`, `scanListShape:206` (C); F14 |
| 6i | Task under a bullet | yes | yes + indeterminate parent | yes | OK | — |
| 7a | `>`, `>x`, `> > n` | quote | bars 1:1, italic dimmed | same | OK | device |
| 7b | Lazy quote continuation | joins | ends the block | same | PARTIAL | `blockStep:149` (C); F27 |
| 7c | List/heading/task in a quote | rendered | literal | literal | PARTIAL | editor:734-748, builder:1008 (C); F15 |
| 7d | `> [!TIP] title` | callout | icon + title | emoji + label | OK | device |
| 7e | `> [!TIP]-` / `+` | foldable, marker hidden | marker in the title | same | WRONG | `parseLead:259-265` (C); F9 |
| 7f | Unknown / unaliased types; no title | callout | dim quote, raw token | same | PARTIAL | callout_test:164 (C); F10 |
| 7g | Nested callout | nested | body tinted, no icon | body | PARTIAL | callout_test:145 (C) |
| 7h | Fence inside a callout | code | not fenced | same | PARTIAL | `isFenceDelimiter` sees `>` (C) |
| 8a | Table | widget | tables-lite | cells joined | PARTIAL (documented ceiling) | device |
| 8b | Alignment colons | aligned | ignored | ignored | PARTIAL (by design) | — |
| 8c | `\|` in a cell | literal | splits, `\` shown | same | WRONG | F5 |
| 8d | No outer pipes | table | plain | plain | MISSING | F22 |
| 8f | Indented row (preview) | — | — | offsets shifted | WRONG (preview) | builder:678 (C); F23 |
| 9a | `---` `***` `___` `----` | rule | 1:1 short rule | rule | OK | device |
| 9b | `- - -` `* * *` | rule | bullet | same | WRONG (pinned) | line_shape_test:120-124 (C); F7 |
| 10a | Hard-wrapped lines | as typed | line-based | same | OK | — |
| 10b | Trailing `\` | break | `\` visible | same | PARTIAL | F21 |
| 11a | `%%c%%` | hidden / dimmed | raw, in previews too | raw | MISSING | F17 |
| 11b | `$x$`, `$$` | math | raw; `$$` line = ledger total when on | same | catalogued + collision | F26 |
| 11c | Front matter | Properties | rule + plain | same | MISSING (#8) | device, §4 |
| 11d | `#nested/tag` | hierarchical | `#nested` only | same | WRONG | `markdown_tag_syntax.dart:50-54` (C); F6 |
| 11e | `#123` | not a tag | not a tag | same | OK | device |
| 11f | `#5x5`, `#1rm` | tags | plain | same | PARTIAL | `:73` (C); F6 |
| 11g | `#tag` in code / URL | not a tag | not a tag | same | OK | grammar_test:343 |
| 11h | Mermaid | diagram | code | code | MISSING (leave) | — |
| 11i | Callout types | 13 + aliases | 7 | same | PARTIAL | `typeFromToken:211-230`; F10 |

ANTA-only, no verdict: money rows, `{{ghost}}`, `{name:text}` colours and
`==name:text==`, `•` bullets, indeterminate parents, counters.

## 4. Declined, deferred, catalogued elsewhere

- **F22 tables without outer pipes** — deferred 2026-10-20: positional
  recognition does not fit the forward-only line index (see §5); reopen
  only with a one-line lookahead role designed into the index's seam model.
- **Obsidian's escaped alias in tables, `[[Note\|alias]]`** — renders raw
  on every surface; a link would need `matchWikiLinkAt` to read `\|` as the
  alias pipe everywhere.
- **A linked image `[![alt](img)](url)`** — needs a bracket stack in the
  link grammar; the inner image renders, the outer link does not.

- `docs/markdown-feature-ideas.md` already carries: images and embeds,
  equations, collapsible sections, front matter (#8), footnotes (#11),
  reference links (#14), ordered renumbering (#4), wiki aliases/embeds/
  autocomplete (#6). F13 and F20 promote the two cheap halves; the rest
  stays there.
- Syntax highlighting inside fences, Mermaid, raw HTML rendering, block
  ids: out of scope for an offline notes app on a phone.
- Column-aligned tables, full-width rules, inline images, select/copy of
  rendered text: impossible or pointless under the code-unit invariant
  (`docs/live-editor-review-and-slices-2026-09.md` §4).

## 5. Ledger

- **2026-10-19/20, phase one BUILT — slices A, B1, B2, C and S (F2, F3, F4
  option B, F5, F6, F7, F8, F11, F12, F13, F19, F20, F21, F23, F24 plus the
  sweep), every slice gated green (`flutter test test/utils` and the slice
  suites, `dart analyze` clean, `untranslated.txt` `{}`).** Run as one
  workflow on the owner's "solve all of them, be very careful": per slice one
  implementer (Opus 5.5), three read-only reviewers (correctness, Obsidian
  parity, tests), three independent verifiers per finding (majority keeps a
  finding), one fix pass, one gate agent computing the next baseline tree
  (A `4bf3f00c`, B1 `ce02c46a`, B2 `15800553`, C `7de21135`, S `99b8af15`).
  Findings: A 33 raised / 27 kept / 19 fixed; B1 32 / 31 / 23; B2 31 / 28 /
  30; C 23 / 21 / 18; S 25 / 22 / 19. The run was interrupted by a power
  loss during B2's fix pass and resumed from the journal with every finished
  agent served from cache. **As built, where it departs from §2/§3:**
  - F2/F3: a destination that fails the CommonMark reading still closes at
    the first `)`; a bare URL's mid-run `)` that closes nothing ends it, and
    an unclosed `(` ends it before that `(` (GFM trims only trailing parens
    — accepted as the slice's rule); titles in `"…"`, `'…'`, `(…)` with
    backslash escapes; `[t](u 'Bob's guide')` cannot parse a title and
    opens no title.
  - F4: the raw title is looked up first (a note named with `#` or `^`
    still resolves), then the split; `[[Note#A#B]]` lands on the last
    segment as Obsidian does; `[[Note^id]]` opens the note with no
    heading; a heading with closing hashes (`## X ##`) now matches `[[#X]]`
    after S2's `contentEnd`; on another note the caret moves to the heading
    line (replacing the restored position), on the same note only the view
    scrolls; the event flow resolves but never scrolls, and `[[#h]]` from an
    event description says "not found" (no current note there).
  - F12: an escape or ghost atom inside `<…>` refuses the autolink
    (pinned); `<b>` stays literal.
  - F13: `[[a|b|c]]` stays literal (pinned in seven suites); `[[a|]]` shows
    the title; Obsidian's table spelling `[[Note\|alias]]` renders raw
    (the `\|` is an escape atom, so no link is built — deferred, §4).
  - F20: the glyph is `▣` U+25A3 for the `!` of `![alt](dest)` and
    `![[file]]`; the wiki part of an embed keeps its tap zone (as before
    the slice); `alert_excerpt` prints the alt since S5.
  - F6: `#1e90ff` and `#2nd` are tags (digit-led with a letter), `#123` is
    not; a letterless non-numeric body stays prose (Obsidian would tag it —
    accepted).
  - F7: the rule indent stays unbounded (the baseline `\t---` pin); the
    editor draws spaced rules solid since S1 (every unit of the rule line,
    whitespace included, is `─`); a rule wider than the viewport still wraps
    off-caret (unmeasured, left).
  - F11: `## Week 3 ##` picked at H2 again gives `Week 3` since S2.
  - F8/F24: `3**10 and 5**2` is still bold (runs of two unchanged); a `_`
    run followed by non-ASCII whitespace still opens emphasis (left).
  - F19: 32 named entities plus numeric forms; uppercase HTML5 names
    (`&AMP;`) stay literal; typographic quotes and arrows are not in the
    table (left); an entity inside a link destination, autolink, wiki link
    or ghost is not decoded; derived preview/FTS columns pick the decoded
    text up on the note's next save, nothing backfills them.
  - F21: the hard break is text-only in phase one — `- D:\Backups\` and a
    paragraph's last line lose the visible `\` — and headings, callout
    titles and money rows never take one; phase two makes it positional
    (slice D): a `\` is a break only when a non-blank line follows.
  - F5: `MarkdownLineShape.nextTableCellPipe` skips `\|`, the alias pipe of
    a wiki link and pipes inside ghosts on all three surfaces; a table
    context in the emitters (P4) is an accepted gap.
  - F22: **left out, deferred (§4).** The line index is forward-only with
    seam proofs; a pipeless header's role depends on the next line, which
    would back-patch a line in the proven prefix; the plain text and the tap
    policy would each need a positional pass. No partial version shipped.
  - F23: done.
  - S: spaced rules solid (S1); heading removal drops the closing run
    (S2); the tokenizer's tag clamp agrees with `MarkdownTagSyntax` (S3);
    `isLineLedConstruct` and the width calculator read the raw line, the
    calculator's fence toggle is `MarkdownChunker.isFenceDelimiter` (S4);
    the alert excerpt prints image alts and drops hard-break backslashes
    (S5); the list-aware paste and the width breaker no longer turn a
    continuation line that is a rule into a bullet, and the header rewrite
    skips fenced lines. The grammar's NBSP quote lead and unlimited indent
    stay (tier-3 notes).
  - The corpus fixture gained lines for every construct and a permanent
    validity test (`test/qa/markdown_corpus_fixture_test.dart`).
- **2026-10-19** — written by the lead (Fable 5.1). The reviewer ran the six
  grammar suites green (651 tests). The lead's probe: a throwaway test that
  tokenized every corpus line (deleted after the run); the device series by
  a `qa-runner`: `qa relaunch --fresh --seed tool/qa/fixtures/markdown_corpus.json`,
  open Corpus → "Markdown corpus" unfocused, `set theme=light locale=en scale=1.0`,
  `swipe up --from 640,2100 --dist 800 --shot corpus_light_NN` until the end
  (x stays at 640; x near 1232 is the scrollbar), the same under
  `set theme=dark`, three caret taps at `1100,<y>` for the reveal shots,
  `tap id:nav-back` → "Front matter"; `qa errors` clean. The emulator cannot
  show Obsidian itself, so every "Obsidian" cell is from the reviewer's and
  the lead's knowledge of 1.x, marked unsure where it is.
