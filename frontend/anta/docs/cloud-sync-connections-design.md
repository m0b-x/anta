# Cloud Sync — Connections, Handshake, QR, Links, Push (Design)

**Status: design, 2026-08-18. Nothing here is implemented.** Builds on Phase 01
as shipped (`cloud-sync-phase-01-pairing.md`); revises the Phase 02/03 plans
where multi-connection forces it. Android-first throughout: every iOS-side
piece (camera scanner's 15.5 floor, APNs, Universal Links) is blocked on the
Mac-side setup the roadmap already lists as outstanding, and is explicitly
deferred, not designed around.

## Context

Phase 01 links exactly two accounts and enforces one active pair per account.
That shape is too small in two ways. First, one person realistically holds
several simultaneous links — a partner for the shared calendar, a training
buddy for a shared folder — and the one-active-pair invariant makes the second
link impossible rather than merely unsupported. Second, redemption is instant
and blind: whoever types a valid code first is linked, and the creator never
sees who before it happens. For a feature whose whole design vocabulary is
consent, that is the wrong default.

This document redesigns pairing into **connections**: an account holds up to
five simultaneous two-member links, each formed by an explicit
claim-and-approve handshake, joined by typing a code, scanning a QR, or
tapping a shared link — and each side is told by push notification when a
request arrives, is approved, or a connection ends, instead of discovering it
on the next Sharing-page open.

What changes for the user: the Sharing page's single pairing row becomes a
connection list; redeeming a code becomes "request → the other person approves
you by name and photo"; invites can be shown as a QR or shared as a tappable
link; and the three events worth knowing about arrive as notifications.

What does not change: local SQLite stays the source of truth, the pair
document stays the wire shape, tombstones stay tombstones, and every one of
Phase 01's six failure modes must still be impossible — the risk register
below checks each.

## Decisions

1. **Term: "connection."** *Pairing* survives as the verb — the handshake that
   forms a link between exactly two accounts — *connection* is the noun for
   the resulting link. User-facing strings say connection/connect/end
   connection. Wire names (`pairs`, `pairId`, `invites`) and the Dart types
   that model the wire (`PairRecord`, `PairProfile`, `PairingGateway`,
   `PairingError`, `PairingService`, `PairingBloc`) keep their names; only the
   types whose *shape* changes are renamed (`PairingSettings` →
   `ConnectionSettings`, `PairingStatus` → `ConnectionsStatus`, the
   `PairingPaired` state → `PairingConnected`). One deployed rules file, one
   TTL policy, and existing pair docs stay valid; the rename cost lands only
   where the diff already lands.
2. **Cap: 5 active connections per account**, enforced client-side at mint and
   at claim (rules cannot count). Five covers the plausible social graph of a
   personal tracker with headroom, keeps reconciliation and the Phase 02/03
   listener fan-out linear-but-small, and stays under the gateway's raised
   query bound (see below) so races beyond the cap are still visible.
3. **Dedup generalizes from "one pair per uid" to "one pair per unordered
   member set."** Reconciliation groups active pairs by member set; within a
   group, earliest `createdAt` wins with `pairId` as tie-break (unchanged
   logic, now per group); distinct member sets all survive. Both devices still
   compute the same answer independently.
4. **Handshake: claim, then approve.** A redeemer files a claim under the
   invite (`invites/{code}/claims/{uid}`); the creator sees claimants by name
   and photo and approves one; **the creator now creates the pair doc**, with
   rules proving both consents — the invite proves the creator's, the claim
   proves the claimant's. Redemption stops being a race won by typing speed.
5. **Invite lifetime rises to 30 minutes** (rules cap widens to 1 hour of
   headroom). Ten minutes fit a code read aloud; a link shared over chat plus
   an approval round-trip does not. Entropy posture is unchanged: 8 chars over
   30 symbols with `list: false` is out of brute-force range at any of these
   lifetimes. One pending invite at a time stays the rule — a second
   simultaneous code doubles the UI and serves no flow.
6. **QR encodes the invite link, not the bare code** — `qr_flutter` renders,
   `mobile_scanner` scans. A link-QR works both in-app and when scanned by the
   system camera (it opens ANTA via the App Link).
7. **Deep link: Android App Links on the project's free Firebase Hosting
   `*.web.app` domain.** No custom `anta://` scheme: messengers linkify only
   http(s), so a custom-scheme "share invite" is not tappable where it is
   actually shared. Hosting is free on Spark and serves both
   `.well-known/assetlinks.json` and a fallback page — the "needs a domain"
   objection dissolves, unless the user wants a vanity domain (their call).
8. **Push: FCM data messages, sent by a minimal Cloudflare Worker relay.**
   This is the honest answer to "no Cloud Functions": FCM's v1 send API
   requires service-account OAuth (the legacy server key was retired in 2024),
   and a service account embedded in an APK is public — anyone could notify
   anyone. The trusted environment has to exist; the smallest free one is a
   ~100-line Worker (Cloudflare free tier, 100k req/day, no card) holding the
   key. In-app immediacy (snapshot listeners, resume-time reconcile) ships
   first and works with the Worker absent; push is additive.
9. **Phase 02's unit of calendar sharing is one designated connection.** Whole
   calendars merge with exactly one partner — a mutual per-connection opt-in —
   not with all N. Phase 03's `is_shared` boolean becomes `share_pair_id`: a
   folder shares into exactly one connection, and a note belongs to at most
   one connection (its folder's). N-way merge of the same rows multiplies
   every Phase 04 hazard and serves no one; two folders is the workaround for
   the rare "share with both" case.

## Local state shape

`ConnectionSettings` replaces `PairingSettings` — same value-object +
non-clearing `copyWith` discipline, same `_write`-persists-before-cache rule,
same exclusion from `BackupService._exportSettings`:

- `connections_account_uid` — unchanged role (the cross-account guard).
- `connections_list` — **one JSON-encoded key** holding the array of
  `{pairId, partnerUid, partnerName}` entries, replacing `pairing_pair_id` /
  `pairing_partner_uid` / `pairing_partner_name`. A single key keeps the list
  itself atomic on disk; the value object keeps a half-updated state
  unrepresentable in memory, exactly as today.
- `connections_pending_code`, `connections_pending_expires_at` — unchanged
  (one invite at a time; the code must still survive a restart or the creator
  is stranded — failure mode 1).
- `connections_pending_claim` — **new**: `{code, creatorUid}` persisted while
  this device waits for approval, for the same reason the creator persists
  the code: a restart mid-wait must resume the waiting state, and the
  server-truth reconcile is what actually resolves it.
- `connections_ended_notices` — JSON array of `{partnerUid, partnerName}`
  replacing the single boolean: with N connections, two partners can end
  theirs while this device is offline, and each deserves its own notice.
- `connections_calendar_pair_id` — Phase 02's cache of the designated calendar
  connection (truth lives on the pair doc; see the ripple section).

The old `pairing_*` keys are read once on first load, migrated into the new
shape when they describe a live single connection, then deleted. No Drift
migration — `user_settings` is a key-value table.

`PairingService` keeps its singleton, `DatabaseLifecycle` reset registration,
listener discipline, and error streams. `findActivePairs` returns the full
list; `_maxActivePairs` rises from 10 to 15 (cap 5 + a duplicate race per
connection + hostile-plant headroom, still bounded); `_maxTombstonesPerReconcile`
stays 4 — the next reconcile finishes what one leaves.

`PairingError` changes: `alreadyPaired` splits into `connectionLimit` (you or
this action would exceed 5) and `duplicateConnection` (the invite's creator is
already a partner — checked client-side from the invite read before filing a
claim; the same-two-people both-redeem race that slips past converges via the
per-member-set dedup). New states, not errors: `PairingRequestPending` (this
device filed a claim and is waiting) and the creator-side claims list riding
on `PairingInviting`.

## Remote shape

```
pairs/{pairId}                        // random id; never deleted, never reused
  members: [uidA, uidB]               // never shrinks — access + tombstone read
  status: 'active' | 'ended'
  createdAt: <server ts>              // per-member-set dedup tie-break
  endedBy, endedAt
  inviteCode                          // consent proof, checked at create
  profiles: { uidA: {displayName, photoUrl}, uidB: {…} }
  permissions: {
    uidA: { allowPartnerEdit: bool, shareCalendar: bool },   // shareCalendar new
    uidB: { … }
  }

pairs/{pairId}/events/{eventId}       // Phase 02 — the designated calendar
pairs/{pairId}/absences/{id}          //   connection only (both shareCalendar
pairs/{pairId}/occurrences/{id}       //   flags true)
pairs/{pairId}/folders/{folderId}     // Phase 03 — folders whose
pairs/{pairId}/notes/{noteId}         //   share_pair_id == this pairId
pairs/{pairId}/notes/{noteId}/chunks/{index}

invites/{code}                        // create-only, short-lived, single-use
  creatorUid, createdAt, expiresAt    // lifetime 30 m (rules cap 1 h)
  pairId, redeemedBy                  // NOW written by the CREATOR on approval

invites/{code}/claims/{claimantUid}   // NEW — doc id = claimant uid, so one
  displayName, photoUrl               //   claim per account is structural
  createdAt: <server ts>
  expiresAt: <mirror of invite>       // own TTL target — see orphan note

users/{uid}/tokens/{token}            // NEW — FCM registration, global to the
  createdAt: <server ts>              //   account, never per-database
  platform: 'android'
```

## Security rules changes

**`pairs` create inverts the consent proof.** Today the redeemer creates the
pair and `authorisedByInvite()` demands `invite.creatorUid != uid()`. Now the
*approver* creates it, so the clause becomes: `invite.creatorUid == uid()`,
the other member is not me, and — the new half —
`exists(/invites/$(code)/claims/$(otherUid))`: the claimant filed a claim on
this exact invite. The invite is still the creator's consent token; the claim
doc is the claimant's. Neither side can force a pair on the other: a stranger
who knows your uid has no live invite of yours, and a claimant cannot create
the pair at all. `profiles` validation changes shape but not spirit: the
creator seeds **both** entries — its own from the account, the claimant's
copied from the claim doc — which incidentally closes today's brief
"partner shows as a bare uid" window. `permissions` seeding widens to
`{allowPartnerEdit: false, shareCalendar: false}` for both, and
`rewritesOwnConsent` widens its `hasOnly` to both boolean keys. Everything
else — `members.size() == 2` including self, `createdAt == request.time`,
tombstone-only updates, `delete: if false` — is untouched.

**`invites` update flips direction.** The redemption stamp
(`pairId`/`redeemedBy`) is now written by the **creator** at approval:
`resource.data.creatorUid == uid()`, still live, still unclaimed, still only
those two keys — plus `exists(claims/$(request.resource.data.redeemedBy))`, so
the creator can only stamp an actual claimant. The old "non-creator writes the
stamp" clause is deleted outright. The stamp is what the waiting claimant's
invite watch reacts to: `redeemedBy == me` → read the pair (I am a member) →
adopt; `redeemedBy == someone else` → the invite went to another claimant,
show the neutral not-approved message.

**`invites/{code}/claims/{claimantUid}` is new.** `create`: claimant id must
equal `uid()`, keys `hasOnly(['displayName', 'photoUrl', 'createdAt',
'expiresAt'])` with the same `validProfile` size bounds, `createdAt ==
request.time`, `expiresAt` equal to the parent invite's (a rules `get()` on
the parent — the invite exists first, so it is visible), parent live and
unclaimed, and `creatorUid != uid()` — you cannot claim your own code.
`update: if false` — a claim is immutable, which is what keeps a claimant from
escalating: they hold no write path to the invite, no write path to their
claim after filing, and the pair-create rule requires being the invite's
creator. `get`/`list`: the invite's creator (this is how the approval sheet
enumerates claimants) or the claimant reading its own. `delete`: the claimant
(cancel my request) or the creator (dismiss a claimant) — a dismissed
claimant's own-claim watch sees the deletion and shows the same neutral
not-approved end state, deliberately indistinguishable from losing to another
claimant.

**Two sharp edges carry over and one is new.** The `resource == null` allowance
on invite `get` stays (typo must read as invalid code, not permission-denied),
and claims inherit the same treatment. The new one: **a TTL-reaped invite does
not delete its `claims` subcollection** — Firestore TTL deletes the document
only, and Spark has no recursive delete. That is why claims carry their own
`expiresAt` mirror: a **second console TTL policy, on the `claims` collection
group**, reaps the orphans. Without it every abandoned invite leaks its
claimant docs forever.

**`users/{uid}/tokens/{token}`**: read, create, delete only when the path uid
equals `uid()`; create validates the two keys and `createdAt == request.time`;
`update: if false` (a changed token is a new doc); `list` only for the owner.
No client ever reads another account's tokens — only the Worker's service
account does, and admin credentials bypass rules.

**Deploy is lockstep with the app update.** The new rules delete the old
redeemer-writes-the-stamp clause, so a stale install's redeem fails
`permission-denied`, which the existing mapping surfaces as `codeInvalid` —
fail-closed and non-destructive, but worth knowing: deploy rules and install
the new build in the same sitting.

## The handshake, end to end

1. Creator mints a code (unchanged mechanics, 30 m lifetime), shows it as
   text, QR, and a Share-able link. The sheet now also hosts the claims list.
2. Claimant types / scans / taps, the sheet prefills, Connect files the claim:
   read invite (client-side checks: not mine, not expired, creator not already
   a partner, under cap), create `claims/{myUid}` with my profile, persist
   `connections_pending_claim`, watch my claim doc and the invite.
3. Creator's claims listener surfaces each claimant as an avatar + name row
   with Approve and Dismiss. Approve runs: create pair (rules verify invite +
   claim), stamp `pairId`/`redeemedBy` on the invite, adopt, delete the
   invite (best-effort; TTL is the backstop). Remaining claimants are
   dismissed implicitly — the stamped invite refuses further approvals, and
   their claims expire under the TTL.
4. Claimant's invite watch sees the stamp. `redeemedBy == me`: read pair,
   adopt, clear the pending claim. Otherwise, or on claim deletion: neutral
   "your request was not approved" end state, clear the pending claim.
5. Every crash window is covered by the same server-truth inversion as Phase
   01: a pair created but never stamped is still found by the claimant's next
   reconcile (`members` contains my uid); a stamp never observed is resolved
   the same way; an approval the creator's device forgot is re-adopted from
   `findActivePairs`. The claim/approve layer adds UX, never a new source of
   truth.

Both flows go through the existing `_guard` discipline — `Source.server`
reads, transactions where a read-check-write races, timeouts, `offline`
mapping. The claims listener is the one new snapshot stream and follows the
rebind-on-error rule (a Firestore stream terminates on error; a deaf approval
sheet is a stranded claimant).

## The Phase 02/03 ripple

**Which collection a row syncs into.** Calendar rows (events, absences,
occurrences) sync into the *designated calendar connection*: the single pair
where both members' `permissions[uid].shareCalendar` is true. Folders and
their notes/chunks sync into the pair named by the folder's `share_pair_id`.
The load-bearing invariant, enforced in the sync services and assumed by
everything below: **a row only syncs into a pair whose `members` contains the
row's `owner_id`.** That single rule stops rows received from partner A ever
leaking to partner B — A's events merged into my SQLite have
`owner_id == A`, and A is not a member of my pair with B.

**Phase 02 migration (v29) is unchanged**: `owner_id` TEXT NULL on
`calendar_events`, `calendar_event_absences`, `calendar_event_occurrences`,
backfilled to the local uid on first sign-in. No per-row connection pointer is
needed for the calendar because the designated connection is a single, mutual,
account-level choice — stored on the pair doc (so both sides and both devices
agree), cached in `connections_calendar_pair_id`, surfaced as a per-connection
"Share calendars" toggle that is live only when both flip it. Enabling it on
connection Y while X carries it flips X off first, with a dialog.

**Switching or ending the calendar connection is a stop, not a retraction.**
Own rows re-push into the new pair's subcollection; the old pair's copies go
stale under the (live or tombstoned) doc and are never tombstoned by the
switch — a tombstone means "deleted everywhere" and would reach into the
ex-partner's local database, breaking the unpair dialog's standing promise
that their data stays. Stale remote copies under an ended pair are storage,
not truth (free tier: 1 GiB, this is nowhere near it). Received partner-owned
rows likewise stay local forever, exactly like Phase 01's ended-pair
semantics.

**`allowPartnerEdit` was already multi-ready.** It lives per-member per-pair
doc; with N connections it simply appears once per connection row instead of
once on the page. The rules clause Phase 02 adds ("write when `ownerId ==
uid()` or the owner's flag on *this* pair is true") needs no change — each
pair's subcollection consults its own doc.

**"Delete all events" is now forced to scope.** With a live calendar
connection, the wipe tombstones **own** rows (they propagate as deletes, as
they should) and leaves partner-owned rows in place, with dialog copy saying
exactly that; deleting a partner's rows wholesale would either be blocked by
rules (no consent) or, with consent, destroy their calendar from a bulk action
they cannot see coming. `importData`'s wipe stays hard and stays local-forever
per the Phase 02 doc — unchanged.

**Phase 03 migration changes shape**: `is_shared` INTEGER is replaced by
`share_pair_id` TEXT NULL on `folders` (plus `owner_id` as planned). NULL is
local-only; sharing a folder is picking a connection, not flipping a bit — the
context menu's Share becomes a connection picker when N > 1. A note cannot
belong to two connections, by construction: it has one folder, the folder has
one `share_pair_id`. The Phase 03 doc's "Migration v27" header is stale
(v27/v28 were consumed by calendar readiness and description scope); real
numbers at implementation time are v29 for Phase 02 and v30 for Phase 03 —
renumber when those docs are revised for this design.

**Restore-vs-sync gets one new clause.** The Phase 04 suspend/reconcile seam
stands. Additionally, the post-restore reconcile validates every
`share_pair_id` and the calendar designation against the live connection
list: a pointer at a pair that is not active-with-me is cleared (the folder
falls back to local; nothing is deleted). Backups **keep** `share_pair_id`
(restoring onto the same device should not force re-sharing every folder;
the validation pass makes a stale pointer harmless); the folder-export
**archive** strips it, as Phase 03 already specifies — an archive is a
cross-device artifact and must land local. Connection settings themselves stay
out of backups, as Phase 01 established.

## QR code

- **Display: `qr_flutter: ^4.1.0`** — pure Dart rendering, no permissions, no
  platform channels, compatible with Dart ^3.10.4. Rendered inside the
  pairing sheet next to the monospace code.
- **Scan: `mobile_scanner: ^7.0.0`** (verify the latest 7.x at implementation)
  — ML Kit + CameraX, minSdk 23 ≤ 24, Dart 3 compatible. Its iOS floor is
  15.5, which is exactly the deferred Mac-side work; the scanner ships
  Android-only behind the same availability plumbing as everything else.
- **Manifest**: add `<uses-permission android:name="android.permission.CAMERA"/>`
  (the plugin merges its own, but self-documenting beats implicit) and
  `<uses-feature android:name="android.hardware.camera.any"
  android:required="false"/>` so camera-less devices are not filtered from
  install. Runtime permission is requested by the scanner controller at first
  use; a denial falls back to the code field, which never goes away.
- **Payload: the full invite URL** (`https://<host>/invite/K7M2P4XQ`), not the
  bare code. The in-app scanner parses the code out of the URI (last path
  segment → `normalizeCode` — note the URL as a whole cannot be fed to
  `normalizeCode`, the hostname contains alphabet characters); the system
  camera scanning the same QR opens the app through the App Link. One payload,
  two working paths.

## Invite deep link

**App Links over a custom scheme, on Firebase Hosting's free domain.** The
comparison is short: a custom `anta://` scheme needs no infrastructure but is
not linkified by messengers, so the primary distribution channel (paste into a
chat) produces dead text; App Links are tappable everywhere, verified (no
disambiguation dialog), and fall back to a real web page for someone without
the app. The classic objection — App Links need a domain plus
`assetlinks.json` — is void here: the Firebase project already exists, and
**Spark includes Hosting with a free `<project-id>.web.app` domain** that can
serve `/.well-known/assetlinks.json` (containing the app id and the release +
debug SHA-256 signing fingerprints) and a one-page fallback ("Open in ANTA /
get ANTA"). A custom vanity domain is possible later without breaking
anything, but is a user decision, not a requirement.

- **Manifest**: a second `intent-filter` on `MainActivity` with
  `android:autoVerify="true"`, `VIEW` action, `BROWSABLE`/`DEFAULT`
  categories, `scheme="https"`, `host="<project-id>.web.app"`,
  `pathPrefix="/invite"`. `launchMode="singleTop"` is already set, which is
  what routes a link into the running activity as `onNewIntent`.
- **Receiving: `app_links: ^7.2.0`** — `getInitialLink()` for cold start,
  `uriLinkStream` for warm. Handled in `main.dart` beside the app-wide bloc
  wiring, the one place that already owns startup sequencing: parse the code,
  then `AppNavigator.rootPush` the Sharing page with a new optional
  `initialInviteCode`, which opens the pairing sheet prefilled and lets the
  normal claim flow (with all its cap/duplicate/signed-out guards and error
  attribution) take over. On cold start the link push simply lands on top of
  `restoreLastLocation()`'s stack — back returns to wherever the user was.
  Signed-out or unavailable states need no special path: the Sharing page
  already renders the sign-in row, and the prefilled code waits in the sheet.
- **Sharing**: the sheet's existing Share button shares the URL instead of the
  bare code; Copy keeps copying the bare code (the read-aloud path).

## Push notifications

**The crux first: who sends.** FCM delivery is free on Spark, but the v1 send
API authenticates with service-account OAuth, and a service account shipped in
the APK is public — extraction hands a stranger the ability to notify every
install. There is no client-only answer; the trusted environment must exist
somewhere. The smallest free one is a **Cloudflare Worker** (free tier: 100k
requests/day, no payment method) of roughly a hundred lines:

1. Verify the caller's Firebase ID token against Google's public JWKS —
   only signed-in ANTA accounts get through.
2. Read `pairs/{pairId}` via the Firestore REST API **using the caller's own
   ID token**, so the security rules — not Worker logic — prove the caller is
   a member and the target is the other member. A tombstoned pair still reads
   for its members (`members` never shrinks), which is precisely what lets
   the connection-ended notification through — the tombstone design pays off
   again.
3. Read `users/{targetUid}/tokens/*` with the service account and send an FCM
   v1 **data message** `{type, pairId, fromName}` to each token, pruning
   tokens FCM reports dead.

The client calls the Worker at the three moments: claim filed (claimant →
creator), approved (creator → claimant), connection ended (ender → partner).
Every call is best-effort and fire-and-forget: push is a poke, never a source
of truth — state always converges through reconcile-on-open/resume, so a
Worker outage degrades to exactly today's behavior. If the user declines to
run a Worker at all, everything before this stage still ships; "your partner
ended sharing" just stays a next-open discovery.

**Token lifecycle is global, deliberately off the `DatabaseLifecycle` reset
contract.** Identity is global while pairing state is per-database; a push
token identifies *this install signed into this account*, so it registers
under `users/{uid}/tokens/{token}` from a small `PushRegistrationService` that
listens to `authStateChanges` — never to database switches. On sign-out it
deletes its token doc **before** the auth session drops (afterwards rules deny
the delete); on token refresh it writes the new doc and removes the old. A
database switch changes nothing: the account still wants its notifications.

**Receiving.** `firebase_messaging` (^16.x — the release paired with the
committed `firebase_core` ^4.13 line; confirm against the FlutterFire
compatibility table at implementation) plus `flutter_local_notifications`
(^19.x) to display, because data-only messages do not auto-display and
notification-type messages cannot pass through `AppLocalizations`. The
background handler resolves strings via the generated `lookupAppLocalizations`
— a pure function safe in a background isolate — against the system locale
(the per-database in-app language override is unreachable from that isolate;
if that mismatch ever matters, mirror the override to a global
SharedPreferences key when it is set). Tapping a notification deep-links to
the Sharing page through the same path as an invite link. Foreground messages
skip the system notification entirely — the live streams already move the UI.

**Android permission**: declare
`<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` and
call `FirebaseMessaging.instance.requestPermission()` — which raises the API
33+ runtime prompt — the first time the user generates or claims an invite,
not at app start; a notification prompt with no visible cause is a denial
generator. A denial degrades to next-open discovery, silently and safely.

**Deferred on iOS**: APNs key/certificate, the push capability in the Runner
project, the 15.0 deployment-target raise — all Mac-side, all stacked on the
same outstanding work as Google Sign-In. The Worker and token schema are
platform-neutral; iOS is additive later.

## Dependency resolution (verified 2026-08-18)

`dart pub add --dry-run qr_flutter mobile_scanner firebase_messaging app_links`
resolves cleanly against the committed `firebase_core ^4.13.0` line with no
conflicts, on Dart `^3.10.4`:

| Package | Resolves to | Stage |
| --- | --- | --- |
| `qr_flutter` | 4.1.0 | D |
| `mobile_scanner` | 7.4.0 | D |
| `firebase_messaging` | 16.5.0 | E |
| `app_links` | 7.2.1 | C |

`mobile_scanner` needs `minSdk 21`; this project is already at 24.

## Staged implementation order

| Stage | Contents | Blocks on | Ships alone? |
| --- | --- | --- | --- |
| A | Multi-connection core: `ConnectionSettings` + key migration, per-member-set dedup, cap, error split, connection-list UI, renames, Phase 02/03 doc revisions | — | **Yes** — this is the safe standalone cut; everything after assumes it |
| B | Handshake: claims subcollection, rules v2 (lockstep deploy), approval sheet, waiting state, second TTL policy | A (error taxonomy, list UI) | Yes, after A |
| C | Deep link: Hosting setup (`assetlinks.json` + fallback page), manifest intent-filter, `app_links` wiring, sheet Share/URL | A; after B so only one redemption flow is ever link-tested | Yes |
| D | QR: `qr_flutter` render, `mobile_scanner` + camera manifest entries | C (the payload **is** the link format) | Yes |
| E | Push: token service + rules, Worker deploy, `firebase_messaging` + local display, `POST_NOTIFICATIONS` | B (the events worth pushing exist); Worker is a user-owned external dependency | Yes — and the app must stay fully functional with the Worker absent |

Phase 02/03 implementation work is not in these stages; stage A only rewrites
their plans (migration shapes, designated-connection model, renumbering) so
they land multi-connection-native instead of being migrated twice.

## What this costs on the Spark free tier

Rules `get()`/`exists()` bill as reads; deletes bill as writes here for
simplicity. Per operation, including rules reads:

- **Mint invite**: 1 read (transaction existence probe) + 1 write.
- **File claim**: 2 reads (client invite read + rules parent `get`) + 1 write.
- **Creator claims listener**: 1 read per claimant arriving.
- **Approve**: pair create 1 write + 2 rules reads (invite, claim `exists`);
  invite stamp 1 write + 1 rules read; pair read-back 1 read; profile confirm
  ≤1 write; invite delete 1 write. ≈ 4 reads, 4 writes.
- **Claimant adoption**: 1 invite-watch read + 1 pair read.
- **Whole handshake, both sides** ≈ 10 reads, 7 writes — pennies-scale against
  50k/20k daily, and it happens a handful of times ever.
- **Reconcile** (every Sharing-page open / sign-in): one query returning one
  doc per active pair — 3 connections ≈ 3 reads, plus 1 read per pair-watch
  initial snapshot. A heavy day of opening the page 20 times with 5
  connections ≈ 200 reads.
- **Push**: 1 write per token refresh (rare); per send, the Worker spends 1
  Firestore read (pair, as caller) + ≤3 token reads. Sends are human-scale
  events, not sync traffic.
- **TTL reaping**: 1 delete per expired invite + 1 per orphaned claim.

Nothing here moves the quota needle. The binding constraint remains what the
roadmap already flags: Phase 03's auto-save push amplification — unchanged by
this design, and slightly *helped* by it, since calendar rows push to exactly
one connection rather than fanning out.

## Risk register

- **High — rules v2 and the app must deploy in lockstep.** The old
  redeemer-writes-the-stamp clause is deleted; a stale install fails closed
  (`permission-denied` → surfaces as `codeInvalid`), non-destructive but
  confusing. One user, own devices: update both in one sitting.
- **High — orphaned claim docs.** TTL deletes the invite doc only; without the
  second console TTL policy on the `claims` collection group, claimant
  profile data (name, photo URL) accumulates forever under dead invites. This
  is a console step no code can perform — it goes next to the existing
  `invites.expiresAt` deployment note.
- **High — Worker service-account compromise = notify-anyone.** Mitigations:
  the key lives only in Worker env vars, the Worker validates
  membership-via-caller-token (so even a caller with a stolen ANTA session
  can only notify their own partners), and the account can be scoped to FCM
  send + Firestore read and rotated. Residual risk accepted; the blast radius
  is spam, never data.
- **Medium — dedup regression re-opens failure mode 2, now ×N.** The
  per-member-set grouping must keep the earliest-`createdAt` + `pairId`
  tie-break bit-for-bit deterministic across devices, or two devices tombstone
  each other's picks *per group*. The fake-gateway suite grows a matrix:
  duplicate same-set races, distinct sets, mixed, at and over the cap.
- **Medium — cap vs. query bound.** If `_maxActivePairs` ever drops back below
  cap + race headroom, reconciliation goes blind to some member sets and the
  invariant silently rots. The bound (15) and the cap (5) should be declared
  side by side with a test asserting the relationship.
- **Medium — calendar-connection switching.** Stale copies under the old pair
  are by design, but a re-designation back to a previously used connection
  must merge by HLC against those stale copies, not trust them — Phase 02's
  `receive()`-on-every-pull rule covers it; the test matrix must include the
  switch-away-and-back path.
- **Medium — the claims listener is a new place to go deaf.** Same failure as
  the pair watch: a terminated snapshot stream leaves the creator's sheet
  showing no claimants forever. Same fix: rebind on error, surface through the
  errors stream.
- **Low — deep link arrives in the wrong context** (signed out, at cap, code
  expired, different account than the sender expected). All funnel into the
  existing sheet with its typed errors and `PairingAction` attribution; the
  only new string is the neutral not-approved state.
- **Low — QR scanned on a device without the app** lands on the Hosting
  fallback page; that page existing (rather than a 404) is part of stage C's
  definition of done.

Against Phase 01's six failure modes: (1) stranded creator — the pending code
still persists, and a crash between pair-create and invite-stamp is now
recovered by the *claimant's* reconcile finding the pair by membership; (2)
double pairing — dedup generalized per member set, race tests extended; (3)
second device/database — reconcile now adopts the whole list, same inversion;
(4) blind unpair — tombstone semantics untouched, and stage E upgrades
discovery from next-open to push; (5) offline hangs — every new call (claim,
approve, token writes) goes through the same `_guard`/`Source.server`/timeout
discipline, and the claims listener follows the rebind rule; (6) stale state
outliving its account — the `accountUid` guard stays, and sign-out gains the
token-doc cleanup. No property of the shipped design is weakened; the consent
proof is strictly strengthened (two tokens instead of one).

## Decisions needed from the user

1. **Cloudflare account + Worker deploy** (stage E). Without it, push is
   dropped and everything else stands. Alternative free hosts (Deno Deploy,
   Val Town) work identically if preferred.
2. **Hosting domain**: the free `<project-id>.web.app` is assumed; a custom
   domain is optional and changes only the manifest host and the shared URL.
3. **Confirm the cap of 5** and the 30-minute invite lifetime — both are
   client constants, trivially changed, but the rules' 1-hour ceiling is a
   deploy.
4. **Confirm calendar exclusivity** — exactly one connection may carry
   calendar sync. Relaxing this later is possible (it is a per-pair flag, not
   a schema shape) but multiplies the Phase 04 matrix; it should be a
   deliberate future decision, not a default.
