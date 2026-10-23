# Harness notes

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

The descriptive paragraphs of SKILL.md's opening, "Which device" and "Two driving layers" sections; the rule lines of those sections stay in SKILL.md, and the three headings below are new.

## The wrapper and the exit codes

The wrapper compiles `build/qa/qa` (`qa.exe` on Windows) the first time it is
used (~3 s on an M-series Mac, ~30 s on the Windows PC) and runs the binary
after that: a verb costs about 30 ms of startup instead of ~2 s of JIT. When a
file under `tool/qa/` changes, the next verb rebuilds itself first
(`qa: sources changed since qa.exe was built — rebuilding…`) and then serves
the verb. `qa build-exe` forces it; `QA_NO_SELF_REBUILD=1` turns it off;
`dart run tool/qa/qa.dart <verb>` still works everywhere and never
self-rebuilds.

Exit codes: `0` ok, `1` usage, `2` target not found or ambiguous, `3` device,
agent or toolchain failure. Every verb takes `--help`.

## `qa devices` and the one `flutter run` slot

`qa devices` lists everything drivable; `--all` adds shut-down simulators. It
exits 3 when nothing is attached *and* a toolchain problem was seen (adb not
answering, `xcrun` missing), so a setup check can rely on it. A `-d` hint also
decides which tools are asked at all: a UDID or `ios` never runs `adb devices`
(a cold adb daemon can take seconds), a serial never runs `simctl list`, and
`boot` honours the same hint (`qa -d android boot` starts the AVD).
Real output, 2026-09-16:

```
ios      B57A8680-5A8F-4010-96BE-7524481996B1    Booted     iPhone 17 Pro Max (iOS 26.2)
macos    macos                                   desktop    pass -d macos  (built: …/build/macos/Build/Products/Debug/ANTA.app)
android  emulator-5554                           device     model:sdk_gphone64_arm64
```

Every recorded connection (`vm_<device>.txt`, `dtd_<device>.txt`) is per
device, so a simulator and the desktop app can be driven in the same session
by switching `-d`. The detached `flutter run` (`run.pid`, `run.log`) is the
one single slot: a `qa run` on a second device ends the first run's tool
process (the first app keeps running — `qa relaunch -d <first>` gets its agent
back in two seconds). Since 2026-10-23 the dump cache
(`last_dump_<device>.txt`), the resolved seed (`seed_resolved_<device>.json`),
the emulator files (`emulator_<avd>.{log,err,pid}`, `emulator_cmd_<avd>.bat`)
and the installed-build record (`installed_<device>.json`) are per device
too, so two `qa` processes driving two devices never read each other's
files; `apk.json` (the last `qa build`) and `latest_<suite>.txt` (the newest
pass report) are deliberately shared.

## The pass and its report (2026-10-23)

`qa pass <suite>` reads `tool/qa/flows/<suite>/_suite.txt` (`fixture=`,
`reseed=flow|suite|none`, `shard=yes|no`, `prelude=`), sorts the `NN_*.txt`
flows by name (files starting with `_` are not flows), applies `--only`
and `--shard i/n` (flow k goes to shard `k mod n + 1`; refused when the
manifest says `shard=no`), and for each flow: `relaunch --fresh --seed
<fixture>` (per flow, or once per suite under `reseed=suite`), the prelude's
steps, the flow's steps — all in one process, sharing the agent connection.
A red flow stops at its failing step, gets `fail_<flow>.png`,
`fail_<flow>_dump.txt` and `fail_<flow>_errors.txt` (the app's error buffer
cleared and logcat stamped at the flow's start, so earlier flows' errors never
leak in), and the pass goes on. Two reseed failures in a row, a failed
`reseed=suite` seed or `--stop-on-fail` mark the rest `skipped`. After the
last flow the pass **leaves the device quiet**: a `relaunch --fresh` with no
seed, so the app's launch reconcile cancels every alarm the seeds armed (ten
per calendar seed; a seeded guest otherwise rings between passes), then a
count of the app's rows in `dumpsys alarm`'s *pending* list, retried for up
to 10 s — `device left quiet (0 alarms armed) in 4.7 s`. A plain `grep -c
com.alexzamfir.anta` on that dump never reaches zero: cancelled alarms stay
in its "Removal history". `--keep-state` skips the quiet step (to look at a
red flow's screen by hand); `quietMs`, `quietAlarms` and `quietFailure` are
in the report, and a failed quiet relaunch never changes the exit code.

The run lives in `build/qa/pass/<suite>_<yyyyMMdd_HHmmss_SSS>_<device>/`:
`report.json` (rewritten after every flow with `"partial": true` until the
end), `pass.log` (everything printed), the evidence files, and the shots the
flows took. `build/qa/pass/latest_<suite>.txt` holds the newest report's
path. Report keys: `schema`, `suite`, `label`, `device{id,label,platform}`,
`host`, `started`, `finished`, `durationMs`, `partial`, `shard{index,count}`,
`reseed`, `fixture`, `prelude`, `build{apk,gitHash,dirty,builtAt,defines,installedAt}`,
`summary{flows,passed,failed,skipped}`, `flows[]{name,status,durationMs,
reseedMs,preludeMs,steps[]{n,line,verb,ms,status,output},failure{step,line,
exitCode,message,shot,dump,errors}}` (`failure.step` 0 = the reseed or the
prelude failed; stderr lines in `output` start with `! `), `verbStats{<verb>
{count,p50Ms,p95Ms,maxMs}}` (nearest-rank; each reseed counts as `relaunch`,
prelude steps are left out). Exit 0 all green, 2 any red, 3 when the device
or the reseed failed before anything ran. `qa pass --summary R` reprints a
report; `qa pass --merge A B…` writes `<suite>_<stamp>_merged.json` under
`build/qa/pass/`, warns when the shards do not cover the suite or repeat a
flow, and repoints `latest_<suite>.txt`.

Measured 2026-10-23 on one pinned fleet device: 26 calendar flows in 604 s
(reseeds 182 s at 5.3–8 s each, the prelude 108 s, the flows' own steps
313 s); sharded over three fleet devices, 268–270 s wall. The real output of
a sharded pass's tail:

```
FAIL  22_palette                    14329 ms  step 9: tap "of your own" — no node matches "of your own". on screen (com.alexzamfir.anta): "Back" | "Appearance" | …
ok    23_overview_list              54276 ms
pass: 25/26 green in 269.9 s on emulator-5556, emulator-5558, emulator-5560 — report D:\…\build\qa\pass\calendar_20261023_180606_626_fleet\report.json
verb       count    p50    p95    max  (ms)
relaunch      26   7650  12698  12746
tap          338    536    661   1053
per device:
  emulator-5556  anta_qa_1  shard 1/3  9 flow(s)  270.0 s  exit 0
```

## The fleet (2026-10-23)

`qa fleet` owns the headless AVDs `anta_qa_N` (N = 1..64; console port
5554 + 2N, so serial `emulator-5556` for `anta_qa_1`), created from the
`pixel_9_pro` profile and the image the owner's `Pixel_9_Pro/config.ini`
names (the same 1280 × 2856 @ 480 screen, so every coordinate in a flow holds)
with `hw.ramSize=2048`, `hw.cpu.ncore=4`, a 6 GB data partition, host GPU and
cold boots. `fleet create [--count N] [--force] [--retune]` makes the missing
ones (the capacity rule `max(1, (threads − 8 for flutter test − the owner's 4
vCPU) ÷ 4)` is 3 on the 24-thread machine and is the cap unless `--force`;
drift from the spec is listed and rewritten only with `--retune`).
`fleet boot <name|N>… | --all [--no-affinity] [--visible]` starts them
detached with `-no-audio -no-boot-anim -no-snapshot -no-metrics -gpu host`
**and a window, which it minimizes** once it appears (`--visible` leaves it
up): a qemu started with `-no-window` keeps one host thread spinning at
100 % while the guest idles (1.2 cores right after boot, two spinners and
2.2 cores after hours of passes — the same for host GPU, swiftshader, audio
on or the snapshot on; measured 2026-10-23), while a windowed one idles at
0.2 cores and a minimized one at 0.14, still relaunching the app in 4 s and
rendering for the agent. It pins the qemu child to the P-cores the moment it
appears (Windows, hybrid CPUs only: `2 × (threads − cores)` logical CPUs;
`ANTA_QA_FLEET_AFFINITY` overrides), waits for `sys.boot_completed` and
`device_provisioned`, then keeps the guest awake (`screen_off_timeout`,
`svc power stayon`). Measured: 13–18 s per boot once an AVD has booted
before, 36 s the first time, 80–113 s when two first boots ran unpinned in
parallel. `fleet status [--json]` lists
name, serial, state (`not created`, `stopped`, `booting`, `device`, `offline`,
`port held by X`), the installed build (`installed <hash> <time>`, `stale`,
`not installed`), the qemu pid and its affinity, and the owner's AVDs marked
`owner — never acted on`. `fleet stop <name>… | --all` sends `emu kill` only
after `adb emu avd name` returns that fleet name — `Pixel_9_Pro` and
`emulator-5554` are refused at argument parsing. `fleet install [--build]`
runs `qa build` when asked or when `apk.json` is missing, installs on every
booted fleet device in parallel and grants `POST_NOTIFICATIONS` on each
guest (`pm grant`; the one permission the owner's emulator had by hand and a
fresh guest lacks — without it the alerts suites never ring; `install
--grant` does the same for one device, refused on a non-fleet serial); `fleet pass <suite> [--devices a,b] [--label]
[--stop-on-fail]` spawns one `qa -d <serial> pass <suite> --shard i/n` child
per ready device with a current install (a stale one is used with a warning,
one without an install is left out), streams each child's `=== flow` lines
prefixed by serial into `build/qa/pass/<suite>_<stamp>_fleet/shard-i.log`,
merges the shard reports into `report.json` there and prints the summary
and the per-device wall times; exit 3 when a shard produced no report.
Host load during a three-device pass: 32–52 % CPU, ≈ 4 GB per qemu.
Fleet health (slice 5): the harness counts app launches per fleet serial
since boot (`launches_<serial>.json`; `fleet status` shows `launches=N` and,
on Windows, the qemu's GPU counter), and `fleet pass` / `fleet install`
recycle a guest over 40 launches or 16 GB before starting (≈ 20 s; the
emulator's host-GPU allocation grows ≈ 400 MB per launch and never comes
back — `traps.md`); `fleet stop <name> --force` is for a hung fleet qemu
that is no longer on adb. A launch also removes the device's previous `adb
forward` (one per relaunch otherwise piles up for the adb server's life).

## The `auto` driver choice (2026-10-23)

`--via auto` (the default) is decided once per process: on Android, the
in-app agent when `vm_<device>.txt` holds a URI from a launch or relaunch and
the agent answers an `info` within 2 s; adb otherwise, with one `note: driver
auto → adb (…)` line on stderr. `relaunch` and `pass` switch to the agent
without probing. `state` prints `driver=agent (auto)` or `adb (auto)`; a
`--via` written on one step of `steps` or `pass` holds for that step only.
`ANTA_QA_VIA` still overrides.

## The two driving layers side by side

| | in-app **agent** (VM service) | **adb** + uiautomator |
| --- | --- | --- |
| Platforms | iOS simulator, macOS, Android (`--via agent`, proved 2026-09-17: a six-step flow in 0.53 s against 10.5 s for three adb steps) | Android only — the default there |
| Needs | the driver build (`test_driver/main_driver.dart`, which `qa run` and `qa relaunch` use) | any build, debug or release |
| Sees | Flutter's own semantics tree: label, value, hint, tooltip, `Semantics.identifier`, flags | the Android accessibility tree, pixels |
| Acts by | synthesised pointer events, `TestTextInput`, key simulation, `popRoute` | `input tap/swipe/text/keyevent` |
| Types | any Unicode, inserted at the caret (`--replace` swaps the field) | ASCII only |
| Waits | frame-synced: every op settles the frame before returning | polls `uiautomator dump` |
| Dump | ~120 ms | ~2 s |
| Cannot see | native chrome: permission prompts, the simulator status bar, share sheets | the soft keyboard is fine; Flutter overlays are fine |
