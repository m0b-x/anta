# Sync pass

Reference, not rules. Read only the part the task needs.

## The sync pass (2026-11-10)

One command is a device pass of the Sync section of a database that really
syncs, against the local Firebase emulator suite — no real account, no real
project:

```bash
tool\firebase\emulators.cmd                                   # a host shell of its own, left running: Auth 9099, Firestore 8080, UI 4000, project alexs-note-tracking-app, everything in memory
./tool/qa/qa build --define ANTA_QA_CLOUD=true --define ANTA_QA_FIREBASE_EMULATOR=10.0.2.2 --define ANTA_QA_ACCOUNT=qa1:qa1@example.com
./tool/qa/qa -d emulator-5556 install --grant                 # or `qa fleet install`: every booted guest
./tool/qa/qa pass sync -d emulator-5556                       # 5 flows on one seed and one sign-in: ≈ 38 s
```

Stop the emulator suite afterwards (Ctrl+C in its shell). The guest keeps
the cloud-define build until the next `qa fleet install --build`, which a
normal pass needs anyway: the other suites expect a build with cloud off
(`settings/09_hub_sharing` reads `sharing-unavailable`).

`tool/qa/flows/sync/_suite.txt` names `basic.json`, `reseed=suite`,
`shard=no` and `_prelude.txt`: one seed, then the prelude, then the five
flows in order, each starting where the last one left the page — so a red
flow reddens the rest, and the suite never shards. The prelude opens Sync &
sharing from the drawer through the hub, expects the signed-out account row
(`sharing-sign-in`) over the unbound row's signed-out line ("Sign in to sync
this database", which tells `SyncSignedOut` from the `SyncInitial` that
carries the same id for a moment), signs in (`sharing-sign-out` within
30 s) and expects the unbound `sharing-sync`. A cloud-off build fails there
at once: its account row is `sharing-unavailable`.

| Flow | Proves |
| --- | --- |
| `00_bind` | "Sync this database" on an account with no space binds in one tap, no picker; the status row reads "Up to date" (after "25 changes waiting / Not synced yet"); Sync now, the switch, Stop and Delete are there |
| `01_manual_cadence` | the switch off: the status row reads "Syncs when you tap “Sync now”", the switch "Only when you tap “Sync now”"; a folder made on the root ("QA sync folder", `create-folder` → type → `sheet-confirm`) waits: back on the page the status row reads "1 change waiting" with no run started; Sync now sends it and the row comes back to the manual line with nothing waiting; the switch on: "Up to date" and "Changes sync while the app is open" |
| `02_stop_and_merge` | Stop through `sharing-sync-stop-confirm` unbinds and keeps the space; the next bind opens the picker with merge, download and upload; Merge asks (`sync-picker-merge-confirm`) and the rebind reads "Up to date" |
| `03_delete_cloud_copy` | Delete through `sharing-sync-delete-confirm`: the Sync section unbound at once; the deletion row (`sharing-sync-finish-delete`) in its own section, "Cloud copy deletion", last on the page after Pairing; it ends as "Cloud copy deleted" (never "Finish deleting") and stays, no status row left; back to the hub and in again, no deletion row at all |
| `04_bind_again_and_delete` | after a deletion the account holds no space: the bind needs no picker and reads "Up to date"; a second deletion as the first, down to the page opened again without the row; the emulator ends with no space, where the next pass starts |

Every flow ends with `errors`. Green twice on 2026-11-10 on `anta_qa_1`,
each against a freshly started emulator suite: 5/5 in 38.3 s and 5/5 in
36.0 s. The first bind's "Up to date" took 4.5–4.6 s of waiting; from the
delete confirm's tap to the deletion row 262–294 ms, the unbound section
confirmed on the next check (≈ 0.2 s), the row gone ≈ 0.5 s later. After
the 2026-11-11 page change (the deletion's own section, the ended row kept,
the waiting count under the manual cadence) green twice again, each against
a freshly started suite: 5/5 in 45.3 s and 5/5 in 43.8 s. At the confirm's
`--wait` the row already read "Deleting cloud copy / 5 items removed" (8 in
one run); the screenshot after the end read "Cloud copy deleted / 26 items
removed", muted under a check.

**The deletion row's life.** During the delete step itself (a second or
so) the deletion section is absent; then it reads "Deleting cloud copy"
over "Starting…" and "N items removed", and when the run ends it stays,
muted, as "Cloud copy deleted" (with "N items removed" when N > 0) until
the page is left. The page opened again has no deletion section. A flow
never waits on the running words — on a database this small the run can be
over before the first check — only on the row's id and then on "Cloud copy
deleted". "Finish deleting" over "Partly deleted from your account: “…”"
(a deletion waiting to be finished) and "Update ANTA to finish" (held for
an update) do not occur on one healthy guest.

**How a flow tells "up to date".** The status row (`sharing-sync-status`)
says "Up to date" only when the engine is idle, nothing waits in the outbox
and a pull is behind it (`_statusLine` in `sync_settings_page.dart`); before
that it reads "N changes waiting", "Receiving changes" or "Waiting for the
first sync". The flows wait with `expect id:sharing-sync-status "Up to date"
--timeout 60` — the label pass matches the row's merged "Up to date\nLast
synced …" by substring; the templates its slot sizes itself from are
excluded from semantics, so the text is in the tree only while the row says
it. Under the manual cadence the same idle state reads "Syncs when you tap
“Sync now”", which is also what says Sync now is enabled; with a local
change in the outbox it reads the count instead ("1 change waiting") and
no run starts until Sync now (since 2026-11-11). Never wait for the
row alone: it appears with the bind, long before the first sync ends.

**The seam: a reseed signs out.** A Firebase session lives in the platform's
own store, outside the QA database and preferences a reset clears, so it
survived `relaunch --fresh` and a reinstall, and against a restarted Auth
emulator the page opened on a bare uid that behaved offline.
`QaBootstrap.applyResetSignOut` (`lib/core/qa/qa_bootstrap.dart`, from
`afterDependencies()`) signs out through `AuthService` when the launch
applied the reset marker on a build with `QaMode.useFirebaseEmulator` — on no
other build. Its `[qa]` line is `signed out of the emulator account` (or
`sign-out threw …`, which the prelude's first expectation then reports).
The pass's closing quiet relaunch signs out as well.

**What it does not cover.** A second device (two guests bound to one space,
a change crossing, the picker's download and join — the multi-user
roadmap's slice R10; the 2026-11-07 two-device pass was driven by hand,
`docs/cloud-sync-phase-02-own-space.md` S6); an interrupted deletion (the
app killed mid-run, "Finish deleting" on the next launch) — on a seed this
small the background run ends within a second of the confirm, too soon to
kill the app inside it; a table of more than twenty rows (the chunked wire's
paging); offline and quota states; a second account (the mismatch pause).

**Traps met.**
- Until 2026-11-11 the deletion row first read "Finish deleting / Partly
  deleted from your account: “qa”" for the moment between the unbind and
  the background run's start; the app no longer does, and the flows check
  "Finish deleting" is absent once the row reads "Cloud copy deleted". The
  confirm's tap carries `--wait id:sharing-sync-finish-delete`, so the
  checks after it are never vacuous — the whole run is over in about a
  second. The row sits on screen on a 1280 × 2856 guest (y 1728–1914), so
  the reopened page's `--absent` is not a row beyond the list's cache
  extent.
- "Up to date" can flicker: after a merge the engine reads "Up to date",
  then "Receiving changes" once more, then "Up to date". The next flow opens
  with its own "Up to date" expectation rather than trusting the last one.
- `errors` hides the `MissingPluginException` for `cancel` on a
  `firebase_firestore/transaction/<id>` channel ("while de-activating
  platform stream") that the plugin logs after every transaction — dozens
  per pass, one per deleted document during a deletion. It is a known-noise
  pattern in `tool/qa/src/log_parse.dart`, counted in each source's
  "N known-noise line(s) hidden (--all to show)" with the other known lines;
  `errors --all` lists them, marked `(known noise)`. Any other
  `MissingPluginException` is still shown.
- Still shown in every flow's `errors`: one `W/… java.io.IOException:
  Unable to create parent directories of /data/user/0/com.google.android.gms/
  files/phenotype/…` from Play services' provider installer, logged once
  per launch of the cloud build (the suite's one reseed) — Play services',
  not the app's; it is not in the known-noise list.
- A pass that recycles the guest right after `qa install` can lose the
  install (seen 2026-11-11: the settings pass recycled `anta_qa_1` at
  8290 MB of GPU memory a minute after the install, and `doctor` then read
  `pm path is empty`): every reseed fails with "is not installed" and the
  pass stops after two. Install again on the recycled guest and rerun; or
  recycle before installing when `fleet status` shows a worn guest.
- The account row prints the emulator's uid; the account is fake
  (`qa1@example.com`), so a dump or a shot of it is safe here, unlike on a
  build signed in to the real project.
- PowerShell mangles a `steps` line with an embedded `"label"`; drive
  label steps from Git Bash or a step file.
