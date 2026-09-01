# Event Description Editing Roadmap — ANTA

**Status: shipped (2026-08-31).** Everything below is implemented; this file
is the design record. Running behaviour: `docs/calendar-events-feature.md`
(§ 6.6 and the 2026-08-31 addendum), `docs/description-scope-roadmap.md` (the
v24/v28 per-occurrence scope model this change did not disturb), and the
calendar bullets in `COPILOT_CONTEXT.md`. Verified at ship time:
`dart analyze lib test` clean; `flutter gen-l10n` clean in en/de/ro; full
`flutter test` suite green at **1603 passed** (1582 before this change), the
21 new tests spread over `test/widgets/event_description_sheet_test.dart`,
`event_detail_description_test.dart` and `event_editor_back_test.dart`.

**Deviations from the plan as written.** The plan was reviewed against the
code before implementation; these are what that review and the build changed.

1. **The back button *replaces* the close button** rather than joining it
   (§6.2, §9.1). Both discard identically, so two adjacent buttons differing
   only in where you land is a distinction too fine to hang a second icon on.
   The header stays one leading button, which means the documented
   `close | centred title | Save` shape is **not** contradicted after all —
   only the leading icon and tooltip change. §6.2's warning about breaking a
   documented rule, and its two centring options, are both moot: the title is
   centred by `Expanded` + `textAlign: center` against a 48dp icon on one side
   and a wider `Save` button on the other, so it is *already* optically
   off-centre today and option 1 cost nothing.
2. **`_openEditorSheet` had to be refactored to return its result.** It was
   `Future<void>` and dispatched internally, so the loop in §6.4 was written
   against a return value that did not exist. It now returns
   `Future<EventEditorResult?>` and still dispatches everything itself; only
   the loop reads the value. `showBack` likewise threads through that helper
   and its **five** callers, not the single `show` call §6.2 pointed at.
3. **The loop carries two guards the plan did not have.** `EventEditorSaved`
   turned out to carry four things, not two: a non-null `occurrenceDay` with a
   **null** description is a *reset that deleted the row*, and `skippedDays`
   (v30) was invisible in §6.4 entirely. So `_pendingAfterSave` is tri-cased
   (dormant → drop the pending value, reset → fall back to the template,
   otherwise the written text) and `_occurrenceSurvives` refuses to reopen on
   a day the save removed — reading the skip set **from the result**, because
   the skip dispatch is async and `EventSkips` may not carry it yet, then
   falling back to `occursOn`. Never `eventsForDay`: it applies the
   hidden-category filter and would call a filtered event gone.
4. **The quick edit skips the dispatch when nothing changed**, and seeds from
   the *raw* text rather than the detail sheet's trimmed render. §4 said it
   follows `_flushWrite`'s routing "exactly"; `_flushWrite` has no such guard
   because a checkbox tick always changes something. Without it, an unedited
   Done on a day with no row of its own would materialise one identical to the
   template — forking that day forever — and on an event would bump `version`
   and the HLC for nothing.
5. **Emptying a per-occurrence quick edit writes `''` (a blank day), not a
   tombstone.** §4's table did not say, and §8.8's invariant made it look
   settled. It is not the same operation: `''` is a deliberately blanked day
   that keeps winning over the template, and returning to the template stays
   the editor's explicit "reset this day". WYSIWYG won — text silently
   reappearing after a delete-all is the worse surprise.
6. **The empty state has no placeholder.** §3.1 called `eventDescriptionHint`
   "already in the ARB" as if it were wired; it is an unused key, and a
   `CodeEditor` has no hint mechanism. Rendering one needs a hand-aligned
   overlay, and a misaligned placeholder is worse than none.
7. **`eventDetailsNoDescription` is now unused.** The empty state became a
   tappable row reading "Add description" instead of a dead line
   naming the state. The key is left in the ARBs.
8. **§3.2's wiring list was incomplete.** The sheet also needs the required
   `ReEditorSearchController` (with `initialize`) and `CodeScrollController`;
   an explicit post-frame `requestFocus`, because `ModernEditorWrapper`
   hardcodes `autofocus: false` and a `CodeEditor` is not an `EditableText`;
   `runRevocableOp` plus a post-frame `makeCursorVisible` around shortcuts;
   the `MarkdownBarBloc` cold-start guard; and the relay driving the **bar's
   undo/redo enablement** too, not just the counter and Done.
9. **Money is disabled by omission, not by a parameter.** There is no money
   argument on `ModernEditorWrapper` or on the span builder — §2.6/§8.1 read
   as though `MoneyDisplayConfig.disabled` gets passed somewhere. The rule is
   really *never call `configureMoney`*, which is a much easier thing to break
   by copying the note editor's setup.
10. **The docked bar makes this a fixed-footer sheet**, so the
    `max(viewInsets, viewPadding)` clearance wraps the whole sheet rather than
    padding a scrollable — the `CalendarFilterSheet` variant of that rule, not
    the one §3.1 assumed both existing sheets shared (they do not: the editor
    sheet sets no `useSafeArea` and pads itself, the detail sheet does the
    opposite).
11. **Sheet stacking needed no justification.** §6.1 defended `EventEditorBack`
    partly as avoiding two stacked barriers; the editor sheet already opens
    `EventTemplateEditorSheet` at 0.92 on top of its own 0.92, and the category
    picker stacks three deep. The loop is still right — it matches the existing
    sequential convention — but for the plainer reason that the page owns the
    sheet it reopens.
12. **The detail sheet has exactly one call site**, so the loop was written
    once. §6.4 did not say either way; every other surface (agenda pencil, FAB,
    template quick-add) goes straight to the editor.
13. **A visual pass followed the functional one**, correcting four things where
    the plan (and the first implementation of it) dressed a full-height surface
    in the inline field's clothes:
    - **The editor lost its border.** §3.1's sketch boxes the editor; that is
      the 120–260 px field's treatment scaled up to a whole screen, where it
      reads as a form field, nests a box in the sheet's own box, and spends the
      horizontal room the sheet exists to provide. The note editor — the app's
      other full-height editor — has no border either.
    - **The header stacks instead of ellipsising.** §3.1's
      `<event title> · Description` breadcrumb loses the wrong half: between a
      48 dp icon and Done there is ~180 dp on a phone, so the word naming the
      sheet is the first casualty. The title now sits as a muted line above the
      label; the title truncates, the label never does, and the pair fits
      inside the row's existing button height at no vertical cost.
    - **The over-limit message no longer resizes the editor.** §3.3 put it
      below the counter as its own row, so crossing the limit reflowed the text
      under the caret — at exactly the moment the user is fighting the limit.
      It now takes the caption's slot inside a status band height-reserved for
      two `bodySmall` lines (scaled with the user's text size), so the swap
      costs no layout change. Guarded by a test that measures the editor before
      and after.
    - **The detail sheet's empty state is filled, not outlined**, with the same
      tonal wash as the populated description card, so it reads as that card
      waiting to be filled rather than as a disabled input; and its pencil
      keeps a full 48 dp tap target with a 20 dp glyph, with the surrounding
      gaps trimmed so the label band matches "Next occurrences" below it.

The plan as written follows.

---

## 1. The problem, restated correctly

The opening complaint was "the markdown is scarce in the detail sheet and I
can't edit it there". Reading the code says something different, and the
difference is what this plan is built on:

- `_buildDescriptionSpan` (`event_editor_sheet.dart:649`) delegates to the
  **same `MarkdownEditorSpanBuilder` the note editor uses**. Headings, lists,
  task boxes, callouts, tags, `{color:…}` runs, links and ghost text already
  render at full parity. **No markdown syntax is missing anywhere.**
- What is actually clamped is **room** and **reach**:

  | Clamp | Where | Effect |
  | --- | --- | --- |
  | `maxHeight: 260` | `event_editor_sheet.dart:216` | ~8 lines, in a box nested inside the form's own `SingleChildScrollView` |
  | Depth | `calendar_page.dart:433` | detail → Edit → scroll a 15-field form → find the description → Save |
  | 3 utility buttons | `_descriptionUtilities`, `:221` | undo/redo/paste only |

  The nested-scroller problem is the one that makes writing feel bad: a
  `CodeEditor` owns its own scroller inside a scroll view that also wants the
  drag.

So the work is **not** "add markdown capability". It is: give the description a
full-height surface, and give it a short path from the detail sheet.

---

## 2. Decisions locked (2026-08-31)

1. **The detail sheet stays read-only.** Checkbox toggling remains its only
   in-place edit. The inline-markdown-editor idea is **rejected** — no editor
   is mounted in `EventDetailSheet`.
2. **The proposed calendar setting is dropped.** It existed to gate an inline
   editor that no longer exists. A quick-edit button needs no toggle, and
   `SettingsKeys` gains nothing. (A deliberate reversal of the opening
   request; the feature it was gating changed shape.)
3. **One widget, two entry points.** The editor sheet's "expand" mode and the
   detail sheet's quick-edit are the *same* full-height description sheet.
4. **Save returns to the detail sheet** when the editor was opened from it.
5. **A back button joins the editor sheet's header**, alongside the existing
   close button, when there is a detail sheet to return to.
6. **Money stays disabled** in every description surface
   (`MoneyDisplayConfig.disabled`) — unchanged hard rule.
7. Not in this pass, explicitly declined: fuller markdown bar (bar switching,
   font sizing, scroll jumps), find-in-description, raising the character
   limit.

---

## 3. The shared surface: `EventDescriptionSheet`

New widget, `lib/widgets/event_description_sheet.dart`. A **pure text-in /
text-out modal**: it never touches a service, never persists, and knows nothing
about scope, occurrences or events.

```dart
static Future<String?> show(
  BuildContext context, {
  required String initialText,
  required String heading,          // event title, for the breadcrumb
  String? scopeCaption,             // "Applies to every occurrence", or null
  required int limit,
  required int grandfatheredLength, // see §3.3
  MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
})  // -> edited text, or null when cancelled
```

Returning `null` on cancel and a `String` on confirm keeps both callers'
handling trivial, and keeps the sheet inside the established rule that a sheet
reports an outcome and the caller dispatches it.

### 3.1 Layout

`FractionallySizedBox(heightFactor: 0.92)` — matching the editor sheet, not the
detail sheet's 0.8, because the whole point is room.

```
[✕]  Leg day · Description                            [Done]
─────────────────────────────────────────────────────────────
 Applies to every occurrence                    1 240 / 2 000
┌───────────────────────────────────────────────────────────┐
│                                                           │
│   (ModernEditorWrapper — the only scrollable on screen)   │
│                                                           │
└───────────────────────────────────────────────────────────┘
[ markdown bar, docked, always visible ]
```

- The editor is `Expanded`, so it owns **all** remaining height and there is
  **no outer scroll view to fight**. This is the single biggest improvement in
  the plan.
- Header mirrors the editor sheet's inline `close | title | action` shape, so
  the two sheets read as one family. Heading is `<event title> · Description`
  as a breadcrumb, ellipsised.
- The markdown bar is **permanently docked**, not focus-gated. In the editor
  sheet it appears on focus because the form must not shift; here the
  description is the entire content, so a stable bar beats a disappearing one.
- Bottom padding uses the existing `max(viewInsets, viewPadding)` clearance
  idiom from both sheets.
- Empty state: the editor is empty and focused, with `eventDescriptionHint`
  (already in the ARB) as placeholder text.

### 3.2 Editor wiring — the traps

The sheet owns its own controller and its own `ModernEditorWrapper`, which is
legal: the "one controller, swap only its text" rule forbids swapping
controllers *under a mounted wrapper*, not a second wrapper in a second route.
Everything else carries over verbatim:

- `ListAwarePasteController(delegate: CodeLineEditingController(spanBuilder:))`,
  a sheet-owned `MarkdownEditorSpanBuilder`, `bind()` after construction.
- `clearHistory()` after the seeding write, or undo wipes what the sheet opened
  with.
- **No `ListenableBuilder` on the controller.** Route the counter and the Done
  button's enablement through a `ValueNotifier<int>` relay with post-frame
  deferral, copied from `_descriptionRevision` — the mid-build
  `notifyListeners()` from re_editor's delegate handoff throws otherwise.
- Live rendering follows the global `liveMarkdownRendering` setting;
  `checkboxTapToggle: _liveMarkdownRendering`, `showScrollIndicator: false`.
- Colour palette resolves late → `configureColors` + `forceRepaint()`,
  **never** a remount.
- Markdown bar: `MarkdownBarBloc` active profile, counter-bound shortcuts
  filtered (`s.effectiveCounters.isEmpty`), `splitEnabled: false`,
  `showSettings: false`, `showReorder: false`, utilities undo/redo/paste.
  Shortcut routing reuses `MarkdownShortcutInserter` + `ShortcutApplier` with
  `mutateCounter: (_, _) async => null`, exactly as `_handleDescriptionShortcut`
  does today.

### 3.3 The limit, without a form to block

`_canSave` guards the limit in the editor sheet by disabling Save. Here:

- Live counter in the header row, red past the limit.
- **Done is disabled** while over budget, with the existing
  `eventDescriptionTooLong` string below the counter.
- The **grandfather rule survives**: `grandfatheredLength` is passed in, and the
  text is always confirmable at a length it already had, so lowering the limit
  blocks growth rather than trapping the user in a sheet they cannot leave.
  Cancel (`✕`) is never disabled.

---

## 4. Entry point A — the detail sheet's quick edit

`EventDetailSheet` gains one action and no editor.

- `EventDetailAction` gains **`editDescription`**.
- The sheet header is already `[✕] centred title [Edit]`; a third control makes
  it four. So the affordance goes on the **description card's own header** — a
  pencil `IconButton` on the `Description` label row. That leaves the sheet
  header untouched and puts the button on the thing it edits.
- Empty state upgrade: `eventDetailsNoDescription` becomes a **tappable** row
  (dashed outline + pencil + "Add description") firing the same action. One tap
  from nothing to a full-height editor.
- The sheet **flushes any pending checkbox write before popping** (`_close`
  already does this) so the description sheet opens on the text the user is
  looking at, never the pre-tick version.

**Which text it edits** follows `_flushWrite`'s existing routing exactly — no
new scope picker, so a quick edit and a checkbox tick can never write to
different places:

| Event | Target | `scopeCaption` |
| --- | --- | --- |
| per-occurrence on (`OccurrenceDescriptions.appliesTo`) | this day's override | `eventDescriptionScopeThisDayHint` |
| one-time | the event's description | none |
| repeating, per-occurrence off | the shared template | new key, "Applies to every occurrence" |

The last row is worth being loud about: a quick edit there changes every
occurrence. It is safe to *offer* — unlike a checkbox tick, typing is explicit
intent — but it must say so.

### 4.1 Inert checkboxes get a reason

Unrelated to editing, and cheap: when the boxes are inert (repeating +
per-occurrence off — `event_detail_sheet.dart:38-43`), render a one-line caption
under the description explaining that ticking would apply to every occurrence,
and that per-day descriptions are the way to tick one. With editing gone from
this sheet, the dead boxes are otherwise the only unresponsive thing on it.
Doubles as discovery for the v28 switch.

---

## 5. Entry point B — expand from the editor sheet

`_buildDescriptionField` keeps its 260px box and gains an **expand** icon
(`Icons.open_in_full_rounded`) in its header row, beside the counter and the
existing preview toggle.

- Seeded from `_descriptionController.text` — i.e. **the active scope only**.
  The editor's own `_scope` control stays behind in the form; the sheet never
  sees it. This is what keeps the sheet a pure text-in/text-out widget and keeps
  the two-buffer copy-on-write logic in exactly one place.
- On return: `_descriptionController.text = result; clearHistory();` and mirror
  into the active buffer (`_templateBuffer` / `_dayBuffer`) the same way
  `_setScope` does. `clearHistory()` is mandatory — same reason as the scope
  swap.
- On cancel: nothing changes.
- **The expanded sheet does not save the event.** It edits the in-flight
  controller; the form still saves. Nothing about the
  `_resolveOccurrenceOutcome` copy-on-write contract changes.

---

## 6. Navigation — back button and the return loop

### 6.1 New result variant

`EventEditorResult` gains `EventEditorBack` (sealed, alongside
`EventEditorSaved` / `EventEditorDeleted`). Matches the file's stated
architecture — "the sheet never writes; it reports what the user did and the
page dispatches it" — and avoids stacking two modal routes with two barriers.

### 6.2 Header layout — and a rule this breaks

`EventEditorSheet` gains `final bool showBack` (default `false`), set only on
the detail-sheet path. `calendar_page.dart:714` (the FAB) leaves it false: a
brand-new event has nothing behind it.

The header becomes `[←][✕]  Edit event  [Save]`.

> **This contradicts a documented rule.** `COPILOT_CONTEXT.md` and the
> `calendar-events` skill state the editor's inline header **stays**
> `close | centered title | Save`. The rule's stated purpose is to keep
> *secondary whole-form actions* (Save as template, Delete) out of the header
> and at the bottom of the body — a back button is navigation, not a form
> action, so the spirit survives. It still must be updated in the same change,
> not silently violated.

Two leading buttons plus a trailing `Save` leaves the centred title visually
off-centre on a 360dp phone. Options, in preference order:

1. Keep the title centred and accept the slight optical offset (smallest diff,
   keeps the family resemblance with the detail sheet).
2. Left-align the title after the button cluster (Material 3 sheets commonly
   do; a larger visual change and a second deviation from the rule).

**Open decision — see §9.**

### 6.3 Semantics

- Back **discards, exactly like `✕`.** There is no dirty tracking in this sheet
  today and `✕` sets the precedent; having the two buttons differ on *discard
  behaviour* would be worse than having them differ on destination.
- The Android system back gesture maps to the same action via `PopScope` when
  `showBack` is true.
- `l10n.back` already exists (`app_en.arb:4274`) — no new key.

### 6.4 `_openDetailSheet` becomes a loop

`calendar_page.dart:397` currently opens the detail sheet once and routes one
action. It becomes a loop over the detail sheet, with two of the four actions
re-entering it:

```
loop:
  action = EventDetailSheet.show(current, day, …)
  edit            -> EventEditorSheet.show(showBack: true)
                       saved   -> dispatch, current = saved event, continue
                       back    -> continue
                       deleted -> dispatch, break
                       null    -> break            (✕ closes everything)
  editDescription -> EventDescriptionSheet.show(…)
                       text    -> dispatch (event or occurrence), continue
                       null    -> continue
  openNote        -> break
  skipOccurrence  -> break     (the occurrence stops existing; reopening would
                                describe something that is gone)
  null            -> break
```

Rules the loop must respect:

- `current` already tracks checkbox rewrites; it must now also absorb
  `EventEditorSaved.event` so the reopened detail sheet shows the save.
- The **occurrence write is dispatched, not awaited**, and the sheet reopens in
  the same turn — so `pendingOccurrence` must carry forward into the reopened
  detail sheet exactly as it already carries into the editor. `EventDetailSheet`
  needs a `pendingOccurrenceDescription` parameter mirroring the editor's, or
  the reopened sheet races the database and shows the pre-edit text.
- Occurrence writes go through `SetOccurrenceDescription` / the existing bloc
  events — **never** a direct service call — and must not invalidate the day
  cache (text is not a membership input).
- Skips and deletes break the loop; presence toggles never reach it.

---

## 7. Localization

New keys (×3: `app_en.arb`, `app_de.arb`, `app_ro.arb`, then `flutter gen-l10n`):

| Key | English |
| --- | --- |
| `eventDescriptionEdit` | Edit description |
| `eventDescriptionAdd` | Add description |
| `eventDescriptionExpand` | Open full editor |
| `eventDescriptionDone` | Done |
| `eventDescriptionAppliesAllOccurrences` | Applies to every occurrence |
| `eventDescriptionTickAllOccurrences` | Ticking here would apply to every occurrence. Turn on per-day descriptions to tick just this one. |

Reused as-is: `eventDescription`, `eventDescriptionHint`, `eventDescriptionCount`,
`eventDescriptionTooLong`, `eventDescriptionScopeThisDayHint`,
`eventDetailsNoDescription`, `back`, `close`, `cancel`.

---

## 8. Invariants this plan must not break

Checked against the `calendar-events` skill; each is a live failure mode:

1. **Money disabled** in every description surface.
2. **Counter-bound shortcuts filtered** out of the bar — `{c1}` resolves against
   a note context an event does not have.
3. **No `ListenableBuilder` directly on a re_editor controller** — relay through
   a `ValueNotifier<int>` with post-frame deferral.
4. **`clearHistory()` after every programmatic text write.**
5. **Never remount the editor** to apply a late-resolving setting —
   `configureColors` + `forceRepaint()`.
6. **`SimpleMarkdownPreview.onCheckboxTap` stays null** on read-only surfaces;
   the detail sheet's existing gating is unchanged.
7. **`OccurrenceDescriptions.descriptionFor` stays the one entry point** for
   resolving a day's text.
8. **A present occurrence row always wins, including when empty**; reset
   tombstones, never writes `''`.
9. **Occurrence writes bump `occurrenceRevision`, never `_invalidateDayCache()`.**
10. **The grandfather rule** on the description limit survives into the new sheet.
11. **Detail sheet checkbox gating** (one-time, or per-occurrence on) is
    untouched.

---

## 9. Decisions taken at implementation

The four that were open when this plan was written, and how they resolved.

1. **Editor header layout** — neither option. The back button **replaces**
   close, so the header keeps exactly one leading button and today's geometry
   (deviation 1). The centring question dissolved with it.
2. **Quick-edit scope picker** — no picker, as planned. A per-occurrence event
   edits *this day* from the detail sheet and its template only in the full
   editor, and the caption says so out loud. Carrying the `SegmentedButton`
   would have dragged the two-buffer copy-on-write logic into a second widget,
   which is the one thing the pure text-in/text-out design exists to avoid.
3. **`openNote` breaks the loop** — as written. Verified that `didPopNext`
   does fire for the note editor's page push (it does not fire for any sheet,
   all `PopupRoute`s), so the calendar refreshes on return; reopening a sheet
   the user deliberately navigated away from would be a surprise, not a
   service.
4. **New, and not in the plan: what an emptied per-occurrence quick edit
   means.** It writes `''` — a deliberately blanked day — and is not a reset.
   See deviation 5.

---

## 10. Verification

| Step | Command |
| --- | --- |
| ARB edits | `flutter gen-l10n`, then check `untranslated.txt` |
| All Dart changes | `dart analyze lib` |
| Regression | `flutter test` |
| Manual | `flutter run` — detail → quick edit → back; detail → Edit → back; detail → Edit → Save lands on detail; editor → expand → Done; a per-occurrence event on a repeating rule; over-limit text; a repeating event with unticked boxes (inert + caption) |

Tests written (standing permission, 2026-08-16) — 21, all green:

- `test/widgets/event_description_sheet_test.dart` (10): Done returns the
  edited text, close returns `null`, Done disables past the limit and recovers
  under it, the grandfathered length stays confirmable while growth past it
  does not, cancel is never disabled over budget, crossing the limit leaves the
  editor exactly the same size (the §13 status-band guard), and the header
  shows the event name above the label — never truncating the label, and
  showing it alone for an untitled event.
- `test/widgets/event_detail_description_test.dart` (7): the empty state
  offers "Add description" and reports `editDescription`, the pencil reports
  it too, the sheet still mounts **no** editor, a pending occurrence write
  beats the facade, and the inert-checkbox caption appears only when the boxes
  are actually inert *and* there is actually a task box.
- `test/widgets/event_editor_back_test.dart` (4): with `showBack` the header
  carries a back button and **no** close button and reports `EventEditorBack`;
  without it, close still reports `null`; and the Android system back gesture
  lands where the button lands in both cases. Drag-dismiss deliberately still
  pops `null` and ends the whole trip — `BottomSheet.onClosing` calls
  `Navigator.pop` directly, which never consults `PopScope`.

Two traps found while writing them, worth knowing before touching either file:

- **`tester.enterText` cannot drive a `CodeEditor`** — it is not an
  `EditableText`, so `showKeyboard` finds no state and throws `Bad state: No
  element`. Drive `tester.widget<CodeEditor>(...).controller!.text` instead,
  which also exercises the relay the counter and Done hang off.
- **The `MarkdownBarBloc` provider must sit above the `MaterialApp`** in the
  test, exactly as `main.dart` provides it: the sheet is a route, so a provider
  inside `home` is below it in the tree and `context.read` throws. And a test
  that leaves the focused sheet open at teardown fails on re_editor's pending
  cursor-blink timer — dismiss the sheet before the test ends.

Left for the manual pass (no widget test): the `_openDetailSheet` loop itself,
which needs a live `CalendarBloc` and the seven calendar services.

---

## 11. Docs updated in the same change

All three landed with the code:

- `COPILOT_CONTEXT.md` — the header rule reworded to "one leading icon
  (`close`, or `back` on the reopen loop)", the new sheet folded into the
  description prose, and it added to the fixed-footer clearance list.
- `docs/calendar-events-feature.md` — §6.2's detail-sheet action list, §6.3's
  editor-sheet header and description bullets, several §6.6 bullets, the same
  header phrase inside the v29 templates addendum, and a new
  **`## Addendum (2026-08-31): editing event descriptions`** carrying the full
  mechanics.
- `.claude/skills/calendar-events/SKILL.md` — the header rule in both places
  it appeared, the money bullet extended with the by-omission mechanism, and
  three new hard rules (the sheet + its footer clearance, the loop's two
  guards, blank-day vs. reset).

Two pre-existing staleness bugs were found and fixed while editing, neither
caused by this change:

1. `calendar-events-feature.md` §6.6 said detail-sheet checkbox tapping was
   enabled "only for `OneTimeRecurrence` events" — it has been *one-time **or**
   per-occurrence-on* since v24/v28, and `SKILL.md` said so correctly. That
   bullet was never updated when the occurrence table shipped, and leaving it
   would have put a self-contradicting doc directly beside §4.1's new caption,
   which only makes sense under the two-condition rule.
2. `SKILL.md`'s detail-sheet action list named only edit / open-note; it
   predated `skipOccurrence` (v30) as well as `editDescription`.
