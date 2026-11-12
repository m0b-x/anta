# Share Surfaces — ANTA

**Status: PLAN — 2026-11-12. Nothing is built. The mock is published
(https://claude.ai/artifact/E5Zm8rPv5hGLk2V5fKphPt); decisions D1–D17, D19
and D20 are the lead's recommendations and wait for the owner's answers
(§4); D18 is the owner's (2026-11-12: how shared things look is a
setting), and §13 answers his question about several people.** This is
the design record for the surfaces the sharing foundations left out
(`cloud-sharing-foundations.md` §1, §11): how a person shares a category,
an event or a folder with their paired partner, and how what the partner
shares shows on their phone. It covers the roadmap's E1's switch and badge,
E6 (a whole category), E7 (a notice), N1's read-only editor and the place
for shared folders (`cloud-multi-user-roadmap.md` §7, §8), and it adds one
piece the foundations do not have: a category as a thing that can be
shared (§7). The partner never edits (E5, N3 stay out).

## Contents

1. How to run this
2. Why
3. The model
4. Decisions
5. Before anything is built
6. The spec — every surface
7. The category grant — what the foundations gain
8. Behaviour: must not change, deliberately changes
9. Facts from the tree
10. Slices
11. Definition of done
12. Deferred
13. More than two people

---

## 1. How to run this

Load `anta-context`, `ui-language`, `ui-revamp`, `delegation`, `verify`;
`calendar-events` + `calendar-ui` for slices A, C, D; `drift-migrations`
for slice B; `markdown-engine` for slice E; `l10n` for every slice; `qa-emulator`
for slice F. Read this record **by section**: a slice needs its part of §6,
§8 and §9, and slice B needs §7 with `cloud-sharing-foundations.md` §3–§7
beside it.

- A Fable 5.2 session at `high` leads: it takes the owner's answers into
  §4, writes each brief, runs the whole-suite gate after each slice.
- Per slice: one `designer` first for A, C and E (it renders the real
  surfaces and returns the exact spec — the mock's bars and the browser's
  root are schematic, §6), then one `implementer`, one `reviewer`; a
  `design-reviewer` after the code review of A, C and E; one `qa-runner`
  for the device pass in F.
- Slice B changes who can read what on the server. Each part of the
  foundations had a privacy hole that only its independent review found
  (`cloud-sharing-foundations.md` §12). B's review is not optional, and the
  owner says whether it is `reviewer` or `fable-max`.
- The gate after every slice: `dart analyze lib` clean; the whole
  `flutter test --reporter failures-only` green, foreground, one run;
  `flutter gen-l10n` and an empty `untranslated.txt` when an ARB changed;
  the rules suite when `firestore.rules` changed (`flutter test
  test/firestore/rules_test.dart --tags firestore-rules --run-skipped`,
  with `firebase emulators:start --only firestore --project
  alexs-note-tracking-app --config firebase.emulators.json` up); §8's
  list re-read against the diff.
- Never commit unasked. At each slice boundary: the number of uncommitted
  files and a ready commit by path.

---

## 2. Why

The foundations are complete and proven on two phones (`qa pass share`
7/7), and nothing in the app can use them: the two calls that set a share
are reached only by tests and the QA seam
(`test_driver/qa_agent.dart:392`, `:407`). On the receiving phone nothing
explains itself: a partner's event opens in the ordinary editor and its
save does nothing, a partner's note opens in the ordinary editor and its
save fails as `SharedRowException`, "New note" inside a shared folder
fails the same way (`cloud-sharing-foundations.md` §11, "The partner's
screens are not read-only yet"). No surface asks `SharedRowDao.isShared`
today — a grep of `lib/pages`, `lib/widgets`, `lib/bloc` and
`lib/controllers` finds no caller.

The first real request (the owner, 2026-11-12): his partner wants to share
**event categories** with him. A category cannot carry a share today: the
mark exists on `calendar_events` and `folders` only, so she would have to
switch on every event, and every new one.

---

## 3. The model

One pair, so there is never a person to pick: the control is a switch
named after the partner.

- **One verb on the thing itself.** "Share with {name}" is a switch in the
  category editor and the event editor, and an entry in a folder's menu.
- **One page that lists everything**, both directions, and ticks
  categories in bulk: Settings → Sync & sharing → the Pairing row.
- **Share a container and what is added later follows.** A category for
  the calendar, a folder for notes. One event is the exception switch.
- **Three promises the copy repeats**: nothing is shared until you switch
  it on; the partner reads and never changes; switch it off and it leaves
  their phone.

| Shared thing | The mark | What follows it | Built? |
| --- | --- | --- | --- |
| a category | `calendar_categories.shared_pair` | its definition (name, colour, icon); every event in it, with their skipped days and per-day texts | **no — §7, slice B** |
| an event | `calendar_events.shared_pair` | its skipped days and per-day texts | yes (F1) |
| a folder | `folders.shared_pair` | every folder and note under it | yes (F1) |
| a note | — | — | no; deferred (§12) |

An event is shared when its own mark is set **or** its category's is.
Presence marks, alerts, counters and the per-note currency stay personal
on both phones (foundations decision j, D18).

---

## 4. Decisions

The mock's lettered questions, numbered here. Each row is the lead's
recommendation (2026-11-12); the owner's answer replaces "recommended"
with "owner, <date>". A later change appends a row, nothing is rewritten.

| # | Decision | Why |
| --- | --- | --- |
| D1 | Sharing a category shares every event in it, now and later, with the category's name, colour and icon. *Not* a one-time copy of the category list. | It is E6 as the roadmap wrote it, and the only reading under which a new event needs no second act. **The owner's sentence can be read the other way — confirm first.** |
| D2 | Containers first: category, folder. One event is the exception. One note is deferred. | Fewest acts for the request; a note cannot stand outside a folder (§12). |
| D3 | Both entry points: the switch on the thing, and the Sharing page with its tick list. | In context is where a person thinks of it; the page is where they check it. |
| D4 | An event in a shared category is always shared; its switch shows on and locked, with the category named. No per-event "keep private". | One sentence explains it; an override is a third state on every event (§12). |
| D5 | No confirm dialog. The caption says what the partner will see; a snackbar offers Undo. | Reversible, and the partner's phone reads at most every five minutes. |
| D6 | Not paired: no share control anywhere. | Most users never pair; a dead row in every editor is noise. The roadmap's E1 says the same. |
| D7 | Paired, database not syncing: the row stays, dimmed, "Turn on sync to share"; a tap opens Sync & sharing. | The capability exists and one step is missing — disabled, not hidden. |
| D8 | Today's "Share note" / "Share folder" (a file through the system share sheet) are relabelled "Send a copy". Keys and behaviour stay. | "Share" must mean one thing. |
| D9 | Marks: what I share carries `Icons.group_rounded`; what the partner shares carries their avatar (`UserAvatar`). Both speak their meaning in semantics. *Superseded in part by D18: the partner's mark is one of three looks, and mine has a switch.* | Direction readable at a glance; never colour alone. |
| D10 | The partner's own categories show under "From {name}" in the Categories page and the filter lists, read-only, never in the picker for my events. A built-in they share (`gym`) is my `gym`: my colour, my row. | Built-in ids are the same on every install (`calendar_categories_table.dart`), and the reader never lets a shared row take the place of my own (`SharedRowRefused`). Separate built-ins would need owner-aware ids in every filter and saved view. |
| D11 | The partner's events are left out of my report, goals, digests and presence figures, and inherit none of my category alerts. | They are the partner's time; and an alert nobody asked for must never arm (`calendar.md`). |
| D12 | A partner's event opens a read sheet, not the editor: its facts, my own alerts, "Copy to my calendar". | A form at 38 % is unreadable; alerts on a shared event are mine by design. |
| D13 | The partner's folders stand in a "From {name}" section at the end of the root. | The reader already places them at the top level (`SharedRowDao.placeFolders`); a section costs no tap. |
| D14 | A partner's note opens in the editor, read-only: no keyboard, no markdown bar, one "From {name} · Read only" line, "Copy to my notes" in the menu. | The live editor is the renderer; a second read page would drift from it. |
| D15 | Freshness as built — at start, on "Sync now", every five minutes while open — plus one read when the Sharing page opens. | A live listener re-reads the whole shared set whenever it re-attaches (foundations §11). |
| D16 | "Stop sharing everything" on the Sharing page clears every mark and keeps the pair. | Otherwise the only fast exit is Unpair, which also ends what the partner shares. |
| D17 | Copy never puts a possessive on the name ("From Maria", never "Maria's event"). | German and Romanian decline names; a placeholder cannot. *The mock's read sheet and note line were drawn with the possessive first and corrected.* |
| D18 | **Owner, 2026-11-12:** how shared things are shown is a user setting, for the calendar and for notes separately — "maybe we can do an outline for calendar events or we can choose to show them normally … same with the notes". Events shared with me: Outlined · Avatar · Like mine. Notes shared with me: Avatar · Like mine. A switch for the sign on what I share. Supersedes D9's fixed marks (§6.6). Defaults, recommended: Outlined, Avatar, on. | Outlined is the only look the month grid can show, where a row's avatar has no room. Notes get no outlined look: a note row has no glyph and a folder's glyph is already an outline (`folder_row.dart:137`). |
| D19 | The three settings live on the Sharing page and are found by the settings search; not under the calendar's Appearance page. | One place for everything about sharing; the appearance page is about my own calendar. |
| D20 | Several people: no group type is built now; every surface is drawn for an audience that is one person today (§13). | The pair is already a member list and the rules check membership; a second kind of group would be a second thing to revoke. |

Settled by the foundations and not reopened: the partner keeps nothing
when a share ends (decision g); the partner cannot edit (scope,
2026-11-11); a database shares into one pair (decision c).

---

## 5. Before anything is built

### 5.1 The owner's steps (no build)

In this order; each is already named in `cloud-multi-user-roadmap.md`.

1. **The region move (R1)** — `eur3`. It deletes the live database, so it
   comes before the partner's data reaches the cloud; a location cannot be
   changed later without every device uploading again.
2. **The rules and indexes deploy**, still owed from the foundations:
   `firebase deploy --only "firestore:rules,firestore:indexes" --project alexs-note-tracking-app`
   (quoted, in PowerShell). After it only the current build can pair.
   Slice B changes both files again — a second deploy follows it (§7.4).
3. **The same build on both phones.** Wire 47 today, wire 48 after slice
   B: a phone on an older build pauses as "Update ANTA" and shares nothing.
4. **Both people signed in, each with "Sync this database" on.** A share
   leaves through the sharer's sync and arrives through the reader's: a
   phone whose database does not sync receives nothing.
5. **Pairing proven on the live project (E0)** — invite, redeem, each sees
   the other, either ends it. Pairing shipped 2026-08-17 and has no
   recorded run against the live database since it was created.
6. Not blocking: the ten commits on `main` are not pushed; D2's device
   check (an account deleted while its pair is active) is still owed.

### 5.2 What the code lacks

- **A category cannot be shared** — §7, slice B: schema v56, wire 48, the
  rules and one index, the reader's sixth table, the fences.
- **No surface knows a row is the partner's.** `CalendarEvent`,
  `CalendarCategory` and the browser's items carry no "from the partner"
  flag; the services load every row alike (`CategoryService._load`,
  `category_service.dart:186`, reads `getAll()` with no owner in sight).
- **Nothing gathers "can I share, and with whom"**: the pair is in
  `PairingService.status` (`pairing_service.dart:172`), whether the
  database syncs is in the sync services, and the three marks are set
  through three services. Slice A adds the one facade (§6.1).
- **The note editor has no read-only mode**: the fork's `CodeEditor` takes
  `readOnly` (`packages/re_editor/lib/src/code_editor.dart:306`), and
  `ModernEditorWrapper` passes a literal `false`
  (`modern_editor_wrapper.dart:1091`).
- **An inherited category alert would arm on a partner's event** whose
  category id is one of mine (a shared built-in): `EventAlerts.effectiveFor`
  (`lib/constants/event_alerts.dart:157`) projects a category's alerts
  onto every event of that id and is handed nothing about whose event it
  is. Read from the code, not yet reproduced — slice A pins it with a
  failing test first. D11.

---

## 6. The spec — every surface

Numbers are the constants a surface reads, never literals. The mock is one
page; its app bars, the calendar grid and the browser's root are schematic
and the `designer`'s render replaces them before each visual slice.

### 6.1 The share service (no pixels)

`lib/services/share_service.dart`, on the `DatabaseLifecycle` reset
contract (pairing state is per database), with a fake for every suite.

- `ShareAvailability`: `notPaired` · `notSyncing` · `ready`, with the
  partner's `PairProfile?` and the pair id; `changes` as a stream that
  **replays its last value** (the replaying-stream rule: a fake of it
  replays too).
- `setCategoryShared(id, on)`, `setEventShared(id, on)`,
  `setFolderShared(id, on)` — the only callers of the three mark writers
  outside tests; each takes the pair id from `PairingService.status`, so a
  surface never holds one. After a write it asks for a sync run, so the
  share leaves now rather than at the next cadence tick.
- `stopAll()` — clears every mark of this database (`clearOtherPairs(null)`
  on the three DAOs, stamped and queued like any edit).
- `overview()` — what the Sharing page lists: my marked categories, my
  singly marked events, my marked folders; the partner's categories, their
  events that came without a category of theirs, their top-level folders;
  when the shared read last finished; `shared_newer_wire`; the count of
  rows refused for an id of mine.
- `isFromPartner(table, id)` — over `SharedRowDao.isShared`.

A thin `ShareBloc` (`lib/bloc/share/`, sealed + `Equatable`) serves the
Sharing page. The editors and menus receive `ShareAvailability` from their
opener, as the event editor receives `dayLoad` today, and return the
choice in their result; the flow that saved the draft calls the service.

### 6.2 The Sharing page

Idiom: **the settings kit** (`SettingsSectionList` under `SettingsAppBar`).
`lib/pages/sharing_page.dart`, pushed from the Pairing row of
`sync_settings_page.dart:306`, which keeps its section and changes its
words while paired: title "Paired with {name}", description the summary
("3 categories, 1 folder" — plural keys; "Nothing is shared yet" at zero),
a chevron. Unpair moves onto the new page.

Top to bottom, title "Sharing with {name}":

1. **YOU SHARE** — three entries, each title + one-line description + chevron:
   Categories (the names, cut with an ellipsis; "None"), Single events
   ("2 events" / "None"), Folders (names / "None"). Intro line under the
   section: "{name} sees these and cannot change them."
   - Categories opens §6.3.
   - Single events and Folders open a filler sheet listing the marked
     rows, each with a trailing ✕ that un-shares it (snackbar + Undo); the
     folders list ends in `FormActionRow` "+ Share a folder", which opens
     the app's folder picker. The events list is empty-stated with one
     line: "Share an event from its editor."
2. **{NAME} SHARES WITH YOU** — the same three entries, read-only lists;
   the section label's trailing slot says "Updated {when}"
   (`formatSyncMoment`). Intro: "Read-only. They leave when {name} stops
   sharing." When this database does not sync, the section's entries dim
   and the intro reads "Turn on sync to receive."
   Two notice lines appear here and nowhere else, each only when true:
   "Update ANTA to see everything {name} shares" (`shared_newer_wire`) and
   "{n} items could not be shown" (rows refused for an id of mine).
3. **HOW SHARED THINGS LOOK** (D18, §6.6) — two `settingsChoiceRow`s,
   "Events shared with you" (Outlined · Avatar · Like mine) and "Notes
   shared with you" (Avatar · Like mine), and a switch, "Mark what you
   share" ("A sign on your shared categories, events, folders"). The kit
   stacks a choice row's segments when a word would break (German at 2.0).
   Each writes at once; the calendar and the browser repaint from the
   settings state.
4. A last group: **Stop sharing everything** ("You stay paired";
   `AppDialogs.confirm`, since it is the one bulk act) and **Unpair** (the
   existing flow and dialog, moved).

Every entry keeps its place and height in every state; "None" rows stay.
The page asks for one shared read as it opens (D15).

### 6.3 The category tick sheet

`CategoryPickerSheet.pickMulti` — the app's one choosing surface — with a
title ("Share categories"), a caption under the header ("{name} sees every
event in a ticked category, new ones too. Only you can change them.") and
each row's event count. It lists my categories, built-ins and archived
ones included, as the picker lists them today; never the partner's. Done returns the set; the page diffs it against the marks and
calls `setCategoryShared` per change; one snackbar ("Sharing Work, Travel
with {name}" / "No longer shared: Gym") with Undo. `pickMulti` never
collapses an empty pick — an empty set here means "share none".

### 6.4 The category editor

One new section between the look group and ALERTS:
`FormSectionLabel` "SHARING" over a `FormRowGroup` of one
`FormSwitchRow(glyph: Icons.group_rounded, label: "Share with {name}",
subtitle: …)`. Subtitle: off "Only you see these events"; on "All {n}
events, and new ones" (plural; "New events are shared" at zero). The
switch is part of the draft and is written after Save. Absent when not
paired; dimmed with "Turn on sync to share" when the database does not
sync. A new category can be created already shared.

The Categories page (`calendar_categories_page.dart`): a shared category's
caption gains "Shared" beside "Built in" / "Alerts on" and the row shows
the group mark; the ⋮ menu gains "Share with {name}" / "Shared with
{name}" ✓ as a `FormMenuChoiceItem` between Edit and Archive. A third
section, "From {name}", lists the partner's own categories: avatar, name,
event count, the partner's avatar, no handle, no menu, no tap. Reorder and
"sort A–Z" never touch that section.

### 6.5 The event editor

One `FormSwitchRow` at the end of the DETAILS group, after Linked note
(`event_editor_sheet.dart:3098`): glyph `Icons.group_rounded`, label
"Share with {name}" in every state, a subtitle that always exists so the
row is two lines (`FormMetrics.twoLineRowMinHeight`) in every state:

| State | Subtitle | Switch |
| --- | --- | --- |
| off | Only you see this event | off |
| on | {name} sees it, read-only | on |
| its category is shared | On for everything in {category} | on, disabled |
| database not syncing | Turn on sync to share | off, disabled; the row's tap opens Sync & sharing |
| not paired | — | the row is absent |

The subtitle follows a category pick at once, as the inherited alerts do.
The choice rides the draft: dirty-checking, `_leave()` and Save are
untouched, and `EventEditorResult` carries it to the flow, which calls
`setEventShared` after the event is stored (a new event has no id before).
A template never stores the choice.

### 6.6 How shared things are told apart — a setting (D18)

Three settings through `SettingsService` + `SettingsKeys`, read by the
widgets from the settings state they already rebuild on — never looked up
per row.

| Key | Values | Default |
| --- | --- | --- |
| `shareEventLook` | `outlined` · `avatar` · `plain` | `outlined` |
| `shareNoteLook` | `avatar` · `plain` | `avatar` |
| `shareMarkMine` | on · off | on |

**Events shared with me**

- **Outlined**: `EventAvatar` (`lib/widgets/event_avatar.dart`) gains an
  outlined cut — no fill, a ring in the category colour
  (`FormMetrics.shareOutlineWidth`, new), the icon in that colour — used
  wherever the event's avatar is drawn: the day list, the agenda, the
  overview, the read sheet's title row. The month grid's markers gain a
  hollow twin for each `CalendarMarkerStyle` (`bars`, `dots`,
  `calendar_appearance.dart:27`), and the day rail's marker the same.
  A partner's event never tints a cell: `CalendarCellStyle` (`:167`) is
  the look of *my* day — the lead's default, lettered for the owner in the
  `designer`'s spec.
- **Avatar**: drawn like mine, with the partner's `UserAvatar`
  (`RowMetrics.partnerAvatarRadius`, new) at the row's end. Lists only —
  the grid shows no difference, which is why Outlined is the default.
- **Like mine** (`plain`): no visual difference.

**Notes shared with me**

- **Avatar**: the partner's avatar before the count on a folder row and at
  the end of a note row — in a folder, in All notes, in Recent, in search.
- **Like mine**: none.
- No outlined look (D18's reason). The root's "From {name}" section (D13)
  stands in every look: it is where the folders are, not how they look.

**What I share** (`shareMarkMine`): `Icons.group_rounded` as a small glyph
(`RowMetrics.shareMarkSize`, new) in `onSurfaceVariant` before the row's
count or chevron — a shared category's row (the Categories page, the
picker, the filter lists), my shared event's row in the day list, the
agenda and the overview (shared singly or through its category), a shared
folder's row. A note inside a shared folder is not marked; its folder is.

**Whatever the look**: semantics always say "From {name}" or "Shared with
{name}"; the read sheet and the note's read-only line always name the
person; write actions are disabled all the same. A look is never the only
carrier of "this is not mine". The ring and the hollow marker meet 3:1
against their ground in both themes for every category colour — measured
from tokens by the `designer`, re-measured by the `design-reviewer`.

### 6.7 A partner's event — the read sheet

`lib/widgets/shared_event_sheet.dart`, a **sub-sheet** (content-tall under
`FormMetrics.sheetHeightFactor`, unguarded, ✕ with the `close` tooltip, an
empty trailing slot). `EventSheetsFlow.openEditor`
(`event_sheets_flow.dart:398`) opens it instead of the editor when the
event is the partner's.

1. Header: "From {name}".
2. A group: `FormReadTitleRow` (the event's `EventAvatar`, its title, the
   category name as caption, the partner's avatar trailing); read rows for
   Date, Time (or "All day") and Repeat in the editor's own words
   (`FormPickerRow` with `onTap: null`, `showChevron: false`); the
   description as a read cell when there is one — for a recurring event
   the text of the opened day.
3. `FormSectionLabel` "YOURS" over a group: my own alerts on this event
   (the event editor's alert rows and its Add alert, over
   `EventAlertService` — rows of my own, in my own space) and nothing
   inherited.
4. A group: `FormActionRow` "Copy to my calendar" — creates an event of my
   own from the facts shown (`createX` stamps now, a new id, no mark; a
   category I do not have becomes `other`), then opens it in the editor.
5. Caption: "Only {name} can change this event. Your alerts stay on your
   phone."

Presence on a partner's event is not offered in this generation (§12).

### 6.8 The partner's events in lists and filters

- The grid, the day list, the agenda and the overview show them, marked
  per §6.6. Swipe and long-press actions that write (delete, skip this
  day, duplicate, move) are disabled on them.
- The filter lists (`calendar_filter_sheet.dart:485`,
  `agenda_filters_sheet.dart:491`) list the partner's own categories under
  a "From {name}" header; hiding one works as for any category id. A
  shared built-in is hidden with mine (D10; the separate switch is §12).
- Report, goals, digests, presence figures and inherited category alerts
  skip them (D11): one predicate on the model, applied where each of those
  reads its events.

### 6.9 A folder — the menu

`folder_overflow_menu.dart:138` and the row actions of `folder_row.dart:284`
gain one entry directly above today's share entry: "Share with {name}"
(`Icons.group_rounded`), which reads "Shared with {name}" with a trailing
tick while the folder's own mark is set. A folder inside a shared folder
shows the entry disabled, "Shared with {name}", since the outer mark
covers it. Absent when not paired; disabled when the database does not
sync, or the folder is the partner's. A snackbar with Undo follows either
way. Today's entries keep their keys and action and read "Send a copy"
(D8) — `note_overflow_menu.dart:124`, `note_row.dart:356` too.

### 6.10 The partner's folders in the browser

- **Root**: after `addGroup(folders, l10n.folders)`
  (`optimized_folder_content_page.dart:2151`), a group "From {name}" of the
  folders whose owner is the shared owner; they leave the Folders group.
  Rows are `ContentRowShell` rows drawn in the notes look (§6.6); no drag
  handle, never part of a reorder or a selection.
- **Inside** a partner's folder, at any depth: the create bar's buttons
  are disabled; row actions that write (rename, move, label, delete) are
  disabled and "Send a copy" stays; the folder's menu keeps Sort by and
  Settings. Sort preferences are mine and keep working.
- **All notes, Recent, search**: the partner's notes appear, marked.
- A row that leaves while its page is open is already announced as gone
  (foundations §5.9); a partner's folder open when its share ends pops to
  the root with one snackbar: "{name} no longer shares this folder."

### 6.11 A partner's note — read-only

`optimized_note_editor_page.dart` asks `ShareService.isFromPartner` before
its first frame and, for a partner's note:

- passes `readOnly: true` through a new `ModernEditorWrapper.readOnly` to
  `CodeEditor` (no keyboard, no caret edits, selection and copy stay);
- builds no `MarkdownBar` and no vocabulary bar; the body takes the room;
- never starts `NoteSaveCoordinator` / auto-save, so `updateNote` is never
  called and `SharedRowException` never surfaces;
- shows one line under the bar, the partner's avatar and "From {name} ·
  Read only" (`surfaceContainerHigh` light / `surfaceContainer` dark,
  `RowMetrics.secondLineFontSize`, `onSurfaceVariant`; one height, a
  `FormCaptionSlot`);
- its ⋮ menu: Edit title, Move, Label and Delete disabled; "Copy to my
  notes" (a new note of my own in a folder I pick, stamped now) and "Send
  a copy" enabled;
- a task checkbox does not toggle; a wiki link, a tag and a money line
  behave as in any note; counters shown are mine (decision j).

### 6.12 Notices

- A share I start or stop: snackbar with Undo (`CustomSnackbar`, or
  `OverlaySnackbar` from inside a sheet and on the editor and calendar
  pages).
- "New from {name}" (E7): when a shared read stores a root this phone had
  not held — a category, a singly shared event, a top-level folder — one
  snackbar while the app is open: "{name} shares Shifts with you" with
  View (the Sharing page). Never a system notification; a closed app
  learns at its next open.

### 6.13 Copy and keys

New keys, en shown; de and ro written with them, `{name}` never declined
(D17), with a fallback word for a partner without a profile
(`sharePartnerFallback` "your partner").

| Key | en |
| --- | --- |
| `shareWithPartner` | Share with {name} |
| `sharedWithPartner` | Shared with {name} |
| `shareFromPartner` | From {name} |
| `sharingWithTitle` | Sharing with {name} |
| `shareYouShare` / `sharePartnerShares` | You share / {name} shares with you |
| `shareRowCategories` / `shareRowEvents` / `shareRowFolders` | Categories / Single events / Folders |
| `shareNone` | None |
| `shareYouShareCaption` | {name} sees these and cannot change them. |
| `sharePartnerSharesCaption` | Read-only. They leave when {name} stops sharing. |
| `shareNeedsSync` / `shareNeedsSyncReceive` | Turn on sync to share / Turn on sync to receive |
| `shareEventOff` / `shareEventOn` | Only you see this event / {name} sees it, read-only |
| `shareThroughCategory` | On for everything in {category} |
| `shareCategoryOff` / `shareCategoryOn` | Only you see these events / All {count} events, and new ones (plural) |
| `shareCategoriesTitle` / `shareCategoriesCaption` | Share categories / {name} sees every event in a ticked category, new ones too. Only you can change them. |
| `shareStarted` / `shareStopped` | Sharing {what} with {name} / No longer shared: {what} |
| `shareStopAll` / `shareStopAllDesc` / `shareStopAllConfirm` | Stop sharing everything / You stay paired / Stop sharing everything with {name}? |
| `pairingSharingSummary…` | "3 categories, 1 folder" from plural parts |
| `sharedEventYours` / `sharedEventCopy` / `sharedEventCaption` | Yours / Copy to my calendar / Only {name} can change this event. Your alerts stay on your phone. |
| `sharedNoteLine` / `sharedNoteCopy` | From {name} · Read only / Copy to my notes |
| `shareNewFromPartner` | {name} shares {what} with you |
| `shareUpdateApp` / `shareNotShown` | Update ANTA to see everything {name} shares / {count} items could not be shown |
| `shareFolderGone` | {name} no longer shares this folder |
| `shareLookSection` | How shared things look |
| `shareEventLook` / `shareNoteLook` | Events shared with you / Notes shared with you |
| `shareLookOutlined` / `shareLookAvatar` / `shareLookPlain` | Outlined / Avatar / Like mine |
| `shareMarkMine` / `shareMarkMineDesc` | Mark what you share / A sign on your shared categories, events, folders |
| `shareMarkMineLabel` / `shareMarkPartnerLabel` (semantics) | Shared with {name} / From {name} |
| `shareNote`, `shareFolder` (values only) | Send a copy |

`SemanticsIds` (kebab-case, never renamed): `sharing-page`,
`sharing-mine-categories|events|folders`,
`sharing-theirs-categories|events|folders`, `sharing-look-events`,
`sharing-look-notes`, `sharing-mark-mine`, `sharing-stop-all`,
`sharing-unpair`, `share-categories-sheet`, `category-editor-share`,
`category-menu-share`, `event-share`, `folder-menu-share`,
`row-action-share`, `shared-event-sheet`, `shared-event-add-alert`,
`shared-event-copy`, `shared-note-line`, `browser-section-partner`.

---

## 7. The category grant — what the foundations gain

The foundations' design holds; a category becomes a third root beside an
event and a folder. Read `cloud-sharing-foundations.md` §3 (the grant) and
§4 (the wire and the rules) first: every rule below is that section's,
applied to one more table.

### 7.1 Local (schema v56)

`calendar_categories` gains `shared_pair TEXT NULL` and `shared_stamp TEXT
NULL`, with the partial index `WHERE shared_pair IS NOT NULL`, exactly as
v52/v53 gave them to events and folders. `CalendarCategoryDao.setSharedPair`
is one stamped write of the mark and its stamp that leaves `updated_at`
alone (decision l) and clears every other pair's mark in all three tables
(decision c); `clearOtherPairs` joins the reader's look at the pair;
`SyncDao.anyShareMark` reads the third index. `CategoryService.setShared`
runs on the service's one mutation chain. v56 also drops and re-creates
the fences (a fence is created only when absent — the v55 lesson).

### 7.2 What is shared (decision b, extended)

| Row | Its document carries the grant of |
| --- | --- |
| a category | its own `shared_pair` |
| an event | its own `shared_pair`, else its category's |
| a skipped day, a per-day text | their event's, by the rule above |
| category alerts, category profiles, templates | never — personal |

One statement answers it — `COALESCE(e.shared_pair, c.shared_pair)` over a
join to the event's live category — behind `CalendarEventDao.sharedPairsOf`
(`calendar_events_binding.dart:30` stops reading the row's own column
alone; the two day-row bindings already go through `sharedPairsOf`).

### 7.3 Keeping documents in step

The foundations' re-send rule (`CrdtWrite.requeueRows`, no new stamp,
tombstones included, real writes first) gains three triggers:

- a mark set or cleared on a category → every event of that category and
  their day rows;
- an event's category changed where the grant differs between the two —
  `upsert` (`calendar_event_dao.dart:64`), `reassignCategory` (`:322`, the
  path a category's delete takes through
  `CalendarCategoryDao.tombstoneCascade`, `calendar_category_dao.dart:258`)
  and `importAll` (`:615`) → the event's day rows; the event itself is the
  write, except in `reassignCategory`, a set update that must queue the
  events it moved;
- a merge that changes a category's mark, or an event's category
  (`mergeRemoteEvent`, `:375`) → the same dependants on the device that
  merged it.

`_Puller._resayShares` and `_Pusher._regranted` take `calendar_categories`
as a sixth table, and an event's `shareStamps` becomes the newer of its
own stamp and its category's `shared_stamp`.

### 7.4 The wire, the rules, the index

- **Wire 48** (`DatabaseSchema.syncSchemaVersion`,
  `database_schema.dart:16`): a build at 47 would drop a category's mark
  on its next push of that row and would encode that category's events as
  private. The space refuses it as it refused 46. A 47 → 48 database reads
  `calendar_categories` again from the start, once, as 46 → 47 read events
  and folders (`shareWireVersion`, `_WireCutover.marks`).
- **Rules** (`firestore.rules`): `shareable()` (`:341`) gains
  `'calendar_categories'`; one more read block beside `:403`–`:415`,
  `match /{path=**}/calendar_categories/{rowKey} { allow get, list: if
  sharedWithCaller(); }`. Nothing else: `activeMember` and the pair's
  shape are untouched. The rules suite gains the category's probes — the
  partner's query, its count, a stranger, an ended pair, a query without
  the pair filter.
- **Index** (`firestore.indexes.json`): one collection-group entry for
  `calendar_categories` — `sharedPair ASC, ownerId ASC, pushedAt ASC`.
- **The owner deploys both again after slice B**, before the build that
  shares a category reaches a phone.

### 7.5 The reader, and whose category is whose

- `sharedTables` (`lib/database/crdt/synced_tables.dart:66`) gains
  `'calendar_categories'` **first** — parents first, so an event never
  arrives before the category that draws it. The reader, its cursors, its
  count and its daily read follow the list.
- `mergeShared` for the category binding: the owner's copy wins, stored
  under the partner's `owner_id`, the mark itself not stored.
- **A category under an id of mine is refused** (`SharedRowRefused`), like
  any shared row over a row of my own. For a built-in that is always the
  case, and it is the design (D10): the partner's `gym` events resolve to
  my `gym` (`CalendarCategories.resolve`, `calendar_categories.dart:159`).
  This refusal is expected and must not count in "{n} items could not be
  shown".
- **The fences** follow `sharedTables`
  (`shared_row_fences.dart:58`): a partner's category cannot be changed or
  deleted here. Two more are written by hand, as the "_into" and "_onto"
  fences are: an event of my own cannot take a partner's category, and
  neither can a template.
- **The catalogue** (`CategoryService._load`): `CalendarCategory` gains a
  transient `fromPartner` (the row's owner is the shared owner; never
  stored, never exported). `CalendarCategories.visible` and everything the
  pickers, the reorder, `deleteCategory`'s targets and the sort use
  exclude such rows; `resolve` and the filter lists include them.
- **Exports** leave a partner's categories out and never write the mark
  (decision i), as the event export does
  (`calendar_event_service.dart:732`).

### 7.6 Tests slice B ships with

The DAO suite for the mark (set, clear, other pairs, the stamp register);
`CrdtMerge.mergeMark` on a category; the encode derivation for an event
with and without its own mark; each re-send trigger of §7.3, the set
update of `reassignCategory` included; the cutover 47 → 48; the reader
storing, refusing (built-in) and removing a category; the fences on a
fresh install and on an upgraded one; the statement-count pins; the
upgrade chain to v56; the rules suite. And the device flow before the
slice is called done — the first two-guest run found two defects sixteen
thousand tests had not: `qa share category "<name>" [--off]` beside the
event and folder seams (`tool/qa/qa.dart:7758`,
`test_driver/qa_agent.dart:177`) and one flow in `tool/qa/flows/share/`.

---

## 8. Behaviour

### Must not change

- Nothing is shared without a switch a person flipped; a new pair starts
  with nothing shared.
- The grant as built: one mark and its stamp on a root, everything under
  it derived at encode; a mark is metadata; private wins a disagreement.
- A partner's rows: read-only in the database, never pushed, removed when
  the grant ends; what a person added of their own stays theirs.
- An account's own sync — every document it writes for itself, every pull
  of its own space, the cost of an idle launch. An account that never
  paired makes no extra call and sees no new row anywhere.
- The pairing sheet and its code flow; `PairingBloc` apart from `SyncBloc`;
  the Sync & sharing page's other sections and their order.
- Categories: built-ins keep their ids and cannot be deleted; `updateCategory`
  never writes `sort_order` / `is_built_in` / `is_hidden`; the service's
  one mutation chain; `CategoryPickerSheet` the one choosing surface.
- The event editor: every existing row, its order, the draft's equality,
  `_leave()`, Save; alerts stay opt-in and never arm unasked.
- The browser: positions, sort preferences, move history, selection; the
  two smart rows; a note cannot live at the root.
- The note editor's typing path for my own notes: no new check per
  keystroke, no BLoC on it.
- File sharing through `ImportExportBloc` and `shareExport`; archives and
  backups hold only my rows and no mark.
- `qa pass share` 7/7 and its seams; `qa pass calendar`, `browser`,
  `settings`, `sync`.

### Deliberately changes

- The Pairing row's words while paired, and where Unpair lives.
- The labels of the two file-sharing entries (D8).
- A partner's event opens a read sheet; a partner's note opens read-only;
  write actions on a partner's rows are disabled where they did nothing.
- A partner's events leave the report, goals, digests and presence
  figures, where the foundations' build counts them like any event.
- `sharedTables` has six entries; wire 48; schema 56.

---

## 9. Facts from the tree

Re-grep before editing; lines are of `81f308d3`.

| What | Where |
| --- | --- |
| Mark writers | `CalendarEventService.setShared` `calendar_event_service.dart:616`; `FolderStorageService.setFolderShared` `folder_storage_service.dart:279` |
| "Is it the partner's" | `SharedRowDao.isShared(table, id)` `shared_row_dao.dart:118`; `owner()` `:81` |
| The pair for a surface | `PairingService.status` `pairing_service.dart:172` (`PairingStatus.pairId`, `.partner`, `:30`); `PairingPaired.partner` `pairing_state.dart:72` |
| Shareable tables | `sharedTables` `lib/database/crdt/synced_tables.dart:66`; the reader `sync_shared_reader.dart:22` |
| The grant at encode | `SyncTableBinding.sharedPairs` `sync_table_binding.dart:79`; overrides in `tables/calendar_events_binding.dart:30`, `…occurrences_binding.dart:32`, `…skips_binding.dart:31`, `folders_binding.dart:32`, `notes_binding.dart:62` |
| Versions | `database_schema.dart:4` (55), `:16` (wire 47), `:27` (`shareWireVersion`) |
| Rules, index | `firestore.rules:341` (`shareable`), `:352` (`validShare`), `:403`–`:415`; `firestore.indexes.json:12`–`:48` |
| Fences | `lib/database/migrations/shared_row_fences.dart:58` (generated per table), `:71`–`:89` (by hand) |
| Category catalogue | `CategoryService._load` `category_service.dart:186`; `deleteCategory` `:490`; `CalendarCategories.resolve` `calendar_categories.dart:159`; binding `tables/calendar_categories_binding.dart:9` |
| Event editor | DETAILS group `event_editor_sheet.dart:3097`–`3106`; `show` `:241`; opened by `EventSheetsFlow.openEditor` `event_sheets_flow.dart:398` |
| Category editor | groups `category_editor_sheet.dart:928`–`956` |
| Categories page | menu `calendar_categories_page.dart:549`–`578`; sections `:768`; caption `:821` |
| Filter lists | `calendar_filter_sheet.dart:485`; `agenda_filters_sheet.dart:491` |
| Pairing row | `sync_settings_page.dart:306` |
| Folder menus | `folder_overflow_menu.dart:138`; `folder_row.dart:284`; notes: `note_overflow_menu.dart:124`, `note_row.dart:356` |
| Browser root | smart rows `optimized_folder_content_page.dart:1951`; groups `:2141`–`2152`; `FolderDao.watchFoldersByParent` `folder_dao.dart:1530` |
| Editor read-only | `CodeEditor.readOnly` `packages/re_editor/lib/src/code_editor.dart:306`; the wrapper's literal `modern_editor_wrapper.dart:1091` |
| QA seam | `tool/qa/qa.dart:7758`; `test_driver/qa_agent.dart:177`, `:392`, `:407`; flows `tool/qa/flows/share/01`–`05`; cookbook `.claude/skills/qa-emulator/references/share-pass.md` |
| The looks | `EventAvatar` `lib/widgets/event_avatar.dart:3`; `CalendarMarkerStyle` `lib/models/calendar_appearance.dart:27`, `CalendarCellStyle` `:167`; the folder row's glyph `folder_row.dart:137`; a note row has none (`note_row.dart`) |
| Inherited alerts | `EventAlerts.effectiveFor` `lib/constants/event_alerts.dart:157` |

Nothing is retired: no widget or constant exists twice after this work.
Three metrics are new (`RowMetrics.shareMarkSize`, `partnerAvatarRadius`,
`FormMetrics.shareOutlineWidth`) and the `designer` names their values.

---

## 10. Slices

Each ends with something a person can do or see, the gate, and a commit on
the owner's word. Sizes as the roadmap counts them (S one implementer run,
M two, L three or more).

| Slice | A person can | Holds | Size |
| --- | --- | --- | --- |
| **0** | pair on the live project, both phones syncing | §5.1 — the owner's steps, no build | — |
| **A — what arrives explains itself** | see which events are the partner's, open one without a dead editor, set an alert of their own on it | `ShareService` + fake (§6.1); the transient "from partner" flag on events; the three look settings' keys and the event looks — the outlined `EventAvatar`, the hollow markers, the avatar (§6.6); the read sheet (§6.7); write actions disabled (§6.8); D11's predicate — report, goals, digests, presence, inherited alerts | L |
| **B — a category can be shared** | (through the QA seam) share a category and watch its events arrive, a new one included | §7 whole, with its tests, its rules probes and its device flow; then the owner's second deploy | L |
| **C — share categories** | open the Sharing page, tick categories, see what goes each way; switch one on in the category editor | §6.2 with its look controls, §6.3, §6.4; the sign on what I share (§6.6); the partner's categories in the Categories page and the filters (§6.8); the Pairing row's new words | L |
| **D — share one event** | switch one event on in its editor; see and stop single events on the Sharing page | §6.5; the events list of §6.2 | S |
| **E — share a folder** | share a folder from its menu; read the partner's folders and notes without a failing save | §6.9, §6.10, §6.11; the notes look (§6.6); D8's relabel; the folders list of §6.2 | L |
| **F — notices, guide, proof** | hear that something new arrived; read how sharing works | §6.12; a "Sharing" page in the app guide (`app_guide_content.dart`); the surface flows added to `qa pass share` (tick a category on guest 1, see it marked on guest 2, open the read sheet, un-tick; a folder from its menu; a read-only note), the matrix in dark, `de`, 2.0 on both phone sizes; `qa errors` clean; the docs (§11 last line) | M |

Order: 0, A, B, C — the owner's request is whole after C — then D, E, F.
A comes before B because it needs no schema and the two-guest suite can
prove it at once with the seams that exist; B before C because C's switch
has nothing to write until B lands. D may ride with C if the owner wants
fewer commits. E opens the note editor and the browser, the two pages that
carry the app: it runs alone.

---

## 11. Definition of done

1. On two phones, paired: ticking Work on one shows every Work event on
   the other within one read, marked with the sharer's avatar; an event
   added to Work afterwards arrives with no second act; un-ticking removes
   them all; the other phone's own events, alerts and report figures are
   what they were.
2. An event moved out of a shared category leaves the partner's phone; one
   moved in arrives; deleting a shared category (its events reassigned)
   takes them off the partner's phone unless their new category is shared.
3. A shared built-in category draws in the reader's own colour; a shared
   custom one in the sharer's, under "From {name}"; neither is offered in
   the reader's picker; a reader's event cannot be given the partner's
   category.
4. A partner's event opens the read sheet; an alert added there arms on
   this phone only and survives the share ending as an inert row; "Copy to
   my calendar" makes an event that is fully mine. None of my category
   alerts arm on a partner's event.
5. A shared folder appears under "From {name}" with its notes; inside it
   nothing can be created, renamed, moved, labelled or deleted and nothing
   says "save failed"; a note opens read-only, with no keyboard on tap.
6. Not paired: every editor, menu and page is byte-for-byte today's, and a
   launch makes no extra call. Paired without sync: the rows are there,
   dimmed, and say why.
7. Every share row keeps one height in every state; 48 dp targets; light
   and dark; en, de, ro with `{name}` never declined; text scale 1.3 and
   2.0 with no clipped label — the German "Mit {name} teilen" with a long
   name included; `untranslated.txt` empty.
8. Every new sheet is in `sheet_bottom_clearance_test.dart`; every new row
   has its `SemanticsIds` entry; the Sharing page, the read sheet, the
   tick sheet's caption and the three switches ship with widget suites
   against `ShareService`'s fake; the existing suites of the event editor,
   the category editor, the Categories page, the browser and the note
   editor pass unchanged where behaviour did not change.
9. `qa pass share` green with its new flows; `qa pass calendar`,
   `browser`, `settings` and `sync` green.
10. Docs in the same change: this record's status line and an as-built
    section; `cloud-sharing-foundations.md` §12 for slice B;
    `cloud-multi-user-roadmap.md` §3 (E1, E6, E7, N1 marked) and its
    status; `anta-context/references/sync-and-accounts.md`,
    `calendar-events` and `markdown-engine` references for the facts; one
    rule line in each area skill (a surface asks `ShareService` before it
    offers an edit; the partner's rows never reach a report or an alert).
11. Each look draws as §6.6 says, in light and dark, for every category
    colour and both marker styles; changing it repaints the open calendar
    and the open browser with no restart; with "Like mine" chosen a
    partner's event still opens the read sheet, its write actions are
    still disabled and TalkBack still says "From {name}"; with "Mark what
    you share" off no sign shows and the Sharing page still lists
    everything.

---

## 12. Deferred

Cut on purpose; each with enough to resume from.

- **One note shared by itself.** Needs `notes.shared_pair` (schema, the
  derivation "its own mark, else its folder's", the space's `sharedPair`
  counting notes) and a place on the reader's phone, since a note cannot
  live at the root: a device-local folder under "From {name}" is the
  likely answer. Until then the note menu offers nothing; the guide says
  "put it in a shared folder".
- **A private event inside a shared category** (D4's other option): a
  third state on the event (`shared_pair` set / inherit / refused), a
  third position on the editor's control, and the derivation's `COALESCE`
  made to honour the refusal.
- **"Show {name}'s events" as one filter switch**: a field on
  `CalendarGridFilters` and the agenda's filters, persisted and carried by
  saved filters and views — the only way to hide the partner's events in a
  shared built-in without hiding mine.
- **A singly shared event in a custom category that is not shared** draws
  as `other` on the reader's phone (as built). The fix: the event's
  document carries its category's name, colour and icon while it is shared
  alone.
- **Presence on a partner's event.** The rows are personal and the
  foundations keep them; the read sheet does not offer the control yet.
- **The partner edits** (E5, N3), **more than one partner** (P7), **push
  while closed** (P6): the roadmap's rows, untouched.
- **Expiring a shared copy on a phone that never syncs** (foundations §11):
  unchanged; the Sharing page's "Updated {when}" is what shows its age.
- **"Sharing…" until the sharer's rows are read back** (foundations §11):
  not shown; a new share can be partly private for a moment and errs
  private.

---

## 13. More than two people

The owner's question (2026-11-12): "what if we want to share with multiple
people, do we need to create a group type?"

**No new type is needed now, and no surface of this record has to be
redone for it.** The pair already is a group of two: its document holds a
`members` list (`PairRecord.members`, `pair_record.dart:34`), a shared row
names the pair's id, and the read rule asks "is the caller a member, and
is the row's owner a member" (`activeMember`, `firestore.rules`), never
"is the caller the other person". That was foundations decision a — the
grant names the pair, not the person — and it is what makes this cheap.

"Multiple people" is two different pieces of work:

1. **One circle with more than two members** — a family: each sees what
   the others share into it. Rows, marks, the wire and the read rule stay
   exactly as they are. What changes is around them:
   - *joining and leaving*: today a pair is made in one write from one
     invite and ends as a whole (`PairingGateway.createPair`,
     `status: 'ended'`); a circle needs "invite into an existing one" and
     "one member leaves, the rest stay", with the rules for both;
   - *the reader*: it reads one owner (`sync_metadata['shared_owner']` is
     a single value; the fences, the count and the cursors go by it) and
     would read one per other member;
   - *names*: a circle needs a name of its own, and "From {name}" names
     the row's owner, which the reader already stores per row.
   Size L; a design record of its own, built on this one.
2. **Several circles, and a thing shared into some of them** — Work to
   Maria, Birthdays to the family. This breaks foundations decision c ("a
   database shares into one pair") and the mark's shape: `shared_pair`
   becomes a set, and the server query cannot stay as it is — the read
   rule can be decided only for a query that pins the pair by equality
   (`sharedPair == <id>`, foundations §4), which a list of pairs on the
   document does not allow. It needs a grant field per circle or a copy of
   the row per circle, decided on the rules emulator first. Size L and
   more; it is the roadmap's P7.

What this plan keeps open for both, at no cost today:

- `ShareService` speaks of an **audience** — an id, a display name, its
  members' profiles — and hands out a list with one entry. No surface
  holds a pair id or a `PairProfile` of its own.
- Every string takes `{name}`; none assumes one person, and the look
  settings name nobody.
- The share row keeps its place and its height when it becomes a pick row
  ("Share with · Maria, Family ›", opening a tick list) — the mock's last
  strip.
- The Sharing page is already a page per audience; the Pairing section
  becomes the list of them.
- "From {name}" sections and the Avatar look go by the owner of a row,
  not by "the partner".

What it does not do: store more than one pair on a row, or let a third
account join a pair. Both wait for the owner's word and their own record.
