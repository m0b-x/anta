---
name: qa-emulator
description: Drive the ANTA app on the Android emulator fleet, the iOS simulator or the macOS desktop build through the `tool/qa/qa` CLI, against an isolated QA database that never touches the owner's data. Load it for any device pass (`qa fleet pass <suite>` runs a whole suite in one call and writes a JSON report); for running the app to see a change working on a device; for screenshots and the accessibility dump; for tapping, typing, scrolling or waiting by semantics id; for reading runtime errors and device logs; for the saved calendar, browser and alerts passes with their seeds and flows; for booting, installing on and stopping the headless fleet AVDs; and for proving an alarm is armed on Android. The wrapper is `./tool/qa/qa` on macOS and Git Bash, `tool\qa\qa.cmd` in PowerShell. Load together with anta-context, and with verify when the pass is part of a change's gate.
---

# QA device harness

**Four rules that hold even when the rest of this page is forgotten:**
1. Never drive `adb`, `emulator`, `avdmanager` or `xcrun simctl` by hand — every device call goes through the wrapper; the few sanctioned read-only queries are named where they apply (`references/alarm-evidence.md`, `references/traps.md`).
2. A seed goes in with `qa relaunch --fresh --seed …` — which is what `qa pass` does before every flow — never with `qa run`: `run` builds first, so a clock-relative seed (the alerts fixtures) comes out of the build already stale. After a `lib/` change the fleet path is `qa fleet install --build`, then the pass.
3. Never start a `flutter test` beside a QA `flutter run` or a `qa build`: two Flutter processes race on `build/native_assets` and kill each other. A pass itself runs no Flutter process, so `flutter test` can run beside `qa fleet pass`.
4. The fleet verbs act only on AVDs named `anta_qa_*`. The owner's windowed `Pixel_9_Pro` (`emulator-5554`) is never booted, stopped, seeded or wiped by a QA agent; no verb deletes an AVD, wipes data, clears or uninstalls the app.

One CLI drives whichever device is attached: a headless fleet emulator, the owner's emulator, an iOS simulator or the macOS desktop build. Run it from `frontend/anta`, through the wrapper:

```bash
./tool/qa/qa <verb> [args]        # macOS, Linux, Git Bash
tool\qa\qa.cmd <verb> [args]      # PowerShell / cmd
```

The wrapper's self-rebuild, the exit codes, the pass report and the fleet in detail: `references/harness-notes.md`. The design record with the measurements behind every default: `docs/qa-pass-rework.md`.

## Which device

`-d/--device` (or `ANTA_QA_DEVICE`) names the target; with neither, the sole attached device wins — a booted simulator or a usable adb device. With the fleet up there are several, so pass `-d emulator-5556` (or let `fleet pass` shard). The desktop app is never picked implicitly.

| `-d` value | Target |
| --- | --- |
| `emulator-5556`, `-5558`, `-5560` | the fleet AVDs `anta_qa_1..3` (`qa fleet status` lists them) |
| `macos` | the desktop build at `build/macos/Build/Products/Debug/ANTA.app` |
| `ios` | the one booted simulator |
| a simulator name (`"iPhone 17 Pro Max"`) or UDID | that simulator (must be booted — `qa boot --sim` otherwise) |
| `android` or a serial | that adb device |

## A pass in one call

```bash
q=./tool/qa/qa
$q fleet status                        # what is up, what carries which build
$q fleet boot --all                    # headless, P-core pinned; ≈ 15 s each once booted before
$q fleet install --build               # build the QA driver APK once (≈ 10–40 s), install everywhere (≈ 3 s each)
$q fleet pass calendar                 # 26 flows sharded over the fleet: ≈ 4.5 min wall, one summary, one report
$q fleet pass browser                  # the browser suite the same way
$q pass alerts -d emulator-5556        # clock-relative suites run whole on one device (reseed=suite, shard=no)
$q pass calendar --only 19_fasting_schedule -d emulator-5558   # one flow: reseed, prelude, the flow
$q pass --summary build/qa/pass/<dir>/report.json              # reprint any report; --merge joins shard reports
```

`pass` reseeds (`relaunch --fresh --seed <fixture>`) before every flow, runs the suite's `_prelude.txt` (the calendar's lands on the calendar page), keeps going after a red, captures a screenshot, the dump and the errors at a red flow's failing step, and writes `report.json` after every flow (`"partial": true` until the end). Exit 0 all green, 2 any red, 3 the device or the reseed failed before anything ran. The report's keys and the directory layout: `references/harness-notes.md` "The pass and its report". A stale-build warning in the output means the installed APK predates a source change: `fleet install --build`, then run again.

A suite is a directory under `tool/qa/flows/`: `_suite.txt` (`fixture=`, `reseed=flow|suite|none`, `shard=yes|no`, `prelude=`), `_prelude.txt`, `_labels.txt` (the content labels its flows may still target by text) and the `NN_name.txt` flows. `test/qa/flows_lint_test.dart` rejects a `tap`/`wait`/`scroll-to`/`longpress`/`drag` target that is not an `id:`, `#N`, `x,y`, a `{{placeholder}}` label or an allow-listed content label, so every control a flow touches carries a `SemanticsIds` entry.

## Hand-driven loop

```bash
$q doctor                                     # first, whenever anything looks off (one line per check, --fix for the safe repairs)
$q -d emulator-5556 relaunch --fresh --seed tool/qa/fixtures/basic.json   # ≈ 5.5 s on a fleet device
$q -d emulator-5556 look 00_start             # ONE call: annotated screenshot (#N tags) + the dump lines
$q -d emulator-5556 tap id:search-open --wait id:search-field --shot 01_search
$q -d emulator-5556 type "squat ăöü"          # any Unicode through the agent
$q -d emulator-5556 expect id:search-field "squat ăöü" --absent "No results found"
$q -d emulator-5556 errors                    # run log + platform log + the app's own error buffer
```

`qa run --fresh --seed …` is still the path with a DTD for hot reload and the Dart MCP (`qa dtd`), and the only path on macOS and iOS; it builds and installs (≈ 1 min; minutes on Android) and holds the one `flutter run` slot. **First run on a fresh install**: markers need the app's documents directory, which `qa install` creates by launching once; on macOS/iOS do a plain `qa run` first.

## Two driving layers

`--via auto|agent|native` (or `ANTA_QA_VIA`) chooses; `auto` is the in-app agent wherever it answers on the VM URI a launch recorded, and adb on Android when it does not (`state` prints `driver=agent (auto)` or `adb (auto)`). The agent lives in [`test_driver/qa_agent.dart`](../../../test_driver/qa_agent.dart) and speaks the JSON protocol in `tool/qa/src/agent_protocol.dart` (version 2: node ids and `reveal`) through Flutter Driver's `request_data`, so nothing about it ships in a normal build. A dump's labels and ids are the same on all platforms, so one step file drives all of them. A `--via native` written on one step of a flow holds for that step only — the overview's scrubber swipe needs a real touch.

Because the agent owns text entry (`TestTextInput`), a driver build never shows the soft keyboard; use `qa type`. The two layers side by side: `references/harness-notes.md`.

## Fold-proof targets

A node the framework keeps in the semantics tree but scrolled out of its viewport (`hidden` in the dump) counts as **present** for `expect` and `wait`, and `--absent`/`--gone` mean no node matches at all. `tap`, `longpress`, `drag` and `scroll-to` first ask the app to scroll such a node on screen (the `reveal` op, Flutter's `showOnScreen`), then act; `scroll-to` swipes only when the target is not in the tree at all (a list row beyond the cache extent). A node that is merely outside the screen rect without the flag (`offscreen` — a sheet still sliding in) does not count as present, so `wait` keeps polling. `--nth` numbers every match in traversal order, hidden ones included.

## Fast loop

The wall clock is not the expensive part; **your round trips are**. A whole suite is one call (`pass`); a screen under study is a few.

- **`steps` runs several verbs in one process**, sharing one device resolution, one agent connection and one dump cache; the first failure stops it (`--keep-going` runs on); a line that fails to parse is one failed step, not an abort. `steps --file flow.txt` is one flow; `pass` is the whole suite with the reseed and the report.
- **`look` is see-everything in one call**: dump + screenshot with every interesting node boxed and `#N`-tagged; then `tap "#14"`.
- **`expect` is a checklist in one call**; it re-checks for `--timeout` seconds and exits 2 listing every miss plus the screen it saw.
- **Act and verify in one call**: every acting verb takes `--wait`, `--wait-gone`, `--wait-timeout`, `--shot` and `--dump`.
- **`relaunch` is the reset** (≈ 4 s on the owner's emulator, ≈ 5.5 s on a pinned fleet device); `run` is the minute-long path with a DTD.
- **`reload`/`restart`** work on the `flutter run` behind `qa run` (POSIX only); on Windows use the Dart MCP.
- **`perf start|stop|read`** brackets a flow with frame timing from inside the app.
- **`#N` resolves against the dump you read**, per device (`build/qa/last_dump_<device>.txt`); `dump --cached` reprints it.
- **`doctor` first when anything looks off**; `--fix` applies only the safe repairs; its `fleet` line says which AVDs are up and pinned.

## Verbs, one line each

Flags, an example and the real output of each: `references/verbs.md`. Every acting verb also takes `--wait`, `--wait-gone`, `--wait-timeout`, `--settle`, `--shot` and `--dump`.

- `pass <suite>[/<flow>] [--only F]… [--shard i/n] [--no-reseed] [--stop-on-fail] [--json P] [--label T]` — a suite in one call with a report; `--summary R`, `--merge A B…`.
- `build [--define K=V]… [--no-driver]` — the QA driver APK once (`build/qa/apk.json`); refused beside a live `qa run`.
- `install [--apk P]` — `adb install` + one launch on the selected device (`installed_<device>.json`).
- `fleet create|boot|status|stop|install|pass` — the headless AVDs `anta_qa_N` (`references/harness-notes.md` "The fleet").
- `devices`, `state`, `doctor [--fix]`, `boot [--avd N | --sim N] [--cold]` — the owner's emulator or a simulator, never the fleet.
- `run [--fresh] [--seed F] [--setting K=V] [--define K=V]`, `relaunch [--fresh] [--seed F] [--setting K=V]`, `launch`, `attach`, `stop`, `kill-run`, `dtd`, `agent [info|<op>]`.
- `shot`, `dump [--all] [--json] [--cached]`, `look`, `expect`, `wait [--gone] [--timeout S]`, `text`.
- `tap`, `longpress`, `scroll-to [--in T] [--up] [--max N]`, `type [--enter] [--replace]`, `key`, `swipe`, `drag [--hold ms]`, `clear`.
- `flows <dir>[/<flow>] [--keep-going] [--prelude]` — the old runner without reseed or report (the prelude runs for a directory and for the first flow).
- `steps`, `reload`, `restart`, `perf`, `set k=v…`, `log`, `errors [--clear]`, `build-exe`, `wake`, `unphone`.

## Never

- Never kill, wipe, cold-boot or restart the owner's emulator or a simulator out from under them; `boot` refuses when a device is already attached. `fleet stop` takes only `anta_qa_*` names and only what you booted in this run.
- Never `pm clear`, `uninstall`, delete app data, a simulator container or an AVD: they are not verbs here and must not be run by hand.
- Never edit the default database from a QA run — that is what `ANTA_QA` is for. The `agent` doctor line turns FAIL when a non-QA build is being driven.

## Top traps

The ones a pass hits most; all of them in `references/traps.md`.

- **A stale-build warning** at the top of a pass: the APK on the device predates a source change. `fleet install --build`, run again.
- **A headless emulator that is uniformly slow** (first frame 9 s instead of 5, every tap half a second): its qemu is on the E-cores. `fleet boot` pins it; `fleet status` shows `affinity=0xFFFF`; an unpinned one is a `doctor` warn.
- **The calendar's bottom panel restores its mode about a second after the page opens**, overwriting a tap on "Upcoming" (an app race, `lib/widgets/calendar_bottom_panel.dart`): the calendar prelude ends with `tap id:panel-mode-day --settle 2000` to ride it out. A flow that taps a panel mode right after landing without that settle is flaky by design until the app fixes it.
- **`doctor` warns about markers left pending** (`qa_seed.json pending in the documents directory`): a non-QA build ignores them and the next QA launch would silently apply a stale seed.
- **One `flutter run` at a time.** `run` on a second device kills the first run's tool process. The fleet never needs `run`.
- **`relaunch` has no DTD**; hot reload and the Dart MCP need the `flutter run` from `qa run` (or `qa attach`).
- **A `wait` on an ambiguous label fails at once.** Prefer `id:` targets; the lint enforces it in saved flows.
- **A tap right after a dialog or sheet closes falls through** to whatever is underneath. Put a `wait` between them.
- **Typing goes through `TestTextInput`:** no soft keyboard, `type` refuses when no field is focused, `key enter` sends the field's own action.
- **The agent cannot see native UI.** A permission prompt, a share sheet or the shade are invisible to `dump`; `shot --via native` shows them and `swipe … --via native` reaches them.
- **`--absent` on a `ListView.builder` row** beyond the cache extent passes because the row is not in the tree; scroll it into the cache extent first when absence must mean gone, not far away.
- **A v1 agent in the APK** fails a tap on a scrolled-out node with "installed agent is v1, this tool needs v2 — `qa build` then `qa install`".
- **`latest_<suite>.txt` after a sharded pass** points at the last shard until `fleet pass` (or `--merge`) writes the merged report.

The Windows emulator traps that never made it into the notes until 2026-10: `qa boot` can exit 3 with "refused to start: WHPX…" while the emulator boots fine (`qa devices` tells); "Lost connection to device" is a degraded quick-boot snapshot — cold boot (`qa boot --avd Pixel_9_Pro --cold`); an install that vanishes at boot is the snapshot's doing, not the app's; an R8 `classes.dex` lock is a stale Gradle daemon or an Explorer window on `build/`. The fleet AVDs boot cold every time, so none of these apply to them.

## References

| File | What it holds | Read it when |
| --- | --- | --- |
| [references/harness-notes.md](references/harness-notes.md) | the wrapper and the exit codes; "The pass and its report" (the JSON contract, the directory layout, the exit codes); "The fleet" (names, ports, boot flags, the pin, capacity); the `auto` driver choice; the two layers side by side; the one `flutter run` slot | you read a report, run or extend the fleet, or choose between the agent and adb |
| [references/verbs.md](references/verbs.md) | "Verbs": each verb's flags, an example and its real output; "Reading `doctor`", "Targets", "Reading a dump", "Reading a screenshot" | an output, an exit code or a target puzzles you; before writing a step file |
| [references/traps.md](references/traps.md) | every trap: shared, iOS simulator, macOS, Android, the fleet, the pass, the shade and the keyboard inset | a verb misbehaves on one platform, or the pass touches the shade, a tile or the keyboard |
| [references/calendar-pass.md](references/calendar-pass.md) | the calendar suite: its seed and placeholders, the prelude, the flows, `qa set`, the calendar's ids, the calendar traps | running, writing or fixing a calendar flow |
| [references/alerts-pass.md](references/alerts-pass.md) | the alerts suites: the two minute-relative fixtures, their flows, the alarm page's ids, seven device facts | running or fixing the alerts flows |
| [references/alarm-evidence.md](references/alarm-evidence.md) | the sanctioned read-only queries, a passing `dumpsys alarm` entry, the PIN-lock recipe | proving an alarm is armed, or a ring behind a keyguard |
| [references/dart-mcp.md](references/dart-mcp.md) | `dtd connect`, runtime errors, hot reload, the widget tree, driver finders | driving the Dart MCP against a `qa run` |
| [references/isolation.md](references/isolation.md) | the QA database, the Firebase cut-off, log redaction, the `[qa]` lines, the marker files and the per-device files under `build/qa/` | a `--fresh` or `--seed` did not land, or you doubt the owner's data is safe |
| [references/secrets.md](references/secrets.md) | secrets and credentials files | before opening a Firebase config or a keystore, or sharing anything from `build/qa/` |
| [references/harness-context.md](references/harness-context.md) | the project context's QA lines: the defines, the Firebase cut-off, the markers, the driver and the agent | you change the app side of QA mode |
| [docs/qa-harness.md](../../../docs/qa-harness.md) | the harness's architecture and the history of the end-to-end passes | you change the harness itself |
| [docs/qa-pass-rework.md](../../../docs/qa-pass-rework.md) | the 2026-10-23 rework: decisions A–N, the measurements, each slice as built, the deferred list | you wonder why a default is what it is |
