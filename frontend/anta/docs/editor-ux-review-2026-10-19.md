# Note editor — the UX/UI review (2026-10-19)

**Status: PROPOSED 2026-10-19 — fixes scheduled as slices U1–U3 after the
markdown features pass; nothing built yet.** The owner asked for a UX/UI
review on top of the quality-of-life pass (`docs/editor-qol-review-2026-10-19.md`)
and the markdown features audit (`docs/markdown-features-audit-2026-10-19.md`),
with the code going straight to production. Method: a qa-runner shot a
21-image matrix of the editor on the Pixel_9_Pro emulator (light/dark, en/de/ro,
text scale 1.0/2.0, the bar in every mode, the H menu, the selection toolbar,
the overflow menu, in-note search, a new note; `scratchpad/ux/*.png` of this
session); four read-only reviewers (UI language, interaction design,
accessibility, rendering polish) read the images and the code; three
independent verifiers judged each of the 91 findings (74 survived, 17 were
refuted). The lead consolidated the survivors below — the same issue seen
through several lenses is one row. The decisions are the lead's, taken under
the owner's "solve all of them, be very careful"; Obsidian mobile and the
app's own UI language (`ui-language` skill, `.claude/rules/ui.md`) are the bar.

Contents: §0 How to run this · §1 The slices · §2 Decisions · §3 Left as is ·
§4 Strengths to keep · §5 Ledger.

## 0. How to run this

Three implementer slices on disjoint files, each followed by three read-only
reviews, adversarial verification and a fix pass, then a gate (the same
machinery as the grammar pass). U1 and U2 may run in parallel (disjoint
files); U3 runs after the grammar slices D–F because it shares the span
builder and the inline emitter with them. The implementing session runs on
Opus 5.5 at high; it loads `ui-language` (SKILL.md and the references it
names), `markdown-engine` for U3, `flutter-principles`, `verify`, `l10n`.

### 0.1 Must not change

- The owner's stored bar profile and utility list keep their order and
  visibility; new behaviour applies to the default for new installs plus
  additive migrations (an unseen id is inserted after its nearest default
  predecessor, never appended at the end, never reordering what is stored).
- The bar keeps one height with and without the suggestion row at every
  text scale (the hidden-template row stays); the glyphs do not scale with
  the system text size (deliberate); the bar's height may grow once, to
  reach 48 dp targets.
- The editor's rendering invariants (`markdown-engine` SKILL.md): code-unit
  preservation, no line-height change on reveal, the span memo order.
- Every string through `AppLocalizations` in all three ARBs; existing keys
  keep their names (values may change).
- Settings keep their keys and stored values; a default may change only for
  new installs.

## 1. The slices

### U1 — the markdown bar (`lib/widgets/markdown_bar.dart`, `vocabulary_suggestion_bar.dart`, `lib/models/utility_button_config.dart`, `lib/config/default_markdown_shortcuts.dart`, `lib/constants/app_constants.dart` or a new bar metrics class, `lib/widgets/form_menu_item.dart` for the keyboard inset, ARBs, their tests)

| ID | Findings | What | Decision |
| --- | --- | --- | --- |
| U1.1 | L5 I13 A3 R19 | Bar targets are 44×40 dp with dead 3 dp bands; B/I/H narrower (Italic ~29 dp) | 48×48 dp contiguous hit areas for every bar button, the glyphs unchanged; the row grows to 48 (the bar once, by ~8 dp; the suggestion row follows through the shared box); the numbers named in one bar metrics class |
| U1.2 | L4 I9 R3 A10 | The utility strip shows 3 of 14 buttons; Indent/Outdent half-clipped or appended at the end for upgraded installs; undo/redo scroll away; no cue that either row scrolls | Undo and Redo pinned outside the utility scroll view, right after the divider; both scrollers get an edge fade driven by the scroll extent as the affordance; `decode` inserts an unseen id after its nearest stored predecessor (test with a pre-indent layout); the utility scroll offset resets after a tap |
| U1.3 | L7 L9 I11 A23 R17 | Reorder panel: fixed 3-per-row grid clips chips and labels at the right edge, hides rows, can overflow the body under the keyboard, no scroll cue | Width-driven `Wrap` of chips inside a vertically scrollable area (drag hit-testing by index kept, edge auto-scroll kept); entering reorder mode unfocuses the editor; panel height capped at half the body |
| U1.4 | L8 I12 A12 | Reorder chips show the stored English labels in de/ro | One `localizedLabel(l10n)` helper on the shortcut used by the buttons' tooltips, the reorder chips and the shortcut settings page |
| U1.5 | A1 R12 I16 L15 A17 | H menu: no visible check on the current level; no way back to body text; copy "Header" (en) / "Antet" (ro) | A visible `Icons.check_rounded` trailing on the current level (the marker preview stays leading); a first row "Body text" / "Fließtext" / "Text normal" checked on a plain line that removes the heading; labels "Heading 1…6", tooltip "Heading"; ro "Titlu 1…6"; de "Überschrift" unchanged |
| U1.6 | L12 | The H menu can open below the button, behind the keyboard | `formMenuPosition` uses `max(viewInsets.bottom, viewPadding.bottom)` as the bottom inset (the app's clearance rule), with a form-menu test |
| U1.7 | A21 | With the menu open a hardware keyboard still types into the note | `requestFocus: false` only on touch platforms; on desktop the menu takes focus |
| U1.8 | L18 A16 A8 | Disabled bar buttons at a literal 0.3 alpha; no button role or disabled state for TalkBack; the B/I/H glyph text read instead of the tooltip | `FormMetrics.disabledOpacity`; `Semantics(button: true, enabled: …)` on every bar button; `ExcludeSemantics` on the glyph; a semantics test |
| U1.9 | I10 | Nothing shows the shortcut row scrolls | Covered by the edge fade of U1.2; the default order stays as set on 2026-10-19 |

### U2 — the page and its chrome (`lib/pages/optimized_note_editor_page.dart`, `lib/widgets/note_editor_chrome.dart`, `lib/widgets/unified_app_bars.dart`, `lib/widgets/note_overflow_menu.dart`, `lib/widgets/note_search_bar.dart`, `lib/utils/custom_snackbar.dart`, `lib/main.dart`, `lib/widgets/modern_editor_wrapper.dart` (selection toolbar items, hint, text scale), the fork's `_code_selection.dart` (toolbar anchors) and `_code_field.dart` (find highlight colours), `CodeEditorStyle`, ARBs, tests)

| ID | Findings | What | Decision |
| --- | --- | --- | --- |
| U2.1 | I2 A11 | Bar shortcuts, indent/outdent and the H menu edit at a stale invisible caret on an unfocused editor | Request content focus first when unfocused (as the bar's Paste does), so the caret and keyboard appear with the edit; then the existing post-frame reveal |
| U2.2 | I4 | Renaming to a taken title looks accepted, then silently reverts; the existing title opens unselected | The title dialog gets `selectAll` and an inline duplicate warning from the service's title check; a reverted save restores the app-bar title |
| U2.3 | L2 | A caret move or a search hop flips the save indicator to unsaved | `_onTextChanged` reports a content change only when the text length or the code-lines identity changed; selection-only notifications do not reach the save coordinator (unit test: a caret move leaves `hasChanges` false) |
| U2.4 | L10 I8 A6 R2 L11 I21 | The stats strip says "distinct characters" (wrong) and "chunk" (storage jargon); numbers ungrouped; an emptied note shows its stored length | Copy "{count} characters · {lines} lines" with number grouping in en/de/ro, no chunk clause (the chunk count only under the developer options if they exist); the fallback value is used only before the tracker's first report; the setting and its default stay |
| U2.5 | L1 I7 A4 R4 | The note body and the stats strip ignore the system text size | The editor font is the user's size times the system text scaler, clamped at 2.0, applied in the wrapper and the width calculator alike (reflow and wrap widths agree); the stats strip clamps at 1.3; a de @ 2.0 widget test |
| U2.6 | L13 L14 I20 | Some editor snackbars cover the bar; the snackbar action is a 32 dp uppercase M2-style target that vanishes in 3 s | A page-local helper always passes the toolbar offset; `CustomSnackbar.showWithAction` gets a 48 dp action in sentence case (app-wide, checked at the other call sites); the link confirm lasts 5 s |
| U2.7 | A13 R18 I22 A5 R6 L17 I14 | In-note search: a stale line stays revealed with no match; the current match looks like every other and all matches are faint in light mode; two close controls; opening find pushes the body down ~50 dp; closing drops the keyboard | Reveal only while a match is selected (`findActive && currentMatch != null`); a distinct current-match colour in the fork's highlight painter (a `CodeEditorStyle` field) and stronger match boxes in light mode; the app-bar toggle focuses the open field and its tooltip says "Close search" while searching, the row's X closes; the find row overlays the top of the body (a `Stack`) so the text does not move; closing find with a match returns focus to the editor at that match |
| U2.8 | I19 L16 | Overflow menu mixes casing; "Label" is hidden before the first save | Sentence case for the editor's en/ro strings (keys unchanged); Label rendered disabled instead of removed |
| U2.9 | L24 I18 | The save status has no spoken state; the title has no semantics as a button | `Semantics` labels per save state (live region on the error only); the title tap wrapped in `Semantics(button: true, label: edit title)`; the cloud glyph stays (the app has sync) |
| U2.10 | R5 A20 | Dark theme shows a light system navigation band | The system overlay style follows the resolved brightness (nav bar icons light in dark mode, contrast enforcement off) at the app root |
| U2.11 | A22 | A new empty note gives no hint | A dimmed hint in the empty editor ("Start typing…" en/de/ro) that disappears on the first keystroke, through the fork's hint |
| U2.12 | L6 I15 A14 R22 | The selection toolbar opens below the selection over the next lines and the bar; it offers no formatting | The fork anchors the toolbar above the selection start when it fits, below the end only when it does not, never over the bar; Bold, Italic and Highlight items in the selection toolbar through `ShortcutApplier.toggleWrap` |
| U2.13 | L23 | No 360-wide or de @ 2.0 coverage for the bar, the reorder panel, the stats strip | A 360 × 780 de @ 2.0 group in the chrome suites (hit-testable buttons, no overflow with a fake keyboard inset, localized chips, legible strip) |

### U3 — rendering polish and editor accessibility (`lib/utils/markdown_editor_span_builder.dart`, `markdown_editor_inline_emitter.dart`, `markdown_editor_paint_spans.dart`, `lib/constants/markdown_constants.dart`, the fork's `_code_field.dart` semantics zone and `_resolveDecorPaints`, `lib/widgets/modern_editor_wrapper.dart` zone labels, ARBs, tests) — after grammar slices D–F

| ID | Findings | What | Decision |
| --- | --- | --- | --- |
| U3.1 | A9 | Light-theme callout and money accents below 4.5:1 (the PR callout ~1.9:1) | Darken the light variants in the one shared table (warning/moneyNeutral ≈ #BF360C, note ≈ #1565C0, success ≈ #00796B, pr ≈ #7A5C00, moneyWarning ≈ #8A6A00), each checked against the light page; colour tests updated |
| U3.2 | A15 | Done-task text 3.26:1 in light | `checkedTextOpacity` 0.5 → 0.62 |
| U3.3 | R10 | Headings lighter than bold body text | `headingWeight` w700 |
| U3.4 | R7 | Inline code proportional; fences have no ground or size step | Monospace in the code chip; fence interior and delimiters at `inlineCodeScale` on a faint chip ground, the root span keeping the strut (no line-height change), the doc comment fixed |
| U3.5 | R9 | Wrapped quote and callout lines wrap under the bar | `CodeHangingTextSpan` for quotes and callouts (hanging at the content start), a span-builder test with a long quote, a device check of the bar on the wrapped row |
| U3.6 | R14 | Tag pills touch each other and overhang the margin | A visible gap between adjacent pills (padding paint-only, inset) and the chip's left edge clamped to the paragraph's x = 0 |
| U3.7 | R16 | List indents jitter between levels; a tab indent is shallower than two spaces | Optional: bullets painted with equal advance (a paint span) and a tab rendered one level wide — only if the hanging-split and units suites stay green and the look is verified on the device; otherwise left as is |
| U3.8 | A7 | TalkBack reads every zone as "Toggle task" / "Open link" with no content or state | `CodeEditorSemanticsZone` gains optional checked/link/value fields; the wrapper passes the task text, the link text or the tag with ARB patterns ("Toggle task: {task}"); the semantics suite extended |

## 2. Decisions

- D1 **48 dp targets grow the bar once.** The owner's bar is the most
  tapped surface; the UI rule says 48 dp; the hidden-template row keeps the
  suggestion bar aligned. Growth ≈ 8 dp.
- D2 **Undo and Redo are pinned.** The "no lost text" action never scrolls
  away. The rest of the utility strip keeps the owner's ratio and order.
- D3 **The editor follows the system text size, clamped at 2.0.** The app
  rule treats text scale 2.0 as part of done; the in-app size stays the
  base; the chrome glyphs stay fixed.
- D4 **The stats strip stays, with honest copy.** No default change; the
  chunk count goes behind developer options.
- D5 **"Heading", not "Header"; ro "Titlu".** Keys unchanged.
- D6 **The reorder panel becomes a wrapping, scrollable grid**, not a
  sub-sheet: the smallest change that makes every chip reachable.
- D7 **The cloud glyph stays** — the app has sync; it gets a spoken label.
- D8 **New-note titles stay "New Note"**; auto-titling from the date or the
  first line is a product decision for the owner, not this pass.

## 3. Left as is

- **The find row as an overlay (U2.7)** — deferred 2026-10-21: the fork's
  find scroll has no top inset, so an overlaid row would hide matches on
  the top lines; it needs a fork change to the match-visible check first.
- **Custom task states in TalkBack (U3.8)** — a custom state and an
  indeterminate parent still announce "not checked"; the positional task
  index would have to feed the zone.

- I18's auto-title setting (D8); R12's size-scaled menu labels (clutter in a
  48 dp row); I10's reordering of the new-install default row (set earlier
  the same day); R16 unless the optional variant proves safe.
- Items already covered by the grammar pass: I3 (F24), R13 (F9/F10), R14's
  nested tags (F6), R20 (F1).

## 4. Strengths to keep (the reviewers' list)

The bottom bar riding the keyboard; one shortcut tap = one undo; live
conceal with the caret-line reveal and the tappable box; the hanging indent
on list items; the dark-mode conceal; the callout icon and accent title;
the money rows; ghosts; the bar profiles with reorder and split ratio; the
indeterminate parent boxes; the new line-prefix and wrap toggles; the H
menu by level; the stable bar height with the suggestion row.

## 5. Ledger

- **2026-10-20/21 — U1, U2, U3 BUILT and gated (uncommitted at the time of
  writing; the completion pass C2 of the same workflow family closes the
  coverage gaps listed below).** Same machinery as the grammar slices: one
  implementer, three reviewers, three verifiers per finding, a fix pass, a
  gate (baselines U1 `0ca58c36`, U2 `f71f0f0d`, U3 `eb656361`). Findings:
  U1 49 raised / 42 kept / 30 fixed; U2 53 / 50 / 28 (its implementer ran
  out of budget before testing, the fix pass finished U2.2, U2.3's memo
  seed, U2.7's toggle and X, U2.10 and the pins it could reach); U3 35 / 28
  / 21. **As built, where it departs from §1:**
  - U1.1: the bar is 55 dp (hairline + 3 + 48 + 3; was 47, D1's growth of
    8); every bar button is a 48 dp contiguous target; the numbers live in
    `lib/constants/markdown_bar_metrics.dart`.
  - U1.2: Undo and Redo are pinned in split mode and in preview mode; the
    single-row mode has no utility scroller to pin them outside of, so it
    gets the edge fade and the 48 dp targets only; the utility scroller
    resets its offset after every tap — including the font-size buttons,
    so a second tap on A+ can land elsewhere (a follow-up exempts the
    repeatable buttons); stored lists gain an unseen id after its nearest
    stored predecessor.
  - U1.3: the reorder panel is a width-driven Wrap in a vertical scroller
    capped at half the screen minus the keyboard inset; entering it
    unfocuses the editor; at de @ 2.0 with the keyboard still up the header
    overflowed the cap for one frame (C2 wraps it).
  - U1.5: the check is trailing in a slot reserved on every row (the marker
    preview stays leading); "Body text" carries the id
    `editor-heading-0`; copy as decided (en "Heading", de "Überschrift", ro
    "Titlu"; "Body text" / "Fließtext" / "Text normal").
  - U1.8: `FormMetrics.disabledOpacity`, `Semantics(button, enabled)`,
    `ExcludeSemantics` on the glyphs.
  - U2.2: the title dialog opens selected with an inline duplicate warning
    (an async folder-title cache redrawn through `warningRefresh` on
    `AppDialogs.textInput`); a reverted save restores the bar title from
    the coordinator's original title.
  - U2.3: selection-only notifications no longer reach the save
    coordinator (a text-length and code-lines-identity memo seeded in
    `initState`).
  - U2.5: `followsTextScale` is opt-in and only the note editor turns it
    on; the event description box keeps unscaled lines by design.
  - U2.6: the overlay road (the earlier ledger entry) plus a sentence-case
    action; the 5 s confirm cap lived on `CustomSnackbar` beside the 3 s
    default in `AppConstants` (C2 names them honestly); the bar had grown
    to ~76 dp around the 48 dp action (C2 brings it to ≤ 56).
  - U2.7: reveal only while a match is selected; a tertiary-hued current
    match and stronger boxes in light mode; the app-bar toggle focuses the
    open field (tooltip "Close search" while searching), the row's X
    closes; **the find row still pushes the body down** — an overlay needs
    a top inset in the fork's match-visible check, deferred (§3); focus
    returns to the match on close by the fork's own collapse.
  - U2.10: `AppSystemBars`, an `AnnotatedRegion` keyed on the resolved
    brightness at the app root (the alarm page's own bars hand over to it
    once its route is gone).
  - U2.11: the hint shows on a new empty note, not after every character
    is deleted (accepted).
  - U2.12: the fork anchors the toolbar above the selection start when it
    fits, below the end otherwise, never over the bar — computed at show
    time (C2 re-anchors on every inset change); Bold, Italic and Highlight
    in the selection toolbar.
  - U3.1–U3.3: as decided; the named colour palette's light presets in
    `markdown_color_syntax.dart` (user-chosen text colours) keep their
    values; `question` measured 4.41:1 on the cursor-line ground (C1
    darkens it).
  - U3.4: monospace inside the chip; fence lines at the inline-code scale
    on a faint chip ground painted per glyph (a blank interior line shows
    no ground, mild); `ghostStyle` keeps a ghost inside a code span in
    prose, as the preview does.
  - U3.5: quotes and callouts hang at their content start; the hanging
    width is measured from the marker, which differs between `>` and `┃`
    exactly as lists differ between `-` and `•` — line height never
    changes.
  - U3.6: a 2 px paint-only gap between pills, the chip's left edge clamped
    to the paragraph's x = 0 in `_code_paragraph.dart`.
  - U3.7: left as is (optional).
  - U3.8: zones announce the task text and its state, the link text or
    the tag (ARB patterns en/de/ro); the node key no longer includes the
    label; custom task states and indeterminate parents still announce
    "not checked" (the positional index would be needed).
  - One U3 agent ran `sed -i` once on an LF test file against the house
    rule; the result was verified correct and nothing was lost.
- **2026-10-19** — written by the lead (Fable 5.1) from the UX review
  workflow (4 reviewers, 91 findings, 74 verified) and the device matrix.
  Slices U1–U3 are scheduled after the grammar slices; their outcomes will
  be appended here.
- **2026-10-19, the owner's report** — "1 long line was formatted" appeared
  with the keyboard up and stayed mid-screen after the keyboard closed.
  Cause: `CustomSnackbar._floatingMargin` baked the keyboard inset into the
  `SnackBar.margin` on pages whose Scaffold does not resize (the note editor,
  the calendar page); a `SnackBar` is laid out once, so the lift never came
  down. Fix (lead, same day, U2.6 territory): on such pages every
  `CustomSnackbar` call rides `OverlaySnackbar.showContent`, whose body reads
  `max(viewInsets.bottom, viewPadding.bottom)` in `build` and re-anchors on
  every keyboard move; pages whose Scaffold resizes keep the Scaffold road
  (the Scaffold moves their bars itself). The overlay body is public
  (`OverlaySnackbarBody`) for tests; the action button dismisses either
  road through `CustomSnackbar.hide`. Pinned in
  `test/widgets/custom_snackbar_keyboard_test.dart` ("follows the keyboard
  down when it closes", "…up when it opens", "keeps the toolbar offset while
  riding the keyboard", "the action takes an overlay bar down with it");
  the editor page suite and the calendar countdown suite now find the
  overlay body. Rule for the language: never bake a keyboard inset into a
  `SnackBar.margin` — a bar that must clear the IME on a self-laid-out page
  goes through the overlay.
