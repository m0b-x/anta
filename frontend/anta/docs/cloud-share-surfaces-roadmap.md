# Share Surfaces — ANTA

**Status: IN PROGRESS — slice A built and committed (2026-11-12), slices
B–E and G in build; §15 says what is built. Scope on the owner's word of
that day: the calendar side, slices A–E and G; slice F (folders, the
partner's notes) is not in this build.** The mock is
published (https://claude.ai/artifact/E5Zm8rPv5hGLk2V5fKphPt). Every
decision is taken (§4): four are the owner's own words, the rest the
lead's on his delegation of the same day ("make sure that the document is
perfectly written with all questions answered"); any row can still be
overturned before its slice is built. §8 walks every case a person can
meet and says what happens. This is the design record for the surfaces the
sharing foundations left out (`cloud-sharing-foundations.md` §1, §11): how
a person shares a category, an event or a folder with their paired
partner, and how what the partner shares shows, sounds and behaves on
their phone. It covers the roadmap's E1 (switch and mark), E6 (a whole
category), E7 (a notice), N1's read-only editor and the place for shared
folders (`cloud-multi-user-roadmap.md` §7, §8), and it adds one piece the
foundations do not have: a category as a thing that can be shared (§7).
The partner never edits (E5, N3 stay out).

Written by the session's lead, Fable 5.2; no agent took a decision in it
(one explorer looked up file locations for §10).

## Contents

1. How to run this
2. Why
3. The model
4. Decisions
5. Before anything is built
6. The spec — every surface
7. The category grant — what the foundations gain
8. Cases — what a person expects, and what happens
9. Behaviour: must not change, deliberately changes
10. Facts from the tree
11. Slices
12. Definition of done
13. Deferred
14. More than two people
15. As built

---

## 1. How to run this

Load `anta-context`, `ui-language`, `ui-revamp`, `delegation`, `verify`;
`calendar-events` + `calendar-ui` for slices A, C, D, E; `drift-migrations`
for slice B; `markdown-engine` for slice F; `l10n` for every slice;
`qa-emulator` for slice G. Read this record **by section**: a slice needs
its parts of §6 and §8, then §9 and §10; slice B needs §7 with
`cloud-sharing-foundations.md` §3–§7 beside it.

- A Fable 5.2 session at `high` leads: it writes each brief and runs the
  whole-suite gate after each slice.
- Per slice: one `designer` first for A, C, D and F (it renders the real
  surfaces and returns the exact spec — the mock's bars, the month grid
  and the browser's root are schematic), then one `implementer`, one
  `reviewer`; a `design-reviewer` after the code review of A, C, D and F;
  one `qa-runner` for the device pass in G.
- Slice B changes who can read what on the server. Each part of the
  foundations had a privacy hole that only its independent review found
  (`cloud-sharing-foundations.md` §12). B's review is not optional, and
  the owner says whether it is `reviewer` or `fable-max`.
- The gate after every slice: `dart analyze lib` clean; the whole
  `flutter test --reporter failures-only` green, foreground, one run;
  `flutter gen-l10n` and an empty `untranslated.txt` when an ARB changed;
  the rules suite when `firestore.rules` changed (`flutter test
  test/firestore/rules_test.dart --tags firestore-rules --run-skipped`,
  with `firebase emulators:start --only firestore --project
  alexs-note-tracking-app --config firebase.emulators.json` up); §9's
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
fails the same way (`cloud-sharing-foundations.md` §11). No surface asks
`SharedRowDao.isShared` — a grep of `lib/pages`, `lib/widgets`, `lib/bloc`
and `lib/controllers` finds no caller.

The first real request (the owner, 2026-11-12): his partner wants to share
**event categories** with him. A category cannot carry a share today: the
mark exists on `calendar_events` and `folders` only, so she would have to
switch on every event, and every new one. His three follow-ups the same
day shaped the rest: shared things must be told apart, by a look the user
chooses; alarms for shared categories need one general setting; and the
record must answer every case.

---

## 3. The model

One pair, so there is never a person to pick: the control is a switch
named after the partner.

- **One verb on the thing itself.** "Share with {name}" is a switch in the
  category editor and the event editor, and an entry in a folder's menu.
- **One page for everything**, Settings → Sync & sharing → the Pairing
  row: what I give (a tick list), what I get (a tick list of what I let
  show), how it looks, whether it may ring, and the two ways out.
- **Share a container and what is added later follows.** A category for
  the calendar, a folder for notes. One event is the exception switch.
- **Giving and showing are separate.** The sharer decides what is given;
  the receiver decides what shows and what rings. Neither asks the other.
- **Three promises the copy repeats**: nothing is shared until you switch
  it on; the partner reads and never changes; switch it off and it leaves
  their phone.

| Shared thing | The mark | What follows it | Built? |
| --- | --- | --- | --- |
| a category | `calendar_categories.shared_pair` | its definition (name, colour, icon); every event in it, with their skipped days and per-day texts | **no — §7, slice B** |
| an event | `calendar_events.shared_pair` | its skipped days and per-day texts | yes (F1) |
| a folder | `folders.shared_pair` | every folder and note under it | yes (F1) |
| a note | — | — | no; deferred (§13) |

An event is shared when its own mark is set **or** its category's is.
Never shared, on either phone: alerts, presence marks, category alerts and
profiles, templates, counters, the per-note currency, every setting.

---

## 4. Decisions

**Who decided.** *Owner* — his words of 2026-11-12, quoted. *Lead* — taken
by the lead on the owner's delegation of 2026-11-12; the option not taken
is named so it can be chosen instead. A later change appends a row;
nothing is rewritten.

### What is shared

| # | Decision | Why, and the option not taken | By |
| --- | --- | --- | --- |
| D1 | Sharing a category shares every event in it, now and later, with the category's name, colour and icon. | It is the roadmap's E6, and the only reading under which a new event needs no second act. The owner's follow-ups speak of shared categories' events drawn on the calendar and of their alarms, which settles the reading. Not taken: a one-time copy of the category list with no events. | Lead; confirmed by the owner's follow-ups |
| D2 | Containers first: a category, a folder. One event is the exception switch. One note alone is deferred. | Fewest acts for the request. A note cannot stand outside a folder, so a lone shared note has no place on the other phone yet (§13). | Lead |
| D3 | An event in a shared category is always shared; its switch shows on and locked, naming the category. No per-event "keep private". | One sentence explains it. Not taken: a third state on every event (§13). | Lead |
| D4 | A share is whole: the category's past events too, each event with its description. No "from today on", no "busy only". | The partner reads the same document the owner's devices read; a cut-down share needs a second, derived document per row (§13). The tick sheet's event count shows how much goes. | Lead |

### Giving

| # | Decision | Why, and the option not taken | By |
| --- | --- | --- | --- |
| D5 | Two entry points: the switch on the thing, and the Sharing page with its tick list. | In context is where a person thinks of it; the page is where they check it. | Lead |
| D6 | No confirm dialog for a share. The caption says what the partner will see; a snackbar offers Undo. "Stop sharing everything" alone confirms. | Reversible, and the other phone reads at most every five minutes. Not taken: a dialog per category or folder. | Lead |
| D7 | Not paired: no share control anywhere. | Most users never pair; a dead row in every editor is noise (the roadmap's E1 says the same). | Lead |
| D8 | Paired, database not syncing: the row stays, dimmed, "Turn on sync to share"; a tap opens Sync & sharing. | The capability exists and one step is missing — disabled, not hidden. | Lead |
| D9 | Today's "Share note" / "Share folder" (a file through the system share sheet) read "Send a copy". Keys and behaviour stay. | "Share" must mean one thing. | Lead |
| D10 | A sign on what I share — `Icons.group_rounded` on my shared categories, events and folders — with a switch to turn it off. | "We need to know which event category is shared somehow." | Owner |

### Receiving

| # | Decision | Why, and the option not taken | By |
| --- | --- | --- | --- |
| D11 | No accept step. The receiver chooses what shows: each category under "{name} shares with you" has a tick, "Show on my calendar", on by default. A hidden category is drawn nowhere and never alerts; it stays up to date underneath. Folders have no tick. | A share must not need a second person to finish it, and the receiver must not be buried by it. It also separates a shared built-in from my own, which no filter can. Folders sit in their own section at the end of the root and ring nothing. Not taken: accept / decline per share. | Lead |
| D12 | How shared things look is a user setting, for the calendar and for notes separately. Events shared with me: Outlined · Avatar · Like mine. Notes shared with me: Avatar · Like mine. Defaults: Outlined, Avatar. | "Maybe we can do an outline for calendar events or we can choose to show them normally, in my opinion we can have a user settings. Same with the notes." Outlined is the only look the month grid can show. Notes get no outlined look: a note row has no glyph and a folder's glyph is already an outline (`folder_row.dart:137`). | Owner; values and defaults Lead |
| D13 | Whether shared events may alert is one general setting, three values: **Off** · **Only alerts I add** (default) · **Category alerts too**. | "There should be a setting to disable alarms for shared categories, a general one." The default keeps the app's rule that nothing arms unasked; Off is the total mute; the third is for a couple whose shared category is really a joint one (§6.8). Not taken: a plain on/off, which cannot tell "ring for the one I chose" from "ring for every gym session of hers". | Owner; values and default Lead |
| D14 | The partner's own categories show under "From {name}" in the Categories page and the filter lists, read-only, never in the picker for my events. A built-in they share (`gym`) is my `gym`: my colour, my row. | Built-in ids are the same on every install, and the reader never lets a shared row take the place of my own (`SharedRowRefused`). Not taken: every shared category separate, which needs owner-aware ids in every filter and saved view. | Lead |
| D15 | A partner's events are left out of my report, goals and presence figures, are never "missed" or "pending", and never tint a day cell. | They are the partner's time. | Lead |
| D16 | A partner's event opens a read sheet, not the editor: its facts, my own alerts, "Copy to my calendar". | A form at 38 % is unreadable; alerts on a shared event are mine by design. | Lead |
| D17 | The partner's folders stand in a "From {name}" section at the end of the root. All notes and search include their notes; Recent does not. | The reader already places them at the top level (`SharedRowDao.placeFolders`); a section costs no tap. Recent is "what I worked on" — a busy partner would take it over. | Lead |
| D18 | A partner's note opens in the editor, read-only: no keyboard, no markdown bar, one "From {name} · Read only" line, "Copy to my notes" in the menu. | The live editor is the renderer; a second read page would drift from it. | Lead |
| D19 | A partner's rows are never exported from my phone: "Send a copy" is disabled on them, an .ics or archive export leaves them out. "Copy to my calendar" / "Copy to my notes" is the act that makes one mine. | Foundations decision i ("backups hold what is mine"), applied to every door out. Reading always allows copying; the app does not pretend otherwise, it makes it one deliberate act. | Lead |
| D20 | Digests include a partner's events only under "Category alerts too", each line saying "From {name}". | A digest is an alert; it follows the alert setting. | Lead |
| D21 | An alert's notice for a partner's event offers Snooze and never Skip. | Skip writes a skipped day or the event's "Category alerts" switch — both the partner's data (`alert_skip_action.dart`); the database would turn the write into nothing. | Lead |

### Timing, endings, wording, place

| # | Decision | Why, and the option not taken | By |
| --- | --- | --- | --- |
| D22 | Freshness as built — at start, on "Sync now", every five minutes while open — plus one read when the Sharing page opens. From seven days without a successful read the page says "May be out of date"; nothing is removed for age. | A live listener re-reads the whole shared set whenever it re-attaches (foundations §11). Expiring rows would empty a phone on a long trip. | Lead |
| D23 | Notices: one when something new arrives ("{name} shares Shifts with you"); one when something leaves **and took an alert of mine with it**. Otherwise things come and go silently. Never a system notification. | Arrival is news; a silent departure is only a problem when I was counting on a reminder. | Lead |
| D24 | "Stop sharing everything" on the Sharing page clears every mark and keeps the pair. | Otherwise the only fast exit is Unpair, which also ends what the partner shares. | Lead |
| D25 | Stopping sync on a database that shares something says so in its confirmation: the partner keeps what is shared as it is now, without later changes; to take it back, stop sharing first. | The shared documents stay in the cloud with their grant — only the reader's look at the pair clears marks (`sync_shared_reader.dart:177`). Not taken: clearing the marks inside "Stop syncing", which needs a push that an offline phone cannot make. | Lead |
| D26 | Copy never puts a possessive on the name ("From Maria", never "Maria's event"). | German and Romanian decline names; a placeholder cannot. | Lead |
| D27 | All of this page's settings live on the Sharing page and are found by the settings search. They are per device, like every setting (settings are not a synced table). | One place for sharing. Per device is right for alerts: a tablet can stay silent while the phone rings. | Lead |
| D28 | Several people: no group type is built now; every surface is drawn for an audience that is one person today (§14). | "What if we want to share with multiple people, do we need to create a group type?" — no: the pair is already a member list and the rules check membership. | Owner asked; Lead |

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
6. Not blocking: the commits on `main` are not pushed; D2's device check
   (an account deleted while its pair is active) is still owed.

### 5.2 What the code lacks

- **A category cannot be shared** — §7, slice B: schema v56, wire 48, the
  rules and one index, the reader's sixth table, the fences.
- **No surface knows a row is the partner's.** `CalendarEvent`,
  `CalendarCategory` and the browser's items carry no "from the partner"
  flag; the services load every row alike (`CategoryService._load`,
  `category_service.dart:186`, reads `getAll()` with no owner in sight).
- **Nothing gathers "can I share, and with whom"**: the pair is in
  `PairingService.status` (`pairing_service.dart:172`), whether the
  database syncs is in the sync services, and the marks are set through
  separate services. Slice A adds the one facade (§6.1).
- **A category alert of mine would arm on a partner's event** whose
  category id is one of mine (a shared built-in): the scheduler walks
  every event the service holds (`alert_scheduler.dart:700`, `:839`) and
  `EventAlerts.effectiveFor` (`lib/constants/event_alerts.dart:157`)
  projects a category's alerts onto every event of that id, knowing
  nothing of whose event it is. Read from the code, not yet reproduced —
  slice A pins it with a failing test before anything else. It is the one
  defect in what is already on `main` that this record found.
- **The note editor has no read-only mode**: the fork's `CodeEditor` takes
  `readOnly` (`packages/re_editor/lib/src/code_editor.dart:306`), and
  `ModernEditorWrapper` passes a literal `false`
  (`modern_editor_wrapper.dart:1091`).

---

## 6. The spec — every surface

Numbers are the constants a surface reads, never literals. The mock is one
page; its app bars, the month grid and the browser's root are schematic,
and the `designer`'s render replaces them before each visual slice.

### 6.1 The share service (no pixels)

`lib/services/share_service.dart`, on the `DatabaseLifecycle` reset
contract (pairing state and settings are per database), with a fake for
every suite.

- `ShareAvailability`: `notPaired` · `notSyncing` · `ready`, with the
  **audience** — an id, a display name, its members' profiles; one person
  today (§14). `changes` is a stream that **replays its last value** (a
  fake of it replays too).
- `setCategoryShared(id, on)`, `setEventShared(id, on)`,
  `setFolderShared(id, on)` — the only callers of the mark writers outside
  tests; each takes the pair id from `PairingService.status`, so a surface
  never holds one. After a write it asks for a sync run, so the share
  leaves now rather than at the next cadence tick.
- `stopAll()` — clears every mark of this database, stamped and queued
  like any edit.
- `overview()` — what the Sharing page lists: my marked categories, my
  singly marked events, my marked folders; the partner's categories with
  their shown / hidden state, their events that came without a category
  of theirs, their top-level folders; when the shared read last finished;
  whether the outbox still holds share re-sends; `shared_newer_wire`; the
  count of rows refused for an id of mine (refused built-in categories
  never counted — §7.5).
- `isFromPartner(table, id)` — over `SharedRowDao.isShared`.
- The receiver's settings, each through `SettingsService` +
  `SettingsKeys`: `shareEventLook`, `shareNoteLook`, `shareMarkMine`
  (§6.7), `shareAlerts` (§6.8), `shareHiddenCategories` (§6.4).

**Where "the partner's" is decided, once.** `CalendarEvent` and
`CalendarCategory` gain a transient `fromPartner` (the row's owner is the
shared owner; never stored, never exported), set where the services load
their rows. The events of a hidden category (§6.4) are dropped at that
same place, so the grid, the agenda, the overview and the alert scheduler
cannot disagree about what exists.

A thin `ShareBloc` (`lib/bloc/share/`, sealed + `Equatable`) serves the
Sharing page. The editors and menus receive `ShareAvailability` from their
opener, as the event editor receives `dayLoad` today, and return the
choice in their result; the flow that saved the draft calls the service.

### 6.2 The Sharing page

Idiom: **the settings kit** (`SettingsSectionList` under `SettingsAppBar`).
`lib/pages/sharing_page.dart`, pushed from the Pairing row of
`sync_settings_page.dart:306`, which keeps its section and changes its
words while paired: title "Paired with {name}", description the summary
("3 categories, 1 folder" from plural parts; "Nothing is shared yet" at
zero), a chevron. Unpair moves onto the new page.

Title "Sharing with {name}". Top to bottom:

1. **YOU SHARE** — three entries, each a title, a one-line description
   and a chevron: Categories (the names, cut with an ellipsis; "None"),
   Single events ("2 events" / "None"), Folders (names / "None"). The
   label's trailing slot says "Sending…" while the outbox still holds
   share re-sends and "Waiting to send" when offline. Intro: "{name} sees
   these and cannot change them."
   - Categories opens §6.3.
   - Single events and Folders open a filler sheet listing the marked
     rows, each with a trailing ✕ that un-shares it (snackbar + Undo); the
     folders list ends in `FormActionRow` "+ Share a folder", which opens
     the app's folder picker (`folder_picker_dialog.dart`). The events
     list, when empty, says one line: "Share an event from its editor."
2. **{NAME} SHARES WITH YOU** — the same three entries; Categories opens
   §6.4, the other two open read-only lists. The label's trailing slot
   says "Updated {when}" (`formatSyncMoment`). Intro: "Read-only. They
   leave when {name} stops sharing." Lines that appear here only when
   true, in this order: "Turn on sync to receive" (this database does not
   sync — the entries dim); "Could not check. Will try again." (the last
   shared read failed); "May be out of date" (D22); "Update ANTA to see
   everything {name} shares" (`shared_newer_wire`); "{n} items could not
   be shown" (rows refused for an id of mine).
3. **HOW SHARED THINGS LOOK** (D12, D10; §6.7) — two `settingsChoiceRow`s,
   "Events shared with you" and "Notes shared with you", and a switch,
   "Mark what you share". The kit stacks a choice row's segments when a
   word would break (German at 2.0).
4. **ALERTS** (D13; §6.8) — one entry, "Alerts for shared events", its
   value as the description, opening a menu of the three choices
   (`FormMenuChoiceItem`s, the current one ticked).
5. A last group: **Stop sharing everything** ("You stay paired";
   `AppDialogs.confirm`: "Stop sharing everything with {name}? {name}
   stops seeing your categories, events and folders. What {name} shares
   with you stays.") and **Unpair** (the existing flow, moved; its dialog
   gains one sentence: "If you pair again, you choose again what to
   share.").

Every entry keeps its place and height in every state; "None" rows stay.
Every control writes at once. The page asks for one shared read as it
opens (D22).

### 6.3 What I share — the category tick sheet

`CategoryPickerSheet.pickMulti` — the app's one choosing surface — with a
title ("Share categories"), a caption under the header ("{name} sees every
event in a ticked category, new ones too. Only you can change them.") and
each row's event count. It lists my categories, built-ins and archived
ones included, as the picker lists them today; never the partner's. Done
returns the set; the page diffs it against the marks and calls
`setCategoryShared` per change; one snackbar with Undo:

- "Sharing Work, Travel with {name}";
- "No longer shared: Gym";
- when an un-ticked category holds events that carry their own mark:
  "No longer shared: Work. 2 events stay shared on their own." (§8, C10).

`pickMulti` never collapses an empty pick — an empty set here means "share
none".

### 6.4 What I let show — the partner's categories

A filler sheet, "Categories from {name}", from the second section's
Categories entry. Caption: "Ticked ones show on your calendar. {name}
never sees what you hide." One row per category the partner shares:

- the category's avatar in the event look (§6.7), its name, a second line
  — "18 events", or "9 events · joins your Family" for a shared built-in
  (D14) — and a switch, **shown / hidden**, on by default
  (`shareHiddenCategories` holds the hidden ids);
- a hidden category: its events are dropped where the service loads them
  (§6.1), so they are drawn nowhere, counted nowhere and never alert; the
  rows stay stored and current, so showing it again is instant;
- tapping the row of one of the partner's **own** categories opens its
  sheet (`SharedCategorySheet`, a sub-sheet): `FormReadTitleRow` (avatar,
  name, "From {name}"), the same show switch, and — only useful under
  "Category alerts too" — `FormSectionLabel` "ALERTS" over my own category
  alerts for it (the category editor's alert rows and Add alert, rows of
  my own keyed by the partner's category id). Under the other two alert
  settings that group stays in place, dimmed, with the caption "Category
  alerts are off for shared events". A shared built-in has no such sheet:
  my own category editor governs it.

### 6.5 The category editor and the Categories page

**Editor.** One new section between the look group and ALERTS:
`FormSectionLabel` "SHARING" over a `FormRowGroup` of one
`FormSwitchRow(glyph: Icons.group_rounded, label: "Share with {name}",
subtitle: …)`. Subtitle: off "Only you see these events"; on "All {n}
events, and new ones" (plural; "New events are shared" at zero). The
switch is part of the draft and is written after Save. Absent when not
paired; dimmed with "Turn on sync to share" when the database does not
sync. A new category can be created already shared.

**Deleting a shared category** (`category_delete_sheet.dart`,
`CategoryDeleteImpact`): the impact gains one line — "{name} stops seeing
its 42 events", or "They stay shared through Travel" when the category
they move to is shared.

**Page** (`calendar_categories_page.dart`): a shared category's caption
gains "Shared" beside "Built in" / "Alerts on", and the row carries the
sign (D10); the ⋮ menu gains "Share with {name}" / "Shared with {name}" ✓
as a `FormMenuChoiceItem` between Edit and Archive. An archived category
stays shared and says so. A third section, "From {name}", lists the
partner's own categories that are shown: avatar, name, event count, no
handle, no menu; a tap opens `SharedCategorySheet`. Reorder and "sort A–Z"
never touch that section.

### 6.6 The event editor

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
untouched, and `EventEditorResult` (`event_editor_sheet.dart:69`) carries
it to the flow, which calls `setEventShared` after the event is stored (a
new event has no id before). A template never stores the choice, and a
duplicate never copies an event's own mark — it is shared only if its
category is.

### 6.7 How shared things are told apart — settings (D12, D10)

| Key | Values | Default |
| --- | --- | --- |
| `shareEventLook` | `outlined` · `avatar` · `plain` | `outlined` |
| `shareNoteLook` | `avatar` · `plain` | `avatar` |
| `shareMarkMine` | on · off | on |

Read by the widgets from the settings state they already rebuild on —
never looked up per row.

**Events shared with me**

- **Outlined**: `EventAvatar` (`lib/widgets/event_avatar.dart`) gains an
  outlined cut — no fill, a ring in the category colour
  (`FormMetrics.shareOutlineWidth`, new), the icon in that colour — used
  wherever the event's avatar is drawn: the day list, the agenda, the
  overview, the read sheet's title row, the received-categories sheet.
  The month grid's markers gain a hollow twin for each
  `CalendarMarkerStyle` (`bars`, `dots`, `calendar_appearance.dart:27`),
  and the day rail's marker the same.
- **Avatar**: drawn like mine, with the partner's `UserAvatar`
  (`RowMetrics.partnerAvatarRadius`, new) at the row's end. Lists only —
  the grid shows no difference, which is why Outlined is the default.
- **Like mine** (`plain`): no visual difference.
- In every look a partner's event never tints a day cell (D15):
  `CalendarCellStyle` (`calendar_appearance.dart:167`) is the look of *my*
  day.

**Notes shared with me**

- **Avatar**: the partner's avatar before the count on a folder row and at
  the end of a note row — in a folder, in All notes, in search.
- **Like mine**: none.
- The root's "From {name}" section (D17) stands in both: it is where the
  folders are, not how they look.

**What I share** (`shareMarkMine`): `Icons.group_rounded` as a small glyph
(`RowMetrics.shareMarkSize`, new) in `onSurfaceVariant` before the row's
count or chevron — a shared category's row (the Categories page, the
picker, the filter lists), my shared event's row in the day list, the
agenda and the overview (shared singly or through its category), a shared
folder's row in the browser and in the folder picker, and beside the title
in the note editor's bar while the open note lies in a shared folder. A
note row inside a shared folder is not marked; its folder is.

**Whatever the look**: semantics always say "From {name}" or "Shared with
{name}"; the read sheet and the note's read-only line always name the
person; write actions are disabled all the same. A look is never the only
carrier of "this is not mine". The ring and the hollow marker meet 3:1
against their ground in both themes for every category colour — measured
from tokens by the `designer`, re-measured by the `design-reviewer`.

### 6.8 Alerts on shared events — one general setting (D13)

`shareAlerts`, on the Sharing page; per device.

| Value | Label | Its line | What arms for an event shared with me |
| --- | --- | --- | --- |
| `off` | Off | Nothing shared with you rings | nothing — my alerts on shared events stay stored and unarmed |
| `own` (default) | Only alerts I add | On one event, from its sheet | the alerts I added to that event in its read sheet |
| `category` | Category alerts too | Shared events follow your category alerts, alarms included | those, plus the alerts of the event's category on my phone: my own category's alerts for a shared built-in, the alerts I gave the partner's category in its sheet (§6.4) |

Rules that hold in every value:

- **The partner's alerts never reach me**, and mine never reach the
  partner (foundations §7). An alert on a shared event is a row of my own,
  in my own space.
- **One predicate, in the scheduler.** `AlertScheduler` decides per event
  from `fromPartner` and the setting; `EventAlerts.effectiveFor` is told
  whether inheritance applies. The partner's own "Category alerts" switch
  on the event is theirs and is not read: under `category` every shared
  event of a category follows that category's alerts. One shared event
  cannot be opted out alone (§13).
- **A hidden category never alerts**, whatever the setting.
- **The notice** names the person ("Night shift · From {name}") and offers
  Snooze, never Skip (D21).
- **An alert follows what this phone last received.** The reader runs
  while the app is open; an event the partner moved or removed while my
  app was closed still alerts at the old time. The read sheet's caption
  says so (§6.9). The cure is push (the roadmap's P6).
- **When a shared event leaves** — un-shared, deleted, its category hidden
  or un-shared, the pair ended — its armed alerts are cancelled by the
  reconcile the sync hooks already run
  (`app_sync_apply_hooks.dart:482`); my alert rows stay, inert. If an
  alert was armed, one snackbar says it (D23).
- **Digests** include shared events only under `category`, each line
  marked "From {name}" (D20).
- The first alert on a shared event runs `AlertPermissionCheck.afterSave`
  like any other.

### 6.9 A partner's event — the read sheet

`lib/widgets/shared_event_sheet.dart`, a **sub-sheet** (content-tall under
`FormMetrics.sheetHeightFactor`, unguarded, ✕ with the `close` tooltip, an
empty trailing slot). `EventSheetsFlow.openEditor`
(`event_sheets_flow.dart:398`) opens it instead of the editor when the
event is the partner's.

1. Header: "From {name}".
2. A group: `FormReadTitleRow` (the event's avatar in the event look, its
   title, the category name as caption); read rows for Date, Time (or "All
   day") and Repeat in the editor's own words (`FormPickerRow` with
   `onTap: null`, `showChevron: false`); a Linked note row only when that
   note lies in a folder the partner shares (it opens read-only); the
   description as a read cell when there is one — for a recurring event,
   the text of the opened day.
3. `FormSectionLabel` "YOURS" over a group: my own alerts on this event
   (the event editor's alert rows and its Add alert, over
   `EventAlertService`); under `category`, the inherited ones listed
   read-only as the editor lists them ("From {category}"). Under `off`
   the group stays in place, dimmed, Add alert disabled, with the caption
   "Alerts for shared events are off".
4. A group: `FormActionRow` "Copy to my calendar" — creates an event of my
   own from the facts shown (`createX` stamps now, a new id, no mark; a
   category I do not have becomes `other`), opens it in the editor, and
   says once: "Copied. Later changes by {name} do not reach your copy."
5. Caption: "Only {name} can change this event. Your alerts follow what
   this phone last received."

While the sheet is open it follows the event: a change redraws it in
place; if the event leaves, the sheet closes with "{name} no longer shares
this event". Presence on a partner's event is not offered (§13).

### 6.10 The partner's events in lists and filters

- The grid, the day list, the agenda and the overview show them in the
  event look (§6.7). Actions that write — delete, skip this day, move,
  mark present or missed — are disabled on them; Duplicate is "Copy to my
  calendar".
- The filter lists (`calendar_filter_sheet.dart:485`,
  `agenda_filters_sheet.dart:491`) list the partner's own shown categories
  under a "From {name}" header; hiding one there is the ordinary,
  per-view filter. A shared built-in is filtered with mine; taking only
  the partner's half away is the tick of §6.4.
- Report, goals, presence figures, "missed" and "pending" skip them (D15):
  the one flag of §6.1, applied where each of those reads its events.
- Exports skip them (D19).

### 6.11 A folder — the menu

`folder_overflow_menu.dart:138` and the row actions of `folder_row.dart:284`
gain one entry directly above today's share entry: "Share with {name}"
(`Icons.group_rounded`), which reads "Shared with {name}" with a trailing
tick while the folder's own mark is set. A folder inside a shared folder
shows the entry disabled, "Shared with {name}", since the outer mark
covers it. Absent when not paired; disabled when the database does not
sync, or the folder is the partner's. A snackbar with Undo follows either
way; sharing a folder that holds an already shared folder says "Lisbon is
now shared through Trips". Today's entries keep their keys and action and
read "Send a copy" (D9) — `note_overflow_menu.dart:124`, `note_row.dart:356`
too.

Moving a note or a folder: the folder picker shows the sign on shared
folders (§6.7), and the move's snackbar ends "· now shared with {name}" or
"· no longer shared" when the move changed that.

### 6.12 The partner's folders in the browser

- **Root**: after `addGroup(folders, l10n.folders)`
  (`optimized_folder_content_page.dart:2151`), a group "From {name}" of the
  folders whose owner is the shared owner; they leave the Folders group.
  Rows are `ContentRowShell` rows in the notes look (§6.7); no drag handle,
  never part of a reorder or a selection.
- **Inside** a partner's folder, at any depth: the create bar's buttons
  are disabled; every row action that writes (rename, move, label,
  delete) and "Send a copy" (D19) are disabled; the folder's menu keeps
  Sort by and Settings. Sort preferences are mine and keep working.
- **All notes and search**: the partner's notes appear, in the notes look.
  **Recent**: never (D17).
- A row that leaves while its page is open is already announced as gone
  (foundations §5.9); a partner's folder open when its share ends pops to
  the root with one snackbar: "{name} no longer shares this folder."

### 6.13 A partner's note — read-only

`optimized_note_editor_page.dart` asks `ShareService.isFromPartner` before
its first frame and, for a partner's note:

- passes `readOnly: true` through a new `ModernEditorWrapper.readOnly` to
  `CodeEditor` (no keyboard, no caret edits; selection and copy stay);
- builds no `MarkdownBar` and no vocabulary bar; the body takes the room;
- never starts `NoteSaveCoordinator` / auto-save, so `updateNote` is never
  called and `SharedRowException` never surfaces;
- shows one line under the bar, the partner's avatar and "From {name} ·
  Read only" (`surfaceContainerHigh` light / `surfaceContainer` dark,
  `RowMetrics.secondLineFontSize`, `onSurfaceVariant`; one height, a
  `FormCaptionSlot`);
- its ⋮ menu: Edit title, Move, Label, Delete and "Send a copy" disabled;
  "Copy to my notes" enabled — a new note of my own in a folder I pick,
  stamped now;
- a task checkbox does not toggle, and the first such tap of a visit says
  "Read only. Only {name} can change this note."; a wiki link, a tag and
  a money line behave as in any note; a link to a note I was not given
  leads nowhere, as any link to a missing note does; counters and the
  currency shown are mine (foundations decision j);
- follows the note while open: a change by the partner redraws the text
  in place, the scroll position kept (there is no local edit to protect);
  if the note leaves, the page closes with "{name} no longer shares this
  note".

### 6.14 Notices

All inside the app (`CustomSnackbar`, or `OverlaySnackbar` from a sheet
and on the editor and calendar pages); never a system notification.

| When | Words | Action |
| --- | --- | --- |
| I share or stop | Sharing {what} with {name} / No longer shared: {what} | Undo |
| something new arrives — a category, a singly shared event, a top-level folder this phone had not held | {name} shares {what} with you; for several at one read, "{name} shares 3 categories with you" | View → the Sharing page |
| something leaves and an alert of mine was armed on it | {name} no longer shares {what}. Your alert is off. | — |
| the thing I have open leaves | {name} no longer shares this event / note / folder | — |
| an import lands events in a shared category | the import's own result line gains "{n} are shared with {name}." | — |

### 6.15 Copy and keys

New keys, en shown; de and ro written with them, `{name}` never declined
(D26), with a fallback word for a partner without a profile
(`sharePartnerFallback` "your partner").

| Key | en |
| --- | --- |
| `shareWithPartner` / `sharedWithPartner` | Share with {name} / Shared with {name} |
| `shareFromPartner` | From {name} |
| `sharingWithTitle` | Sharing with {name} |
| `shareYouShare` / `sharePartnerShares` | You share / {name} shares with you |
| `shareRowCategories` / `shareRowEvents` / `shareRowFolders` | Categories / Single events / Folders |
| `shareNone` | None |
| `shareYouShareCaption` | {name} sees these and cannot change them. |
| `sharePartnerSharesCaption` | Read-only. They leave when {name} stops sharing. |
| `shareSending` / `shareWaitingToSend` / `shareUpdated` | Sending… / Waiting to send / Updated {when} |
| `shareNeedsSync` / `shareNeedsSyncReceive` | Turn on sync to share / Turn on sync to receive |
| `shareCheckFailed` / `shareMaybeStale` | Could not check. Will try again. / May be out of date |
| `shareUpdateApp` / `shareNotShown` | Update ANTA to see everything {name} shares / {count} items could not be shown |
| `shareEventOff` / `shareEventOn` | Only you see this event / {name} sees it, read-only |
| `shareThroughCategory` | On for everything in {category} |
| `shareCategoryOff` / `shareCategoryOn` | Only you see these events / All {count} events, and new ones (plural) |
| `shareCategoriesTitle` / `shareCategoriesCaption` | Share categories / {name} sees every event in a ticked category, new ones too. Only you can change them. |
| `shareTheirCategoriesTitle` / `shareTheirCategoriesCaption` | Categories from {name} / Ticked ones show on your calendar. {name} never sees what you hide. |
| `shareJoinsYours` | joins your {category} |
| `shareStarted` / `shareStopped` / `shareStoppedSomeStay` | Sharing {what} with {name} / No longer shared: {what} / … {count} events stay shared on their own. |
| `shareNowThrough` | {inner} is now shared through {outer} |
| `shareMovedIn` / `shareMovedOut` | now shared with {name} / no longer shared |
| `shareDeleteImpactStops` / `shareDeleteImpactStays` | {name} stops seeing its {count} events / They stay shared through {category} |
| `shareStopAll` / `shareStopAllDesc` / `shareStopAllConfirm` | Stop sharing everything / You stay paired / Stop sharing everything with {name}? … |
| `pairingRepairHint` | If you pair again, you choose again what to share. |
| `syncStopSharingLine` | {name} keeps what you share as it is now, without later changes. To take it back, stop sharing first. |
| `shareLookSection` | How shared things look |
| `shareEventLook` / `shareNoteLook` | Events shared with you / Notes shared with you |
| `shareLookOutlined` / `shareLookAvatar` / `shareLookPlain` | Outlined / Avatar / Like mine |
| `shareMarkMine` / `shareMarkMineDesc` | Mark what you share / A sign on your shared categories, events, folders |
| `shareAlertsSection` / `shareAlerts` | Alerts / Alerts for shared events |
| `shareAlertsOff` / `shareAlertsOffDesc` | Off / Nothing shared with you rings |
| `shareAlertsOwn` / `shareAlertsOwnDesc` | Only alerts I add / On one event, from its sheet |
| `shareAlertsCategory` / `shareAlertsCategoryDesc` | Category alerts too / Shared events follow your category alerts, alarms included |
| `shareAlertsOffCaption` / `shareCategoryAlertsOffCaption` | Alerts for shared events are off / Category alerts are off for shared events |
| `shareAlertNoticeTitle` | {title} · From {name} |
| `sharedEventYours` / `sharedEventCopy` / `sharedEventCopied` | Yours / Copy to my calendar / Copied. Later changes by {name} do not reach your copy. |
| `sharedEventCaption` | Only {name} can change this event. Your alerts follow what this phone last received. |
| `sharedNoteLine` / `sharedNoteCopy` / `sharedNoteReadOnly` | From {name} · Read only / Copy to my notes / Read only. Only {name} can change this note. |
| `shareNewFromPartner` / `shareNewManyFromPartner` | {name} shares {what} with you / {name} shares {count} categories with you |
| `shareGoneEvent` / `shareGoneNote` / `shareGoneFolder` / `shareGoneWithAlert` | {name} no longer shares this event / note / folder / {name} no longer shares {what}. Your alert is off. |
| `shareImportLine` | {count} are shared with {name}. |
| `shareMarkMineLabel` / `shareMarkPartnerLabel` (semantics) | Shared with {name} / From {name} |
| `shareNote`, `shareFolder` (values only) | Send a copy |

`SemanticsIds` (kebab-case, never renamed): `sharing-page`,
`sharing-mine-categories|events|folders`,
`sharing-theirs-categories|events|folders`, `sharing-look-events`,
`sharing-look-notes`, `sharing-mark-mine`, `sharing-alerts`,
`sharing-alerts-off|own|category`, `sharing-stop-all`, `sharing-unpair`,
`share-categories-sheet`, `shared-categories-sheet`,
`shared-category-show-<id>`, `shared-category-sheet`,
`category-editor-share`, `category-menu-share`, `event-share`,
`folder-menu-share`, `row-action-share`, `shared-event-sheet`,
`shared-event-add-alert`, `shared-event-copy`, `shared-note-line`,
`shared-note-copy`, `browser-section-partner`.

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
(decision c); `clearOtherPairs` joins the reader's look at the pair
(`FolderDao.clearSharesExcept`, `folder_dao.dart:1175`);
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
  under the partner's `owner_id`, the mark itself not stored. The
  partner's `sort_order` and `is_hidden` are theirs and are not obeyed
  here: the receiver's list has its own order and its own show tick.
- **A category under an id of mine is refused** (`SharedRowRefused`), like
  any shared row over a row of my own. For a built-in that is always the
  case, and it is the design (D14): the partner's `gym` events resolve to
  my `gym` (`CalendarCategories.resolve`, `calendar_categories.dart:159`).
  The reader records which built-in ids the partner shares (the
  received-categories sheet lists them, §6.4), and this refusal never
  counts in "{n} items could not be shown".
- **The fences** follow `sharedTables`
  (`shared_row_fences.dart:58`): a partner's category cannot be changed or
  deleted here. Two more are written by hand, as the "_into" and "_onto"
  fences are: an event of my own cannot take a partner's category, and
  neither can a template. A category alert of my own *may* name a
  partner's category (§6.4) — it is a personal row, like an alert on a
  shared event.
- **The catalogue** (`CategoryService._load`): `fromPartner` per §6.1.
  `CalendarCategories.visible` and everything the pickers, the reorder,
  `deleteCategory`'s targets and the sort use exclude such rows; `resolve`
  and the filter lists include the shown ones.
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

## 8. Cases — what a person expects, and what happens

Every case found by walking both people through the whole life of a
share. "Me" is the person holding the phone; "{name}" the other. The last
column says where the answer is specified, or that it is deliberately not
built (§13).

### 8.1 Starting

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| S1 | I never paired | No share control anywhere; the app is today's. | D7 |
| S2 | Paired; my database does not sync; I try to share | The row is there, dimmed, "Turn on sync to share"; a tap opens Sync & sharing. | D8 |
| S3 | I share; {name}'s database does not sync | Nothing arrives there, and my phone cannot know — no phone reads the other's state. Their Sharing page says "Turn on sync to receive"; the guide says both must sync. | §6.2; receipts §13 |
| S4 | One of us runs an older build | That phone pauses as "Update ANTA"; the other's Sharing page shows the update line when it meets rows it cannot read. | §6.2 |
| S5 | {name} has no profile name | Every label says "your partner". | §6.15 |
| S6 | I keep several databases on this phone | A mark belongs to the database it was set in; the Sharing page speaks for the open one. What {name} shares arrives in every database of mine that syncs; ticks and settings are per database, so a second database can hide all of it. | §6.4 |
| S7 | We un-pair and pair again | Nothing is carried over; each chooses again. The unpair dialog says so. | §6.2 |

### 8.2 Sharing a category

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| C1 | I tick Work | Every Work event goes, past ones too; the row showed how many; snackbar with Undo. | §6.3, D4 |
| C2 | I add an event to a shared category — in the editor, from a template, by duplicating, by importing | It is shared with no second act. The editor shows the switch on and locked before I save; an import says how many landed in shared categories. | §6.6, §6.14 |
| C3 | I move one event out of a shared category, or into one | It leaves {name}'s phone, or arrives; the editor's row says which before I save. | §6.6 |
| C4 | I want one event of a shared category private | Give it another category. | D3; override §13 |
| C5 | I want {name} to see only that I am busy, or only from today on | Not possible: a share is whole. | D4; §13 |
| C6 | I rename a shared category, or change its colour or icon | It follows — for a category of my own making. A built-in looks on {name}'s phone the way *they* set it. | D14 |
| C7 | I archive a shared category | It stays shared and says so; to stop, un-tick it. | §6.5 |
| C8 | I delete a shared category | The delete sheet says what {name} stops seeing, or that the events stay shared through the category they move to. | §6.5 |
| C9 | I create a new category later | Private until I tick it. "Everything, always" is not built. | §13 |
| C10 | I un-tick a category that holds events I also shared one by one | Those stay shared; the snackbar says how many, and they are listed under Single events. | §6.3 |
| C11 | A recurring event | The whole series goes, with its skipped days and day texts. One occurrence alone cannot be shared. | §3 |
| C12 | An event with a linked note | {name} sees the link only when that note lies in a folder I share. | §6.9 |
| C13 | My alerts, presence marks, category alerts, goals, templates | Never leave my phone. | §3 |
| C14 | I tick a category of thousands of events, or tick while offline | Marked at once; "Sending…" or "Waiting to send" on the page until it has left. | §6.2 |
| C15 | I ticked the wrong one | Undo; {name}'s phone reads at most every five minutes. | D6 |

### 8.3 Sharing one event, a folder, a note

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| E1 | One event | Its switch, in the editor; a new event can be created shared. | §6.6 |
| E2 | I duplicate a singly shared event | The copy is private unless its category is shared. | §6.6 |
| F1 | A folder | Its menu; everything inside goes, new notes and folders too. | §6.11 |
| F2 | I move a note into or out of a shared folder | The picker shows which folders are shared; the snackbar says what the move did. | §6.11 |
| F3 | I write in a note that lies in a shared folder | The sign sits beside the title the whole time. | §6.7 |
| F4 | I share a folder that holds a shared folder, or the other way round | One share, the outer one; the entry on the inner folder is disabled and says it is shared. Un-sharing the outer one later un-shares both. | §6.11 |
| F5 | My shared note links to a private note | On {name}'s phone the link leads nowhere, as any link to a missing note does. | §6.13 |
| F6 | We want one shopping list both can tick | **Not in this generation.** {name} reads and cannot tick; it needs the partner's editing (the roadmap's N3). | §13 |
| F7 | A shared note with counters or money lines | {name} sees their own counter values and their own currency setting — a ledger can show another currency sign than mine. | §13 |
| F8 | One note alone | Not yet: put it in a shared folder. | §13 |

### 8.4 What {name} shares — my calendar

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| R1 | Something new arrives | One notice with View; drawn in the look I chose. | §6.14, §6.7 |
| R2 | I do not want one of their categories on my calendar | Un-tick it under "{name} shares with you". They never know. | §6.4 |
| R3 | I want to see only mine for a moment | Hide their categories in the calendar's filter; a shared built-in goes by the tick of R2. | §6.10 |
| R4 | I tap their event | The read sheet. | §6.9 |
| R5 | I try to edit, delete, skip a day, mark present | Disabled, in place. Duplicate becomes "Copy to my calendar". | §6.10 |
| R6 | My report, goals, presence, "missed" | Their events are never in them. | D15 |
| R7 | Their category is one they made | It stands under "From {name}", in their colour; never offered for my events. | D14 |
| R8 | Their category is a built-in | Their events join my category of that id, in my colour. | D14 |
| R9 | A singly shared event whose own category was not shared | Drawn as Other. | §13 |
| R10 | I copy their event | It is mine and no longer follows theirs; the snackbar says so. If its category is one I share, {name} will see my copy. | §6.9 |
| R11 | I export my calendar | Their events are left out. | D19 |
| R12 | {name} changes or removes an event | It follows at the next read; an open read sheet redraws or closes with a line. | §6.9 |
| R13 | I am offline | What I last received stays readable. | D22 |
| R14 | I have not synced for a long time | Rows stay; from seven days the Sharing page says "May be out of date". | D22 |

### 8.5 Alerts on what {name} shares

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| A1 | Nothing set | Nothing of theirs rings. | D13 |
| A2 | I want a reminder for one of their events | Add alert, in its read sheet. | §6.9 |
| A3 | I want my phone silent for everything shared | "Off". My alerts on shared events stay stored, dimmed. | §6.8 |
| A4 | Their Gym sessions should ring like mine; all their shifts should remind me | "Category alerts too": my Gym alerts apply; for a category of theirs I add alerts in its sheet. | §6.8, §6.4 |
| A5 | Under A4 my category alert is an alarm | It rings as an alarm. The setting's line says "alarms included". | §6.8 |
| A6 | Under A4 one shared event is too much | It cannot be opted out alone; hide its category or go back to "Only alerts I add". | §13 |
| A7 | {name} moves or cancels the event while my app is closed | My alert fires at the time this phone last knew; the notice says "From {name}", the sheet's caption says why. | §6.8; push §13 |
| A8 | The event leaves while an alert of mine is armed | The alert is cancelled at that read; one snackbar says so; my alert row stays, inert. | §6.8, D23 |
| A9 | The notice's buttons | Snooze, never Skip. | D21 |
| A10 | My digest | Their events are in it only under "Category alerts too", each marked. | D20 |
| A11 | {name}'s own alerts | Never reach me; mine never reach them. | §6.8 |
| A12 | My tablet should stay quiet | The setting is per device. | D27 |

### 8.6 What {name} shares — my notes

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| N1 | Where their folders are | "From {name}", at the end of the root. | §6.12 |
| N2 | I open their note | The editor, read-only; I can select and copy. | §6.13 |
| N3 | I tap a checkbox in it | Nothing changes; once per visit a line says it is read-only. | §6.13 |
| N4 | I try to add, rename, move, label, delete inside their folder | Disabled, in place. | §6.12 |
| N5 | {name} edits the note I am reading | The text updates in place, my scroll position kept. | §6.13 |
| N6 | {name} stops sharing what I have open | The page closes with one line. | §6.12, §6.13 |
| N7 | Search, All notes, Recent | Search and All notes include their notes, marked; Recent never does. | D17 |
| N8 | I want to keep or send one | "Copy to my notes" makes it mine; "Send a copy" is disabled on theirs. | D19 |
| N9 | I do not want a folder of theirs | It stays in its section; folders have no tick. | D11 |

### 8.7 Endings

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| X1 | I un-share | The server refuses {name} at once; their phone drops it at its next read. | D22 |
| X2 | I want everything back, pair kept | "Stop sharing everything". | D24 |
| X3 | Either un-pairs | Both phones drop what the other shared; my marks are cleared; alerts on shared events are cancelled; the looks and the alert setting stay. | §6.2, §6.8 |
| X4 | I stop syncing a database that shares | {name} keeps the last state, frozen; the confirmation says so and how to take it back. | D25 |
| X5 | I delete the cloud copy or my account | Everything I shared leaves {name}'s phone. | foundations §6 |
| X6 | I restore a backup | Marks come back from the cloud after the bind, never from the file. | foundations §8 |
| X7 | I get a new phone | My marks arrive with my sync; the looks and the alert setting are per device and start at their defaults. | D27 |
| X8 | {name} copied something before I stopped | The copy is theirs and stays; the guide says so. | D19 |

### 8.8 When something is wrong

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| W1 | The rules are not deployed, or an index is still building | The shared read fails quietly and is tried again; the page says "Could not check. Will try again." My own sync is untouched. | §6.2 |
| W2 | Offline, or the daily quota is spent | The sync status row says it, as today; shares wait. | §6.2 |
| W3 | {name} and I hold a row under one id (both restored one backup) | Mine stays, theirs is not shown; the page says how many. | §6.2 |
| W4 | Another device of mine has not heard of a new share yet | The share can be partly private for a moment; it errs private. | foundations §3 |
| W5 | A row of mine names a shared row as its parent | Held back, in the existing held-back section. | foundations §7 |

---

## 9. Behaviour

### Must not change

- Nothing is shared without a switch a person flipped; a new pair starts
  with nothing shared.
- The grant as built: one mark and its stamp on a root, everything under
  it derived at encode; a mark is metadata; private wins a disagreement.
- A partner's rows: read-only in the database, never pushed, never
  exported, removed when the grant ends; what a person added of their own
  stays theirs.
- Alerts are opt-in: nothing arms that the person did not ask for, on
  either phone, in any setting.
- An account's own sync — every document it writes for itself, every pull
  of its own space, the cost of an idle launch. An account that never
  paired makes no extra call and sees no new row anywhere.
- The pairing sheet and its code flow; `PairingBloc` apart from `SyncBloc`;
  the Sync & sharing page's other sections and their order.
- Categories: built-ins keep their ids and cannot be deleted; `updateCategory`
  never writes `sort_order` / `is_built_in` / `is_hidden`; the service's
  one mutation chain; `CategoryPickerSheet` the one choosing surface.
- The event editor: every existing row, its order, the draft's equality,
  `_leave()`, Save.
- The browser: positions, sort preferences, move history, selection; the
  two smart rows; a note cannot live at the root.
- The note editor's typing path for my own notes: no new check per
  keystroke, no BLoC on it.
- File sharing through `ImportExportBloc` and `shareExport`; archives and
  backups hold only my rows and no mark.
- `qa pass share` 7/7 and its seams; `qa pass calendar`, `alerts`,
  `browser`, `settings`, `sync`.

### Deliberately changes

- The Pairing row's words while paired, and where Unpair lives; one
  sentence more in the unpair and the stop-sync confirmations.
- The labels of the two file-sharing entries (D9), and "Send a copy" is
  disabled on a partner's rows (D19).
- A partner's event opens a read sheet; a partner's note opens read-only;
  write actions on a partner's rows are disabled where they did nothing.
- A partner's events leave the report, goals and presence figures, where
  today nothing tells them apart; and no category alert of mine arms on
  one unless I chose "Category alerts too".
- Recent no longer lists a partner's notes.
- `sharedTables` has six entries; wire 48; schema 56.

---

## 10. Facts from the tree

Re-grep before editing; lines are of `81f308d3`.

| What | Where |
| --- | --- |
| Mark writers | `CalendarEventService.setShared` `calendar_event_service.dart:616`; `FolderStorageService.setFolderShared` `folder_storage_service.dart:279` |
| "Is it the partner's" | `SharedRowDao.isShared(table, id)` `shared_row_dao.dart:118`; `owner()` `:81` |
| The pair for a surface | `PairingService.status` `pairing_service.dart:172` (`PairingStatus.pairId`, `.partner`, `:30`); `PairingPaired.partner` `pairing_state.dart:72` |
| Shareable tables | `sharedTables` `lib/database/crdt/synced_tables.dart:66`; the reader `sync_shared_reader.dart:22`; marks cleared for another pair `:177` |
| The grant at encode | `SyncTableBinding.sharedPairs` `sync_table_binding.dart:79`; overrides in `tables/calendar_events_binding.dart:30`, `…occurrences_binding.dart:32`, `…skips_binding.dart:31`, `folders_binding.dart:32`, `notes_binding.dart:62` |
| Versions | `database_schema.dart:4` (55), `:16` (wire 47), `:27` (`shareWireVersion`) |
| Rules, index | `firestore.rules:341` (`shareable`), `:352` (`validShare`), `:403`–`:415`; `firestore.indexes.json:12`–`:48` |
| Fences | `lib/database/migrations/shared_row_fences.dart:58` (generated per table), `:71`–`:89` (by hand) |
| Category catalogue | `CategoryService._load` `category_service.dart:186`; `deleteCategory` `:490`; `CalendarCategories.resolve` `calendar_categories.dart:159`; binding `tables/calendar_categories_binding.dart:9`; delete impact `lib/models/category_delete_impact.dart` |
| Event editor | DETAILS group `event_editor_sheet.dart:3097`–`3106`; `show` `:241`; `EventEditorResult` `:69`; opened by `EventSheetsFlow.openEditor` `event_sheets_flow.dart:398` |
| Category editor | groups `category_editor_sheet.dart:928`–`956` |
| Categories page | menu `calendar_categories_page.dart:549`–`578`; sections `:768`; caption `:821` |
| Filter lists | `calendar_filter_sheet.dart:485`; `agenda_filters_sheet.dart:491` |
| The looks | `EventAvatar` `lib/widgets/event_avatar.dart:3`; `CalendarMarkerStyle` `lib/models/calendar_appearance.dart:27`, `CalendarCellStyle` `:167`; the folder row's glyph `folder_row.dart:137`; a note row has none (`note_row.dart`) |
| Alerts | the scheduler's passes over `eventService.events` `alert_scheduler.dart:700`, `:839`; `EventAlerts.effectiveFor` `lib/constants/event_alerts.dart:157`; the reconcile after a sync page `app_sync_apply_hooks.dart:482`; Skip on a notice `lib/bloc/calendar/alert_skip_action.dart` |
| Pairing row, stop sync | `sync_settings_page.dart:306`; the stop confirmation's words `syncStopConfirmBody` in the ARBs |
| Folder menus | `folder_overflow_menu.dart:138`; `folder_row.dart:284`; notes: `note_overflow_menu.dart:124`, `note_row.dart:356`; the picker `lib/widgets/folder_picker_dialog.dart` |
| Browser root | smart rows `optimized_folder_content_page.dart:1951`; groups `:2141`–`2152`; `FolderDao.watchFoldersByParent` `folder_dao.dart:1530`; Recent opens through `AppNavigator.toRecentNotes` `app_navigator.dart:365` |
| Editor read-only | `CodeEditor.readOnly` `packages/re_editor/lib/src/code_editor.dart:306`; the wrapper's literal `modern_editor_wrapper.dart:1091` |
| QA seam | `tool/qa/qa.dart:7758`; `test_driver/qa_agent.dart:177`, `:392`, `:407`; flows `tool/qa/flows/share/01`–`05`; cookbook `.claude/skills/qa-emulator/references/share-pass.md` |

Two locations are left to the brief of their slice, because no decision
hangs on them: where a digest gathers its events, and the query behind
Recent.

Nothing is retired: no widget or constant exists twice after this work.
Three metrics are new (`RowMetrics.shareMarkSize`, `partnerAvatarRadius`,
`FormMetrics.shareOutlineWidth`) and the `designer` names their values.

---

## 11. Slices

Each ends with something a person can do or see, the gate, and a commit on
the owner's word. Sizes as the roadmap counts them (S one implementer run,
M two, L three or more).

| Slice | A person can | Holds | Size |
| --- | --- | --- | --- |
| **0** | pair on the live project, both phones syncing | §5.1 — the owner's steps, no build | — |
| **A — what arrives explains itself** | see which events are the partner's, open one without a dead editor, set an alert of their own on it — and nothing rings unasked | the failing test of §5.2's alert defect first; `ShareService` + fake (§6.1); `fromPartner` on events; the setting keys with their defaults; the event looks — outlined `EventAvatar`, hollow markers, avatar (§6.7); the read sheet (§6.9); write actions disabled, D15's flag in the report, goals and presence (§6.10); the scheduler's predicate at its default, Snooze-only notices, cancel on leave (§6.8) | L |
| **B — a category can be shared** | (through the QA seam) share a category and watch its events arrive, a new one included | §7 whole, with its tests, its rules probes and its device flow; then the owner's second deploy | L |
| **C — give** | open the Sharing page, tick categories, see what goes; switch one on in the category editor | §6.2's page with YOU SHARE and its last group; §6.3; §6.5 (editor, delete impact, the page's sign and menu entry); the sign on what I share (§6.7); the Pairing row's new words; D25's line | L |
| **D — choose what shows and what rings** | hide a category the partner shares, pick the looks, let shared events alert or silence them all | §6.2's other three sections; §6.4 with `SharedCategorySheet`; the partner's categories in the Categories page and the filters (§6.10); the other two values of §6.8, with digests (D20) | L |
| **E — share one event** | switch one event on in its editor; see and stop single events on the Sharing page | §6.6; the events list of §6.2 | S |
| **F — share a folder** | share a folder from its menu; read the partner's folders and notes without a failing save | §6.11, §6.12, §6.13; the notes look and the editor's sign (§6.7); D9's relabel and D19's disabled entries; the folders list of §6.2 | L |
| **G — notices, guide, proof** | hear that something arrived; read how sharing works | §6.14; a "Sharing" page in the app guide (`app_guide_content.dart`) that states the three promises, that both phones must sync, that a share is read-only (so a list cannot be ticked by both), and that a copy stays; one paragraph in "Where your data is stored" saying what the partner can read; the surface flows added to `qa pass share`; the matrix in dark, `de`, 2.0 on both phone sizes; `qa errors` clean; the docs (§12, last item) | M |

Order: 0, A, B, C — the owner's request works after C — then D, which
makes it comfortable to live with, then E, F, G. A comes before B because
it needs no schema, closes the alert defect, and the two-guest suite can
prove it at once with the seams that exist; B before C because C's switch
has nothing to write until B lands. F opens the note editor and the
browser, the two pages that carry the app: it runs alone.

---

## 12. Definition of done

1. On two phones, paired: ticking Work on one shows every Work event on
   the other within one read, in the chosen look; an event added to Work
   afterwards arrives with no second act; un-ticking removes them all; the
   other phone's own events, alerts and report figures are what they were.
2. An event moved out of a shared category leaves the partner's phone; one
   moved in arrives; deleting a shared category takes its events off the
   partner's phone unless their new category is shared, and the delete
   sheet said which.
3. A shared built-in category draws in the reader's own colour; a shared
   custom one in the sharer's, under "From {name}"; neither is offered in
   the reader's picker; a reader's event cannot be given the partner's
   category.
4. Un-ticking a received category removes its events from the grid, the
   lists, the filters and the scheduler at once, with no restart; ticking
   it brings them back with no read.
5. With nothing set, no alert fires for any partner's event — a shared
   built-in whose category on this phone has an alarm included. An alert
   added in the read sheet arms on this phone only. "Off" disarms it and
   keeps the row. "Category alerts too" arms the category's alerts, and
   the read sheet lists them. A shared event that leaves takes its armed
   alerts off the platform (proven as the alerts suite proves an armed
   alarm). No notice of a shared event offers Skip.
6. A partner's event opens the read sheet; "Copy to my calendar" makes an
   event that is fully mine.
7. A shared folder appears under "From {name}" with its notes; inside it
   nothing can be created, renamed, moved, labelled, deleted or sent, and
   nothing says "save failed"; a note opens read-only, with no keyboard on
   tap; a change by the sharer redraws it in place.
8. Each look draws as §6.7 says, in light and dark, for every category
   colour and both marker styles; changing it repaints the open calendar
   and the open browser with no restart; with "Like mine" a partner's
   event still opens the read sheet and TalkBack still says "From {name}";
   with "Mark what you share" off no sign shows and the Sharing page still
   lists everything.
9. Not paired: every editor, menu and page is byte-for-byte today's, and a
   launch makes no extra call. Paired without sync: the rows are there,
   dimmed, and say why.
10. Every case of §8 has a test or a device flow that walks it, named
    after its number.
11. Every share row keeps one height in every state; 48 dp targets; light
    and dark; en, de, ro with `{name}` never declined; text scale 1.3 and
    2.0 with no clipped label — the German "Mit {name} teilen" with a long
    name included; `untranslated.txt` empty.
12. Every new sheet is in `sheet_bottom_clearance_test.dart`; every new
    row has its `SemanticsIds` entry; the Sharing page, the three sheets
    and the switches ship with widget suites against `ShareService`'s
    fake; the existing suites of the event editor, the category editor,
    the Categories page, the browser and the note editor pass unchanged
    where behaviour did not change.
13. `qa pass share` green with its new flows; `qa pass calendar`,
    `alerts`, `browser`, `settings` and `sync` green.
14. Docs in the same change: this record's status line and an as-built
    section; `cloud-sharing-foundations.md` §12 for slice B;
    `cloud-multi-user-roadmap.md` §3 (E1, E6, E7, N1 marked) and its
    status; `anta-context/references/sync-and-accounts.md`, the
    `calendar-events` and `markdown-engine` references for the facts; one
    rule line in each area skill (a surface asks `ShareService` before it
    offers an edit; a partner's rows never reach a report, an export or an
    unasked alert).

---

## 13. Deferred

Cut on purpose; each with enough to resume from.

- **The partner edits** (the roadmap's E5, N3) — the first thing two
  people will ask for after this ships, because a shared list cannot be
  ticked by both (F6). It needs a consent switch per person, a write rule
  for the grantee, the grantee's edits routed to the owner's space, and
  conflict copies across two accounts.
- **One note shared by itself.** Needs `notes.shared_pair` (schema, the
  derivation "its own mark, else its folder's", the space's `sharedPair`
  counting notes) and a place on the reader's phone, since a note cannot
  live at the root: a device-local folder under "From {name}" is the
  likely answer.
- **A private event inside a shared category** (D3's other option): a
  third state on the event (set / inherit / refused), a third position on
  the editor's control, and the derivation's `COALESCE` made to honour the
  refusal.
- **"Busy only" and "from today on"** (D4): a second, derived document per
  shared row, written by the owner's device, which the partner reads
  instead of the row.
- **"Share everything, always"**: a mark on the calendar itself, so a new
  category is born shared.
- **One shared event opted out of category alerts** (A6): a personal row
  per event, since the switch that exists lives on the partner's row.
- **Push while closed** (the roadmap's P6): what makes A7 true to the
  minute, and X1 instant.
- **Receipts** (S3): the reader writing "last read at" where the sharer
  can see it — one write per read, and a thing the other person can watch.
- **A singly shared event in a custom category that is not shared** draws
  as `other` (R9). The fix: the event's document carries its category's
  name, colour and icon while it is shared alone.
- **A tick per received folder** (N9), should the section ever grow long.
- **Presence on a partner's event.** The rows are personal and the
  foundations keep them; the read sheet does not offer the control.
- **The partner's counters and currency on a shared note** (F7): the
  note-data settings of the roadmap's N1 (readiness D10).
- **More than one partner** — §14.

---

## 14. More than two people

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
- Every string takes `{name}`; none assumes one person, and the look and
  alert settings name nobody.
- The share row keeps its place and its height when it becomes a pick row
  ("Share with · Maria, Family ›", opening a tick list) — the mock's last
  strip.
- The Sharing page is already a page per audience; the Pairing section
  becomes the list of them.
- "From {name}" sections and the Avatar look go by the owner of a row,
  not by "the partner".

What it does not do: store more than one pair on a row, or let a third
account join a pair. Both wait for the owner's word and their own record.

---

## 15. As built

One subsection per slice, appended as each lands. The sections above are
the plan as decided; where the build differs, this section says so and is
the truth.

### Slice A — what arrives explains itself (2026-11-12)

Led by Fable 5.2; built by Opus 5.5 implementers in parallel worktrees
from the lead's briefs; the looks, the read sheet, the timeline and the
hub from three designer specs (rendered with real fonts first); reviewed
by two code reviewers and a design reviewer, their findings fixed in the
same commit. Gate: `dart analyze lib test` clean, the whole suite
`+16345 ~17, plus the delete-all case that fails only under machine
load and passes run alone`.

**What a person gets.** A partner's event is told from mine everywhere it
is drawn, in the look the person chose; a tap opens a read sheet, never
the editor; nothing of the partner's rings unasked; their events are in no
figure about my time; no write and no door out touches them.

**The pieces.**

- `ShareService` (`lib/services/share_service.dart`), on the
  `DatabaseLifecycle` reset contract, opened lazily: `availability`
  (`ShareNotPaired` · `ShareNotSyncing(audience)` · `ShareReady(audience)`)
  and `changes`, which replays its last value; the audience is one person
  (id, a nullable name, members as `AppUser`). A stored pairing counts only
  for the signed-in account. It hears this device's own pairing writes
  through a new `PairingService.written` — `changes` would have handed
  `PairingBloc` a second state mid-action. `setEventShared` /
  `setFolderShared` refuse unless ready (`ShareRefused`) and then ask
  `SyncEngine.pushNow()`: a drain-only run under every cadence (under the
  manual one a stale run would pull every table).
- `CalendarEvent.fromPartner` — transient, in `props`, set where
  `CalendarEventService` maps its rows (the shared owner is asked only
  when a row names an owner, so a never-bound database pays nothing).
- Settings (`lib/models/share_settings.dart`, `SettingsKeys`):
  `shareEventLook` (outlined · avatar · plain), `shareMarkMine`,
  `shareAlerts` (off · own · category), `shareHiddenCategories`. Their
  keys sit outside the pairing prefix, so a restore carries them.
  `shareNoteLook` is not built (slice F).
- Alerts. The defect §5.2 predicted was real: the first test showed a
  category alert of mine arming on a partner's event. One predicate,
  `ShareAlerts.inheritsOn(event)`: nothing under `off`; only my own alerts
  on that event under `own`; my category's too under `category`, whatever
  the partner's own switch says. A partner's event takes its category by
  its **raw id** — an id this phone does not hold inherits nothing, never
  Other's (a review finding: under `category` my Other's alerts armed on
  every partner event in an unknown category). `EventAlerts.effectiveFor`
  takes `inherit`; the badges, the hub and the digests (D20: only under
  `category`, each expanded line "· From {name}") follow the same
  predicate. A leave cancels what was armed; my alert rows stay, inert.
- Notices (D21). `AlertPayload` gains `fp` / `pn` (absent = mine, so
  payloads of the shipped build keep working); the arm grammar token moved
  to `~g5`, which re-arms standing entries under their own ids; the flag
  and the name are part of the arm signature for a partner's event only.
  Title "{title} · From {name}" on every tier and on the ring screen; no
  Skip; a partner's upcoming notice offers Open alone; `removeAfterAlert`
  is never honoured on a partner's event; no "Open note" on its session
  chip.
- The belt. `CalendarEventService` refuses a write of a partner's event
  by name (`SharedRowException`); `EventSkipService` and
  `EventOccurrenceService` ask `SharedRowDao.ensureOwn` before a write;
  `CalendarBloc` ignores skips and per-day texts on one. Nothing answers
  "saved".
- "Copy to my calendar" — `CalendarEventService.copyToMine(event, day)`
  behind a bloc event handled like a create (alerts reconciled, the ledger
  refreshed): title, time, repeat, priority, the event's own look, the
  opened day's text, its category when I hold that id as my own, else
  Other; stamped now, a new id, no mark, none of my alerts, no note.
- D15. `fromPartner` is asked where each reader takes its events: the
  report (`_Scoped.of`, its Markdown), goals, presence
  (`EventPresence.appliesTo` — the one gate most readers share), the day
  rail (`eventInDayRail`), the day tint, the overview's Years tiles and
  totals, the grid's "tracked only" and "missed" filters, "Delete all
  events". Two counts follow what their own list shows and keep the
  partner's events: an Upcoming card and its drill-down tiles, and the
  overview's Month / Week caption.
- The looks (`slice-a-spec`, decisions a–q). `EventAvatar` gains
  `outlined`, `badge`, `semanticsLabel` and `EventAvatar.ofRow`; the day
  panel and the agenda card now draw `EventAvatar` (pixel-identical for
  mine). One contrast rule, `MarkerContrast.atLeast(color, ground)` — an
  HSL-lightness walk to 3:1 against the ground a mark actually sits on,
  measured on the 8-bit pair that is painted. Hollow twins for the grid's
  bars and dots (`DayBar.hollow`, `CalendarDayBars.groundOn`), in the
  overview's month grid too; a partner's event never joins the day rail.
  `PartnerLook` carries the look and the partner to the rows from the
  page's settings state — never a lookup per row; a change repaints on
  return from settings.
- The read sheet `SharedEventSheet` (`lib/widgets/shared_event_sheet.dart`),
  the sibling of `EventDetailSheet`: both doors of `EventSheetsFlow` route
  a partner's event to it. The rows the two sheets share live in
  `event_read_rows.dart`, the alert rows the editor and the sheet share in
  `event_alert_rows.dart`. My alerts are written through a `SetEventAlerts`
  bloc event, handled one at a time. The sheet follows the event and
  closes its own route when it leaves — a review probe showed it popping
  the alert editor above it and locking the navigator.
- The day timeline and the Alerts hub (`slice-a2-spec`, ga–gj): outlined
  blocks and chips, a 20 dp face on a block's title line under Avatar, a
  ring or the face for the hub's glyph. The ring screen's avatar and the
  Android notification's icon are unchanged: their title says whose it is.

**Where the build differs from §6.**

- The Avatar look and the sign on what I share are a corner badge on the
  event's avatar, not a glyph at the row's end (the end slot cost 34 dp of
  title at every scale). **The owner saw the mock with the end slot; the
  badge is the designer's default, taken by the lead.**
- No Linked note row and no note button on a partner's event: nothing in
  this build may open the ordinary editor on a partner's note (slice F).
- Under `off` a partner's event has no effective alert, so no badge is
  drawn (the spec dimmed it).
- The read sheet mirrors the detail sheet's order (title and description,
  WHEN, YOURS, DETAILS, copy, caption); its Dates row is a plain read row;
  measured heights 497 / 627 / 718 dp where the spec said 497 / 621 / 700
  (real wording wraps).
- The audience is singular in `ShareAvailability` (§14 spoke of a list
  with one entry).
- Copy: `shareStopAllConfirm`, `shareTheirCategoriesCaption`,
  `shareMarkMineDesc` reworded so `{name}` never starts an inner sentence
  and folders are not promised; the stand-in for a partner without a name
  is "your partner" / "Partner" / "partenerul tău", capitalised by
  `ShareCopy.sentence` where it starts a string.

**What the reviews found** (all fixed unless marked).

- The read sheet popping the wrong route (reproduced); the copy going
  around the bloc, so its inherited alerts were never armed; a leave during
  a copy losing the copy's editor; two quick alert removals able to land
  out of order.
- Other's alerts on a partner's event in an unknown category (reproduced);
  `ShareService`'s open not generation-safe to its end; `pushNow` pulling
  every table under the manual cadence; the partner flag and name missing
  from the arm signature.
- Costs for a database that never paired: the shared-owner read per load,
  a scan of every event per change, a refold on every drill-down open —
  all removed.
- Design: the sheet's header was not a heading (now opt-in on
  `FormSheetHeader`); one hollow marker at 2.99:1; no guideline tests on
  the new surfaces.
- Kept as built: a window in which an alarm armed by an older build on a
  partner's event shows a Keep that does nothing — no shipped build could
  share, so no such entry exists.

**Owed to a device** (the closing device pass): the partner's real photo
at 20 dp; the hollow dot at dpr 2.625; TalkBack on the three lists and the
sheet; task boxes in a partner's description; the nested duplicate ids
under `tap --id`; the 200 % font scale in German; the sheet's bottom
clearance.

**Seen, not this slice's**: 15-minute timeline blocks are under the 48 dp
target and hour labels clip at text scale 2.0; today's filled avatar icon
is under 3:1 on its own fill for about half the palette; sheet titles and
section labels are not semantic headings app-wide.
