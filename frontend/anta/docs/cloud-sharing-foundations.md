# Cloud Sharing Foundations — ANTA

**Status: F1 BUILT 2026-11-12 (the grant and the wire), REVIEWED and
FIXED the same day (§12: two privacy holes closed, the mark given its own
stamp); F2–F4 to build. The owner's scope (2026-11-11): everything under the "Share with
partner" switch, for events and for notes — schema, wire, rules, the
engine reading a partner's shared rows, read-only protection, backups,
two app versions — proven by tests and the rules emulator; no switch, no
badge, no read-only editor; the partner never edits (E5, N3 stay out);
when a share ends the rows disappear from the partner's phone.** It is the design record the
multi-user roadmap asks for before E1 and before N1
(`cloud-multi-user-roadmap.md` §7, §8), written once for both because the
layer is the same. Slices E1–E4, N1–N2, R5 and R9 of that roadmap are
built here without their surfaces; their surfaces are a later slice each.

## Contents

1. What this builds, and what it leaves
2. Decisions (lettered)
3. The grant
4. The wire, the rules, the indexes
5. The reader
6. Rows that leave
7. Read-only, and what stays personal
8. Backups and archives
9. Parts, in build order
10. Must not change
11. Open for the owner
12. As built

---

## 1. What this builds, and what it leaves

After this record is built, a row marked as shared on one account's device
appears on its paired partner's device at the next sync, follows every
later change, and disappears when the mark is cleared, the pair ends, the
owner's cloud copy or account is deleted. The partner cannot change it.
Nothing in the app sets the mark yet: the two service calls that do
(§3) are reached only by tests and by the QA harness's seam.

Left for the surface slices: the switch in the event editor and the folder
menu, the owner's mark on a row, the read-only editor, "new from my
partner", a place for shared folders in the browser.

## 2. Decisions (lettered)

Taken by the lead; each is reversible until the rules deploy.

- **a. The grant names the pair, not the person.** A shared row carries
  the id of the pair it is shared into (`shared_pair` locally,
  `sharedPair` on its document). The rules let a member of that pair read
  the document while the pair is active, by one `get()` of the pair. So
  ending the pair, or deleting an account (D2 removes the pair document),
  revokes every share on the server at once, whether or not the owner's
  phone ever runs again; a new pair starts with nothing shared. The
  readiness record's sketch (a uid list, no `get()`) could only be revoked
  by the owner's own device. Two things make the id safe to go by (review
  2026-11-12): the pair must hold the row's **owner** as well as the
  reader, and a pair's id can never come round again for the same two
  people — it starts with the code of the invite it was made from, minted
  by one of them, and ends in what the other one's device adds (§4).
- **b. One mark on the root, the rest derived.** `calendar_events` and
  `folders` gain the column. An event's skipped days and per-day texts,
  and a folder's whole subtree — folders and notes — carry the grant on
  the wire only, read from the root when the row is encoded. Nothing can
  drift from the tree it hangs in.
- **c. A database shares into one pair.** The only writer of the mark
  clears every other pair's mark as it sets one, and the reader's look at
  the account's pair (§5) clears every mark of a pair that is no longer
  it — a merge alone can leave two, and an ended pair's marks would
  otherwise stand for good.
- **d. The owner's copy is the truth for a shared row.** The partner's
  merge of it lets the remote win whatever the stamps say.
- **e. A shared row is never pushed by the partner.** The push retires a
  queued entry of another account's row unsent.
- **f. Rows that leave are found by counting.** After each read of a
  shared table the reader asks the server how many rows are shared with
  it and compares with what it holds; fewer on the server means some
  left, and only then is the whole set read again and the absent ones
  removed. No notice feed, no extra write on the owner's side.
- **g. Shared rows are a cache of a live grant.** They are removed — hard
  deleted, no tombstone — when the grant ends: the row left the set, the
  pair ended, or this database stopped syncing. What a person added of
  their own to a shared event (presence, alerts) stays theirs and is kept.
- **h. Two app versions.** A shared document says which wire wrote it. A
  reader meeting a newer one skips it, says "Update ANTA", and reads the
  set again after the update.
- **i. Backups hold what is mine.** Another account's rows are not
  exported; an import takes every row as this device's own and no share
  mark. A restored database shares nothing until the space, or a person,
  says otherwise.
- **j. Counters and the per-note currency stay personal** in this
  generation; a shared note shows the partner's own.
- **k. A document's grant is said again — towards private always,
  towards shared only on proof.** A document says who may read it as of
  the push that wrote it. One that names a pair while its row is private
  on a device of the owner is said again by that device at once, whoever
  pushed it and whenever: a share that outlives its end is the one
  outcome that must not last, and the pusher may never return. One that
  is private while the row is shared there is said again only by its own
  pusher reading it back, or by a device whose deciding write is newer
  than the push (§3). The same holds for the pair the space names for
  its notes' text. Two devices that disagree therefore never write at
  each other for good: everything rests at private until the one that
  shares pushes again.
- **l. A mark is metadata.** Setting or clearing one stamps the row and
  leaves `updated_at` alone, as a colour label does: sharing a folder
  must not move it in a "recently changed" order.
- **m. The mark is a register of its own.** Beside `shared_pair` a row
  carries `shared_stamp`, the stamp of the write that last set or cleared
  the mark, and a merge keeps the mark with the newer stamp whichever
  side's row wins. A row is one last-writer-wins register; without this a
  rename made on a device that had not yet heard of a share's end would
  carry the old mark back over it, and every device would converge on
  "shared" against the owner's last word (review 2026-11-12).
- **n. Real writes are pushed before re-sends.** The rows a mark queues
  again are entries that only re-send a version the space holds; a push
  sends every real write first, so the mark's own write is in the space
  before the rows under it say the new grant — and another device of the
  owner reads the mark first instead of taking those rows for a share
  that outlived its end. As re-sends they also never count as unpushed
  edits, so a newer version of a note arriving meanwhile files no copy.

## 3. The grant

**Locally** (migrations v52, v53): on `calendar_events` and on `folders`,
`shared_pair TEXT NULL` — the id of the pair the row is shared into, NULL
for a private row — and `shared_stamp TEXT NULL`, the stamp of the write
that last set or cleared it, NULL while the mark was never touched
(decision m). Both travel in the row's `data` (`sharedPair`,
`sharedStamp`), so the owner's other devices know the mark and its age.
Two partial indexes (`… WHERE shared_pair IS NOT NULL`) answer "is
anything marked" for a database that shares nothing without reading
either table.

**Who sets it.** Two service calls and nothing else:
`CalendarEventService.setShared(eventId, pairId?)` and
`FolderStorageService.setFolderShared(folderId, pairId?)` — over
`CalendarEventDao.setSharedPair` and `FolderDao.setSharedPair`, each one
stamped write of the mark and its stamp under one stamp for the whole act
(decision l: `updated_at` untouched). Setting a pair clears, in the same
transaction, every mark of another pair in both tables (decision c) and
every mark inside the folder's own subtree, which the outer mark now
covers. A missing or deleted root writes nothing; a mark it already
carries writes nothing of its own. `clearOtherPairs(pairId?)` on both
DAOs is the other writer: every mark of a pair that is not the given one
— all of them when there is none — for the reader's look at the pair
(§5). No surface calls any of them yet.

**How it merges** (decision m, `CrdtMerge.mergeMark`). After the row's
own merge, in the same transaction, the mark with the newer stamp stands,
on every outcome: a remote that wins the row can leave this device's
newer mark in place, a remote that loses can still bring a newer mark,
and a remote at the row's own stamp can bring one the row was stored
without (§4's re-read). When the mark that stands is not the one the
remote's document says, the row is queued again as a real write, so its
document is corrected ahead of the rows under it. A tombstone carries no
mark and the one here stands — two devices can disagree on a deleted
root's mark for good, which shows only on tombstones' documents and
settles private (decision k).

**What is shared** is derived when a row is encoded for the push, never
stored a second time (decision b):

| Row | Its document carries the grant of |
| --- | --- |
| an event | its own `shared_pair` |
| a skipped day, a per-day text | their event |
| a folder | the nearest folder at or above it that carries a mark |
| a note | the nearest marked folder at or above its folder |
| presence, alerts, counters, everything else | never — personal (D18) |

**Keeping documents in step.** A document's grant is written when the row
is pushed, so a change of the root has to push its dependants again, at
their own stamps (`CrdtWrite.requeueRows`, no new stamp; tombstones
included). Every row this device may push follows — its own, however
`owner_id` spells that: a row from before the bind carries the account's
uid and one written since carries NULL, so "the same owner as the root"
would skip most of a subtree (`SyncDao.mineSql`: every row but those
another account shares with this one). They are queued as re-sends
(decision n):

- a mark set or cleared on an event → its day rows; on a folder → every
  folder and note under it;
- a folder moved (`moveFolder`, `moveFolders`, `updateFolder`) → its
  subtree, when the grant differs between the two places; a note moved
  is itself the write;
- a merge that changes a root's mark or a folder's place (the parent
  repair's included) → the same dependants, on the device that merged it.

That is not enough by itself, because a merge settles a row and retires
its queued entry — at an equal stamp as "the space holds this", under a
newer remote as "overwritten" — and the entry it retires may be the one
that would have corrected the grant. The pull closes it over each part it
merged, inside that part's transaction (`_Puller._resayShares`), for the
five tables only (decision k):

- **A document that names a pair while the row is private here** is
  queued again, always — whoever pushed it and whenever. This covers the
  note a device pushed just before the owner ended a share and the one it
  pushed long after, never having heard: the first build compared the
  decision's stamp with the push time and so lost an end decided offline
  to any later push of a device that was behind.
- **A document that is private, or names another pair, while the row is
  shared here** is queued again in two cases only:
  1. *its own push, read back* — the ordinary case, not only a race: a
     device that marks a folder and syncs pulls first, reads back the
     notes it pushed last time at their own stamps, and the merge retires
     every entry the mark had queued;
  2. *another device's, older than what this one knows* — the newest
     write that decides the row's share here (its event's stamp, the
     newest stamp among the folders above it,
     `SyncTableBinding.shareStamps`) is later than that push by the
     server's clock, so the pusher could not have known.
  Otherwise it is left to its pusher, which says it again once it merges
  the root.

A pulled page carries who pushed each document and when
(`SyncPullPage.pushed`). Nothing is read when no document of a part names
a pair and no root here carries a mark (`SyncDao.anyShareMark`, answered
by the two partial indexes), and only a part that holds a differing
document of the second kind asks for the stamps.

Two more places keep the grant from being lost on its way out:

- **The push sends real writes first** (decision n,
  `SyncOutboxDao.pending(unpushedOnly:)`): the queue is read a second
  time only when a re-send stands at its head.
- **A mark changed while a push is in flight.** The write that changes it
  queues the rows again at the stamps they carry, which entries already
  standing at those stamps absorb — and the push in flight would then
  retire them with the old grant on the documents. Before it retires
  anything the push compares each shared-table row's grant with what it
  sent (`_Pusher._regranted`, inside the retiring transaction) and leaves
  the differing ones queued, once more in the same drain.

*Known cost.* Every device of the owner that merges a root's change
queues its copies of the dependants again, and every device reads the
others' re-sends back: a share set on a folder of N rows costs up to N
writes per other device of that account and that many reads on each —
once per toggle or move, and nothing for a database that shares nothing.
The re-queue statements read the whole folders and notes tables (the
indexes are partial on live rows and the statements include tombstones):
fine once per toggle, not for a hot path.

A tombstone keeps its grant: the partner has to hear of the delete.

## 4. The wire, the rules, the indexes

**Wire 47.** `syncSchemaVersion` 46 → 47: an older build would drop the
mark on its next push of the row, so the space has to refuse it (the
`schema >= stored` rule already does; the build pauses as `appOutdated`).
The body cutover (`_cutOverWire`) stays tied to wire 46
(`DatabaseSchema.bodyWireVersion`) — a 46 → 47 database re-queues
nothing and reads no note again. It does read `calendar_events` and
`folders` again from the start, once (`DatabaseSchema.shareWireVersion`,
`_WireCutover.marks`): a build below 47 may have merged an event or a
folder a newer one had already marked, without the mark it could not
read, and a row that does not change is never delivered again on its own
— the device would go on saying "private" for everything under it. The
re-read hands the mark to the merge, which takes it at the row's own
stamp; the version is stored once that run's pull reached every table's
end, so a run cut short reads the two tables again.

An event and a folder carry their own mark in `data` under `sharedPair`,
written only when set, and its stamp under `sharedStamp`, written
whenever the row has one — a mark taken away still says when — so the
owner's other devices merge the mark as its own register (decision m). A
tombstone carries no data, and a merge of one keeps the mark the row had.

A shared row's document gains two top-level fields beside the envelope's
(`SyncEnvelope.sharedPair`, `wire`), present only when the row is shared
— the grant in effect, worked out when the row is encoded
(`SyncTableBinding.sharedPairs`, once per table and part):

- `sharedPair` — the pair id, what the read rule and the reader's query go
  by;
- `wire` — the wire version of the build that wrote it (decision h).

A document is replaced whole on every push, so a row made private loses
both with that write.

The space document gains `sharedPair` too — the pair this database's
notes are shared into (`FolderDao.sharedPairOfNotes`: the mark of its
live folders), written with every push and taken out when none — which is
what lets a partner fetch a shared note's text: chunks are stored once
per space under their hash and carry no grant of their own. An event
shares no text, so an event's mark alone leaves the space naming nobody.

Every push writes the field from what its device knew then, so a device
that had not yet merged the end of a share puts the pair back with its
next push of anything. A run that pulled to the end and pushed nothing
therefore compares the document with its own answer and writes the field
alone when they differ (`SyncGateway.writeSpaceShare`,
`SyncEngine._settleSpaceShare`; what the document says comes with the
live snapshot, or under the manual cadence with the run's own read of the
space) — by decision k's rule: a pair the document names where this
device knows of none is always taken out; one it lacks is put back only
over this device's own earlier write.

**Rules** — proven on the emulator's rules engine before the design was
fixed (2026-11-11, a scratch project: 23 probes — the partner's query,
its cursor and resumed forms, its count, single reads, chunk reads; a
stranger, a dead pair, a query without the pair filter, the pair ended and
the pair deleted all refused; the owner untouched), and changed by the
review of 2026-11-12, which read the owner's rows again on the emulator
after deleting an ended pair and making it again under the same id with
a second account:

```
function activeMember(pairId, ownerUid) {
  let pair = get(/databases/$(database)/documents/pairs/$(pairId)).data;
  return pair.status == 'active'
      && uid() in pair.members && ownerUid in pair.members;
}
function sharedWithCaller() {
  return signedIn() && resource.data.sharedPair is string
      && resource.data.ownerId is string
      && activeMember(resource.data.sharedPair, resource.data.ownerId);
}

// The partner's read of a shared row, wherever its space is — one match
// per shareable table, never a wildcard over the collection name.
match /{path=**}/calendar_events/{rowKey} {   // and the four other tables
  allow get, list: if sharedWithCaller();
}

// Under users/{owner}/spaces/{spaceId}/{table}/{rowKey}, beside the
// owner's own clauses:
allow get: if table == 'content_chunks' && signedIn()
  && activeMember(get(<the space>).data.sharedPair, owner);

// A new pair, beside the invite check it already had:
function namedAfterInvite() {
  return pairId.split('_')[0] == request.resource.data.inviteCode
      && pairId.size() > request.resource.data.inviteCode.size() + 1
      && pairId.size() <= 64;
}
```

- **The pair has to hold the owner.** A document names a pair by its id
  alone; an ended pair may be deleted by a member, and its id was then
  free for the former partner to take again with any second account. Such
  a pair now reads nothing: it does not hold the owner of the documents
  that still name it. `ownerId` is what the write rule holds to the
  space's account.
- **A pair's id never comes round again for the same two people.** A new
  pair is `<invite code>_<nonce>` (`PairingGateway.pairIdFor`): the code
  is minted at random by whoever invites, the nonce by the device that
  redeems, and the rules hold the first half to the invite the pair cites
  — which only the other person could have created. A former partner on
  either side of a new pairing cannot steer both halves back to the id
  the other's documents still carry. Pairs made before this keep their
  ids, which hold no `_`. A build before this cannot create a pair once
  these rules are deployed: both phones update before pairing again.
- **Stale marks are cleared besides** (decision c), so a new pair starts
  with nothing shared even on the documents: belt and braces with the two
  rules above, since clearing needs the owner's device to run.

As deployed the owner's side gains `validShare()` — `sharedPair` only on
the five tables, a non-empty string of at most 64, with an integer
`wire`; a `wire` without a share refused — and `validSpace()` takes a
`sharedPair` of the same shape. The rules stay additive: a build before
this one writes neither field, and this build writes them only for a
database that shares something, so it runs against the rules as they
were until then.

- A query must pin the pair and the owner (`sharedPair == <pairId>`,
  `ownerId == <partner's uid>`) or the rule cannot be decided and the
  whole query is refused — so nothing can be listed across pairs or
  across owners. One `get()` of the pair per query, however many rows.
- The pair id is not proof of who wrote a row: anyone who learned it could
  write documents citing it into a space of their own. Nobody reads those
  — the pair does not hold their owner — and the reader checks the owner
  again on every envelope.
- A chunk read costs the rules two lookups (the space, the pair). Only
  `get`, never `list`: a partner fetches the hashes a shared manifest
  names and cannot enumerate a space's text. Accepted limit: a partner who
  can guess an unshared chunk's exact text can confirm the guess.
- The owner's write is checked for shape only (`sharedPair` a short
  string on the five shareable tables, `wire` an int): validating the
  pair there would cost one lookup per written row, past the twenty a
  batch is documented to allow (D1's lesson).

**Indexes** (`firestore.indexes.json`, collection-group scope, one per
shareable table): `sharedPair ASC, ownerId ASC, pushedAt ASC`. The
emulator does not need them; production refuses the query without.

## 5. The reader

A second, smaller pull beside the bound space's, run by the engine after
its own pull and drain, never by a drain-only run:

1. **Who.** The active pair, asked of the server (`findActivePairs`), not
   of the per-database cache. No answer (offline) → no shared pull, and
   nothing is removed. No active pair → everything another account owns is
   removed (§6).
2. **What.** For each shareable table in parent-first order — events, day
   texts, skipped days, folders, notes — the collection-group query
   `sharedPair == pair, ownerId == partner`, in arrival order from the
   table's own cursor (`shared_cursor.<table>`, cleared with
   `shared_pair` when the pair changes), with the same ten-second overlap
   on a resumed cursor.
3. **Merge.** Each envelope through the table's own binding and DAO merge,
   with the remote winning whatever the stamps say (decision d), stored
   under the partner's `owner_id`. A document of a newer wire is skipped
   and remembered (decision h). A shared note's text is fetched from the
   partner's space by the hashes its manifest names.
4. **Place.** A shared folder whose parent was not shared lands at the
   root of the browser: its `parent_id` is set to NULL here, after the
   table was read to its end. The row is never pushed, so the difference
   from its document stays local.
5. **Caches** hear of the pages through the hooks the own pull uses.

## 6. Rows that leave

A query cannot report a document that stopped matching it. After a table's
read the reader asks the server for the count of the same query (an
aggregation: one read per thousand rows) and compares it with the rows it
holds of that owner. Fewer on the server means rows left — a mark
cleared, a note moved out, a cloud copy deleted: the table is then read
again from the start, and what the server no longer returns is removed
here. More on the server means rows are still arriving, and the cursor
brings them.

Removed means hard-deleted, with the rows that hang on them (a shared
event's day rows; a shared folder's notes, their text, their search
index). What the person added of their own — presence marks, alert
definitions — is theirs, stays in their space, and is simply inert while
its event is not there.

Everything another account owns is removed at once when the pair is found
ended, when another partner is found, and when the database is unbound —
there is then no reader to keep it true.

Once a day, with the engine's full pull, every shared table is read from
the start whatever the count says: it brings back a shared row this
device changed locally by a path that should not have (§7).

## 7. Read-only, and what stays personal

"Another account's" is one test everywhere: `owner_id` is set and is not
the account this database is bound for. (An unbound database holds none:
an unbind releases its own rows to NULL — the roadmap's §6.1 f — and
removes the rest, §6.)

Three layers keep such a row the owner's, each catching what the one
before lets through:

1. **The services refuse.** The calls a person's action reaches — save or
   delete an event, skip a day or write its text; rename, move, label,
   delete a folder or a note, save a note's text — throw a typed
   `ForeignRowException` for another account's row, which the surface
   slice turns into a disabled control.
2. **The push never sends one** (decision e). Whatever queued it — a bulk
   write that re-stamps every row of a folder, a path no check covers —
   its entry is retired unsent, as an entry of a row that is gone is.
3. **The owner's copy comes back.** The reader lets the remote win
   (decision d) and reads every shared table from the start once a day
   (§6), so a local change that slipped through both lasts a day at most
   and never leaves the device.

Personal, and so never refused: presence marks and alert definitions on a
shared event, counter values on a shared note — rows of the person's own,
keyed by the shared row's id, in the person's own space (readiness D18).
The owner's are never shared, so a partner's phone arms only the alerts
the partner set.

An event whose category this device does not have — the owner's custom
one — draws as the built-in fallback category until a surface decides
better; its link to a note the partner was not given is inert.

## 8. Backups and archives

- **Export** leaves out every row another account owns and writes neither
  `ownerId` nor the share mark.
- **Import** stores every row as this device's own (`owner_id` NULL)
  whatever the archive says, and no mark. Every archive written before
  this build holds only its exporter's rows — nothing could be shared —
  so reading their `ownerId` as "mine" loses nothing; the format stays 7.
- A restore already unbinds; the next bind lets the space win what it
  holds (D15), and the marks come back from there, never from a file.
- A folder archive carries no ownership either: an imported copy is the
  importer's.

This replaces readiness D16 A ("`owner_id` travels in backups"), whose
reason — the partner who keeps a copy after a share ends — the owner
decided against on 2026-11-11.

## 9. Parts, in build order

Each is one build with the whole-suite gate and a commit; the review is
one sitting per part.

1. **F1 — the grant and the wire.** v52; the two service calls; the
   derivation at encode; the re-queues; wire 47 with the cutover pinned to
   46; the envelope's and the space's `sharedPair`, `wire`; both gateways;
   the rules, the indexes and their suites.
2. **F2 — the reader.** The gateway's shared page, count and foreign
   chunk read; the partner source; the shared pull, its cursors and
   parks, the newer-wire skip and its status; the count and the re-read;
   the removals at pair end and at unbind; the root placement; the caches.
3. **F3 — the fences.** The push's backstop; the services' refusals; the
   category fallback; backups and archives.
4. **F4 — proof on devices.** The QA seam that sets a mark without a
   surface, and the two-guest flows (the roadmap's R10): pair, share an
   event and a folder, see them, change them, clear the mark, end the
   pair.

## 10. Must not change

The roadmap's §12, and: an account's own sync — every document it writes
for itself, every pull of its own space, the cost of an idle launch; the
pairing flow; backups staying importable; `owner_id` NULL meaning "mine".

## 11. Open for the owner

*(collected as the build meets them)*

## 12. As built

### F1 — the grant and the wire (2026-11-12)

One session on Fable, the build inline.

- *Schema.* v52: `calendar_events.shared_pair`, `folders.shared_pair`
  (two guarded `ALTER`s, no index, no row rewritten);
  `DatabaseSchema.syncSchemaVersion` 47, `bodyWireVersion` 46.
- *Writes.* `CalendarEventDao.setSharedPair` / `clearOtherPairs` /
  `sharedPairsOf` / `stampsOf`; `FolderDao.setSharedPair` /
  `clearOtherPairs` / `sharedPairsOf` / `shareStampsOf` /
  `sharedPairOfNotes`, the subtree re-queue in `moveFolder`,
  `moveFolders`, `updateFolder` and both merges;
  `CrdtWrite.requeueRows` over `SyncOutboxDao.requeueRows` (the guard
  suite keeps the outbox behind `CrdtWrite`); `SyncDao.anyShareMark`.
  Services: `CalendarEventService.setShared`,
  `FolderRepository.setSharedPair`,
  `FolderStorageService.setFolderShared`.
- *Wire.* `sharedPairKey`; `SyncEnvelope.sharedPair` / `wire` /
  `sharedInto`; `SyncPullPage.pushed` (`SyncPush`);
  `SyncGateway.pushBatch(sharedPair:)`; `SyncTableBinding.sharedPairs` /
  `shareStamps` on the five bindings; `sharedTables`; the pusher stamps
  the grant after `encode` and reads the space's pair at every push; the
  puller's `_resayShares`; `_cutOverWire` pinned to the body wire.
  Both gateways, the fake refusing a share on any other table as the
  rules do.
- *Rules and indexes.* `firestore.rules` as §4; five collection-group
  indexes `sharedPair, ownerId, pushedAt` in `firestore.indexes.json`,
  pinned to `sharedTables` by `firestore_indexes_test.dart`.
- *Found while building.* The merge hooks alone lost their re-queue to
  the device's own read-back in the ordinary flow, and an un-share could
  stay readable until another device of the owner returned — decision k
  and §3's two rules, each pinned by a test that fails without it. The
  re-queue went behind `CrdtWrite` when the outbox guard suite refused
  the DAOs naming the outbox.
- *Gate.* `dart analyze lib test tool test_driver` clean; the whole suite
  `+15908 ~17`; the rules suite 147 of 147 against the emulator (23 new,
  group "sharing"). New suites: `test/database/shared_pair_test.dart`
  (27), `test/services/sync/sync_share_push_test.dart` (18),
  `test/services/share_mark_service_test.dart` (8); extended:
  `sync_codec_test`, `firestore_sync_gateway_test`,
  `firestore_indexes_test`, `sync_engine_runs_test` (the 46 → 47 no-op).
- *Not built here.* Nothing reads another account's rows yet (F2), no
  write is refused and no foreign entry retired (F3), no device has run
  it (F4). A build before wire 47 pauses as `appOutdated` once a 47
  build has pushed to its space: every device of an account updates
  together.

### F1 — the review and its fix pass (2026-11-12)

An independent review on Fable in a separate checkout of the F1 commit
(`b203f092`): fourteen findings, two of them privacy holes it reproduced
— one on the emulator's rules engine, one in SQLite. All but the ones
named last are fixed in this pass.

| # | Found | Fixed by |
| --- | --- | --- |
| 1 | An ex-partner deletes the ended pair, makes it again under the same id with a second account, and reads the owner's shared rows and text again | the pair must hold the owner (`activeMember(pairId, ownerUid)`); a new pair's id is bound to its invite (`namedAfterInvite`, `PairingGateway.pairIdFor`); stale marks are cleared (`clearOtherPairs(null)`, driven in F2) |
| 2 | The "queue again" statements took "same `owner_id` as the root" for "mine" and skipped every row written after the bind — an un-share left their documents naming the pair | `SyncDao.mineSql`: every row but those another account shares with this one |
| 3 | The mark rode the row's last-writer-wins: an unrelated edit on a device that was behind silently re-shared (or un-shared) for everyone | decision m: `shared_stamp` (v53), `CrdtMerge.mergeMark` in both merges |
| 4 | An end decided offline lost to any later push of a device that was behind | decision k: a document that says "shared" where the row is private is always said again |
| 5 | The re-queued rows counted as unpushed edits, so a newer version of a note arriving next filed a copy of text that was never unsynced | re-sends (`republish`) from `requeueRows` and `_resayShares` |
| 7 | A mark changed during a push was lost to that push's acknowledgement | `_Pusher._regranted` |
| 8 | The space's `sharedPair` was whatever the last pusher believed | `writeSpaceShare`, `_settleSpaceShare` |
| 9 | Nothing kept another account's marks out of this account's derivations | `mineSql` here; F2 stores a shared row without its owner's mark |
| 10 | Decision c was not kept by merges; marks of an ended pair stood | `clearOtherPairs` takes "no pair", and `setSharedPair` clears other pairs before its own early return; driven by the reader in F2 |
| 11 | A build below 47 that merged a marked root kept it unmarked for good | the one-time re-read of the two root tables (§4) |
| 12 | Two table scans per pulled part for a database that shares nothing; two more per merged folder | the two partial indexes; the folder merge reads what it shared into only when it can change |
| 13 | Rule 2's clock comparison passed whatever order a test acted in; several cases untested | the share suites run the server on the devices' clock; the cases added below |
| 14 | `sharedTables` had been inserted between the bindings list and its doc comment | the constant lives beside `syncedTables` now, re-exported where it was |

Found while fixing, and fixed: with "always say private again" a second
device of the owner that pulled between two parts of a large share would
have taken the first rows for a share that outlived its end, said them
private, then shared them again once it merged the mark — hence decision
n; and two devices that disagree would have written the space's field at
each other for as long as they did — hence its one-sided rule.

Accepted, not fixed:

- *6 — a deleted root's mark can differ between devices for good.* A
  tombstone carries no mark. It shows only in which grant tombstones'
  documents carry, never in content, and settles private.
- *The cost of a toggle* (12's last line): about devices × rows writes
  and as many reads back. A 5,000-note folder on three devices is a
  visible share of a free-tier day; the surface slice should say so
  before it offers the switch on a large folder.
- *A build before this one cannot create a pair* once the rules are
  deployed (the new id shape).

Gate: `dart analyze lib test` clean; the whole suite `+15940 ~17`; the
rules suite 150 of 150 on the emulator. `shared_pair_test` 39 (the
register on every merge outcome, the owner spellings, the re-send kind,
`clearOtherPairs`), `sync_share_push_test` 29 (both directions of decision
k on one clock, the offline end, no copy on either device, mark first,
a mark changed mid-push, the space's field in four cases),
`share_mark_migration_test` 4 (v51 and v52 databases, the re-run, the
plan), `sync_engine_runs_test` +3 (the marks re-read), the rules suite +3
(the owner in the pair, the id's shape, the id not steerable). Each new
behaviour was checked the other way too: with the fix taken out, its test
fails.
