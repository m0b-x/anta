# When the fleet fails — recovery, the guard, and what a pass heals by itself

Reference, not rules. Built 2026-11-11 (`docs/qa-pass-rework.md` §9, decisions H1–H12). Read the section the situation needs.

## Symptom → what to run

Run `qa doctor` first when you do not know what is wrong: its `leftovers` line names anything an earlier session left and says `qa reap`.

| You see | It means | Run |
| --- | --- | --- |
| A guest, a `flutter run` or stale files left by an earlier session; `doctor` warns `leftovers` | nobody cleaned up | `qa reap --dry-run`, then `qa reap` |
| `reap` prints `skip: anta_qa_N … held by pass pid …` | a live pass or install is using that guest | wait for it; `qa reap --force` only when you know that process is dead weight |
| A pass ends `stopped early: …` with exit 3 | the fleet failed twice, the boot failed, or the pass ran past its ceiling — not a verdict on the app | read the `recovery:` lines; `qa fleet stop anta_qa_N --force`, then run the pass again (it boots its guest) |
| `recover: anta_qa_N did not come back (…)` | the stop or the boot of a recovery failed | `qa fleet stop anta_qa_N --force`, `qa fleet boot anta_qa_N`, run again; twice in a row → stop and tell the owner (a host reboot has been the cure) |
| `fleet status` says `booting` for minutes | the qemu is up but never reached adb | nothing for three minutes — the guard force-stops it; sooner: `qa fleet stop anta_qa_N --force` |
| A flow reads `ok*` … `recovered` | the guest died under it and the rerun was green | nothing; report it as recovered, with the `recovery:` line |
| The same flow shows `flaky` in `qa pass --history <suite>` | red and green in the last twenty passes | read its reds' evidence before blaming the app or the flow |
| `guard: not running` while a guest is up | the guard was turned off or died | `qa fleet boot <name>` on the guest that is up starts one |
| A pass was killed (the agent was capped, the session closed) | its guest is still up with the app in whatever state | nothing is required: the guard stops the guest after thirty idle minutes; `qa reap` does it now |

`reap` never acts on `Pixel_9_Pro`, `ANTA_Personal` or any AVD that is not `anta_qa_*`, and ends no process except the harness's own run, a fleet qemu through the guarded stop, and an emulator crash handler whose parent is gone.

## `qa reap [--dry-run] [--force] [--prune]`

Idempotent and safe at any time. In order: the recorded `flutter run` (killed only while its pid is still the harness's own run), every fleet guest that is up or coming up (graceful stop; the guarded force for one that is off adb; a guest with a live hold is skipped without `--force`), orphaned emulator crash handlers, files whose process is gone (pid files, DTD and VM URI files of serials that are not attached, a stale `rebuild.lock`, guest state files of guests that are not running, a stale `guard.pid`, old guard copies). `--prune` also deletes pass directories past the newest twenty per suite — what `--history` reads. One line per action (`stopped: …`, `skip: …`, `removed <file> (<why>)`, `pruned pass/<dir>`); the last line is `reap: clean`, `reap: left — …` or `reap: dry run — N line(s) above; nothing was changed`. Exit 0, or 3 when a stop that was tried failed. Off Windows it stops the run and clears the stale files.

To stop only the guest you used — the right ending for one agent's pass while other sessions may be on other guests — `qa fleet stop anta_qa_N --force`: graceful while adb answers, the guarded kill when it does not.

## What a pass does by itself

- **Boots its guest.** `qa pass <suite> -d emulator-5556` on a guest that is not up: `pass: anta_qa_1 (emulator-5556) is not up — booting it first`; the report gains `booted {ms}`. Fleet serials on Windows only. It does not install: a stale-build warning still means `qa fleet install --build`.
- **Holds its guest.** `fleet status` shows `held by pass pid N since HH:MM`; neither the guard nor a plain `reap` touches a held guest.
- **Ceilings.** A flow (reseed, prelude and steps together) past 360 s fails as a device failure — `flow_ceiling=<seconds>` in `_suite.txt` or `--flow-ceiling <s>` change it, on every device. A pass past `--max-minutes` (default 45; 0 for none) finishes the flow in flight and skips the rest.
- **Recovers once.** After a device failure — a step that exited 3, a reseed that did not go in, a ceiling — it probes the guest. An unhealthy guest, or any ceiling, on a fleet guest: the first attempt's evidence is kept (`fail_<flow>_attempt1*`), the guest is stopped and booted (≈ 20 s), and the flow runs again on a fresh seed. Once per flow, twice per pass. A `reseed=suite` suite restarts from its first flow, once; a `--no-reseed` pass recovers the guest and stops. A device failure on a guest that probes healthy stands as the app's.
- **Says so.** `=== <flow>: device failure (<cause>, guest <trouble>)`, `recover: …`, `=== <flow>: ok in N ms (recovered)`; in the summary the row starts `ok* ` and the closing line reads `pass: N/M green, K recovered in …` (unchanged when K is 0), followed by one `recovery: <flow> — <cause> (guest <g>): rerun after a X s stop and boot → green|red` per recovery and `stopped early: <reason>` when it gave up.
- **Report keys, all additive and absent when empty:** `infra[] {flow, cause: ceiling|device|reseed, guest, message, action: rerun|restart suite|stop, ms, outcome, evidence}`, `infraStop`, `flows[].recovered`, `booted {ms}`, `interrupted`.
- **Exit codes.** 0 all green (a recovered flow is green); 2 any red; 3 the pass could not finish — a partial report, or any `infraStop`; 130 after Ctrl+C, which writes the report (`partial`, `interrupted`), leaves the device quiet within fifteen seconds and releases the hold.

`qa pass --history <suite> [--last N]` reads the newest twenty reports of the suite (shard reports counted, merged ones not) and prints per flow the runs, reds, recoveries, the last red and a `flaky` mark.

## The guard

`fleet boot` starts one detached, windowless `qa fleet guard` when none runs (`guard: started (pid N, idle limit 30 min, poll 60 s)`); `fleet status` ends with `guard: running (pid N, idle limit 30 min)` or `guard: not running`. Every poll it:

- stops a guest that is up with no live hold, is not the device of a live `qa run`, is not marked keep, and has been idle for the limit — idle is the time since any `qa` verb last named its serial;
- force-stops, through the guarded stop, a qemu that is off adb and has burned no CPU for three minutes;
- leaves alone any guest whose hold has beaten in the last three hours (a pass beats at every flow) — the pass holding it owns its recovery.

It exits by itself once no guest is up for two polls, logs one line per decision to `guard.log` in the fleet state directory (below), and runs from its own copy of the tool (`guard_<stamp>.exe`, same directory) so the wrapper's self-rebuild is never blocked; after a rebuild it hands over to a guard on the new build within one poll.

- `qa fleet boot <name> --keep-up` — a guest you will drive by hand for longer than the limit; the guard never idle-stops it (a hung one still goes). `reap` still stops it.
- `ANTA_QA_IDLE_MINUTES` (default 30; 0 turns the idle stop off), `ANTA_QA_GUARD_POLL_SECONDS` (default 60), `ANTA_QA_GUARD=0` (no guard is started — then `qa reap` when you are done).

## State files

The fleet is the host's, so its state is host-wide: `%LOCALAPPDATA%\anta-qa\fleet` (`ANTA_QA_FLEET_STATE` overrides) holds `guest_<avd>.json` (`bootedAt`, `lastUsedAt`, `keep`, `hold {pid, verb, since, beatAt, checkout}`), `guard.pid`, `guard.log` and the guard's `guard_<stamp>.exe`. Every checkout and worktree reads the same files, so a pass in one is seen by a `reap` or a guard started from another, and `fleet status` says which checkout holds a guest. What belongs to one checkout stays under its `build/qa/`: `run.pid`, `emulator_<avd>.pid`, the per-device DTD, VM and install files, the pass directories.

**A check that could not answer protects.** A holder whose process cannot be checked still holds; a state file that exists and does not parse protects its guest; a pid file whose owner cannot be checked is kept. So `reap` can end `reap: left — …` where a probe failed: run it again, and `--force` only when you know the holder is gone. `reap` removes the files whose owner is gone; nothing is deleted by hand.

## Not shown live yet

Unit-tested only: the guard's force-stop of a hung guest, the `reseed=suite` restart, a boot that fails during a recovery, the pass ceiling, a recovery inside a `fleet pass` shard (two shards recovering at once would boot side by side — the known trigger for the boot hang).
