# Cloud Sync Phase 01 — Pairing

**Status: shipped 2026-08-17.** No schema change. Depends on Phase 00. See
`cloud-sync-roadmap.md` for the architecture stance.

Deployment steps the code does **not** do, required before pairing works on a
device:

1. `firebase deploy --only firestore:rules,firestore:indexes` — both
   `firestore.rules` and `firestore.indexes.json` are committed. The index is
   not optional: `members array-contains` + `status ==` is a composite query,
   and without it every reconcile fails `failed-precondition` in release
   builds where nobody sees the console hint.
2. A console-configured **TTL policy on `invites.expiresAt`**. Spark has no
   Cloud Functions, so nothing else reaps abandoned invites.
3. **Firebase App Check.** Rules can authorise but cannot rate-limit, and
   Spark's 50k reads / 20k writes per day have no overflow: one signed-in
   account can otherwise exhaust the project's daily quota and take pairing
   down for everyone. Also confirm anonymous auth is disabled.

## Goal

Two signed-in accounts link into one pair. Nothing syncs yet — this phase
ends when both devices show each other as paired, either side can end the
link, and the other side finds out.

## The failure modes this design exists to prevent

The original sketch (invite → redeem → delete invite; unpair removes your uid
and deletes the doc when empty) had six silent failures. Every decision below
traces back to one of them.

1. **Stranded creator.** Deleting the invite on redemption destroys the only
   channel back to the creator, and nothing persisted the generated code, so
   an app restart between generate and redeem left the creator permanently
   unpaired while the redeemer sat in a pair of one.
2. **Double-pairing.** Both sides generate, both redeem — two pair docs, each
   device stores a different one, both screens say "paired". Phase 02 then
   syncs into two disjoint collections forever.
3. **Second device / second database reads "not paired"**, because pairing
   lives in per-database `user_settings`. The obvious user response is to
   pair again, which is failure 2.
4. **Unpair leaves the other side blind**, and from Phase 02 a deleted pair
   doc orphans its `events`/`notes` subtree — Firestore has no recursive
   delete without Cloud Functions, which the Spark plan does not include.
5. **Offline hangs.** Firestore's `set()` resolves against the local cache
   and its future does not complete until a server accepts the write, so a
   naive `await` on "generate code" spins forever with no error.
6. **Stale `pairId` outliving its account.** Sign in as a different Google
   account and every read is `permission-denied` with no explanation.

## Remote shape

```
pairs/{pairId}                       // random id; never deleted, never reused
  members:   [uidA, uidB]            // never shrinks — access + tombstone read
  status:    'active' | 'ended'
  createdAt: <server ts>             // deterministic tie-break, see below
  endedBy:   uid | absent
  endedAt:   <server ts> | absent
  profiles:  { uidA: {displayName, photoUrl}, uidB: {…} }
  permissions: { uidA: {allowPartnerEdit: false}, uidB: {…} }

invites/{code}                       // create-only, short-lived, single-use
  creatorUid, createdAt, expiresAt
  pairId, redeemedBy                 // written by the redeemer, read by the creator
```

`profiles` is load-bearing, not decoration: `members` holds uids only, and
the UI has to name the partner. Each member may write only its own key.
`permissions` is seeded here with `allowPartnerEdit: false` for both so
Phase 02 only adds the rules clause rather than the field.

**Unpair is a tombstone, never a delete.** `status: 'ended'` plus `endedBy`
and `endedAt`; `members` never shrinks. Both sides keep read access, so a
partner who was offline for a month still learns who ended it and when — and
the doc survives to anchor whatever Phase 02+ hung underneath it. Re-pairing
always mints a fresh `pairId`; an ended pair is never revived.

**Invite code.** 8 characters from `23456789ABCDEFGHJKMNPQRSTVWXYZ` — no
`0/O/1/I/L/U`, because the code gets read aloud. Displayed `XXXX-XXXX`;
input is uppercased and stripped of non-alphanumerics before lookup.
Creation is a create-only transaction retried up to 5 times on collision.

**Convergence rule.** Pair ids stay random. The redeem path refuses to create
a pair when the client already knows of an active one, and reconciliation
resolves anything that slips past: if a uid ends up in more than one active
pair, **the earliest `createdAt` wins and the rest are tombstoned** (`pairId`
breaks exact ties). Both devices compute the same answer independently, so this
converges with no conflict UI. Security rules *cannot* enforce
one-active-pair-per-uid — that needs a query — so this is a client invariant,
and it is only sound because reconciliation runs on sign-in and on every
opening of the Sharing page.

**The local `pairId` is a cache, not the truth.** The server answers "which
active pair contains my uid". That single inversion fixes failures 1, 2, 3
and 6 at once.

## Security rules

`firestore.rules` ships in this phase (committed — it holds no secrets), so
Phase 02 only extends it with the consent clause.

- **`pairs`** — `get`/`list` when `uid() in resource.data.members`; `list` is
  what reconciliation needs (`where('members', arrayContains: uid)` +
  `status == 'active'`), which needs the committed composite index.
  `create` requires `members.size() == 2` including self, `status ==
  'active'`, `createdAt == request.time`, both `profiles` entries limited to
  `displayName`/`photoUrl`, both `permissions` entries seeded to
  `allowPartnerEdit: false` — **and proof of consent**: the doc carries the
  `inviteCode` it was born from, and the rule `get()`s that invite to confirm
  it is live, unclaimed, and created by the *other* member.
  Without that last clause, uid is the only thing needed to force a pair on
  someone, and this app prints the signed-in uid on screen. A planted pair
  with an earlier `createdAt` would even win reconciliation and evict the
  victim's real one. The invite exists before the pair, so unlike the reverse
  direction a rules `get()` can see it.
  `update` may only tombstone (`status: 'ended'`, `endedBy == uid()`,
  `members` unchanged), rewrite your own `profiles[uid()]`, or flip your own
  `permissions[uid()].allowPartnerEdit` — consent is the owner's to give, and
  letting the redeemer set both entries at creation would hand it permanent
  write access with no revocation path. `delete: if false` — the tombstone
  model depends on the doc surviving.
- **`invites`** — `get` while `expiresAt > request.time`, or when the document
  is absent (see below); `list: if false`, so codes cannot be enumerated.
  `create` requires `creatorUid == uid()`, exactly the three creation keys,
  `createdAt == request.time`, and `expiresAt` within 30 minutes of
  `request.time`: client clocks are not trusted, or a skewed device mints a
  year-long invite, and the window has to absorb the skew a hand-set phone
  clock realistically carries. `update` is the redemption write only — not
  your own invite, not already redeemed, touching only a non-empty `pairId`
  plus a `redeemedBy` equal to the caller. The pair id is deliberately *not*
  verified here: a rules `get()` cannot see a pair created in the same batch,
  so the creator verifies instead by reading the pair. `delete` only by the
  creator, which is the cancel path.

Because expired invites are unreadable, the client cannot tell expired from
mistyped from already-used. Those collapse into **one** user-facing message.
That is a consequence of the rules, not an oversight.

Two sharp edges follow from how rules treat a missing document. `resource` is
null for a code that does not exist, so `resource.data.expiresAt` *errors* and
denies — the `get` rule therefore allows `resource == null` explicitly, and
`redeem` re-raises `permissionDenied` as `codeInvalid`. Without both halves the
single most common failure in the whole flow, a one-character typo, would tell
the user "permission denied".

Two operational notes:

- `firebase.json` is currently gitignored but `firebase deploy --only
  firestore:rules` needs its `firestore` block. Either un-ignore it (it
  carries project ids, not keys) or document the block for fresh clones.
- Configure a Firestore **TTL policy on `invites.expiresAt`** in the console.
  Spark has no Cloud Functions, so nothing else ever reaps abandoned invites.

## Design

- **`PairingGateway`** (`lib/services/pairing_gateway.dart`, new) — abstract
  interface + `FirestorePairingGateway`, mirroring how `AuthService` hides
  `firebase_auth`. Only plain models (`PairRecord`, `InviteRecord`) cross the
  boundary; no `DocumentSnapshot` escapes, same rule as `AppUser`. This is
  `cloud_firestore`'s first real use and the precedent Phase 02's
  `SyncGateway` follows.
  **Offline handling lives here**: `runTransaction` fails fast without a
  server, so creation and redemption both go through it; authoritative reads
  use `Source.server`; every call has a timeout; `unavailable` and
  `deadline-exceeded` map to `PairingError.offline` instead of an infinite
  spinner.
- **`PairingService`** (`lib/services/pairing_service.dart`, new) owns the
  workflow: code generation with collision retry, redemption, the
  creator-side invite listener that picks up `pairId`/`redeemedBy`,
  reconciliation, tombstoning, and exception → `PairingError` mapping. A fake
  gateway makes the whole state machine testable.
- **Reconciliation** runs on sign-in, on opening the Sharing page, and after a
  database switch: clear local state when the stored account uid no longer
  matches the signed-in one; then query active pairs containing my uid — zero
  means the pair was tombstoned while offline (raise the ended notice), one
  means adopt it, more than one means keep the earliest `createdAt`
  (`pairId` breaks ties, because `Timestamp` truncates to microseconds and two
  devices disagreeing would tombstone each other's pick) and tombstone the
  rest. Expired pending invites are dropped. The query is bounded and the
  tombstone loop is capped — both are unmetered free-tier quota otherwise.
  **There is no app-resume hook**: nothing outside the Sharing page holds a
  `PairingBloc`, so a partner who unpairs is discovered the next time that
  page is opened, not the next time the app is foregrounded. Phase 04 owns
  closing that gap if it proves to matter.
- **A tombstoned pair is not automatically a break-up.** The dedup path
  tombstones the loser of a both-sides-redeemed race, and the losing device is
  watching that exact doc. `_onPairChanged` therefore reconciles before
  raising the ended notice — otherwise the convergence mechanism's own cleanup
  pops a false "your partner ended sharing" dialog on a device that is, in
  fact, still paired.
- **Settings storage.** Seven keys through `SettingsService` +
  `SettingsKeys` — never raw keys: `pairing_pair_id`, `pairing_account_uid`,
  `pairing_partner_uid`, `pairing_partner_name`, `pairing_pending_code`,
  `pairing_pending_expires_at`, `pairing_ended_notice_pending`.
  `pairing_pending_code` is what stops the creator being stranded — the code
  must survive an app restart.
  Because settings live in the per-database `user_settings` table, pairing is
  per-database by construction, and this is where pairing state joins the
  `DatabaseLifecycle` reset contract (identity itself stays global and off
  it).
  **These keys stay out of `BackupService._exportSettings` on purpose** —
  restoring a backup onto a third device must not clone a pair membership.
  Excluding them is the default; this line exists so nobody "fixes" it later.
- **`PairingBloc`** (`lib/bloc/pairing/`, new) rather than more `SyncBloc`
  states: pairing is orthogonal to auth (signed-in × unpaired / pending /
  paired / ended) and merging the two sealed hierarchies is combinatorial.
  Recoverable errors ride as a nullable `PairingError?` **on the state they
  failed from**, not as a separate failure state — a failed cancel must not
  drop the code the user is currently reading aloud. Availability comes from
  `AuthService.isAvailable`, never `SyncAvailability` directly.
- **Dedicated error taxonomy.** Phase 00's "every failure becomes
  `signInFailed`" is fine for one button and wrong here, because each
  redemption failure implies a different next action. `PairingError`
  (`offline`, `notSignedIn`, `unavailable`, `codeInvalid`, `ownCode`,
  `alreadyPaired`, `permissionDenied`, `unknown`) resolves through
  `PairingErrorMessages.of(l10n)` — the `MoneyLineError` /
  `MoneyErrorMessages` pattern, a sealed `switch` with no key lookup. There is
  deliberately no `partnerAlreadyPaired`: rules stop a redeemer reading the
  creator's pairs, so it is undetectable where it would be shown. The creator
  refusing to mint a code while already paired covers the real case.
  A failure carries the `PairingAction` that produced it, because the code
  field must only claim redemption failures — a failed "create a code" putting
  a red border on a field the user never touched is a worse lie than no
  message at all. Sign-in gets the same treatment through `AuthError`.

## UI

The Sharing page (`lib/pages/sync_settings_page.dart`) grows a **Pairing**
section under Account, one row per state, built the way `_accountRow`
already switches:

| State | Row |
| --- | --- |
| unavailable / signed out | disabled "Sign in to share" — keeps the section findable by the settings search |
| unpaired | `Icons.link_rounded`, "Not paired" → opens the sheet |
| inviting | code + live countdown → opens the sheet |
| redeeming | inline spinner, matching `SyncSigningIn` |
| paired | `UserAvatar` + partner name, trailing Unpair — deliberate symmetry with the sign-out row |
| ended | `Icons.link_off_rounded`, "<Name> ended sharing", trailing Dismiss |

**`lib/widgets/pairing_sheet.dart`** (new) hosts the flow — a modal bottom
sheet, the `event_editor_sheet` / `move_history_sheet` precedent. Settings
rows stay scannable; the sheet carries the generated code in monospace, a
live countdown, Copy / Share / Cancel, and the code field with **inline**
error text under it (inline beats a snackbar when the user is mid-correction).
Cancel matters: without it an overheard code stays live until it expires.
Progress is inline, never a blocking dialog.

**Unpair** confirms through `AppDialogs.confirm` (`isDestructive`,
`Icons.link_off_rounded`) with copy that names the consequence — *"Your notes
and events stay on this device. Nothing new will be shared."* Nothing about
pairing tells the user whether local data survives, so the dialog says it.

**When the partner ends it**, a one-time `AppDialogs.action` fires the first
time the ended state is observed, and the Sharing row persists until
dismissed. This is Phase 04's "silent failure is the worst outcome for a
trust feature" applied early: the app has no push notifications, so next
foreground is the only moment available.

**Sign-out gains a confirmation when paired** — it currently fires
`SignOutRequested` with none, and signing out silently stops sharing.

All strings en/de/ro together.

## Done when

Two devices show each other as paired after one invite round-trip, under
every interleaving including both-generate-both-redeem; force-quitting the
creator mid-invite still adopts the pair; unpair removes the link on both and
the passive side is told; a second database on the same account adopts the
existing pair instead of forking a new one; airplane mode reports offline
instead of hanging; still nothing syncs.

## Verify

`dart analyze lib`; `flutter gen-l10n` (untranslated counts unchanged);
`flutter test` — `PairingService` and `PairingBloc` suites against a
hand-written fake gateway, in `test/bloc/sync_bloc_test.dart`'s style (no
mocking library in this repo), covering each of the six failure modes above.

**The rules are tested against the real rules engine**, not reasoned about —
they are the only part of this feature with no local safety net, and review
alone found two critical holes in them. `test/firestore/rules_test.dart` drives
the Firestore emulator over its REST API with unsigned tokens, and is tagged
out of the default run because it is the one suite with an external dependency:

```powershell
firebase emulators:start --only firestore --project demo-anta --config firebase.firestore.json
flutter test --tags firestore-rules --run-skipped
```

It pins the forced-pair refusal, the consent-escalation refusal, membership and
`createdAt` immutability, delete-never, code non-enumerability, the lifetime
ceiling, claim-once, and that a nonexistent code reads 404 rather than 403.
Re-run it on every `firestore.rules` change — the handshake in
`cloud-sync-connections-design.md` rewrites them wholesale.

Finally, a two-device manual round-trip with two Google accounts.
