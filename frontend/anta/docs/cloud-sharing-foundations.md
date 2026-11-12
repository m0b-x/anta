# Cloud Sharing Foundations — ANTA

**Status: F1 BUILT 2026-11-12 (the grant and the wire), REVIEWED and
FIXED the same day (§12: two privacy holes closed, the mark given its own
stamp); F2 BUILT (the reader — §5, §6) and REVIEWED; F3 BUILT with that
review's fixes (the fences — §7, §8; a pair and the claim of its invite
made one write — §4), REVIEWED and FIXED; F4 DONE — the two-guest device
suite `qa pass share` green twice (§12). Every part of the foundations is
built; what is left is the owner's (§11, and the roadmap's status). The owner's scope (2026-11-11): everything under the "Share with
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
  by one of them, and ends in what the other one's device adds, and that
  invite is spent by the very write that creates the pair (§4).
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
  the root. The sharer has no trigger of its own here: a second device of
  the owner that read the folders before the mark arrived and the notes
  after their re-sends says those notes private (the rule above), and if
  it then stays away they rest private — a new share can be partly
  private until that device returns or the sharer pushes those rows
  again. Private is the side this may err on.

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
  the differing ones queued; the same drain sends each again, once per
  such change.

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
// ... and the claim of that invite, in the same write (review of F2):
function claimsInvite() {          // on the pair's create
  let invite = getAfter(<the invite the pair cites>).data;
  return invite.pairId == pairId && invite.redeemedBy == uid();
}
function claimsOwnPair() {         // on the invite's update
  let pair = getAfter(<the pair the claim names>).data;
  return pair.inviteCode == code && uid() in pair.members;
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
  ids, which hold no `_`.
- **A code names one pair, once.** The id's shape was not enough: the
  claim of the invite was a second write the redeemer could leave out,
  and then end the pair, delete it and create it again under the same id
  for as long as the invite lived (thirty minutes at most) — the F2
  review did so on the emulator. The pair and the claim are now one
  write (`PairingGateway.createPair`, a transaction), and each one's rule
  reads the other document as it stands after the commit (`getAfter`): no
  pair without its invite claimed for it, no claim without a pair made
  from that invite that holds the caller. A claimed invite passes
  `authorisedByInvite` for nobody, and only its creator could mint the
  code again. A redemption that loses a race now leaves nothing behind,
  where it used to leave a pair to end.
- A build before this cannot create a pair once these rules are
  deployed (the id's shape, the claim in the same write): both phones
  update before pairing again. This build pairs against the rules as
  they were, too.
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

A second, smaller pull beside the bound space's (`_SharedReader`, a part
of the engine), run after a run's own pull and drain — never by a
drain-only run, never after a pull a leave cut, never in the background.
A table of the account's own that failed its pull does not hold it back
(what a partner shares is read from other documents); only the bind's
first merge waits for a pull that read everything, so the space has had
its whole say before another account's rows arrive.

Nothing in it may hurt the account's own sync, and nothing of it is the
run's: a failure of the shared read is logged and tried again, never a
failure or a pause of the run; its calls do not count as the run's — a
read of the pair must not end a back-off or lift a quota pause the
account's own sync is under — and its rows are not in the run's report.
The whole of it runs inside one guard, the local reads before the first
call and the stamp after the last included; only a halt goes through,
since it ends the run itself. It comes last, after the run's own books
are closed — its failure recorded, its success counted, the space's share
settled — so neither its deadlines nor a halt raised inside it can leave
those undone. The rules it depends on may not be deployed yet; a pair may
end between two calls.

1. **Whether.** An account that never paired, shares nothing and holds no
   shared row asks nothing: three local reads (the stored owner, "is
   anything marked", the database's own pairing), no call. That is every
   account until someone pairs, and it keeps an idle launch at what it
   cost.
2. **When.** A poll: nothing signals a partner's change, since this
   account cannot read the other's space document. Unasked, not more than
   once per `SyncEngine.sharedReadInterval` (five minutes); "Sync now"
   reads at once. A read with nothing new costs the pair, a page and a
   count per shareable table — eleven calls, about a dozen document reads
   plus the rules' own lookups of the pair.
3. **Who.** The active pair, asked of the server
   (`SharePartnerSource.activePartner` over `findActivePairs`, the
   earliest pair as pairing itself keeps it), not of the per-database
   record. "Could not be asked" is never "nobody": it throws, and the
   reader then changes nothing — and so does an active pair the server
   names that this build cannot read (`findActivePairs` fails the whole
   answer rather than leave one out). That one answer drives three
   things:
   - the account's **own marks** follow it — every mark of a pair that is
     not the account's is cleared (`FolderDao.clearSharesExcept`, decision
     c), stamped and queued like any edit;
   - the **shared rows held** are removed, all of them, when there is no
     pair any more or it is another one (§6);
   - the tables are read.
4. **Whose row is whose.** `sync_metadata['shared_owner']` names the
   account whose rows this database reads, with `shared_pair` beside it:
   a row is another person's exactly when its `owner_id` is that value.
   Before it is first set (`SharedRowDao.begin`), every row that carries
   an owner other than the bound account is made the bound account's and
   queued — as a write the space never saw, not a re-send, so a newer
   document under the same key is a conflict like any other: such a row
   is the person's own, left by a binding from before
   an unbind released its rows, and if that earlier account is the
   partner now — one person's two accounts — the first read would
   otherwise remove it for not being shared.
5. **What.** For each shareable table in parent-first order — events, day
   texts, skipped days, folders, notes — `SyncGateway.sharedPage`: the
   collection-group query `sharedPair == pair, ownerId == partner`, in
   arrival order from the table's own cursor (`shared_cursor.<table>`),
   with the same ten-second overlap on a resumed cursor. Across spaces the
   cursor carries a document's whole path, compared segment by segment as
   Firestore orders paths.
6. **Merge** (`SyncTableBinding.mergeShared`). Through the table's own DAO
   merge, the owner's copy winning whatever the stamps say
   (`CrdtMerge.everyStamp`, decision d — a document stamped like a
   shipped default included, which an own merge would not let win over an
   edit), stored under the partner's
   `owner_id`, in one transaction per page with its cursor. Apart from an
   own merge: nothing is queued, repaired, re-filed or stamped; the mark
   an event or a folder carries for its owner's devices is not stored —
   here a mark means "I share this"; the clock is not moved by another
   account's stamps. Three kinds of document are passed over:
   - one that is not the partner's or names another pair — the query pins
     both, so a gateway answered wrongly;
   - one a newer wire wrote (decision h): the highest such wire is kept
     under `shared_newer_wire`, and a build that reads it reads every
     table again from the start;
   - one that would take the place of, or hang under, a row of this
     person's own (`SharedRowRefused`): two accounts can hold one id —
     both restored one backup, or one kept the id of a row it was once
     given — and a shared row over it would hand the person's own data to
     the next "no longer shared". Checked per row: an event, a folder or a
     note under that id; a day row's event; a note's folder, which must
     also be a folder at all.
7. **A note's text** is read from the space its document lies in, by the
   hashes its manifest names (`readSharedChunks`), each held to its hash.
   A space that refuses — it does not name the pair, yet or any more —
   leaves those notes waiting, each under `shared_waiting.<note id>` with
   the space its document lies in. The next reads ask for exactly those
   documents again, one `get` each (`SyncGateway.readSharedRows`), then
   their text — twelve times at most, an hour of polls, after which a
   note is left to the daily read from the start. The first build read
   the whole table from its start for as long as one note waited: a read
   per shared note every five minutes, on a quota every account shares,
   and "waiting" is not always brief — the space rests at "no pair" while
   two of the owner's devices disagree (decision k). A note whose
   document is gone or refuses the read stopped being shared, and stops
   waiting; so does one whose retry ends any other way than still lacking
   its text — a newer wire wrote it, the merge refuses it — which is no
   wait for text and would otherwise be asked for at every poll with no
   try ever counted.
8. **Place** (`SharedRowDao.placeFolders`, inside each folders page's
   transaction). A shared folder whose parent was not shared — or is a
   folder this device holds as its own — stands at the top level:
   `parent_id` NULL here, the parent its document names kept under
   `shared_root.<id>`, so it goes back under that parent once it arrives.
   Never stamped: the difference from the owner's document is this
   device's own.
9. **Screens** hear of the pages through the hooks the own pull uses. A
   row that was removed is announced as *gone*, with where it stood — the
   folder a note lay in, a folder's parent (`SyncAppliedRow.gone`,
   `SharedRowDao`'s `SharedRemovals`, `FolderRepository.announceRemoved`,
   `NoteRepository.announceRemoved`): the announcements of a merged page
   re-read their rows to place them, and of a removed shared row nothing
   is left to read. Without it the device pass found a folder that had
   left still on the open page until the app was started again.

## 6. Rows that leave

A query cannot report a document that stopped matching it. After a table's
read the reader asks the server for the count of the same query (an
aggregation: one read per thousand rows) and compares it with the rows it
holds of that owner. Fewer on the server means rows left — a mark
cleared, a note moved out, a cloud copy deleted: the table is then read
again from the start, and what the server no longer returns is removed
here. More on the server means rows are still arriving, and the cursor
brings them.

The count is ordered as the page query is (`orderBy pushedAt`), though a
count has no order: only so is it served by the one index both need —
collection-group scope has no single-field indexes to merge for the bare
filter, and the emulator, which needs no index, would never have said so.
A count the server still cannot answer (an index building) skips that
table's look for rows that left and nothing else: the tables after it are
read, and the daily read finds what left. Only a walk that reached the
table's end removes anything — one the app leaving cut removes nothing,
and neither does one a gateway ended by promising more and sending
nothing.

A read from the start is exact for a row that stays shared: its document
stands at its old place in the order until a push of it commits and at a
later one from then on, so a walk that had not reached the old place
meets the new one. The comparison is one-sided on purpose: a document
this build passed over leaves the device holding fewer than the server
counts, which reads as "still arriving" — a leave can hide behind it
until the daily read, never the other way round.

Removed means hard-deleted, no tombstone, each table on its own evidence:
an event's day rows and a folder's notes leave when their own table says
so, a removed note's chunk rows with it (the search index drops what has
no note), and a folder left without its parent is placed at the top level
again. What the person added of their own — presence marks, alert
definitions, counter values — is theirs, stays in their space, and is
simply inert while its row is not there.

Everything another account owns is removed at once when the pair is found
ended, when another pair is found — with the same partner or not — and
when the database is unbound (inside the unbind's transaction, before its
own rows are released): there is then no reader to keep it true, and the
next bind takes every row it finds for its account's.

Once a day (`SyncEngine.fullPullInterval`, on its own stamp) every shared
table is read from the start whatever the count says: it brings back a
shared row this device lost or changed by a path that should not have
(§7).

*The limit.* The server revokes at once; this device's copy goes when a
read finds the grant gone. Where no run reaches the reader — signed out
with the binding kept, the manual cadence without "Sync now", never
online in the foreground — the rows stay on screen until one does (§11).

## 7. Read-only, and what stays personal

"Another account's" is one test everywhere: `owner_id` is set and is not
the account this database is bound for. (An unbound database holds none:
an unbind releases its own rows to NULL — the roadmap's §6.1 f — and
removes the rest, §6.)

Three layers keep such a row the owner's, each catching what the one
before lets through:

1. **The database refuses** (`SharedRowFences`, v54: twenty-four
   `BEFORE` triggers, the same on a fresh install and an upgraded one).
   Planned as a check in each service; built in the database because the
   writers are many and some are sets — a reorder of a folder's notes,
   "delete all", a label taken off every row that wears it, whatever a
   later change adds — and one that forgot the check would stamp another
   person's row and queue it. Fenced:
   - an insert, an update or a delete of a row of the five tables that
     the shared owner owns, and an update that would make an own row
     look like one;
   - anything of the person's own hung under a shared row — a note or a
     folder created in or moved into a shared folder, a skipped day or a
     day's text put on a shared event: it would show beside the owner's
     rows and be stranded when they leave;
   - the chunk rows of a shared note, which carry no owner of their own.

   A fence skips its row and nothing else (`RAISE(IGNORE)`): a statement
   over many rows goes on with the others. So a write of a shared row
   does not fail, it does nothing — a surface asks
   `SharedRowDao.isShared(table, id)` before it offers an edit, and the
   calls whose answer would otherwise be a lie throw `SharedRowException`:
   `createNote`, `createFolder`, `importNote` and `importFolder` inside a
   shared folder, which would hand back a row that was never stored, and
   `updateNote` and `moveNote` of a shared note or into a shared folder,
   which stamped, queued and answered as if they had written — an editor's
   auto-save would have taken its text for kept. `setSharedPair` answers
   false for a shared row: what is shared with me is not mine to share
   on.

   A delete does not pass through to what the person keeps on a shared
   event: `tombstoneEventCascade` does nothing at all for one, and "delete
   all my events" leaves the presence marks and alerts set on one
   (`SyncDao.onSharedEventSql`) — the event stays, so they do. The sweep
   that tombstones the counter values of a deleted note is for notes of
   the person's own; a shared note its owner deleted keeps what the
   person counted on it.

   The fences are armed only while `shared_owner` is present and stand
   down inside the reader's own transactions
   (`SharedRowDao.writing`, which sets `shared_writing` and takes it away
   before it commits, so no other transaction ever sees it and a rollback
   takes it along). A database that never read a shared row pays one
   lookup of a key that is not there. A migration step after v54 runs
   under the same licence, since it may have to rewrite every row.
2. **The push never sends one** (decision e). Whatever queued it, its
   entry is retired unsent, as an entry of a row that is gone is
   (`_Pusher._adopted`).
3. **The owner's copy comes back.** The reader lets the remote win
   (decision d) and reads every shared table from the start once a day
   (§6), so a local change that slipped through both lasts a day at most
   and never leaves the device.

**The person's own data comes first**, in both orders: a shared row never
takes the place of a row of theirs under the same id (`SharedRowRefused`,
§5), and a row of theirs that arrives from their own space under an id a
shared row took first removes that cached copy before it is merged
(`_Puller._makeRoom` over `SharedRowDao.evict`). Without the second, the
own document would have merged as "unchanged" into the partner's row and
been lost here when the share ended. What hung under the evicted copy
goes with it — an event's shared day rows, the shared notes directly
inside a folder — since under a row of the person's own they are exactly
what the reader refuses to store; a shared folder under it stays shared
and stands at the top level.

The eviction is a transaction of its own, committed before the page is
prepared. Inside the page's transaction it removed chunk rows a notes
page had already planned its bodies against: the merge failed, the
eviction rolled back with it, and the same page failed at every run from
then on — the notes pull of that account was wedged (review of F3).

**A row of theirs that names a shared row as its parent is held back** —
a note or a folder whose folder, a day row whose event, is held here as
shared (`SharedParentHeld`). Stored, the fences would turn the insert
into nothing while the merge counted it and the cursor passed it for
good; and evicting the parent for it does not hold, since the reader's
next look brings the shared row back with the person's row inside it.
Held back like any row that could not be merged, it shows among the
held-back rows, is tried again at the next start and at "Sync now", and
lands once its own parent arrived — which takes the shared one's place
by its key — or the share ended.

One writer needed the eviction spelled out: the events import
(`CalendarEventDao.importAll`) inserts with `INSERT OR REPLACE`, and
SQLite fires no delete trigger for the row a replace removes — an
archive's event under a shared event's id would have replaced it past
the fences, silently and without its day rows. It evicts first. The two
day-row imports replace too and need no eviction: a row of the person's
own is not stored on a shared event at all, and under an event of their
own no shared day row is kept. **No other writer of the five tables may
use a replacing insert** without settling the same question.

Personal, and so never refused: presence marks and alert definitions on a
shared event, counter values on a shared note — rows of the person's own,
keyed by the shared row's id, in the person's own space (readiness D18).
The owner's are never shared, so a partner's phone arms only the alerts
the partner set.

An event whose category this device does not have — the owner's custom
one — draws as the built-in fallback category until a surface decides
better; its link to a note the partner was not given is inert.

## 8. Backups and archives

- **Export.** The app writes no JSON backup any more — a backup is a
  copy of the database file — but the three calendar services' export
  lists remain (`exportData`, read by the archive helper the suites
  use), and they leave out every row another account owns and never
  write the share mark, so a JSON writer built on them later cannot leak
  a partner's rows.
- **Import** stores every row as this device's own (`owner_id` NULL)
  whatever the archive says (`JsonKeys.ownerIdOf`), and no mark. Every
  archive written before this build holds only its exporter's rows —
  nothing could be shared — so reading their `ownerId` as "mine" loses
  nothing; the format stays 7.
- **A copy of the database file** holds the cached rows together with
  `shared_owner`, so wherever it is opened they are still known as
  another account's: fenced, never pushed, and removed when the database
  stops syncing — a copy opened beside its original is unbound at once
  (`_healClaim`) — or when its reader next finds the grant gone. It
  cannot expire them without a run (§6's limit).
- A restore already unbinds, which removes what was shared (§6); the
  next bind lets the space win what it holds (D15), and the marks come
  back from there, never from a file.
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
3. **F3 — the fences.** The database's refusals (§7), the own row that
   evicts a shared one, backups and archives — with the F2 review's
   fixes. The push's backstop came with F2; the category fallback was
   already there (`CalendarCategories.resolve`).
4. **F4 — proof on devices.** The QA seam that sets a mark without a
   surface, and the two-guest flows (the roadmap's R10): pair, share an
   event and a folder, see them, change them, clear the mark, end the
   pair.

## 10. Must not change

The roadmap's §12, and: an account's own sync — every document it writes
for itself, every pull of its own space, the cost of an idle launch; the
pairing flow; backups staying importable; `owner_id` NULL meaning "mine".

## 11. Open for the owner

Collected as the build met them; none blocks the foundations.

- **How fresh a partner's rows are.** A poll every five minutes while the
  app is in use, at once on "Sync now". A live listener on the shared
  query would be instant and cost a re-read of the whole shared set
  whenever it re-attaches; the surface slice should decide with the
  switch in hand.
- **"Update ANTA to see everything shared with you".** The reader keeps
  the wire of what it could not read (`shared_newer_wire`) and reads
  again after the update; nothing shows it yet, since no surface speaks
  of sharing at all.
- **One id on both accounts.** A shared row whose id this person already
  uses for a row of their own is not shown (§5.6) — it happens to two
  accounts that restored one backup. Silent today; the surface could say
  "1 item could not be shown".
- **A partner with several synced databases** shares from each into the
  same pair, and the reader takes them as one set: the same row id in two
  of the partner's spaces reads as whichever was pushed later.
- **A shared copy that outlives its grant on a device that never
  syncs** (§6's limit). The server refuses at once; the device keeps
  showing the rows until a run reaches the reader. Expiring them locally
  — hide or remove what `shared_read_at` says was not confirmed for N
  days — would close it at the price of a partner's rows vanishing on a
  long flight. Not built; the surface slice should decide.
- **Imports no longer keep `ownerId`** (§8, replacing readiness D16 A).
- **A new share can be partly private** until a device of the owner that
  was behind returns (§3). It errs towards private, so nothing is done
  about it; a surface could show "sharing…" until the sharer's own
  device has read its rows back.
- **The partner's screens are not read-only yet** — the scope left the
  surfaces out. A shared note opens in the ordinary editor, and a save
  there is refused with `SharedRowException`, which the editor shows as a
  save that failed; "New folder" and "New note" inside a shared folder
  fail the same way; a rename, a move, a label or a delete of a shared
  row does nothing. Nothing is lost or sent, but nothing explains itself
  either: the surface slice (E1's badge, N1's read-only editor) asks
  `SharedRowDao.isShared` and disables instead.
- **The same note id in two of the partner's databases** (a copied
  database file, bound twice): one of the two documents is asked for its
  text in the other's space and waits, within the bound of §5.7.
- **An active pair this build cannot read** stops reconciliation on a
  device with nothing cached, which then shows "not paired" and could
  make a second pair; the rules cannot produce such a document, and an
  update is what reads it.
- **A person's own marks and alerts on a shared event** are in the
  calendar export lists while the event is not (§8): inert orphans in a
  JSON archive, should one ever be written from them.

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

### F2 — the reader (2026-11-12)

Built inline on Fable, after the fix pass. §5 and §6 are the design as
built.

- *Gateway.* `SyncGateway.sharedPage` / `sharedCount` /
  `readSharedChunks`; `SyncPullPage.spaces`. Firestore: the
  collection-group query pinned to the pair and the owner, its cursor
  carrying the document path (`compareSharedCursors`, `spaceOfPath`), the
  count as an aggregation, a chunk as a single document read. The fake
  keeps the pairs the rules would know (`pair`, `endPair`) and refuses a
  read through a pair that is not active or does not hold the owner, and
  a chunk of a space that does not name the pair.
- *Local.* `SharedRowDao` (`owner`, `begin`, `holdsOther`, `countOf`,
  `removeAbsent`, `removeAll`, `placeFolders`); the keys under
  `sync_metadata` (`shared_owner`, `shared_pair`, `shared_cursor.*`,
  `shared_read_at`, `shared_full_at`, `shared_newer_wire`,
  `shared_retry.*`, `shared_root.*`); `CrdtMerge.everyStamp`; the `shared`
  path of `FolderDao.mergeFolder`, `CalendarEventDao.mergeRemoteEvent`,
  `NoteDao.mergeNoteDocument`; `SyncTableBinding.mergeShared` on the five
  bindings, `SharedRowRefused`; `FolderDao.clearSharesExcept`.
- *Engine.* `_SharedReader` (`sync_shared_reader.dart`), called from the
  run after the drain; `SharePartnerSource` /
  `PairingSharePartnerSource` (`share_partner_source.dart`), wired in
  `SyncEngine._build`; `SyncEngine.sharedReadInterval`.
- *Stops syncing.* `SyncBindingService._unbind` removes the shared rows
  in its transaction; `SyncBindingService.onSharedRowsRemoved`, set by
  DI, reloads the screens.
- *The push* (pulled forward from F3, because a test met it): a queued
  row whose owner is not the bound account no longer reaches the gateway
  as a programming error that fails the run for as long as it stands.
  One statement decides (`_Pusher._adopted`): a row the partner shared is
  never sent and its entry is retired; any other owner is an earlier
  binding's, and the row is made the bound account's and sent.
- *Found while building.* The adoption in `begin` first ran only for rows
  with nothing queued — the count it went by was of queue entries
  written, not of rows — and a row left under an old account failed every
  run before any shared read could adopt it (the push, above). A note's
  text is refused per space, not per page, so one space that does not
  name the pair does not stop the notes of another.
- *Simpler than the own pull, on purpose.* A page of shared notes is one
  transaction whatever its bodies weigh, and a document that could not be
  merged is not parked: it is met again by the next read from the start
  (once a day, or at once when the server counts fewer rows than held,
  or while a note waits for its text).
- *Gate.* `dart analyze lib test` clean; the whole suite `+15979 ~17`.
  New: `sync_shared_reader_test` 30 (two accounts over the fake gateway:
  arrive, follow, leave, the pair ended or made again, no call for an
  unpaired account, the cost of an idle read, the interval, the daily
  read, the unbind, both adoptions, the refusals, a newer wire and the
  re-read after the update), `share_partner_source_test` 6,
  `firestore_sync_gateway_test` +3.
- *Not proven here.* The Firestore gateway's three new calls run against
  no backend in the suite — the query's cursor form, the aggregation and
  the indexes are proven by the rules suite over REST and by F4's device
  pass against the emulator, not by a unit test.

### F3 — the fences (2026-11-12)

Built inline on Fable. §7 and §8 are the design as built.

- *Schema.* v54: `SharedRowFences.statements`
  (`lib/database/migrations/shared_row_fences.dart`), created by
  `DatabaseIndexes.createSharedRowFences()` on both paths — the fresh
  install's `createAllIndexes()` and `_migrateV53ToV54`. No table or
  column changes. `runMigrations` runs every later step under the
  reader's licence. **A later step that drops or renames a column a
  fence names must drop the fences first and create them again**: SQLite
  refuses `ALTER TABLE … DROP COLUMN` while a trigger mentions the
  column, which the upgrade-chain suite met when it rebuilt the oldest
  shape.
- *Local.* `SharedRowDao.writing` / `isShared` / `ensureOwn` /
  `sharedAmong` / `evict`, `SharedRowException`;
  `SyncDao.keySharedWriting`; `removeAbsent`, `removeAll` and
  `placeFolders` run under `writing`; the reader's page transaction is
  one (`_SharedReader._apply`); `FolderDao.createFolder` and
  `NoteDao.createNote` refuse a shared parent; both `setSharedPair`
  refuse a shared row.
- *The own pull* evicts a shared row under a key its page is about to
  merge (`_Puller._applyPart`); nothing is read for a database that
  holds no shared row.
- *Backups.* `JsonKeys.ownerIdOf` answers null; the three `exportData`
  leave shared rows out.
- *Found while building.* Removing a shared note deleted the chunk rows
  under its id whoever owned the note — the fences suite caught it on a
  key that named a note of the person's own; the partner's note ids are
  now selected first. A query plan pinned by name moved to a covering
  index once the fences' lookups were in the schema; the pin is on the
  index, not on the word.
- *Suites.* `test/database/shared_row_fences_test.dart` 11 (each fence,
  the set statements that go on with the person's own rows, the reader's
  licence and its rollback, an unarmed database, the two refusals by
  name); `upgrade_chain_test` (trigger parity between a fresh install
  and the whole chain); the reader suite's eviction, exports and
  tamper cases; the two backup round trips and the category profile
  suite now expect an import to be the importer's own.

### F2 — the review, fixed with F3 (2026-11-12)

An independent review on Fable in a separate checkout of the F2 commit
(`6465fe47`): no blocker for what ships — nothing can set a mark yet —
and sixteen findings, six of them to settle before any share exists, one
reproduced on the emulator. Three were closed by F3 as designed; the
rest are fixed in the same commit.

| # | Found | Fixed by |
| --- | --- | --- |
| 1 | The count carried no order, so the one declared index would not serve it in production: every read but the day's first would have stopped after the events table | `orderBy('pushedAt')` on the count; a count that fails ends only that table's look for rows that left (§6) |
| 2 | A row of the account's own space under an id a shared row held merged into the partner's row as "unchanged" and was lost when the share ended | F3: the own pull evicts the cached copy first (§7) |
| 3 | A note or folder of the person's own inside a shared folder was stranded when it left | F3: the fences keep anything of theirs from being hung under a shared row (§7) |
| 4 | A backup could carry the partner's rows into the next bind as the person's own | F3: imports are the importer's own, exports leave shared rows out; a database-file copy keeps `shared_owner` (§8) |
| 5 | One note waiting for its text made every poll re-read every shared note | the waiting notes are asked for one by one, a bounded number of times (§5.7, `shared_waiting.*`, `SyncGateway.readSharedRows`) |
| 6 | A pair's id could be created again inside its invite's life — end, delete, create — because the claim was a write of its own | the pair and the claim are one write, each rule holding the other (§4); `PairingGateway.claimInvite` is gone |
| 7 | An active pair this build could not parse read as "no pair", which ends every share on the device | `findActivePairs` fails the answer (`FirestorePairingGateway.activePairsFrom`) |
| 8 | The local copy outlives the grant while no run reaches the reader | narrowed — an own table's fault no longer skips the read — and written down as the limit it is (§6, §11) |
| 9 | Rows adopted before the first shared read were queued as re-sends though the space never held them | queued as writes (`requeueRows(unpushed: true)`) |
| 10 | A shared document stamped like a shipped default lost to the copy here, which was then kept and queued | `everyStamp` overrides the seed exemption; a shared note returns before the kept-local path |
| 11 | The shared read could touch the run's outcome: its calls ended a back-off or lifted a quota pause, its rows were in the report, and its first and last statements stood outside its guard | the reader counts nothing into the run and is one guard from end to end (§5) |
| 12 | A new share can stay partly private until a device that was behind returns | by design (decision k); said in §3 and §11 |
| 13 | A comment promised "once more" where the code re-sends once per change | the comment |

Accepted, not changed: *14* — the push reads the real queue a second
time per batch when a re-send stands at its head and every real entry is
held; a held table is rare and the scan is bounded by the queue. *15* —
a mark set before a database was bound survives the bind's merge and is
re-queued; the reader's look at the pair clears it if it names no pair of
the account's.

Each fix has a test that fails without it — checked by taking the fix
out: the six reader fixes at once against their six tests (two tests
passed for the wrong reason on the first try and were tightened: the
day's first read never counts, and the cut had landed before the walk
began), the two rule clauses against the emulator.

Gate for F3 and the fixes together: `dart analyze lib test tool
test_driver` clean; the whole suite `+16003 ~17`; the rules suite 153 of
153 on the emulator (+3: no pair without its claim, an id made once, no
claim without its pair). `sync_shared_reader_test` 41 (+11: the waiting
note asked for alone, its bound, its end; the count that fails; a
tombstone, a day row and a seed-stamped document against the person's
own; the run's report; an own table's fault; a walk cut by a leave; the
adopted row queued as a write), `pairing_service_test` 31 (+2, and the
lost race now leaves no pair).

### F3 — the review, fixed with F4 (2026-11-12)

An independent review on Fable in a separate checkout of `d0130151`:
eighteen findings, eight of them reproduced through probe tests against
the real DAOs, the engine and the fake gateway. Two mattered before any
share could exist — the first wedged an account's own notes pull, the
second dropped a row of the person's own without a trace. No hole in the
rules, by reading.

| # | Found | Fixed by |
| --- | --- | --- |
| 1 | An own note arriving over a shared note's id with the same text failed its page at every run: the eviction, inside the page's transaction, removed chunk rows the page had planned against, and rolled back with the failure | the eviction is a transaction of its own, before the page is prepared (`_Puller._makeRoom`, §7) |
| 2 | An own row arriving under a shared parent was skipped by the fences, counted as pulled and passed by the cursor for good | it is held back (`SharedParentHeld`) and retried until its own parent arrives or the share ends (§7) |
| 3 | Deleting a shared event, or "delete all events", tombstoned the person's own presence marks and alerts on it while the event stayed | the cascade does nothing for a shared event; the wipe leaves what hangs on one (§7) |
| 4 | The waiting-note retry was unbounded whenever the retry ended any other way than still lacking its text | such a note stops waiting (§5.7) |
| 5 | `importNote` / `importFolder` into a shared folder failed with a bare "no element" | they refuse by name, as the two creations do |
| 6 | A save or a move the fences skipped still stamped, queued and answered as if it had written | `updateNote` and `moveNote` throw `SharedRowException` (§7) |
| 7 | The two day-row imports replace as the events' did | looked at again: no shared day row can stand under their keys, so nothing is evicted — said where they insert (§7) |
| 8 | The chunk update fence looked at the old note only | both ends |
| 9 | Rows evicted by the own pull reached no screen | removals are announced as gone, with where the row stood (§5.9) — the device pass had met the same on the reader's side |
| 10 | A pair without a second account read as "no pair" | `partnerOf` throws |
| 11 | The shared read stood in front of the run's own bookkeeping, and a halt inside it skipped that | the books are closed first (§5) |
| 12 | A walk a gateway ended by promising more and sending nothing counted as complete | a walk from the start then removes nothing (§6) |
| 13 | A redemption whose write landed and whose answer was lost threw, and a second try said "code not valid" | `redeem` asks the server once before it believes the failure; an invite that ran out in between is "not valid", not "not allowed" |
| 15 | An owner's delete of a shared note swept the partner's own counter values under the owner's stamp | the sweep is for notes of the person's own (§7) |
| 18 | `evict` read the owner before looking at its keys; `writing`'s cleanup could mask the body's error | both |

Accepted, in §11: 14 (an unreadable active pair on a device with nothing
cached), 16 (one note id in two of the partner's spaces), 17 (marks of a
shared event in the export lists). Of 10, the other half — more than ten
active pairs with no order — is left: the rules hold a pair to two
accounts and reconciliation ends the extra ones.

Found while fixing: finding 2's first answer, evicting the shared parent
for the own row, did not hold — the reader's next look brought the
shared folder back with the person's note inside it, which its own test
showed; hence "held back". And the day-row imports of finding 7, given
an eviction, would have removed an owner's skipped day for a row the
fences then refuse — taken out again.

### F4 — proof on devices (2026-11-12)

The two-guest saved suite `qa pass share -d emulator-5556`
(`tool/qa/flows/share/`, cookbook
`.claude/skills/qa-emulator/references/share-pass.md`): two fleet guests,
two accounts on the local Firebase emulator suite, the app's own UI for
everything but the share itself — sign-in, bind, the pairing sheet, the
calendar and the browser on the partner's guest, the unpair dialog. Six
flows: pair; a shared event arrives; a shared folder arrives with what is
under it and its notes' text; a folder added under it later follows; made
private, both are gone from the open pages; the pair ended, the partner
is told once and the event is gone. Green twice, each against a freshly
started suite: 6/6 in 117.6 s and in 120.6 s.

This is the first run of the Firestore gateway's shared page, its cursor
and its count, of the chunk read from another account's space, and of
the one-write redemption, against a backend and the deployed-to-be rules.

- *The seams.* `qa share event|folder "<name>" [--off]` (agent op
  `share`, protocol v3) calls the two service calls a switch will make;
  `qa set account=<sub>:<email>` (`QaIdentity`) gives the second guest
  its own emulator account from the one APK. Harness: a step may lead
  with `-d <serial>` and runs on that guest's own connection; `text
  --match --capture` and `{{var:name}}` carry the invite code across.
- *Ids.* `pairing-generate`, `pairing-code`, `pairing-code-field`,
  `pairing-connect`, `sharing-unpair-confirm`, `sharing-ended-close`.
- *What it found.* The pairing sheet closed itself on every "paired"
  state, and the second — the partner's name arriving — popped the page
  under it: the redeemer landed on Settings. It closes once
  (`test/widgets/pairing_sheet_test.dart`, which fails on the old code).
  And a shared row that left stayed on the open page until a relaunch
  (§5.9).
- *Not covered.* §11's surfaces; the partner's own presence or alert on
  a shared event; one id on both accounts; a newer wire; a second device
  of either account; D2 while paired, whose device pass is still owed;
  the real project, which is the owner's phone check.

Gate for the review's fixes and F4 together: `dart analyze lib test tool
test_driver` clean; the whole suite `+16029 ~17`. `sync_shared_reader_test`
47, `shared_row_fences_test` 15, `pairing_service_test` 34,
`pass_command_test` and `agent_tree_test` with the harness's new cases,
`app_sync_apply_hooks_test` and `share_partner_source_test` +1 each. The
rules were not changed by this part; the rules suite stands at 153.

*Later the same day:* a seventh flow, `06_delete_account` — the partner
deletes its account after the pair ended; the deletion's row runs to
"Account deleted", the page is signed out, and the owner's side is
untouched. 7/7 in 160.6 s. This is the first device pass of the roadmap's
D2; an account deleted while its pair is still active is not walked yet.
