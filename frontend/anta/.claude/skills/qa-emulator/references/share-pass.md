# Share pass

Reference, not rules. Read only the part the task needs.

## The share pass (2026-11-12)

One command is a device pass of sharing between two accounts on two fleet
guests, against the local Firebase emulator suite — no real account, no
real project. It is the device proof of the sharing foundations
(`docs/cloud-sharing-foundations.md` F4), the multi-user roadmap's R10,
and of the share surfaces' slice B, "a category can be shared"
(`docs/cloud-share-surfaces-roadmap.md` §7.6), with slice A's read sheet.

```bash
tool\firebase\emulators.cmd                                   # a host shell of its own, left running: Auth 9099, Firestore 8080
./tool/qa/qa fleet boot 1 && ./tool/qa/qa fleet boot 2        # anta_qa_1 (emulator-5556) and anta_qa_2 (emulator-5558), one at a time
./tool/qa/qa build --define ANTA_QA_CLOUD=true --define ANTA_QA_FIREBASE_EMULATOR=10.0.2.2 --define ANTA_QA_ACCOUNT=qa1:qa1@example.com
./tool/qa/qa fleet install                                    # the same APK on both
./tool/qa/qa pass share -d emulator-5556                      # 13 flows on one seed: ≈ 4.5 min
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
| `04a_share_category` | the owner makes "Mobility drills" in Strength in the editor, then `share category "Strength"`: the partner's day panel lists it, each row read "From qa1@example.com" first; the Upcoming card of the category (`agenda-card-days-category-qa-category-strength`) opens a day list with both events under "Strength"; the partner's editor's picker never offers it (`--absent id:category-pick-qa-category-strength`); the owner adds "Core circuit" to Strength and moves "Mobility drills" to Cardio — after one sync each side the first arrived and the second left, with no second act |
| `04b_category_renamed` | the owner renames Strength to "Power" in the category editor; the partner's Upcoming card reads "Power", and the day list it opens names "Power", not "Strength", over the two events still in it |
| `04c_read_sheet` | a tap on the partner's "Core circuit" opens the read sheet (`shared-event-sheet`: "From …", the category "Power", Add alert, Copy) and neither the editor nor the detail sheet's Edit; Copy to my calendar closes it and opens the copy in the editor under the "Later changes by …" snackbar, which the flow closes unchanged (`event-close`) |
| `04d_category_unshared` | `share category "Power" --off`: every partner row leaves the day panel and the Upcoming list; the copy stays, no longer the partner's |
| `04e_shared_builtin` | the owner makes "Treadmill run" in its default Gym and shares Gym: the partner's read sheet names the partner's own Gym; Gym private again and the event leaves |
| `04f_category_deleted` | Power shared again and seen; the owner deletes it from the Categories page, moving its two events to Cardio (`category-delete-target`, `category-pick-cardio`): they leave the partner's calendar |
| `05_pair_ended` | the event shared again and seen; the owner unpairs on the Sharing page its Pairing row opens (`sharing-paired`, then `sharing-unpair` and `sharing-unpair-confirm`); the partner's Sync & sharing opens on the "Sharing ended" notice (`sharing-ended-close`), and after its next sync the event is gone |
| `06_delete_account` | the partner deletes its account (`sharing-delete-account`, `sharing-delete-account-confirm`): the deletion's row ends as "Account deleted" (never "Finish deleting account"), the page is signed out; the owner's side is still bound, up to date and ready to pair; the partner's guest is relaunched fresh at the end — the first device pass of the roadmap's D2 |

Green on 2026-11-12 on `anta_qa_1` + `anta_qa_2`, each run against a
freshly started suite: the first six flows 6/6 in 117.6 s and in 120.6 s,
then with the seventh 7/7 in 160.6 s (the deletion itself ≈ 39 s, most of
it the run that empties the account's space). With slice B's six flows,
13/13 twice in a row on the same day, each on a freshly started suite and
both guests freshly booted: 268.2 s and 267.9 s.

**The seams.** No surface shares anything yet, so two harness verbs stand
where a switch will:

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

**What it does not cover.** A note's text opened on the partner's guest
(the editor has no read-only mode yet, and a save there is refused); the
partner's own presence mark or alert on a shared event; the same id on
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
- **Building in a worktree on C: with the pub cache on D:**, `qa build`
  fails in `:<plugin>:compileDebugKotlin` with "Could not close
  incremental caches … different roots". Build with
  `GRADLE_OPTS=-Dorg.gradle.project.kotlin.incremental=false`, after
  removing the `build/<plugin>/kotlin` folders a failed build left.
