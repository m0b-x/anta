# Cloud Multi-User Roadmap — ANTA

**Status: D1 BUILT AND REVIEWED 2026-11-10, uncommitted — "Delete cloud
copy": four build runs, one review in two sittings, two fix passes, the
gate green (`+15303 ~17`), two device passes green against the Firestore
emulator; §5.9 is the truth over §5.1–5.6. Left to the owner: the rules
deploy, the build on every device, the phone check (§5.8), the commit.
Every other slice is PLAN: one row of §3, with its own design section or
record when it starts; D2 (delete my account) is next. The target is the
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
| **D1** | Delete a database's cloud copy | M | yes — first |
| D2 | Delete my account and everything it holds in the cloud | M | yes |
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
| R1 | The database in the region the owner chose | S | yes — before the partner's data |
| R2 | The app says where synced data lives and who can read it | S | yes |
| R3 | The cloud copy stops growing (old note text, old tombstones) | L | later |
| R4 | A second account on one phone cannot see or feed the first one's data | M | later — owner's call |
| R5 | Two people on two app versions: "update ANTA" instead of silence | S | yes — inside E1 |
| R6 | Knowing why sync broke on a phone I do not hold | M | later |
| R7 | iPhone | L | only if the partner has one |
| R8 | Sign-in on Windows and macOS | L | later |
| R9 | Backups and restores that hold shared rows | M | yes — with E2 |
| P1 | App Check: only the real app may talk to the database | S | no |
| P2 | The paid plan with a budget alert | S | no |
| P3 | Privacy policy, terms, the Play data-safety form | S | no |
| P4 | Console checks: sign-in open to anyone, the Play signing fingerprint | S | no |
| P5 | End-to-end encryption | L | no — a decision first |
| P6 | Push: notified while the app is closed | M | no |
| P7 | More than one partner | L | no |

**Thirty slices.** Fifteen are on the road to the target (D1, D2, E0–E5,
N1–N3, R1, R2, R5, R9); two are optional on it (E6, E7); five wait for a
reason of their own (R3, R4, R6, R7, R8); eight matter only for a public
listing (D3, P1–P4, P6) or a later ambition (P5, P7).

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

### 5.1 What the user gets

In Settings → Sync & sharing, the Sync section of a syncing database gains
a last row, **Delete cloud copy**, under "Stop syncing". It asks once,
naming the space; on yes the copy in the account is removed for good, this
database stops syncing, and every note and event stays on the phone. The
account's other devices that synced with that copy stop with the words
"the cloud copy was deleted" and keep what they hold.

Today the only way out is "Stop syncing", which unbinds locally and leaves
the space in the cloud for ever (`SyncSpaceService.stopSyncing`,
`sync_space_service.dart:309`; the page's own comment at
`sync_settings_page.dart:1180`: "nothing is deleted — the cloud copy
stays").

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
- **g. Any device finishes a half-done deletion.** The space document
  carries the mark, so the next "Sync this database" on any device of the
  account finishes marked spaces before it lists the others, and the
  device that started it shows a "Finish deleting" row meanwhile.
- **h. No wire bump.** The space document gains a key; no row's `data`
  changes; `syncSchemaVersion` stays 46.

### 5.3 The protocol

1. **Mark.** The space document gets `deletedAt` = the server time. From
   then on the rules refuse every update of that document — and every push
   of this app writes it in the row's own transaction
   (`touched`, `lastWriter`, `lastWriteAt`), so a push to a marked space
   fails whole.
2. **Empty.** For every table of the registry
   (`lib/database/crdt/synced_tables.dart`, `content_chunks` included —
   the client SDK cannot list subcollections, so the registry is the list):
   read a page of documents, delete them in one write-only transaction,
   repeat until the table reads empty. Nothing new can land after the
   mark, so the loop ends.
3. **Remove** the space document, last.

A build older than the space's `schema` refuses to delete ("update ANTA
first"): a newer build may have written a table this one does not know,
and removing the space document over it would strand those rows.

Cost: one read and one delete per document, one more read per batch for
the rule's look at the space, and at least one read per table. The owner's
space is about 312 rows plus note chunks. The free plan allows 20,000
deletes a day; past that the job stops with the quota reason and resumes
another day.

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
  `test/support/fake_sync_gateway.dart`): mark a space, delete up to *n*
  documents of one table and answer how many, delete the space document;
  `SyncSpaceInfo` and `SyncSpaceSignal` say whether the space is marked.
  Deletes go through the write-only transaction the pushes use, so nothing
  is ever queued offline. `content_chunks` pages are small (a chunk is up
  to 64 KB and the SDK returns whole documents); a page that times out
  halves that table's page for the rest of the job. The fake's existing
  `deleteSpace` test helper (a console delete) is renamed, not reused.
- **Service** (`sync_space_service.dart`): `deleteCloudCopy` with a
  progress callback — read the binding, mark (a failure here changes
  nothing: still bound, still syncing), unbind exactly as "Stop syncing"
  does and record the pending deletion install-wide beside the space
  registry (`sync_space_registry.dart`), empty, remove, clear the record.
  `start()` finishes marked spaces first, best effort, and never offers
  one; binding or downloading a marked space answers `spaceGone`.
- **Engine** (`sync_engine.dart`, `sync_pusher.dart`, `sync_status.dart`):
  a pause `spaceDeleted` for a space that is marked or missing — from the
  signal (`_onSignal`, today `noAccess` for a missing space) and from the
  diagnosis of a denied push (`_diagnose`). It behaves as `noAccess` does:
  nothing runs, one "Sync now" re-reads the space once. `noAccess` keeps
  the refusals.
- **Bloc** (`lib/bloc/sync/`): an event and a busy flow with the count
  removed so far, run through `_step` like every other change of binding.
- **Page and drawer** (`sync_settings_page.dart`,
  `lib/widgets/drawer_sync_status.dart`): the row, the confirmation, the
  progress line, the "Finish deleting" row on the unbound section, the
  pause's line on both surfaces (the page's line joins
  `_statusLineTemplates`, so the status row keeps one height), the "Stop
  syncing" confirmation's second wording, an announcement at the end, a row
  in the app guide's sync topic.
- **Strings** en/de/ro; `sync-and-accounts.md` gains the as-built bullet.

### 5.6 Tests

- Rules (`test/firestore/rules_test.dart`, tag `firestore-rules`): no
  delete of a row or a space while unmarked; the owner marks; a marked
  space refuses an update and a second mark; rows and then the space
  delete once marked; another account can do none of it; `deletedAt` must
  be the server time and cannot be set at create. The probe
  (`tool/firebase/rules_probe.ps1`) gains the same cases.
- Fake gateway contract; the service (the whole path; offline at the mark
  leaves the database bound; a failure while emptying leaves it unbound
  with the pending record and resumes; the quota; the older-build refusal;
  `start()` finishing a marked space and never offering it); the engine
  (the pause from the signal and from a denied push, nothing running under
  it, the one re-read); the bloc; the page at 1.0, 1.3 and 2.0 in en, de
  and ro with the kit's guideline cases.
- A device pass against the Firestore emulator: bind, push, delete, the
  emulator holds no document under the space, the database is intact and
  unbound; a second guest bound to the same space reads the pause.

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
  account, so the flow re-authenticates with Google first. Open: an ended
  pair document keeps both uids for ever (`members` never shrinks, no
  delete) — decide whether a member may delete an ended pair.
- **D3 — Deletion from outside the app.** A page (the project's free
  Hosting domain) that says how to ask, and the operator's runbook:
  `firebase firestore:delete --recursive` on `users/<uid>` and the
  console's user delete. Google Play requires the link for any listed app
  that lets people create accounts; nothing else does.

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

- **R1 — Region.** The owner's decision (§11). Moving is: stop syncing on
  every device, delete and recreate the database in the chosen location,
  deploy rules and indexes, "Sync this database" on the phone, then the
  second device, in the Phase 02 record's §7 order. Cheap while one
  account's space is all there is.
- **R2 — "Where your data lives."** A few true sentences in the Sync
  section and the guide: synced data is stored in Google's cloud (the
  location), it is not end-to-end encrypted so the project's operator can
  read it, and what a partner sees when something is shared.
- **R3 — Storage stops growing.** Replaced note chunks are never removed
  and tombstones are never purged (Phase 02 record §8, readiness §8). A
  chunk collector and a tombstone purge after every device has seen it;
  D1's rule is widened here.
- **R4 — A second account on one phone.** It sees every local row, and
  its edits wait in the queue and upload into the first account's space
  when that account returns (`sync_engine.dart:1141`,
  `crdt_write.dart:121`). Accept for personal phones, or tie a database to
  its account.
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
  uploading again.
- **O3 — The partner's phone.** **Android — the owner, 2026-11-10.** R7
  (iPhone) stays a later slice and blocks nothing here.
- **O4 — A second account on one phone (R4).** **A:** accept; each person
  has a phone. **B:** tie a database to its account.

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
