# Live editor — list nesting by indentation (2026-11-08)

**Status: IMPLEMENTED 2026-11-08, uncommitted — N1 (Space + cap), N2
(swipe), N3 + N3b + N3c (visible depth, the revealed marker, the painted
square and the quote gap) built, three code reviews and one design review
answered by two fix passes, the gate green on the final tree (`dart analyze`
→ the fork's two known infos; `flutter test` → `+14866 ~16`), the device pass
and its re-check green; 35 files (27 modified, 8 new); the owner commits.**

Contents: §0 How to run this · §1 Why · §2 Decisions · §3 The spec ·
§4 Behaviour · §5 Facts from the tree · §6 Slices · §7 Definition of done ·
§8 Deferred · §9 Ledger.

## 0. How to run this

The lead runs on Fable 5.1 (the owner asked for quality and allowed agents);
it writes this record and briefs one `implementer` (Opus 5.5, default
effort) per slice, each in its own detached worktree under
`C:\Users\mobx3\AppData\Local\Temp\anta-wt-nest-<a|b|c>` because two
`flutter test` runs in one tree collide on `build/native_assets`. N3 is a
visual slice: the `designer` writes its exact spec first (§3.3), the lead
accepts the designer's lettered defaults on the owner's behalf (the owner
said "build it, focus is quality"; every default is reversible and listed in
§2), then the implementer builds it and a `design-reviewer` checks the
built surface. One `reviewer` per slice on the slice's diff, briefed with §3
and §4; the lead merges the worktrees by `git diff --binary` +
`git apply --3way`, runs the gate once on the merged tree (`dart analyze
lib`, the whole `flutter test`, no ARB changes expected), then one
`qa-runner` for §7's device checks. Skills: `markdown-engine` (SKILL.md plus
`references/live-editor-rendering.md`, the list Tab/Enter bullets, and
`references/fork-and-hot-path.md` for any fork change), `flutter-principles`,
`verify`, `delegation`. Never two writers on one file. Do not commit — the
owner commits; the session that opens this record next corrects the status
line from `git log`.

## 1. Why

The owner, 2026-11-08: a bullet is now easy to add and to delete, but
nesting one is not. Nobody types two spaces before a marker on a phone, and
the only soft-keyboard way to nest is the bar's Indent button in the
scrolling utility strip. The owner wants one quality way to get different
bullet types by indentation.

What the tree already does: the glyph per depth is built — `•` `◦` `▪`
cycling every three levels on both surfaces (`MarkdownListSyntax.bulletGlyph`);
Tab/Shift-Tab, the bar's Indent/Outdent, Backspace after a marker (outdents
a nested item, then strips the marker) and Enter on an empty item (outdents a
nested item, ends a top-level one) all exist since the 2026-10-19 pass. Two
things are missing: a one-input way to nest from the keyboard the thumb is
already on, and a depth that is visible — one level is two literal spaces,
about half a character, so `◦` under `•` reads as a typo rather than a
level.

What the big apps do (web research 2026-11-08, sources in the chat record):
Apple Notes and Craft indent by a horizontal swipe on the item (Craft only on
the block being edited); Google Keep drags an item right, one level only;
Notion, Bear, Obsidian, Samsung Notes and OneNote use bar buttons on mobile
(Bear declined a swipe because it collides with its swipe-back); Workflowy
and Dynalist use swipes for complete/delete and Dynalist turned them into
buttons after accidental deletes. Glyph per depth: disc, circle, square
cycling wherever depth is shown at all (HTML, Word, Docs, Notion); Obsidian
and Bear keep one glyph. Notion and Workflowy cap a block at one level deeper
than the block above it. Nobody types spaces on a phone.

## 2. Decisions

| # | Decision | Why | Who, when |
| --- | --- | --- | --- |
| D1 | **Space on an empty list item indents it one level.** Caret exactly at the item's content start, nothing after it: Space rewrites the line one indent step in, as one undo node. Content items, non-list lines and fenced lines take the plain space. | Enter, Space, type is three keys to a nested item with the thumb never leaving the keyboard; it is the exact dual of the two rules the editor already has (Backspace outdents, Enter on an empty nested item outdents). A second space after an empty bullet has no other meaning. No big app does exactly this; ANTA's own rule. | Owner, 2026-11-08 (A) |
| D2 | **A horizontal swipe on the caret line re-nests it.** Right indents, left outdents, one level per swipe, the caret, selection and focus untouched, a selection-click haptic when a level changed. Only the focused editor's caret line reacts (Craft's gate), touch and stylus only, the swipe may start anywhere on the line. | The idiom people know from Apple Notes and Craft, for the moment an existing line has to move. The caret-line gate means a diagonal flick while scrolling never nests a line (what bit Dynalist); touch-only keeps a mouse drag a selection on Windows; "anywhere on the line" because Android's back gesture owns the first 20–30 dp at the left edge, where the bullet sits. | Owner, 2026-11-08 (B) |
| D3 | **Depth is visible.** The indent run is drawn wider than its literal spaces so one level reads as a clear step (the exact width per level, the tab width and the alignment rule come from the designer's spec in §3.3); the line's code units, its height and the hanging indent rule are unchanged, and the indent width is identical in the concealed and the revealed state. | Two literal spaces are about half a character; Notion, Apple Notes and Obsidian use 1.25–2 em per level. Letter spacing on the indent span widens the advance without adding or dropping a code unit, so the caret and search offsets stay 1:1. This is U3.7 of the 2026-10-19 UX review, left optional then. | Owner, 2026-11-08 (C); width delegated to the designer |
| D4 | **Depth decides the glyph, never the marker character.** `•` `◦` `▪` cycling every three levels stays; `-`, `*` and `+` are not mapped to glyphs. | The convention everywhere depth is shown; CommonMark treats the three markers as interchangeable and notes from other apps would render oddly. | Owner, 2026-11-08 (D) |
| D5 | **An item is never indented more than one level deeper than the list item above it;** a first item, or one after a column-0 paragraph, a heading, a rule or a fence, cannot be indented at all. The cap applies to Space (D1), the swipe (D2), Tab and the bar's Indent alike, through one function; at the cap the action is a no-op (no haptic, the Space keystroke is consumed). Outdent is never capped. | One answer to "how deep can this go" keeps lists from drifting into orphan levels that render as noise; Notion and Workflowy enforce the same rule. | Lead's recommendation, owner's "build it" 2026-11-08 |
| D6 | **Space on an empty ordered item restarts the number at 1** (`2. ` → `  1. `, the delimiter kept). Tab, the swipe and the bar keep the number as today. | A Space-indented empty item starts a new sub-list, so `1.` is the right first number; a moved item with content keeps its number because ordered lists are not renumbered, by design. | Lead's default, reversible |
| D7 | **No setting, no new string, no new bar button.** Haptics follow `EditorSettings.hapticFeedback` as the wrapper's other haptics do; the bar's Indent/Outdent stay as the screen-reader and hardware-free equivalent of the swipe. | Nothing to learn, nothing to configure; the accessible path already exists. | Lead's default |
| D8 | **F18 stays accepted:** a four-space nested note from another app still shows two levels per step. | Out of this rework's scope; the audit's decision stands. | Lead, 2026-11-08 |
| D9 | **One level is 1.25 em of the line's font size** (`MarkdownConstants.listIndentPerLevelEm = 1.25`): 20 dp at 16 px, 26 at 1.3, 40 at linear 2.0, the same for every list kind. | Measured from real-font renders: today a level is 7.92 dp (two Roboto spaces) and a nested glyph sits inside its parent's 9 dp marker. "One level = the parent's marker advance" was rejected: it differs by kind (bullet 9, ordered 17, task 20 dp) and for bullets would step 1 dp more than today. 1.25 em equals the task marker, so nested task boxes sit exactly under the parent's content start, and it is inside the 1.25–2 em range other apps use. | Designer's default A, accepted by the lead 2026-11-08 |
| D10 | **The width follows the grammar's level** (`indentLevel`), not the raw columns: three spaces draw at level 1, a lone tab at exactly one level, four spaces at level 2. | Every level-k glyph shares one column, and a line's position agrees with its glyph. Today a tab draws at one space's width (half a level) and three spaces drift between levels. | Designer's default B, accepted |
| D11 | **Letter spacing only, the first indent unit unspaced.** For an indent of n ≥ 2 units: unit 0 in the plain style, units 1…n−1 with `letterSpacing = (W − natural) / (n − 1)` where W = level × L and natural is the measured sum of space and tab advances. A lone tab: one span with `letterSpacing = (W − natural) / k`, k = 1.5 when the indent starts the line, 1.0 behind quote bars. Space and tab advances are measured once per `EditorRenderContext` generation with a `TextPainter`, keyed by font style. | SkParagraph shifts a line whose first glyph is letter-spaced by half the spacing (the caret at offset 0 moves by ls/2); leaving the first unit unspaced avoids it, and a lone tab cannot, so k = 1.5 absorbs it. The caret x at offset 0 measured 0.00 on every line. | Designer's default C, accepted |
| D12 | **The `◦` and `▪` glyph runs are unchanged** — pending one device screenshot: the SDK's Roboto has neither glyph, so on the phone they come from Android's fallback face. | With a stand-in face both read as different from `•` at 1.0 in light and dark; the device face is the only unknown. | Designer's default D, accepted; the device pass (§7.9) closes it |
| D13 | **The deprecated preview's `indentPerLevel` (16 dp) is left alone.** | The preview is off by default and already differs in metrics. | Designer's default E, accepted |
| D14 | **The fork's hanging fallback at deep levels and large text is accepted:** at linear 2.0 a level-3 task (161 dp prefix) and a level-4 bullet (195 dp) exceed the fork's half-viewport rule (152 dp on 360) and their wrapped lines start at x = 0. | D5 keeps deep nesting rare; the fallback is the fork's existing behaviour; shrinking the level or changing the rule would cost more than it gives. | Designer's default F, accepted |
| D16 | **A lone leading tab's first glyph run starts ls/2 in** (5.3 dp at 16 px, 10.7 at 32): D11's k = 1.5 absorbs the half-spacing shift for the glyph's position; through the fork's own paragraph the caret at offset 0 still draws at 0.00, and the shift shows only as an unpainted sliver at the left of a selection covering the line (the design review's measurement, which supersedes the `TextPainter` caret figure). Accepted: a lone-tab indent is rare on a phone (Gboard has no Tab; it arrives by paste or from a desktop note), the alternative is the half-level tab the rework set out to fix, and the design-reviewer judges the look. | The designer's claim that the caret at offset 0 measured 0.00 on the lone-tab line did not hold in the implementer's geometry test; the test skips that one assertion and measures the glyph x from 0 so the shift stays in the sum — if the engine drops the quirk, the glyph-x assertion fails and the constant is revisited. | Lead, 2026-11-08, from N3's report |
| D17 | **The level-3 square is painted, not typed.** On Android `▪` (U+25AA) is an emoji-capable code point and the device drew it from the emoji font: a grey square that ignores `primary`, about three times a dot's advance (device pass, light and dark). The editor substitutes the `-` of a level-2 bullet (every third level) with one U+FFFC and paints a square (`EditorBulletSquareSpan`, beside `EditorCheckboxSpan`): side 0.28 em, `primary`, centred on the x-height midpoint (0.264 em above the baseline for Roboto), advance equal to the bold `•`'s so the gap and the content column match a dot line; the revealed line still shows the raw `-`. `bulletGlyph(2)` stays `▪` for the deprecated preview and the plain-text surfaces. | A painted glyph is identical on Android, Windows, macOS and in tests (the SDK's Roboto has none of the three symbol glyphs, so renders showed tofu); no font subset has to be bundled; the checkbox is already painted the same way. `■` (U+25A0, not emoji) was rejected: a full-size square is too heavy and a scaled one sits on the baseline, not the x-height centre. | Lead, 2026-11-08, from the device pass |
| D18 | **Quote content does not move on caret entry.** The space after a line's `>` run is letter-spaced in whichever reveal state has the narrower run (the `┃` bars concealed vs the dimmed `>` revealed), the `bulletGap` rule applied to quotes, so a quoted line's content — a nested item's included — keeps its x when the caret enters. | The device showed about 4 dp of movement on `>   - quoted nested` (1.3 dp on the test machine; the bar's fallback face is wider on the phone). The rework's D3 promised no shift on caret entry and quoted nested lists are in its spec (§3.3, §7.6); the infrastructure now exists. Quote-wide by nature: every quote and callout body line gains the same stability. | Lead, 2026-11-08, from the device pass |
| D15 | **The revealed marker keeps the concealed glyph's advance (N3b).** On the caret line the raw `-` is drawn dimmed instead of the bold glyph, and their advances differ, so the content start moves on caret entry: −9 dp at 1.0 and −19 dp at 2.0 on a `◦` line, −1 dp on a `•` line — pre-existing, found by the designer. The space after the revealed marker is letter-spaced by the measured difference (glyph advance − dash advance), so the content and the hanging indent stay put. | "Nothing moves under the finger" is the house rule, and the rework's own D3 promised no horizontal shift on caret entry. The post-marker space is never a line's first glyph, so D11's quirk does not apply. | Lead, 2026-11-08, from the designer's finding 2 |

## 3. The spec

### 3.1 Space on an empty item (N1)

- A typed space arrives at `ListAwarePasteController.edit` as a rewrite of
  the caret line (the IME sees only that line). The shape that triggers the
  rule: the new text is the caret line with exactly one `0x20` inserted at
  the collapsed caret, no composing range — the single-unit sibling of the
  fork's `isSingleBackspace`. Any other shape goes on to the fork unchanged.
- The rule itself is a pure policy beside `MarkerBackspacePolicy`
  (`MarkerSpacePolicy.apply(line, caretOffset, {maxLevel})` or a sibling
  name of the implementer's choosing), table-tested: it returns the new line
  and caret, or `null` when the caret is not exactly at an empty list item's
  content start. "Empty" is `MarkdownListItem.isEmpty`; the item may sit
  inside a quote (`> - |`), in which case the quote run is kept and the
  remainder is indented, exactly as `MarkerBackspacePolicy` reads a quoted
  item.
- The indent step is `EditorInputPolicy.listIndent(outdent: false)` — the
  grid snap Tab uses — so Space, Tab, the swipe and the bar land an item on
  the same column. The cap (§3.4) is passed in; at the cap the policy
  returns the line unchanged and the keystroke is consumed (the space is not
  typed, the line stays an empty item so the next Enter still ends it).
- An ordered empty item restarts at `1` with its delimiter kept (D6):
  `3) ` → `  1) `; a task stays a task (`- [ ] ` → `  - [ ] `); a custom
  state stays (`- [-] ` → `  - [-] `).
- The edit is one revocable op through `replaceLine` with the IME resynced
  (`_applyMarkerBackspace` is the template); fenced lines are skipped
  through the existing `_isFenceLine`.
- Tests: the policy's table (every kind, quoted, capped, non-empty, caret
  not at content start, tab-indented, fenced through the controller suite);
  `list_aware_paste_test.dart` or `ime_edit_test.dart` sends the real IME
  delta and reads the line, the caret and the undo step; a space anywhere
  else types a space.

### 3.2 Swipe on the caret line (N2)

- Fork: a `CodeEditorLineSwipeHandler` beside `CodeEditorTapInterceptor`
  on `CodeEditor` — `shouldHandle(CodeLinePosition down)` and
  `onSwipe(int lineIndex, {required bool toRight})`. The mobile gesture
  branch of `_CodeSelectionGestureDetector` (the `kIsAndroid`/iOS
  `GestureDetector` with tap and long-press handlers) gains one horizontal
  drag recognizer whose `isPointerAllowed` asks `shouldHandle` for the line
  under the pointer-down, so a pointer on any other line never enters the
  gesture arena and every ancestor behaves exactly as today. Devices: touch
  and stylus only (the selection handles' set). The desktop branch is
  untouched (a horizontal drag there is a selection drag).
- The gesture fires once per drag: when the accumulated horizontal travel
  since pointer-down (`DragStartBehavior.down`, so the platform's slop is
  not subtracted and the distance is exactly one touch target) passes
  `CodeEditor.lineSwipeDistance` (48 logical px, a fork constant), in the
  sign of that travel; nothing fires on a shorter drag, on release, or a
  second time in the same drag. Which gesture owns the drag is the slop's
  call, not the distance's: a drag that passes the vertical slop first stays
  a scroll. A pointer-down inside a selection handle's 48 dp target, or
  below the line's own paragraph (the blank area under the last line), is
  refused. With word wrap off, a sideways-scrolling line's own scrollable
  wins the drag and the swipe does not fire there — accepted and documented
  on the handler. The recognizer never moves the caret,
  changes the selection, requests focus or shows the toolbar; a long press
  on the line behaves as today (the long-press recognizer still wins a
  held pointer).
- App: `ModernEditorWrapper` builds the handler. `shouldHandle` is true only
  when the editor has focus, `controller.selection.isSameLine`, the line is
  the selection's line, `MarkdownListUtils.isListLine(text)` (quoted items
  through `quotedListItem` count) and the line is not fenced. `onSwipe`
  runs `ListIndentAction.apply(controller, outdent: !toRight,
  isFenceLine: …)` — the same call as the wrapper's Tab (`_onListIndent`) —
  and fires `HapticFeedback.selectionClick()` only when the line text
  changed and `hapticsEnabled` holds. The cap (§3.4) is inside
  `ListIndentAction`, so the swipe gets it for free.
- Tests: `test/re_editor/line_swipe_test.dart` on the mobile branch through
  `support/editor_test_support.dart`: a right swipe on the allowed line fires
  once with `toRight: true` and leaves selection and focus identical; a left
  swipe fires `toRight: false`; a 20 px drag fires nothing; a drag on a line
  `shouldHandle` refuses fires nothing and reaches an ancestor
  `GestureDetector.onHorizontalDragStart` wrapped around the editor; a mouse
  drag fires nothing; a vertical drag scrolls and fires nothing; a long
  press still selects a word. App side: a wrapper test pins the predicate
  (unfocused editor, non-list line, fenced line, other line all refuse) and
  that the swipe edit equals the Tab edit for the same line.

### 3.3 Visible depth (N3) — the designer's spec

Written by the `designer` after rendering the current states with real fonts
(light and dark, text scale 1.0 / 1.3 / 2.0, 360 dp wide): a four-level
bullet list, nested tasks, a nested ordered list, a wrapped nested item, a
tab-indented item, a four-space item, a quoted nested list. The spec names:

- the width of one level as a function of the font size (the hypothesis to
  judge: the parent's marker advance, so a nested glyph sits under its
  parent's content start, as Word, Docs and Notion align; else a fixed em
  multiple), given as a `MarkdownConstants` name and value;
- how the width is produced: letter spacing on the indent span of
  `_buildListItem` (the only mechanism allowed — the span's text stays the
  source indent, so the units suite stays green) and the value for a tab
  unit so a tab reads as exactly one level;
- what else, if anything, changes in the glyph run (weight, colour, size)
  for `◦` and `▪` to read at 1.0 — or that nothing does;
- the states that must be identical: the concealed and the revealed line
  (the caret line shows the raw `-` dimmed; the indent width must not
  differ, so nothing shifts horizontally on caret entry), the line height,
  the hanging indent (the fork measures the marker paragraph's advance, so
  it follows the wider indent on its own), the bulleted money row.

The designer's lettered defaults are D9–D14 in §2; the spec as delivered
(2026-11-08, renders and `measure.json` in the session scratchpad's
`designer-depth/` folder):

- `MarkdownConstants.listIndentPerLevelEm = 1.25`; L = `style.fontSize ×
  1.25`; W = `MarkdownListSyntax.indentLevel(indent) × L`; a level-0 indent
  (a lone space) is emitted untouched.
- One static helper (`EditorSpanEmitter.listIndent(indent:, style:,
  context:, startsLine:, out:)` or an equivalent name) emits the indent for
  both `_buildListItem` (`startsLine: prefix == null`) and the money row's
  `[0, listMarkerStart)` run in `markdown_editor_money_row.dart` (:180-186
  at HEAD): n ≥ 2 → `indent[0]` plain + `indent.substring(1)` with
  `letterSpacing = (W − natural) / (n − 1)`; n = 1 → one span with
  `letterSpacing = (W − natural) / k`, k = 1.5 at line start, 1.0 behind a
  quote run. `natural = spaces × a_space + tabs × a_tab`.
- `a_space` / `a_tab` come from a `TextPainter` over the indent style
  (`TextSpan(text: ' |')`, `getOffsetForCaret(TextPosition(offset: 1)).dx`,
  the same for `'\t|'`, `textDirection: ltr`, `layout()`, then `dispose()`),
  memoised once per `EditorRenderContext` generation as a derived,
  non-compared member (like `onAccent`), keyed by font style so a quote's
  italic content style gets its own pair. Measured in Flutter 3.44: space =
  tab = 0.2476 em.
- Alignment measured in the proposed render (glyph x by level, 1.0 / 1.3 /
  2.0): 20/40/60/80, 26/52/78/104, 40/80/120/160; a nested task box lands
  on the parent's content start within 1 dp; a nested number +3…+5 dp
  right of it; inside a quote each level is exactly +L from the quote's
  level-0 glyph.
- Tolerances for the design-reviewer: glyph x = level × L ± 0.5 dp for two,
  three and four spaces, a lone tab, `\t\t`, a quoted item and the money
  row, at every scale; the indent's shift between concealed and revealed is
  0.00 on every list line; `preferredLineHeight` stays 25.00 / 32.00 /
  50.00; wrapped lines start at the measured content x; the units suite is
  green with `_substitutions` not extended. A test lays the built span out
  with a `TextPainter` and asserts the caret x at `indent.length` at 16 and
  32 px — it also catches an engine change to the half-spacing quirk.
- Found beside the indent (not the designer's brief): `◦`/`▪` are not in
  the SDK's Roboto (D12 — device screenshot at 1.0, light and dark); the
  content start moves on caret entry because the dimmed `-` and the bold
  glyph differ in advance (D15, slice N3b); quote bars shift 0.36 dp on
  reveal (pre-existing, negligible, left alone).

### 3.4 The cap (N1, used by every indent path)

One pure function beside `EditorInputPolicy.listIndent`
(`EditorInputPolicy.indentCap(...)` or `MarkdownListUtils.nestingCap(...)`;
the implementer picks the home and gives it a table test):

- Input: a line reader `String lineAt(int)`, the line count, the item's
  index, and the optional `isFenceLine` predicate. Output: the maximum level
  the item at `index` may be indented to.
- Scan upward from `index - 1`: a blank line (whitespace only) is skipped; a
  line that parses as a list item at the same quote depth ends the scan with
  `cap = item.level + 1`; a non-blank, non-list line whose first character is
  whitespace is skipped (a continuation paragraph); a non-blank column-0
  non-list line, a fenced line, a line at a different quote depth, or the
  document start ends the scan with `cap = 0`.
- `EditorInputPolicy.listIndent` gains `int? maxLevel` (null = unbounded, so
  its table suite is unchanged): when the snapped result's
  `MarkdownListSyntax.indentLevel` exceeds `maxLevel`, the result is the
  line unchanged with `delta 0`. `ListIndentAction._tryListIndent` computes
  the cap from the controller's lines and passes it; the multi-line fallback
  to the fork's `applyIndent` is unchanged.

## 4. Behaviour

### Must not change

- Code-unit preservation: every list line's span still holds exactly the
  source line's UTF-16 units; `_substitutions` in the units suite is not
  extended (no new 1:1 substitution).
- Line height never changes with depth, reveal state or caret position.
- `MarkdownListSyntax.indentUnit` stays 2; `indentLevel` keeps tab = two
  columns; `bulletGlyph` keeps `•` `◦` `▪`; the one-list-regex rule holds.
- The grid snap of `EditorInputPolicy.listIndent` (`' - a'` → `'  - a'`), its
  tab outdent, and the fork's multi-line Tab fallback.
- Enter on an empty item (`emptyLineEnd`: outdent one level, end at top
  level, a quote's innermost `>`), Backspace after a marker
  (`MarkerBackspacePolicy`), the Enter continuation prefix, ordered lists not
  renumbered on Enter/Tab, ordered items never taking a task box.
- The tap interceptor's claim rules and every pass-through rule (ghosts win,
  reveal lines, fence lines), the selection handles' pan recognizer, the
  long-press selection, the desktop drag selection, the mobile selection
  toolbar's show/hide rules.
- The bar: Indent/Outdent ids, their default position and repeatable
  behaviour; `UtilityButtonConfig.decode`'s insertion rule.
- The hanging-indent contract of `CodeHangingTextSpan` (indent = the marker
  paragraph's advance floored; split rejected when the marker wraps).
- The IME resync after a controller-side rewrite, the typing undo grouping,
  `expandClosuresOnNewLine` false.
- No new `SettingsKeys`, no ARB change, no `SharedPreferences` key.

### Deliberately changes

- A Space with the caret at an empty list item's content start indents the
  item (D1) instead of typing a space; at the cap it is consumed.
- Tab and the bar's Indent no longer indent a single list line past the cap
  (D5); a first item in a note cannot be indented by Tab any more.
- Tab, Shift-Tab, the bar and the swipe on a quoted list item (`> - a`)
  nest or unnest the item after its `>` run; before, they fell through to
  the fork's plain indent, which padded or removed spaces at the caret
  mid-word. Shift-Tab on `> - a` at the remainder's column 0 is consumed
  with no change instead of reaching the fork's `applyOutdent`.
- A horizontal swipe on the focused editor's caret line, when that line is
  a list item, indents or outdents it (D2); before, a horizontal drag on the
  touch branch did nothing.
- The indent run of a list line is drawn wider than its literal spaces
  (D3), so nested items step visibly; the hanging indent of wrapped nested
  lines moves with it.

## 5. Facts from the tree (HEAD `6f4d7b2d`, re-grep before editing)

- `lib/utils/markdown_list_syntax.dart:90` `indentUnit = 2`; `:293`
  `bulletGlyph(level)`; `:308` `indentLevel` (tab = two columns); `:78-81`
  `MarkdownListItem.level`; `:94-98` the task and bullet regexes.
- `lib/utils/markdown_list_utils.dart:45` `isListLine`; `:65` `getListPrefix`;
  `:85` `continuationPrefix`; `:103` `emptyLineEnd` (`MarkdownOutdentItem` /
  `MarkdownEndMarker`).
- `lib/utils/editor_input_policy.dart:653` `listIndent` (grid snap, tab
  outdent, `EditorListIndent(text, delta)`); `:685` `_leadingSpaces`.
- `lib/controllers/list_indent_action.dart:8` `ListIndentAction.apply`
  (`:21`), `_tryListIndent` (`:39`, single-line path, `runRevocableOp` +
  `replaceLine`, caret kept on the same content character).
- `lib/utils/marker_backspace_policy.dart:27` `MarkerBackspacePolicy.apply`
  (list item first, then a quote; `_applyToItem` outdents a nested item
  through `listIndent(outdent: true)`).
- `lib/utils/list_aware_paste.dart:48` `deleteBackward`; `:63` `edit()`
  (`isSingleBackspace` → `_applyMarkerBackspace`, a `\n` commit →
  `_applyImePaste`); `:92-115` `_applyMarkerBackspace` (collapsed caret,
  fence check, `runRevocableOp`, `replaceLine`, IME resync).
- `packages/re_editor/lib/src/code_line.dart:437` `isSingleBackspace` (the
  delta shape reader to mirror for a single inserted unit).
- `lib/widgets/modern_editor_wrapper.dart:72` `hapticsEnabled`; `:857`
  `HapticFeedback.selectionClick()`; `:869` `lightImpact`; `:887`
  `CodeShortcutIndentIntent` override; `:901` `_onListIndent` →
  `ListIndentAction.apply`; `:1055` `wordWrap`; `:1069`
  `shortcutOverrideActions`; the `CodeEditor(...)` construction around
  `:1050-1075` is where `tapInterceptor` is passed and where the swipe
  handler goes.
- `lib/pages/optimized_note_editor_page.dart:2838-2839` the bar's
  `onIndent`/`onOutdent` → `_shiftListIndent`; `:3483` `ListIndentAction.apply`
  under the tracker guard; `:2962` `wordWrap: settings.wordWrap`.
- `lib/widgets/markdown_bar.dart:177-187` `_repeatableUtilityIds`; `:540-545`
  the indent/outdent cases. `lib/models/utility_button_config.dart:24-25`
  the ids, `:35-50` `defaultOrder`.
- `lib/utils/markdown_editor_span_builder.dart:1335` `_buildListItem`;
  `:1352-1353` the indent span (`TextSpan(text: item.indent, style: style)`);
  `:1358-1372` the bullet glyph span (primary, bold, upright); `:1500-1510`
  the `CodeHangingTextSpan(hangingChars: contentStart)` root; `:1607-1617`
  `taskMarkerRevealed`.
- `packages/re_editor/lib/src/_code_paragraph.dart:453` `_markerMeasurements`
  (keyed by the marker `TextSpan`); `:831-861` the hanging split (`trucate`,
  `_dropPrefix`); `:888` the measurement cache read.
- `packages/re_editor/lib/src/_code_selection.dart:9-28`
  `_CodeSelectionGestureDetector` (fields incl. `tapInterceptor`); `:96-160`
  the tap claim, `_withinHitSlop`, `_finishInterceptedTap`; `:185-235` the
  mobile `GestureDetector` branch (tap, long press — no horizontal drag);
  `:236-270` the desktop branch (`onHorizontalDragUpdate: _onDrag` is the
  selection drag); `:1533-1550` the selection handles' `PanGestureRecognizer`
  with `supportedDevices: {touch, stylus, unknown}`.
- `packages/re_editor/lib/src/code_editor.dart:202-212`
  `CodeEditorTapInterceptor`; `:285` / `:411` the `tapInterceptor` field;
  `:669` handed to the detector.
- `lib/constants/markdown_constants.dart:101` `indentPerLevel = 16.0` — the
  deprecated preview's nesting width, untouched.
- Tests that pin today's behaviour: `test/utils/editor_input_policy_test.dart`,
  `marker_backspace_policy_test.dart`, `markdown_list_utils_test.dart`,
  `markdown_list_syntax_test.dart`, `list_aware_paste_test.dart`,
  `markdown_editor_span_builder_units_test.dart` (`_substitutions` at
  `:2411`), `test/re_editor/tap_interceptor_test.dart` (+
  `support/editor_test_support.dart`), `tap_interceptor_desktop_test.dart`,
  `hanging_paragraph_test.dart`, `ime_edit_test.dart`,
  `test/widgets/modern_editor_wrapper_*_test.dart`.

## 6. Slices

| Slice | Files (owner of each) | Builds |
| --- | --- | --- |
| **N1 — Space + the cap** | `lib/utils/marker_space_policy.dart` (new), `lib/utils/editor_input_policy.dart`, `lib/controllers/list_indent_action.dart`, `lib/utils/list_aware_paste.dart`, `lib/utils/markdown_list_utils.dart` (only if the cap lives there), `packages/re_editor/lib/src/code_line.dart` (the single-insert shape reader only), their tests | §3.1 and §3.4 |
| **N2 — the swipe** | `packages/re_editor/lib/src/code_editor.dart`, `_code_selection.dart`, `re_editor.dart` exports, `lib/widgets/modern_editor_wrapper.dart`, `test/re_editor/line_swipe_test.dart` (new), `test/widgets/modern_editor_wrapper_swipe_test.dart` (new) | §3.2 |
| **N3 — visible depth** | `lib/utils/markdown_editor_span_builder.dart`, `lib/utils/markdown_editor_emitter.dart`, `lib/utils/markdown_editor_render_context.dart` (the advance memo), `lib/utils/markdown_editor_money_row.dart`, `lib/constants/markdown_constants.dart`, the units suite and a new geometry test, `hanging_paragraph_test.dart` only if a case is added | §3.3 (D9–D14) |
| **N3b — the revealed marker's advance** | the same files as N3, by the same implementer after N3 is green | D15: on a revealed list line the space after the raw marker is letter-spaced by (concealed glyph advance − dimmed dash advance), both measured through the N3 memo per glyph (`•` `◦` `▪`) and per generation, so the content x and the hanging indent are identical in both states; the geometry test asserts the content x of every list line concealed == revealed at 16 and 32 px |
| **N4 — gate, reviews, device pass, docs** | the lead: merge, gate, `reviewer` ×3 (one per slice, on the slice's diff), `design-reviewer` for N3, `qa-runner`, then `markdown-engine/references/live-editor-rendering.md`, `fork-and-hot-path.md`, `SKILL.md` rule lines, `docs/live-markdown-editor-roadmap.md` addendum, this record's §9 | §7 |

N1, N2 and N3 touch disjoint files and run in parallel worktrees. N2 reads
`ListIndentAction.apply` as it exists at HEAD; the cap lands through N1's
merge and needs no N2 change.

## 7. Definition of done

1. `- a`↵, Space, `b` gives `- a` / `  - b` with the caret after `b`; a
   second Space on the empty item before typing is a no-op when `a` is at
   level 0 (cap), and indents again when the item above is one level deeper.
2. Space on `- [ ] |` gives `  - [ ] |`; on `2. |` gives `  1. |`; on
   `> - |` gives `>   - |`; on `- item|` types a space; inside a fence types a
   space; mid-line types a space.
3. Backspace after the Space-indent returns the item to its previous column
   (the existing rule), and undo reverts the Space-indent in one step.
4. A right swipe on the focused caret line that is a list item indents it
   one level with a haptic; left outdents; a swipe on any other line, on a
   non-list line, on an unfocused editor, or with a mouse does nothing; a
   vertical flick scrolls; a long press still selects a word; the selection
   toolbar does not appear after a swipe.
5. Tab on a single list line stops at the cap; Shift-Tab is never capped;
   the bar's Indent and Tab agree on every line; a multi-line selection's
   Tab is the fork's own indent as before.
6. A nested item's glyph sits where the designer's spec says, identical in
   the concealed and the revealed state (no horizontal shift on caret
   entry), at 1.0, 1.3 and 2.0, light and dark; a wrapped nested line hangs
   under its content; the line height is unchanged (the line-height
   contract suite and the units suite green).
7. A four-level list shows `•` `◦` `▪` `•`; a tab-indented item sits at
   level 1; a four-space item at level 2 (F18 unchanged).
8. TalkBack: the bar's Indent/Outdent still carry their tooltips; the swipe
   adds no node and changes no announcement.
9. Device: the Space flow typed through `qa type`, the swipe through
   `qa swipe` on the caret line, screenshots at text scale 1.0 and 2.0 in
   dark and light, `qa errors` clean.
10. The gate on the merged tree: `dart analyze lib` clean, the whole suite
    green, no ARB touched.

**Results, 2026-11-08.** 1–3 pinned by `marker_space_policy_test.dart` (the
D1 flow and its undo through the IME channel, the cap, quoted Space, the
double-space period) and seen on the device (Enter, Space, `b` → `  - b`;
Enter, Space, `c` → `    - c`; Enter on the empty nested item steps out one
level per Enter). 4 pinned by `line_swipe_test.dart` and the wrapper's swipe
suite, seen on the device (left → `- b`, right → `  - b`, a first item and a
non-caret line do nothing; 48 logical px ≈ 126 device px on the Pixel 9 Pro).
5 pinned by `list_indent_action_test.dart` and the policy table. 6 pinned by
the geometry test (82 cases through the fork's layout at three sizes) and
measured by the design review; on the device the content of `  - b`,
`    - c`, `> - quoted` and `>   - quoted nested` stays put on caret entry.
7 seen on the device: `•` `◦` and the painted square, then `•`; the tab at
level 1, four spaces at level 2. 8: no node added, the bar's buttons
unchanged (the wrapper semantics suite green). 9: shots in
`build/qa/shots/20261108_14*`, `qa errors` clean twice. 10: analyze → the
two known fork infos; `+14866 ~16: All tests passed!`.

## 8. Deferred

- Per-level glyph styles beyond the three (a dash at level 4, a user
  choice of set) — Notion added a picker; not asked for.
- A multi-level drag (Keep's continuous drag) — one level per swipe is the
  decision (D2); a second swipe nests again.
- Renumbering an ordered sub-list on Tab/swipe — out of scope by the
  standing "never renumber" decision.
- F18 (four-space nesting as one level) — stays accepted (D8).
- `>\t- ` round trip: Space reads the quoted item through
  `MarkdownCalloutSyntax.quotedListItem` (the tab is the quote's separator,
  so Space gives `>\t  - `), while `MarkerBackspacePolicy` and `emptyLineEnd`
  read the remainder from the `>` run's `contentStart` and treat the tab as
  the item's indent (Backspace leaves `>  - `). Same level, different bytes.
  Intended fix: both older readers go through `quotedListItem`; files
  `lib/utils/marker_backspace_policy.dart:60`, `markdown_list_utils.dart`
  `emptyLineEnd`, with their table tests.
- A quoted line's content shifts 1.27 dp at 16 px on caret entry because
  `>` and `┃` differ in advance — quote-wide and pre-existing, not a list
  matter. Intended fix: the same `bulletGap` rule on the space after the
  quote run, in `_buildQuote…` of the span builder.
- **D14's fallback reads poorly at linear 2.0 for a level-3 task or a
  level-4 bullet** (design review, severity 2): the prefix (161 / 182 dp)
  exceeds the fork's half-viewport hanging limit (152 dp on 360), so the
  first row holds one word at 182 dp and every wrapped row runs from x = 0,
  reading as a paragraph. Why it is not fixed here: the fork's hanging
  layout is two paragraphs side by side (marker, content), so a capped hang
  (content rows at half the viewport) would need a first-row-aware layout
  — the first row's content must start after the real marker while later
  rows start at the cap — which the two-paragraph model cannot express;
  simply hanging at 182 dp would leave a 122 dp column (about six 32 px
  characters per row). Reach: depth ≥ 3 at the maximum text scale; D5
  keeps depth rare, and on Android's non-linear 200 % (28 px) a level-3
  task still hangs. Intended fix if the owner wants it: a `firstRowIndent`
  on `CodeHangingTextSpan` honoured by `_HangingParagraphImpl` (three
  paragraphs: first row, marker-free rest at the capped indent), measured
  for the hot path. Owner's call.
- The dimmed raw marker on a revealed line (`-` at `dimAlpha` 45 % over the
  caret-line ground) measures 2.80:1 in light, 3.70:1 dark — pre-existing,
  shared by every concealed-marker reveal (`**`, `#`), noted by the design
  review; a `dimAlpha` change is an editor-wide decision, not this
  rework's.
- A bulleted money row's text after the content start moves 9–19 dp on
  caret entry because the revealed `$` takes up space — the ledger's own
  conceal behaviour, not the list's.
- The fork extension `CodeLineEditingBackspaceShape` now also holds
  `isSingleInsert`; the name is left (a rename is churn across the fork's
  callers and the reference docs).

## 9. Ledger

- **2026-11-08** — record written by the lead (Fable 5.1) from the chat
  proposal the owner accepted ("okay, build it; you may use other agents;
  focus is quality"). N1, N2 dispatched to implementers in worktrees
  `anta-wt-nest-a` and `anta-wt-nest-b`; the designer dispatched for N3's
  spec; N3's implementer follows in `anta-wt-nest-c`.
- **2026-11-08** — the designer's spec landed (24 real-font renders, light
  and dark × 1.0 / 1.3 / 2.0 × concealed / revealed, `measure.json`): the
  current look measured at 7.92 dp per level, a tab at half a level, three
  spaces drifting between levels; the spec is §3.3, its defaults D9–D14. Two
  findings beside the brief: the `◦`/`▪` device face (D12) and the content
  jump on caret entry (D15 → N3b). N3 dispatched to `anta-wt-nest-c`.
- **2026-11-08** — N2 built in `anta-wt-nest-b` (6 files: the fork's
  `CodeEditorLineSwipeHandler`, `CodeEditor.lineSwipeDistance = 48.0`, the
  `lineSwipeHandler` parameter gated by `readOnly`, `_LineSwipeGestureRecognizer`
  with `isPointerAllowed` asking the handler, the mobile branch wrapped by
  `_withLineSwipe`; `lib/utils/line_swipe_policy.dart`; the wrapper's
  `_onLineSwipe`; 10 + 15 tests). Two as-built deviations: the recognizer
  uses `DragStartBehavior.down`, so the 48 px threshold counts travel from
  pointer-down (with `start` the slop would eat 18 px of every swipe); and a
  swipe on a quoted item is accepted but guarded to a no-op while
  `EditorInputPolicy.listIndent` returns null for quoted lines — a
  **pre-existing bug found here**: Tab and the bar's Indent on `> - a` fall
  back to the fork's `applyIndent` and pad spaces at the caret mid-word. N1
  was told to teach `listIndent` quoted items; after the merge N2's "a quoted
  item is never padded" test expects the nested line instead. Also noted: a
  slow swipe that starts on a checkbox zone drops the tap claim (as a drag
  always did) and nests the line; with word wrap off a sideways-scrolling
  line's scrollable wins the drag. Reviewer dispatched on the worktree.
- **2026-11-08** — N1 built in `anta-wt-nest-a` (11 files, 808+/14−):
  `isSingleInsert(newValue, unit)` beside `isSingleBackspace` in the fork's
  `code_line.dart`; `listIndent(maxLevel:)` and `EditorInputPolicy.listIndentCap`
  (§3.4); `MarkerSpacePolicy` (new file, 18 tests incl. two real IME-delta
  cases); the controller's `_applyMarkerSpace` between the Backspace and the
  `\n` checks, at the cap a `notifyListeners()` resync so the keyboard sees
  the unchanged line; `ListIndentAction` passes the cap on indent only.
  As-built deviations: the policy acts only when the unit before the caret
  is a space or tab, so `- [ ]|` + Space types the separating space (the
  grammar's content start is right after `]`) and the next Space nests; a
  bare `>` line counts as blank for the cap scan; the cap takes no line
  count; quoted items read through `MarkdownCalloutSyntax.quotedListItem`.
  Four existing tests that indented a first item got an item above (the cap
  forbids a first-item indent, §4). The quoted-`listIndent` addition
  (previous entry) reached the implementer after this report and was built
  as an addendum: `listIndent` accepts a quoted item (`> - a` → `>   - a`,
  the `>` run kept, the cap on the remainder's level, the old body in a
  private `_itemIndent` so unquoted lines are byte-identical),
  `EditorListIndent` gains an optional `start` (0 unquoted, so existing
  results compare equal), `ListIndentAction` leaves a caret inside the `>`
  run unmoved and clamps the rest to `[start, length]`; 11 files, 941+/25−;
  the listed suites green (+622, +244 ~1, +102, +134). Reviewer dispatched.
- **2026-11-08** — N3 built in `anta-wt-nest-c` (5 lib files + 1 new test,
  133+/10−): `MarkdownConstants.listIndentPerLevelEm = 1.25`;
  `EditorRenderContext.indentAdvances(FontStyle?)` (two `late final` pairs,
  upright and italic, outside `==`/`hashCode`); the static
  `EditorSpanEmitter.listIndent(...)` (level 0 untouched; n ≥ 2 first unit
  plain + the rest spaced; n = 1 divided by 1.5 at line start, 1.0 behind a
  quote run; adds `style.letterSpacing ?? 0`); `_buildListItem` and the
  money row's bulleted indent (the error row too) go through it in both
  reveal states. Geometry test with real Roboto (`test/goldens/support/
  golden_fonts.dart`): glyph x 20.0 at 16 px for two spaces, three spaces,
  a lone tab, `>   - b`, the nested money row and task; 40.0 for four spaces
  and `\t\t`; doubled at 32 px; concealed == revealed everywhere. Deviation
  accepted as D16 (the lone tab's caret). Units suite +434 with
  `_substitutions` untouched; hanging_paragraph +38; line_height_contract +5.
  N3b (D15) sent to the same implementer.
- **2026-11-08** — N2 review (one reviewer, read-only, 9 findings, nothing
  loses data): (1) PLAUSIBLE medium — a touch in the translucent padding of
  a selection handle's 48 dp target, over the caret line, is offered to both
  recognizers and the swipe accepts at the touch slop before the handle's
  pan (which needs twice that), so a handle drag indents the line instead
  of moving the caret → refuse a pointer-down within the handle targets
  while handles show; (2) CONFIRMED low-medium — `positionAt` maps any y
  below the last paragraph to the last line, so a swipe in the blank lower
  half of the editor nests a last-line item → require the pointer-down's y
  inside the line's paragraph; (3) word wrap off: the horizontal scrollable
  wins → documented, accepted; (4) the wrapper's guard duplicates
  `_tryListIndent`'s decision with the uncapped `listIndent` → give
  `ListIndentAction` a `tryApply` that never falls back to the fork and
  returns whether the line changed, shared by Tab and the swipe, the haptic
  driven by its result; (5) device set lacks `unknown` → add it; (6) the
  record's "since the drag was accepted" → "since pointer-down" (fixed in
  §3.2); (7) the `lineSwipeDistance` doc conflates the slop with the
  distance → reword; (8) test gaps: reset after a cancelled drag, haptics
  off, a second pointer, stylus, long press then move, a handle drag, below
  the last line, a diagonal swipe, the wrapper's fence predicate, one undo
  step, the desktop branch with a handler attached; (9) CRLF intact, new
  files LF (stored LF), the seven plugin registrants are pub-get noise.
  Verified OK: arena lifecycle against the SDK source, read-only gate, Tab
  parity, one `positionAt` per touch-down, no semantics node. Fix pass
  scheduled after the merge, when N1's `ListIndentAction` is in the tree.
- **2026-11-08** — N3b built (D15): `EditorRenderContext.listAdvances(FontStyle?)`
  replaces `indentAdvances` with an immutable `EditorListAdvances` (space,
  tab, the bold `glyph(level)` advance of `•` `◦` `▪`, the plain
  `marker(codeUnit, level)` advance of `-` `*` `+` `•`; upright and italic
  measured lazily once per context); `EditorSpanEmitter.bulletGap(...)`
  letter-spaces the run between the marker and the content in whichever
  state has the narrower marker (never negative); `_buildListItem`'s bullet
  branch and the money row's `_emitListMarker` (its error row too) use it.
  On the test machine the `◦` line's content moved −2.68 dp on reveal
  before and 0.00 after (the designer's −9 dp was the phone's fallback face;
  the rule measures at runtime, so the device gets its own advance). Left
  alone: a quoted line's `>` bars shift 1.27 dp at 16 px on reveal (`>` vs
  `┃`), pre-existing and quote-wide, not a list matter (§8). Cumulative N3 +
  N3b: 6 files, 588+/40−; geometry test +32. Then the three patches were
  applied to the main tree with `git apply --3way`, all clean, 23 files.
- **2026-11-08** — N1 review (one reviewer, read-only, no blocker, nothing
  on the must-not-change list moved): (1) PLAUSIBLE device-only — Gboard's
  double-space period: on a hand-typed `- [ ]`, `3)` or `+` item the first
  Space is typed (the rule needs a blank before the caret) and starts the
  countdown; the second arrives as "trailing space replaced by `. `", which
  `isSingleInsert` rejects, so the item gains `. ` instead of nesting (not
  the Enter-continuation flow, not `- `/`* `/`1. `) → recognise that shape
  when the policy would claim the original line; (2) CONFIRMED perf — the
  cap scan runs as an argument expression before the policy or `listIndent`
  can say no, so a double space in prose or Tab on a plain line scans
  upward → check the line first (controller side in the N1 fix pass, the
  action side in the N2 fix pass, which owns that file); (3) `>\t- ` Space
  then Backspace is not a byte round trip → deferred (§8); (4) the quoted
  Tab change was missing from §4 → added; (5) `_shiftListIndent` in the
  page calls `_onTextChanged()` unconditionally, so a capped Indent tap
  marks the note unsaved → call it only when the text changed; (6) tests
  missing: `isSingleInsert`'s shapes (composing before the commit, a
  selection replaced by a space, a two-unit commit, a space before the
  caret), the Enter → Space → type flow and undo through the channel, a
  quoted Space through the controller, cap cases (a heading above, a
  2-space first item under a paragraph, an item already deeper than its
  cap + Tab), Space at the end of a long multi-segment document, one
  event-host case; (7) nits: the extension's name (left, §8), the new files
  LF (stored LF), `['> - a', '', '> - ']` caps at 1 although CommonMark ends
  a quote at a blank line (noted). Verified OK: the delta shape is O(1) on
  a non-space key and rejects composing, replacement, multi-unit and
  off-caret inserts; the resync at the cap pushes the unchanged line with
  no composing range; the tracker never reads the +2 growth as an Enter; the
  policy and cap tables; `listIndent` byte-identical unquoted; the four
  fixture changes adapted, not weakened. Fix pass dispatched in `anta-wt-nest-a`
  with the merged state staged, so its export is the delta alone.
- **2026-11-08** — Design review of N3 + N3b (one design-reviewer, fresh
  context, the spec only; renders through the real span builder and the
  fork's paragraph provider at 304 dp, Roboto, light/dark × 1.0/1.3/2.0,
  concealed and revealed; `measure.json` and eight PNGs in the session
  scratchpad's `design-review-depth/`): **meets the spec** — glyph x =
  level × 1.25 em with 0.00 error in every case (20/40/60/80, 26/52/78/104,
  40/80/120/160); content x identical concealed/revealed on every bullet,
  task, ordered and money line; the indent never shifts; `preferredLineHeight`
  25.00/32.00/50.00 in every state; the wrapped level-1 bullet hangs at
  31/40/62 dp and follows the wider indent; the nested task box lands on
  the parent's content start; the glyphs 6.12:1 light / 10.91:1 dark on the
  editor ground. Findings: (1) severity 2 — the D14 fallback strands a
  level-3 task / level-4 bullet at linear 2.0 (first row one word at
  182 dp, wrapped rows from x = 0) → analysed and deferred (§8), owner's
  call; (2) severity 1 — a quoted list's content moves 1–2 dp on caret
  entry (`>` vs `┃`), already deferred; (3) severity 1 — the geometry test
  misses line height, wrapped-row starts, the 1.3 scale, task/ordered
  content-on-reveal and the lone tab through the fork → test follow-up sent
  to the N3 implementer; (4) D16 re-measured through the fork: the caret at
  0 draws at 0.00, the shift is a selection sliver → D16 reworded; (5) the
  dimmed raw `-` 2.80:1 in light, pre-existing → §8; (6) the money row's
  `$` conceal and the caret between marker and gap move, neither this
  slice's; (7) taste: a nested bullet sits 11 dp right of its parent's text,
  a task 0, a number 3 — follows D9; (8) `◦`/`▪`/`┃` render as tofu in the
  SDK's Roboto, so whether they read as a level is device-only (D12).
  Device bucket for the qa-runner: the four-level list at 1.0 light and
  dark; caret on `  - b` and `    - c` vs concealed; Android's maximum font
  size for the D14 lines; a pasted `\t- t` line selected whole; the caret on
  `>   - b`; TalkBack reading a nested line.
- **2026-11-08** — N3 test follow-up (test only, 67 cases, was 32): every
  case laid out through `CodeParagraphProviderForTesting` at 304 dp in
  Roboto at 16 / 20.8 / 32 px; `preferredLineHeight` one value per size
  across 14 list lines and the money row in both states ({25}, {32}, {50});
  glyph x 20/26/40 and 40/52/80; the lone tab's first run at ls/2
  (5.346 / 6.950 / 10.693) with the caret at 0.00; bullets' content x equal
  in both states (absolute and unfloored); nested task 40/52/81 and ordered
  37/49/75 equal in both states; the wrapped nested item's every row at the
  content x (31/40/62); the D14 fallback pinned (32 px: level-3 task first
  row at 161.5, level-4 bullet at 182.1, later rows at 0; 20.8 px: hanging
  at 104 / 118). The quoted line's 1.27 / 1.65 / 2.53 dp content move on
  caret entry is the quote run's (`┃` vs dimmed `>`), asserted around, not
  hidden (§8). Delta applied to the main tree.
- **2026-11-08** — N1 fix pass (8 files, in `anta-wt-nest-a`, copied into
  the main tree): `isDoubleSpacePeriod(newValue)` beside `isSingleInsert`
  in the fork's `code_line.dart` (the space before a collapsed caret
  replaced by `. `, no composing) routed to `_applyMarkerSpace`, so Gboard's
  double-space period on a hand-typed `- [ ] `, `3) ` or `+ ` nests the item
  and the `. ` never lands (pinned by a real replacement delta; whether
  Gboard sends one update or a Backspace + `. ` pair is device-only);
  `MarkerSpacePolicy.apply(line, caret, {int Function()? maxLevelOf})` —
  the cap is read only after the line is claimed (a counting `lineAt` reads
  0 lines for prose, an indented block, `- a `, `- [ ]`, a quoted line);
  the page's `_shiftListIndent` calls `_onTextChanged()` only when
  `codeLines` changed (a capped Indent leaves `hasChanges` false and
  schedules no save; the guard was removed once to see the test go red);
  tests: the two shape readers' cases (composing before/on the commit, a
  selection replaced, a two-unit commit, a space before the caret, a period
  elsewhere), the D1 flow through the channel (Enter → Space → `b`, two
  undo steps read from the pushed IME state), quoted Space through the
  controller and at the cap, a heading above, `intro` / `  - `, `intro` /
  `    - a` / `    - `, a 700-line document keeping its segments' identity,
  one event-description-sheet case. Suites: policy +30, input policy +347,
  paste +30, backspace +14, re_editor +258 ~1, wrapper +102, page +135,
  event sheet +28, event editor description +5, action +16.
- **2026-11-08** — N2 fix pass (8 files, in the main tree): the pointer
  gate refuses a touch inside a shown selection handle's 48 dp target
  (`_SelectionOverlayController.handleTargetContains`, the rect math shared
  with the handle's own `_handleRectOf` / `_handleInteractiveRectOf` so gate
  and handle cannot drift; always false on desktop) and a touch off the
  line's own paragraph (`_isOnLineParagraph`: top padding and the blank
  area under the last line); `PointerDeviceKind.unknown` joins the device
  set; the `lineSwipeDistance` and handler docs reworded (the slop owns the
  drag, the distance only fires; the two refusals; word wrap off);
  `ListIndentAction.tryApply` (never falls back to the fork, returns whether
  the line changed) over a private three-way `_listIndent` (not a list line
  / unchanged / changed) that `apply` shares, so Tab never sends a capped
  list line to the fork's padding indent; the cap is computed lazily (only
  for an indent on a list line, never for an outdent); `_onLineSwipe` calls
  `tryApply` and clicks only on true, the duplicated guard gone; fixtures:
  `- intro` / `- warm-up` / `  - squat`, a capped swipe pinned (no change,
  no haptic, no undo), the quoted case `> - intro` / `> - warm-up` →
  `>   - warm-up`; +9 fork cases (reset after cancel, second pointer,
  stylus, long press then move, handle drag, below the last line,
  diagonal), +5 wrapper cases (haptics off, fence predicate, one undo
  step…), +3 `tryApply` cases, +1 desktop case with a handler attached.
  Both refusals were disabled once to see their tests go red. Suites:
  re_editor +264 ~1, wrapper +122, action +19, page +134. Noticed, not
  this slice's: in widget tests a handle drag started in the handle's
  transparent margin fires `onStart` but never `onUpdate`/`onEnd`, so the
  100 ms auto-scroll poll keeps re-applying the start position — worth a
  device look at handle drags from that margin.
- **2026-11-08** — Gate on the merged tree: `dart analyze lib test
  packages/re_editor/lib` → only the fork's two pre-existing `avoid_print`
  infos; the whole `flutter test` → `+14850 ~16: All tests passed!`, exit 0
  (4 min 10 s). Docs placed: `markdown-engine/SKILL.md` (the list-nesting
  rule), `references/live-editor-rendering.md` and `fork-and-hot-path.md`
  (2026-11-08 paragraphs), `docs/live-markdown-editor-roadmap.md` (Done).
  Fixture `tool/qa/fixtures/list_nesting.json` (the "Depth" and "Capture"
  notes) for the device pass. Worktrees removed.
- **2026-11-08** — Device pass (qa-runner, `anta_qa_1` on emulator-5556,
  QA build from the uncommitted tree, seed `list_nesting.json`; shots in
  `build/qa/shots/20261108_14*`): **depth GREEN** — real glyphs, each level
  steps right, the wrapped item hangs under its content, 2.0 clean;
  **caret entry GREEN** on `  - b` and `    - c` (the text stays, the dot
  becomes a faint `-`), **RED on the quoted nested line** (about 4 dp of
  movement, the quote bars' advance → D18); **Space GREEN** — Enter, Space,
  `b` gives `  - b`, Enter, Space, `c` gives `    - c`, Enter on the empty
  nested item steps out one level per Enter; **swipe GREEN** — left on
  `  - b` gives `- b`, right restores it, a first item does not nest, a
  non-caret line does nothing; a 120-device-px swipe did not fire because
  48 logical px is about 126 device px on the Pixel 9 Pro (density 2.625) —
  the threshold works as designed, the brief's number was in the wrong
  unit; **`qa errors` clean.** Finding: the level-3 `▪` renders grey and
  about three dots wide in both themes — Android's emoji font (U+25AA is
  emoji-capable) → D17, a painted square. Also seen: the Capture seed's
  trailing newline parks a tap below the text on an empty line (the seed,
  not the app); the IME echo's leading zero-width space is the fork's known
  caret-line prefix.
- **2026-11-08** — N3c built in the main tree (D17 + D18, 7 files):
  `MarkdownConstants.bulletSquareSideEm = 0.28` / `bulletSquareCentreEm =
  0.264`; `EditorBulletSquareSpan` (const `CodeInlinePaintSpan`, alphabetic
  baseline, box 2 × 0.264 em tall so its centre is the x-height midpoint,
  advance = the bold `•`'s, `drawsLevel(level)` = `level % 3 == 2`) drawn by
  `_buildListItem` and the money row's `_emitListMarker` on a concealed
  level-2 bullet; `EditorListAdvances.glyph` returns the dot's advance for a
  square level (only `•` and `◦` are measured now); `EditorQuoteAdvances`
  (`bar`, `boldBar`, `marker`) behind `quoteAdvances(FontStyle?)`;
  `_emitQuoteBars(context, boldBars)` letter-spaces the gap after the last
  `>` in the narrower state (`>a`, `> >a`, `>\t- a` left as typed); the
  units suite's `_substitutions[0xFFFC]` allows `-*+•`; geometry test +82
  (the square at three sizes: content x 49/64/99 = a dot line's 9/12/19 plus
  two levels; quote content x identical concealed/revealed for `> - a`
  21/28/43, `>   - b` 43/56/86, `> plain text` 12/16/24, `> > deep`
  24/32/49 — with the spacing disabled 10 of 12 failed). Gate on the tree:
  analyze → the two known fork infos; the whole `flutter test` →
  `+14866 ~16: All tests passed!`, exit 0 (4 min 28 s). References updated
  (D17, D18). Device re-check dispatched.
- **2026-11-08** — Device re-check (same guest, rebuilt and reseeded): the
  level-3 square is purple, dot-sized and centred on the dot's axis in light,
  dark and dark 2.0, its text gap equal to a dot line's; `> - quoted` and
  `>   - quoted nested` keep their x on caret entry (66 and 96 shot px before
  and after); `    - c` keeps its x when the square becomes the faint `-`;
  `qa errors` clean. Shots `build/qa/shots/20261108_1444*` and `1445*`. The
  level-3 text moved left versus the first build because the emoji square's
  gutter is gone — the intended column. Status line set to IMPLEMENTED.
