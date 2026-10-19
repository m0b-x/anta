# Live editor — quality-of-life review (2026-10-19)

**Status: IMPLEMENTED 2026-10-19, uncommitted — E1–E33 built the same day
on the owner's "solve all of them" (E22 kept as is, E33 already held, E35 a
note; E34 and E36 left out, §5).** Eight implementer slices on disjoint files
(F1 fork engine, F2 tracker/reflow, T1 shortcut semantics, T2 bar chrome, R1
reveal/taps, then F3 fork polish, R2a page/settings, R2b wrapper/applier),
two read-only reviews (X fork/engine, 13 findings; Y app side, 20), two fix
passes (X 13/13; Y 14/15, the 15th's premise did not hold) — the as-built
deviations from §2's "recommended fix" column are in §7. The gate on the
final tree: `dart analyze lib test tool test_driver packages/re_editor/lib`
clean apart from the fork's two pre-existing `avoid_print` infos in
`debug/_trace.dart`; the whole `flutter test` `+8350 ~10 -1` (8077 before
the pass; the one failure the known Windows-only `host_devices_test`
"MacosDevice locate…"); `flutter gen-l10n` run, `untranslated.txt` `{}`;
the skill references and `docs/live-markdown-editor-roadmap.md` updated in
the same change; 39 files that `dart format` had turned LF restored to CRLF.
The device pass is the qa-runner's line at the end of §7. The owner reviews
and commits; the next session that opens this record corrects this line
from `git log`. The list itself (§2) was written earlier the same day from
three read-only reviews (keystrokes, paste/caret/scroll, rendering/chrome);
E3 was reproduced by a throwaway probe. §3's line numbers are from the tree
**before** the change — re-grep every one before editing.

Contents: §0 How to run this · §1 The ask and the baseline · §2 The list ·
§3 The findings in detail · §4 Works already · §5 Declined before, deferred ·
§6 Device pass · §7 Ledger.

## 0. How to run this

The implementing session runs on **Opus 5.5 at high**; it loads
`markdown-engine` (SKILL.md plus `references/live-editor-rendering.md` lines
45-50 and `references/fork-and-hot-path.md` line 45), `flutter-principles`,
`verify`, `delegation`, `l10n` for any bar string and `ui-language` for any
bar button or menu. It reads this record **by section**: the slice's rows of
§2, their entries in §3, and §0.1 whole. One `implementer` per slice (default
effort), one `reviewer` per slice briefed with §0.1 and the slice's §3
entries, one `qa-runner` for the device pass of §6 at the end. Never two
writers on `packages/re_editor/lib/src/_code_line.dart` or
`_code_input.dart` at once. Do not commit — the owner commits after each
slice's gate.

The gate after every slice (`verify`): `dart analyze lib test` clean, plus
`dart analyze packages/re_editor/lib` when the fork changed; the **whole**
`flutter test` green in one run (on Windows the known failure is
`test/qa/host_devices_test.dart` "MacosDevice locate…", never touch it; a
`sqlite3.dll` lock crash is transient, rerun); `flutter gen-l10n` and
`untranslated.txt` equal to `{}` whenever an ARB changed; §0.1 re-read
against `git diff`. Never run `flutter test` beside a QA `flutter run`.

Windows 11: wrapper `tool\qa\qa.cmd`, emulator `Pixel_9_Pro` (boot cold on
"Lost connection to device"), no `python`, never `perl -i`/`sed -i`, repo
files are CRLF.

### 0.1 Must not change

- **Code-unit preservation**: a rendered line holds exactly the source
  line's UTF-16 units; markers are concealed or substituted 1:1, never
  added or removed. Caret-line reveal may change conceal state only, never
  line height.
- **One grammar per syntax**: list, quote/callout, inline, link, tag, money,
  colour, ghost modules in `lib/utils/`; a Backspace or Enter rule reads
  `MarkdownListSyntax.parse(...).contentStart` and
  `MarkdownCalloutSyntax.quoteMarkers(...)`, never a new regex.
- **Single-line edits** are `CodeLines.replaceLine` / `removeLine`;
  programmatic inserts run under `EditorEditTracker.runGuarded`; seeding is
  `loadText`.
- **Undo contract**: the Enter and its list continuation are one node; a
  paste and its reflow are one node; caret-only changes fold into the
  current node (`test/re_editor/undo_baseline_test.dart`); the history cap
  stays 200.
- **The tracker's bounds**: `pastedLength` is the net growth; a paste over a
  selection under-covers its range (never a line before the true start);
  `"\n" + indent` reads as an Enter; Enter over a non-empty selection
  continues nothing. These are pinned, not bugs.
- **Tap policy**: zone rules only in `EditorInputPolicy`; ghosts win; a box
  tap is one atomic value change with the selection untouched; one claim
  live at a time.
- **Fork optimizations** listed in `references/fork-and-hot-path.md`; new
  `CodeLines` mutation paths call `cloneShallowDirty()`.
- **Owner decisions already taken** (2026-09-05): ordered lists are not
  renumbered on Enter/Tab (E36 reopens it only if the owner says so);
  ordered items take no task box; Enter right after a marker splits the
  item; the plain-text (live rendering OFF) path stays.
- Persisted settings and bar profiles keep their keys; new utility buttons
  are appended to stored `toolbar_utility_config` lists, never reorder an
  existing profile.

## 1. The ask and the baseline

### 1.1 The ask (owner, 2026-10-19)

Basic quality-of-life is missing from the markdown page: deleting the last
character of a bullet item leaves the bullet; after a paste the cursor is not
where it should be. The owner wants an Obsidian-like UI/UX review of the
live editor and a list of what to fix, to accept one item at a time.

### 1.2 The baseline

Obsidian 1.x live preview on a phone, with two corrections from the forums
(2026-10-19): Enter on an empty **nested** item outdents one level in the
built-in editor rather than exiting the list; Backspace removing a whole
list marker in one keystroke is the outliner convention (Notion, Bear, Apple
Notes) and, in Obsidian, the Smart List Input plugin — the owner's
expectation is taken as the bar, not Obsidian's stock behaviour. Obsidian
ships auto-pair of brackets and of markdown syntax on by default. ANTA's
own bar: capture one-handed in the middle of a set, no lost text, no layout
shifts, minimal taps.

### 1.3 How the reviews ran

Three `reviewer` agents (Opus 5.5, read-only, no test runs), briefed with
the baseline and disjoint file sets: A keystrokes (`editor_edit_tracker`,
list utils, the fork's key, delta and delete paths), B paste/selection/caret
/scroll (`list_aware_paste`, `paste_line_breaker`, the fork's `edit`,
`_replaceRange`, selection overlay, scroll helpers), C rendering and chrome
(span builder reveal, input policy, bar, settings, focus). The lead verified
by hand: E3 by probe (`abc\ndef`, selection (0,1)→(1,1), IME value
`aX\nY` → `aaX\nYef`; backward → `aX\nYefef`), E2's path in
`_code_selection.dart:168-199` and `:406-418`, E12's menu →
`applyHeader` route, E13's `_findDisplayRenderParagraph` overflow, E21's
`_shouldAutoQuoted`, and the three defaults of E16/E17/E20.

## 2. The list

Accept, skip or pick an option per row. "Size" is the implementer's
estimate: S under ~50 lines, M a focused slice, L a rework of its own.
"Source" is the reviewer finding the row consolidates (§1.3).

### 2.1 Tier 1 — the two complaints, and text safety

| ID | Source | What | Recommended fix | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| E1 | A1, A2 | Backspace right after a list, task, ordered or quote marker deletes one character at a time; a soft-keyboard Backspace also skips the fork's "delete both halves of a pair" and "delete an indent unit" rules | A: one keystroke removes the marker as one undo step; a **nested** item outdents one level first, the marker goes at top level; soft Backspace is routed through `deleteBackward()` so pairs and indent units go together · B: remove the marker outright at any depth | M | |
| E2 | B2 | Long-press on an empty line never moves the caret there, but the Paste toolbar still opens, so Paste lands at the old caret and the view jumps | Place the caret at the pressed position before the toolbar shows | S | |
| E3 | B1 | A keyboard (IME) multi-line paste over a selection spanning lines duplicates the start line's prefix (or, backward, the end line's suffix) — CONFIRMED by probe | Cut the replacement to the IME's own text in `edit()`'s multi-line branch; fork test | M | |
| E4 | B3, B7, B12 | After a toolbar or IME paste the scroll-to-caret measures the previous frame's layout; undo/redo never reveal the restored caret; the bar's Paste inserts while the editor is unfocused | Reveal post-frame (or `makeCenterIfInvisibleOnLayout`) on those paths; undo/redo reveal; bar Paste requests focus first | S | |
| E5 | C1 | The caret line is "revealed" (raw markers, taps pass through) even when the editor has no focus — a freshly opened note shows line 0 raw and its checkbox does nothing | Reveal only while the editor has focus; repaint on focus change; shared predicate for render and tap policy | S–M | |
| E6 | C2 | On the caret line a task's box is drawn raw and cannot be tapped — the item you just typed cannot be ticked without moving off the line | Keep the box painted and tappable on the caret line; reveal `- [ ]` only while the caret sits inside the marker | M | |

### 2.2 Tier 2 — list and quote editing completeness

| ID | Source | What | Recommended fix | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| E7 | A5 | Enter on a `> quote` or callout body line gives a bare line; an empty `> ` is never removed | Continue with `> ` (nested quotes keep their depth); Enter on an empty `> ` drops it like an empty list item; a callout lead is never "empty" | S–M | |
| E8 | A7 | Enter on an empty nested item jumps to column 0 | A: outdent one level per Enter, exit at top level (Obsidian) · B: keep | S | |
| E9 | A3, C6 | No way to indent or outdent a list item on a soft keyboard | Two utility buttons (indent, outdent) calling the wrapper's list-aware indent; ARB tooltips | S–M | |
| E10 | C7 | Bullet, numbered, task and quote bar buttons insert their marker at the caret, even mid-line, and stack on a second tap | Line-prefix toggles over the caret line or every selected line; second tap removes | M | |
| E11 | A9, B9, B8 | Bold/italic/strike never unwrap (`**x**` → `****x****`), the selection is dropped after wrapping, and with no selection only the opener `**` is inserted | Unwrap when the selection or its surroundings are already wrapped; keep the inner text selected; A: no selection inserts the pair with the caret between · B: keep the two-press `**` habit | M | |
| E12 | C5, B10 | The H menu ignores the level picked (H3 on plain text gives `# `), labels are hard-coded English, and applying a heading throws the caret to the line end | `applyHeaderLevel(level)`; ARB `header1…6`; `FormMenuChoiceItem`; caret column kept | S | |
| E13 | C4 | A tap below the last line lands on the last line at the finger's x — under a task line at the left it can toggle the box or open a tag search | Past the last paragraph: caret at the document end, no zone | S | |
| E14 | B14 | A list-aware paste whose text ends in a newline leaves the caret on a bare, unmarked line | Trim one trailing newline before the transform, or end on a marker | S | |
| E15 | A8 | Enter between auto-paired brackets (`[[|]]`, `{{|}}`, `- [|]`) inserts an indented block of three lines | Bracket expansion off outside fences | S | |

### 2.3 Tier 3 — defaults and settings

| ID | Source | What | Recommended fix | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| E16 | B4 | "Scroll caret on keyboard" defaults to off, so the rising keyboard hides the caret | A: default on · B: reveal on any viewport shrink regardless of the setting | S | |
| E17 | B5 | "Auto-break long lines" (default on) hard-wraps a paste **and** the pre-existing text of the caret line, moves the suffix to its own line without its space, and drops list markers on continuation pieces | A: keep the feature, reflow only the pasted span, never a list item, join the suffix · B: default off · C: remove | M | |
| E18 | A6, B6 | On the phone a whole line of typing is one undo node, while each hardware Backspace is its own; an IME multi-line paste merges into the typing node | Time-gap and insert/delete boundaries like CodeMirror; the IME paste in its own node | M | |
| E19 | C8 | A new note opens unfocused with the keyboard down (two taps before typing) | Focus the body after the first frame when `noteId == null` | S | |
| E20 | C9 | The global Haptic feedback setting is ignored by the editor's taps and the bar | Read it in the wrapper and the bar | S | |
| E21 | A4 | Typing `'` on the delta path pairs it (`don't'`); typed closers are skipped even when not auto-inserted | No pairing after a letter or digit; skip only an auto-inserted closer; probe on the device first (Gboard may send composing replacements, which do not pair) | S | |
| E22 | C10 | External links ask before opening; tags and wiki links navigate at once | A: keep (confirm only what leaves the app) · B: confirm none · C: confirm all | S | |
| E23 | C12 | Default bar order puts the checkbox 9th (off-screen on 360 dp) and ships two bullet buttons | New installs: checkbox, bullet, undo first; one bullet. Existing profiles untouched | S | |
| E24 | C13 | Headings barely separate from body text (h1 1.375, h2 1.125, h3 1.0625, h4 1.0 with w500 only) | A: raise the scales and give h4 a blend · B: keep | S | |
| E25 | C14 | Changing the font size does not keep the caret line in view | Post-frame centre on the caret after the size lands | S | |

### 2.4 Tier 4 — polish

| ID | Source | What | Recommended fix | Size | Answer |
| --- | --- | --- | --- | --- | --- |
| E26 | B13 | Selection toolbar: Paste shown with an empty clipboard; the toolbar hides on scroll and never returns; Select all re-shows with stale anchors | `Clipboard.hasStrings`; re-show on scroll end; fresh anchors | S | |
| E27 | C15 | Bar buttons have no ink or pressed state; default tooltips are English; the link prompt floats over the bar | `InkResponse`; ARB labels for the default IDs; `withToolbarOffset: true` | S | |
| E28 | C11 | The suggestion bar replaces the whole bar (undo gone) and may change height at large text scales | Pin label scaling; keep undo | S | |
| E29 | A10 | Typing `*`, `_`, `~`, `=` over a selection replaces it instead of wrapping it | Extend the fork's wrap symbols | S | |
| E30 | A11 | Windows: Ctrl+arrows jump to line ends, no Ctrl+B/I, Ctrl+Backspace double-bound | App `shortcutsActivatorsBuilder` | S | |
| E31 | A12 | With live rendering off, Tab on a list line inside a fence runs the list indent | Pass the fence predicate unconditionally | S | |
| E32 | B11 | IME paste skips the list-aware transform; Ctrl+V on an Android hardware keyboard is not wired | Apply the transform in `edit()`'s multi-line branch; map Ctrl/Meta+V in the mobile key handler | M | |
| E33 | B15 | The "lines formatted" snackbar can cover the pasted caret | Offset above the bar | S | |
| E34 | C3 | The whole caret line reveals at once: text shifts sideways, a concealed URL unfolds, a wrapped row can appear | Per-token reveal (only the construct the caret touches) | L | |
| E35 | A13 | Enter rebuilds the marker with one space (`-   a` → `- `) | Note only; negligible | — | |
| E36 | — | Ordered lists are not renumbered when an item is inserted mid-list (declined 2026-09-05) | Reopen only on the owner's word: renumber the following siblings on Enter | M | |

### 2.5 Proposed slices once the answers are in

- **Slice 1 — the complaints**: E1, E2, E3, E4. Touches the fork
  (`_code_line.dart`, `_code_selection.dart`), `ListAwarePasteController`,
  a new `EditorInputPolicy.markerBackspace`. One implementer, one reviewer.
- **Slice 2 — reveal and taps**: E5, E6, E13. Span builder, input policy,
  wrapper, the fork's position lookup.
- **Slice 3 — lists and quotes**: E7, E8, E9, E10, E14, E15. Tracker, list
  utils, bar, page handlers, ARBs.
- **Slice 4 — formatting shortcuts**: E11, E12. `ShortcutApplier`, bar
  menu, ARBs.
- **Slice 5 — defaults and settings**: E16, E17, E18, E19, E20, E25.
- **Slice 6 — polish**: whatever of E21–E33 is accepted.
- One device pass (§6) after slice 3 and one after the last slice.

## 3. The findings in detail

Each entry: Now (with `file:line`, CONFIRMED or PLAUSIBLE), Baseline,
Fix, Tests to change, invariants touched.

### E1 — Backspace after a marker (A1 + A2)

**Now.** Nothing in ANTA interprets a deletion: `EditorEditTracker.onTextChanged`
returns at `lib/controllers/editor_edit_tracker.dart:131` on
`textLengthDiff <= 0`, and no test calls `deleteBackward`. `- |` →
Backspace → `-` (plain text under `MarkdownListSyntax`'s
`^(\s*)([-*+•])\s+`, `lib/utils/markdown_list_syntax.dart:82`); clearing a
task takes six keystrokes and passes through `- [ ` (a bullet whose text is
`[ `); `> |` → `>` stays a quote line. CONFIRMED.

How a soft-keyboard Backspace arrives on Android: the IME connection runs
with `enableDeltaModel: true` (`packages/re_editor/lib/src/_code_input.dart:457`)
and sees only the caret line behind a zero-width space (`:496-505`, `:699`).
A Backspace away from column 0 is a delta batch →
`_controller.edit(newValue.removePrefixIfNecessary())` (`:182`) → the
editor's `edit()` (`_code_line.dart:217`), which rewrites the line; only at
column 0, where the IME deletes the zero-width space, does it become
`deleteBackward()` (`:178-180`). Hardware Backspace and desktop go to
`deleteBackward()` (`code_editor.dart:655-661`). Both paths notify
synchronously, so the tracker sees the shrink but cannot classify it (it
keeps no pre-edit line: `- a|`→`- |` and `-  |`→`- |` are the same −1; a
selection delete and a Gboard composing rewrite look the same). The two
rules that live only in `deleteBackward()` — delete both halves of a pair
(`_isWrapedByClosureSymbol`, `_code_line.dart:1305`) and delete a whole
indent unit (`_isMultipleIndent`, `:1318`) — therefore never run for a
soft-keyboard Backspace: with auto-pair on (`code_editor.dart:430`,
`autocompleteSymbols ?? true`), typing `(` then Backspace on the phone
leaves `)`. CONFIRMED by reading; PLAUSIBLE for Gboard specifically.

**Fix (M).** A pure rule `EditorInputPolicy.markerBackspace(line, caret)`
over `MarkdownListSyntax.parse(...).contentStart` and
`MarkdownCalloutSyntax.quoteMarkers(...).contentStart`: when the collapsed
caret sits exactly at `contentStart` (content may follow), the result is
the line with the marker removed — for a nested item, the line outdented
one level (`EditorInputPolicy.listIndent(outdent: true)`), the marker only
at top level (option A) — or the bare content (option B). Apply it in the
app's controller (`ListAwarePasteController`, `lib/utils/list_aware_paste.dart`,
already the delegate every edit is forwarded to, `code_editor.dart:418-420`,
and already holding `isFenceLine`): override `deleteBackward()` to run the
rule inside `runRevocableOp` with `replaceLine`; in `edit()`, when the
change is exactly one code unit removed just before a collapsed caret on the
same line, route to `deleteBackward()` and clear the composing range — that
one routing also restores the pair and indent-unit rules on the phone (A2).
Skip fenced lines. The rewrite runs before any listener, so the tracker's
guard is untouched; undo: one node.

**Tests.** New rows in `test/utils/editor_input_policy_test.dart`; a delegate
suite for `ListAwarePasteController.deleteBackward`/`edit`; widget tests
must send `updateEditingStateWithDeltas` over the text-input channel
(`updateEditingValue` is a no-op, `_code_input.dart:192`). No existing test
changes. The fix also reaches the two event-description editors (same
controller).

### E2 — Long-press on an empty line (B2)

**Now.** `onLongPressStart` (`packages/re_editor/lib/src/_code_selection.dart:168-180`)
calls `_onMobileLongPressedStart`, which returns early when `selectWord` is
null (`:406-410`); `_selectWord` returns null for any collapsed word range
(`_code_field.dart:1807-1813`), and an empty line always gives one. The
caret never moves; `onLongPressEnd` (`:186-195`) still shows the toolbar,
anchored to the old caret or to the finger when that caret is off screen.
Paste then inserts at the old position and the view jumps there. CONFIRMED
by the lead's read. Most likely the owner's "cursor not where it should be".

**Fix (S).** On a null or collapsed word, `_selectPosition(position, tapUp)`
before the toolbar shows. Test: a new case in `test/re_editor/` with a
long-press on an empty line asserting the caret index.

### E3 — IME multi-line paste over a multi-line selection (B1)

**Now.** The IME sees only the base line (`_code_input.dart:484-505`:
selection base→line end forward, 0→base backward). `edit()`'s multi-line
branch (`_code_line.dart:218-231`) keeps `newValue.text` whole when it does
not end with the end line's suffix (forward) or start with the start line's
prefix (backward), and `_replaceRange` (`:1751-1752`) re-adds that prefix
or suffix. Probe (lead, 2026-10-19): `abc\ndef`, selection (0,1)→(1,1), IME
value `aX\nY` → `aaX\nYef` (correct: `aX\nYef`); backward with `X\nYef` →
`aX\nYefef`. CONFIRMED.

**Fix (M).** In the multi-line branch, when `!selection.isSameLine`, the
replacement is `newValue.text.substring(beforeText.length)` forward and
`newValue.text` minus the base line's suffix backward; nothing else in
`_replaceRange`. Fork test for both directions (none covers `edit()`).

### E4 — Caret reveal after paste, undo, bar Paste (B3 + B7 + B12)

**Now.** `_replaceRange` calls `makeCursorCenterIfInvisible` synchronously
(`_code_line.dart:1775`) before relayout, reading the previous frame's
`_displayParagraphs`; when the old paragraph at the new caret index is empty
(`getOffset` → `Offset.zero`, `_code_paragraph.dart:205-206`) or long, it
reports "visible" and no retry runs (`_code_field.dart:1116-1129`) —
PLAUSIBLE. Toolbar and ghost inserts already reveal post-frame (page
`:2480`, `:2500`, `:2568`); the bar's Paste (`optimized_note_editor_page.dart:2038`)
and the IME path do not. `_CodeLineEditingCache.undo/redo` only set the
value (`:1979-1991`); `TextHistoryObserver.undo` (`:68`) adds nothing —
CONFIRMED. The bar's Paste runs while the editor is unfocused: insert at a
stale caret, no caret painted, view jumps — PLAUSIBLE.

**Fix (S).** Post-frame reveal (or `CodeScrollController.makeCenterIfInvisibleOnLayout`)
after the delegate's `paste()`, the IME multi-line branch and undo/redo;
`_contentFocusNode.requestFocus()` before the bar's `paste()`. Widget test
beside `test/re_editor/scroll_to_position_test.dart`.

### E5 — Reveal without focus (C1)

**Now.** `selectionCoversLine` (`lib/utils/markdown_editor_span_builder.dart:1107`,
used at `:247`) reads the selection alone; no `hasFocus` anywhere in the
span builder, `EditorRenderController` or the wrapper. A note with no saved
position opens at 0:0 (`test/widgets/optimized_note_editor_page_test.dart:579`),
so line 0 renders raw and `resolveTap` returns null on a revealed line
(`lib/utils/editor_input_policy.dart:177`; `zonesOf` `:313`): a tap on
line 0's box places the caret and raises the keyboard. The same for the
line a restored position lands on. CONFIRMED.

**Fix (S–M).** `reveal = hasFocus && selectionCoversLine(...)`, threaded
from the page's `_contentFocusNode` through the render controller into the
builder and the policy's `lineRevealed`; a repaint on focus change (the
reveal lines bypass the memo already). Tests: the policy table, the tag and
wiki tap suites, a page test "unfocused editor conceals the caret line".
Invariant: one reveal predicate for render and taps.

### E6 — The box on the caret line (C2)

**Now.** On the caret line `- [ ]` is drawn raw and dimmed and the box zone
is gone: `test/utils/editor_input_policy_test.dart:688-689` pins
`zonesFor('- [ ] …', revealed: true)` → empty. Typing `- [ ] squat 5x5`
then tapping the box gives a caret, not a tick. CONFIRMED.

**Fix (M).** In `_buildListItem` (span builder ~975-1010) keep the painted
`EditorCheckboxSpan` unless the caret offset lies in `[indent, contentStart]`;
`resolveTap`/`zonesOf` keep the box zone under the same rule. Tests: the
policy table, the units suite's `_substitutions` table,
`test/widgets/modern_editor_wrapper_toggle_test.dart`. Invariants:
code-unit preservation, 1:1 substitution, line height, ghosts win.

### E7 — Enter on quotes and callouts (A5)

**Now.** `_handleNewLine` asks only `MarkdownListUtils.getListPrefix`
(`editor_edit_tracker.dart:216-219`), null for `>` lines, so `> a`↵ gives a
bare line and the callout block ends there; an empty `> ` is never removed;
`> - a` continues nothing. CONFIRMED.

**Fix (S plain, M for `> - a`).** Fall back to
`MarkdownCalloutSyntax.quoteMarkers(prevLine)` for the prefix (the `>`
run up to `contentStart`, then the list prefix of the remainder if any);
Enter on an empty quote line drops it like an empty list item; a callout
lead line (`> [!TIP]`) is never "empty". Keep the growth check;
`replaceLine`/`removeLine`. New cases beside "a plain line gets no prefix"
in `test/controllers/editor_edit_tracker_test.dart`.

### E8 — Enter on an empty nested item (A7)

**Now.** `'  - '`↵ → `''` at column 0, pinned by "Enter on a nested empty
item drops it back to column 0" and "dropping the nested empty item is one
undo step". CONFIRMED.

**Fix (S, option A).** In the empty-item branch, when the item's level is
above 0, rewrite the line with `EditorInputPolicy.listIndent(outdent: true)`
instead of removing it. Those two tests change.

### E9 — Indent and outdent on a soft keyboard (A3 + C6)

**Now.** List indent exists only as the Tab intent (`code_editor.dart:669-704`,
wrapper `_tryListIndent` `lib/widgets/modern_editor_wrapper.dart:668`).
`UtilityButtonId.defaultOrder` (`lib/models/utility_button_config.dart:27-40`)
and the default shortcuts have no indent, outdent or caret-move button.
CONFIRMED.

**Fix (S–M).** Two `UtilityButtonId`s calling `_onListIndent` through the
page; ARB tooltips (en/de/ro); append to stored utility lists when missing.
Tests: `test/widgets/markdown_bar_chrome_test.dart`, a page test.

### E10 — Line-prefix toggles (C7)

**Now.** Checkbox, bullet, numbered and quote shortcuts insert their text at
the caret (`optimized_note_editor_page.dart:2554` `replaceSelection(text)`),
mid-line included; a second tap stacks a second prefix. CONFIRMED.

**Fix (M).** A `linePrefix` insert type in `ShortcutApplier` that toggles
the prefix at the start of the caret line, or of every line in the
selection, through `MarkdownListSyntax` (bullet ↔ task ↔ numbered swap the
marker rather than stacking). Persisted custom shortcuts keep their
behaviour unless they carry the new type. Tests: `shortcut_applier_test`,
the page's shortcut group.

### E11 — Wrap toggles and the empty-selection pair (A9 + B9 + B8)

**Now.** `ShortcutApplier.resolve` with an empty selection returns only
`before` (`lib/controllers/shortcut_applier.dart:94-104`, test `:54`
expects `'**'`, the source calls it "historical behavior"); with a
selection it always wraps (`'**sel**'`, test `:58-78`) and collapses the
caret after the closer; no unwrap exists. CONFIRMED.

**Fix (M).** Unwrap when the selection is `**x**` or sits inside a wrapped
run; keep the inner text selected inside the same revocable op; option A
inserts `before + after` with the caret between (as `insertGhost` does).
Tests `:41-78` change.

### E12 — The heading menu (C5 + B10)

**Now.** `_showHeaderMenu` (`lib/widgets/markdown_bar.dart:368-416`) hands
the picked shortcut to `onShortcutPressed`; `resolve` returns null for
`insertType: 'header'` and the page runs `ShortcutApplier.applyHeader`
(`optimized_note_editor_page.dart:2551-2553`), which cycles one level
regardless of the pick (H3 on plain text → `# `). Labels are
`Text('Header $level')` (`:407`) though `header1…header6` ARB keys exist;
the menu is `showMenu`/`PopupMenuItem`, not `FormMenuChoiceItem`.
`applyHeader` is `selectLine` + `replaceSelection` (`shortcut_applier.dart:278-279`),
so the caret lands at the line end and a multi-line selection is lost.
CONFIRMED (lead's read).

**Fix (S).** `ShortcutApplier.applyHeaderLevel(controller, level)` with
`replaceLine` and the caret column restored (`offset + delta`); the bar
button's own tap keeps cycling; ARB labels; the language's menu idiom.
Tests: an H3 case in the page group; `shortcut_applier_test:137-140`.

### E13 — Tap below the last line (C4)

**Now.** `_findDisplayRenderParagraph(offset, canOverflow: true)`
(`_code_field.dart:1817-1847`) returns `list.last` for any dy past the
bottom, so `positionAt` resolves to the last line at the finger's x; the
interceptor uses the same position (`_code_selection.dart:99`). Under a
last task line at the left edge the tap can toggle the box; under a tag it
can open search. Mechanism CONFIRMED (lead's read); the user-facing
consequence PLAUSIBLE until a device check.

**Fix (S).** When dy is past the last paragraph's bottom: caret at the
document end and no interception. Test in
`test/re_editor/tap_interceptor_test.dart`.

### E14 — List paste ending in a newline (B14)

**Now.** Pasting `a\nb\n` into `- x|` gives `a`, `- b`, and a bare third
line with the caret at column 0 (`lib/utils/list_aware_paste.dart:105-111`).
CONFIRMED.

**Fix (S).** Trim one trailing newline before transforming, or end on a
marker line. `test/utils/list_aware_paste_test.dart` changes.

### E15 — Enter between brackets (A8)

**Now.** `_selectionInClosure` (`_code_line.dart:1914-1940`) matches
`{}`/`[]`/`()` around the caret and `_applyNewLine` (`:1502`) inserts an
extra indented line — three lines from one Enter inside `[[|]]`, `{{|}}`
or `- [|]`, all normal states right after an auto-paired opener. CONFIRMED.

**Fix (S, fork).** An option to disable bracket expansion outside fences;
the wrapper sets it. New fork test.

### E16 — Scroll caret on keyboard (B4)

**Now.** `defaultScrollCursorOnKeyboard = false`
(`lib/constants/settings_keys.dart:412`); the only reveal on keyboard rise
is gated on it (page `:557-567`); the fork has no metrics observer; the
body shrinks by the inset (page `:1871`), so a tap in the lower half or the
centred restore plus `requestFocus` (`:1650-1657`) leaves the caret behind
the keyboard. CONFIRMED.

**Fix (S).** Default true (not pinned by `editor_settings_test.dart`), or
reveal on any viewport shrink in the render's `performLayout`.

### E17 — Auto-break long lines (B5)

**Now.** `defaultAutoBreakLongLines = true` (`settings_keys.dart:410`); any
growth over 20 units is a paste (`editor_edit_tracker.dart:140`).
`test/utils/paste_line_breaker_test.dart:311-341` expects the caret line's
own suffix ` tail` to move to its own line without its space; list items
are not line-led (`:245-247`), so continuation pieces lose their marker; a
snackbar follows. CONFIRMED. PLAUSIBLE: a Gboard voice commit can count as
a paste.

**Fix (M, option A).** Reflow only the pasted span; never break a list
item (or give continuation pieces the item's indentation); join the suffix
to the last piece. Tests `:311-341` and `editor_edit_tracker_test:107-200`.

### E18 — Undo granularity (A6 + B6)

**Now.** `edit()` starts a new undo record only when the edited line
changes (`_code_line.dart:278-289`), otherwise it overwrites the last one
(`_onValueChanged` `:2007`); hardware Backspace runs through
`runRevocableOp` (`:863`, `:1114`), one record per press. The IME
multi-line branch calls `_replaceRange` with no `runRevocableOp` (`:231`),
merging the paste into the typing node; typing on the same line after any
toolbar paste or shortcut merges into that op's node because
`_preEditLineIndex` (`:278`) is unchanged. CONFIRMED.

**Fix (M, fork).** New record after a time gap (~500 ms) or an
insert/delete switch; wrap the multi-line branch; reset
`_preEditLineIndex = -1` in `runRevocableOp`. Keep the caret-only folding
(`undo_baseline_test.dart`); pin the new grouping there.

### E19 — New note focus (C8)

**Now.** `autofocus: false` (`modern_editor_wrapper.dart:808`); the page's
only `requestFocus` calls are the preview handoffs (`:1468`, `:1657`); the
title is edited through the app-bar dialog. From the list: new note, tap
the body, type. CONFIRMED.

**Fix (S).** When `noteId == null`, request content focus after the first
frame (the mount gate). Page test asserting `hasFocus`.

### E20 — Haptics (C9)

**Now.** `SettingsKeys.hapticFeedback` (default true, `settings_keys.dart:402`)
is read by the search bar, the match sheet and the calendar appearance page
only; the wrapper fires `selectionClick`/`lightImpact` unconditionally
(`modern_editor_wrapper.dart:596-623`), as does the bar's reorder mode
(`markdown_bar.dart:118-138`). CONFIRMED.

**Fix (S).** Read it through the editor settings bundle in the wrapper and
the bar. Wrapper tests with haptics off.

### E21 — Quote auto-pair (A4)

**Now.** `_quoteSymbols = ['\'', '"', '`']` (`_code_input.dart:515`);
`_shouldAutoQuoted` (`:642`) returns true when no quote exists on either
side, so an insertion delta of `'` after `don` becomes `don''`; typing `"`
inside `"|"` gives `""|""`; `_shouldSkipClosed` skips `)]}` whether or not
they were auto-inserted. Rule CONFIRMED; whether Gboard delivers a mid-word
apostrophe as an insertion delta (pairs) or a composing replacement
(`_smartReplacement` returns multi-character replacements unchanged, no
pairing) is a device question.

**Fix (S, fork).** No pairing after a letter or digit; skip over a closer
only when it was auto-inserted; optionally drop `'`. Device probe first:
type `don't` and `(` + Backspace on Gboard.

### E22 — Tap consistency (C10)

**Now.** Editor link taps show a confirm snackbar
(`_handleEditorLinkTap`, page `:1353-1365`, "mid-workout taps can land on
it by accident"); tag taps push search at once (`:1482-1487`); wiki links
push the note. CONFIRMED. A defensible split (confirm only what leaves the
app); listed for the owner's call.

### E23 — Default bar order (C12)

**Now.** `lib/config/default_markdown_shortcuts.dart`: bold, italic, H,
point list, strike, highlight, bullet list, numbered list, checkbox…; the
split is on at 0.7, so about five shortcut and two utility buttons fit on
360 dp (PLAUSIBLE arithmetic); two bullet buttons (`• `, `- `) ship by
default. Order CONFIRMED.

**Fix (S).** New installs only.

### E24 — Heading scale (C13)

**Now.** h1 1.375, h2 1.125, h3 1.0625, h4 1.0 with w500 and no blend
(`test/utils/markdown_heading_scale_test.dart` pins them). Obsidian's
default theme is about 1.8/1.6/1.4/1.27/1.13 em on desktop. CONFIRMED.

**Fix (S).** A design pick in `MarkdownConstants`; the line-height
calculator reads the same constants, so line heights follow.

### E25 — Font size and the caret (C14)

**Now.** `_adjustFontSize` (page `:656-663`) only writes the setting.
PLAUSIBLE. **Fix (S).** Post-frame `makeCenterIfInvisible(selection.extent)`.

### E26 — Selection toolbar polish (B13)

**Now.** Paste shown with an empty clipboard (wrapper `:410-416`); the
toolbar hides on scroll start and never returns (`_code_editable.dart:286-289`);
Select all re-shows with the old anchors (`_code_selection.dart:1476-1484`).
CONFIRMED.

### E27 — Bar feedback and localization (C15)

**Now.** Shortcut and utility buttons are bare `GestureDetector`s
(`markdown_bar.dart:975`, `:1050`); default tooltips use `shortcut.label`
(English, `:973`); the link prompt uses `withToolbarOffset: false`
(`lib/utils/custom_snackbar.dart:53`). CONFIRMED. Gate: all three ARBs.

### E28 — Suggestion bar (C11)

**Now.** `MarkdownBar` renders `VocabularySuggestionBar` instead of normal
mode during a session (`markdown_bar.dart:163-177`), heights match at 40 px
at 1.0 scale; B/I/H labels scale with text size, the pills do not
(`vocabulary_suggestion_bar.dart`). Replacement CONFIRMED; the shift
PLAUSIBLE.

### E29 — Markdown-symbol wrapping (A10)

**Now.** `_wrapSymbols` (`_code_input.dart:517`) covers `{[('"` and the
backtick only. CONFIRMED. **Fix (S).** Add `*`, `_`, `~`, `=` for notes.

### E30 — Windows shortcuts (A11)

**Now.** `code_shortcuts.dart`: Ctrl+←/→ are line start/end, word jumps on
Alt; Ctrl+Backspace bound to both line- and word-delete (PLAUSIBLE that
word-delete wins); no Ctrl+B/I in `lib/`. CONFIRMED.

### E31 — Fence predicate without live rendering (A12)

**Now.** `isFenceLine: markdownRendering ? _render.lineInFence : null`
(page `:2167`), while the tracker and the paste controller always get it
(`:348`, `:319`). CONFIRMED. **Fix (S).** Pass it unconditionally.

### E32 — IME paste and Ctrl+V on Android (B11)

**Now.** The IME path is `edit()` → `_replaceRange`, no list-aware
transform (`list_aware_paste.dart:26-28`); Android/iOS build no
`Shortcuts` (`code_editor.dart:638-705`), so Ctrl+V on a hardware keyboard
never reaches the delegate (whether it pastes at all: unsure). CONFIRMED.

### E33 — The reflow snackbar (B15)

**Now.** Page `:820-827`. PLAUSIBLE, low.

### E34 — Per-token reveal (C3)

**Now.** `markerStyle = reveal ? dimStyle : concealStyle`
(`lib/utils/markdown_editor_inline_emitter.dart:85`) for every marker on
the caret line; a concealed URL unfolds; the roadmap admits the reflow
(`docs/live-markdown-editor-roadmap.md:566`, `:405-408`). With word wrap
the extra width can add a visual row. Mechanism CONFIRMED; shift sizes
PLAUSIBLE. **Fix (L).** Pass the caret offset into
`EditorInlineEmitter.append` and reveal only the token containing or
touching it. Deferred unless the owner wants it (§5).

### E35, E36

E35: `getListPrefix` rebuilds the marker with one space
(`markdown_list_utils.dart:40-45`). E36: see §0.1 and §5.

## 4. Works already (no spend needed)

- Enter at the end of a bullet, ordered or task item continues it (same
  marker, next number, unchecked box, same depth); Enter on an empty
  top-level item removes the marker as one undo step; Enter mid-item
  splits; Enter at column 0 inserts a plain line; Enter in a fence is a
  plain newline with the indentation copied; Enter on a heading is plain.
- Soft and hardware Enter take the same path (`_code_input.dart:110-115`,
  `:143-151` → `applyNewLine`).
- Hardware Tab/Shift-Tab move the whole item, keep the caret, snap to the
  grid, also with a multi-line selection and on a physical keyboard on
  Android.
- Brackets auto-pair, skip over their closer and wrap a selection; hardware
  Backspace deletes both halves of a pair.
- The caret is collapsed at the end of the pasted text on every path
  (`_replaceRange` `:1757`/`:1764`); the reflow maps it past the paste, not
  past the suffix; delegate paths replace exactly the selection; plain text
  only; `\r` normalised twice; paste plus reflow is one undo step and the
  pre-paste caret is restored.
- Long-press or double-tap on a word selects it with handles and
  Cut/Copy/Paste/Select all; handle drag extends; toolbar anchors follow the
  selection; toolbar and ghost inserts reveal the caret post-frame.
- The bar sits at the bottom and rides the keyboard; undo/redo are buttons;
  one shortcut tap is one undo step.
- Live conceal preserves code units; box toggles keep the selection, are one
  undoable change and need no focus (except on the caret line, E5/E6);
  links, tags and wiki links open on tap; line height is stable across
  reveal for headings, rules, callouts, the box and inline code; wrapped
  list items hang; dark-mode conceal is fully transparent.
- ANTA strengths with no Obsidian equivalent: money ledger shortcuts and
  `$` rows with the detail sheet, counters, dated shortcuts with offsets,
  ghost placeholders with the two-tap engagement, vocabulary autocomplete,
  bar profiles with reorder and split ratio, indeterminate parent boxes,
  colour text, the callout insert.

## 5. Declined before, deferred

- **Ordered-list renumbering** (E36) — declined 2026-09-05 as a render
  (changes the unit count) and left out as an Enter edit; reopen on the
  owner's word only.
- **Per-token reveal** (E34) — L; the whole-line reveal is the documented
  design; revisit after Tier 1–2 land and a device pass shows the shift
  matters.
- **Rich paste, URL-over-selection link wrapping, slash menu, selection
  formatting bar** — `docs/markdown-feature-ideas.md` items 15–17; not QoL
  gaps.
- **Lite rendering tier, inline images, select rendered text** — rejected
  in `docs/live-editor-review-and-slices-2026-09.md` §4; unchanged.

## 6. Device pass (what only a phone can answer)

- Gboard: is a mid-word `'` an insertion delta (pairs, E21) or a composing
  replacement? In `(|)`, does soft Backspace leave `)` (E1's A2 half)?
- Does the Gboard clipboard chip paste through the delta path (E3, E32)?
  Does Ctrl+V on a hardware keyboard paste at all on Android?
- E13 on a device: tap under a last task line at the left edge; a tap in
  the editor's left padding.
- The E34 shift in px on task, link and bold lines; whether a wrap row
  appears on reveal.
- Real hit size of the box (~17 px by one line height, under 48 dp) under a
  thumb; bar height at 130 % / 200 % text scale with and without a
  suggestion session (E28).
- Still open from `docs/live-markdown-editor-roadmap.md:542-592`: toggle
  far from the caret with no scroll jump; undo selection after a toggle;
  scroll-drag starting on a box or link; long-press and double-tap on
  links; wiki tap target at small font sizes; snackbar clearance with
  gesture navigation; haptic strength; highlight and tag contrast on
  checked tasks in both themes; caret and selection on wrapped hanging
  lines.

## 7. Ledger

- **2026-10-19** — written by the lead (Fable 5.1) from three read-only
  reviews (Opus 5.5) and the lead's own verification (§1.3). The owner
  answers §2 row by row; slices follow §2.5. The C reviewer stopped at its
  turn limit and reported from what it had read; its unread files
  (`bar_switcher_sheet.dart`, the font-size step and range, the inline-code
  chip alpha in dark mode, the vocabulary session rules) are not covered.
- **2026-10-19, later** — the owner: "solve all of them, use other agents".
  The lead took the recommended option everywhere. Built in two phases of
  parallel implementers (Opus 5.5) with exclusive file ownership, reviewed
  by two read-only reviewers, fixed in two passes. **As built, where it
  departs from §2/§3:**
  - E1: only the marker rule runs in the delegate (`ListAwarePasteController`
    + `MarkerBackspacePolicy`, one revocable op); every other single-unit
    soft Backspace is recognised inside the fork's `edit()`
    (`isSingleBackspace`: ASCII, no composing range, the grapheme before the
    caret one unit) and runs `_deleteBackward()` in the line's typing undo
    node — so a held Backspace is one step, not one per character. `''` was
    dropped from the pair-delete list because `'` no longer pairs. The rule
    also reads a list item after a quote run (`> - |a` → `> |a`).
  - E4: the post-frame reveal sits in `_replaceRange` (every paste site,
    toolbar and ghost inserts included) and after undo/redo only when a
    node actually moved.
  - E5: reveal is `selectionCoversLine && (focused || findActive)` — the
    review found that the in-note find applies its match as the selection
    only while the search field holds focus, so focus alone hid matches
    inside concealed syntax; the page binds `_findActive` from
    `_searchController.isSearching`; both event sheets bind their focus
    nodes too. The wrapper rebuilds the editor subtree on focus change and
    the fork's `hasFocus` setter marks layout.
  - E6: the marker reveals for a collapsed caret in the half-open
    `[indent, contentStart)` — at `contentStart` (right after an Enter
    continuation) the box is already painted, so the first typed letter
    moves nothing.
  - E7/E8: one marker per Enter, innermost first: a nested item outdents, a
    top-level item ends into its quote, an empty `> > ` becomes `> `;
    `> - a` continues as `> - `; `shortcut_editor_page.dart` runs the same
    helpers.
  - E9: Indent/Outdent sit right after undo/redo for new installs (appended
    for stored lists); the bar hides them when a host wires nothing (the
    event sheets keep their own undo/redo/paste lists). The page and the
    wrapper share `ListIndentAction`.
  - E10: the toggle applies to the default list/task/numbered/quote ids
    however they were persisted; multi-line selections toggle as one unit;
    a list marker goes after a quote's `>` run; fence lines are skipped;
    numbering continues from the nearest non-blank ordered line above;
    quote removal strips the whole run.
  - E11: symmetric custom wrappers toggle too (accepted, not restricted to
    defaults); for `*`/`_` the outside-markers unwrap needs non-word
    characters beyond them (`snake_case` safe); a collapsed caret between
    two runs starts a new pair instead of merging them.
  - E12: the menu is the language's `FormMenuChoiceItem`s, `requestFocus:
    false`, the caret line's level checked; `applyHeader` (cycling) keeps the
    caret column too.
  - E14: the trailing newline is trimmed only when the transform continued
    the list to its last line; the old `'a\n\n'` pin became `'a\n- b\n\n'`.
  - E15: bracket expansion on Enter is off everywhere (the fork cannot see
    fences), behind `CodeLineOptions.expandClosuresOnNewLine`.
  - E16: the keyboard-rise reveal also requires editor focus.
  - E17: list items are never broken (not re-indented); the protected range
    covers the pre-paste text of the first line too; a paste's trailing
    whitespace is held back in front of the suffix.
  - E18: same line, same direction, 500 ms; the hardware single Backspace
    is grouped the same way; the IME multi-line commit is its own step;
    `runRevocableOp` resets the typing line.
  - E21: closers are tracked as a list of IME-view offsets mapped through
    every delta (not "the previous insertion only"); `"`/backtick do not
    pair against `[\p{L}\p{M}\p{N}]`; a bracket typed after a word still
    pairs (left).
  - E24: h5 and h6 stay 1.0 and share the one `headingWeight` (w600); h6
    stands apart by its blend.
  - E26: the toolbar's dismiss (Copy) clears the shown flag so a scroll does
    not resurrect it; Paste stays visible until the first clipboard answer,
    queried once per show, and Cut/Copy set it true.
  - E28: the two rows were 50 px and 47 px at scale 1.0, not "40 = 40"; the
    normal row now stays laid out but hidden under the suggestion bar (built
    once as the builder's `child`), the glyphs no longer scale, the pills
    clamp to 1.4.
  - E30: the controller's `extendSelectionToWordBoundaryForward/Backward`
    are named in reverse; the Windows/Linux table binds them crosswise like
    macOS and a desktop test pins the physical direction; Ctrl+Y redoes;
    the macOS Shift+Alt word-selection reversal is left alone.
  - E32: the IME multi-line commit gets the list-aware transform in the
    delegate; the touch key path handles Ctrl/Cmd+V, +Z, +Shift+Z, +Y.
  - E33: nothing to do — the reflow snackbar already used
    `withToolbarOffset: true`.
  - Beyond the list: Ctrl/Cmd+B/I reach the page through
    `onFormatShortcut` and run under its guard; the normal bar no longer
    rebuilds per keystroke during a vocabulary session; the settings page's
    switch starts from the new default; German "Einzug vergrößern /
    verringern".
  - **Noted, not changed:** the event sheets pass no `isFenceLine` to their
    wrapper and `ShortcutApplier.apply` forwards none, so a fenced line in a
    description can still take a heading or a box tap; two editor rebuilds
    per focus change (page `setState` + the wrapper's listenable); the E5
    page test proves the predicate, the wrapper suite the relayout.
  - **Device pass (qa-runner, Pixel_9_Pro emulator, `qa relaunch --fresh
    --seed tool/qa/fixtures/basic.json`, `--via agent`): 11 of 14 checks
    green, none red.** Green: new note focused at open (A), list Enter with
    the bar's Indent and the one-level exit (B), quote Enter (C), marker
    Backspace through `qa key backspace` for `- `, `1. `, `- [ ] ` (D1),
    long-press on an empty line then Paste landing there (E), the box on
    the caret line ticking with no shift (F), the unfocused reopen with a
    painted box that toggles without focus (G), the bar — Indent/Outdent
    after undo/redo, bullet toggle, task swap, bold wrap/unwrap, the H menu
    with the caret level checked and H3 pick/unpick (H), tap below the last
    line toggling nothing and parking the caret at the end (I), font size
    keeping the caret line (K), the 12-cell matrix with graded headings and
    the bar at the same bounds at 1.0 and 2.0 (L), `qa errors` clean (M).
    Not run, needs the phone: the soft-keyboard Backspace (D2), the
    keyboard-rise reveal (J) and the suggestion-row height at 2.0 — the
    driver build raises no soft keyboard and the seed triggered no
    suggestions; `adb shell input keyevent 67` never reaches the editor in
    that build either. Observations to check by hand: Outdent and the
    font-size buttons sit past the right edge at 427 dp (the strip
    scrolls); the first tap on the selection toolbar's Copy seemed to leave
    the toolbar up and a second tap closed it (possibly a harness timing
    quirk; E26's dismiss path is the suspect if it reproduces on the
    phone). Screenshots under `build/qa/shots/20261019_18*`.
