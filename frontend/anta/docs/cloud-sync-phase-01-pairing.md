# Cloud Sync Phase 01 — Pairing

**Status: planned.** No schema change. Depends on Phase 00 (shipped). See
`cloud-sync-roadmap.md` for the architecture stance.

## Goal

Two signed-in accounts link into one pair. Nothing syncs yet — this phase
ends when both devices show each other as paired, and unpairing cleanly
drops the link.

## Design

- **Invite flow.** One side generates a short-lived, single-use code written
  to `invites/{code}` (`creatorUid`, `expiresAt`). The other side redeems it,
  creating `pairs/{pairId}` with both uids in `members` and default
  `permissions` (`allowPartnerEdit: false` for both). Delete the invite on
  redemption.
- **`PairingService`** (`lib/services/pairing_service.dart`, new) owns the
  workflow behind an interface that hides Firestore, mirroring how
  `AuthService` hides `firebase_auth`. A fake makes the pair/unpair state
  machine testable.
- **`pairId` storage.** Through `SettingsService` + a new `SettingsKeys`
  entry — never raw keys. Because settings live in the per-database
  `user_settings` table, pairing is automatically per-database: switching
  local databases cannot leak one pair's data into another. This is also the
  point where pairing state joins the `DatabaseLifecycle` reset contract
  (identity itself stays global and off the contract).
- **Security rules, first cut.** Everything downstream keys off
  `pairs/{pairId}.members`: read/write only for members; invites readable
  only for redemption; expired invites unreadable. Rules ship in this phase
  so Phase 02 only extends them with the consent clause.
- **Unpair semantics.** Local rows stay untouched; the remote link drops
  (remove uid from `members`; if empty, delete the pair doc). Define
  re-pairing behaviour: a fresh `pairId`, no resurrection of the old one.

## UI

The Sharing page (`lib/pages/sync_settings_page.dart`) grows a Pairing
section under Account: generate code / enter code when unpaired; partner
identity + Unpair when paired. All strings en/de/ro together.

## Done when

Two devices show each other as paired after one invite round-trip; unpair
removes the link on both; database switching shows each database's own
pairing state; still nothing syncs.

## Verify

`dart analyze lib`; `flutter gen-l10n` (untranslated counts unchanged);
`flutter test` (new `PairingService` suite against the fake gateway);
two-device manual round-trip.
