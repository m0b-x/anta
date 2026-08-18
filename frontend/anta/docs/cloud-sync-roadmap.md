# Cloud Sync Roadmap

**Status: Phase 00 shipped 2026-08-16, Phase 01 shipped 2026-08-17. Phases
02–04 planned.** Master document
for the cloud migration; per-phase implementation docs live alongside this
file (`cloud-sync-phase-01-pairing.md` … `cloud-sync-phase-04-hardening.md`).

## What this is

A shared calendar and shared note folders for two people, built on the CRDT
metadata (`hlcTimestamp`, `deviceId`, `version`, `isDeleted`, `deletedAt`)
that folders, notes, and content chunks already carry. Firebase (Spark plan)
is the backend; Google Sign-In is the identity.

## Architecture stance — the rules every phase obeys

- **Local SQLite stays the source of truth.** Firestore is a transport with a
  durable offline queue, never the primary store. Any design that inverts
  this is wrong.
- **One platform gate.** `SyncAvailability.isSupported`
  (`lib/services/sync_availability.dart`) = `!kIsWeb && (Android || iOS)`.
  Desktop stays local-only because `google_sign_in` ships no desktop
  implementation — regardless of what the Firebase plugins support. Nothing
  outside `main.dart` and DI consults the gate directly.
- **The bound service is the availability truth.** `AuthService.isAvailable`
  (false on `NoOpAuthService`) is what blocs/UI consult — it also covers the
  "gate passed but Firebase init failed" degradation, which the static gate
  cannot see.
- **Firebase types stop at the service layer.** `AppUser`
  (`lib/models/app_user.dart`) is the boundary; blocs and pages never see
  `firebase_auth`'s `User`. Phase 02 extends the same principle with a
  `SyncGateway` interface so Firestore never leaks into services.
- **User-data dates cross the wire as epoch-ms integers**, exactly like the
  backup format. `CalendarEventService._dateOnlyUtc` exists because Drift
  returns local `DateTime`s that shift days in non-UTC zones; Firestore
  `Timestamp`s would reintroduce that bug across the network.
  **Control-plane instants are the carve-out**: `createdAt` / `expiresAt` /
  `endedAt` on `pairs` and `invites` are Firestore `Timestamp`s, because
  security rules compare them against `request.time` and an int cannot be
  checked that way without trusting the client's clock — the exact thing those
  rules exist to prevent. The day-shift bug does not apply to instants.
- **Reuse `exportData()` maps as the Firestore document shape.** The backup
  serializers are a proven, JSON-safe wire format — do not design a second
  one.

## Phase ladder

| Phase | Scope | Schema | Status |
| --- | --- | --- | --- |
| 00 | Firebase foundations, platform gate, Google Sign-In, Sharing page | none | **Shipped 2026-08-16** |
| 01 | Pairing two accounts (`invites/{code}` → `pairs/{pairId}`) | none | **Shipped 2026-08-17** |
| 02 | Calendar sync + ownership + consent | v26 | Planned |
| 03 | Shared folders (folder → note → chunks) | v27 | Planned |
| 04 | Hardening (restore-vs-sync, DB switching, status UI, tests) | none | Planned |

## Phase 00 — what actually shipped (deviations from the original plan)

- `SyncAvailability`, `AuthService` interface + `FirebaseAuthService` /
  `NoOpAuthService`, `SyncBloc` (`lib/bloc/sync/`), `SyncSettingsPage`,
  drawer entry + header identity row, l10n keys en/de/ro,
  `test/bloc/sync_bloc_test.dart` against a fake `AuthService`.
- **No `serverClientId` in Dart.** Android resolves the web OAuth client from
  `google-services.json` (`client_type: 3`) via the Gradle plugin; iOS reads
  `Info.plist`. Nothing OAuth-shaped is committed to the repo.
- **No `attemptLightweightAuthentication()` on startup.** Firebase persists
  its own session; a returning user is already signed in when
  `authStateChanges` first emits. Google re-auth is not needed for identity.
- **`AuthService` is deliberately NOT on the `DatabaseLifecycle` reset
  contract.** Identity is global. Pairing state (Phase 01) lives in
  `user_settings` via `SettingsService`, which makes it per-database
  automatically — that is where the reset contract becomes relevant.
- `FirebaseAuth.instance` is resolved lazily and DI checks
  `Firebase.apps.isNotEmpty` before binding the real service; a checkout
  without `google-services.json` launches offline with the no-op binding.
- Firebase config files (`google-services.json`, `GoogleService-Info.plist`,
  `lib/firebase_options.dart`, `firebase.json`) are gitignored; regenerate
  with `flutterfire configure --platforms=android,ios`.

## Remote shape (target)

```
pairs/{pairId}                        // random id; never deleted, never reused
  members: [uidA, uidB]               // never shrinks
  status: 'active' | 'ended'
  createdAt, endedBy, endedAt
  profiles: { uidA: { displayName, photoUrl }, uidB: { … } }
  permissions: { uidA: { allowPartnerEdit: bool }, uidB: { … } }

pairs/{pairId}/events/{eventId}      // mirrors exportData() + sync columns
pairs/{pairId}/folders/{folderId}
pairs/{pairId}/notes/{noteId}
pairs/{pairId}/notes/{noteId}/chunks/{index}   // keyed by index, never local id

invites/{code}                        // short-lived, single-use, create-only
  creatorUid, createdAt, expiresAt
  pairId, redeemedBy                  // written by the redeemer, read by the creator
```

**Unpairing tombstones the pair, never deletes it** (`status: 'ended'`,
`members` unchanged): both sides keep read access so the passive partner
learns who ended it and when, and the doc survives to anchor the
subcollections above — Firestore has no recursive delete without Cloud
Functions, which Spark does not include.

**The locally stored `pairId` is a cache, not the truth.** The server answers
"which active pair contains my uid", reconciled on sign-in and resume. That
inversion is what stops a second device, a second local database, or a
both-sides-redeem race from silently forking into two pairs. When a uid does
end up in two active pairs, the earliest `createdAt` wins and the rest are
tombstoned — both devices reach that answer independently.

Consent rule sketch: read for any member of the pair; write when
`ownerId == uid()` or the owner's `allowPartnerEdit` is true. A standing
toggle, not per-edit approval — approve-each-change needs pending-state UI
and push notifications this app doesn't have, to serve two people who can
talk to each other. Authorship stays visible via owner colours and an
"editing X's event" banner instead.

## Risk register

- **High — auto-save amplification.** `AutoSaveService` is tuned for cheap
  local writes; naive push-per-save burns the 20k writes/day Spark quota and
  battery. The Phase 03 debounce is a design requirement, not an
  optimisation.
- **High — two persistence layers can disagree.** SQLite drives the UI;
  Firestore holds its own offline queue; they reconcile only on pull. Any
  write path that skips the push (migration, restore, direct DAO call)
  diverges silently until the other device contradicts it.
- **Medium — `position` has no natural merge.** Last-writer-wins on manual
  ordering means an occasional surprise reorder when both people rearrange
  the same shared folder. Accepted.
- **Deferred — per-occurrence descriptions.** `calendar_event_occurrences`
  (v24 sparse delta table) stays device-local in v1; only the template
  description syncs.

## Standing constraints

- iOS needs deployment target 15.0 (currently 13.0) plus `GIDClientID` and
  the `REVERSED_CLIENT_ID` URL scheme in `Info.plist` — Mac-side work.
- Every phase drags in l10n (en/de/ro together) and, where columns are
  added, `BackupService` compatibility per the absent-keys-take-defaults
  precedent.
- Tests are welcome (standing user permission, 2026-08-16): new sync
  services/blocs get suites against fakes, extending
  `test/bloc/sync_bloc_test.dart`'s pattern; schema phases extend
  `test/database/`.
