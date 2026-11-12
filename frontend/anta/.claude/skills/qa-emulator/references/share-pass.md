# Share pass

Reference, not rules. Read only the part the task needs.

## The share pass (2026-11-12)

One command is a device pass of sharing between two accounts on two fleet
guests, against the local Firebase emulator suite — no real account, no
real project. It is the device proof of the sharing foundations
(`docs/cloud-sharing-foundations.md` F4) and the multi-user roadmap's R10.

```bash
tool\firebase\emulators.cmd                                   # a host shell of its own, left running: Auth 9099, Firestore 8080
./tool/qa/qa fleet boot 1 && ./tool/qa/qa fleet boot 2        # anta_qa_1 (emulator-5556) and anta_qa_2 (emulator-5558), one at a time
./tool/qa/qa build --define ANTA_QA_CLOUD=true --define ANTA_QA_FIREBASE_EMULATOR=10.0.2.2 --define ANTA_QA_ACCOUNT=qa1:qa1@example.com
./tool/qa/qa fleet install                                    # the same APK on both
./tool/qa/qa pass share -d emulator-5556                      # 6 flows on one seed: ≈ 2 min
./tool/qa/qa fleet stop anta_qa_1 && ./tool/qa/qa fleet stop anta_qa_2
```

Stop the emulator suite afterwards. **Every pass needs a freshly started
suite**: it leaves both accounts' spaces in it, and a second pass against
the same suite meets the space picker at its first bind. Both guests keep
the cloud-define build until the next `qa fleet install --build`, which
the other suites need (they expect cloud off).

Always name the pass's device (`-d emulator-5556`): the flows drive the
second guest through steps that lead with `-d emulator-5558`, and a pass
that named no device would open a second connection to its own guest for
a step that names it.

| Flow | Proves |
| --- | --- |
| `_prelude` | the partner's guest relaunched fresh; each guest signed in as its own account (the partner through `set account=qa2:qa2@example.com` before its sign-in tap), bound to a space of its own, "Up to date" |
| `00_pair` | the owner makes a code (`pairing-generate`, read off `pairing-code`), the partner types it and taps Connect; both pairing rows read paired (`sharing-unpair`) — the redemption is one write, the owner adopts through its invite listener, and neither sheet takes the page under it along |
| `01_share_event` | `share event "Lifting session"` on the owner; after a sync on each side the partner's calendar lists it under Upcoming and not the event that was not shared; its category is one the partner does not have |
| `02_share_folder` | `share folder "Training"`; the partner's browser shows it at the top level, the folder inside it and that folder's two notes, and none of the owner's other folders |
| `03_follows` | a folder the owner makes inside the shared one afterwards reaches the partner at the next sync, with no second act of sharing |
| `04_made_private` | both made private (`--off`): after a sync on each side the folder is gone from the partner's browser and the event from its calendar, on the open pages, without a relaunch |
| `05_pair_ended` | the event shared again and seen; the owner unpairs (`sharing-unpair-confirm`); the partner's Sync & sharing opens on the "Sharing ended" notice (`sharing-ended-close`), and after its next sync the event is gone; the partner's guest is relaunched fresh at the end |

Green twice on 2026-11-12 on `anta_qa_1` + `anta_qa_2`, each against a
freshly started suite: 6/6 in 117.6 s and 6/6 in 120.6 s.

**The seams.** No surface shares anything yet, so two harness verbs stand
where a switch will:

- `qa share event|folder "<name>" [--off]` — the agent's `share` op calls
  `CalendarEventService.setShared` / `FolderStorageService.setFolderShared`
  with the account's pair id (from `PairingService`), the calls a switch
  will make; the row is one of the person's own, live, the only one of its
  name, and sharing needs a pair — anything else fails the step and says
  which.
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
both accounts; a newer wire; a second device of either account; deleting
an account while paired (D2's device pass is still owed); anything on the
real project.

**Traps met.**
- A step line that starts with `-d` cannot be given to `qa steps` on the
  command line (above): write a step file.
- The partner's "Sharing ended" notice is a dialog over Sync & sharing: a
  flow that waits for the page's bar there waits in vain — it answers
  `sharing-ended-close` first.
- The first "Up to date" after a tap on "Sync now" can be the one from
  before the run: the flows never rely on it alone, each check on the
  partner's guest carries its own timeout.
