---
name: qa-emulator
description: Drive the ANTA app on the Android emulator, the iOS simulator or the macOS desktop build through the `tool/qa/qa` CLI, against an isolated QA database that never touches the owner's data. Load it for any device pass; for running the app to see a change working on a device; for screenshots and the accessibility dump; for tapping, typing, scrolling or waiting by label or semantics id; for reading runtime errors and device logs; for the saved calendar and alerts passes with their seeds and flows; and for proving an alarm is armed on Android. The wrapper is `./tool/qa/qa` on macOS and `tool\qa\qa.cmd` on Windows. Load together with anta-context, and with verify when the pass is part of a change's gate.
---

# QA device harness

**Three rules that hold even when the rest of this page is forgotten:**
1. Never drive `adb` or `xcrun simctl` by hand — every device call goes through the wrapper; the few sanctioned read-only or device-UI calls are named where they apply (`references/alarm-evidence.md`, `references/traps.md`).
2. A seed goes in with `qa relaunch --fresh --seed …` (about 2.5 s). `qa run` builds first, so a clock-relative seed — the alerts fixtures, whose events sit minutes ahead — comes out of the build already stale; after a `lib/` change it is two commands, a plain `qa run` and then the relaunch with the seed. `qa run --fresh --seed` is acceptable only for a seed with no clock in it (the calendar fixture) after a `lib/` change.
3. Never start a `flutter test` beside a QA `flutter run`: the two Flutter processes race on `build/native_assets` and kill each other.

One CLI drives whichever device is attached: an iOS simulator, the macOS
desktop build, or an Android emulator. Run it from `frontend/anta`, through
the wrapper:

```bash
./tool/qa/qa <verb> [args]        # macOS, Linux, Git Bash
tool\qa\qa.cmd <verb> [args]      # PowerShell / cmd
```

The wrapper's self-rebuild, the exit codes and `qa devices` in detail: `references/harness-notes.md`.

## Which device

`-d/--device` (or `ANTA_QA_DEVICE`) names the target; with neither, the sole
attached device wins — a booted simulator or a usable adb device. The desktop
app is never picked implicitly.

| `-d` value | Target |
| --- | --- |
| `macos` | the desktop build at `build/macos/Build/Products/Debug/ANTA.app` |
| `ios` | the one booted simulator |
| a simulator name (`"iPhone 17 Pro Max"`) or UDID | that simulator (must be booted — `qa boot --sim` otherwise) |
| `android` or a serial (`emulator-5554`) | that adb device |

## Two driving layers

`--via auto|agent|native` (or `ANTA_QA_VIA`) chooses; `auto` is native on
Android and the agent elsewhere. The agent lives in
[`test_driver/qa_agent.dart`](../../../test_driver/qa_agent.dart) and speaks
the JSON protocol in `tool/qa/src/agent_protocol.dart` through Flutter
Driver's `request_data` command, so nothing about it ships in a normal build.
A dump's labels and ids are the same on all three platforms — `"All notes\n3"`,
`id=search-open`, `"Money\nGreen label\n1"` — so one step file drives all of
them.

Because the agent owns text entry (`TestTextInput`), a driver build never
shows the soft keyboard and the Dart MCP's `enter_text` is disabled there; use
`qa type`. Everything else in the Dart MCP (`widget_inspector`,
`get_runtime_errors`, `hot_reload`, `flutter_driver_command` finders) works
against the DTD `qa run` prints.

What each layer needs, sees and costs, side by side: `references/harness-notes.md`.

## Canonical loop

```bash
q=./tool/qa/qa
$q doctor                                     # first, whenever anything looks off
$q boot                                       # iOS: boots a simulator only if none is; --avd for Android
$q run --fresh --seed tool/qa/fixtures/basic.json    # builds + installs; ~60 s iOS, ~45 s macOS, minutes on Android
$q dtd                                        # -> feed to the Dart MCP: dtd connect <uri>
$q look 00_start                              # ONE call: annotated screenshot (#N tags) + the dump lines
$q tap "Search all notes" --wait id:search-field --shot 01_search
$q type "squat ăöü"                           # any Unicode through the agent
$q expect id:search-field "squat ăöü" --absent "No results found"
$q errors                                     # run log + platform log + the app's own error buffer
```

Use `-d macos` on every line for the desktop app (or `export
ANTA_QA_DEVICE=macos`). Do not `kill-run` at the end unless you started the
run — leave the app up.

**First run on a fresh install.** `--fresh`/`--seed` need somewhere to put the
markers: the app's documents directory, which exists only once the app has
been installed (simulator) or launched once (macOS sandbox container). On a
machine that has never run ANTA, do a plain `qa run` first and then
`qa relaunch --fresh --seed …`; `run` says exactly this when it applies.

## Fast loop

The wall clock is not the expensive part; **your round trips are**. Five tool
calls at model latency cost far more than the five device calls inside them.

- **`steps` runs a whole flow in one call**, sharing one device resolution,
  one agent connection and one dump cache. Each step prints `[2/5] wait
  id:search-field` and then its own output, indented. The first failure stops
  the run and says `steps: stopped at 2/5`; `--keep-going` runs the rest.

  ```bash
  ./tool/qa/qa steps 'tap "Search all notes"' 'wait id:search-field' \
                     'type "squat ăöü"' 'shot results' 'key back'
  ./tool/qa/qa steps --file flow.txt      # one step per line, # comments ok
  ```

  Measured 2026-09-16 on the iPhone 17 Pro Max simulator: an eight-step flow
  (tap, wait, type, dump, shot, back, back, dump) took **1.7 s** end to end.
  From PowerShell 5.1 use `--%` with `\"` escapes or `--file`; it strips the
  inner quotes otherwise.

- **`look` is see-everything in one call**: it dumps, takes the screenshot,
  boxes every interesting node on it with its `#N` tag (orange = tappable,
  blue = text field, green = scrollable) and prints the dump lines under the
  path. Read the picture, then `tap "#14"` — no second look needed. `--all`
  marks every node.

- **`expect` is a checklist in one call**: `expect id:search-field "Training"
  --absent "No results found"` re-checks for `--timeout` seconds and exits 2
  listing every miss, plus the screen it saw. An ambiguous label counts as
  present.

- **Act and verify in one call.** `tap`, `longpress`, `drag`, `type`, `clear`,
  `key`, `swipe`, `launch`, `relaunch`, `reload` and `restart` all take
  `--wait <target>` (or `--wait-gone`, `--wait-timeout S`), `--shot <name>`
  and `--dump`, applied in that order. A `--wait` that times out still takes
  the `--shot` first and says so. On the agent path there is no `--settle`
  pause by default (the op already waited for the frame); on adb it stays
  300 ms.

- **Edit, `reload`, verify.** After a code change, `qa reload --wait "New
  label"` signals the `flutter run` behind `qa run` (SIGUSR1), waits for its
  `Reloaded … libraries` line and then verifies; `qa restart` (SIGUSR2) resets
  state, keeps the QA database and the agent. Both are POSIX only; on Windows
  use the Dart MCP. Measured: reload 0.4 s, restart 1 s including the wait.

- **`perf start` … `perf stop` brackets a flow with frame timing** from
  inside the app: p50/p90/max build, raster and total ms plus a jank count
  (frames whose build or raster exceeded 16.7 ms). Use it around typing in
  the editor or a long scroll; `perf read` samples without stopping.

- **`relaunch` is the ~2 s reset.** It drops the markers, stops the app, starts
  the installed build with a fixed VM-service port and no auth token, waits for
  the agent, prints the `[qa]` lines straight from the app's memory and leaves
  every verb reachable. `run` is the ~1 minute path that also builds, installs
  and gives you a DTD.

- **`#N` resolves against the dump you read**, from `build/qa/last_dump.txt`,
  not against a fresh one — the output says `(#18 from the dump 4 s ago)`.
  `dump --cached` reprints it; `x,y` targets skip the dump entirely.

- **`doctor` first when anything looks off.** One line per check, `ok`/`warn`/
  `FAIL` plus the fix; exit 3 if anything failed. `--fix` applies only the safe
  repairs (wake, unphone, kill a leftover `uiautomator`, clear a stale
  `run.pid`, reap orphaned `dart development-service` processes) and re-runs
  the checks. It never restarts a device, never stops the app and never
  touches app data.

## Verbs, one line each

Flags, an example and the real output of each, how a target resolves, and how to read `doctor`, a dump and a screenshot: `references/verbs.md`. Every acting verb also takes `--wait`, `--wait-gone`, `--wait-timeout`, `--settle`, `--shot` and `--dump`.

- `devices [--all]` — what is drivable; `--all` adds shut-down simulators.
- `state [--json]` — one line: device, app pid, lifecycle, foreground app, awake and locked, keyboard, screen size, driver, URIs.
- `doctor [--fix] [--json]` — one line per check with its fix; `--fix` applies only the safe repairs.
- `boot [--sim N] [--avd N] [--cold] [--phone]` — boots a simulator or the AVD; refuses when a device is already attached.
- `run [--fresh] [--seed F] [--setting K=V] [--define K=V] [--no-qa] [--no-driver]` — builds, installs and starts the QA driver build and gives a DTD (about a minute; minutes on Android).
- `relaunch [--fresh] [--seed F] [--setting K=V]` — restarts the installed build in about 2 s with the markers and the agent; no DTD.
- `launch` — brings the running app to the front, or starts it like `relaunch` without markers.
- `attach` — `flutter attach` to the running app: the DTD and VM URIs again.
- `stop` / `kill-run` — ends the recorded `flutter run`; a device app stays up.
- `dtd [--vm]` — reprints the DTD URI (`--vm`: the VM service URI) for the Dart MCP.
- `agent [info | <op> [json]]` — asks the in-app agent directly: `info`, or one raw op.
- `shot [name] [--scale F] [--full] [--via native|agent]` — a screenshot; prints one path, 0.5× unless `--full`.
- `dump [--all] [--json] [--cached]` — the tree as `#N` lines; `--cached` reprints the last one.
- `tap <target> [--nth N]` — taps a label, an `id:`, a `#N` or raw `x,y`.
- `longpress <target> [--ms]` — long-presses a target.
- `text <target>` — prints a node's text.
- `wait <target> [--gone] [--timeout S]` — waits for a node to appear, or with `--gone` to go.
- `scroll-to <target> [--max N] [--in T] [--up]` — swipes until the node is on screen; `--in` names the scrollable.
- `type "<text>" [--enter] [--replace]` — types into the focused field; any Unicode on the agent path.
- `key <name>` — `back`, `enter`, `done`, and chords such as `ctrl+shift+z` on the agent path.
- `swipe <dir> [--from x,y] [--dist px] [--ms N]` — a swipe, kept clear of the screen's edges.
- `look [name] [--all] [--scale F] [--full] [--via]` — the annotated screenshot and the dump lines in one call.
- `expect <target>… [--absent T]… [--timeout S]` — a checklist of present and absent nodes; exit 2 lists every miss.
- `drag <from> <to> [--hold ms] [--ms N]` — press, hold, move: a reorder (agent path).
- `clear` — empties the focused field (agent path).
- `reload [--timeout S]` / `restart` — hot reload or restart through the `flutter run` behind `qa run` (POSIX only).
- `perf start|stop|read [--json]` — frame timing around a flow.
- `steps <line>… [--file F] [--keep-going]` — a whole flow in one call.
- `flows <dir>[/<flow>] [--keep-going] [--list]` — runs saved flows (`calendar`, `alerts`, `alerts_pair`).
- `set k=v…` — theme, locale and text scale on the running QA build.
- `log [--lines N] [--all]` (alias `logcat`) — the platform log: logcat, the simulator's unified log, or `app.log` on macOS.
- `errors [--lines N] [--all] [--clear]` — the run log, the platform log and the app's own error buffer.
- `build-exe` — rebuilds the compiled wrapper.
- `wake`, `unphone` — Android only: wake the screen; put the screen size back after `boot --phone`.

## Never

- Never kill, wipe, cold-boot or restart an emulator or simulator out from
  under the owner. `boot` refuses when a device is already attached; `xcrun
  simctl erase`/`shutdown` are not verbs here and must not be run by hand
  during a pass.
- Never `pm clear`, `uninstall`, delete app data or a simulator data
  container: the default database in each is the owner's.
- Never edit the default database from a QA run — that is what `ANTA_QA` is
  for. The `agent` doctor line turns FAIL when a non-QA build is being driven.

## Top traps

The ten a pass hits most, copied verbatim — eight from `references/traps.md`, the `ANTA_QA_VIA=agent` one from `references/alerts-pass.md` (the calendar pass needs it on the Windows emulator too), the `scroll-to` one from `references/calendar-pass.md`; change both copies together. "See Targets" is in `references/verbs.md`.

- **`doctor` warns about markers left pending** (`qa_seed.json pending in the
  documents directory`): a non-QA build ignores them and the next QA launch
  would silently apply a stale seed.
- **One `flutter run` at a time.** `run` on a second device kills the first
  run's tool process (not its app). Per-device VM/DTD files keep the verbs
  pointed at the right app; `relaunch` restores the agent on either side.
- **`relaunch` has no DTD.** Hot reload and the Dart MCP's `dtd connect` need
  the `flutter run` from `qa run` (or `qa attach`). `relaunch` records the VM
  URI, which is all the agent and `qa dtd --vm` need.
- **A `wait` on an ambiguous label fails at once** (see Targets). Prefer
  `id:` targets in step files.
- **A tap right after a dialog or sheet closes falls through** to whatever is
  underneath. Put a `wait` (or a second `dump`) between them.
- **Typing goes through `TestTextInput`,** so there is never a soft keyboard,
  `type` refuses when no field is focused (exit 2: tap a field first), and
  `key enter` sends the field's own input action (`search`, `done`,
  `newline`…). `key done|search|newline` sends a specific action.
- **The agent cannot see native UI.** A permission prompt, a share sheet or
  the simulator's own dialogs are invisible to `dump`; `shot` (native on iOS)
  shows them. Android's adb path sees them and warns `foreground is …, not
  com.alexzamfir.anta`.
- **`qa type` on adb warns when no keyboard is up** — with the driver build
  installed that is always, because the agent owns the text channel; use
  `--via agent`.
- Add `--setting alert_notice_lead_minutes=1` to the relaunch to see the
  upcoming notice; the fixtures keep it off so nothing but the rings is on
  the shade. On the Windows emulator run the pass with `ANTA_QA_VIA=agent`.
- **`scroll-to` swipes inside the first scrollable in the tree**, which in
  the editor is the header strip — eight swipes and nothing moves. Pass
  `--in id:event-form` for anything below the fold (`scroll-to
  id:event-priority --in id:event-form`), and scroll before an `--absent`
  check so absence means gone, not off-screen.

The Windows emulator (`Pixel_9_Pro`), from the sessions of 2026-09 and 2026-10 — these never appeared in the harness notes, only in session memory:

- **`qa boot` can exit 3 with "refused to start: WHPX…" while the emulator boots fine** — check `qa devices` before booting a second one.
- **"Lost connection to device" means a degraded quick-boot snapshot**, not the app: boot cold (`qa boot --avd Pixel_9_Pro --cold`, with `ANDROID_HOME` set).
- **An install that vanishes at boot** ("permissions stripped every run") is the emulator deleting the package after a hard kill, frozen into the quick-boot snapshot — cold boot and reinstall; the app's permission code is not at fault.
- **An R8 `classes.dex` lock or a build that cannot delete `build/`** is a stale Gradle daemon of another version or an Explorer window holding the folder: `release doctor --fix` stops the daemons; close Explorer.

## References

| File | What it holds | Read it when |
| --- | --- | --- |
| [references/verbs.md](references/verbs.md) | "Verbs": each verb's flags, an example and its real output; "Reading `doctor`", "Targets" (the label passes, `id:`, `#N`, `x,y`, ambiguity), "Reading a dump", "Reading a screenshot" | an output, an exit code or a target puzzles you; before writing a step file |
| [references/traps.md](references/traps.md) | "Traps", all of them: shared, iOS simulator, macOS, Android (the keyboard-inset recipe, the Windows launcher), notification-shade actions, the Quick Settings tile | a verb misbehaves on one platform, or the pass touches the shade, a tile or the keyboard inset |
| [references/calendar-pass.md](references/calendar-pass.md) | "The calendar pass (2026-09-26)": the relative-dated seed and its placeholders, the flows, `qa set`, the calendar's semantics ids, the calendar traps | running, writing or fixing a calendar flow |
| [references/alerts-pass.md](references/alerts-pass.md) | "The alerts pass (2026-10-05)": the two minute-relative fixtures, their flows, the alarm page's ids, seven device facts | running or fixing the alerts flows |
| [references/alarm-evidence.md](references/alarm-evidence.md) | "Alarm-clock evidence (event alerts, Android)" and "A ring on a locked phone (2026-10-04)": the sanctioned read-only queries, a passing `dumpsys alarm` entry, the PIN-lock recipe | proving an alarm is armed, or a ring behind a keyguard or in a dead process |
| [references/dart-mcp.md](references/dart-mcp.md) | "Dart MCP tools": `dtd connect`, runtime errors, hot reload, the widget tree, driver finders | driving the Dart MCP against a QA run |
| [references/isolation.md](references/isolation.md) | "Isolation model": the QA database, the Firebase cut-off, log redaction, the `[qa]` lines, the marker files per platform | a `--fresh` or `--seed` did not land, or you doubt the owner's data is safe |
| [references/secrets.md](references/secrets.md) | "Secrets and credentials files" | before opening or checking a Firebase config file or a keystore, or sharing anything from `build/qa/` |
| [references/harness-notes.md](references/harness-notes.md) | the wrapper's self-rebuild and the exit codes; `qa devices` and its real output; the one `flutter run` slot; the two driving layers side by side | the wrapper rebuilds, an exit code needs reading, or you are choosing between the agent and adb |
| [references/harness-context.md](references/harness-context.md) | the project context's QA lines: the QA defines, the Firebase cut-off, the marker files, the driver and the agent, the calendar and alerts layers | you change the app side of QA mode |
| [docs/qa-harness.md](../../../docs/qa-harness.md) | the harness's architecture (two driving layers and one verb layer, how the agent is reached, speed, the Windows launcher, the app seams contract) and the history of the end-to-end passes (2026-09-13, -16, -17), the calendar layer, the alarm-clock evidence, Phase C | you change the harness itself, or need to know why it is built as it is |
