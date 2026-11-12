# Cloud Multi-User Roadmap — ANTA

**Status: D1 and D2 DONE 2026-11-11. D1 — "Delete cloud copy", committed
`f67c942a` (2026-11-10) and its debt pass after it (2026-11-11): the long
part of a deletion runs in the background, resumes by itself and has a
section of its own; reviewed three times, the saved `sync` device suite
green. §5.1–5.8 state the design as built, §5.9 the history. D2 — "Delete
account" (§6.1, design and as-built; commit `978898fc`): built on D1's
run, reviewed, the gate green (`+15822 ~17`, the rules suite 124 of 124);
no device pass yet — it rides the two-guest suite (R10). R2 — "Where your
data is stored" DONE 2026-11-12 (§9): a Privacy section on the Sync page
and a guide row. Sharing FOUNDATIONS BUILT 2026-11-12, without their
surfaces (the owner's scope of 2026-11-11): everything slices E1–E4,
N1–N2, R5 and R9 stand on — the grant, wire 47, the rules and indexes,
the reader of a partner's shared rows, read-only in the database, backups
— in `cloud-sharing-foundations.md` (F1–F3, two independent reviews and
their fixes); nothing in the app can set a share yet, and each surface is
still its own slice. Its device proof (F4, with R10) is to do. Decided 2026-11-11 on the owner's word: the region is
the European Union (R1, the owner runs the move, whose last step now
flips the notice's place); a second account on one phone is accepted (R4,
not built). Left to the owner: the rules and indexes deploy (now carrying
D2's pair and invite rules, the sharing rules and their five indexes, and
the one-write redemption — after it only this build can pair), the build
on every device, the phone checks (§5.8,
§6.1), the region move (R1). Every other slice is PLAN: one row of §3,
with its own design section or record when it starts. The target is the
owner's (§1).** Written from the
investigation of 2026-11-10 at `14a1dc58`: two code sweeps, the cloud
records read by section, the live database's metadata, the Firebase and
store documentation. Master ladder: `cloud-sync-roadmap.md`. This record is
the plan for what that ladder calls Phases 03 and 04;
`cloud-sync-phase-03-shared-folders.md` predates the engine (it speaks of
v27, `is_shared` and chunks keyed by index) and stays as history only.

## Contents

1. The target
2. What exists
3. The slices, counted
4. Order
5. D1 — Delete cloud copy (design)
6. Group D — deletion
7. Group E — shared events
8. Group N — shared notes
9. Group R — the rest of the findings
10. Group P — only for a public listing
11. Decisions for the owner
12. Must not change
13. How to run this

---

## 1. The target

The owner, 2026-11-10: **two users share some calendar events and some
notes between them; calendar events matter more; the findings are fixed one
by one, starting with deletion.**

What that settles:

- **Two people, not a public service.** The pair of Phase 01 is the consent
  plane as it stands: exactly two accounts, one active pair per account.
  The "connections" design (`cloud-sync-connections-design.md`: five links,
  request-then-approve, QR, push) is not needed for this target.
- **Selected events and selected notes**, never the whole database. Each
  person keeps a private space; sharing is a mark on a row of that space,
  as the readiness record decided (D1: a row lives once, in its owner's
  space; a share is a grant, never a second copy).
- **Events before notes.** Group E is built before group N.
- **Everything only a store listing for strangers needs is parked** in
  group P and counted apart.

---

## 2. What exists

Verified in code on 2026-11-10; the cloud records hold the detail.

- **Sign-in:** Google only, Android and iOS, behind `AuthService`
  (`lib/services/firebase_auth_service.dart`). No account deletion, no
  re-authentication, no second provider.
- **Private data per account:** `users/{uid}/spaces/{spaceId}/{table}/{rowKey}`,
  owner-only rules, every document's `ownerId` must be the writer's uid
  (`firestore.rules`). Deployed. Nothing in `lib/` is tied to one account.
- **The engine** (`lib/services/sync/`): eighteen tables plus note text,
  offline-first, tombstones, conflict copies, a per-space wire version
  gate, a quota pause, automatic and manual cadence. One database binds to
  one space of the signed-in account.
- **Ownership:** `owner_id` on every synced table, NULL meaning "mine";
  the upload queue never sends another account's rows
  (`lib/database/crdt/synced_tables.dart`); backups carry it. No page or
  widget reads it.
- **Pairing:** two accounts link by an invite code, consent enforced in the
  rules; `permissions.{uid}.allowPartnerEdit` is seeded false and nothing
  reads it. No data crosses a pair.
- **Not there at all:** any remote delete (the rules say `allow delete: if
  false` under `users/`), any grant to a second account, any second space
  read by the engine, ownership in the UI, a `shared_with` field anywhere,
  push, App Check, telemetry, a privacy text.
- **The live database:** `(default)` of `alexs-note-tracking-app`, location
  `nam5` (United States), Standard edition, point-in-time recovery off,
  created 2026-11-05 10:31 UTC — the minute of the first rules release, so
  the location reads as the deploy's default rather than a choice. Read it
  with `firebase firestore:databases:get "(default)" --project
  alexs-note-tracking-app`.
- **Schema 51, wire 46.** The next free migration is v52; the next wire
  version is 47.

---

## 3. The slices, counted

Each slice ends with something a person can do or see, on a device, that
they could not before. Size is an estimate: **S** one implementer run,
**M** two, **L** three or more and a design record of its own before any
build.

| Id | What the user gets | Size | For the two-user target |
| --- | --- | --- | --- |
| **D1** | Delete a database's cloud copy | M | yes — first; done |
| **D2** | Delete my account and everything it holds in the cloud | M | yes — done (§6.1) |
| D3 | Ask for deletion from outside the app (a web page) | S | no — listing only |
| E0 | Pairing proven between two real accounts on the live project | S | yes |
| E1 | An event I share shows on my partner's calendar, read-only | L | yes |
| E2 | Stopping a share takes the event off my partner's calendar | M | yes |
| E3 | A shared recurring event arrives whole: skipped days, per-day texts | M | yes |
| E4 | My own presence and my own alerts on an event shared with me | M | yes |
| E5 | My partner may edit the events I share, when I allow it | L | yes |
| E6 | Share a whole category, future events included | M | optional |
| E7 | "New from my partner" — a notice inside the app | S | optional |
| N1 | A folder I share shows on my partner's phone, read-only | L | yes |
| N2 | Stopping a folder share takes it off my partner's phone | M | yes |
| N3 | My partner may edit the notes I share, when I allow it | L | yes |
| R1 | The database in the European Union — `eur3`, decided; the owner runs the move | S | yes — before the partner's data |
| **R2** | The app says where synced data lives and who can read it | S | yes — done (§9) |
| R3 | The cloud copy stops growing (old note text, old tombstones) | L | later |
| R4 | A second account on one phone cannot see or feed the first one's data | M | decided: not built |
| R5 | Two people on two app versions: "update ANTA" instead of silence | S | yes — inside E1 |
| R6 | Knowing why sync broke on a phone I do not hold | M | later |
| R7 | iPhone | L | only if the partner has one |
| R8 | Sign-in on Windows and macOS | L | later |
| R9 | Backups and restores that hold shared rows | M | yes — with E2 |
| R10 | The device pass for sharing in one command: a saved suite on two guests | M | yes — before E1's device pass |
| P1 | App Check: only the real app may talk to the database | S | no |
| P2 | The paid plan with a budget alert | S | no |
| P3 | Privacy policy, terms, the Play data-safety form | S | no |
| P4 | Console checks: sign-in open to anyone, the Play signing fingerprint | S | no |
| P5 | End-to-end encryption | L | no — a decision first |
| P6 | Push: notified while the app is closed | M | no |
| P7 | More than one partner | L | no |

**Thirty-one slices.** Sixteen are on the road to the target (D1, D2,
E0–E5, N1–N3, R1, R2, R5, R9, R10); two are optional on it (E6, E7); four
wait for a reason of their own (R3, R6, R7, R8); one is decided against
(R4); eight matter only for a public listing (D3, P1–P4, P6) or a later
ambition (P5, P7).

Where each finding of the investigation went: nothing deletes cloud data →
D1, D2, D3; one shared free quota → P2; no abuse protection → P1; the
database is in the United States → R1; no legal surface → R2, P3, P5;
storage only grows → R3; devices you do not control → R5, R6; a shared
phone → R4; platforms → R7, R8; the console → P4; sharing unbuilt → E, N,
R9.

---

## 4. Order

1. **D1**, then **D2** — deletion first (owner).
2. **R1** and **E0** — owner's steps and a check, no build; R1 before any
   of the partner's data reaches the cloud, because a location cannot be
   changed and moving later means every device uploads again.
3. **R2** — small, and it must be true before a second person signs in.
4. **E1 → E2 → E3 → E4 → E5**, with R5 decided inside E1 and R9 beside E2.
   E1 starts with a design record: the event half of the old Phase 03,
   rewritten against the engine as built.
5. **N1 → N2 → N3**, the same shape for folders and notes.
6. E6, E7 and the "later" rows when wanted; group P only if the app is
   ever listed for strangers.

---

## 5. D1 — Delete cloud copy (design)

§5.1–5.8 state the design as it was built — rewritten on 2026-11-11, after
the debt pass moved the long part of a deletion out of the foreground.
§5.9 is the history: every run, both reviews' ledgers and the device
passes, in order.

### 5.1 What the user gets

In Settings → Sync & sharing, the Sync section of a syncing database ends
with **Delete cloud copy**, under "Stop syncing". It asks once: the copy
is removed from the account for good, this database stops syncing, nothing
is deleted on this device, and the other devices keep what they hold and
stop too. On yes the database is unbound within a second or two and the
page is free again; the emptying of the cloud copy goes on in the
background and is shown in a section of its own at the end of the page —
"Deleting cloud copy", a count of the items removed, then "Cloud copy
deleted". A deletion that was cut short — the app closed, the link lost —
resumes by itself when the account is next known, and waits as "Finish
deleting" when it cannot. The account's other devices that synced with
that copy stop with "Paused — the cloud copy was deleted" and keep what
they hold.

Before D1 the only way out was "Stop syncing", which unbinds locally and
leaves the space in the cloud for ever.

### 5.2 Decisions taken by the lead (lettered, reversible before the build)

- **a. Scope.** The space this database syncs with. The account's other
  spaces are deleted by D2, and a deletion left half done is finished by
  any device (g).
- **b. Local data is never touched.** Deleting what is on the phone stays
  the Databases page's job.
- **c. No undo, no cancel.** Once confirmed the space is marked and takes
  no more writes; an undo after the first rows are gone would hand back a
  half-empty copy.
- **d. Other devices pause; they do not unbind themselves.** A device that
  finds its space marked or gone shows "Paused — the cloud copy was
  deleted" and pushes and pulls nothing; "Stop syncing" is the way out, and
  its confirmation says the right thing for that state. An engine that
  unbinds its own database from inside a run is the riskier build.
- **e. One confirmation**, drawn as destructive — the first destructive
  row of the page. It says "this database's cloud copy": the binding holds
  no space name and the dialog must not wait for the network (amended
  2026-11-10 during the build; the "Finish deleting" row names the space
  from the pending record).
- **f. The rules allow a row to be deleted only under a marked space.** A
  live space keeps the engine's oldest invariant — a row disappears by
  tombstone, never by a missing document — enforced on the server, not
  only by this client. R3 will widen it on purpose.
- **g. A half-done deletion is always finished.** The space document
  carries the mark and the install keeps a record of the deletion: the
  service's background run resumes it when the account is next known, the
  "Finish deleting" row asks for it, and "Sync this database" on any
  device of the account records a marked space it meets and never offers
  it.
- **h. No wire bump.** The space document gains a key; no row's `data`
  changes; `syncSchemaVersion` stays 46.
- **i. The long part is not a step of the page** (the debt pass,
  2026-11-11). After the unbind a deletion touches nothing local — only
  the cloud and the install-wide record — so the emptying belongs to a
  background run of the service, and the page is held only for the local
  phase.

### 5.3 The protocol

**The local phase** — awaited by the page's step, the engine stopped
first (`SyncSpaceService.deleteCloudCopy`):

1. **Read** the space. Gone already: unbind and return. Its `schema`
   above this build's: refused (`appOutdated`) with nothing changed — a
   newer build may have written a table this one does not list, and
   removing the space document over it would strand those rows.
2. **Mark.** The space document gets `deletedAt` = the server time. From
   then on the rules refuse every update of that document — and every push
   of this app writes it in the row's own transaction (`touched`,
   `lastWriter`, `lastWriteAt`), so a push to a marked space fails whole.
   A failure here changes nothing: still bound, still syncing.
3. **Read again.** The schema is final once the space is marked; a newer
   one found here leaves the mark standing and the database bound and
   paused, for an updated app to finish.
4. **Record** the deletion install-wide. From here the account's status
   reads "running".
5. **Unbind**, exactly as "Stop syncing" does.

**The remote phase** — in the service's background run, one at a time for
the whole process:

6. **Empty.** For every table of the registry
   (`lib/database/crdt/synced_tables.dart`, `content_chunks` included —
   the client SDK cannot list subcollections, so the registry is the list):
   read a page of twenty documents (`SyncGateway.rowDeleteBatch`), delete
   them in one write-only transaction, repeat until the table reads empty.
   Nothing new can land after the mark, so the loop ends. A page refused
   while emptying is followed by a read of the space: gone means another
   device finished it.
7. **Remove** the space document, last, and clear the record.

**Twenty** because each deleted row costs the rules one `get()` of the
space, and Firestore allows twenty document-access calls in one
transaction; the emulator does not enforce that limit, so the documented
number is the contract.

**The run** takes every record of its account in turn. A record whose
space is gone or reads unmarked is cleared, never marked: the mark is the
only authority to delete. A record whose space a newer build wrote to is
passed over and the run ends as `appOutdated`. A failure of the link or of
the account stops the run and leaves the records. It is requested by the
delete step, by "Finish deleting", by "Sync this database" meeting a
marked space, and by the account becoming known (the app's start, a
sign-in): once per process and account, and again after a run that ended
only on the moment — a refusal or offline.

Cost: one read and one delete per document, one more read per page for
the rule's look at the space, and at least one read per table. The owner's
space is about 312 rows plus note chunks. The free plan allows 20,000
deletes a day; past that the run stops with the quota reason and waits for
"Finish deleting" or the next start.

### 5.4 The rules (a sketch — the emulator suite is the judge)

```
match /users/{owner}/spaces/{spaceId} {
  // validSpace(): 'deletedAt' joins the hasOnly list
  function marked() { return 'deletedAt' in resource.data; }

  allow create: … && !('deletedAt' in request.resource.data);
  allow update: … && !marked()
                && (!('deletedAt' in request.resource.data)
                    || request.resource.data.deletedAt == request.time);
  allow delete: if isOwner() && marked();

  match /{table}/{rowKey} {
    function spaceMarked() {
      return 'deletedAt' in get(/databases/$(database)/documents/users/$(owner)/spaces/$(spaceId)).data;
    }
    allow delete: if isOwner() && syncedTable() && spaceMarked();
  }
}
```

The change only adds: a build that never marks is judged exactly as today,
so **the rules deploy before the build installs** and breaks nothing.
Known limit, accepted: a client that is not this app could write a row
under a marked space without touching the space document; guarding it
would cost every push of every device one extra read.

"Breaks nothing" holds until the first space is marked. A build from
before D1 does not know the mark (review F2): its push to a marked space
is denied and it parks the rows as refused, ending at a "no access" pause
that "Sync now" cannot lift; its bind flow still offers the marked space.
Nothing is lost — an unbind clears the parks and the update reads the mark
— but **every device runs D1 before the first delete** (§5.8).

### 5.5 Code

- **Gateway** (`sync_gateway.dart`, `firestore_sync_gateway.dart`,
  `test/support/fake_sync_gateway.dart`): `markSpaceDeleted`,
  `deleteRows` (at most `rowDeleteBatch`, the count answered, 0 for an
  empty table), `deleteSpace`; `markedForDeletion` on `SyncSpaceInfo` and
  `SyncSpaceSignal`. Deletes go through the write-only transaction the
  pushes use, so nothing is ever queued offline; a page that times out
  halves that table's page for the rest of the run. The fake models who
  is signed in (an acting account, a signed-out state) and can hold a
  call open.
- **Service** (`sync_space_service.dart`, `sync_space_registry.dart`):
  `deleteCloudCopy()` — the local phase, then the run requested; the
  background run and its queue; `SyncDeletionStatus {accountUid, pending,
  running, removed, failure}` through `deletionStatus` and the broadcast
  `deletionStatusOf`; `finishPendingDeletions` (a request);
  `followAccounts` (the resume, wired at start-up in
  `lib/core/di/injection.dart`); the install-wide record
  `SyncPendingDeletion` under `SettingsKeys.syncPendingDeletions`.
  `start()` records a marked space, requests the run and never offers the
  space; binding or downloading a marked or missing space answers
  `spaceGone`.
- **Engine** (`sync_engine.dart`, `sync_pusher.dart`, `sync_status.dart`):
  the pause `spaceDeleted` for a space that is marked or gone — from the
  signal, from the diagnosis of a denied push (every denied batch, and
  before a fresh row is parked), from the one read "Sync now" makes under
  either pause and, under the manual cadence, from the read an asked run
  makes first. It holds as `noAccess` does — nothing runs, the outbox and
  the parks stay, the engine never unbinds — and a refusal stays
  `noAccess`.
- **Bloc** (`lib/bloc/sync/`): `DeleteCloudCopyRequested`, a short step
  through `_step` (`SyncBindDeleting`); `FinishDeletingRequested`, a
  request and no step; the account's `SyncDeletionStatus` followed and
  carried by every state that carries the signed-in account; one rule,
  `SyncStatus.canDeleteCloudCopy` (bound, and not under `accountMismatch`,
  `appOutdated` or `spaceDeleted`), for the page and the bloc.
- **Page and drawer** (`sync_settings_page.dart`,
  `lib/widgets/drawer_sync_status.dart`): the Delete row and its
  destructive confirmation; the section "Cloud copy deletion", last on the
  page, whose one row (`sharing-sync-finish-delete`) is running, waiting,
  failed, held until an update, or ended — nothing above it ever moves;
  the pause's line on both surfaces (the page's joins
  `_statusLineTemplates`); the "Stop syncing" confirmation's second body;
  the announcements; a row in the app guide's sync topic.
- **Strings** en/de/ro; `sync-and-accounts.md` holds the as-built entry.
- **Device** (`tool/qa/flows/sync/`, `lib/core/qa/qa_bootstrap.dart`): the
  saved `sync` suite, and the seam that makes a reseeded cloud QA build
  open signed out.

### 5.6 Tests

- Rules (`test/firestore/rules_test.dart`, tag `firestore-rules`): no
  delete of a row or a space while unmarked; the owner marks; a marked
  space refuses an update and a second mark; rows and then the space
  delete once marked; another account can do none of it; `deletedAt` must
  be the server time and cannot be set at create. The probe
  (`tool/firebase/rules_probe.ps1`) gains the same cases.
- Fake gateway contract; the service
  (`test/services/sync/sync_space_delete_test.dart`: the local phase's
  order and each of its failures, the run's status sequence, its queue,
  its resume rule, a failure while emptying and its finish, the quota, the
  older-build refusal, `start()` recording a marked space); the engine
  (the pause from the signal, from a denied push and from the manual read;
  nothing running under it; no row parked on a stale diagnosis); the bloc
  (the status followed, the short step, the refusals); the page at 1.0,
  1.3 and 2.0 in en, de and ro on both phone sizes with the kit's
  guideline cases.
- The saved device suite, `qa pass sync -d emulator-5556`, against the
  Firestore emulator on one guest (bind, the manual cadence with a waiting
  change, stop and merge, delete, bind again and delete); the two-guest
  pass of 2026-11-10 by hand (the second device reads the pause) until
  R10 saves it.

### 5.7 Must not change

Tombstones stay upserts and no row of an unmarked space is ever deleted
remotely; "Stop syncing" and its strings; the picker's layout and ids; the
`pairs` and `invites` rules; `syncSchemaVersion` and the `_wireKeys`
snapshot; the contracts of the gateway's existing methods; the binding
keys, the floor and what an unbind clears; backups; the status row's
one-height rule.

### 5.8 What only the owner does

1. `firebase deploy --only "firestore:rules,firestore:indexes" --project
   alexs-note-tracking-app` before installing the build (check first that
   the gitignored `firebase.json` still carries its `firestore` block).
2. The build on **every** device before the first delete (review F2): an
   older build misreads a space being deleted.
3. The phone check: delete the cloud copy of a database whose space holds
   more than twenty rows in one table — the owner's own does — and see the
   space gone in the console and the notes still on the phone. This is the
   one thing the emulator cannot prove: how the live rules count their
   look at the space across a page of deletes (review F9).

### 5.9 As built

**Run 1 — the remote contract (2026-11-10; gate from the lead: analyze
clean, the whole suite `+15174 ~17` green; uncommitted).**

- **Rules** (`firestore.rules`, the `users/{owner}/spaces` block):
  `deletedAt` joins `validSpace()`; `marked()` = the key is present; a
  create may not carry it; an update is refused once marked and may set it
  only to `request.time`; the owner may delete a marked space document; a
  row of a synced table may be deleted only while `spaceMarked()` — one
  `get()` of the space per request. Two consequences the suites pin: a
  space document that no longer exists cannot be "deleted" (there is no
  mark to read — the gateway reads back and answers "gone"), and a row
  under a missing space can never be deleted, which is why the space
  document goes last.
- **Gateway** (`sync_gateway.dart`): `markSpaceDeleted(space)`,
  `deleteRows(space, table, {limit})` → the count, 0 for an empty table
  whatever the space's state, `deleteSpace(space)`; `markedForDeletion` on
  `SyncSpaceInfo` and `SyncSpaceSignal` (false while `exists` is false).
  Mark and space delete make one attempt and, after any failure, read the
  space once and answer by what the server shows; `deleteRows` is one page
  read from the server then one write-only transaction.
  `FirestoreSyncWire.markKey` is `deletedAt`.
- **Fake** (`test/support/fake_sync_gateway.dart`): the three calls with
  the scripted failures; a push to a marked space is `permissionDenied`;
  the console-delete helper is `consoleDeleteSpace`.
- **Suites:** the rules suite 114 green on the emulator (17 new cases,
  four beyond §5.6: a row already gone, a row of an unknown table, a row
  under a missing space, a space already gone); the probe 44 PASS; the
  fake's suite 8 new cases.
- **Not verified:** the Firestore gateway's three calls need the platform
  plugin — the device pass is their first run, the mark of a missing space
  included.

**Run 2a — the engine pause (2026-11-10; gate from the lead: analyze
clean, the whole suite `+15182 ~17` green; uncommitted).**

- `SyncPause.spaceDeleted` and `SyncRunSkip.spaceDeleted`. The rule as
  built: **a space that is marked or gone is `spaceDeleted`; a refusal
  stays `noAccess`.** `_onSignal` raises it on `!exists` or
  `markedForDeletion`; the pusher's `_diagnose` on a null or marked
  `readSpace` (its own denied read stays `noAccess`); `_regainsAccess` runs
  for both pauses and settles on what its one read shows — null or marked
  is `spaceDeleted`, a newer schema `appOutdated`, a live space lifts
  either. Still `noAccess`: a pull's refusal, a listener's refusal, more
  than twenty refused rows. Everywhere else the two hold alike
  (`_accessLost`): the gate, `pauseOver`, a sign-in lifting it.
- Nothing runs under the pause, the outbox and the parks stay, the binding
  stays; "Sync now" re-reads the space once; "Stop syncing" works.
- Words: `syncPausedSpaceDeleted` ("Paused — the cloud copy was deleted",
  in `_statusLineTemplates`) and `drawerSyncPausedSpaceDeleted` ("Paused —
  cloud copy deleted"; the Romanian line was shortened to fit the drawer
  at 1.0).
- Five existing cases moved from `noAccess` to `spaceDeleted` (a deleted
  space under a started device, on a resume, under a denied push); the
  refusal cases kept theirs.
- Known, as with `noAccess`: a launch whose last full pull is a day old
  walks every table of a gone space once (eighteen empty reads) before
  the signal pauses it.

**Run 2b — the service (2026-11-10; gate from the lead: analyze clean,
the whole suite `+15205 ~17` green; uncommitted).**

- `SyncSpaceService.deleteCloudCopy({onProgress})`, in the order of §5.3:
  unbound → nothing; a restore running → `suspended`; the space read —
  gone already → unbound as "Stop syncing" does; its `schema` above this
  build's → the new `SyncBindFailure.appOutdated`, nothing changed; the
  mark (a failure here changes nothing); `unbind()`; the record; every
  table of `syncedTables` emptied; the space document; the record cleared.
  `content_chunks` starts at pages of 50 (`chunkDeletePage`); a timed-out
  page halves its table's page down to 1, and a timeout at 1 fails as
  `offline`. The service never touches the engine — the caller stops it.
- **The pending record:** `SyncPendingDeletion {space, spaceName}` kept by
  `SyncSpaceRegistry` under the install-wide `sync_pending_deletions`
  (`SettingsKeys.syncPendingDeletions`), never in a backup, a malformed
  entry dropped. `pendingDeletions(accountUid)` lists the account's;
  `finishPendingDeletions({accountUid, onProgress})` takes each to the end
  (mark again, empty, remove, clear), clears a record whose space is gone,
  leaves another account's alone and stops at the first that fails.
- **The bind flow:** `start()` finishes the account's marked spaces first,
  best effort, and decides on the unmarked ones only; `bindExisting` now
  reads the space before it binds — a missing or marked one is
  `spaceGone` (it bound a missing space blindly before, and can now fail
  `offline` at that read) — and so does the download.
- Words: `syncFailedAppOutdated` ("A newer ANTA wrote to this cloud copy —
  update the app first").
- Suites: `sync_space_delete_test.dart` (23 cases), four registry cases.
- Windows the death of the app leaves, and what heals each: marked and
  still bound (the unbind did not run) → the engine pauses as
  `spaceDeleted`, and a second "Delete cloud copy" carries on; unbound
  with no record (the record did not land) → the next "Sync this
  database" on any device finishes the marked space.

**Run 3 — the surface (2026-11-10; gate from the lead: analyze clean, the
whole suite `+15274 ~17` green on the second run — the first showed the
known load flake of `database_settings_page_test.dart` "delete all wipes
the database directory", green alone 47/47; uncommitted).**

- **Bloc:** `DeleteCloudCopyRequested` and `FinishDeletingRequested`, both
  through `_step` (the engine stopped first) with the busy flow
  `SyncBindDeleting(removed)`, one emit per progress report; a failure is
  `SyncBindFailed(…, deleting: true)` so the page words it on the
  deletion's own row. `SyncSignedIn.pendingDeletions` is read with every
  status read: at load, after an account change, at every step's settle.
- **Page:** "Delete cloud copy" is the bound section's last row — the
  title in the error colour, the subtitle in one `_FixedLinesSlot` sized
  from the description and the progress line — and opens
  `AppDialogs.confirm(isDestructive: true)`. Held while a step runs, when
  signed out and under `accountMismatch`; enabled under every engine
  pause. "Finish deleting" sits under "Sync this database" while a
  deletion is pending or running, names the first pending space, asks
  nothing. The "Stop syncing" confirmation takes
  `syncStopConfirmBodyDeleted` under `spaceDeleted`; "Cloud copy deleted"
  is announced politely at the end.
- **Ids:** `sharing-sync-delete`, `sharing-sync-delete-confirm`,
  `sharing-sync-finish-delete`. **Strings:** twelve keys
  (`syncDeleteCloud*`, `syncStopConfirmBodyDeleted`,
  `appGuideSyncDelete*`), the progress line a plural ("Deleting — {count}
  items removed"), "delete" in `syncKeywords`. **Guide:** a `sync-delete`
  row after `sync-stop`.
- **Heights** (360 × 780, one height per row across idle, busy, held,
  failed): 80 dp at 1.0 in en, de and ro; at 2.0 — en 172, de 212, ro 212
  for Delete (its title wraps) and 172 for Finish.
- **Fake:** `createSpace` ids never reused; `consoleRestoreSpace` brings a
  console-deleted space back for the one case that needs it.
- **Open after the build:** no saved QA flow drives the three new ids
  (the Sync section of a bound database is out of the saved suites'
  reach, as before); the kit's guideline cases do not scroll, so the
  Delete row may go unjudged at de 2.0; the bloc does not itself refuse a
  delete under `accountMismatch` — the page holds the row and the service
  fails `permissionDenied` with nothing changed.

**Review, first sitting — the data plane and the engine (2026-11-10, one
`reviewer` probing in a copy of the tree).** No path deletes or empties a
space the user did not confirm, and none touches local data; the rules
match their intent on the emulator. The ledger and what the lead decided:

| Id | Finding | Decision |
| --- | --- | --- |
| F1 | CONFIRMED — under the manual cadence no signal is attached, so a device whose space was marked or deleted never pauses: "Sync now" pulls eighteen tables and reports success | **Fix:** an asked run under manual reads the space once first |
| F2 | A build from before D1 misreads a marked space: its pusher parks rows as refused and ends at a `noAccess` no "Sync now" lifts; its bind flow offers the marked space and can download a half-emptied copy | **Limit, recorded** (§5.4, §5.8): D1 on every device before the first delete |
| F3 | The schema check judges the read made before the mark; a newer build's push in between could leave a table unwalked under a removed space document | **Fix:** read again after the mark — the schema is final from then on |
| F4 | Two devices finishing one space: a page delete landing after the other's space delete is denied and reads as "another account" | **Fix:** a denial followed by a space that reads gone is "done" |
| F5 | A malformed row diagnosed earlier in the same drain hides a space marked mid-drain; rows are parked until the next launch | **Limit, recorded** — rare, and an unbind clears the parks |
| F6 | The record was written after the unbind, so a death between the two left a marked space nobody was shown | **Fix:** mark → record → unbind |
| F7 | `start()` finishes marked spaces to the end with no progress shown | **Fix:** the progress reaches the bloc, which shows the deleting flow |
| F8 | Finishing re-marked whatever the read returned, so a record was a standing licence to delete | **Fix:** finishing never marks; a record whose space reads unmarked is cleared |
| F9 | Each row delete makes one rules `get()`; Firestore documents twenty access calls per multi-document request, and only the emulator was seen accepting 499 | **Fix:** delete pages of twenty; a multi-row case in the rules suite; the owner's phone check deletes a table of more than twenty rows |
| F10 | `markSpaceDeleted` and `deleteSpace` touch the database handle outside `_guard` | **Fix** |
| F11 | The fake has no account and its scripted mark failure never lands | **Recorded;** the landed-mark recovery gets a service case (F12) |
| F12 | No case for a second "Delete cloud copy" on a database still bound to a marked space; no multi-row rules case | **Fix:** both added |
| F13 | Pre-existing: `_gate` reports the `noAccess` skip when the re-read turned the pause into `appOutdated` | **Left as found** |

**Device pass 1 — the first real run of the Firestore calls (2026-11-10,
one `qa-runner` on `anta_qa_1` against `tool\firebase\emulators.cmd`, the
cloud-define QA build of the tree as run 3 left it): green, 8/8.** The
`basic.json` seed bound and read "Up to date" (25 changes); the emulator
held 1 space, 4 folders, 3 notes, 3 chunks, 2 events, 10 categories.
"Delete cloud copy" → the destructive dialog → "Deleting — 25 items
removed" with the other rows held → the unbound row, in under about
fifteen seconds; every one of the six collections then counted 0, the
browser still showed its three root folders and their notes, and a second
"Sync this database" created a new space with the same counts. The only
log lines: `MissingPluginException … cancel` on a transaction stream at
teardown, once per transaction, the noise the Phase 02 passes already
recorded. Not covered by this pass: a second device reading the pause, a
table of more than twenty rows, an interrupted deletion — the final pass
and the owner's phone check (§5.8).

**Review, second sitting — the bloc, the page, the strings (2026-11-10,
the same `reviewer`).** Nothing loses data or deletes what was not
confirmed; six revert probes each turned their case red, so the suites
probed are not vacuous. The ledger and what the lead decided:

| Id | Finding | Decision |
| --- | --- | --- |
| S1 | The confirmation never says that this database stops syncing, and "your other devices stop syncing" overstated what a manual-cadence device and an older build do | **Fix:** the body says the copy goes for good, this database stops syncing, nothing is deleted here, the other devices keep what they hold and stop too (true once F1 is in); the guide row likewise |
| S2 | A space name of ordinary length ellipsizes the meaning out of the "Finish deleting" subtitle (the name came first) | **Fix:** the name goes last, and the text is one of the slot's templates |
| S3 | The Delete row was enabled under `appOutdated`, where the service always refuses, and under `spaceDeleted`, where the dialog asks to delete a copy already gone | **Fix:** held under both; under `spaceDeleted` "Stop syncing" is the one way out and "Finish deleting" follows. Kept enabled under `noAccess` and the quota pause: deleting a copy that will not sync is a legitimate way out |
| S4 | The page holds for the whole deletion, with no bound and no cancel | **Limit, recorded:** the count shows it working; a deletion that outlives the page is a decision of its own |
| S5 | While a deletion runs, "Stop syncing" and the bind row ignore taps but look live | **Fix:** the page's disabled look |
| S6 | The bloc ran a whole engine stop and start for a request that could do nothing (a finish with nothing pending, a delete with no binding or under a pause that forbids it) | **Fix:** the bloc refuses those requests by the page's own rule |
| S7 | The progress line began at "0 items removed" | **Fix:** a plain "Deleting…" at zero |
| S8 | "Finish deleting" named the first pending space and finished them all | **Fix:** with several pending it says how many |
| S9 | German guide body ended on a dangling possessive | **Fix** with S1's rewrite |
| S10 | Not pinned: the Finish subtitle with a long name, the bloc's refusals of S6, the guideline cases for rows below the fold | **Fix:** cases added; the guideline cases scroll to the new rows |

**Fix pass A — the data plane and the engine (2026-11-10; gate from the
lead: analyze clean, the whole suite `+15289 ~17` green, the rules suite
115 green on the emulator, the probe green; uncommitted). It supersedes
the run blocks above wherever they differ.**

- **F1:** under the manual cadence an asked run reads the space once
  before anything else (`SyncEngine._confirmSpace`): missing or marked →
  `spaceDeleted`, a schema above this build's → `appOutdated`, a live
  space or a failed read → the run goes on. A manual "Sync now" costs one
  more read; the automatic cadence is untouched.
- **F9:** `SyncGateway.rowDeleteBatch` = 20 is the default and the ceiling
  of `deleteRows` in both gateways, and what the service asks for every
  table, `content_chunks` included (its page of 50 is gone); a timed-out
  page still halves. The rules suite and the probe delete twenty rows in
  one commit.
- **The order of `deleteCloudCopy` as it now stands:** read (gone →
  unbind, clear any record, return; a newer schema → `appOutdated`,
  nothing changed) → mark → **read again** (F3: gone → unbind and clear; a
  newer schema → `appOutdated` with the mark standing, no record, still
  bound — the engine pauses as `spaceDeleted` and an updated app finishes
  it; a failed re-read leaves the same state, and a second call carries
  on) → **record → unbind** (F6; recording a recorded space changes
  nothing) → empty → remove → clear.
- **F4:** a page refused while emptying is followed by a read of the
  space; gone means another device finished — the record is cleared and
  the call returns normally.
- **F8:** finishing never marks. `finishPendingDeletions` clears a record
  whose space is gone or reads unmarked; only a marked space is emptied
  and removed.
- **F7 (service half):** `start({accountUid, onProgress})` reports the
  documents removed while it finishes the account's marked spaces.
- **F10:** the two calls resolve the document reference inside `_guard`.
- Each of F1, F3, F4, F6, F8 has a case that was seen failing with the
  fix removed (`sync_engine_cadence_test.dart`,
  `sync_space_delete_test.dart`).

**Fix pass B — the bloc, the page, the strings (2026-11-10; gate from the
lead: analyze clean, the whole suite `+15303 ~17` green, `untranslated.txt`
`{}`; uncommitted). It supersedes run 3's block wherever they differ.**

- **One rule for the page and the bloc:**
  `SyncStatus.canDeleteCloudCopy` (`sync_state.dart`) — bound, and the
  pause is none of `accountMismatch`, `appOutdated`, `spaceDeleted`. The
  page adds "signed in" and "no step running"; the bloc refuses a delete
  the rule forbids and a finish with nothing pending before `_step` — no
  engine stop, no start, no emit (S3, S6). Enabled with no pause, under
  `noAccess` and under the quota pause.
- **The words (S1, S9):** the confirmation — "The copy is removed from
  your account for good, and this database stops syncing. Nothing is
  deleted on this device. Your other devices keep what they hold and stop
  syncing too." The guide row says the same of the phone and the other
  devices.
- **"Finish deleting" (S2, S8):** "Partly deleted from your account:
  “{space}”" — the name last, so an ellipsis cuts the name and never the
  meaning (the German is "Cloud-Kopie erst teilweise gelöscht: „{space}“",
  shortened to keep the row's height); with several pending,
  `syncDeleteCloudFinishMany` counts them. Its texts are among its slot's
  templates.
- **Held rows look held (S5):** while a deletion runs, "Stop syncing" and
  the bind row are the page's disabled tile, in the tree and in semantics.
- **Progress (S7, F7):** "Deleting…" at zero; "Sync this database" passes
  its progress to the bloc, which shows the deleting flow while `start()`
  finishes an older deletion, and the step is still announced as a bind.
- **Heights after the wording change** (360 × 780, one height per row
  across idle, busy, held, failed, a forty-character name and the many
  form): 80 dp at 1.0 in the three languages; at 2.0 — en 172 / 172, de
  212 / 212, ro 212 / 172 (Delete / Finish).
- The guideline cases now prove they reached the new rows
  (`meetsAll(judged: …)`), at en 1.0 and de 2.0 dark.

**Known after the build, recorded and not fixed:**

- The page cannot be left while a deletion runs, as with every sync step,
  and a deletion has no cancel (S4, decision c). A deletion that outlives
  the page is a decision of its own.
- A build from before D1 misreads a marked space (F2) — §5.4, §5.8.
- A malformed row diagnosed earlier in one drain hides a space marked
  mid-drain until the next launch (F5).
- While "Sync this database" finishes an older deletion, the count stays
  up until `start()` returns, and a "Finish deleting" row can appear under
  the bind row for the length of that step, moving the Pairing section.
- From a failed sign-out, a refused delete still emits the one account
  state that puts the account back on screen.
- No saved QA flow drives the three new ids; the fake gateway has no
  account, so "another account's delete is refused" is pinned by the rules
  suite alone.
- The status row keeps its carried line ("Up to date") while a deletion
  runs; the Delete row's own line says what is happening.

**Device pass 2 — the final one (2026-11-10, one `qa-runner`, `anta_qa_1`
as A and `anta_qa_2` as B against `tool\firebase\emulators.cmd`, the
cloud-define QA build of the finished tree): green, 11/11.** A (the
`basic.json` seed) and B (empty, bound in one tap) both read "Up to
date"; the emulator held 1 space, 4 folders, 3 notes, 3 chunks, 2 events,
10 categories. B was set to manual ("Syncs when you tap “Sync now”"). A:
"Delete cloud copy" → the dialog with the new body → unbound within two
seconds; all six collections then counted 0; A's browser kept its three
folders. B, untouched, still read its manual line; one "Sync now" and it
read "Paused — the cloud copy was deleted", its Delete row present and
disabled, its folders intact; B's "Stop syncing" asked with the
deleted-copy body and unbound. A's second "Sync this database" created a
new space with the same counts. Only the known `MissingPluginException …
cancel` teardown lines in the logs. Still not run anywhere but in unit
tests: a table of more than twenty rows (no fixture has one) and an
interrupted deletion — the first is step 3 of §5.8.

**Committed `f67c942a` (2026-11-10, pushed), then the debt pass on the
owner's word ("do not leave tech debt") — it supersedes the blocks above
wherever they differ.**

**Debt run 1 — the deletion's long part leaves the foreground
(2026-11-10; gate from the lead: analyze clean, the whole suite `+15315
~17` green).** The recorded limits had one cause: the whole deletion ran
as a step of the page. After the unbind a deletion touches nothing local,
so:

- `deleteCloudCopy()` keeps its local phase exactly (read, checks, mark,
  read again, record, unbind) and then *requests* the owner's run and
  returns. A failure while emptying is never this call's.
- **The run** belongs to the service, one per process: one run at a time,
  in the order asked; asking again for an account that runs or waits
  changes nothing; another account's waits its turn. It re-reads the
  account's records before each one, clears a record whose space is gone
  or reads unmarked, empties and removes a marked one.
- **The status:** `SyncDeletionStatus {accountUid, pending, running,
  removed, failure}` through `deletionStatus(uid)` and the broadcast
  `deletionStatusOf(uid)` (the current value first, then every change).
  `finishPendingDeletions({accountUid})` is a request that returns at
  once; `resumePendingDeletions(uid)` requests the run once per process
  and account when records are pending, so an interrupted deletion
  resumes by itself and a failed one waits for "Finish deleting";
  `deletionRunsIdle()` lets a test await the end.
- `start()` finishes nothing inline any more: a marked space of the
  account is recorded, the run requested, and the bind decided at once
  over the unmarked spaces.
- **F5 closed:** a push denial is diagnosed for every whole batch that is
  denied, not once per drain, so a space marked in the middle of a drain
  pauses as `spaceDeleted` instead of parking rows. **F13 closed:** the
  gate's skip matches the pause its re-read left.
- The fake gateway takes an acting account (another owner's space is
  refused, reads included) and can hold `deleteRows` open; the Firestore
  gateway has one read-back helper for create, mark and delete.

**Debt run 2 — the bloc and the page follow the run (2026-11-10; gate
from the lead: analyze clean, the whole suite `+15333 ~17` green,
`untranslated.txt` `{}`).**

- **Bloc:** a signed-in state follows `deletionStatusOf(uid)` and carries
  it as `SyncSignedIn.deletion` (it replaces `pendingDeletions`); the
  subscription is remade on every account change and cancelled on
  sign-out and on close; `resumePendingDeletions(uid)` is asked when the
  account becomes known. `DeleteCloudCopyRequested` is a short step
  (`SyncBindDeleting()`, no count); `FinishDeletingRequested` is no step —
  it stops no engine and only asks the service, with something pending
  and nothing running. A request the rule forbids is judged before a
  failed sign-out's account is put back, so it emits nothing.
- **Page:** one row, `sharing-sync-finish-delete`, ends the Sync section
  in both states — after "Delete cloud copy" when bound, after "Sync this
  database" when unbound — while something is pending or a run is in
  flight. Running: "Deleting cloud copy", the busy indicator, "Deleting…"
  then "Deleting — N items removed", no tap. Waiting: "Finish deleting",
  the space named last or several counted, a tap; with a failure, the
  error glyph and the failure's words as the row's value. The Delete row's
  subtitle is its description alone. "Cloud copy deleted" is announced
  when a run ends with nothing pending and no failure; a run that fails
  raises the failure snackbar once.
- **The service's run skips what it cannot finish for the record's own
  reason:** a space whose schema is above this build's stays recorded, the
  later records are still finished, and the run ends as `appOutdated`. A
  failure of the link or of the account still stops it at once.
- **Removed with the foreground design:** the count on the deleting flow,
  the deleting flow during "Sync this database", the announcement rule
  written for it, the bloc's pending reads, the page's shared deletion
  slot. `SyncBindFailed.deleting` stays: it words a failed delete *step*
  (offline at the mark, an outdated app, a restore running) on the Delete
  row.
- **Heights** (360 × 780, one height per row across every state and both
  sections; en / de / ro): Delete 80 / 80 / 80 at 1.0, 96 at 1.3, 172 /
  212 / 212 at 2.0; the deletion row 80 / 62 / 80 at 1.0, 96 at 1.3, 212
  at 2.0.
- **What this closed of the recorded limits:** the page is held only for
  the local phase (seconds); the section turns unbound at once, so no
  "Up to date" stands over a running deletion; "Sync this database" no
  longer waits on an older deletion or shows its count.

**Review of the debt pass, first sitting — the run, the pusher, the bloc
(2026-11-10, one `reviewer` probing in a copy).** The run never empties an
unmarked space and never touches the binding, the engine or the local
database. The ledger and what the lead decided:

| Id | Finding | Decision |
| --- | --- | --- |
| G1 | CONFIRMED — a deletion status that arrives while a status read is in flight makes the bloc drop that read (its identity guard), and the real stream always sends one when the account becomes known; the bloc suite's fake stream stayed silent, so no case saw it | **Fix:** a deletion status never invalidates a status read; the fake replays like the real stream |
| G2 | CONFIRMED — a run cut by a sign-out or an account change ends as a refusal and, "once per process and account", is never resumed when the account returns | **Fix:** a run that ended on the account's or the link's moment (a refusal, offline) may be resumed the next time the account is known |
| G3 | CONFIRMED — nothing resumes at launch: only a `SyncBloc` asked, and one exists only once the drawer or the page is opened; the drawer's bloc thereby started a deletion run, against its own "only loads" rule | **Fix:** the resume follows the account from the app's start, outside any bloc |
| G4 | CONFIRMED — between the record and the run's request, the status read "pending, not running" with the previous run's failure | **Fix:** recording a deletion clears the account's last failure |
| G5 | CONFIRMED — F5 was closed only between batches; a space marked during one batch's bisect still parked healthy rows | **Fix:** no row is parked as refused without a read of the space saying it is live at that moment (bounded by the refused-rows cap) |
| G6 | A throw in the run's tail would leave the waiting accounts "running" for the life of the process | **Fix:** the run loop survives any throw |
| G7 | A failed first read of the status left "Finish deleting" unavailable | **Fix:** the first value never fails the stream |
| — | `start()` failed a bind when recording a marked space failed; a comment claimed synchronous delivery; `pending`'s doc still said "this install began" | **Fix** |
| — | The fake gateway has no signed-out state and spends a scripted failure before its owner check | **Fix** |

**The saved `sync` suite (2026-11-10; one implementer who wrote the flows
and ran them on `anta_qa_1`): `qa pass sync -d emulator-5556`, 5/5 green
twice, each against a freshly started emulator suite, 36–38 s a pass.**

- **The seam:** on a QA build pointed at the Firebase emulator
  (`QaMode.useFirebaseEmulator`) a fresh launch signs out once
  dependencies exist (`QaBootstrap.applyResetSignOut`), so a reseeded app
  opens signed out. The hand-driven passes each met a session that had
  survived the reseed. Five cases in `test/qa/qa_bootstrap_test.dart`.
- **The suite** (`tool/qa/flows/sync/`, `reseed=suite`, `shard=no`, a
  prelude that fails at once on a cloud-off build): `00_bind`,
  `01_manual_cadence`, `02_stop_and_merge` (through the picker),
  `03_delete_cloud_copy`, `04_bind_again_and_delete` — it ends with no
  space left, so the next pass meets the same start. "Up to date" is read
  off the status row's own words. Its note:
  `.claude/skills/qa-emulator/references/sync-pass.md`.
- **Measured on the guest:** the section reads unbound about half a second
  after the delete is confirmed, and the deletion row is gone about half a
  second after that.
- **What the device showed that no test had** (each decided): the deletion
  row opened as "Finish deleting — Partly deleted…" for a moment (G4 — the
  fix is in the service); under the manual cadence a waiting change was
  not counted on the status row until a run (the outbox trigger emitted
  nothing under manual — fixed in the engine); every Firestore transaction
  logs a `MissingPluginException … cancel` from the plugin's own stream,
  which buries real lines in `errors` (the harness filters that one line);
  the cadence switch's id sits on the row, not on the switch, so a flow
  reads its subtitle (left: the row is a container by the kit's rule).
- Not covered by one guest: a second device (R10), an interrupted
  deletion, a table of more than twenty rows.

**Review of the debt pass, second sitting — the page, the strings
(2026-11-10/11, the same `reviewer`).** One height holds for the deletion
row in every state, both sections, three scales, three languages and both
phone sizes (real fonts); four of five reverted behaviours turned a case
red. The ledger and what the lead decided:

| Id | Finding | Decision |
| --- | --- | --- |
| H1 | During the delete step the row arrived in the bound section, held and worded "Partly deleted…", then spun beside the spinning Delete row | **Fix:** with H2 — the row leaves the Sync section |
| H2 | The row comes and goes at the end of the Sync section, so Pairing shifts by 62 to 212 dp each time — against the page's own rule that nothing moves | **Fix:** a deletion has its own section, last on the page, as "held back" items have; a deletion that ends while the page is open stays in place as "Cloud copy deleted" until the page is opened again |
| H3 | "Finish deleting" could be tapped when only an app update can finish it (the last run ended `appOutdated`) | **Fix:** held then, its words saying to update |
| H4 | A delete whose space was already gone ends without a word to a screen reader | **Fix:** announced at the step's end when no run was needed |
| H5 | A failed sign-out hid the row though the account is still signed in | **Fix:** drawn for every state that still carries the account |
| H6 | Words: "Deleting…" under the title "Deleting cloud copy" repeats it; the Romanian "Șters doar parțial" is the wrong gender for the copy | **Fix:** the subtitle counts ("Starting…", then "N items removed"); "Ștearsă" |
| H7 | Not pinned: the row under the delete step, the held row in the bound section, the heights at 412 × 915, the guideline cases for the held row, "another account's status says nothing"; the bloc suite's fake stream does not replay as the real one does | **Fix:** cases added; the fake replays |

**Fix pass C1 — the run, the engine, the start (2026-11-11; gate from the
lead: analyze clean, the whole suite `+15352 ~17` green). It supersedes
"Debt run 1" and "Debt run 2" wherever they differ.**

- **The resume is the app's, not a bloc's (G3, G2):**
  `SyncSpaceService.followAccounts(Stream<String?>)`, called from
  `configureDependencies` right after the engine starts when sync is
  available, follows the account stream for the life of the process; the
  stream's replay of the current account is the resume at launch.
  `resumePendingDeletions` is gone and the bloc only listens. **The rule:**
  when an account becomes known, its run is requested if something is
  pending and either no run was asked for it in this process or its last
  run ended on the moment — a refusal (signed out or another account under
  it) or offline. A run that ended on the quota, an outdated app or an
  unknown failure waits for "Finish deleting" or the next process. With
  nothing pending it costs one read of the install-wide record and no
  network call.
- **No moment that reads as a failed deletion (G4):** from the record on,
  the account's status reads running with no failure; a failed unbind
  settles it pending, not running, with no failure.
- **G6, G7:** the run loop survives a throw anywhere in a run and the
  accounts behind it still run; `deletionStatusOf` never fails its first
  value. `start()` binds all the same when a marked space cannot be
  recorded.
- **G5:** inside a bisect, a row is parked as refused only after a read of
  the space says it is live at that moment — marked or gone pauses as
  `spaceDeleted` with nothing parked. A drain with two refused rows reads
  the space three times (the batch, then each row); bounded by the rows
  parked.
- **The manual cadence shows what is waiting:** a write to the outbox makes
  the engine emit its status under manual too — no run, no timer.
- The fake gateway has a signed-out state and checks the owner before it
  spends a scripted failure.

**Fix pass C2 — the bloc and the page (2026-11-11; gate from the lead:
analyze clean, the whole suite `+15383 ~17` green, `untranslated.txt`
`{}`). It supersedes "Debt run 2" wherever they differ.**

- **G1:** a deletion status that arrives while the sync status is being
  read no longer costs that read — the bloc remembers which state a
  re-stamped state came from, and the read lands on it. The bloc suite's
  fake stream now replays like the real one, and a case holds the reader
  open across a status.
- **The deletion has its own section, last on the page (H1, H2, H5):**
  "Cloud copy deletion" (`syncDeletionSection`), after Pairing and after
  the held-back section, for every state that still carries the signed-in
  account (a failed sign-out included). Both shapes of the Sync section
  end as they did before a deletion row existed, and during the delete
  step the Delete row spins alone. Its one row, `sharing-sync-finish-delete`:
  - running — "Deleting cloud copy", the busy indicator, "Starting…" then
    "N items removed", no tap;
  - waiting — "Finish deleting", "Partly deleted from your account:
    “{space}”" or the count of several, a tap; held while a step runs;
  - failed — the error glyph, the failure's words as the row's value;
  - held until an update (H3) — after a run that ended `appOutdated`:
    "Update ANTA to finish" (`syncDeleteCloudFinishUpdate`), no tap;
  - ended while the page is open — "Cloud copy deleted", muted, the check
    glyph, the count beneath, no tap; gone at the next open.
  Nothing above the section moves when it appears, changes or ends
  (eighteen cells: three languages, three scales, both phone sizes).
- **H4:** a delete that needed no run — its space already gone — is
  announced at its step's end; a run's end is announced once, as before.
- **Words (H6):** the progress line counts and never repeats its title;
  the Romanian "Ștearsă doar parțial…".
- **Heights** (real fonts, one height across every state, bound, unbound
  and a failed sign-out; en / de / ro): at 360 × 780 — 80 / 62 / 80 at
  1.0, 96 / 96 / 122 at 1.3, 212 / 176 / 212 at 2.0; at 412 × 915 — 80 /
  62 / 80, 96 / 73 / 96, 136 / 176 / 212.
- **Small:** `SyncSpaceService.dispose()` releases the account follower
  when dependencies are reset (`test/core/di/deletion_follow_test.dart`
  pins the start-up wiring and the release).
- Chosen in the build: the section is absent for the length of a delete
  step, so one already on screen leaves and returns with the step — it is
  last, so nothing moves; a failed sign-out draws the last status the
  account had.

**Closing review of the two fix passes (2026-11-11, a fresh `reviewer`
probing in a copy).** No data-loss or persisted-data problem; the run
never deletes from a space that is not marked. G3, G6, H2, H3, H4, H6 and
the `start()` and fake-gateway rows closed outright; the remainders and
what the lead decided:

| Id | Remainder | Decision |
| --- | --- | --- |
| K1 | CONFIRMED — G5's read before a park also ran for every *retried* park, which the refused-rows cap does not count: fifteen refused rows cost sixteen reads on every start and every "Sync now" | **Fix:** a retried park is not read for again — its refusal is known; a fresh row still is |
| K2 | CONFIRMED — G1 held for one re-stamp only: a status read begun on a re-stamped state was dropped by the next re-stamp (a same-account auth emission makes it reachable) | **Fix:** the guard compares the states' origins; the bloc suite's auth fake replays as the real stream does |
| K3 | CONFIRMED — under a failed sign-out the deletion row froze: the bloc emitted no status there and the page drew the last one | **Fix:** every state that carries the signed-in account carries its deletion status |
| K4 | An account that returns while its run is still ending on the refusal is not resumed (the resume was asked while the run was in flight) | **Fix:** a resume asked during a run is owed at its end when the run ended on the moment; the fake judges the owner when a held call is sent, as Firestore does |
| K5 | Under the manual cadence every outbox write queued a whole status read | **Fix:** at most one emit waits behind the one in flight |
| K6 | A deletion section already on screen left and came back with a delete step, shifting a page scrolled to its end | **Fix:** a section that is on screen stays, held, through the step |
| K7 | `start()` recording a marked space showed the "pending, not running" moment G4 removed elsewhere; a failed record lost the previous run's failure | **Fix:** one record-and-request path; a failed record restores what was there |
| K8 | `dispose()` left a run in flight; the follow test registered its own service instead of the app's registration; a doc line overstated what the follower takes on; the done row counted only the last run | **Fix:** a disposed service ends its run at the next call; the test uses the app's registration; the line says when; the done row carries no count |
| K9 | G7: after a first read that failed, "Finish deleting" stays hidden until the page is opened again | **Accepted:** a new listener reads again, and the read fails only when the install-wide record cannot be read at all |

**The saved suite after the rework (2026-11-11, one implementer on
`anta_qa_1`): `qa pass sync` 5/5 green twice (44–45 s), each against a
freshly started emulator suite; `qa pass settings` 21/21 on a normal QA
build.** `03_delete_cloud_copy` and `04_bind_again_and_delete` wait on the
row ending as "Cloud copy deleted" and on the page, opened again, showing
no deletion section; `01_manual_cadence` makes a folder with the switch
off, reads "1 change waiting" with no run started, and sends it with "Sync
now". On the guest the row read "Deleting cloud copy — 5 items removed" a
quarter of a second after the confirmation and was never seen as "Finish
deleting". The harness's `errors` hides the plugin's known
`MissingPluginException … cancel` line (34 lines a flow before; a count
line now).

**Fix pass D1 — the service, the pusher, the engine (2026-11-11; gate
from the lead: analyze clean, the whole suite `+15391 ~17` green).**

- **K1:** a retried park is parked again without a read — fifteen refused
  rows read the space sixteen times on the first sync and once on each
  later one (it was sixteen each time). A fresh row still gets its read.
- **K4:** a resume asked while the account's run is in flight is owed and
  spent at that run's end — only when it ended on a refusal or offline and
  the followed account is still that one. The fake judges the owner when a
  held call is sent.
- **K5:** under the manual cadence at most one status emit waits behind
  the one in flight — two status reads for thirty writes, the last showing
  thirty waiting.
- **K7:** one path records a deletion and requests its run
  (`_recordAndRequest`), for the delete and for `start()`; a record that
  cannot be written puts the previous run's state back, its failure
  included.
- **K8:** a disposed service ends its run at the next call and publishes
  nothing after.

**Fix pass D2 — the bloc, the page, the tests (2026-11-11; the final gate
from the lead: `dart analyze lib test` and `dart analyze tool test_driver`
clean, the whole suite `+15400 ~17` green, `untranslated.txt` `{}`).**

- **K2:** the status-read guard compares the states' origins, so a read
  begun on a re-stamped state survives every later re-stamp; three cases
  hold a read across a re-stamp and show it still never lands on another
  account's state, on a newer flow or after close. The bloc suite's auth
  fake replays the current account to a new listener, as the real stream
  does.
- **K3:** `SyncFailure` carries the account's deletion status too
  (`deletion`, `withDeletion`); the bloc follows and stamps it there, the
  page reads the status from the state alone, and a run's end is said — or
  its failure shown — under a failed sign-out as when signed in. "Finish
  deleting" from a failed sign-out is judged on the live status and emits
  nothing by itself.
- **K6:** a deletion section on screen when a delete step begins stays
  through it, its row held; one that would first appear because of that
  step waits for its end. A page scrolled to its end keeps its offset.
- **K8:** the ended row is its title alone ("Cloud copy deleted"), its
  slot keeping the height; `registerSyncSpaceService` is the app's own
  registration and the follow test goes through it, so losing its
  `dispose:` turns the case red.
- The three `curly_braces_in_flow_control_structures` infos of
  `test_driver/qa_agent.dart` and `tool/release/src/locks.dart` are gone.
- Noticed and left, older than this work: a bloc reads the sync status
  twice when it is created — its own load, then the account stream's
  replay of the same account. Two local reads, no network.

**The final device pass (2026-11-11, one `qa-runner`, the finished tree's
cloud-define build on `anta_qa_1`, a freshly started emulator suite):
`qa pass sync` 5/5 green in 35 s.** In `03_delete_cloud_copy` the
deletion row was there 408 ms after the confirmation, the Sync section
read unbound on the next check (52 ms), and the row read "Cloud copy
deleted" 362 ms later; the page opened again showed no deletion section.
The guest was left on the normal QA build.

---

## 6. Group D — deletion

- **D2 — Delete my account.** One action on the Account row: every space
  of the account (D1's operation, bound or not), the pairing ended and the
  account's own name and photo emptied from the pair document
  (`rewritesOwnProfile` already allows nulls), a pending invite deleted,
  then the sign-in account itself, then sign-out. Local data stays.
  **The order is the design:** data first, the account last — a deleted
  account that signs in again is a new uid and could never reach what the
  old one left. Firebase asks for a fresh sign-in before it deletes an
  account, so the flow re-authenticates with Google first. The question
  left open here — an ended pair document keeps both uids for ever — is
  answered in §6.1 g: a member's account deletion removes its pairs.
  **DONE 2026-11-11, §6.1.**
- **D3 — Deletion from outside the app.** A page (the project's free
  Hosting domain) that says how to ask, and the operator's runbook:
  `firebase firestore:delete --recursive` on `users/<uid>` and the
  console's user delete. Google Play requires the link for any listed app
  that lets people create accounts; nothing else does.

### 6.1 D2 — Delete my account (design)

Decided and built in the session of 2026-11-11 (the owner: "implement the
roadmap, make the decisions that are mine to make, ask the rest"). The
bullet above is the plan it started from; this section states the design
as built, and its last block the history.

**What the user gets.** In Settings → Sync & sharing the Account section
has a second row, **Delete account**, drawn destructive — always there
under the account, held while nobody is signed in, so signing in and out
moves nothing. It asks once: every cloud copy of the account is deleted
for good, pairing ends, the account itself is removed, nothing on this
device is deleted. On yes Google asks for the account once more; then
every cloud copy is marked, this database stops syncing, and the page is
free again. The emptying runs in the background in the page's last
section — "Deleting account", a count — and when the last copy is gone the
pair and invite documents are removed, the sign-in account is deleted and
the page reads signed out, with "Account deleted" said once. A deletion
that could not finish — the app closed, the link lost, the fresh sign-in
gone stale — waits as "Finish deleting account", and its tap asks Google
again. While an account is going, "Sync this database" is held; signing
out is the way to keep the account, and the sign-out's question says so.

**Decisions taken by the lead (lettered, reversible before a release).**

- **a. Scope.** On the server: every space of the account, bound on this
  install or not (D1's operation, once per space); every pair document the
  account is a member of; every invite it created or redeemed; the sign-in
  account. On any device: nothing.
- **b. The order is the design.** Spaces, then pairs and invites, then the
  account — a deleted account that signs in again is a new uid and could
  never reach what the old one left. The account is deleted only after a
  listing of its spaces reads empty, and three things keep that true to
  the last moment: from the record on, this install refuses every bind of
  the account (`SyncBindFailure.accountDeleting` — a copy made now could
  land after the last listing); a `deleteAccount` call still marking
  spaces holds the run's close; and the closer asks once more right before
  the account's own delete (`stillWanted`), where a space of the account
  recorded meanwhile, the deletion given up, or the session changed each
  mean no.
- **c. A fresh sign-in, asked first, and a window.** Firebase deletes an
  account only minutes after a sign-in (about five as observed; its
  documentation names no figure), so Google is asked right after the
  confirmation, before anything is touched; another account
  chosen there is refused (`SyncBindFailure.otherAccount`). Each
  `deleteAccount` call hands the run it starts or joins a licence dated at
  the call, and the run may begin the account's end only within four
  minutes of it (`SyncSpaceService.accountCloseWindow`): the pairs and
  invites go before the account, so past the window they are left alone —
  sharing is never ended for an account the server would then refuse to
  delete. A run with no licence — resumed at a start-up, asked by "Finish
  deleting", started by a later cloud copy's deletion — finishes the
  copies and waits as "Finish deleting account", whose tap signs in again;
  so does one whose window passed, with no failure shown. An attempt takes
  back only the licence it began under, never a later call's.
- **d. No undo for the copies; a way out for the account.** A marked copy
  is gone (D1 c). The account's own deletion is dropped by signing out —
  the sign-out confirmation says so, and it is dropped before the sign-out
  itself, whether or not that then lands, so a run in its last steps
  cannot finish them meanwhile — and by another account signing in; the
  copies already marked are still removed.
- **e. D1's run carries it.** One install-wide record more (the uid whose
  account is being deleted, `SettingsKeys.syncPendingAccountDeletion`),
  one field more on `SyncDeletionStatus` (`account`), one step more at the
  end of the account's run (`AccountCloser`). No second queue, no second
  status stream, no second section on the page.
- **f. An unbind releases the account's rows, and a bind takes up every
  row.** `owner_id = <the account that bound>` becomes NULL on every synced
  table when a database is unbound — "Stop syncing", a restore, the heal,
  a deletion — and a bind owns every row not already the binding
  account's (`owner_id IS NOT ?`), so one left naming an earlier account
  by an older build or an import is uploaded too. An unbound database
  holds only rows that are simply "mine"; before this a person returning
  under a new uid (which a deleted account always is) or a second Google
  account left every old row out of the next bind's upload, and with
  sharing those rows would read as another account's. Only the binding
  account's rows are released: a row any other uid owns is somebody
  else's. (Imports still store an archive's `ownerId`; R9 settles that
  with the sharing build, and a partner's rows are purged at an unbind
  there, before this release.)
- **g. Pair documents are removed, not only ended.** The active pair is
  ended first — the partner's device hears a tombstone — then every pair
  document of the account is deleted. The rules gain: a member may delete
  an ended pair; a missing pair reads as "not found" instead of "denied"
  (the invites' precedent) and may be "deleted" by anyone signed in, so
  two deletions walking the same pair never refuse each other. A refused
  `endPair` is read back before it counts: the partner may have ended or
  removed the pair since it was listed. The deleting device forgets its
  own pairing first (`PairingService.forget`), so it never tells itself
  the partner ended sharing. A partner's device raises the ended notice
  when its pair reads gone — at a reconcile, or when its listener hears
  "no document" after a live one (never before: a pair just written
  reads as none until its server time arrives) — since only an account's
  deletion removes one. Accepted: another device of the deleted account
  blames the partner for the hour its session outlives the account.
- **h. Invites.** The rules gain: an account may list the invites it
  created or redeemed, and delete them — one already gone goes through.
  Codes stay impossible to enumerate — a listing is only ever one's own.
- **i. The account's other devices pause.** Their space is marked, then
  gone ("Paused — the cloud copy was deleted"); their session ends when
  its token does, within the hour, and reads signed out. Accepted limit:
  inside that hour such a device — unlike this install (b) — could still
  create a space, which nobody could reach afterwards.
- **j. No wire bump, no migration.**
- **k. Nothing this final starts unseen.** The step begins only for the
  account the prompt confirmed and only from a page still there: an
  account that changed or signed out while Google's prompt was up, or a
  page left meanwhile, starts nothing. The account's own delete is bounded
  (30 s, then "offline"; the deletion waits), and Google's `disconnect`
  after it is best-effort and never awaited.
- **l. The words follow what happened.** A failure with no better reason
  says "The account couldn't be deleted", never "Sync couldn't be turned
  on"; the done row says "Account deleted" only when the run the page
  last saw was deleting the account — a deletion given up ends as its
  copies' do.

**The protocol.** The bloc re-authenticates (`AuthService.reauthenticate`),
then runs one short step with the engine stopped
(`SyncSpaceService.deleteAccount`): refused while a restore runs; the
account's spaces listed — a failure here changes nothing, and so does a
space a newer build wrote to (`appOutdated`); the account deletion
recorded; the space this database syncs with, if it is the account's,
marked, recorded and unbound first, as "Delete cloud copy" does less its
second read — a newer build's write between the listing and the mark is
met by the run, which passes that space over with the database already
unbound; then every other unmarked space marked and recorded, one by one,
so a failure midway leaves marks and records in step; the account's run
requested and licensed. The run empties and removes the spaces as D1's
does and then, when it holds a licence inside its window (c) and a
listing reads empty, closes the account (`AccountCloser`): the open
database's pairing forgotten, pairs ended and deleted, invites deleted,
the caller asked once more (b), the sign-in account deleted, the record
cleared, the account named on `accountsDeleted`. A space found at that
listing — made or marked elsewhere since — is recorded when marked and
left for the next tap when not: only a person marks. What reaches a run
while it judges the account's end — a space recorded, a later call's
licence — is looked at again before the run ends.

**Rules** (`firestore.rules`; additive, deployed before the build):

```
match /pairs/{pairId} {
  allow get: if signedIn() && (resource == null || uid() in resource.data.members);
  allow list: if isMember();
  allow delete: if signedIn() && (resource == null
      || (uid() in resource.data.members && resource.data.status == 'ended'));
}
match /invites/{code} {
  allow list: if signedIn() && (resource.data.creatorUid == uid()
                                || resource.data.redeemedBy == uid());
  allow delete: if signedIn() && (resource == null
      || resource.data.creatorUid == uid()
      || ('redeemedBy' in resource.data && resource.data.redeemedBy == uid()));
}
```

**Must not change.** D1's protocol, statuses and strings; pairing's
create, redeem, reconcile and unpair; the engine; `owner_id` NULL meaning
"mine"; backups; the page's one-height rows.

**What only the owner does.** The rules deploy before the build installs
(the same command as §5.8) — without it the account's end stops as
"permission denied" at its pairs, with every cloud copy already gone and
the account waiting. On the phone, once, with a throw-away Google
account: sign in, sync a database, pair, delete the account — the console
then shows no `users/<uid>` documents, no pair, no invite, and the user
gone from Authentication. That is the one thing the emulator cannot
prove: Firebase's fresh-sign-in window, which the Auth emulator does not
enforce.

**As built (2026-11-11).** One session on Fable, the build inline.

- *Code.* `AuthService.reauthenticate` / `deleteAccount` (+
  `OtherAccountException`, `RecentSignInRequiredException`);
  `PairingGateway.findPairs` / `deletePair` / `findOwnInvites`;
  `PairingService.forget` and the listener's "no document" path;
  `AccountCloser` / `PairedAccountCloser`
  (`lib/services/sync/account_closer.dart`); in `SyncSpaceService`
  `deleteAccount`, `abandonAccountDeletion`, `accountsDeleted`, the
  licence and its window, the bind refusal; `SyncSpaceRegistry`'s account
  record; `SyncBindingService`'s release and take-up (f); the bloc's
  `DeleteAccountRequested` / `SyncAccountDeleted`, `SyncAccountDeleting`,
  `SyncSignedOut.accountDeleted`; the page's row, dialog, deletion-row
  wording and snackbar; fourteen strings in en/de/ro; the guide row
  "Delete account"; `firestore.rules`.
- *Reviews.* The lead's own pass replaced a per-process "may close" set
  with the per-run licence. One independent review (the `reviewer` agent
  on Fable) returned twenty findings, no blocker; nineteen were addressed
  — the bind refusal, the abandon before the sign-out and the closer's
  last question (b, d), the take-up at a bind (f), `forget` and the
  read-back of a refused `endPair` (g), the deletes of what is already
  gone (g, h), the bound on the account's delete (k), the window (c), the
  marking guard and the second look (b), the wording (l), the suites and
  this record — and one accepted: the record of an account already gone
  can remain when the process dies between the account's delete and the
  record's clearing; nothing reads it as a deletion and any sign-in drops
  it. The fix pass then found four of its own: a later call's licence
  could be taken back by an older attempt, the window was dated at the
  end of a slow marking instead of the call, a space recorded while the
  closer worked did not hold the account's delete, and the done row could
  read "Account deleted" after a deletion given up.
- *Gate.* `dart analyze lib test tool test_driver` clean; the whole suite
  `+15822 ~17`; the rules suite 124 of 124 against the emulator. Suites:
  `account_closer_test` (21), `sync_account_delete_test` (38, its guards
  checked by mutation), the bloc's group (149 in the file), the page's
  group (293 in `sync_section_test`), `pairing_service_test` (28),
  `sync_binding_service_test` (36), the registry's (22).
- *Not proven here.* Firebase's fresh-sign-in window and the real Google
  prompt (the owner's phone check above); a device pass of the flow waits
  for the two-guest suite (R10), which carries a "delete account" flow.

---

## 7. Group E — shared events

One design record before E1 covers the group: the event half of the old
Phase 03, rewritten against the engine as built, on the readiness
decisions D1, D16, D17 and D18.

- **E0 — Pairing proven.** The live database was created on 2026-11-05;
  pairing shipped on 2026-08-17 and no record shows it run against the
  live project since. Two real accounts: invite, redeem, each sees the
  other, either ends it. Code only if it fails.
- **E1 — A shared event shows on the partner's calendar, read-only.** A
  "Share with *partner*" switch in the event editor, shown only when
  paired; the partner sees the event marked as the owner's and cannot edit
  it. Needs: a top-level `sharedWith` on the event's document (wire 47, the
  rules' envelope check, a read rule for the grantee on the
  `calendar_events` collection group, a collection-group index);
  `calendar_events.shared_with` locally (v52) and rows stamped with their
  owner at write (a row made after the bind keeps `owner_id` NULL today —
  Phase 02 record §8); a reader in the engine for the partner's shared
  events beside the bound space, with its own cursor, storing them under
  the partner's `owner_id` and taking only the active partner's — so a
  stranger who writes my uid into their event is never shown; the switch,
  the owner mark, the read-only guard; a fallback for an event whose
  custom category the partner does not have.
- **E2 — Stopping a share.** The switch off, the event deleted, the pair
  ended, the owner's cloud copy or account deleted: the event leaves the
  partner's calendar. The hard part: a query cannot report a document that
  left its result, so the reader needs a reconcile of the whole shared set
  on a revision stamp, or a notice feed. Decision: the partner keeps
  nothing, or keeps a personal copy.
- **E3 — Recurring events whole.** Skipped days and per-day descriptions
  are event data and follow the event (readiness D18); their documents
  need the same grant, kept in step when the share changes.
- **E4 — Personal layers.** The partner's own presence and own alert
  definitions on a shared event live in the partner's space, keyed by the
  event's id (D18); the partner's devices arm the partner's alerts and
  never the owner's. Decision: whether reports and analytics count shared
  events.
- **E5 — The partner may edit.** A consent switch per person — the pair
  document already carries it — a rules write clause for the grantee, the
  grantee's edits routed to the owner's space (the gateway refuses an
  envelope whose owner is not the space's, `sync_gateway.dart:276`),
  last-writer-wins, an "edited by" mark.
- **E6 — A whole category.** Every event of a category, future ones
  included.
- **E7 — "New from my partner".** A mark or a line when shared events
  arrive or change, at open or within seconds while both apps are open.
  Nothing runs in the background: a closed app learns at its next open
  (P6 is the push).

---

## 8. Group N — shared notes

One design record before N1, the folder half of the old Phase 03.

- **N1 — A shared folder, read-only.** "Share with *partner*" on a folder
  shares its subtree; the partner sees folder, notes and text with an
  owner badge and search finds them. Needs: the grant on folder and note
  documents, kept in step when a note moves in or out; read access to note
  text — chunks are addressed by hash per space
  (`content_chunks/{sha256}`), so the rule lets the partner fetch a chunk
  by its hash without listing them; the reader for notes (the fetch of a
  manifest's chunks exists, `readRows`); a read-only editor for a foreign
  note; the settings that are note data (`money_currency`, readiness D10);
  a decision on a shared note's counters.
- **N2 — Stopping a folder share.** E2's endings, plus a note moved out of
  the shared folder.
- **N3 — The partner may edit notes.** Whole-note last-writer-wins with
  conflict copies across two accounts (decision: in whose space the copy
  is filed), and the open-editor rule (Phase 02 record §3.9) for a foreign
  note.

---

## 9. Group R — the rest of the findings

- **R1 — Region. Decided 2026-11-10: `eur3` (§11 O2). The runbook, run by
  the owner with the phone in hand, from `frontend/anta`:**
  1. Every device runs the D1 build. A fresh export of the phone
     (Settings → Backup), kept as a file: between steps 3 and 6 the phone
     is the only copy.
  2. "Stop syncing" on every device, the phone last. Local data stays.
  3. `firebase firestore:databases:delete "(default)" --project
     alexs-note-tracking-app` — it asks once. Every space, pair and invite
     goes with it; the app holds none of them as its only copy.
  4. `firebase firestore:databases:create "(default)" --location eur3
     --project alexs-note-tracking-app`. If it answers that the name is
     still in use, wait a few minutes and run it again. Check: `firebase
     firestore:databases:get "(default)" --project alexs-note-tracking-app`
     reads `Location eur3`.
  5. `firebase deploy --only "firestore:rules,firestore:indexes" --project
     alexs-note-tracking-app` (the gitignored `firebase.json` must carry its
     `firestore` block).
  6. The phone: "Sync this database" — it creates the account's first
     space in the new database and reads "Up to date". Then the second
     device: "Sync this database"; with data of its own, "Download … into
     a new database", never Merge, as the Phase 02 record's §7 says.
  7. A pair made before the move is gone with the database: pair again
     (E0 is that check anyway).
  8. Last, and only after step 4's check read `Location eur3`: set
     `CloudDataRegion.current` to `europeanUnion`
     (`lib/constants/cloud_data_region.dart`), build, and install that
     build on every device. The app cannot ask the server where its
     database is, so the "Where your data is stored" notice (R2) says what
     this constant says; until this step it says "the United States",
     which is true until step 3.
  Cheap while one account's space is all there is; after the partner's
  first upload it is two people's upload and a second pairing.
- **R2 — "Where your data lives." DONE 2026-11-12.** A few true sentences
  on the Sync & sharing page and in the guide. *As built:* a **Privacy**
  section after Pairing — in every state but the one where sync does not
  exist — with one row, "Where your data is stored"
  (`SemanticsIds.sharingDataNotice`), its description the short answer and
  its tap the whole one, a notice to read and close
  (`AppDialogs.action`, now scrollable and, here, dismissible). Six
  paragraphs (`dataNoticeParagraphs`, `lib/utils/data_notice.dart`): notes,
  events and counters live on the device and leave it only when a
  database syncs; a synced database keeps a copy in Google's cloud, in the
  place `CloudDataRegion.current` states (two whole sentences per
  language, never a spliced place name); the copy is encrypted in transit
  and at rest but not end-to-end, so whoever runs the cloud project can
  read it; signing in keeps the Google name, e-mail address and profile
  picture with the account — in the United States whatever the database's
  location, because Firebase Authentication runs only there (Firebase's
  "Privacy and Security" page, read 2026-11-12); a paired partner sees
  the name and picture and nothing else unless it is shared; "Delete
  cloud copy" and "Delete account" remove it. The guide's sync page ends
  with a row of the same name. Decisions: a section of its own rather
  than a row inside Sync, so no existing row moves and the two sections
  that come and go stay last; the place is a constant, flipped by R1's
  step 8, because no client call reads a database's location; the partner
  sentence is worded to stay true once a share switch exists. Suites:
  `test/utils/data_notice_test.dart` (three languages, both places),
  `sync_settings_page_test.dart` (group "where your data is stored"),
  `app_dialogs_test.dart` (the notice at 2.0 in German), the guide's.
- **R3 — Storage stops growing.** Replaced note chunks are never removed
  and tombstones are never purged (Phase 02 record §8, readiness §8). A
  chunk collector and a tombstone purge after every device has seen it;
  D1's rule is widened here.
- **R4 — A second account on one phone. Decided 2026-11-10: accepted, not
  built (§11 O4).** It sees every local row, and its edits wait in the
  queue and upload into the first account's space when that account
  returns (`sync_engine.dart` `_gate`, `crdt_write.dart` `enqueue`). One
  phone is one person; tying a database to its account is the build if a
  phone is ever shared.
- **R5 — Two app versions.** A shared row written by a newer wire is
  skipped with "update ANTA", never parked in silence; the reader checks
  the partner space's `schema`. Decided inside E1. No global
  minimum-version gate exists (`kAppVersion` is the constant `1.0.0`).
- **R6 — A phone I do not hold.** No crash reporting; a revoked session
  reads as "offline" (Phase 02 record §8). A "copy diagnostics" action, or
  Crashlytics.
- **R7 — iPhone.** Deployment target 15.0 and the URL scheme are in; it
  has never been run; the App Store asks for Sign in with Apple beside
  Google and for D2.
- **R8 — Desktop sign-in.** None: `google_sign_in` has no desktop
  implementation (readiness §8: the official plugin on macOS, a loopback
  flow on Windows).
- **R9 — Backups with shared rows.** `owner_id` travels in backups, and a
  restore re-creates foreign notes and folders as copies under fresh ids
  that never meet their originals (readiness §8, F6). Decide: read-only
  copies, re-homed, or dropped.
- **R10 — A saved two-guest suite.** The saved `sync` suite (the debt
  pass of D1) drives one guest: bind, sync, stop and merge, delete the
  cloud copy. Sharing is proven on two phones at once, and the harness
  runs one device per pass (`qa pass … -d`): a suite whose flows name
  their guest, or a pass that alternates two, so E1's device pass is one
  command and not a hand-driven run. Tooling only.

---

## 10. Group P — only for a public listing

- **P1 — App Check** with Play Integrity. The rules cap neither documents
  nor spaces per account; one account can fill the storage or burn the
  day's quota for everyone.
- **P2 — The paid plan.** One free quota for the whole project: 50,000
  reads and 20,000 writes a day, 1 GiB; an estimate from the Phase 02
  record's cost model is 100–200 active users a day. The paid plan has no
  hard spending cap, so it comes with a budget alert and P1; it also
  brings server functions and backups.
- **P3 — Privacy policy, terms, the Play data-safety form.**
- **P4 — Console checks.** Whether Google sign-in is open beyond a test
  list; whether the Play signing key's fingerprint is registered (a store
  install fails sign-in without it).
- **P5 — End-to-end encryption.** A wire change and a re-upload of every
  space; with sharing, keys must pass between partners. A decision before
  it is a slice.
- **P6 — Push.** FCM through the Cloudflare Worker of
  `cloud-sync-connections-design.md`.
- **P7 — More than one partner.** The connections design.

---

## 11. Decisions for the owner

- **O1 — D1 as §5 describes it?** **Yes — the owner, 2026-11-10** ("Yes,
  build it": the cloud copy first, the account as the slice after).
- **O2 — Region (R1).** **A:** recreate the database in the European
  Union before the partner's data arrives. **B:** stay in `nam5`. A is the
  only choice on this page that cannot be made later without every device
  uploading again. **A — taken by the lead on the owner's word ("make the
  decisions", 2026-11-10): the European Union, location `eur3`,** the
  multi-region that `nam5` is in the United States. Both people are in
  Europe, the data is personal (training, fasting, money), and today the
  move costs one upload from one phone. The move itself deletes the live
  database, so it is run with the owner's phone in hand — R1 holds the
  runbook — and was not run by the session that decided it.
- **O3 — The partner's phone.** **Android — the owner, 2026-11-10.** R7
  (iPhone) stays a later slice and blocks nothing here.
- **O4 — A second account on one phone (R4).** **A:** accept; each person
  has a phone. **B:** tie a database to its account. **A — taken by the
  lead on the owner's word, 2026-11-10.** One phone is one person: a second
  Google account on it is the same person's, the page already says "Paused
  — this database syncs with another account", and nothing is re-owned.
  R4 is not built; it would come back only if a phone were ever shared
  between two people.

Each slice's own decisions are lettered in its design when it starts.

---

## 12. Must not change

Across every slice: local SQLite stays the source of truth; a row lives
once, in its owner's space; tombstones are upserts; the `pairs` and
`invites` consent plane as shipped; `owner_id` NULL means "mine"; the
rules deploy before the build that needs them and never break a build
already installed; a wire change raises `syncSchemaVersion` and the
`_wireKeys` snapshot together; backups stay importable; the on-disk
`gym_notes` directory.

---

## 13. How to run this

- This record was written on Fable. A slice runs as the house runs every
  slice: its design section (an L slice: its own record) with lettered
  decisions, the owner's yes, one `implementer` (Opus 5.5) per part with
  the part's section and §12 as the brief, one `reviewer` per slice, the
  gate from the lead, a device pass by `qa-runner` whenever a path through
  the real gateway changed. `flutter test` one run at a time.
- **D1 runs in four parts**, each one implementer run in the main tree
  with the whole-suite gate from the lead after it: run 1 the remote
  contract (rules and their suite, the gateway's three calls, the fake),
  run 2a the engine pause and its two status lines, run 2b the service
  (`deleteCloudCopy`, the pending record, `start()` finishing marked
  spaces), run 3 the surface (bloc, page, strings, guide, the reference);
  then one review of the whole, then the device pass. Each run's facts go
  into §5.9 as it lands.
- After every slice: the as-built block under its section (the truth over
  the plan), the status line at the top, `sync-and-accounts.md`, the
  master ladder. Commits on the owner's word.
