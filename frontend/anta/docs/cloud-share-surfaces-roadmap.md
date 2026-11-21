# Share Surfaces — ANTA

**Status: BUILT 2026-11-12 → 14, whole — the calendar side (slices A, B,
C, D, E and G: `6f6b8c62` A, `9bb22e4f` B, `da3a892b` C and E, `1e054564`
D, `7cde4038` G; the closing reviews `3395137f` and `fa3af0ad`), then
the finishing pass of §16: slice F (folders, the partner's notes), the
filters and the alerts (H), the check with the app closed (I), the relay
(J) and the debts (K), committed as they stood at the pause in
`daa6d9c4`, and the fixes that answered the pass's final reviews and
what the device found (`7803e07a`), which §16.9 accounts for. §15 says what is built and is the truth over the
plan above it — a later block over an earlier one.** The mock is
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
16. The finishing pass (2026-11-13)
17. The correctness review (2026-11-21)

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

1. **The region move (R1)** — `eur3`. **Done 2026-11-13** by the owner:
   the database was deleted and created again in `eur3`, the phone
   uploaded again (`cloud-multi-user-roadmap.md` §9). It deleted the live
   database, so it came before the partner's data reached the cloud; a
   location cannot be changed later without every device uploading again.
2. **The rules and indexes deploy**:
   `firebase deploy --only "firestore:rules,firestore:indexes" --project alexs-note-tracking-app`
   (quoted, in PowerShell). **Done with the move for the rules of
   `b1046f23`** — slice B's category rule and index included — so only a
   build of that wire can pair. The finishing pass (§16) changes the
   rules once more (the pair's `push` field, `config/push`): one more
   deploy is due when that is committed.
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
- **"All of mine" in an allowlist** (found in slice D's review). The
  agenda's and the overview's category filters are allowlists; with a
  partner's group listed, "only mine" is an explicit list, and a category
  created later stays out until the filter is opened again. The way out
  that keeps the stored shape: a reserved token for "all of mine" beside
  the partner's ticked ids — `EventAgenda.passesEventFilters`, the two
  sheets' `_pickCategories`, `CalendarFilterSummary.allowlistLabel`. A
  saved overview view syncs, so every device must know the token before
  one writes it.
- **The import line** (§6.14's last row): for the day an import can land
  events in an existing category. Today the only import that carries
  events is a backup restore, which replaces the categories and unbinds
  the database.
- **What slice F finds waiting in the built surfaces**:
  `ShareService.setFolderShared` is not one transaction; the Sharing page
  has no Folders entry and no "Notes shared with you" row;
  `shareMarkMineDesc`, the stop-all confirmation and the guide's "What is
  never shared" row name no folders; a partner's event shows no Linked
  note.
- **The partner's Single events, opened from the Sharing page, open
  nothing**: Sync & sharing holds no calendar. The door is
  `PartnerSharedEventsSheet.onOpen`.
- **A digest restricted to categories** lists mine only.
- **Who ended the pair**: the leave notice after an unpair says "your
  partner"; knowing who ended it would let the notice say nothing when I
  did.
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

### Slice B — a category can be shared (2026-11-12)

Built by Opus 5.5 implementers in parallel worktrees (the owner's side,
the reader's side, the catalogue), reviewed by two Fable 5.2 reviewers —
one on what leaves the phone and the rules, one on what the receiving
phone stores — and fixed in the same commit. Gate: `dart analyze lib test
tool test_driver` clean; the whole suite `+16482 ~17`; the rules suite
163/163 against the Firestore emulator; the two-guest device suite
``qa pass share` 13/13, twice in a row on freshly started emulator suites`.

**Schema v56, wire 48.** `calendar_categories` gains `shared_pair` and
`shared_stamp` with the partial index `idx_calendar_categories_shared_pair`;
v56 also drops and re-creates the fences. A 47 build is refused by the
space; a database that last ran at 47 reads `calendar_categories` again
from the start, once (46 → 48 reads events and folders too).

**The owner's side.**

- `CalendarCategoryDao.setSharedPair` / `clearOtherPairs`,
  `CategoryService.setShared`; a mark set through any of the three tables
  clears another pair's marks in all three.
- The grant at encode: `CalendarEventDao.sharedPairsOf` =
  `COALESCE(e.shared_pair, c.shared_pair)` over the event's **live**
  category, joined on the stored id. Decided here: an event's own mark
  wins; a tombstoned or missing category grants nothing (an event on a
  dangling id drawn under Other does not take Other's mark); an archived
  category still grants; a category's mark reaches only the person's own
  events; the derived grant's stamp is the newer of the event's
  `hlc_timestamp` and its category's `shared_stamp`.
- Re-sends (no new stamp, tombstones included, real writes first) when a
  category's mark is set or cleared, when an event changes category where
  the grant differs (`upsert`, `reassignCategory`, `importAll`,
  `mergeRemoteEvent`), when a marked category is deleted, merged as
  deleted or wiped by a restore.
- **A delete ends the grant for good**: a category that comes back from a
  tombstone — a merge, or `seedMissing` reviving a built-in — comes back
  private, by a stamped clear of the mark. (The review reproduced a
  deleted shared category revived by another device's rename, shared
  again, taking a new event with it.)
- **The marks' cutover holds the drain**: a database whose marks are still
  unread after a wire bump pushes none of the tables concerned until their
  re-read has completed — 46 → 47 as well as 47 → 48. (Reproduced: a device
  updated from 47 pushed a queued rename before its re-read and ended the
  share.)
- A tombstone a device never held the data of is not "corrected" to
  private: its document carries no content, and the device cannot know
  the grant. Events only; the older tables keep the foundations' rule.

**The server.** `firestore.rules`: `shareable()` gains
`calendar_categories`, one read block for the collection group;
`firestore.indexes.json`: one entry (`sharedPair`, `ownerId`, `pushedAt`).
Nothing else changed. **Both files must be deployed before this build
reaches a phone** — until then a category's document is refused and the
reader's category query fails ("Could not check. Will try again.").

**The receiving phone.**

- `sharedTables` lists `calendar_categories` first. A partner's own
  category is stored under their `owner_id` with `sort_order` 0, shown, not
  built-in, no mark; `CalendarCategory.fromPartner` says whose it is;
  the catalogue lists mine by order, then the partner's by name.
- A built-in id is always refused and recorded
  (`SharedRowDao.sharedBuiltIns()`): the partner's `gym` events resolve to
  my `gym`. `seedMissing` evicts a partner's row under a built-in id before
  it seeds mine, so a build that learns a new built-in later is safe.
- An id of mine is refused and counted (`refusedCount`, which counts
  categories, events, folders and notes — never an event's day rows). **An
  id my own events or templates name is mine too**, even with no category
  row under it (two accounts restored from one backup).
- Refused documents count toward the reader's `countOf` for every shared
  table, tombstones included, so a leave is noticed by the count instead
  of waiting for the daily read; an account with no refusal pays nothing
  for it.
- Fences: the generated set covers categories; four by hand keep an event
  or a template of mine from taking a partner's category. The writers
  refuse first, by name (`SharedRowException`), before anything is stamped
  or queued — a save that answers "saved" must have stored.
- A row of mine under a partner's category (colliding ids) is held back
  from my own pull (`SyncHeldReason.sharedParent`, worded "Waiting for its
  folder, event or category") and lands when the share ends, at the next
  start or "Sync now".
- `CalendarCategories.visible` / `visiblePlus` and `CategoryService
  .categories` hold mine only; `resolve`, `all`, `byId` hold both;
  `.partner` the partner's. `updateCategory`, `setHidden`, `reorder`,
  `deleteCategory` refuse a partner's category; `tombstoneCascade` never
  reassigns onto one. Exports carry no partner's category and no mark; the
  .ics export asks whose the **event** is.
- My category alerts and profile on a partner's category that left stay
  stored, inert, as my alerts on a shared event do.

**Costs, pinned.** No network call for an account that never paired. Local
statements the slice added on the unshared path: the grant join per push
part that holds events; one select on a save or a merge that changes an
event's category; `reassignCategory`'s fourth statement; one local read
per templates page of the own pull.

**Kept as built, known.** A day row can be shared for a moment while its
event's document is still private (another device pushed the event before
it heard of the mark); it errs private and heals at that device's next
sync. `clearOtherPairs` re-stamps a tombstoned category, as events and
folders do. Held-back rows land at the next start or "Sync now", not at
the read that freed them.

**The device suite.** `qa share category "<name>" [--off]` beside the event
and folder seams; six flows `04a`–`04f` in `tool/qa/flows/share/` (a
shared category arrives, grows, shrinks and is renamed; the read sheet and
the copy; un-share; a shared built-in joins mine; a deleted shared
category). Cookbook: `.claude/skills/qa-emulator/references/share-pass.md`.

**Not done, by choice.** `CalendarEventDao.upsert` does not itself refuse
a row that is the partner's (the service's check and the fence cover it).

### Slices C and E — give (2026-11-12)

Built together, because the Sharing page lists what slice E's switch
writes. Opus 5.5 implementers in parallel worktrees — the primitives, the
service layer, the Sharing page, the category editor with the Categories
page, the event editor with the Single events sheets — from one designer
spec rendered with real fonts first; reviewed by two code reviewers and a
design reviewer, whose findings seven fix runs closed in the same commit,
each fix pinned by a test of its own. Gate: `dart analyze lib test
tool test_driver` clean; the whole suite `+16739 ~17`; `untranslated.txt`
empty. The device flows of the surfaces come with slice G.

**What a person gets.** While paired and syncing: "Share with {name}" is a
switch in a category's editor and in an event's editor, and an entry in
the Categories page's ⋮ menu. Sync & sharing's Pairing row reads "Paired
with {name}", says what is shared and opens the Sharing page: what I share
— categories through a tick sheet, single events through a list with a ✕
each — "Stop sharing everything", and Unpair, which moved there. Every
change says what it did, with Undo. A shared category and a shared event
wear a small sign where they are listed, and say "Shared with {name}" to a
screen reader. An account that never paired sees none of this.

**The pieces.**

- Primitives, each opt-in with every existing caller unchanged:
  `SettingsSectionData.trailing` / `trailingTemplates`,
  `SettingsEntry.descriptionMaxLines`, `FormMenuItem.caption` (a disabled
  item's reason stays at full strength), `FormSwitchRow.subtitleTemplates`
  / `subtitleFitsTemplates` / `onDisabledTap` / `onDisabledTapHint`,
  `FormPickerRow.captionWraps`, `FormPickerSwitchRow.leading` / nullable
  `onTap` / `switchSemanticsLabel` / `enabled`;
  `FormMetrics.receivedCaptionMaxLines`, `RowMetrics.avatarTextInset`.
  `CustomSnackbar.showWithAction` holds its messenger from the moment it
  shows, so its action still dismisses the bar after its page has left.
- The models say what is shared with no lookup per row:
  `CalendarCategory.sharedByMe`, `CalendarEvent.markedShared` (the event's
  own mark), `CalendarCategories.shareOf(event)` → `EventShareVia?` (its
  own mark, or its category's), `CalendarCategories.anySharedByMe`.
- `ShareService`: `setEventShared`, `setCategoryShared`,
  `setCategoriesShared(Set<String>)` (the tick sheet's Done, as one act),
  `undo(ShareChange)`, `stopAll()`, `overview()`, `refreshShared()`.
  `ShareChange` names what an act wrote — and how many events of an
  un-shared category stay shared by their own mark — for the snackbar and
  its Undo. `ShareOverview` is what the page lists, the tick sheet's
  counts included.
- **An act is whole.** Its marks are written in one transaction through
  the DAOs' writers; a write that throws takes the act's earlier ones with
  it, so a failure said is a failure true. The category catalogue and the
  event cache read their marks again once, after the act, whatever its
  end. This is where the build leaves §9's "the service's one mutation
  chain": the catalogue's chain could not hold that transaction — a link
  queued ahead of it waiting on the database would wait on the transaction
  itself — so `CategoryService.setShared` and
  `CalendarEventService.setShared` remain for the QA seam and the tests,
  and SQLite keeps a delete of the same category out of the act.
- `ShareBloc` (`lib/bloc/share/`): `ShareOpened` (load, follow, and ask
  for one shared read — D22), `ShareLoadRequested` (the Pairing row's
  summary: no read), the four acts as one ordered queue (`ShareActEvent`),
  an outcome per act with a sequence number so two equal ones both reach
  the snackbar, `ShareLoadFailed` for a first load that threw. It reads
  the overview again when the read it asked for ends and as each sync run
  ends.
- `SyncEngine.readSharedNow()`: the shared read alone, under every
  cadence, never beside a pull or a drain; merged into a run nobody asked
  for it does not lift that run past the manual cadence, and it never
  spends the access recheck a resume owes. `ShareService.refreshShared()`
  asks for it at most once a minute (`sharedReadMinAge`) and completes
  when it has ended.
- What the page's status says, exactly: "Sending…" from a share act until
  the outbox holds no entry of the shareable tables (`SyncDao
  .keyShareSending`, cleared in the transaction that finds it drained —
  an ordinary save while paired says nothing); "Could not check" only
  after a read that failed as one (`keySharedReadFailedAt` newer than
  `keySharedReadOkAt`; a read the app's leaving cut records nothing);
  "shares anything" is the database's answer (`SyncDao.anyShareMark()`),
  folders included.
- A mark the reader cleared — a pair that ended, or was made again —
  reaches the caches (`SyncInvalidation.shareMarks`), so no row keeps a
  sign for a share that is gone; and the sign needs a partner
  (`PartnerLook.unpaired`): marks left behind by an unpair draw nothing.
- Counts: `countByCategory()` counts my events only;
  `countPartnerByCategory()` the partner's.

**The surfaces.**

- `lib/pages/sharing_page.dart` — the settings kit. Built here: YOU SHARE
  (Categories, Single events) and the last group; slice D adds the three
  sections between them. The intro and the reason "Turn on sync to share"
  share one slot sized by the taller, so the entries never move, at open
  or mid-visit. A load that fails says so in one line and still offers
  Unpair.
- The Pairing row (`sync_settings_page.dart`): id `sharing-paired`, the
  summary in a fixed-lines slot; `sharing-unpair` and its confirm moved to
  the page. Stopping sync while this database shares something says what
  the partner keeps (D25), asked at the tap: a tap before the first read
  waits for it, for at most `SyncLimits.stopConfirmShareRead`.
- The tick sheet is `CategoryPickerSheet.pickMulti` with a title, a
  caption and counts; a category created inside it arrives un-ticked
  (`tickCreated: false`, case C9).
- `lib/widgets/share_events_sheets.dart`: `MySharedEventsSheet` (each row
  a ✕, snackbar with Undo; a row returns only when its Undo was written;
  a past event's date carries its year; nothing is cut at German 2.0) and
  `PartnerSharedEventsSheet` (read-only; slice D opens it).
- The category editor's SHARING section (`CategoryEditorSheet.open` →
  `CategoryEditorResult{category, share}`), the delete sheet's sentence
  about what the partner stops or starts seeing, the Categories page's ⋮
  entry, caption and sign. A share chosen for a new category is written
  as the editor returns, before the row's reveal.
- The event editor's `event-share` row: one height in every state (62 dp
  at 1.0, whatever the category names), on and locked while its category
  is shared, following a category pick. **The share choice rides the
  save**: the create and the update events carry it, and the handler sets
  the mark only after the row is stored — a save that failed shares
  nothing, and a mark that could not be set is said as such.
- Both editors follow sync turned on: back from Sync & sharing they ask
  their opener again and the row is live, the draft still clean.

**Decided in the build** (each differs from, or adds to, the plan above).

- No Folders entry anywhere: slice F is not built.
- The Sharing page leaves only when the pairing itself says the pair is
  gone. A pair another account made on this database (the share service
  says "not paired", the pairing still stands) keeps the page open on its
  last group, so that pair can still be ended. Leaving closes what the
  page opened above itself first; Sync & sharing's "pairing ended" notice
  stays on top.
- A dimmed entry or switch that leads to Sync & sharing is announced as
  an enabled button with the hint "Opens Sync & sharing", never as a
  disabled control that acts; from the Sharing page that tap goes back,
  not forward. A disabled switch that is on keeps Material's own disabled
  colours with no second dimming, so "on" still reads on.
- An Undo outlives the surface that offered it: through the bloc while it
  is open, through `ShareService.undo` once it is closed — the one place
  a surface writes past its bloc — with a failure said on the app's
  messenger.
- An archived category that is not shared yet is not in the tick sheet
  (the picker lists what it lists everywhere); it is shared from the
  Categories page's menu.
- "Stop sharing everything" is offered while not syncing — clearing marks
  needs no sync — and says nothing on success: its confirmation was the
  conversation.
- My Single events rows have no tap: the list is for stopping, the
  calendar for opening.

**Costs, pinned.** Someone who never paired: the Sharing surfaces read
nothing and add no await before an editor or the Categories page shows —
"not paired" is answered from memory (`PairingService.pairedInMemory`).
The one exception is the first editor of a session opened before any
pairing service was built: it opens the share service once (local reads,
no network), since nothing in memory can yet tell a never-paired database
from a paired one that shares nothing. No pass over the events for an
account that shares nothing (`mayHoldPartnerEvents`, `mayHoldOwnMarks`).
A paired account: the overview's reads on each load of the Sharing page
or the Pairing row's summary, one keyed read for "Sending…" while no act
is in flight, and one shared read per page open at most once a minute.

**Kept as built, known.** If the pair ends while one of the Sharing
page's own confirmations is on top and Sync & sharing has not raised its
notice yet, that confirmation is taken for the notice and outlives the
page; its answer is ignored. An Undo from the Categories page that fails
after that page has left is logged, not said. In the mode no share row
uses, a disabled `FormSwitchRow` still dims its switch twice (its callers
stay pixel-identical).

**The device suite.** Flows `00`, `05` and `06` follow the Unpair entry
to its new page; the cookbook's two sentences about it are corrected. The
surfaces' own flows, and the run of all of them, come with slice G.

### Slice D — choose what shows and what rings (2026-11-12)

Built by Opus 5.5 implementers in parallel worktrees — the service layer,
the two sheets, the filter lists, the Sharing page's receiving half, the
remaining lists, the Categories page's section — from the designer's
slice D spec; reviewed by three code reviewers and a design reviewer.
Their findings are fixed in a commit of their own, after slice G's ("The
reviews of the receiving side", below). Gate: `dart analyze lib test tool
test_driver` clean; the whole suite `+16915 ~17`.

**What a person gets.** The Sharing page's other three sections: what
{name} shares with me (categories, single events), how shared things look
(Outlined · Avatar · Like mine, and whether what I share is marked), and
alerts for shared events (Off · Only alerts I add · Category alerts too).
A sheet of the partner's categories with a switch each: a hidden one
leaves my calendar at once — the grid, the lists, the filters, the
figures, the alerts — and comes back with no read. A sheet for one of
their categories, where I keep my own alerts for it. Their shown
categories on the Categories page under "From {name}", and in the filter
lists as a group of their own.

**The pieces.**

- **Hiding is one predicate, in one place.** `shareHiddenCategories` holds
  the hidden ids, per device. A partner's event in a hidden category is
  left out where `CalendarEventService` maps its rows — the whole load
  and a pull's keyed patch alike (`_sharingOf`, `_shown`) — so nothing
  that reads the cache can disagree about what exists; the rows stay
  stored and current. My own events in a built-in the partner shares
  stay. `ShareService.setCategoryShown` writes the set, publishes
  `CalendarCategories.partnerShown`, reloads the events once (local, no
  network), tells the open calendar and runs the alert pass.
- **The hidden set stays true.** The shared reader prunes it after every
  read (`_keepHiddenShared`): an id leaves when its category is un-shared
  or deleted, when a built-in stops being shared, and when the pair ends
  or changes — so sharing it again starts shown.
- `CalendarCategories.partnerShown` (the partner's own categories shown
  here, by name; never a shared built-in), `updatePartnerHidden` (it does
  not bump `revision`: hiding changes which events exist, never what an
  id resolves to).
- `ShareBloc`: `ShareCategoryShownSet`, `ShareEventLookSet`,
  `ShareMarkMineSet`, `ShareAlertsSet`; `ShareLoaded.look` and `.alerts`.
  **A setting shows from the tap**: the bloc lays the writes still in
  flight over every state it emits, so a switch never waits on the
  calendar's reload and the read after an earlier write cannot flip a
  later one back for a frame; a failed write draws back to what is
  stored.
- `ShareOverview.partnerCategories` (`PartnerSharedCategory{category,
  joinsMine, shown, eventCount}`), `partnerEvents` (shared one by one),
  `isStale(now)` (D22: seven days, `staleAfter`).
- My alerts for a partner's category are rows of my own keyed by its id
  (`EventAlertService.replaceForCategory`): nothing of mine reaches the
  partner and nothing of theirs reaches me.

**The surfaces.**

- The Sharing page, sections 2–4. The header's end says "Updated {when}"
  or, after a failed read, "Could not check"; the reason "Turn on sync to
  receive" takes the intro's place in one slot; "May be out of date",
  "Update ANTA to see everything {name} shares" and "{n} items could not
  be shown" are held from the page's first loaded state for the visit, so
  the entries never move. The look is a choice row, the mark a switch,
  the alerts an entry with a menu of three captioned items.
- `SharedCategoriesSheet` (a filler): one row per category the partner
  shares — their own by name, then the shared built-ins in my page's
  order. An own category's row is two targets (the row opens its sheet,
  the switch shows or hides); a built-in's row is one, and toggles. A
  hidden row dims its avatar only.
- `SharedCategorySheet`: who it is from, the show switch, and ALERTS — my
  alerts for it, each written at once and in order; inert, in place, with
  the caption that says why, under "Off" and "Only alerts I add" and while
  the category is hidden. It closes itself when the category is no longer
  shared.
- The Categories page's "From {name}" section: after Archived, outside
  the reorderable list, read-only rows that open that sheet; absent when
  nothing is listed.
- The filters: `CategoryPickerSheet.pickMulti(partner:, partnerLook:)`
  lists the partner's shown categories under "From {name}" for the grid's
  denylist, the agenda's allowlist and the overview's; Select all / none
  act on both groups; "everything listed is ticked" still stores nothing.
  The chips and a saved filter's subtitle count the same lists. An
  Upcoming card of a partner's own category wears the event look and says
  "From {name}".

**Decided in the build.**

- The partner's own categories list **by name** everywhere: the reader
  stores every one of them at sort order 0 — their order is no place in
  my list — so the stored order would be by id.
- The partner's Single events, opened from the Sharing page, are
  read-only rows with no tap: Sync & sharing holds no calendar to open an
  event sheet on. Where a calendar opens the list, a tap opens the read
  sheet.
- The agenda's category chip keeps its wording, "Categories (N)"; only
  what it counts changed — the listed categories, the partner's shown
  ones included, never the id of a deleted category ("No categories" when
  none is left).
- The received sheet counts a hidden category's events: it says what the
  partner shares; "counted nowhere" (§6.4) is about my calendar's figures.
- A digest restricted to categories lists mine only; an all-categories
  digest includes the partner's under "Category alerts too".
- The alerts menu's items are as tall as their captions need (56 dp, 74
  with a two-line caption), not the spec's 66.

**Costs, pinned.** An account that never paired: no new statement and no
new await on a launch, an event load, a category load or a sync run. A
paired one: one settings read per event load once a loaded row is the
partner's; one per category load while a partner's own category is held;
one per shared read (about four when something is hidden); two more per
reload of an open Sharing page.

### The closing review of slices C and E (2026-11-12)

Two reviewers read the fix pass of slices C and E once more, in fresh
contexts: 27 findings, three reproduced by a probe. Twenty are fixed in
this commit, each with the test that would have been its probe; seven
are kept and listed below.

**Fixed.**

- A share bloc closed in the turn it was opened subscribes to nothing
  (it used to follow the calendar and throw on the next change).
- "Shares anything" counts live rows (`SyncDao.anyLiveShareMark`): a
  shared event that was deleted no longer enables "Stop sharing
  everything" over empty lists, nor the stop-syncing sentence. The
  engine and `stopAll()` still count tombstones — their marks must be
  cleared and re-sent.
- An Undo belongs to the database it was offered in: it keeps
  `ShareService.databaseGeneration` and writes nothing under another.
  Built-in category ids are the same in every database.
- One voice per outcome: while the Single events sheet is open the page
  says no outcome of a ✕ or an Undo; the sheet says them, over itself.
- Back from Sync & sharing, an editor's share switch is re-seeded from
  what is stored now, not from what it opened with.
- The stop-syncing confirmation opens only where it was asked: a route
  or a dialog that arrived while it waited for the first read drops the
  tap; a failed load is an answer.
- A summary load (the Pairing row's) follows the calendar's changes and
  reads no counts; the tick sheet's counts are read for the Sharing page
  alone.
- The calendar hears a share flag that an act only corrected; the
  catalogue's refresh waits for a construction in flight; no failure
  stamp for an account that never paired; what is counted after an act's
  store cannot fail the act.
- A dimmed entry says what is shared as well as why it is dimmed; a date
  not in this year carries its year, and "Tomorrow" keeps its word across
  a year's end; the page's shape is decided at its first loaded state, so
  it keeps its sections while a pair is ending; an error after the page
  has left needs no host Scaffold.

**Kept, known.** An offline shared read says "Could not check" — the
check could not be made. "Sending…" stands while the pusher has parked a
share's entry; the Sync page lists it as held back. A reload that fails
right after an act can drop that act's snackbar. An Undo queued behind a
running act is dropped if its bloc closes inside those milliseconds. The
Categories page of an account not yet paired does not follow a pairing
made while it is open. A share written for a new category after its page
has gone fails silently. `ShareService.setFolderShared` is not one
transaction — no surface reaches it (slice F).

### Slice G — say what arrived; the guide (2026-11-12 → 13)

**What a person gets.** A bar, inside the app, the first time something
of the partner's arrives — "{name} shares Night shift with you", with
View, which opens the Sharing page on top of Sync & sharing — and one
when a shared event left while an alert of mine was armed on it: "{name}
no longer shares {what}. Your alert is off." A "Sharing with your
partner" page in the app guide, and one paragraph more in "Where your
data is stored".

**The pieces.**

- A shared read says what it changed (`SharedReadChanges`): the partner's
  categories newly held (a stored row whose merge was an insert; a
  built-in newly recorded as shared), the events newly held, and the
  events it removed, with their titles. Arrivals cost no statement; a
  page that carries a built-in or an event tombstone costs one keyed
  read; a read that changes nothing costs nothing more. A re-read from
  the start and an update of a held row are no arrival.
- `AppSyncApplyHooks.afterRun` asks the device's alert registrations
  which removed events were armed **before** the reconcile cancels them,
  and posts — after the run's reloads, at most once per run for each
  kind — `ShareLeftWithAlert` and `ShareArrived` (`lib/models/
  share_notice.dart`). An arrival names every new category and, of the
  events, only those shared one by one. Hiding a category is my own act:
  no notice.
- `ShareService.notices` / `notify` are static, like
  `CalendarEventService.externalChanges`: `ShareNoticeListener`, mounted
  once in the app shell, subscribes without building a service. It says
  a notice at once while the app is in front and holds it — merged, no
  duplicates — until the next resume while it is not; the leave is said
  before the arrival, each for `AppConstants.shareNoticeDuration` (a
  notice arrives unasked, so it stays as long as any bar may).
- The guide: `AppGuideTopic.sharing`, eight rows, every label passed in
  from the app's own strings; `dataNoticeShared` after the partner's
  paragraph.

**Not built.** The import line (§6.14's last row, case C2's last clause):
the only import that carries events is a backup restore, which replaces
the categories and unbinds the database; marks return from the cloud
after the bind (X6). The string left the ARBs.

### The reviews of the receiving side (2026-11-13)

Slice D was read by three code reviewers and a design reviewer, slice G
by one reviewer, each in a fresh context: 53 findings, 14 reproduced by a
probe. The ones ruled a fix are fixed here, each pinned by the test that
was its probe; the rest are kept and listed. Gate: `dart analyze lib test
tool test_driver` clean; the whole suite `+17127 ~17`.

**Fixed — what shows.**

- The hidden set goes with the shared rows (`SharedRowDao.removeAll`): it
  used to survive "Stop syncing", so a new pair's built-in could start
  hidden. Its two writers — a switch and the reader's prune — each run in
  one transaction and cannot interleave. A failed read of it no longer
  empties the category list. A write the database was switched under
  publishes nothing.
- A prune that removed an id ends in a whole re-read of the events
  (`SyncInvalidation.unhidden`); a failed prune is not a failed read.
- `CalendarEventService` refuses a write to a partner's event it no
  longer holds because its category is hidden — one keyed read, and only
  while something is hidden.
- The share bloc falls back to what it last read from storage, never to
  what is on screen: a tap whose write and read-back both fail draws
  back.
- **A filter decides by the category an event draws under**
  (`CalendarCategories.drawnIdOf`): an event the partner shares on its
  own from a category of theirs that is not shared draws as Other (R9)
  and is now filtered, grouped and found as Other — it was reached by no
  filter, and Upcoming showed two cards both titled Other. The alert rule
  "an unknown category inherits nothing" still reads the stored id, and
  so does an allowlist for my own events (the report's D32).
- Searching by a category's name finds the partner's shown categories; a
  category created inside the agenda's or the overview's picker can be
  left un-ticked; "Create '{typed}'" follows my categories alone; my
  shared categories wear their sign in the filter lists.
- On the Categories page a share bloc is built per sheet and closed with
  it (a reused one contradicted the alert setting); the alert setting is
  read only when there is a partner row to caption; the search field
  counts both lists; the partner's bare glyph at large text is
  contrast-corrected in every look. An alert write that ends after the
  category's sheet has closed still tells the calendar and asks for the
  permission. The look row and the mark switch wait for the page's first
  load.
- The header's failure text is "Could not check" (it was two sentences,
  and wrapped the section's title).

**Fixed — what is said.**

- What a read removed and stored again has not left: re-pairing with the
  same partner used to say "no longer shares" about events that were
  back. Under a pair made anew they are told as arrived.
- A notice names an event by id and title (`ShareNoticeEvent`), so two
  events of one title are two.
- "View" always ends on the Sharing page, over the one Sync & sharing
  page, exactly once — it used to stack a second pair of pages, or do
  nothing with Sync & sharing in front. Going back to a Sync & sharing
  page closes what is above it, so View only takes the bar down when a
  form sheet — it may hold a draft — lies above that page; one under it
  stays, and the Sharing page opens over it.
- Over a plain bottom sheet the bar takes the overlay road and is seen;
  under a dialog or a menu, over a form sheet, while an alert rings or
  waits to be routed, and while someone's bar with an action — an Undo —
  is up, the notice waits and is said when that has gone
  (`ShareNoticeRoutes`, an observer of every route; no timer but a bar's
  own).
- What the listener holds belongs to the database it arrived under; a
  category is worded from a loaded catalogue.
- An e-mail address standing in for a name — an account with no profile
  name publishes its address — is no longer capitalised at a sentence's
  start (`ShareCopy.sentence`; found on the device, where the accounts
  have no names).
- The guide no longer says the partner's events are always drawn apart
  (not under "Like mine").

**Kept, known.**

- In the agenda's and the overview's filters — allowlists — choosing
  only my categories stores them by name, so a category created later
  stays out until the filter is opened again; the chip shows a filter is
  on, and the grid's filter, a denylist, is the answer for "only mine for
  a moment" (R3). The way out is in Deferred.
- A stale id of the partner's leaves the grid's denylist when its picker
  is next opened, as a deleted category's always did.
- A shared built-in's caption can wrap with its "·" leading a line at
  text scale 2.0 in a narrow column: the count before it is already
  unbreakable and wider than the column.
- Hiding a category, stopping sync and a restore's unbind take armed
  alerts off with no notice: each is the person's own act on this phone.
- After the pair has ended the leave notice says "Your partner": the name
  went with the pair.
- A category and single events arriving in one read are told as the
  category; an event that comes back from a tombstone is no arrival; a
  notice that arrives before any page exists waits for the next resume.
- The Sharing page's held lines read as one block with the intro at
  German 2.0; the kit's switch entry carries its id on an unlabelled
  node and "ALERTS" is spoken in capitals — the kit's and
  `FormSectionLabel`'s behaviour app-wide.
- The guide's "What is never shared" names notes: true while slice F is
  not built.
- A ring stopped from its notification with no alarm page up changes no
  route: a notice that waited for it is said at the next route change or
  resume. The ✕ of someone's Undo does not end the wait for that bar. A
  plain message over a sheet can be replaced by a notice.

### The device proof (2026-11-13)

The two-guest suite `qa pass share -d emulator-5556` gains three flows
that use no seam — the surfaces themselves give, receive and stop:

- `04g_share_from_surfaces`: a category shared from its editor as it is
  made, a built-in from its row's ⋮, an event from its editor's switch;
  the Sharing page names them, the tick sheet takes one back, the Single
  events sheet stops one and Undo brings it back; the partner is told
  what arrived, and View opens its Sharing page.
- `04h_receiver_chooses`: a category switched off leaves the partner's
  calendar with no sync and comes back; under "Category alerts too" the
  partner adds an alert of its own to it; the Categories page lists it
  under "From …"; the filter lists it in a group of its own; the look
  row changes how a partner's row is drawn.
- `04i_stop_everything`: the partner arms an alert of its own on a
  shared event, the owner stops sharing everything, and the partner is
  told its alert is off.

Sixteen flows, green twice in a row, each on a freshly started emulator
suite (350 s each), and once more, 16/16 in 349 s, on the final build.

**What the device found that no suite had.**

- View did nothing with Sync & sharing in front — where "Sync now"
  lives, so where a person who syncs by hand meets the bar. The review of
  slice G had ruled it the same hour; `04g` now pins the fix.
- An e-mail address standing in for a name was capitalised at a
  sentence's start (the emulator's accounts have no names).
- **A sheet covered while it is still sliding in kept the geometry of
  mid-slide.** `04h` went red twice in six runs at the Filters sheet's ✕:
  the category picker had opened before the sheet settled, the sheet
  reached its place under the picker's barrier — which blocks its
  semantics — and its ✕ was reported some 70 dp below where it was
  painted, for TalkBack as for the harness. It is the 2026-10-13 trap
  (`FormSheetSemanticsRefresh`) with no resize at all. The wrapper is now
  on the two filter sheets, on the received-categories sheet and on the
  shared-events lists, each pinned by a test that opens the sub-sheet
  150 ms into the slide. A tap by sight was never affected. Every sheet
  that opens a route above itself has the exposure: adopting the refresh
  in the sheet chrome stays the open app-wide decision
  (`ui-language-adoption-roadmap.md`).

**The app's other saved suites on the final build:** calendar 35/35,
settings 21/21, browser 3/3, alerts 5/5, alerts_pair 1/1, sync 5/5 — with
the share suite 86 flows, none red, none rerun; `qa errors` clean.

**The matrix** — dark, German, text scale 2.0 on both guests, then
Romanian on the partner's; twenty-one screens, read by the lead. Nothing
is broken in the share surfaces. Seen and kept: at 2.0 a Categories row
is compact, with no avatar and so no "mine" badge (its caption still
says "Shared"); the held end of the "YOU SHARE" header is an empty line
at 2.0 (it is where "Sending…" goes); "Like mine" wraps inside its
segment in German at 2.0, since the kit stacks only when a word would
break; an e-mail address breaks at its dot in the editors' switch
labels. Seen outside this build and left for their own pass: in German
at 2.0 the day panel's header runs the date into the count, the Add
event button covers the end of the day panel's last row, and the
category editor's title is cut.

Left to a phone, since no emulator proves it: TalkBack on the Sharing
page and on the editors' share rows; the partner's real photo under the
Avatar look; the system's 200 % font on a narrow phone; two real
accounts on the live project (slice 0).

### Slice H — the filters keep their meaning (2026-11-13)

Decisions D29 and D34 (§16.2), the semantics of §16.3. One implementer,
one reviewer.

**What a person gets.** A filter that ticks all of my categories and none
of {name}'s holds "all of mine": a category made afterwards is in, with no
reopening. The same for all of {name}'s. A digest restricted to
categories can name {name}'s under "Category alerts too".

**The pieces.**

- `CategoryAllowlist` (`lib/utils/category_allowlist.dart`), pure, over
  the `CalendarCategories` facade: the entries `mineEntry` (`*mine`) and
  `partnerEntry` (`*partner`); `isPartnerSide(event)`; `admits`;
  `ticked` (what a picker opens with) and `fromPicker(previous, picked,
  {partnerListed})` — the one store, which reads the catalogue itself at
  the moment of the store, so no caller hands it a list of "mine" that a
  category created inside the picker has already outdated; `listed`,
  `tickedListed`, `soleTicked`, `filtersNothing`; `forReport`.
- **Two rules the review made explicit.** *A picker changes only the
  part of a list it could show*: what it did not list — {name}'s group
  where the surface or the setting lists none of it, a category of theirs
  that I hid — is carried over as it stood, and only an id no category
  holds any more is dropped. *A label, a count and a look are taken from
  the listed categories that are ticked*, never from the raw set.
- `EventAgenda.passesEventFilters` delegates its allowlist part to it, so
  the agenda, the overview, the report and the digest planner follow with
  no change of their own; the denylist still reads the drawn id.
- Every "is a filter on" asks `filtersNothing` — the agenda's chip and
  its count of restricting filters, the overview's options badge, the
  report bar; the one category a list ticks (`soleTicked`) gives the
  label, the Alerts row's look, the notification's tint and glyph, and
  the overview's tile colour alike.
- The report takes only its own part of a list it is handed
  (`forReport`): {name}'s part is dropped and `*mine` alone is off — the
  report never counts their events (D15). A report digest's picker lists
  mine only.
- While the catalogue is not loaded a partner's event is on **their**
  side — unknown is never "mine" — and the Alerts hub resolves the
  catalogue before it plans a digest.

**Decided in the build.**

- A group that lists no category counts as whole, and its entry is never
  written. Both entries together filter nothing.
- A list that holds only `*partner` while nothing of {name}'s is listed
  admits nothing and reads "No categories": it said "only theirs", and
  there is nothing of theirs. Handed to the report it is off — the report
  cannot hold "nothing".
- An empty list holds all of {name}'s group too: a digest opened under
  "Only alerts I add" and narrowed to two of mine stores those two and
  `*partner`.
- For an account that never paired the stored lists are byte for byte
  what they were; one thing it sees differently: a list that holds only
  the id of a deleted category reads "No categories" with the plain look,
  where it wore Other's name and colour.
- A digest syncs like a saved view, so D29's reasoning about a build
  that does not know the entries covers both.

**The review.** One reviewer, ten findings, five reproduced: a digest
stored as `*partner` and opened under another alert setting read "0
categories" and a Done with no change widened it to every category; a
category created inside the digest's picker was lost; an empty catalogue
made every partner's event "mine"; a label and its look disagreed; a
report digest could be narrowed to a group the report never counts. All
fixed, each pinned by the test that was its probe.

### Slice F0 — the share service's folder half (2026-11-13)

No pixels. One implementer.

- **Sharing a folder is one act.** `ShareService.setFolderShared(id, on)`
  answers a `ShareChange`, written in one transaction through
  `FolderDao.setSharedPair`; `ShareChange` names `sharedFolders`,
  `unsharedFolders` and `coveredFolders` — the inner folders whose own
  mark the outer share replaced — and `undo` puts each back, the outer
  mark off first, in one transaction. It refuses unless ready; a missing
  folder, or the partner's, writes nothing. `ShareServiceWiring.markFolder`
  is gone: the service writes through the DAO like its siblings.
- **The overview lists folders.** `ShareOverview.folders` — my marked
  folders that no mark above them covers, with the name of the folder
  each lies in and the notes in its subtree; `partnerFolders` — {name}'s
  top-level folders as the reader placed them; `folderCount` for the
  Pairing row's summary. One statement (`SyncDao.liveShareMarks`) answers
  what is shared at all, so a database with no folder mark and no shared
  folder runs nothing more; the page reads two lists more at most.
- **The notes look.** `ShareNoteLook { avatar, plain }`, key
  `share_note_look` outside the pairing prefix, `ShareLook.noteLook`,
  `PartnerLook.noteLook` — read while paired only, so the looks statement
  of an unpaired account is the old one.
- `ShareBloc`: `ShareFolderShared`, `ShareFolderUnshared` in the ordered
  queue with numbered outcomes; `ShareNoteLookSet`, shown from the tap.
- A partner's row never carries a mark on this phone
  (`FoldersBinding.mergeShared` stores none), so "you share something"
  cannot be true of what was received.

### Slice H — no alert goes off unsaid (2026-11-13)

Decisions D30, D31, D33, D35. One implementer, in two legs.

**What a person gets.** Hiding a category of {name}'s that an alert of
mine rings for says so at once, over the sheet. Stop syncing, Unpair,
Delete cloud copy and Delete account say, before I confirm, that my
alerts on what {name} shares turn off — and Stop syncing that what {name}
shares leaves this phone. When {name} ends the pair, the notice names
them; after my own Unpair nothing more is said. {name}'s Single events
open from the Sharing page.

**The pieces.**

- **D31 was already true**, and is now pinned: `SyncBindingService._unbind`
  calls `onSharedRowsRemoved`, which DI points at
  `AppSyncApplyHooks.afterSharedRowsRemoved()` — the calendar reloads
  whole and the alert pass cancels what was armed, with no run, resume or
  relaunch after it (`shared_rows_leave_alerts_test.dart`). A restore
  goes through the same unbind and ends in its own pass; a forgotten pair
  is announced by the reader.
- `ShareService.armedOnPartner({categoryId})`: how many of {name}'s
  events hold a pending registration of mine — no statement while the
  cache holds none of theirs, one read otherwise.
- **The hide bar** is one path that needs no sheet and no bloc to be
  alive: the service reads the armed count before the reload drops the
  events and, once the hide is written, posts a notice
  (`ShareHiddenWithAlerts`); `ShareNoticeListener` says it at once on
  its overlay road — over a sheet, a form sheet or a dialog, since it
  answers the person's own tap — never held for a resume, waiting only
  for a ringing alert. Nothing when nothing was armed, nothing on showing
  again, nothing when the write failed, nothing on switching "Alerts for
  shared events" to Off. Only registrations whose time is still ahead
  count as armed.
- **Who ended it.** The reader notes the pair it forgets
  (`SharedReadChanges.endedPair`); the hook asks
  `PairingService.endingOf(pair)` and tells a leave only when the partner
  ended it or their account is gone, with `ShareLeftWithAlert.partnerName`
  as it stood — kept past the "pairing ended" notice's dismissal
  (`pairingEndedPair`) and given up when told. An un-share or a delete is
  told as before. When it cannot be told who ended it, nothing is said.
- **The confirmations** (`lib/widgets/share_alerts_at_stake.dart`): the
  count is asked at the tap through the page's `ShareBloc`, for at most
  `SyncLimits.stopConfirmShareRead`; a failure or a late answer shows the
  dialog without the sentence; an account that is not paired is answered
  at once, with no await. `ShareOverview.holdsPartnerRows` — categories,
  single events or folders, answered by the statement the Pairing row's
  summary already runs — decides Stop syncing's second sentence.
- **D33.** Sync & sharing passes the Sharing page an opener: one keyed
  read that the event is still held, then
  `AppNavigator.toCalendarOccurrence`.

**Decided in the build.**

- The app has no restore over a database that could hold a partner's
  rows: the one restore with a confirmation is onboarding's, on a
  database that never paired. Nothing was added there.
- With a calendar already under Sync & sharing, opening {name}'s event
  closes everything above that calendar — the list, the Sharing page and
  Sync & sharing (`AppNavigator.toCalendarOccurrenceFromList`) — never a
  second calendar, so Back no longer reaches the Sharing page in that
  shape; with none beneath, only the list closes, the calendar is pushed
  over the Sharing page and Back returns to it.
- An account that has just unpaired but still holds the partner's rows
  gets no sentence: the read is asked only while paired. A tap before the
  pairing has loaded waits for it, inside the same bound.

**The review.** One reviewer, eleven findings, three reproduced: the
name kept for an ended pair leaked into the next pair (a new pair now
never inherits a name, and `endingOf` answers before it clears); D33's
tap came from an open sheet, so the navigator closed the wrong routes
and left a Sharing page with a dead bloc over the calendar; the hide bar
was lost when its sheet closed before the write landed — which is why it
is the listener's now. Also from it: a test that start-up really wires
`onSharedRowsRemoved` (the first pin assigned it itself), the pairing's
settings read in one statement again (the kept ending had added one for
every account), and the German and Romanian sentence said without a
pronoun for the category.

### Slice F — shared folders and a partner's notes (2026-11-13)

§6.11–§6.13 with §16.8's look. Built in four streams — the data layer
(F0), the browser (F1), the note editor (F2), the Sharing page (F3) —
each one implementer in its own worktree, from one designer spec rendered
with real fonts first.

**The data layer.**

- `Folder.fromPartner` and `Folder.share` (`FolderShare.none` · `.byMark` ·
  `.through(folderId)`); `NoteMetadata.fromPartner`,
  `.sharedThroughFolderId`, `.inSharedFolder`. Transient, in equality,
  never stored or exported, set where the two storage services map their
  rows — every load the browser, All notes, search, the picker and the
  editor use — and by `NoteRepository.flaggedMetadata` at the four doors
  that used to hand the editor an unflagged note (the launch restore, the
  session chip, a linked note, the counter page).
- **One census per database** (`lib/repositories/share_census.dart`,
  filled by `FolderDao.shareCensus()`): who the shared owner is, which
  folders carry a mark, which are covered. One statement on the first
  load after a change, never one per row; a database with no mark and no
  shared row pays that one read after it opens and after a full cache
  drop, and nothing through its own creates, moves, renames and deletes.
  The typing path gains no await: a save keeps the flags it was given.
- **The belt.** Rename, label, move and delete of a partner's folder or
  note — single and bulk — throw `SharedRowException` before anything is
  written; create, import and save already did. Nothing answers "done"
  for a write the database would have turned into nothing.
- Recent never lists a partner's note (`loadNotesPaginated(ownOnly:)`,
  on the page, its load-more and the idle search recents); All notes and
  search list them, flagged.
- `NoteStorageService.copyToMine(noteId, folderId)`: a note of my own
  with the partner's title and text, a new id, stamped now, no label.
- `ImportExportService` refuses a partner's note, folder or selection
  before a file is written (`ImportExportFailure.refusedShared`).
- A move says what it did to sharing (`BulkMoveResult.shareChange`).
- **My sort order in a partner's folder is mine**: her row cannot be
  written, so it is kept per database in settings
  (`share_folder_sorts`, a map by folder id), laid over her folder where
  the service maps it, and pruned where the reader removes folders.

**The Sharing page.** Folders under YOU SHARE and under {NAME} SHARES
WITH YOU; "Notes shared with you" (Avatar · Like mine); the Pairing row's
summary counts folders. `MySharedFoldersSheet` — a row per marked folder
that no outer mark covers, ✕ with Undo, "Share a folder" through the
folder picker — and `PartnerSharedFoldersSheet`, whose rows open the
folder (D37). The frame the list sheets share is `ShareListFrame`
(`share_list_frame.dart`), with a footer. A pick that an outer mark
already covers writes nothing: `FolderDao.setSharedPair` refuses a mark
under a mark by this device's own act. The words that name folders:
`shareMarkMineDesc`, the stop-all confirmation, the guide's "What is
never shared" (notes left it) and a new guide row "Share a folder",
`dataNoticeShared`.

**A partner's note.** The editor decides before its first frame, from the
flag the note arrives with, and corrects it once from the load: no
keyboard, no markdown bar, no vocabulary bar, the save coordinator
disabled from the start (a disabled coordinator tracks and schedules
nothing), `SharedReadOnlyLine` under the bar. A task box does not toggle
and says once per visit why; its screen-reader node says "Task, done" /
"Task, not done" and is no checkbox. The ⋮ menu dims every write and
offers "Copy to my notes" (`copySharedNoteToMine`: the picker, the copy
opened on top, one bar). It follows the note: a change redraws in place,
a leave closes the page with one line. My own note in a folder I share
wears the sign beside its title, from the flag and the look the share
service last published (`ShareService.publishedLook`), so nothing pops in.
A partner's event's read sheet shows a Linked note row only when that
note is on this phone as theirs.

**The browser** (first leg). The root's "From {name}" group after
Folders; the sign before a shared folder's count; the partner's face
before a folder's count and at the start of a note row's or a search
result's second line (`RowShareMark`); with no share input a row builds
exactly today's tree. Each page reads the look once into its state
(`PartnerLookReader`), only when the census says something is shared, and
again on return. A partner's folder that leaves while it is open closes
back to where the person was with one line. "Share note" / "Share
folder" read "Send a copy" (D9).

**The review of the data layer, and its rule.** One reviewer, fourteen
findings, six reproduced — two of them privacy holes, as every part of
the foundations had one. The rule that came out of it, now the first
sentence of `FolderDao.setSharedPair`'s doc: **un-sharing a folder leaves
nothing shared under it; a move changes no mark.**

- *An un-share left an inner folder's own mark standing* — a mark under a
  mark is what a merge from another of my devices leaves — while the
  browser showed that folder as covered. An un-share now clears every
  mark in the subtree, live and tombstoned, in its transaction, and the
  `ShareChange` names them (`clearedInnerFolders`). Its Undo marks the
  outer folder again, which covers them as before.
- The first build made a move into a shared folder drop the moved
  folder's own mark, so that an un-share could not miss it. With the rule
  above that is not needed, and it was wrong twice over: moved back out
  the folder was private without a word, and move history's Undo quietly
  un-shared it. A move changes no mark; a marked folder reads as covered
  while it lies in a shared one and shares itself again when it leaves.
- *A live folder under a deleted, marked folder was shared and no surface
  could show or stop it.* A live row now takes its grant only through
  live folders up to a live mark; a tombstone still derives through
  tombstones, so the partner's phone hears of a delete (foundations §3).
  The census, the overview and the encode agree in all four corners.
- **A database file that leaves the phone holds only my rows.** "Share
  database" sent a copy that still held the partner's notes, folders and
  events, which anyone not signed in as me could then read for good.
  `DatabaseManager` strips the copy inside its isolate — the partner's
  rows in the six tables, their chunks and search rows, the reader's
  metadata, the hidden set — under the fences' licence, then compacts it,
  so no freed page keeps their text. A database with no shared owner is
  copied byte for byte as before. Foundations §8's "a copy of the file
  holds the cached rows" no longer holds for a copy that is handed out.
- `copyToMine` refuses a deleted or missing target
  (`FolderGoneException`) and reads its source's title and text as one
  read. The folder caches and the census drop before the calendar's
  refreshes after a share act, so a failed refresh cannot leave the
  browser saying "not shared". A save keeps the share flags it was given
  and never answers from a dropped census. A reorder never plans the
  partner's rows.

**The review of the editor.** One reviewer; no confirmed defect — its
two keyboard probes showed a read-only editor rejecting every editing key
on the desktop and the Android path — and nine weak points, all closed:

- The sign on my own note follows what changes while the page is open:
  the share census tells when it was forgotten (`ShareCensus.forgotten`:
  a share act, a merge, a shared read), and the page reads its note's
  flags again then and on return from a page above it.
- **A wiki link resolves on the linking note's own side**: a link in my
  note finds my notes only, a link in a partner's note that partner's
  only — it used to open my note of the same title from hers, and, since
  her notes are on the phone, could open hers from mine.
- A read-only page has nothing unsaved (`_bodyIsUnsaved` is false there),
  so no conflict copy can ever be filed into the partner's folder; a
  page test fails if the save machinery is started for a partner's note.
- A copy made after its page has gone is still opened and announced; a
  source that leaves during the copy is told once, by the page; a target
  folder that went away says so in words.
- A partner's change keeps my selection when the selected text is
  unchanged. The Linked note row checks again at the tap. A note that is
  gone before it could load closes its page with one line — it used to
  stay blank.
- The look the share service publishes is only ever one that was read,
  and never another database's.

**The browser after its reviews.** One code reviewer over the browser and
the Sharing page, one design reviewer over the rows, the menus, the
picker and the folder page; a fix pass of sixteen items — nine from the
code, seven from the look.

- *A paired account with nothing shared yet had no "Share with {name}"
  after a cold start*: the look is read only when the census says
  something is shared. The fix of that day asked once before the first
  folder menu or row sheet opened; the final review found what that ask
  cost (B3), and it is gone — the census's one statement now also says
  whether this database is paired ("After the final reviews — the
  browser and the Sharing page" below is the truth).
- The share picker offers no recent destinations: a chip could confirm a
  folder that is already shared. In move and copy a shared folder's chip
  wears the sign; the partner's folders never appear.
- The signs follow a share made elsewhere — the Sharing page, my other
  device — within a moment (`NoteStorageService.shareFactsChanged`, one
  re-read per burst, none when nothing was shared before or after).
- An act that wrote nothing says the truth: a share of a folder already
  shared says so, a stop that found no mark says nothing, and every
  message is fenced by the database the act was asked on.
- **One line when a share ends under open pages** (`ShareLeaveVoice`):
  the page in front speaks; a page underneath offers its line, which is
  said only if nothing in front spoke.
- The selection bar's export reads "Send a copy", like the menus (D9).
- **A partner's folder page is read-only from its first frame.** The
  opener says whose the folder is (`AppNavigator.toFolder(fromPartner:)`
  — a row, the Sharing page's list) or the warm census does; her page
  holds a bare ground until her look is known rather than change its line
  after the first frame. A folder of mine never waits.
- Returning to the editor re-evaluates the sign from memory; a row is
  read only after the census was forgotten.
- A disabled ⋮ entry reads disabled. The share picker fits German at text
  scale 2.0: a short confirm word per purpose ("Share", "Copy here"), two
  lines at most. The "already shared" reason wraps in a slot that is
  there from the start, so entering a shared folder changes the text, not
  the geometry. A partner's search result keeps its date beside the face.
  A disabled sheet tile is announced as a disabled button.

**The Sharing page after its review** (with slice K's second part).

- A failed or refused act is still said after its list sheet was
  dismissed, on the app's own messenger (`sayShareFailuresPastSheet`); a
  success says nothing more — its bar would have offered an Undo that
  needs the sheet. The Categories page does the same for a failed Undo
  and for the share of a new category whose page has gone.
- The share bloc keeps the bar when the reload after an act fails, hands
  a queued Undo to the service when it closes, and no longer makes
  `close()` wait for a held write: its acts run one at a time through
  `oneAtATime` (`lib/bloc/one_at_a_time.dart`), which never pauses the
  event stream. `CalendarBloc` keeps its own queue on purpose — there an
  alert edit queued behind a running one still runs when the bloc closes,
  and the shared queue would have dropped it.
- The page closes only the routes it opened, by their handles; a route of
  another's above it stays.
- A hide abandoned by a database switch posts no notice, and neither does
  a hide that found the category already hidden.
- An un-share that cleared marks under the folder says so: "No longer
  shared: {folder} and N folders inside it" (`shareStoppedWithInner`).

**Decided in the build.**

- A read-only task box keeps a plain tap for a screen reader — the owned
  editor fork gives every zone one — which says the read-only line and
  ticks nothing.
- The reason a folder's sort order needs a store of its own, the four
  unflagged doors and the missing `_track` guard in the save coordinator
  were found by the builders, not by the plan.

### Slice K — the debts (2026-11-13)

§16.5's list, closed one by one, each with the test that would have been
its probe.

- **Held-back rows land in the run that freed them.** The shared reader
  notes that it removed or made room for something; the puller then
  tries the rows held for a shared parent again in the same run
  (`retryFreed`, at most `maxParkRetries`), and a read that removed
  nothing reads nothing more. Not under the manual cadence unless asked,
  and never while the app is away — then the next run does it.
- **The export lists** of presence marks and alerts leave out a row of
  mine that names a partner's event (`getActiveForExport`,
  `getAllActiveForExport`), in the two statements they always were.
- **"Waiting to send"** on the Sharing page while every remaining entry
  of the shareable tables is parked by the pusher
  (`ShareOverview.sendingParked`, from one statement over the outbox and
  its parks).
- **The Categories page follows a pairing made while it is open**
  (`PairingService.writtenInMemory`, which is null — and so costs nothing
  — while no pairing service was built).
- **A share caption never starts a line with its dot**
  (`ShareCopy.caption`). The cause was not the dot's own space: a count
  is bound to its noun by a no-break space in the strings, and "123
  Ereignisse ·" as one unbreakable run is wider than a narrow column at
  text scale 2.0, so the line was cut just before the dot. The count's
  space is freed in a caption's first part only: there a count may part
  from its noun, which is the lesser flaw and happens only when the three
  together do not fit; at ordinary sizes every caption wraps as before
  (measured).
- **A save in the editor reads no share census**: the page's metadata
  rides the save event (`UpdateOptimizedNote.current`) to the service,
  which keeps its flags.

### After the final reviews — the data path (2026-11-13 → 14)

The final review of the folder-sharing data path (Fable, with probes)
found seven defects no test caught, two of them privacy holes (§16.9,
P1–P7); an eighth was found while they were fixed. One implementer built
them, each test written first and seen red. Two Fable reviewers then read
the fixes and found no path around them — and eighteen things, two of
them real defects; a fix pass of two legs answered those. A closing
review read that pass and found twelve more, none of them a loss; a
third leg answered them. What follows is the result of all of it.

**What a person gets.** What {name} un-shares, deletes or takes away with
the pair leaves this phone whole: search finds nothing of it, and a copy
of my database that I hand to someone names nothing of {name}'s and tells
nothing of their days. What I delete on my other device stops being
shared in the cloud too. And {name}'s phone drops what I take back at its
next read, also when it could not read one of my documents. A copy of my
own that I restore on another phone gets back from my space what the
copy had to leave out — my alerts and marks on {name}'s events.

**The pieces.**

- **A partner's note leaves the search index with the note (P1).**
  `NoteSearchDao.forgetNotes(ids)` deletes the notes' index rows — found
  through the ledger, by rowid or by note id, so a row a VACUUM left under
  an older rowid goes too — and then their ledger rows, in the caller's
  transaction. `SharedRowDao._remove` calls it for the notes it is about
  to remove, so `removeAbsent`, `removeAll` and `evict` all carry it. The
  index first and the ledger last: a delete in the index that fails is
  logged, does not roll the removal back, and leaves the ledger rows for
  the indexer's own orphan sweep to find.
- **A copy that leaves the phone carries no word of a note that is gone
  (P1).** Two layers. The rows: `_stripShared` drops every ledger row that
  belongs to no live note and every index row without a ledger row,
  whether or not a shared owner is set — so the words of a note of my own
  that I deleted, and that the indexer has not swept yet, do not travel
  either. The bytes: the index is contentless-delete, so a deleted row's
  terms stay in its segment blobs until they merge, and `VACUUM INTO`
  copies blobs as they are. A copy of a database that **may have held
  {name}'s words** therefore always has its index rebuilt (`optimize`)
  and is vacuumed again. One statement decides "may have held": the
  shared owner; the record `shared_ever_held` — "this database has had a
  partner to read from", written when the reader first begins for one,
  before any row is held, and again when a partner's rows are removed,
  and never taken away; or, for a database that paired before that record
  existed, any `pairing_` settings row — the one writer of the pairing
  always writes `pairing_ended_notice_pending`. A database that never
  paired, with its index in step, is still copied byte for byte.
- **A partner's tombstone keeps none of their words (P4, P8)** — in all
  six shared tables. When {name}'s row lands as a tombstone over a row
  this phone holds, what it said is emptied and the row stays, because
  the reader's count needs it:

  | Table | Emptied | Kept |
  | --- | --- | --- |
  | `notes` | title, preview; chunks and search rows removed | id, folder, position, label, stamps, owner |
  | `folders` | name → its id (the column refuses an empty one) | parent, order, mark, stamps |
  | `calendar_events` | title, description | category and note ids, dates, the rule and its payload, flags, mark, stamps |
  | `calendar_event_occurrences` | description | event id, day, stamps |
  | `calendar_event_skips` | — (no text column) | event id, day, stamps |
  | `calendar_categories` | name | colour, icon key, order, built-in flag, mark, stamps |

  Ids, dates, a rule, a colour and an icon key are not words. A tombstone
  followed by a live version of the same row has its words back. A
  tombstone of my own space keeps everything, as before. **Tombstones
  stored before this fix** are emptied once per database by the shared
  reader, inside its own writing context (`SharedRowDao.emptyTombstones`);
  whether that has run rides the one statement the reader already makes
  for the waiting notes, so a quiet read costs what it cost.
- **A handed-out copy names nothing of {name}'s and tells nothing of
  their days (P6).** Beyond the rows:

  | In the copy | Before | Now |
  | --- | --- | --- |
  | The location stack | {name}'s folder titles and ids | emptied whenever it names a folder or note the copy does not hold |
  | `pairing_*` (pair id, both uids, {name}'s name, the invite code, the ended pair) | all of it | none |
  | My alerts, presence marks, day rows and alert registrations on {name}'s events | kept — the days and times of their events | stripped |
  | My counter values on {name}'s notes; `note_position_` and `money_note_currency_` of their notes | kept | stripped |
  | Hidden categories, folder sorts, `share_sending`, the owed pokes | stripped only with a shared owner | always stripped |
  | The notices a background check kept ({name}'s event titles and name) | kept | stripped |
  | The reader's records (`shared_ever_held`, the sweep's mark) | — | stripped |
  | The `sync_space_*` binding | mine | kept: a restore's heal reads it |
  | The looks and the alert choice | mine | kept: choices of mine that name nobody |
  | The pair id in the marks on **my own** rows | mine | kept: a mark is my row's state, and what a restore of my own copy goes on sharing by |
  | {name}'s category ids inside my filters, saved views, digests and category alerts | mine | kept: a random id of a category the copy does not hold says no word, no time and no person, and each list drops it at its next store |

  "Hangs on {name}'s row" is decided as "names an event or a note the
  copy does not hold", so it also covers a pair that has ended. The live
  database keeps all of it — a re-share finds my marks and alerts again;
  the JSON export already left them out. The whole stack is emptied, not
  pruned: a stack with a hole is a chain nobody walked, and where the
  copy is opened the position is worth nothing.

  **What the copy drops of mine comes back.** For each synced table the
  strip took a hanging row from, the copy also forgets where that table's
  pull stood (`pull_cursor.`, `pull_settled.`, `pull_seen.`). A restore
  that keeps the binding then reads the table again from my space, and my
  alerts, presence marks, day rows, skips and counter values on {name}'s
  rows return — hanging, as on the phone the copy was made on, until the
  reader brings their rows back. The scheduler's registrations and the
  per-note settings are device-local and are not read back. An entry of
  the outbox whose row the strip took pushes nothing: no document, no
  delete.

  **A database that never had a partner is not judged for hanging rows.**
  What hangs on a row the copy does not hold, and a location stack that
  names one, are looked for only where the database may have held
  {name}'s rows. Anywhere else such a row is an orphan of my own — a
  test alarm's registration, an alert pulled before its event, a key the
  JSON import could not map — and travels as it always did: a
  never-paired copy costs four reads at most and is byte for byte what
  `VACUUM INTO` wrote. A test alarm's registration is never taken,
  paired or not.
- **A folder tombstone that arrives by merge un-shares what lies under it
  in the cloud too (P2).** When a merged tombstone lands on a live local
  folder that was shared, this device's **live** rows under it are queued
  again, in the merge's transaction, and the pair is owed a normal poke
  when there is one — before, my phone called those rows private while
  their documents went on granting them. The other way too: a merge that
  brings a buried folder back live queues its subtree again when the
  folder is shared after. Whether any folder is marked rides the read of
  the local row, so a database that shares nothing pays no statement for
  it (three for such a merge, as before the fix).
- **The poke for a note's move is owed in the DAO (P5)** — `moveNote`,
  `moveNotes` and the re-file repair, each in its own transaction, as the
  folders' writers always did. Whether any folder is marked rides a read
  each path already makes, so a database that shares nothing pays no
  statement more (pinned: seven for a move, as before). **A poke is never
  sent under a pair that is no longer the active one**: an entry a stale
  mark left for an ended pair is dropped unsent when pokes are sent. The
  active pair is the one this phone's stored pairing names now
  (`SharePartnerSource.localPairId`, no network) — it changes at the
  moment of pairing, where the pair the shared read last found lags by a
  read.
- **One rule for a folder's new parent (P7)**, for `moveFolder` and for
  `updateFolder` with a move: never into itself, a missing or deleted
  target, or its own subtree — walked **up** from the target through
  every row, deleted or not, so a folder stranded under a tombstone
  cannot hide a cycle. A refused move writes nothing, a rename that came
  with it included.
- **The reader accounts for what it does not hold (P3).** A document this
  phone has seen and does not hold — written by a newer build, unreadable,
  a note waiting for its text, a row of {name}'s evicted for one of my
  own — is recorded where the refused ones are, with a value of its own
  (`u`): counted, never shown as "could not be shown", forgotten when the
  row is held or when a read from the start no longer meets it. So "the
  server's count equals what I account for" again means nothing left, and
  a removal is seen at the next read instead of the next day. A document
  is counted once whatever records name it — a shared built-in has a
  record of its own, and counted twice it made every read walk that table
  from the start for good. A refusal already recorded is never replaced
  by "not held", and a document met again writes nothing. `countOf` is
  one statement where it was two: a quiet read costs 277 statements where
  it cost 283.

**Decided in the build.**

- The live database keeps a removed note's bytes in the index's segments
  until they merge, as SQLite's free pages keep a deleted row's: nothing
  of them can be searched and nothing leaves the phone.
- Once a marked folder was deleted, `_derivePairs` costs eleven statements
  more per drain (417 → 428 with fifty-one folders), three of them reads
  of three columns of every folder. Kept: the derive path is the grant's
  source of truth and the final review read it sound; a rare state does
  not justify reopening it.
- A folder **above** the marked one deleted on my other device leaves the
  marked folder shared — both sides agree — and out of the browser's
  reach until the existing repair lifts it to the root. Pinned as it is.
- An evicted row is recorded as not held without asking whether it was
  live; the next read that meets its document says what it really is.
- A page that meets a document already recorded still runs its one
  insert, which writes nothing.
- With no pairing stored at all — a restored copy before its first
  sign-in has answered — what is owed is sent as it was owed: the relay
  refuses a pair the caller is not in.
- A merged folder tombstone on a database that holds a mark costs what a
  merged live folder there always cost, one read of the table's ids and
  parents: five statements for the burial of a private folder, nine
  inside a shared subtree with a live note under it; eight for a live
  applied merge, five with no mark anywhere. Pinned.
- The bulk move keeps a walk of its own — one for the whole selection —
  equal to the single move's rule, and pinned to stay so.
- A buried folder with only tombstones under it leaves the cloud granting
  those tombstones: {name} holds them without words, and they leave when
  the share ends.
- A page of documents the reader skipped whose cursor did not move
  records nothing: the gateway's cursor passes every document it lists
  at the read that first meets it, and an overlap re-read meets them
  again, already recorded.
- `FolderStorageService.moveFolder` still checks the name in the target
  before the rule is asked: it can only mis-answer for a move no surface
  offers, and asking first would cost every folder move a read.

### After the final reviews — the filters (2026-11-13 → 14)

The second review of D29 confirmed three defects with a probe; a fourth
was found while they were pinned. §16.3 says the rules; this is what was
built.

- **A pick changed to nothing is every category.** "Select none" over a
  part of mine beside {name}'s group stored {name}'s group alone, and
  over a category of theirs I had hidden it stored that id alone — an
  agenda that showed nothing. `fromPicker` now answers the empty list for
  a pick the person changed into one that ticks none of the listed rows.
  A Done on a picker nobody touched is no such pick: it keeps what the
  list meant — the first review's fix — and still writes a whole listed
  group as its entry.
- **One reader of a digest's list**, `CategoryAllowlist.forDigest`: a
  report's own part alone, whatever its stored list still names. The
  planner's scan, the scheduler's payload, the words and the editor's
  store all read it. Found on the way: a report digest whose stored list
  named only {name}'s group was never armed at all, because the planner
  scanned by the raw list; and under "Category alerts too" a report's
  span was kept alive by {name}'s events alone. The planner counts none
  of their events for a report, whatever the setting.
- **While no category is known nothing is claimed.** A list that holds
  anything reads as in force, and a label reads "Categories" — never
  "No categories", never a made-up count (`tickedCount`). For an account
  that never paired this changes a label for the moment before the first
  load: a plain list read "No categories" there and now reads its count.

**After the independent review of that pass** (a property sweep over
sixteen thousand picks; the fixes held, four things were open), a third
round, each case seen red first:

- **After the pair ends, "Select none" is every category.** With nothing
  of a partner's known the store took its oldest path and kept
  {name}'s old id alone — a list that shows nothing. The "changed to
  nothing" answer now comes before every path.
- **A Done nobody touched is no store, and {name}'s part changes only
  when a row of theirs is changed** (§16.3): a look no longer turns a
  part of their group into the whole of it once the left-out category is
  hidden, no longer freezes their group into ids when one of theirs
  arrives while the picker is open, and no longer collapses my group to
  "all" over an archived category I had left out. `fromPicker` takes
  what the picker showed when it opened (`CategoryAllowlist.opening`)
  from each of its four callers.
- **"Select all" is all**, with one of theirs hidden too, and with none
  of theirs on offer — the first cut of this round lost the first, and
  the reviewer's sweeps (a hundred and thirty thousand picks each,
  catalogue changes during the pick among them, and ten thousand editor
  cases) found both.
- **A report digest's editor opens its picker on what its row says**
  (`forDigest`) and stores the answer over the list as it is held: a
  list that named {name}'s group alone read "Events" on the row and
  opened with no row ticked; and their part is carried, so a switch back
  to Upcoming in the same editing session finds it — the report's
  reading is applied once, at the save.
- **A saved view compared in the report is read as the report reads a
  list** (`forReport`): a view of {name}'s group compared as "none of my
  events".

Kept as they are: a changed pick that ticks every listed row of mine is
my whole group, also while an archived category was left out — older
than sharing, and what "Select all" has always meant; an account that
never paired stores exactly what it stored before the feature, an
untouched Done included; a list that names only {name}'s ids reads "No
categories" after the pair ends, and the report counts nothing by it —
the filter was "only theirs", and theirs is gone; a category of mine
that arrives from my other device while a picker is open and is not
ticked stays out, as one made inside the picker does; "Select all" while
one of theirs arrives mid-pick stores their part as the ids that were
shown; and with a left-out category of theirs hidden, a list can show
every row ticked and still be a filter until a pick changes it ("Select
none" clears it).

### After the final reviews — no alert goes off unsaid (2026-11-13 → 14)

The second review of D30 found five gaps; D38 was decided beside them.

- **One rule for "armed"**: a pending registration whose time is still
  ahead (`AlertRegistrationDao.armedEventIds`). The confirmation's count
  and the leave notice both say by it, so an alert that already rang is
  never said to go off (A18).
- **An arrival undone before it could be said is dropped**, at the moment
  it would be said: a category asked of `partnerSharesCategories` — the
  catalogue answers for {name}'s own, and one read of the shared
  built-ins for a built-in of mine, which the catalogue holds as my own
  row either way — and an event of the calendar. Nothing left, nothing
  said; never "{name} shares Other with you".
- **A held hide bar** keeps to the database it was made in, and is
  dropped when the category shows again before it could be said.
- **The confirmation's wait has one deadline.** It already had: the outer
  bound wraps both reads. The finding was a misreading, and the claim is
  now a test.
- **What may ring belongs to the pair (D38).** Adopting another pair puts
  "Alerts for shared events" back at "Only alerts I add", whatever stood
  — "Off" included: each pair chooses again, and under that choice
  nothing rings that the person did not add themselves. The choice is
  written **in the pair's own write** — both or neither
  (`SettingsService.setPairingSettings(startAlertsAt:)`): a pair can
  never be stored with the old pair's choice standing, and a write that
  fails fails the adoption, which the next reconcile tries again. After
  a reset that changed the value the alert pass a change by hand runs is
  run, so nothing armed under the old choice outlives it. **The same
  pair found again keeps its choice**: the last pair this database was
  in is remembered (`pairing_last_pair`, a pairing row like the others —
  in no export, in no handed-out copy), so a pair lost locally while the
  server could not be asked, and adopted again under the same id, is not
  "another pair" — or a glitch would silently take "Category alerts too"
  away. A real re-pair, with the same person too, has a new id and
  resets. A database whose pairing was forgotten in between — a restore,
  another account signed in — counts as another pair.

**After the independent review of those fixes** (five ordering defects in
the listener, each reproduced by a probe; a run's kept notices hidden
from a live app; the reset not atomic with the pair), a second leg:

- **A bar names only arrivals it has just asked about.** What lands
  while the check waits stays held for a turn of its own, which checks
  it — never one bar that mixes checked and unchecked arrivals.
- **No wait before a bar is unbounded** (`shareNoticeCheckLimit`, three
  seconds each). A leave needs only the share service; an arrival's
  check that does not answer is skipped and the arrival said as held —
  a check can cost an undone arrival being said, never a leave. The
  listener's turn is released on every path.
- **"Dealt with" lasts as long as the store's forget, and no longer.** A
  kept notice said once is said again when a later run keeps the same id
  anew; a notice said live has its kept copy forgotten unsaid.
- **A notice belongs to the opening of the database it was made or read
  under** — kept, live, or a hide, which is stamped at the act. A switch
  during a read drops the result and forgets nothing in the other
  database's store.
- **A notice a run kept behind a live app is seen.** Where a run can
  exist the list of databases that keep notices is read from the
  platform's store, not from this isolate's copy, at start and at each
  return; and after a catch-up (the freshness record's H2) the listener
  reads again at once. An install where no run can exist makes no
  platform call, runs no statement and looks for no file.
- **Leaves under different names are separate bars**, oldest first; a
  kept leave carries its own name.
- **An arrival in a category hidden on this phone is dropped unsaid**: a
  person is not told of an event they chose not to see.

### After the final reviews — the browser and the Sharing page (2026-11-13 → 14)

The final review of the browser and the Sharing page found seven things
(§16.9, B1–B7), two of them reproduced; a pass of pins the outage had cut
was finished first. One worktree, the implementers one after another;
each fix has a test seen red, or shown able to fail by a mutation that
was then restored byte for byte. An independent code review of those
fixes then confirmed all seven and found two things more — a stack of
pages where a share ending said nothing, and a search that outlived a
database switch — and a further leg answered them.

**What a person gets.** A partner's folder never opens writable, by any
door, for any frame. When a share ends under me one bar says so,
whichever page I am on. The ⋮ button of a folder page is the button it
always was — its ripple, its tooltip, its badge — and opens on one tap,
paired or not. A failure is said once, by the sheet that asked. The share
picker's search knows what is shared now.

**The pieces.**

- **One voice when a share ends — decided by who leaves.** One leave
  says one bar: the front-most page that leaves says it, and a leave
  under pages that all stay is said at once, over them
  (`ShareLeaveVoice`). Every folder page and editor takes its place as it
  opens and hands the voice a probe — "is my own row gone?", the same
  predicate it closes by. A page's leave is silent only when a page in
  front of it leaves too: it has already spoken, is still asking, or its
  probe says gone. The probe is asked only at a leave, after the sync
  run's hooks, when every removal of that run is in the database; one
  that throws counts as "stays" — two bars are better than none. A page
  that never learned whose its row was — an editor opened over cold
  caches — says the share's words when a leave under it was silenced for
  it, never "deleted on another device". A page of mine in front that
  loses its own row in the same run speaks in its own words. The registry
  is emptied when the database switches, and a page that spoke closes by
  pops and removals no `PopScope` can refuse. The first form of this rule
  silenced a leave whenever a page *known to be {name}'s* stood in front;
  its review found the stack where that page stays — {name}'s folder, a
  page of mine, their other folder still shared — and nothing was ever
  said. An account that never paired pays one list entry and one closure
  per open page: no read, no notify, no rebuild.
- **The editor's return asks the database nothing about notes, folders or
  sharing** — only the settings re-read that lets a setting edited above
  apply on the way back. Pinned over a counted twin of the database file
  (`openCountedTwin`, test support).
- **A share act across a database switch writes nothing.** The folder
  menu's toggle checked the switch only after the write; a switch while
  the share service resolved handed back the new database's service and
  the act went into it. The fence now stands before the write too.
- **A look read that fails no longer blanks the page (B1); a share
  service that cannot be built is not asked once per frame (B2).**
  `PartnerLookReader`: the first failed read ends the hold, the hold is
  bounded at two seconds (`AppConstants.partnerLookHoldLimit`), and a
  failed start is tried again only by something outside the reader — a
  start under the same asker, pairing and database is a no-op. And the
  hold no longer blanks anything: while the look is out the page draws
  its bar — back, search, ⋮ — and leaves out only the partner line and
  the rows, which then appear under a bar that does not move. Every
  writing entry is off there (the page is read-only), so nothing can be
  done wrong in those two seconds.
- **The ⋮ button asks nothing before it opens (B3).** The overlay
  (`_OpensWhenReady`), the pre-open ask and `PartnerLookReader.resolve`
  are gone. The share census's one statement also reads the stored pair
  id (`ShareSnapshot.paired`); a pairing write that changes the stored
  pair id forgets the census — only that, not a name refresh or a
  dismissed notice (`PairingService.writes`, a static relay — no hook of
  the container can see an instance the pairing bloc or the sync hooks
  built before its first write); a page starts its look reader from that. No statement
  more for anyone, pinned in `query_count_test`; an account that never
  paired builds no share service and has the exact button of before the
  feature. On a cold process a paired account's first folder page shows
  the share entry a few milliseconds after its first frame, when the
  share service answers.
- **A share act reaches the picker's search (B4), and the search follows
  the database.** `FolderNameIndex` is marked dirty by
  `FolderRepository.shareFactsChanged`. Lazy: nothing is read until the
  next search. Both repositories' share-facts streams are one helper
  (`ShareCensus.forgottenAcross`): resubscribed when the database is
  rebound, and the rebind itself told as a forget — so after a switch the
  pickers no longer search the previous database's folder names (older
  than this pass, found by its review), and a page that outlives a switch
  still hears the new database's census. A build of the index that a
  dirty mark overtook does not publish.
- **One height for the picker's reason (B5).** In the share pick the
  slot under the path is always there, searching included — the button
  still confirms the folder the crumbs are in — and is laid out for two
  lines (`FormCaptionSlot`); a longer reason is cut with an ellipsis, the
  crumbs carry the name in full and the semantics read the whole line.
  The literal sizes became role-named metrics on `FormMetrics`:
  `pickerReasonPadding`, `pickerReasonLines`, `pickerChevronSize`,
  `buttonGlyphSize`, `menuRowGap`.
- **An outcome belongs to the sheet that asked (B6).** A share act
  carries its asker (`ShareActEvent.asker`, by identity, outside the
  event's equality) and its outcome names it; a sheet answers only its
  own, and the Sharing page speaks for every act no sheet asked for —
  its own, and an Undo tapped after its sheet had gone, whose failure
  used to go unsaid while another list sheet was open.
- **Smaller (B7).** One reload per share act — the census's forget
  reloads the page, the act no longer does it a second time, so the page
  that acted shows the sign after the same 120 ms as every other open
  page. A disabled action of a row sheet is one node, a button that is
  off. The Sharing page holds only the route its opener really pushed
  (the top route before against after). And **the cold door**: the
  folder cache outlives the census, which many ordinary events let go,
  so a way back to {name}'s folder when it was not on the stack — a
  restored note, a chain of wiki links — could open it writable. Every
  door that reads the folder now hands over whose it is
  (`AppNavigator.popToFolder` / `popToAncestor`, the replacement page,
  the launch restore).

**Checked and found sound, now pinned:** the picker's path row four long
German names deep at text scale 2.0 in all three picks; a partner's
folder page four long names deep at 2.0 (the bar's eyebrow, title and
line keep their order and clear the toolbar).

**After the second design review** (the editor, the Sharing page and the
Linked note row judged whole; round one's findings rechecked, with real
fonts at 360 wide, light and dark, 1.0 / 1.3 / 2.0):

- **No label of the two ⋮ menus is cut at German, text scale 2.0.** A
  label wraps, three lines at most (`FormMetrics.menuLabelLines` — "In
  meine Notizen kopieren" needs three in the room a 2.0 menu leaves), and
  a row with a value — a note's folder, the folder menu's Sort — puts the
  value under its label when both do not fit. At 1.0 every row is the 44
  dp it was; at 1.3 the rows that used to be cut now wrap and grow.
- **The picker's reason says why first** — "Already shared: {folder}", a
  key of its own — so a long name is what the two lines cut, not the
  reason; the two snackbars keep the sentence. While searching the slot
  keeps its height and says nothing: the crumbs it would speak of are
  hidden, and each result carries its own reason.
- **The picker's title cannot starve its list**: clamped like every kit
  dialog's (`FormMetrics.dialogTitleMaxTextScale`). At German 2.0 the
  share pick's list held one whole row; it holds three, the move and
  copy picks four.
- **The Linked note row stands from the first frame**, empty and inert
  while its title loads, so the sheet's top does not jump when it lands.
  A link to a note that is not shared still removes the row once.
- **The editor names {name} from its first frame** where the pairing is
  already known in memory — it used to say "your partner" and then the
  name.

**After the re-check of the last two legs** (the same reviewer; the
stack that said nothing and the index that served another database were
closed, five narrower findings were not — all closed since):

- **A probe that never answers holds nothing.** A leave asks every page
  in front of it "is your row gone too?"; each ask is bounded by a second
  (`AppConstants.shareLeaveProbeLimit`) and a probe that has not answered
  counts as "stays", like one that throws. A read that stalled used to
  leave that leave pending for good, its page counted as leaving, and
  every later leave under it silenced.
- **A leave speaks only for the database it began under.** It takes the
  database generation when it begins; moved by the time the asks return —
  a switch, a restore — nothing is said over the new database.
- **A search never answers from an emptied index.** A build the
  generation overtook is run once more; overtaken a second time in a row
  the search serves what the last build read rather than "no folders" —
  at worst, for one keystroke, the names of the database that just
  closed.
- **The Linked note row cannot be left empty and inert**: a tap that
  finds the note gone while a re-read is in flight clears the loading
  mark with the note, and the row goes.
- `shareFolderAlready` is the sentence it was ("{folder} is already
  shared") for the two snackbars and a search result's subtitle; the
  picker's reason slot reads `pickShareAlready`.

Kept as they are, by ruling: two bars rather than none when a probe
throws; an editor disposed before its folder's leave lands; a ⋮ row
with a value that grows at 1.0 when the label and a long value do not
fit (it used to overflow or cut); the confirm button off with no reason
beside it while searching — each result says its own.

**After the last review** (an independent read of that leg, then a
verification of what answered it; nothing severe):

- **One bar, whoever closes what while a leave asks.** A leave is
  silenced only by a page in front that has left or is still there to
  leave, and is said after all when none of them is left to speak. Four
  sequences ended wrong and are that one rule now. A page that left
  stays counted while any leave is still asking: the note that spoke and
  was disposed before the folder's ask ended cost a second bar. A
  probe's "gone" counts only for a page still open when the answers are
  used: one the person closed meanwhile will never speak, and the folder
  under it said nothing. A leave silenced for a page that then goes
  without leaving — popped by the person before its own leave landed —
  is kept with that page and said after all, once, in the words it had,
  never across a database switch. And with three pages open — an outer
  folder, a folder, a note — the kept leave moves on to the next page
  that silenced it before it is said, so the folder speaks once where
  the outer folder and the folder each spoke.
- **A tap on the Linked note row opens only what the event links now.**
  While a re-link's lookup is out the row still shows the old note: a
  tap then opens nothing, and a tap whose own read returns after the
  re-link changes nothing of the row. The leg before removed the row
  there although the event linked a note that exists.
- **The picker's search never serves another database's names, nor an
  older read**: whatever the index holds — published or the fallback —
  is stamped with the repository binding it was read under
  (`FolderRepository.bindings`, a count of rebinds) and the order it
  was read in, and is not served under another. The database generation
  could not be that stamp: it moves when a switch begins, before the
  repository is rebound, so a build in between was stamped new and read
  old.
- **A share pick whose folder is gone by then says the change failed**;
  it used to close in silence.
- The editor's partner group no longer passes by margin
  (`ShareLeaveVoice.probeLimit`, set long where a suite's fake clock
  outruns real reads); `shareFolderAlready`'s description names its
  three readers.
- **Identifiers for the device flows** — nothing a person sees, hears
  or taps changed: the folder page's ⋮ (`folder-more`), the entries of
  a note row's and a folder row's long-press sheet (`row-action-…`),
  the folder picker's search field, confirm, cancel, up arrow and rows
  (`folder-picker-…`), the editor ⋮'s folder entry
  (`editor-menu-folder`). The device pass had tapped these by screen
  coordinates, which no flow in the repository does.

Kept, by ruling: a probe that answers "gone" after its bound, whose page
then leaves, gives two bars — the bound's price; a rename of the open
database, or a failed download that switches out and back, moves the
database generation though what the person sees does not change — a
leave asking in that instant says nothing; an editor whose row went
and which keeps the typed text as a new note never leaves, so a leave
kept with it is said when the person closes it — late, and still true.

Kept by the lead, **open for the owner**: the share sign beside a note's
title in the editor's bar costs a title of seven to nine characters its
last letters (the bar leaves the title 75 dp; the sign and its gap take
22). It stays, because it is the one cue on that screen that {name} can
read what is being written; the option not taken is a sign that yields
to a short title. Recorded: the read-only line is 123 dp tall at German
2.0 with a long name (as specified); the share entry is taller than the
spec measured and cuts nothing; `FormPickerRow` carries no button flag —
an app-wide primitive, not this pass's.

### Found on a device (2026-11-14)

The pass's own device flows found five things no suite had, each fixed
where it was and proven on the guests again:

- **A QA build's run without the app could not start** — a fix leg had
  put the alarm-presenter resign ahead of the QA build's preference
  namespacing, which the plugin refuses once the preferences were
  opened. Production was never affected; the device proof of the whole
  check was red. `cloud-shared-freshness.md` §12, "Found by the device
  pass", has the cause and the rule it leaves.
- **A share mark outlived its pair in the app's own lists** (D39, §16.2).
  As built: `SettingsService.setPairingSettings(…, clearMarksOfOtherPairs:)`
  clears them inside the pairing's own transaction
  (`FolderDao.clearSharesExcept(pairId)`, after one statement that says
  whether any mark stands), `PairingService` asks for it at every
  adoption of a pair other than the cached one, and
  `ShareService.afterMarksClearedElsewhere` tells the folder cache, the
  event and category caches and the calendar — with or without a share
  service built, since the calendar and the folders hold their flags
  without one. An adoption with no mark is one statement; the same pair
  again asks nothing.
- **"Sharing ended" named nobody** when the partner had deleted their
  account while paired: `" ended sharing. …"`. A blank name is no name
  now, decided where the state is made (`PairingEnded.from`), and the
  Sync page's line and its notice choose their words in one place — "Your
  partner ended sharing. …". Older than this pass; the case had not been
  walked on a device before.
- **Leftovers that read as a regression.** A pass that aborts leaves
  alerts armed on a guest, and one kind the QA reset's quiet could not
  reach: an alarm named only by its notice, or held in the alarm
  plugin's own list with a payload the alert tier does not read. It
  stayed armed through every reset, a reinstall and a cold boot — the
  plugin arms what its own store holds — so every later pass on that
  guest went red wherever a flow expected none armed, on a build that
  armed nothing. The tell: the pair was already armed right after
  pairing on a fresh suite, in a pass that had armed nothing yet. The QA
  quiet now reads the pending notices and the plugin's own list too
  (`lib/core/qa/qa_alert_quiet.dart`, QA builds only), and the harness
  has a plugin-level recovery for a guest that already holds such an
  entry (`qa platform-alerts --native`, fleet guests only).
- **The harness** — every verb on a guest took seconds after a work had
  started that guest's process (the connection fell to adb), and a
  control with no identifier could only be tapped by its coordinates.
  The harness finds a process no launch started, an `id:` target may end
  in `*` for an id keyed by a row minted at import, and the folders'
  surfaces carry identifiers (the browser block above).

---

## 16. The finishing pass (2026-11-13)

**Status: BUILT AND REVIEWED 2026-11-13 → 14.** Slices F, H, I, J and K
were built and committed at the pause (`daa6d9c4`). The pass's final
reviews then found more; every finding is decided (D38, §16.3, §16.4)
and built, each stream read again by a reviewer who had not built it
until its findings ran out. **§16.9 says where each finding was closed,
what was proven on a device and what stays open** — for the owner, or
for two real phones. §15 is the truth for what the tree does.

### 16.1 Scope — the owner's words

2026-11-13: "please finish the feature of the cloud sharing, I believe
there are some slices like F left, then do a very important review to see
if they work". Of the four limits the build of A–E and G was handed over
with: "The agenda limits we should fix" · "Second we should fix" · "Fix
the third" · "It is okay for partner to not edit what I share". And: "I
do not want tech debt. You also have full permissions to fix tech debts".

So this pass builds slice F as §6.11–§6.13 specify it, removes three
limits (D29–D32), closes what the build left as "kept, known" (§16.5),
and ends in an independent review and the two-phone suite (§16.7). The
partner still never edits (E5, N3).

### 16.2 Decisions

Taken by the lead on the owner's delegation of 2026-11-13; the option not
taken is named so it can be chosen instead.

| # | Decision | Why, and the option not taken | By |
| --- | --- | --- | --- |
| D29 | **A category filter stores a whole group as the group.** Two reserved entries in an allowlist: `*mine` — every category of mine, whenever made — and `*partner` — every category {name} shares that this phone shows. A group whose every listed category is ticked is stored as its entry; both groups whole is no filter, stored empty as today; a part of a group is its ids, as always. It holds for every allowlist: the agenda's, the overview's (the live one and a saved view), a digest's. With no partner's category listed nothing new is ever stored, so an account that never paired writes what it writes today. | "The agenda limits we should fix." An explicit list of today's categories cannot know tomorrow's; the intent "all of mine" can. The same defect stood on the other side (all of the partner's, one of mine un-ticked), so both groups get an entry. Not taken: a second stored field per filter — the same exposure on an older build and one more shape; a wire bump for the saved view — the only builds that can read a wire-48 space and do not know the entries are the development builds of 12–13 November, which would draw such a view without that group until updated and lose nothing. | Owner asked; Lead |
| D30 | **No alert of mine goes off silently.** *My act, with a confirmation* (stop syncing, unpair, restore a backup, delete the cloud copy, delete the account): the confirmation gains one sentence, only when an alert of mine is armed on something {name} shares. *My act, at once* (hiding a category): one bar, said where the switch is — "{category} is hidden. Your alerts on it are off until you show it again." — only when one was armed. *{name}'s act* (un-shared, deleted, the pair ended by them, their account deleted): the notice of D23, which now names them — the name outlives the pair. After an act of my own nothing more is said: the confirmation was the conversation. | "Second we should fix." The rule of D23 was "a silent departure is a problem only when I was counting on a reminder"; that is as true when the act is mine. Not taken: a notice after every one of my own acts (says twice what the dialog said); a list of "alerts that went off" to visit. Switching "Alerts for shared events" to Off needs nothing: its own line says nothing shared rings. | Owner asked; Lead |
| D31 | **What leaves this phone takes its armed alerts off the platform at once** — on "Stop syncing" too, where no sync run follows to do it. | Definition of done 5 says so; the stop path was read and holds no alert pass of its own. Pinned by a test first. | Lead |
| D32 | **The phone keeps what {name} shares fresh while ANTA is closed, on Android**: it checks on its own — more often as an alert of mine on a shared event comes near, never when no alert depends on it — and a change by {name} can wake it at once through a small relay the owner deploys. Its record is `cloud-shared-freshness.md`. The read sheet's caption and the guide say what is true on the phone they run on. | "Fix the third." An alert is the one thing that acts while the app is closed, so it is the one thing that must not be stale. The check needs no server and is proven on the emulators; the relay is the roadmap's P6 and is what makes it immediate. Not taken: a background service with a live listener (a permanent notification, the battery); the paid plan's server functions (a card); push alone (nothing works until the relay is deployed, and nothing proves it here). | Owner asked; Lead |
| D33 | **{name}'s Single events open their read sheet from the Sharing page too**, through the calendar's own door for an event opened from outside the calendar. | A list of rows that look tappable and are not was a debt of slice D. | Lead |
| D34 | **A digest restricted to categories can name {name}'s** — its picker lists the "From {name}" group under "Category alerts too", like every allowlist. | It listed mine only, so a restricted digest could not hold what the setting let ring. | Lead |
| D35 | **Who ended the pair is known** (`PairRecord.endedBy`): the leave notice names {name} when they ended it and is not said when I did (D30). | "Your partner no longer shares…" after my own Unpair was wrong twice. | Lead |
| D36 | **R9 stays** — an event shared alone from a category that is not shared draws as Other. | The fix sends that category's name, colour and icon with the event; a person who shares one appointment has not said the name of its category may travel. It errs private until the owner says otherwise (§13). | Lead |
| D37 | **A partner's folders are opened from the Sharing page** by a tap on their row; my shared folders are stopped there with ✕ and added with "Share a folder". | The same list shape as the events' (§6.2), with the tap D33 gives events. | Lead |
| D38 | **What may ring belongs to the pair.** "Alerts for shared events" goes back to the shipped choice, "Only alerts I add", when another pair is adopted — from "Category alerts too" and from "Off" alike; the same pair adopted again — a reconcile at launch, or a pair lost locally and found again under the same id — keeps it. | Found by the pass's final review: the choice was stored with the database and outlived the pair, so "Category alerts too", chosen for one person, armed my alerts on a built-in the next person shares without my having chosen that for them — against S7 ("nothing is carried over; each chooses again") and against "nothing arms that the person did not ask for". What shows already went with the rows. Not taken: keeping it as a setting of the app — quieter to build, and wrong the first time it rings for someone I never chose it for. **Open for the owner — "Off":** it is reset too, so the alerts I add on the new partner's events ring; not taken: keeping "Off" across pairs, under which those alerts would stay silent by a choice made for someone else. | Lead |
| D39 | **A mark of another pair is never a share.** When the stored pair becomes another pair, every share mark set under any other pair — on folders, events and categories — is cleared in the write that stores the new one: stamped and queued, so those rows are sent private by the next drain, and every cache that holds a share flag is told. Not at an unpair and not while the pair is merely lost locally: there the shared reader clears, when the server says there is no pair, and the same pair found again keeps its marks. | Found on a device by this pass's own flows: after "un-pair, pair again" a folder shared under the ended pair read "Shared with {name}" at once, and a tap on it "stopped" a share nobody had made — against S7 ("nothing is carried over; each chooses again"). The wire was sound and was checked first: a stale mark names the ended pair, which nobody can read, and no path writes the new pair's id from it. But every list of the app's own — the browser's census, the event's and the category's switch, the Sharing page — asked only whether a mark stood, never whose, until the new pair's first shared read cleared it: seconds, or as long as the phone stayed offline. Not taken: teaching each reader to compare the mark with the stored pair — five readers and every one after them; the write makes the stale state not exist. | Lead |

### 16.3 The allowlist, exactly (D29)

One place decides: `CategoryAllowlist` (`lib/utils/category_allowlist.dart`),
pure, with the two entries as constants. No reader of an allowlist
compares ids by itself any more.

- **Which side an event is on.** {name}'s side: the event is theirs *and*
  the category it draws under (`CalendarCategories.drawnIdOf`) is one of
  their own. Every other event is on mine — my own events whatever their
  category (an archived one, an id no category holds: the report's D32
  still meets it by its stored id), and {name}'s events that join a
  built-in of mine or draw as Other.
- **Admits.** Empty admits everything. My side: `*mine`, or the id (the
  drawn id for {name}'s event, the stored id for mine). {name}'s side:
  `*partner`, or the drawn id.
- **Stored from the picker.** With no partner's category listed: exactly
  today's rule. Otherwise: both groups whole → empty; a whole group → its
  entry; else that group's ticked ids.
- **Ticked in the picker.** An entry ticks every listed category of its
  group; an id ticks itself; a stale id ticks nothing and is dropped at
  the next store, as a deleted category's always was.
- **Counted and "on".** A chip, a saved view's subtitle and
  `allowlistLabel` count the listed categories that are ticked. A list
  that holds `*mine` while no category of {name}'s is listed filters
  nothing and reads as off — the pair ended, or everything of theirs is
  hidden here; it filters again when one is listed.
- **A saved view syncs** with its entries as two more strings of the same
  list; nothing else about its payload changes.
- **A pick changed to nothing is every category.** A pick the person
  changed into one that ticks none of the rows the picker listed —
  "Select none", or the last row un-ticked — stores the empty list,
  whatever the list carried for rows it could not show: a hidden
  category's id, the other group's entry, the id of a category that is
  gone (the picker hands back what it has no row for). A carried part
  rides along only with a pick that ticks something. This holds for an
  account that never paired too — the one case where it stores other
  bytes than before the feature: a list holding a deleted category's id,
  "Select none", stored that id alone and showed nothing.
- **A Done on a picker nobody touched is no store.** Each sheet hands the
  store what its picker showed when it opened — the rows listed and the
  rows ticked (`CategoryAllowlist.opening`) — so "untouched" is judged
  against what the person saw, not against a catalogue that moved
  meanwhile. An answer equal to what opened, with no row that was not
  there at the opening, gives the list back as it is: never widened,
  narrowed or rewritten by a look. {name}'s group alone, opened where
  this picker cannot list it, stays {name}'s group alone — reading "No
  categories" there, and meaning theirs again once the setting lists
  them. The one Done that changes no tick and still stores is the one
  after a category was made inside the picker and left un-ticked: it
  stays out, as it always did.
- **A pick changed into every row on offer is every category** — the
  empty list: "Select all" means all, also while a category of {name}'s
  is hidden on this phone, and where none of theirs is on offer at all
  (every one hidden, or a surface that lists none). It is the one place
  a part of theirs the picker could not show is not carried.
- **{name}'s part changes only when a row of theirs is changed.** Only
  they can add to their group, so while no row of theirs was touched the
  list keeps exactly what it held of them — the whole group where it held
  the whole group, the same ids otherwise: a category of theirs that
  arrives while the picker is open is not left out by a pick nobody made,
  and one I had left out and hidden since is not taken in by ticking the
  rows beside it. Once a row of theirs is changed, every row of theirs on
  offer ticked is their group, and a part is its ticked ids beside the
  hidden ones the list held. My own group is read from the answer as it
  came: whole, it is its entry; a category I make inside the picker and
  leave un-ticked stays out.
- **A report holds no part of {name}'s** (the report's D15): `forReport`
  is applied where a list reaches a report — the page, a saved view the
  report compares with, and for a report digest at its store, where the
  planner scans its span, where the scheduler folds and names it and
  where its editor opens its picker (`forDigest`, one reader for all of
  them), since a list can arrive from my other device. Their events never
  keep a report's span alive, whatever "Alerts for shared events" says.
- **While no category is known at all** — the moment after a database
  switch, before the first load — a list that holds an entry reads as in
  force, as `admits` treats it: nothing is claimed about what it covers.
- **`*partner` is the partner of the moment.** A view or a digest that
  holds it reads "No categories" while nobody is paired and means the new
  person's categories after a new pair — which is what its words say. A
  digest rings for them only under "Category alerts too", which a new
  pair starts without (D38).
- **A list stored by the builds of 12–13 November stays the list it was.**
  Those builds stored "only mine" as that day's ids. No migration: a list
  cannot say whether it was meant as "all of mine", and those builds ran
  on the development phones alone. Such a list becomes the group at the
  first pick that changes it and leaves every row of that group ticked —
  un-tick one row, Done, tick it again, Done; a Done on it untouched
  stores nothing, like every untouched Done.

### 16.4 Cases added to §8

| # | Situation | What happens | Where |
| --- | --- | --- | --- |
| R15 | I filter the agenda to mine only, then make a category | Its events are there: the filter holds "all of mine". | D29 |
| R16 | I filter to {name}'s only; {name} shares one more category | It is in. | D29 |
| R17 | I pick two of my five categories | Those two, as always; a sixth made later stays out — I chose a list. | D29 |
| R18 | A saved overview view holds "all of mine"; the pair ends | The view shows everything and its chip is off; pair again and it means only mine again. | §16.3 |
| A13 | I hide a category of {name}'s that an alert of mine rings for | One bar, over the sheet, says the alerts on it are off until it shows again; showing it arms them again. | D30 |
| A14 | I stop syncing, unpair, restore or delete the cloud copy while an alert of mine is armed on something shared | The confirmation says so before I confirm; the alerts leave the platform with the rows. | D30, D31 |
| A15 | {name} ends the pair while my app is closed | At my next open — or at once, with the relay — one notice names {name} and says my alert is off. | D30, D35 |
| A7 | {name} moves or cancels the event while my app is closed | On Android my alert follows: at once with the relay, else at the phone's next check, which comes sooner the nearer the alert is. Offline, it rings at the time this phone last knew. | D32 |
| N10 | I tap one of {name}'s folders on the Sharing page | It opens in the browser, read-only. | D37 |
| R19 | A filter holds two of my categories and one of {name}'s that I have hidden; I open it and press "Select none", Done | Every category again — never a list that shows nothing. | §16.3 |
| R20 | A digest holds "all of {name}'s"; the pair ends; I pair with someone else | It reads "No categories" in between, then means the new person's — and rings for them only once I choose "Category alerts too" for this pair. | §16.3, D38 |
| A16 | I chose "Category alerts too" with {name}; the pair ends; I pair with someone else | The choice is back at "Only alerts I add": nothing of the new person's rings that I did not choose. | D38 |
| A17 | I switch "Alerts for shared events" from "Category alerts too" to "Only alerts I add" | The category's alerts on {name}'s events go off and nothing more is said: each choice's own line says what rings (D30 says it of Off; it holds for every choice). | D30 |
| A18 | An alert of mine on {name}'s event rang an hour ago; {name} then stops sharing the event | Nothing is said: no alert of mine was still ahead. | D30 |

### 16.5 Debt — closed in this pass, or kept with its reason

**Closed** (each with a test that would have been its probe):

- `ShareService.setFolderShared` is one act — one transaction, a
  `ShareChange` with its Undo — like the category's and the event's.
- The Sharing page's Folders entries, the notes look, the words that
  name folders (`shareMarkMineDesc`, the stop-all confirmation, the
  guide's "What is never shared"), a partner's event's Linked note —
  slice F.
- {name}'s Single events open nothing (D33). A restricted digest lists
  mine only (D34). "Your partner" after an unpair (D35).
- Held-back rows land at the read that freed them, not only at the next
  start or "Sync now".
- A person's own presence marks and alerts on a shared event are left
  out of the calendar's export lists, as the event is.
- "Sending…" while the pusher has parked a share's entry: the header
  says "Waiting to send".
- A reload that fails right after an act no longer drops that act's bar;
  an Undo queued behind a running act is written by the service when its
  bloc closes; an Undo, or a share written for a new category, that fails
  after its page has left is said on the app's messenger.
- The Categories page follows a pairing made while it is open.
- A confirmation of the Sharing page's own is never taken for the "pair
  ended" notice: the page closes the routes it opened by their handles.
- A shared built-in's caption no longer starts a line with "·".

**Kept, each for a reason that is not "later":**

- A stale id of {name}'s stays in the grid's denylist until its picker is
  next opened: a denylist entry for a category that is gone hides
  nothing.
- A disabled `FormSwitchRow` in the mode no share row uses dims its
  switch twice: every disabled switch in the app would repaint — the
  UI-language record's call.
- A category and single events that arrive in one read are told as the
  category; an event back from a tombstone is no arrival: both by design
  (D23 — arrival is news once).
- `FormSectionLabel` speaks its capitals and the kit's switch entry
  carries its id on an unlabelled node — app-wide kit behaviour;
  `ui-language-adoption-roadmap.md`.
- Adopting `FormSheetSemanticsRefresh` in the sheet chrome app-wide: the
  same record's open decision; every sheet of this feature that opens a
  route above itself carries the wrapper.
- R9 (D36). The partner's counters and currency on a shared note (F7).

### 16.6 Slices

| Slice | A person can | Holds |
| --- | --- | --- |
| **F0 — the notes' share core** | (nothing new on screen) | `fromPartner` and the share state on `Folder` and `NoteMetadata`, set where the services load; `ShareService`'s folder act, overview and `copyNoteToMine`; `shareNoteLook`; Recent without {name}'s notes; "Send a copy" refused for {name}'s rows (each of F1–F3 adds its own strings, ids and metrics) |
| **F1 — the browser** | share a folder from its menu; see {name}'s folders under "From {name}" | §6.11, §6.12; the picker's sign; the move's snackbar |
| **F2 — the note** | read {name}'s note without a failing save; copy it | §6.13; the sign beside my shared note's title; the Linked note row |
| **F3 — the Sharing page** | see, stop and add shared folders; choose the notes look | §6.2's Folders entries and sheets (D37); the words that name folders; the guide |
| **H — the filters and the alerts** | keep "only mine" true; never lose an alert unsaid | D29–D31, D33–D35 |
| **I — the check** | have alerts follow {name}'s changes with the app closed | `cloud-shared-freshness.md` §4–§6 |
| **J — the relay** | have them follow at once | `cloud-shared-freshness.md` §7–§9; the owner's deploy |
| **K — the debts** | — | the rest of §16.5 |
| **L — review and proof** | — | §16.7 |

F0 first; F1, F2, F3 and H side by side in worktrees; I after F0; J after
I; K after F3 and H; L last.

### 16.7 Review and proof

- One `reviewer` per slice; slice I and slice J are read by Fable 5.2,
  as is the whole pass at its end ("a very important review… you may use
  fable 5.2 more than usual", the owner, 2026-11-13).
- `design-reviewer` on F1–F3 against the designer's spec.
- `qa pass share` with new flows: a folder shared from its menu and read
  on the other phone; {name}'s note opened read-only and copied; the
  folders stopped from the Sharing page; "only mine" kept across a new
  category; a hidden category's bar; the check proven with the app
  closed — {name} moves an event, the job is run, the armed alarm has
  moved. Then `calendar`, `alerts`, `browser`, `settings`, `sync`.
- Definition of done: §12, with item 7 now in scope and A7 as §16.4
  words it.

### 16.8 The look of slice F — the designer's defaults, taken

One designer rendered F's surfaces with real fonts and returned one spec
(folder and note rows, the partner's folder page, the share entry, the
picker, the editor, the Sharing page, the two folder sheets, the Linked
note row). Its defaults, taken by the lead on the owner's delegation;
each differs from, or adds to, §6 and can be overturned:

| # | Decision | Instead of |
| --- | --- | --- |
| fa | A subfolder inside a folder I share wears the sign. | only the marked folder |
| — | The mark stands **before the count** on a folder row and **at the start of the second line** on a note row and a search result (a 16 dp face). | §6.7's end slot, which cost a note's title 34 dp at every scale; a badge on the 22 dp folder glyph could not be read |
| fb | The reason is said once per surface, as a line at its top; no caption under each disabled entry. | a caption per entry |
| fc | One new widget, `SharedReadOnlyLine` (`content_rows.dart`): under the editor's bar, under the bar of a partner's folder page, in the header of a partner row's long-press sheet. | — |
| fd | A partner's folder page carries "From {name} · Read only" under its bar, at any depth (32 dp). | a dimmed create bar that nothing explains |
| fe | The share entry is **absent** on a partner's folder. | §6.11's disabled entry — "Share with Maria" on Maria's own folder reads as a fault |
| ff | "Copy to my notes" is in a partner note's long-press sheet too. | the editor's menu alone |
| fg | Shared through an outer folder: the entry disabled, captioned "On for everything in {folder}". | no caption |
| fh | The "From {name}" header is uppercased like every header, an e-mail address included. | — |
| fi | Paired, not syncing: the menu entry is disabled with "Turn on sync to share" and takes no tap — the Categories menu's built precedent. | D8's tap that opens Sync & sharing, which stays on rows and switches |
| fk | A partner's folders on the Sharing page: rows with a chevron that open the folder. Mine: no tap; ✕ stops. | — |
| — | Inside a partner's folder and on her rows Select is disabled, not hidden; in selection mode the From group draws at 38 % and takes no tap. | — |

Not taken — **fj** (both folder sheets inside `share_events_sheets.dart`):
the frame the list sheets share moves to a file of its own and the folder
sheets get theirs, so no file named for events holds folders.

### 16.9 After the pause — where every open item went (2026-11-14)

The session of 2026-11-13 was cut by an outage while eight agents
worked. The owner committed the tree as it stood at the last whole gate
(`daa6d9c4`) and asked for the pass to be finished: "Quality is the
focus", at most three agents at a time, no commit, push or deploy. This
section listed every item open at that pause. All of them are closed,
and the table says where each is written down as built. The fixes are in
the tree on top of `daa6d9c4`, COMMITTED `7803e07a`.

| Open at the pause | Closed in | Read by |
| --- | --- | --- |
| The data path — P1 a partner's note text left in the search index and in "Share database", P2 a merged folder tombstone ending a grant unsaid, P3 a removal missed for a day, P4 a tombstone keeping title and preview, P5 a move's poke outside its transaction, P6 a copy that leaves naming the partner, P7 `updateFolder`'s move unchecked | §15 "After the final reviews — the data path" | a Fable reviewer in three parts, then a closing review of the fixes and a last leg on what it found |
| The browser and the Sharing page — B1 a failed look read leaving a blank page, B2 a retry per frame, B3 the ⋮ button's pre-open ask, B4 the picker's stale search, B5 the reason slot's height and literal sizes, B6 an outcome taken by the wrong sheet, B7 the smaller four | §15 "After the final reviews — the browser and the Sharing page" | a reviewer four times (the fixes, the re-check, the last leg, a verification of what answered it) and the lead's own read of the two files rewritten last; a design reviewer twice |
| The filters (`allowlist-fix.patch`) | §15 "After the final reviews — the filters"; §16.3 is the rule as it stands | a reviewer three times, each with a sweep over every pick a person can make (16,374, then 130,312 picks) |
| The notices and D38 (`notices-fix.patch`) | §15 "After the final reviews — no alert goes off unsaid"; §16.2 D38 | a reviewer, then a second leg on its findings |
| One voice when a share ends, the read-only pins (`browser-pins-leg2.patch`) | the same browser block — `ShareLeaveVoice` | with the browser's reviews |
| The background check's rulings 3–14, B13, the kept notice (`slice-i-leg6-rulings-3-7.patch`) | `cloud-shared-freshness.md` §12: "After the review of the check", then H1–H11, R1–R9, K1–K8 | a Fable reviewer four times (the handshake; what a run arms and reads; the closing review; a second look) |
| "A Fable review of the background check and push once their rulings are in" | `cloud-shared-freshness.md` §12 "After the review of the push client" | a Fable reviewer four times (the client; a second look; the last leg; a verification of what answered it) |
| The second design review | the browser block, "After the second design review" | — |
| The harness fix (`device-harness-fix.patch`) and the device flows | "On a device", below; §15 "Found on a device" | — |

**The gate on the last code** (2026-11-14, the merge of every stream).
`dart analyze lib test tool` and the alarm fork clean; `untranslated.txt`
empty; the whole suite 18,407 passed, 17 skipped, none red — the
services 3,453, the other directories but the widgets 8,363, the widgets
3,179 and 3,233, the editor 139 and 40; the fork's own Dart suite 129.
No stream of this pass touches `firestore.rules`, the indexes or
`backend/push-relay`: the rules suite (177) and the relay's suite stand
as on the commit. A signed release build (`release build --arm64`) was
made from this tree.

**On a device** — two fleet guests, Android API 36; the share suite on
the cloud-define QA build against the local Firebase emulator suite, a
freshly started suite for every pass:

- On the fixed code the share suite ran green twice, 23 flows each: the
  19 of the commit and four new ones — a folder shared from its menu and
  read on the other phone, read-only, with "Copy to my notes"; notes
  moved in and out of it, edited and deleted, and the partner's search
  finding none of what left; every door into a partner's folder
  read-only; a folder stopped from the Sharing page, heard once. `04k`,
  the check with the app closed — the event moved by {name}, the job
  run, both tiers of the alert an hour later — is green in both.
- Four more flows, each green twice: "only mine" kept across a new
  shared category (D29); the hide bar and what it disarms; the alert
  choice per pair (D38); the pair ended with a folder shared. And the
  account deleted with a folder shared, folded into the suite's last
  flow.
- On the final build the whole suite, 27 flows, ran green twice more
  (610 s each). Right after "un-pair, pair again" a folder shared under
  the ended pair read "Share with" at once (D39), and after the partner
  deleted their account the notice read "Your partner ended sharing.
  Your notes and events stay on this device."
- `sync` 5 of 5 and `browser` 3 of 3 on the final build. And the QA
  quiet proven: a guest left with sixteen entries armed, as an aborted
  pass leaves it, was clear after one fresh launch.
- `alerts` 5 of 5, `alerts_pair` 1 of 1, `settings` 21 of 21 and
  `calendar` 35 of 35, on the plain QA build of the merge before the
  last fix legs, which touch none of those areas.
- Not walked on a device: "Share database" holding nothing of the
  partner's — pinned byte for byte by `database_manager_test`; a flow
  needs a harness verb that pulls the snapshot off the guest. And
  nothing that needs a message to arrive: a QA build receives none.

What those passes found in the app, and where each went: §15 "Found on
a device".

**Decided in the finishing pass and open for the owner** — each is built
one way and can be turned:

- D38 resets "Off" too when another pair is adopted (§16.2).
- The share sign beside a note's title in the editor's bar costs a short
  title its last letters (§15, the browser block).
- The pair's document shows {name} how many devices I have, their sync
  ids and their push addresses (`cloud-shared-freshness.md` §12, "What
  the pair's document shows the partner").
- With the app in front a change waits a minute at most to be read —
  there is no urgent bypass; one would need a field on the wire and a
  relay deploy (same record, "Receiving").
- A message's work that still owes its read is tried three times back to
  back and then ends; one plain retry kept for a maintenance window is
  the option not taken (same record, "Receiving").
- Not of this pass, found by it: Android's backup restores the alarm and
  notification plugins' own stores onto a new phone, where nothing is
  armed; and the alarm fork reloads its copy of the preferences at every
  foreground and background change (same record, "Recorded, not
  changed").
- Not of this pass, read on the way and not verified on a device:
  "Delete all data" removes every database and takes nothing off the
  platform. The next launch's sweep cancels the entries of the database
  it opens and skips those whose payload names another database — so
  alerts armed for a second database stay armed for data that no longer
  exists (`AppDatabase.deleteAllData`; the stray sweep's database filter
  in `alert_scheduler.dart`). And no sweep can cancel a notice whose
  alarm went outside the gateway; a notice ends at its alarm's instant.

**Only two real phones and the deployed relay can show** — the lists
"Only a device can show" and "Still owed" of `cloud-shared-freshness.md`
§12, after the owner's steps of its §9. The rules are live since
2026-11-14 (the indexes were already); left: the relay deployed,
`config/push` written, this build on both phones.

**Not built, by decision**: the partner never edits (E5, N3); presence
on a shared event (§13); R9 (D36); the partner's counters and currency
on a shared note (F7); the items "kept, each for a reason" of §16.5.

**Decided and needing no code** (§16.3, §16.4): a list stored by the
builds of 12–13 November is not migrated; `*partner` is the partner of
the moment; changing "Alerts for shared events" says nothing more;
`CalendarBloc` keeps its own queue; two bars for two visible closings
when a partner's note leaves before its folder.

---

## 17. The correctness review (2026-11-21)

**Status: A1–A13 FIXED 2026-11-21, uncommitted (§17.7; the share device
pass 27 of 27 on the final build, the sync pass not run); §17.3 and §17.4
open.** The owner asked for a correctness review of sharing as it stands
on `main` (`698f5292`, a clean tree), and on its list answered "fix all
13, tests first" the same day. §17.2 keeps each finding as it was read;
§17.7 says what was built for it.

### 17.1 How it ran

Seven `reviewer` agents (Opus 5.5, read-only), one per part — the give
side, the receive side, pairing and endings, the check with the app
closed, push and the relay, the Sharing page, a partner's rows in my
screens (two sittings) — and the lead (Fable 5.2) on `firestore.rules`,
the indexes and the gateway's queries across accounts. Seven readers
shared one tree, so none ran a suite (the native-assets lock); the relay's
own ran and is green (106 of 106). **Nothing below was reproduced by a
test.** "Read" means the lead read the cited lines and found no other
path; "reported" means it rests on the reviewer's reading alone.

### 17.2 Worth fixing first

- **A1 — Another account's sign-in clears the bound account's marks
  (read).** `reconcile` empties the cache when another account is signed
  in (`pairing_service.dart:259-261`); `_adopt` then compares the pair it
  found with that emptied cache (`:680`, `clearMarksOfOtherPairs:
  _cached.pairId != pair.pairId`), and `setPairingSettings` clears every
  mark that is not the new pair's (`settings_service.dart:2626-2629`,
  `FolderDao.clearSharesExcept`) — with no look at whose marks they are.
  *When:* the database is bound to A, paired, with marks; A signs out, B
  signs in and opens Sync & sharing; B has an active pair of its own. *What
  happens:* every mark of A's is cleared, stamped and queued; when A signs
  in again the queue drains under A's binding and the partner loses
  everything A shared, and A's alert choice is reset (D38). Not when B has
  no pair, nor when B is A's own partner (one pair id). *Probe:*
  `pairing_service_test.dart:1350` with one mark set under the first pair;
  it must still stand after `cara.service.load()`. *Direction:* clear only
  when the pair that stood was the signed-in account's own, or when the
  database's binding is that account's.
- **A2 — The pairing listeners re-attach without a pause on a refused
  listen (read).** `_reportStreamError` always calls `_attachListeners()`
  (`pairing_service.dart:798-803`, `:772-789`); nothing detaches at
  sign-out. *When:* paired, Sync & sharing opened once in this process,
  then Sign out — the listen on the pair is refused for nobody; or a
  pending invite past its end at any re-listen. *What happens:* listen,
  refused, listen — a round trip each, for the life of the process, each
  turn an "offline" on the page. The fake's streams never fail. *Probe:* a
  fake `watchPair` that fails and counts its calls; two at most after
  `load()`. *Direction:* no re-attach on a refusal (the next reconcile
  attaches), a back-off for the rest, detach when the signed-in account is
  not the cache's.
- **A3 — Un-sharing does not reach a row whose newest write is parked
  (read).** A re-queue raises an entry only by a later stamp
  (`sync_outbox_dao.dart:392-418`), a parked entry is not eligible
  (`sync_pusher.dart:245-249`, `:349-355`), and `_regranted` covers a push
  in flight only. *When:* a note under a shared folder was pushed, then
  edited, and that edit is parked (a refusal of the rules, a refused
  chunk, an encode fault, a pull of its own held back); the folder is
  switched off. *What happens:* the re-queue is absorbed by the parked
  entry; the earlier document goes on naming the pair, and the partner
  keeps that version's title, preview and text for as long as the park
  stands. The same for a day row under an event or a category switched
  off. *Probe:* `sync_share_push_test.dart` — share, drain, edit, have the
  fake gateway refuse the note at its new stamp, drain, un-share, drain:
  the stored document still names the pair. *Direction, a decision:* a
  write of the document's grant alone for a parked key (the rules'
  `validEnvelope` passes on the merged document), or a park that a change
  of grant lifts.
- **A4 — An act queued behind a running one is dropped when the bloc
  closes (read).** `ShareBloc.close` hands over the queued Undos alone
  (`share_bloc.dart:411-436`); `oneAtATime` never starts what had not
  started. *When:* ✕ on A, ✕ on B, back, back before A's write and reload
  end. *What happens:* the sheet has said "No longer shared" for B and
  hidden its row; B is never written and stays shared. A queued
  `ShareCategoriesSet` goes without a word. *Probe:* a fake whose first
  `setFolderShared` waits; two ✕, close, release — B is never recorded.
  *Direction:* hand every queued act over at close, as the Undos are.
- **A5 — The category tick sheet writes back ticks it read before an act
  landed (read).** `_pickCategories` takes the overview of the last build
  and lets go of `_picking` as the sheet closes
  (`sharing_page.dart:444`, `:978-1008`); `setCategoriesShared` sets
  exactly the ticked set (`share_service.dart:552-564`). *When:* untick X,
  Done, Categories again before the state arrives — X is still ticked;
  tick Y, Done: X is shared again. Without the race: a mark another device
  of mine or the shared reader changed while the sheet was open is
  overwritten by any Done that changes something. *Probe:*
  `sharing_page_test.dart` with a waiting `setCategoriesShared`.
  *Direction:* hold `_picking` until the act's outcome; send what was
  added and removed, not the whole set.
- **A6 — Undoing a note's move can choose a partner's folder (read).**
  `_firstAvailableFolderId` takes the first top-level folder
  (`move_coordinator.dart:639-643`) from a query with no owner in it
  (`folder_dao.dart:53-70`, by position, then id). *When:* a note moved
  from A to B, A deleted, Undo from Move history, the picker left without
  a pick, and a partner's folder sorting first. *What happens:*
  `NoteDao.moveNote` refuses (`note_dao.dart:1467-1472`) — unhandled on
  the single path (`:610`: no bar, the entry not marked), "could not be
  moved" on the batch path (`:463`) though a folder of mine exists.
  *Direction:* leave `fromPartner` out of the fallback; guard `:610`.
- **A7 — A partner's day row or note stored without its parent stays when
  my own parent lands under that id (reported).** `evict` returns when no
  shared row is held under the keys, so nothing under them goes
  (`shared_row_dao.dart:276-280`); the reader refuses a day row only when
  some row is held under its event's id
  (`calendar_event_occurrences_binding.dart:116-137`, the skips alike;
  notes: `notes_binding.dart:537-550`). *Needs* ids that meet — both
  people restored one backup — and the partner's parent absent when the
  child lands (skipped, removed first, or waiting). *What happens:* the
  partner's skipped day or day text shows on my own event; my edit of
  that day passes `ensureOwn`, is stamped and queued, and the fence turns
  its UPDATE into nothing — said as saved, and lost. A partner's note
  inside my own folder makes `exportFolder` refuse the folder whole.
  *Probe:* `shared_row_dao_test.dart` — an occurrence of the partner's
  with no event, `evict('calendar_events', ['E'])`, my own E: the
  occurrence is still there and `setDescription` stores nothing.
  *Direction:* cascade by key in `evict` whatever was held, or refuse a
  shared child whose parent is absent.
- **A8 — A run that finds a silent holder takes the name without asking
  it to give way (read).** `SharedRefreshRunPort.open` removes the name
  after three unanswered pings (`shared_refresh_ports.dart:386-401`); the
  launch sends the yield with its verdict (`:183`, `:198`), a run does
  not. *When:* one run's isolate busy past six seconds as another starts.
  *What happens:* the first goes on unaware — two alert passes over one
  registry and one native store, two shared reads over one cursor.
  *Probe:* `shared_refresh_ports_test.dart` — a raw port under the name
  that records and never answers must have been sent `giveWayToRun`.
  Whether an isolate stalls that long is a device's to show.
- **A9 — The folders sheet keeps hiding a folder shared again (read).**
  `_leaving` loses an id only at a successful Undo or a failed ✕
  (`share_folders_sheets.dart:170`, `:270-286`, `:339`; the events sheet
  alike, `share_events_sheets.dart:142`, `:226-234`, `:264`). *When:* ✕ on
  A, then Share a folder → A, in one sheet. *What happens:* the bar says
  it is shared, the list leaves it out until the sheet is opened again.
- **A10 — The relay reads the pair's whole document (read).**
  `readPair` (`backend/push-relay/src/relay.js:336-338`) sends no
  `mask.fieldPaths`: the names, the photo addresses, the permissions and
  the invite code come back beside the four fields it uses, so "reads no
  user data" does not hold to the letter. *Direction:* mask to `members`,
  `status`, `endedAt`, `push`; then a deploy.
- **A11 — My event's linked-note picker offers the partner's notes
  (read in part).** `loadNotePickerPage` lists All notes, the partner's
  flagged, and its search is unfiltered
  (`note_storage_service.dart:463-497`); `_pickNote` takes any pick
  (`event_editor_sheet.dart:1757-1766`). *What happens:* the ledger folds
  every linked note (`note_money_ledger_service.dart:106-141`) and the
  report counts its net for my event (`calendar_report_service.dart:
  479-486`) — a partner's lines in my report, day bars and day summary;
  the link reads "Not found" once the share ends. Opening it is safe
  (flagged, read-only). *Direction:* leave `fromPartner` out of the
  picker, or out of the fold.
- **A12 — An account's deletion removes the pair before its "ended" poke
  can be served (read).** `_removePairs` ends and at once deletes
  (`account_closer.dart:139-142`); the flush comes after the walk
  (`:112`), and the relay answers a missing pair 403. The partner's closed
  app is not woken; it learns at its next check. *Direction:* flush
  between the end and the delete.
- **A13 — An owed poke can still go to an ended pair (reported).** With
  no pair stored every owed pair is poked (`sync_pusher.dart:65-71`,
  `:88-97`) on the word that the relay refuses a pair the caller is not
  in — an ended pair still holds the caller and is served for a day
  (`relay.js:386-391`). The reader's own clearing of marks owes such
  pokes. The former partner's devices are woken; timing only.

### 17.3 Narrower

- **B1** Cancelling an invite as it is redeemed
  (`pairing_service.dart:318-325`): the code is deleted and cleared with
  no look at the server, so the pair just made is unknown here until the
  next reconcile, and a pairing made meanwhile is ended by earliest-wins.
- **B2** `redeem` and `generateInvite` trust the cache (`:289-293`,
  `:330-334`): an account paired on its other phone makes a second pair
  here, which the next reconcile ends as ended by me.
- **B3** Unpair on a pair already ended or gone (`:431-440`, `:852`)
  answers "Not allowed" or "Pairing failed" and the page stays "Paired".
- **B4** My own Unpair asks for no shared read (`:431-440`): the
  partner's rows, their alerts and my marks stand until the next run.
- **B5** A tombstone seen while the server cannot be asked clears the
  pair with no ended notice (`:878-882` → `:621-646`).
- **B6** A share act reads the pair before its transaction
  (`share_service.dart:539-596`) and Undo reads it afresh (`:780-840`;
  `ShareChange` carries no pair): a pair replaced within the Undo bar's
  life shares the folder with the new partner.
- **B7** A row's place is last-writer-wins: a device behind that edits a
  note moved out of a shared folder puts it back, and shares it again.
  `mergeMark` guards the mark, nothing guards the place. By design, and
  until now unrecorded — a known limit.
- **B8** Notice timers (`share_notice_listener.dart:348-376`,
  `:488-528`, `:584-602`, `:679-686`): a turn already waiting does not
  check `_barUp`, and `_holdBarTime` re-arms without cancelling.
- **B9** `_foreign ??=` (`sharing_page.dart:311-314`) is taken from the
  first loaded state and kept for the visit.
- **B10** A run that answered the launch's ping and outlasted its five
  seconds writes behind the app and owes no catch-up
  (`shared_refresh_ports.dart:196`, `shared_refresh_app.dart:87-90`);
  freshness K4 rules it so, on a premise that fails past five seconds.
- **B11** A check yielded before its `open()` can leave no check standing
  until the app's next pass (`shared_refresh.dart:315-327`, `:394`).
- **B12** An own row parked under a key a shared row holds evicts and
  restores that row at every start and "Sync now"
  (`sync_puller.dart:255-276`, `:996-1012`).
- **B13** "Tomorrow" on 31 December (`share_events_sheets.dart:418`):
  `tomorrow` is local, `day` and `today` UTC, so they never compare equal
  and the year rule writes a date. The suite builds both local.

### 17.4 Small: accuracy, tests, cost

- **The pairing fake accepts what the rules refuse** —
  `endPair` on a missing or an ended pair, `removePushDevices` on a
  missing one (`test/services/pairing_support.dart:283-297`, `:365-373`).
  It hides how the client answers a pair the partner's account deletion
  removed (`push_registry.dart:163-176`, `:328-343`;
  `account_closer.dart:150-158`). One rules-suite case, an update of a
  missing `pairs/x`, says which code comes back.
- Pairing: `pairedInMemory` ignores the account (`:210-213`); both
  inviting at once fork until each reconciles; a claimed invite learned
  of after its end is never deleted; a phone ten minutes slow cannot make
  a code.
- Give: `softDeleteFolderWithDescendants` reads the subtree before its
  transaction (`folder_dao.dart:958-970`); `softDeleteFolder` has no
  caller and no re-queue (`:712-731`); `afterMarksClearedElsewhere` asks
  for a run only when ready (`share_service.dart:887-903`);
  `sharedPairOfNotes` takes `MAX` across pairs (`folder_dao.dart:
  1291-1298`), which can name a dead pair — the private side.
- The page: two overview reloads per act, not one (`share_bloc.dart:
  223-227`, `:306`); "Could not check" is not tried again within a minute
  of the last success (`share_service.dart:738-747`); "Sending…" under a
  failure that is not offline; a failed ✕ brings back rows of ✕s still
  queued; no guard against a second Sharing page from two taps
  (`sync_settings_page.dart:2285-2302`); the events sheet builds every
  row and walks up to 366 days for each on every state.
- Push: every Android launch reads the preferences store once for an
  owed address, a never-paired install included (`injection.dart:625`);
  `leave()` returns on "no address held" though `push_written` names a
  pair (`push_registry.dart:133`); the later-pair branch never clears
  `push_written` on a refusal (`:187-196`); one WorkManager name for every
  pair beside a waiting note per pair; the relay's own 503 carries no
  `Retry-After`.
- The check: a run measures the schema by the fresh active name and
  opens by its copy's (`shared_refresh_app.dart:582-587`, `:710-714`);
  `runsCanExist` and `checkPlanned` read a key another isolate writes off
  the copy; a work's wall time adds up to about 77 seconds, not 60;
  `detached()` gives the name up while a write may still run.
- Receive: the count compare hides removals when one id is shared from
  two spaces (`sync_shared_reader.dart:463`), until the daily read; kept
  notices outlive the pair in the live database; `emptyTombstones` binds
  every id in one statement; `placeFolders` counts a tombstoned parent as
  arrived (`shared_row_dao.dart:866-873`).
- A partner's rows: a refused calendar write is silent by design
  (`calendar_bloc.dart:1198-1201`, `:1260-1262`) — every gate holds today;
  a saved list that names only a partner's category reports every
  category while it is held and nothing once it left
  (`category_allowlist.dart:293-303`); a partner's event evicted by my
  own pull may leave no notice.

### 17.5 Read and found sound

`firestore.rules`, whole, against the gateway's queries and the six
indexes: a pair's id cannot come round again for the same two people by
any order of end, delete, invite and redeem; a query that does not pin
pair and owner is refused; a chunk is one `get` behind the space's pair;
the access calls stay under the limits; the rules suite pins each of
these. The relay's token check, membership, targets, paths and rate
limit. The fences against every replacing insert and import, and the
migrations after them. `_stripShared` against §16.3. The three mark
writers, each one transaction; `mergeMark`; `_regranted`; `_resayShares`;
the space's settle rule. The read-only doors of the browser, the editor
and the calendar, down to their service and DAO gates. Presence at no
door; Skip and "remove after it rings" at none; the move, the removal and
the leave notice of an alert on a partner's event. Outcomes carry a stamp
of their own, so an equal state swallows none. A run never migrates,
creates a database or a device id.

### 17.6 Considered, not findings

- Under "Category alerts too" my built-in category's alerts ring on a
  partner's event shared alone in that built-in: the event is drawn under
  that category here, so the choice does what it says.
- The `fid` target of the FCM message rests on decision m's reading of
  Google's reference (2026-11-13); only the two phones can show it.

### 17.7 The fix pass (2026-11-21)

The owner: "fix all 13, tests first". Three `implementer` agents (Opus
5.5), each in a worktree of its own on files no other touched — pairing
(A1, A2, A12), the screens (A4, A5, A6, A9, A11), the data path (A3, A7,
A8, A13) — and the lead on the relay (A10). Every item's test was seen
to fail for the stated reason before its fix, except where noted. No
schema, no migration, no change of the wire or of `firestore.rules`; one
new `sync_metadata` key. Gate on the merged tree: `dart analyze lib
test` clean; the whole suite 18,444 passed, 17 skipped, none failed (six
chunks); the rules suite 178 of 178 on the local emulator; the relay's
106 of 106. No device pass yet — it rides the guide's (§11 of
`guide-hub-roadmap.md`).

- **A1.** `SettingsService.setPairingSettings` clears the marks of other
  pairs only when they are the adopting account's to take away: the
  database has no sync binding, or its binding is that account's
  (`_boundToAccountOrNone`, read inside the write's transaction and only
  once a mark is known to exist). **D39 is amended so:** a database bound
  to another account's space keeps its marks. D38 — the alert choice
  starts over when the stored pair is another one — is as it was.
- **A2.** A listen that ended in an error is asked again after a wait,
  `PairingLimits.relistenFirst` (two seconds) doubling to
  `relistenCeiling` (five minutes) and starting over at the first
  snapshot (`lib/constants/pairing_limits.dart`). With nobody signed in,
  or another account than the stored pairing's, nothing listens again:
  the next `load` attaches. One pending timer, cancelled by
  `_detachListeners`, so by a reset and a dispose too.
- **A3.** The grant alone is taken off a stored document whose row
  cannot be pushed. `SyncGateway.unshareRows` — in Firestore a
  read-then-update transaction that deletes `sharedPair` and `wire` and
  restamps `pushedAt` and `pushedBy` on each document that names a pair,
  creating nothing. `_Pusher._unshareHeld` runs after a drain's pushes:
  for a key of a shareable table that a push park or a pull park holds
  back, whose grant as derived now is private, once per park
  (`share_cleared.<table>.<rowKey>` holds the stamp held back, and goes
  when the park lifts and at an unbind). Never toward shared. A drain
  with no such park reads nothing; a database never in a pair
  (`SyncDao.everPaired`) sends nothing; a failure is tried again at a
  later drain and never fails the run. The rules already allow it — the
  merged document passes `validEnvelope` — and the rules suite has the
  case, with the partner's same update refused.
- **A4.** `ShareBloc` keeps every act added and not yet started, with
  the database generation it was asked under; at close all of them are
  written in order after the running act, the way a queued Undo was. One
  asked under another database is not written; a failure is said once by
  the event's own `failedPastBloc`.
- **A5.** Done sends what the person changed — the categories newly
  ticked and those unticked against what the sheet opened with — and
  `ShareService.changeCategoriesShared` applies exactly those to the
  marks as they stand, in one transaction. The Categories row does not
  open again until that act has answered.
- **A6.** The fallback folder of a move's Undo is never a partner's; the
  single-note Undo answers a refused move with the "could not move" bar
  and stays undoable. Beyond the finding: that path now counts a deleted
  source folder as gone, as the batch path did — before, the picker never
  opened for one.
- **A7.** `SharedRowDao.evict` removes the partner's rows that hang
  under the evicted keys whatever stood under the keys themselves — the
  day rows of an event id, the notes of a folder id — past the "no shared
  owner" exit, so a database that reads from nobody pays what it paid. A
  partner's folder under such a key is lifted to the top by
  `placeFolders`, as before.
- **A8.** A run sends `giveWayToRun` to a silent holder before it takes
  the name.
- **A9.** In both give sheets each ✕ is matched to its own outcome: a
  failed one brings back its own row only, and a row hidden by its ✕ is
  listed again once it is shared again.
- **A10.** `readPair` asks Firestore for `members`, `status`, `endedAt`
  and `push` alone. **It takes effect at the owner's next deploy of the
  relay.**
- **A11.** The linked-note picker of an event lists my own notes only,
  on the list and on the search (`ownOnly`; the counters page's picker
  is as it was). The ledger folds a partner's note as before but says
  whose it is, and the calendar report leaves such a note out. *The
  first build left a partner's note out of the ledger everywhere, which
  also took the money off the partner's own events in my day bars; it
  was sent back and narrowed to the report, which is all the rule asks.*
- **A12.** `PairedAccountCloser.afterPairEnded`, awaited between a
  pair's end and its removal and bounded by `kPushEndedPokeBound` (five
  seconds), sends what that end asked the relay for;
  `HttpPushRelay.flush` now waits for a poke already on its way too.
- **A13.** With no pairing stored, an owed pair is poked when the shared
  read holds it, dropped when the read holds another or found the pair
  ended, and poked as owed when this database's reader never met a
  partner (a second database on the phone).

Each stream then went to a `reviewer` of its own, in a fresh context
(read-only; the gate above had already run). Their verdicts: A5, A6, A7,
A8 and A9 closed; the others closed for the trigger the finding names,
each with something the fix left or opened — which a second leg, tests
first again, answers:

- **A1.** The marks now survive another account's sign-in — and then show
  on that account's Sharing page as its own, where "Stop sharing
  everything" clears them (`ShareService.overview` asks only whether a
  mark stands; `stopAll` asks nothing of the pairing). And the alert
  choice is still reset, twice: at the other account's adoption and at
  the owner's return, because the adoption overwrote the last-pair
  memory. *Second leg:* on a database bound to another account an
  adoption changes neither marks nor alert choice nor last pair, and
  there the Sharing page lists nothing of mine and `stopAll` writes
  nothing.
- **A2.** An invite past its end was still listened to every five
  minutes; and after a sign-out and sign-in of the same account nothing
  attached again until Sync & sharing was opened (the old loop had hidden
  that). *Second leg:* an expired code is dropped, never listened to; the
  service follows the signed-in user and attaches and detaches by it.
- **A3.** The "cleared" record knew the held stamp but not the decision
  it answered: with two devices of one owner — clear, re-share from the
  other, un-share here again at the same held stamp — the second
  clearing was skipped. And a document pushed after this device's
  decision (another device's later re-share, or the newer version a pull
  park holds back) could lose a grant it rightly carried, with nothing to
  put it back. *Second leg:* a document is cleared only when it was
  pushed before the write that decides the row is private here, and the
  record keeps that decision beside the stamp.
- **A4.** The hand-over at close opened an order race: an Undo tapped
  after the page had gone wrote at once, and the handed-over un-share it
  undid landed after it; a page reopened in that moment likewise. A
  handed-over act skipped for a database switch said nothing. *Second
  leg:* one order for every write made past a bloc or by a newer one;
  the skipped act is said.
- **A11.** An old link from an event of mine to a partner's note still
  counted in the day bars, the day summary and the month's net. *Second
  leg:* an entry counts for an event only when the note is mine or the
  event is the partner's too — one rule for the four readers.
- **A12.** The hook's bound (five seconds) was shorter than one poke's
  own deadline (ten), and a held poke went only after the entry's
  removal and the address's give-up. *Second leg:* the poke first, the
  bound derived from the poke's deadline.
- **A13.** In a run that only drains, a poke owed to a pair the reader
  had not begun yet was deleted unsent. *Second leg:* such an entry is
  kept until it can be judged.

Kept as known limits, no code: after "Stop syncing" a database is bound
to nobody, so another account's adoption there still clears its marks —
the rule of an unbound database ("simply this device's rows"); should the
first account bind that same database again, the clearing goes up with
it. And a second database whose reader still holds an ended pair pokes
that pair, not the new one, until its next shared read.

**The second leg as built (2026-11-21), each point's test seen to fail
first.**

- **A1.** `setPairingSettings` reads the binding once in its transaction;
  on a database bound to another account it stores the pairing rows and
  nothing else — no mark cleared, no alert choice started over, the
  last-pair memory left as it was — and answers what it did
  (`marksCleared`, `alertsReset`), so the alert pass runs only after a
  reset that was stored. The owner's return finds its choice, its marks
  and nothing queued. `SettingsService.boundToAnotherAccount` is the one
  place that answers it for the pairing side;
  `ShareSyncSource.boundToAnotherAccount` answers it for the screens:
  there `ShareService.overview` lists nothing and `stopAll` writes
  nothing (the per-row acts already refused, as `ShareNotSyncing`).
- **A2.** `PairingService` follows the signed-in user: signed out or
  another account, it detaches; the cache's own account back, it
  attaches what the cache holds. An invite past its end is dropped by
  the wait itself and never listened to; a `load` starts the wait over.
  `reset` and `dispose` cancel the follow and a pending wait.
- **A3.** A document is cleared only when it was pushed before the write
  that decides the row is private here — `pushedBefore(pushedAt,
  decidedAt)`, the same comparison `_resayShares` now calls, by this
  device's clock as that one is — and the record
  `share_cleared.<table>.<key>` holds the held stamp *and* the deciding
  stamp: due again whenever either differs. The gateway reads fifty
  documents at a time. A gap test found one more real case: a day row
  under a category that was un-shared was never cleared, because
  `CalendarEventDao.stampsOf` joined only a category still marked; it now
  counts the category's `shared_stamp` for any event of mine without a
  mark of its own. *Limit, recorded:* a phone whose clock runs behind
  leaves a document pushed within that lag before the un-share uncleared
  until its park lifts.
- **A4.** One order for every share write made past a bloc or by a newer
  one: `ShareBloc.writePastBloc`, a process-wide tail the hand-over at
  close, the Undo tapped after its page and every act of a later bloc go
  through — not bounded, since a bound would let a later write overtake.
  An act added while the bloc is closing is written past it; one skipped
  for a database switch is said. `ShareLoaded.read` numbers each
  overview read, for the sheets (A9).
- **A6.** A title clash at a single note's Undo says the batch's words;
  the folder Undo counts a deleted parent as gone and says a failed move.
- **A9.** A row hidden by its ✕ stays hidden only against the read that
  carried that ✕; a newer read that lists it shows it.
- **A11.** `NoteMoneyLedgerService.ledgerForEvent` is the one rule — an
  entry counts for an event when the note is mine or the event is the
  partner's too — read by the day bars, the day summary, the month's net
  and the report.
- **A12.** The end's poke is flushed before the entry leaves the pair and
  before the address is given up; the hook's bound is one poke's own
  deadline.
- **A13.** With no pairing stored and a reader that holds no pair after
  having had a partner, an owed poke is kept — neither sent nor deleted —
  until a pairing is stored or the reader holds a pair; one entry per
  pair, removed by the next pair's first drain that can judge it or by
  an unbind.

**Gate on the whole, in the main tree (2026-11-21):** `dart analyze lib
test` clean; the whole suite 18,481 passed, 17 skipped; the rules suite
178 of 178 (run on the first leg; the second changed neither the rules
nor their case); the relay's 106 of 106. One case of
`optimized_folder_content_page_test.dart` ("a row's long-press sheet
leads with the strip…", colour labels) went red once in its chunk while
another worktree's build loaded the machine and is green alone, 131 of
131 — a load flake outside the diff. Not delivered: a widget test of the
A4 scenario through the folders sheet — under `testWidgets` a bloc
closed while its act is held never finishes closing; the bloc suite
covers it. **No device pass yet.**

**The closing reviews of the second leg (two `reviewer`s, fresh
contexts) — and two of the lead's own second-leg decisions withdrawn.**

- **A3 did not hold.** Clearing only a document "pushed before the write
  that decides the row private" needs that write's stamp, and
  `shareStamps` does not have it for three kinds of row: a note moved
  out of a shared folder (the move is a write of the note; only the
  folder chain was read), an event or day row under a *deleted* shared
  category (a tombstone moves `hlc_timestamp`, not `shared_stamp`), and
  a category row itself (the binding gives none). All three kept their
  grant, and the record then said "answered". The rule also left a
  device that is behind free to push the grant back for good. *Third
  leg — back to the foundations' own rule, private always:* a held row
  that is private here has its document's grant cleared, with no
  comparison; the record is "cleared at this park" and is dropped when
  the park lifts, when the row is shared again at a drain, and whenever
  a pulled document of that key names a pair, merged or parked.
  `stampsOf` goes back to what it was. *What this costs, accepted:* a
  parked row's document can stay private where another device of the
  owner shared its root later, until the park lifts — the side the
  foundations say to err on (§3 there). Also from the first leg: a day
  row stored at a local midnight by an older build was asked for under
  its outbox key, not the document's — mapped now.
- **A4's process-wide tail was fragile.** A lone running act (nothing
  queued behind it) stood outside it, so an Undo past the bloc could
  still land first; an act delayed by the tail wrote with no check for a
  database switch; the calendar's, the Categories page's and the folder
  page's own share writes bypassed it; a running act that failed after
  its bloc closed said nothing; and one write that never completed froze
  every later act of every later bloc. *Third leg:* the order lives in
  `ShareService` — its share writes run in the order they are asked,
  per instance, each carrying the database generation it was asked
  under — and `ShareBloc` starts an act's write when the act is added,
  so nothing waits to be handed over and every door is ordered with no
  change of its own. The tail, its counter and its zone marker go.
- **A2.** The wait's drop of an expired invite wrote a copy of the cache
  taken when the timer fired, and could undo a fresh code or an adopted
  pair whose write was in flight. *Third leg:* one queue for every write
  of the pairing state, and a write that depends on what the cache held
  re-reads it in its turn. The account's return attached but did not
  look, so a pair removed meanwhile stayed "paired": it now reconciles
  in the background.
- **A12.** An Unpair followed by a sign-out on a slow relay could leave
  this phone's entry in the ended pair's document (the end's flush, ten
  seconds, outlasted the leave's five). *Third leg:* the end's own wait
  is bounded under the leave's.
- **A11, A6.** The "money only" grid filter still read the ledger by
  note; leaving the folder Undo's picker without a pick moved the folder
  to the top level. *Third leg:* the filter reads `ledgerForEvent`; no
  pick cancels.
- **Recorded, no code:** on a database bound to another account, what
  "Category alerts too" armed for the owner's partner goes on ringing
  under the other account (nothing is reset there now, by A1's rule); a
  newer overview read that fails in the event cache can list an event
  just un-shared, and its row then shows again in the sheet (A9, rare).

**The third leg as built (2026-11-21, three fresh `implementer`s; each
changed behaviour's test seen to fail first).**

- **A3.** `_unshareHeld` clears every held row that is private here;
  `SyncGateway.unshareRows` takes keys again, fifty reads at a time. The
  record `share_cleared.<table>.<key>` is the held stamp and is dropped
  at the park's lift and at an unbind, at a drain that finds the row
  shared, and by `_Puller._forgetCleared` when a pulled document of that
  key — merged or parked — names a pair. A held key is sent as the
  document's id (`SyncTableBinding.documentKeyOf`; a day row's is its
  envelope key). `stampsOf` is HEAD's again. The second leg's line about
  a slow clock no longer applies: the clearing reads no clock.
- **A4.** `ShareService._inTurn`: the seven mark writers run in the
  order asked, per instance; a write whose turn comes after a database
  switch throws `ShareDatabaseSwitched` and writes nothing. `ShareBloc`
  starts an act's write in `add` and its handler awaits it; an act whose
  write fails once its bloc is closing says so through `failedPastBloc`,
  once. The tail, its counter, its zone marker, the hand-over at close
  and `ShareUndoRequested.pastBloc` are gone; the calendar's, the
  Categories page's and the folder page's own share writes are ordered
  with no change of theirs.
- **A2.** `PairingService._inTurn`: one queue for every write of the
  pairing state; `_rewrite` builds its value from the cache when its
  turn comes and writes nothing when what it meant to change is gone
  (the expired-invite drop, cancel, the ended notice's dismissal, a
  vanished pair, the partner's name, `_adopt` whole). The account's
  return reconciles in the background, one at a time, and attaches
  after it.
- **A12.** `kPushEndedPokeWait`, half the leave's deadline, bounds the
  end's own wait for its poke.
- **A1.** `setPairingSettings` reads the binding only when a mark
  exists, an alert reset is asked or the last pair would change; the
  same pair adopted again on a database with no mark costs its rows and
  one read, pinned.
- **A11, A6.** The grid's money filter reads `ledgerForEvent`; a folder
  Undo left without a pick is cancelled and stays undoable.

**Gate on the whole after the third leg, in the main tree:** `dart
analyze lib test` clean; the whole suite **18,513 passed, 17 skipped,
none failed** (six chunks; the colour-label case that flaked once under
load in the second run is green in its chunk). The rules suite stands at
178 of 178 from the first leg — neither later leg changed the rules, the
write sent, or its case; the relay's 106 of 106. **No device pass yet.**

**The device pass (2026-11-21, later the same day, on the tree that also
holds the sync guide — whole suite there 19,038 passed, 17 skipped, none
failed).** `qa pass share` on two guests against the local Firebase
emulators with the cloud build: **27 of 27 green**, no flaky — `00_pair`,
`04_n`–`04_q`, `04g`–`04m`, `05a`, `06_delete_account` among them — and
`qa pass settings` 21 of 21. `qa pass sync` did not run (it needs a
freshly started emulator suite; the stop of the running one was refused
by the session's permissions) and is the owner's to run.

**Seen on the way and left, for a later pass:** `unpair()` writes a
fixed value and does not look again in its turn; the Categories page
caches its share service across a database switch; a day row stored at
a local midnight gets a second row at the UTC midnight when the device
pulls its own push back.

**For the owner:** the relay's mask (A10) needs a deploy; the device
checks of §17.5's last line still stand. **Found on the way, not
fixed:** the day list writes an event's time in 24-hour form while its
read sheet follows the locale (`EventSummaryProvider.formatRange`
against `formatRangeOfContext`).
