# Share pass

Reference, not rules. Read only the part the task needs.

## The share pass (2026-11-12)

One command is a device pass of sharing between two accounts on two fleet
guests, against the local Firebase emulator suite — no real account, no
real project. It is the device proof of the sharing foundations
(`docs/cloud-sharing-foundations.md` F4), the multi-user roadmap's R10,
and of the share surfaces' slice B, "a category can be shared"
(`docs/cloud-share-surfaces-roadmap.md` §7.6), with slice A's read sheet,
and of the surfaces that give, receive and stop (04g–04i, no seam).

```bash
tool\firebase\emulators.cmd                                   # a host shell of its own, left running: Auth 9099, Firestore 8080
./tool/qa/qa fleet boot 1 && ./tool/qa/qa fleet boot 2        # anta_qa_1 (emulator-5556) and anta_qa_2 (emulator-5558), one at a time
./tool/qa/qa build --define ANTA_QA_CLOUD=true --define ANTA_QA_FIREBASE_EMULATOR=10.0.2.2 --define ANTA_QA_ACCOUNT=qa1:qa1@example.com
./tool/qa/qa fleet install                                    # the same APK on both
./tool/qa/qa pass share -d emulator-5556                      # 27 flows on one seed: ≈ 11 min
./tool/qa/qa fleet stop anta_qa_1 && ./tool/qa/qa fleet stop anta_qa_2
```

Stop the emulator suite afterwards. **Every pass needs a freshly started
suite**: it leaves both accounts' spaces in it, and a second pass against
the same suite meets the space picker at its first bind. Between two
passes stop the suite and start it again — never reset it by hand: three
passes on 2026-11-12 ran on a hand-reset suite, and their reds proved
nothing either way. Started from a session's background shell, stopping
that shell freed ports 8080 and 9099 within seconds; check them
(`netstat -ano`) before the next start. Both guests keep
the cloud-define build until the next `qa fleet install --build`, which
the other suites need (they expect cloud off).

Always name the pass's device (`-d emulator-5556`): the flows drive the
second guest through steps that lead with `-d emulator-5558`, and a pass
that named no device would open a second connection to its own guest for
a step that names it.

| Flow | Proves |
| --- | --- |
| `_prelude` | the partner's guest relaunched fresh; each guest signed in as its own account (the partner through `set account=qa2:qa2@example.com` before its sign-in tap), bound to a space of its own, "Up to date" |
| `00_pair` | the owner makes a code (`pairing-generate`, read off `pairing-code`), the partner types it and taps Connect; both Pairing rows read paired (`sharing-paired`) — the redemption is one write, the owner adopts through its invite listener, and neither sheet takes the page under it along |
| `01_share_event` | `share event "Lifting session"` on the owner; after a sync on each side the partner's calendar lists it under Upcoming and not the event that was not shared; its category is one the partner does not have |
| `02_share_folder` | `share folder "Training"`; the partner's browser shows it at the top level, the folder inside it and that folder's two notes, and none of the owner's other folders |
| `03_follows` | a folder the owner makes inside the shared one afterwards reaches the partner at the next sync, with no second act of sharing |
| `04_made_private` | both made private (`--off`): after a sync on each side the folder is gone from the partner's browser and the event from its calendar, on the open pages, without a relaunch |
| `04_n_folder_from_menu` | no seam: the owner shares Training from its page's ⋮ (`folder-menu-share`; "Sharing Training with …", the entry then "Shared with …"); after a sync each the partner's root lists it under `browser-section-partner`, its page shows `browser-partner-line` ("Read only") and a tap on `create-note` or `create-folder` opens nothing; Session 1 opens read-only (`shared-note-line`, no `editor-toolbar` after a tap on the body, its task list unchanged); "Copy to my notes" (`editor-more`, `shared-note-copy`) into the partner's own "My copies" opens an editable copy ("Later changes by …") that keeps "Partner kept this" |
| `04_o_notes_follow` | January moved from Money into the shared Training (row sheet → picker search) reaches the partner; the owner's edit ("Paid in full") is what the partner reads; moved back to Money it leaves, and Session 2, deleted (`sheet-confirm`), leaves; the partner's search answers "No results found" for "coffee", "Deadlift" and "Paid in full", each after a query that finds Session 1 |
| `04_p_read_only_doors` | the partner reaches Training from the Sharing page's Folders row (`sharing-theirs-folders` → `shared-folder-open-*`), Week 1 from the ⋮ folder entry of the note a search opened, and Training again from the folder page's breadcrumb: each page shows `browser-partner-line` and a tap on either create button opens nothing |
| `04_q_folder_stopped` | the partner stands in Session 1 (the editor over Week 1) with Sync & sharing opened over it when the owner stops Training from its Folders sheet (`sharing-mine-folders`, `share-folder-unshare-*`: "No longer shared: Training"); after a sync each the partner's `sharing-paired` reads "Nothing is shared yet" and no bar has been said; Back lets the covered editor leave (it keeps its leave until it is in front again): both pages close onto the root — no `browser-section-partner`, no Training, "My copies" kept — and one bar says "… no longer shares this note", never "… this folder" with it, nothing after it leaves. Training ends private, as 04a on expects |
| `04a_share_category` | the owner makes "Mobility drills" in Strength in the editor, then `share category "Strength"`: the partner's day panel lists it, each row read "From qa1@example.com" first; the Upcoming card of the category (`agenda-card-days-category-qa-category-strength`) opens a day list with both events under "Strength"; the partner's editor's picker never offers it (`--absent id:category-pick-qa-category-strength`); the owner adds "Core circuit" to Strength and moves "Mobility drills" to Cardio — after one sync each side the first arrived and the second left, with no second act |
| `04b_category_renamed` | the owner renames Strength to "Power" in the category editor; the partner's Upcoming card reads "Power", and the day list it opens names "Power", not "Strength", over the two events still in it |
| `04c_read_sheet` | a tap on the partner's "Core circuit" opens the read sheet (`shared-event-sheet`: "From …", the category "Power", Add alert, Copy) and neither the editor nor the detail sheet's Edit; Copy to my calendar closes it and opens the copy in the editor under the "Later changes by …" snackbar, which the flow closes unchanged (`event-close`) |
| `04d_category_unshared` | `share category "Power" --off`: every partner row leaves the day panel and the Upcoming list; the copy stays, no longer the partner's |
| `04e_shared_builtin` | the owner makes "Treadmill run" in its default Gym and shares Gym: the partner's read sheet names the partner's own Gym; Gym private again and the event leaves |
| `04f_category_deleted` | Power shared again and seen; the owner deletes it from the Categories page, moving its two events to Cardio (`category-delete-target`, `category-pick-cardio`): they leave the partner's calendar |
| `04g_share_from_surfaces` | no seam: the owner makes Stretching shared from its editor's switch (`category-editor-share`), shares Gym from its row's ⋮ (`category-menu-gym`, `category-menu-share`), makes "Hip openers" in Stretching (its `event-share` reads "On for everything in Stretching", disabled) and shares "Lifting session" from its editor's switch; the Sharing page reads "Gym, Stretching" and "1 event"; the tick sheet (`share-categories-sheet`) takes Gym back ("No longer shared: Gym"); the Single events sheet's ✕ (`share-event-unshare-qa-event-weekly-lift`) stops the event and Undo (`snackbar-undo`) brings it back. The partner, after its sync: "… shares Stretching with you", whose View (`share-notice-view`) opens the Sharing page — Stretching and "1 event" under what it is shared — and its day panel draws "Hip openers" as "From qa1@example.com" |
| `04h_receiver_chooses` | the partner switches Stretching off in "Categories from …" (`shared-categories-sheet`): "Hip openers" leaves its day panel with no sync, and comes back when switched on; under "Category alerts too" (`sharing-alerts-category`) the category's sheet (`shared-category-sheet`) takes an alert (`shared-category-add-alert` → `shared-category-alert-0`); the Categories page lists Stretching under `category-section-partner-header` with "Alerts on"; the calendar filter's picker lists it after `category-pick-create` under "From …"; the look row's Avatar and Outlined each shot on the day panel; ends on "Only alerts I add" and Outlined |
| `04ha_only_mine_new_category` | D29: the partner filters its Upcoming list to its own categories as a group (`agenda-filter-categories`; every row of its own ticked, Stretching under "From …" not: "Gym, Cardio +7 more"); the owner makes Recovery shared from its editor (`category-editor-share`) with "Foam rolling" in it; after a sync each the event is on the partner's phone, yet the filtered list has no Recovery card (the Cardio card stays) and the summary reads as before, never Recovery; Select all ("All") brings the card |
| `04hb_hide_bar` | D30: Recovery hidden in "Categories from …" with no alert of the partner's on it says no bar; the partner adds an alert to "Foam rolling" from its read sheet (`armed --expect some`); hidden again, the bar says "Recovery is hidden. Your alerts on it are off until you show it again." and `armed --expect none`; shown again, armed again. The owner makes Recovery private (`share category … --off`): "… no longer shares Foam rolling. Your alert is off.", nothing armed, the filter back to "All" |
| `04i_stop_everything` | the partner adds "10 min before" to "Lifting session" from its read sheet (`shared-event-add-alert`); the owner's "Stop sharing everything" (`sharing-stop-all`, then `sheet-confirm`) leaves both "You share" entries "None"; after a sync each side the partner reads "… no longer shares Lifting session. Your alert is off.", its "shares with you" entries read "None", and its day panel and grid hold nothing of the owner's |
| `04j_fresh_b1_no_work` | freshness B1 (`docs/cloud-shared-freshness.md` §10): with nothing shared the partner holds no scheduled work and nothing armed (`work --expect none`, `armed --expect none`) — the work 04i's alert scheduled was cancelled when the event left |
| `04k_fresh_b4_b5_closed_app` | freshness B11, B4, B5, both tiers: the event shared again, the partner adds an alarm (30 min before) beside 04i's reminder; app open but sent home, the work is run and the check ends `forwarded`; the partner's process is ended (`kill-app`), the owner moves the event an hour later (`move-event`), the work is run and ends `read`, and both tiers' armed instants have moved by 3600 s with the app never opened; the owner makes the event private, the work runs, nothing is armed and no work is left; the next `launch` says "… no longer shares Lifting session. Your alert is off." from what the run kept with the database |
| `04l_fresh_b10_launch_during_run` | freshness B10: shared again, process ended, the event moved, the work started and the app launched at once — the launch succeeds and both tiers end an hour later, whichever of the two read the change |
| `04m_alerts_choice_per_pair` | D38: the partner chooses "Category alerts too"; the owner unpairs ("qa1@example.com ended sharing."); paired again with a new code, the partner's `sharing-alerts` reads "Only alerts I add"; "Category alerts too" chosen again survives `relaunch` of the partner's app (the same pair adopted again); ends on "Only alerts I add" |
| `05_pair_ended` | the event shared again and seen; the owner unpairs on the Sharing page its Pairing row opens (`sharing-paired`, then `sharing-unpair` and `sharing-unpair-confirm`); the partner's Sync & sharing opens on the "Sharing ended" notice (`sharing-ended-close`), and after its next sync the event is gone |
| `05a_pair_ended_folder` | paired again (a third code), the owner shares Training from its ⋮ and the partner sees it under "From …"; the owner unpairs: the partner's notice reads "qa1@example.com ended sharing.", after a sync its "From …" group and Training are gone, and the owner's Training row no longer reads "Shared with …" |
| `06_delete_account` | paired again (a fourth code) with Training shared from the ⋮ and seen at the partner, the partner deletes its account (`sharing-delete-account`, `sharing-delete-account-confirm`): the deletion's row ends as "Account deleted" (never "Finish deleting account"), the page is signed out; after a sync the owner's side reads unpaired (`sharing-pair`), still bound and up to date, its Training no longer "Shared with …"; the partner's guest is relaunched fresh at the end — the roadmap's D2, now with the pair still active (the 2026-11-14 fold of the "account deleted with a folder shared" flow; kept last) |

Green on 2026-11-12 on `anta_qa_1` + `anta_qa_2`, each run against a
freshly started suite: the first six flows 6/6 in 117.6 s and in 120.6 s,
then with the seventh 7/7 in 160.6 s (the deletion itself ≈ 39 s, most of
it the run that empties the account's space). With slice B's six flows,
13/13 twice in a row on the same day, each on a freshly started suite and
both guests freshly booted: 268.2 s and 267.9 s. With 04g–04i, 16/16
twice in a row on 2026-11-13, on the build of the share surfaces, each
on a freshly started suite: 350.3 s and 349.5 s. With the folder flows
(04_n–04_q), 23/23 twice on 2026-11-14 on the build with the freshness
fix: 496.0 s and 498.2 s. With 04ha, 04hb, 04m, 05a and the folded 06
(27 flows), each new flow green with `--only` on a fresh suite the same
day; the whole pass then ended 23/27 in 716.3 s: 04l's launch-during-run
race started a second process whose VM service never answered, the
partner's connection fell to adb, and 04m's `type` of the invite code
went nowhere ("no keyboard is up") — 05, 05a, 06 red behind it; `auto`
now takes the agent back after such a fall (the traps below). On the
final build of the day the whole pass ended 18/27 in 454.1 s
(`share_20261114_081842_057`): 04hb and 04j red on two alerts an earlier
pass had left in the alarm plugins' stores ("What it found"), the rest
behind them; the pair tail 00–04, 04m, 05, 05a, 06 was 9/9 in 224.7 s
with 06's two new assertions, and `qa pass sync` 5/5 in 46.0 s. With the
leftovers cleared (`platform-alerts --native` on both guests) and 04m
lifting its alerts row off the foot of the screen, **27/27 twice**, each
on a freshly started suite: 610.3 s (`share_20261114_091136_671`) and
610.0 s (`share_20261114_092207_850`).

**The seams.** The flows up to 04f and 05 share through two harness
verbs, which stood where the switches now are (04g–04i use the switches
and no seam):

- `qa share event|folder "<name>" [--off]` — the agent's `share` op calls
  `CalendarEventService.setShared` / `FolderStorageService.setFolderShared`
  with the account's pair id (from `PairingService`), the calls a switch
  will make; the row is one of the person's own, live, the only one of its
  name, and sharing needs a pair — anything else fails the step and says
  which. `qa share category "<name>" [--off]` calls
  `CategoryService.setShared` the same way. A category is named as the
  calendar shows it — a custom one by its name, a built-in by its label in
  the app's language (`"Gym"` in English) — and a partner's categories are
  never candidates. The kind came without a protocol bump: an older driver
  build answers "share takes event or folder".
- `qa set account=<sub>:<email>` — who the next emulator sign-in is
  (`QaIdentity.override`), so one APK serves two guests as two accounts.
  In memory: a relaunch is the build's `ANTA_QA_ACCOUNT` again, so it is
  set after the fresh relaunch and before the sign-in tap. `account=build`
  puts the build's back.

Both came with agent protocol v3: a guest holding an older driver build is
told to `qa build` then `qa install`.

**Two guests in one flow.** A step that leads with `-d <serial>` runs on
that device, on a connection of its own that later steps naming it share;
a step naming none runs on the pass's. `text <target> --match <regex>
--capture <name>` keeps what one guest shows, and `{{var:<name>}}` writes
it in any later step — how the invite code crosses. Only in a flow file:
on the command line `steps '-d emulator-5558 tap …'` reads the `-d` as its
own option.

**The partner syncs on demand.** Nothing tells the partner's engine of the
owner's change — it cannot watch another account's space — and unasked it
looks at most every five minutes. Every check on the partner's guest
follows a "Sync now" there (`sharing-sync-now`), reached from any root
through the drawer's account row (`drawer-account`). The checks then wait
up to 30 s on the open page: the screens follow the run by themselves.

**What it found, 2026-11-12.** On its first runs the pass met two defects
no suite had:

- the pairing sheet closed itself on every "paired" state, and the second
  one — the partner's name arriving — popped the page under it: the
  redeemer landed on Settings (`pairing_sheet.dart`, pinned by
  `test/widgets/pairing_sheet_test.dart`);
- a shared row that left was removed from the database and stayed on the
  open page until the app was started again: a removal is now announced
  as gone, with where the row stood (`SyncAppliedRow.gone`,
  `FolderRepository.announceRemoved`, `NoteRepository.announceRemoved`).

**What it found, 2026-11-14.** The first two are fixed in the app and
pinned by 06 since the final build of the day (the ⋮ entry reads "Share
with …" right after the new pair; the owner's notice reads "Your partner
ended sharing. Your notes and events stay on this device."); the third
was no defect of the build:

- after the partner deleted its account while paired, the owner's
  "Sharing ended" notice read " ended sharing. Your notes and events stay
  on this device." — an empty name, neither the partner's nor "Your
  partner";
- a folder's share mark outlived its pair: after 05a's unpair the owner's
  Training wore no sign, but at the next pair its ⋮ entry read "Shared
  with your partner" at once and the partner received it with no new act;
- 04hb, 04j and 04k went red on "2 armed, expected none" — a reminder
  and an alarm of Lifting session's last occurrence in the window
  (2026-12-10) — and read at first as a regression. They were leftovers:
  an earlier pass that never reached a clean end left them in the alarm
  plugins' own native stores; the QA reset clears the preferences the
  alert tier reads them by before its quiet runs, so the quiet named
  none of them (`platform-alerts` lists 0), and the plugins re-armed them
  at every launch — through `fleet stop`, a cold boot and a reinstall.
  The flows arm nothing of them: a reinstall cleared them and one
  `relaunch --fresh` brought them back. **Recovery:** `qa -d <guest>
  platform-alerts --native` (fleet guests only) — the alarm fork's
  stop-all and the notifications plugin's cancel-all empty those stores;
  `armed` then reads none, and still none after `relaunch --fresh`. The
  durable fix landed in the build of 10:01: the QA reset's quiet also
  reads the pending notification requests (a notice names its alarm) and
  every id in the alarm plugin's own list. Proven on the partner left as
  an aborted 04l leaves it (16 reminder-tier entries, 8 alarms): one
  `relaunch --fresh` said `quiet: stopped 0 ring(s), cancelled 16
  alarm(s), took down 0 notification(s)`, and `armed --expect none` held,
  also after a plain relaunch. `--native` stays as the recovery for a
  guest that holds entries from before that build.

**What it does not cover.** The partner's own presence mark or alert on a shared event; the same id on
both accounts; a newer wire; a second device of either account; an
account deleted while its pair is still active (the flow deletes it after
the pair ended); anything on the real project.

**Traps met.**
- A step line that starts with `-d` cannot be given to `qa steps` on the
  command line (above): write a step file.
- The partner's "Sharing ended" notice is a dialog over Sync & sharing: a
  flow that waits for the page's bar there waits in vain — it answers
  `sharing-ended-close` first.
- The first "Up to date" after a tap on "Sync now" can be the one from
  before the run: the flows never rely on it alone, each check on the
  partner's guest carries its own timeout.
- An event a flow makes has an id minted on the device, so its day-panel
  row is tapped by title — and today's grid cell carries every title of
  the day in its marker label ("Lifting session, From …, Core circuit, From
  …"), which comes first in traversal: the flows tap `--nth 1`. The panel's
  expand toggle, which would take the grid out of the tree, has no id.
- A partner's row reads "From qa1@example.com": the owner's account has no
  profile name in the Auth emulator, so the partner's name is its email.
- The Upcoming list groups a category of two or more events into one card
  that names the category, not its events: a title is read off the card's
  day list (`agenda-card-days-category-<id>`, closed by `day-list-close`),
  and a flow that needs one event's title on the partner's Upcoming list
  keeps it alone in its category there (why 04f moves to Cardio, not
  Other). A recurring event makes a card on its own: 01's shared
  "Lifting session" shows on the partner's Upcoming list as an "Other"
  card ("1 event · 9× in window"), and 01's `expect "Lifting session"`
  is met by today's grid cell's marker label, not by that card.
- A label target falls back to ids: `expect --absent "Strength"` on the
  calendar page matches the card's id
  `agenda-card-days-category-qa-category-strength`, so a renamed
  category's old name is checked absent only inside the day list the card
  opens (04b).
- A count in the category delete sheet is glued to its noun with a
  no-break space (U+00A0) — "Power\n2 events" — and a target typed with a
  plain space never matches it: 04f's `expect "2 events"` carries the
  U+00A0 byte. The Edit tool writes a plain space; the byte went in
  through PowerShell (`[char]0xA0`), checked with `od -c`.
- A picker that slides in shows its rows before they stop moving, and a
  tap then lands beside the row: the tap that opens it holds
  (`--settle 1000`, 04f's `category-delete-target`).
- The owner's "Up to date" right after its "Sync now" can be the status
  from before the run, so the partner may read before the owner's push
  lands: the slice-B flows tap the owner's `sharing-sync-now` with
  `--settle 3000`. 01 and 04 have none and were green in three passes on
  a freshly started suite; their reds of 2026-11-12 came on a hand-reset
  suite with six test runs loading the machine.
- A flow run alone (`--only`) starts where the prelude leaves both
  guests — on Sync & sharing two Backs from the root, through the
  Settings hub — and every flow after 01 expects one Back (the drawer's
  account row): `--only 00_pair --only 04a_share_category` reds at 04a's
  second step by construction.
- `expect` splits its targets at commas: `expect "Gym, Stretching"` checks
  "Gym" and " Stretching" apart, and `--absent "Gym, Stretching"` fails
  on either word. A comma-joined value (the Sharing page's category names)
  is read with `text <target> --match "Gym, Stretching"`, which keeps it
  whole; a grid cell's marker label ("Lifting session, From …") is
  checked word by word.
- On the calendar's Upcoming list a third card's "Show every day"
  (`agenda-card-days-category-*`) lies under the Add event button, and
  a tap there opens the editor. 04g and 04i reach "Lifting session"'s
  Cardio card by filtering the list to recurring events first
  (`agenda-filter-events-recurring`), then put the filter back.
- A row of a category card's day list carries no id; a tap on it selects
  its day, and the day panel's row then carries the event's id
  (`event-row-qa-event-weekly-lift`). The partner's Single events list
  opens nothing.
- The Sharing page's sheets — the Single events lists, "Categories from
  …", a received category's sheet, the read sheet — have a ✕ with no id;
  the flows close them with `key back`.
- "Stop sharing everything" confirms through the app-wide `sheet-confirm`.
- The bar that says what arrived (`share-notice-view`) leaves after a few
  seconds: the flow taps View straight after its wait.
- A category made on the device has a minted id: 04g–04h name Stretching
  and "Hip openers" by title, and in "Categories from …" the title
  matches the row (`--nth 0`, which opens its sheet) and the show switch
  ("Show Stretching on my calendar", `--nth 1`).
- The page's captions and the notices begin with the partner's name; an
  e-mail address standing in for one is left as it is written
  (`ShareCopy.sentence`). The flows match the words after the name.
- A row tapped while its sheet is still sliding in opens a sub-sheet over
  a sheet that has not settled. Until 2026-11-13 the parent then kept the
  geometry of mid-slide and reported its ✕ some 70 dp low, so
  `tap id:filter-close` missed it (04h, two reds in six runs). Fixed in
  the app — the filter sheets and the share lists refresh their geometry
  once uncovered (`FormSheetSemanticsRefresh`). The tell in a pass log: a
  row whose bounds differ between its `wait` and the `tap` after it.
- **Building in a worktree on C: with the pub cache on D:**, `qa build`
  fails in `:<plugin>:compileDebugKotlin` with "Could not close
  incremental caches … different roots". Build with
  `GRADLE_OPTS=-Dorg.gradle.project.kotlin.incremental=false`, after
  removing the `build/<plugin>/kotlin` folders a failed build left.
- **The freshness flows (04j–04l) end the partner's process**, and three
  things follow (2026-11-13):
  - `kill-app` ends it with `run-as … kill -9`, never `am kill`: WorkManager
    reads an exit "requested by the user" as a force-stop ("Application
    was force-stopped, rescheduling" in logcat) and a forced job is then
    not run. The verb warns when it had to fall back.
  - The partner's sign-in account (`set account=…`) is held in memory, so
    each flow sets it again after its `launch`; without that 06's
    re-authentication offers the build's account and the page says "That
    is another account — nothing was deleted".
  - `key home` needs `--via native`: the agent has no Home.
  - After `kill-app` the work it runs starts the process again, on a VM
    service port no launch forwarded, so the next `launch` only brings it
    to the front. Until 2026-11-13 the recorded URI stayed the killed
    process's and `auto` settled on adb for the rest of the pass: every
    partner verb from 04k on took 2–4 s, and 06 missed its four-second
    "Account deleted". `launch` of a running app now asks the agent and,
    when it does not answer, finds the process's VM service in its log
    (`agent: vm=… (a process no launch started — found in its log)`);
    the tell of the old way is `note: driver auto → adb` in `pass.log`.
  - 04l's launch can race the work: `pidof` finds nothing, `am start`
    asks for a forwarded VM service port, and the activity lands in the
    process the work started a moment before — whose Dart VM opened its
    service on a port of its own before the activity existed, so the port
    asked for never answers (45 s, then adb; the whole pass of 2026-11-14
    went red at 04m on it). Since 2026-11-14 the launch's wait reads the
    process's log, stops as soon as it names another port, and adopts that
    process's agent (`agent: vm=… (the process was already up — the work
    started it first …)`); and an `auto` that fell to adb takes the agent
    back once a VM URI is recorded since the fall (`note: driver adb →
    agent on …`).
  - `work --run` cold-starts a killed process, and WorkManager's start-up
    reconcile can stop the forced job it was started for ("Found unfinished
    work, scheduling it" → `onStopJob`; 04k red twice on 2026-11-14 with
    "no ending within the timeout"). `--await` now reads those lines too
    and runs the rescheduled job once more ("WorkManager stopped the forced
    run at its start-up reconcile … running it once more"). Not yet seen
    firing on a device: the race came twice before it was in and never in
    the runs after. A run that logs no ending now prints the WorkManager
    lines its filtered log held and the jobs `dumpsys` lists, so the next
    one says which of the two reads came back empty.
- `work` reads `dumpsys jobscheduler`. On API 36 WorkManager's job has a
  namespace (`JOB androidx.work.systemjobscheduler:u0a217/7: … @androidx.
  work.systemjobscheduler@com.alexzamfir.anta/…SystemJobService`), and
  `work --run` must name it (`cmd jobscheduler run -f -n <namespace>`);
  `work --raw` prints the text the verb parsed when a job seems missing.
- The check's work sits in one of two slots (`shared-refresh`,
  `shared-refresh-2`); each run schedules its successor into the other, so
  the job id `work` prints changes after every run.
- 04h opens the filter sheet with `--settle 1000`: its next tap landed on
  the row under the sliding sheet once (`filter-categories` → "Priority").
- **The folder flows (04_n–04_q, 2026-11-14).** A row keyed by a folder's
  id carries an id the seed's import minted, so it is named by prefix:
  an `id:` target ending in `*` matches the ids that start with the rest
  (`id:share-folder-unshare-*`, `id:shared-folder-open-*`), and the lint
  takes it only after a function-built id's fixed part
  (`id:folder-picker-row-*` where the picker shows one row). The folder
  page's ⋮ is `folder-more`, a row sheet's entries `row-action-move` and
  `row-action-delete`, the picker's field `folder-picker-search` and its
  one confirm `folder-picker-confirm`, the editor ⋮'s folder entry
  `editor-menu-folder`: no flow taps a point. A picker search result
  moves the note at once. The field takes a stem of the name ("Train"): the
  whole name matches the field's own text exactly, which outranks the
  row. Session 2's preview names Session 1 and sorts first, hence
  `--nth`. The partner's bar is checked with `expect` (an acting `wait`
  on its words fails the lint): present, then `--absent` with a timeout
  until it leaves, then `--absent` once more — a second bar would be
  queued behind the first and shown the frame it left.
- **04k red on the 2026-11-14 tree (an app defect, not the harness).**
  Every `SharedPreferences` write of the shared check threw `Bad state:
  setPrefix cannot be called after getInstance` (`not applied`, `plan not
  written down`, `retry not counted` in logcat), and the closed-app run
  ended `trigger failed` in `AppSharedRefreshRunSteps.prepare`:
  `QaBootstrap.namespacePreferences()` calls `setPrefix` on every
  `PreferencesSharedRefreshMemory._store()` and `prepare()`, after the
  isolate's first `getInstance`. QA builds only (the prefix is QA's), but
  it ends 04k at `work --run --await read` and leaves the partner on the
  launcher, so 04l–06 red after it.
