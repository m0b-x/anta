---
name: qa-emulator
description: Drive the ANTA app on an iOS simulator, the macOS desktop build or the Android emulator from the command line - boot, launch in an isolated QA database, screenshot, read the accessibility tree, tap/type by label, and read runtime errors. USE FOR - running the app on a device, device passes, screenshots, tapping/typing by label, reading runtime errors, QA checklists. Load together with anta-context.
---

# QA device harness

One CLI drives whichever device is attached: an iOS simulator, the macOS
desktop build, or an Android emulator. Run it from `frontend/anta`, through
the wrapper:

```bash
./tool/qa/qa <verb> [args]        # macOS, Linux, Git Bash
tool\qa\qa.cmd <verb> [args]      # PowerShell / cmd
```

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
back in two seconds).

## Two driving layers

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

## The calendar pass (2026-09-26)

One command is a device pass of the calendar, against a seed that puts every
calendar state around today:

```bash
./tool/qa/qa relaunch --fresh --seed tool/qa/fixtures/calendar.json   # ~2.5 s; `run` instead after a lib change
./tool/qa/qa flows calendar                                           # seven flows, ~35 s on the simulator
./tool/qa/qa flows calendar/03_dates                                  # one flow; --keep-going runs past a failure
```

`tool/qa/fixtures/calendar.json` is written with **relative dates** —
`"startDateMs": "{{today-28}}"`, `"dayMs": "{{today+7}}"` — that the tool
resolves against the run's clock before pushing (`(60 placeholders
resolved)` in the push line); the resolved copy lands in
`build/qa/seed_resolved.json`, the fixture in the repo is never edited. It
seeds a weekly session with presence marks, a skipped day and a per-day
description, a daily walk carrying five alerts (the cap), six pinned dates,
a yearly birthday with a custom colour, a workdays event that assumes
absence, an ended one-time event, an event in a hidden category, a template,
a saved filter, a custom holiday, the German holiday profile and Orthodox
fasting. `test/qa/calendar_fixture_test.dart` pins that every piece imports
and occurs where the flows expect it. `--setting key=value` (repeatable)
overrides a settings key in the seed before it is pushed — `--setting
locale=de --setting theme_mode=dark` is the matrix at launch.

The flows live in `tool/qa/flows/calendar/*.txt`, one per checklist item
(open, new event, editor sub-sheets and the dirty guard, the Dates sheet,
the alert cap, the overview page, the accessibility matrix), each ending in
`expect`s, a `shot` and `errors`. **A flow is updated in the same slice that
changes its screen**, and the last slice of a calendar rework runs
`flows calendar` (the `ui-revamp` gate). Every flow starts and ends on the
calendar page except `00_open`, which starts at the root — so a full pass
starts from a fresh launch.

Placeholders work in step files too: `tap "{{longdate+1}}"` taps tomorrow's
day cell by the label the grid gives it.

| Placeholder | Value |
| --- | --- |
| `{{today}}`, `{{today+N}}` | UTC midnight of that day, epoch ms (`startDateMs`, `dayMs`) |
| `{{now}}` | this instant, epoch ms (`createdAtMs`) |
| `{{day+N}}` | `yyyy-MM-dd` |
| `{{longdate+N}}` | `Sunday, September 27, 2026` — the English label a month-grid day cell carries |
| `{{weekday+N}}`, `{{year+N}}`, `{{month+N}}`, `{{dom+N}}` | that day's ISO weekday / year / month / day of month |

A numeric placeholder written as a JSON string (`"{{today+3}}"`) sheds its
quotes on resolution, so a fixture is valid JSON before and after.

**`set` is the matrix without a rebuild or a relaunch:**

```bash
./tool/qa/qa set theme=dark locale=de text-scale=2.0   # any subset; the agent's `set` op
./tool/qa/qa set text-scale=off locale=system theme=system
```

Locale and theme go through the app's own settings bloc (they persist like a
tap in Settings would); the text scale is a QA-only override
(`QaOverrides.textScale`, mounted by `MaterialApp.builder` in a QA build;
`--define ANTA_QA_TEXT_SCALE=2.0` seeds it at launch). `agent info` and
`doctor` print `scale=2.0` while one is imposed. In German the ids still
resolve — that is what they are for.

**Calendar targets** (`lib/constants/semantics_ids.dart`): the editor's rows
(`event-title`, `event-category`, `event-look`, `event-date`, `event-dates`,
`event-add-date`, `event-all-day`, `event-starts`, `event-ends`,
`event-repeat`, `event-priority`, `event-linked-note`, `event-alert-add`),
its chrome (`event-close`, `event-save`, `event-save-as-template`,
`event-delete`) and its scrolling body (`event-form`); the sub-sheets' Done
(`repeat-done`, `look-done`); the Dates sheet (`date-picker-save`,
`date-picker-cancel`); the detail sheet (`event-detail-edit`,
`event-detail-close`); and **a day-panel row by its event id**
(`event-row-<eventId>`, e.g. `id:event-row-qa-cal-lift` for the seed's
weekly session). A title is never a safe target on the calendar page:
every marked day cell's marker label carries the titles of its events, so
`tap "Morning walk"` is ambiguous twelve ways.

Calendar traps, all seen 2026-09-26:

- **`scroll-to` swipes inside the first scrollable in the tree**, which in
  the editor is the header strip — eight swipes and nothing moves. Pass
  `--in id:event-form` for anything below the fold (`scroll-to
  id:event-priority --in id:event-form`), and scroll before an `--absent`
  check so absence means gone, not off-screen.
- **Day cells are label-only.** `table_calendar` wraps each cell with
  excluded semantics, so an id inside the cell never reaches the tree; tap a
  day by `"{{longdate+N}}"`.
- **`MenuAnchor` items expose no semantics nodes** (the priority and day-rail
  menus): the menu draws, `dump --all` shows only the scrim. A flow can open
  the menu, `shot` it and `key escape`; it cannot pick an item by label. A
  screen-reader gap to fix on the app side, not a tool problem.
- **`relaunch` starts the installed build**, without anything hot-reloaded
  since the last `qa run`; after a lib change, `qa run --fresh --seed …` is
  the honest path (about a minute). **`restart` after `attach` lost the
  agent** once (`no isolate exposes ext.flutter.driver`) — `qa run` again.
- The `[qa] seed:` line counts folders and notes only; the calendar entities
  import silently. A grid with fasting tints but no events after a seed
  means the events were skipped — check the push line said `placeholders
  resolved`.

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

## Verbs

Every acting verb also takes `--wait T` / `--wait-gone T` / `--wait-timeout S`
/ `--settle MS` / `--shot NAME` / `--dump`.

| Verb | Example | Real output (2026-09-16) |
| --- | --- | --- |
| `devices [--all]` | `qa devices` | see above |
| `state [--json]` | `qa state` | `device=B57A8680-… (ios)  app=pid 16257  lifecycle=resumed  foreground=com.alexzamfir.anta  awake=yes  locked=?  ime=down  screen=1320x2868 @480dpi (440 x 956 dp)  driver=agent  run.log=yes  dtd=ws://…  vm=http://…` |
| `doctor [--fix] [--json]` | `qa doctor` | see below |
| `boot [--sim N] [--avd N] [--cold] [--phone]` | `qa boot --sim "iPhone 17 Pro"` | `booting iPhone 17 Pro (A8642AB6-…)…` then `ready: A8642AB6-…  iPhone 17 Pro (iOS 26.2)`; `--avd`, `--cold`, `--phone` are the Android path |
| `run [--fresh] [--seed F] [--setting K=V] [--define K=V] [--no-qa] [--no-driver]` | `qa run --fresh --seed tool/qa/fixtures/basic.json` | `pid=14023  log=…/build/qa/run.log` / `dtd=ws://…` / `vm=http://…` then the three `[qa]` lines — 27–62 s on the simulator, 27–44 s on macOS; a cold Android build gets up to 8 minutes with a `still waiting for flutter run (40 s): …` heartbeat every 20 s |
| `relaunch [--fresh] [--seed F] [--setting K=V]` | `qa relaunch --fresh --seed tool/qa/fixtures/basic.json` | `launched: xcrun simctl launch com.alexzamfir.anta (vm-service-port 51615)` / `vm=http://127.0.0.1:51615/  (no DTD after a bare launch …)` / `agent: iOS  1320x2868 @3.0x  lifecycle=resumed  semantics=on  textField=none  qa=qa` then the `[qa]` lines — 1.9–2.5 s |
| `launch` | `qa launch --wait Folders` | brings a running app to the front, or starts it like `relaunch` without markers |
| `attach` | `qa attach` | `flutter attach` against the running app: DTD + VM URIs again |
| `stop` / `kill-run` | `qa kill-run` | `killed run pid 14023` then `forgot the URIs recorded for <device> (they died with the run — …)` — only when the recorded URI is the run's own DDS proxy; a URI a later `relaunch` recorded is kept (`kept the VM URI for <device> …`). A device app stays up; a desktop app started by that run dies with it |
| `dtd [--vm]` | `qa dtd` | `ws://127.0.0.1:51233/FFsxRyTXm7w=`; after a bare `relaunch` there is no DTD and it says so (`--vm` still prints the VM URI) |
| `agent [info \| <op> [json]]` | `qa agent info` | `iOS  1320x2868 @3.0x  lifecycle=resumed  semantics=on  textField=none  qa=qa  (19 ms round trip, protocol v1, up 515.3 s)` then `documents: …` and the `[qa]` lines |
| `shot [name] [--scale F] [--full] [--via native\|agent]` | `qa shot home` | `…/build/qa/shots/20260916_205807_home.png` — native `simctl` capture on iOS (0.45 s, includes the status bar), the agent's render on macOS (0.4 s, Flutter view only); `adb screencap` on Android |
| `dump [--all] [--json] [--cached]` | `qa dump` | see below; ends `14 node(s) of 23 (pass --all for the rest)  [agent]` |
| `tap <target> [--nth N]` | `qa tap "Search all notes"` | `tapped 1104,258  #9  Button  "Search all notes"  id=search-open  [1032,186][1176,330]  click` |
| `longpress <target> [--ms]` | `qa longpress "Injury notes"` | `long-pressed 640,2440 for 800ms  …` |
| `text <target>` | `qa text id:search-field` | the node's text |
| `wait <target> [--gone] [--timeout S]` | `qa wait id:search-field` | `found: #8  EditText  "Search all notes"  id=search-field  [216,219][1272,297]  click,focused` |
| `scroll-to <target> [--max N] [--in T] [--up]` | `qa scroll-to "Warm-up protocol"` | `found after 2 swipe(s): #32  View  "Warm-up protocol…"` |
| `type "<text>" [--enter] [--replace]` | `qa type "squat ăöü"` | `typed "squat ăöü"  → field: "squat ăöü" (caret 9)` |
| `key <name>` | `qa key back` | `sent back`; with nothing to pop: `sent back (nothing to pop — already at the root route, so the app was left running)`. Chords work on the agent path: `key meta+z`, `key ctrl+shift+z`, `key shift+tab` |
| `swipe <dir> [--from x,y] [--dist px] [--ms N]` | `qa swipe up` | `swiped up: 660,1434 -> 660,48 (300ms)` |
| `look [name] [--all] [--scale F] [--full] [--via]` | `qa look root` | the annotated PNG path, then the dump lines, then `14 node(s) marked; orange = tappable, blue = text field, green = scrollable` |
| `expect <target>… [--absent T]… [--timeout S]` | `qa expect id:search-open Training --absent Rename` | `ok  present  "id:search-open"` per target; exit 2 with `2 expectation(s) failed after 5s:` + the misses + the screen listing |
| `drag <from> <to> [--hold ms] [--ms N]` | `qa drag "Week 1" "Inbox"` | `dragged 660,1200 -> 660,976  #19 …  onto  #17 …` (press, hold 600 ms, move over 400 ms — a reorder needs the hold; agent path) |
| `clear` | `qa clear` | `cleared the focused field` (agent path) |
| `reload [--timeout S]` / `restart` | `qa reload --wait "New label"` | `reloaded in 253 ms: Reloaded 0 libraries in 75ms (…)` / `restarted in 1046 ms: Restarted application in 984ms.` — needs the live `flutter run` from `qa run` |
| `perf start\|stop\|read [--json]` | `qa perf stop` | `frames=122 over 2414 ms  jank=0 (build or raster over 16.7 ms)` then one line each for build, raster, total (p50/p90/max ms) |
| `steps <line>… [--file F] [--keep-going]` | `qa steps 'tap "Training"' 'key back'` | `[1/2] tap "Training"` then the verb's output, indented; `{{today+N}}`-style placeholders resolve first |
| `flows <dir>[/<flow>] [--keep-going] [--list]` | `qa flows calendar` | `=== flow 1/7: 00_open.txt` … `=== 00_open.txt: ok in 2460 ms` per file, then `flows: all 7 passed` |
| `set k=v…` | `qa set theme=dark locale=de text-scale=2.0` | `set  text-scale=2.0  locale=de  theme=dark` |
| `log [--lines N] [--all]` (alias `logcat`) | `qa log --lines 40` | logcat on Android; the simulator's unified log (~1 s, last 10 min) on iOS; the app's stdout (`build/qa/app.log`) on macOS |
| `errors [--lines N] [--all] [--clear]` | `qa errors` | `no errors in …/run.log` / `no errors in simulator log` / `no errors in agent` — the last is the app's own `FlutterError.onError` buffer, which only the driver build has |
| `build-exe` | `qa build-exe` | `…/build/qa/qa  (2327 ms)` |
| `wake`, `unphone` | | Android only; `qa wake -d ios` exits 1 saying so |

### Reading `doctor`

Real output, iPhone 17 Pro Max simulator, 2026-09-16:

```
ok    xcrun                   /usr/bin/xcrun present
ok    simulator               iPhone 17 Pro Max (iOS 26.2) booted
ok    app installed           ~/Library/Developer/CoreSimulator/Devices/B57A8680-…/data/Containers/Bundle/Application/C0B007D5-…/Runner.app
ok    app running             pid 16257, lifecycle resumed
ok    agent                   answered in 1 ms  iOS  1320x2868 @3.0x  lifecycle=resumed  semantics=on  textField=none  qa=qa
ok    host run state          run.pid 14023 is alive
ok    dtd                     ws://127.0.0.1:51233/FFsxRyTXm7w=
ok    qa.exe                  up to date
```

After the app quit under it, the same command said `warn  app running  no
process`, `FAIL  agent  cannot reach the VM service at ws://127.0.0.1:52186/ws:
Connection refused. The recorded run is gone … — run `qa relaunch`` and
`warn  host run state  run.pid names 18253, which is gone` — three lines that
together mean "relaunch, then `doctor --fix`". `qa=OFF (owner database!)` in
the agent line is a **FAIL**: the running build is not a QA build and is
reading the owner's data — `qa run` installs the right one. On Android the
list is the adb one (adb server, device, boot, awake, screen, app installed,
app running, uiautomator, /data space) plus an agent line that only matters
with `--via agent`.

### Targets

A target is one of:

- `#12` — the flat node index, resolved against **the cached dump**
  (`build/qa/last_dump.txt`) so the index still means the node you read;
- `123,456` — raw device pixels (physical, the same space the screenshots
  and the dump use), which costs no dump at all;
- `id:content` — a `Semantics.identifier` from
  `lib/constants/semantics_ids.dart` (the Android resource id; it never moves
  with the locale);
- anything else — a **label**, matched against content description (label +
  tooltip), then text (the value), then id, in three passes: exact,
  case-insensitive, case-insensitive substring. The first pass with any hit
  wins.

An ambiguous label exits 2 and lists the candidates with the `--nth N`
(0-based) that picks each one. **`wait` on an ambiguous label exits 2 at
once** rather than polling: `"All notes"` matches both `"All notes\n3"` and
`"Search all notes"` — wait for `id:drawer-all-notes` or `"All notes\n3"`
instead. A tap on a node that is not itself clickable retargets to the nearest
clickable ancestor and says so; a tap on a node the dump marked `hidden`
(scrolled out of view) exits 2 with `scroll-to it first`.

A label that matches nothing exits 2 **with the screen it looked at**:

```
qa: no node matches "Nothing here at all". on screen (com.alexzamfir.anta):
"Open navigation menu" | "Search all notes" | "Show menu" | "Folders" |
"All notes / 3" | "Recent" | "FOLDERS" | "Inbox / 0" |
"Money / Green label / 1" | "Training / Blue label / 2" | "New folder" |
"Import" | "3 folders"
```

### Reading a dump

`dump` prints `#index  Class  "content-desc"  text="…"  hint="…"  id=…
[l,t][r,b]  flags`, labelled/clickable/scrollable nodes only (`--all` adds the
rest, including off-screen `hidden` ones). Real output, simulator, QA build
seeded from `basic.json`:

```
#7  Button  "Open navigation menu"  [0,186][168,330]  click
#9  Button  "Search all notes"  id=search-open  [1032,186][1176,330]  click
#13  Scroll  [0,0][1320,2586]  scroll
#14  View  "All notes
3"  id=drawer-all-notes  [0,492][1320,639]  click
#18  View  "Money
Green label
1"  [0,1050][1320,1197]  click,long
#20  Button  "New folder"  id=create-folder  [12,2595][174,2757]  click
14 node(s) of 23 (pass --all for the rest)  [agent]
```

The class is a role derived from the semantics flags (`Button`, `EditText`,
`Switch`, `CheckBox`, `Scroll`, `Header`, `Image`, `View`), so it reads like
the Android dump; a text field shows its content as `text="…"` and its
placeholder as `hint="…"`. The `[agent]` tail says which layer produced it. On
Android's adb path the format is the uiautomator one from the earlier skill
version (`android.widget.Button`, `id=` from the resource id).

**Where the ids sit.** A tagged leaf control carries its id, its label and its
click flag on **one** node, because [`AutomationId`](../../../lib/widgets/automation_id.dart)
merges the pair. A tagged **container** — `editor-body`, `editor-toolbar`,
`label-picker` — keeps its own node above its children, so it shows as an
unlabelled `View` with only the id; `tap id:<name>` works either way.

### Reading a screenshot

`shot` prints one absolute path and nothing else. Read that path; the image
comes back as a picture. It is downscaled 0.5× by default so it costs fewer
tokens; pass `--full` when you need exact pixels. On iOS the native capture is
the default and shows the status bar and Dynamic Island; `--via agent` renders
only the Flutter view (what macOS always gets). Neither layer shows the soft
keyboard in a driver build — the agent owns text entry.

## Dart MCP tools

`qa run` and `qa attach` print the DTD URI and save it per device (`qa dtd`
reprints it; `qa dtd --vm` gives the VM service URI, which `relaunch` also
records). Then:

- `dtd` tool, command `connect`, `uri: <the ws:// URI>` — connects and lists
  the app. After a bare `relaunch` there is no DTD; the `vm_service` tool's
  `connect` takes the `--vm` URI instead.
- `get_runtime_errors` (`clearRuntimeErrors: true` to reset) — the app's
  uncaught exceptions. `qa errors` reads the same errors from the agent's
  buffer without the MCP.
- `hot_reload` / `hot_restart` — apply a code edit without rebuilding (needs
  the `flutter run` behind `qa run`; a `relaunch` ends that tool process).
- `widget_inspector`, command `get_widget_tree` (`summaryOnly: true`).
- `flutter_driver_command` — finders `ByTooltipMessage` (icon buttons),
  `ByText` (rows), `ByValueKey`; `BySemanticsLabel` finds almost nothing in
  this app. `enter_text` is disabled in the driver build — `qa type` types.

## Isolation model

Proved end to end on 2026-09-13 on Android (owner's `gym_notes.db` byte-identical
after four QA runs) and on 2026-09-16 on the iOS simulator and macOS.

- QA builds carry `--dart-define=ANTA_QA=true --dart-define=ANTA_QA_DB=qa`
  (`qa run` adds them unless `--no-qa`). The app then uses the `qa` database
  under `gym_notes/` and a namespaced SharedPreferences prefix, so the owner's
  data is never touched.
- **A QA build cannot reach Firebase.** The signed-in identity belongs to the
  install, not to a database, so a QA run on a device where the owner is
  signed in would otherwise act as them: show their name or e-mail on the
  account screens and create or delete `invites`/`pairs` documents in the
  production project. `SyncAvailability` therefore answers false whenever
  `ANTA_QA` is set, which means Firebase is never initialized and the no-op
  auth and pairing bindings are registered. `agent info` and `doctor` print
  `cloud=off` so this is checked, not assumed. Testing sync on purpose is an
  explicit opt-in — `qa run --define ANTA_QA_CLOUD=true` — and every launch
  then warns, and `doctor` turns the agent line to `warn`. Never screenshot
  or dump an account screen in such a run.
- **Everything the tool prints from a log is redacted**: Firebase API keys,
  OAuth client ids, Firebase app ids, OAuth tokens, JWTs, authorization
  headers, private keys and e-mail addresses are masked in `log`, `errors`
  and in the log tails that failure messages quote. Tool output lands in an
  agent transcript, so this is the one place a secret could leave the
  machine. Local VM service URIs are not secrets and stay readable.
- A QA launch reports what it did on the `[qa]` channel, and the driver build
  also keeps those lines in memory for the agent, which is where `run` and
  `relaunch` read them from (logcat / the unified log / `app.log` are the
  fallbacks). A `--fresh` that never produces `[qa] reset`, or a `--seed` that
  never produces `[qa] seed`, exits 3; so does a seed the app rejected. A
  fixture that imports nothing is reported as `imported 0 folders, 0 notes`
  and is **not** a failure — check the count.
- Markers are files in the app's documents directory:

  | Platform | Documents directory | Delivery |
  | --- | --- | --- |
  | iOS simulator | `xcrun simctl get_app_container <udid> com.alexzamfir.anta data` + `/Documents` | a plain file write on the host |
  | macOS | `~/Library/Containers/com.alexzamfir.anta/Data/Documents` (sandboxed; the agent's `info` confirms the path and `qa agent info` prints it) | a plain file write on the host |
  | Android | `/data/user/0/com.alexzamfir.anta/app_flutter` | `adb push` to `/data/local/tmp`, then `run-as … cp` (debug builds only) |

  `--fresh` drops an empty `qa_reset`; `--seed <file>` copies a full-backup
  JSON as `qa_seed.json`. Fixtures live in `tool/qa/fixtures/*.json`.
- **Caveat**: while a QA build is installed, the app icon opens the *QA*
  database. The owner gets their data back on the next normal `flutter run`.

## Traps

Shared:

- **`key back` is `Navigator.maybePop` on the root navigator**, which is
  what Android's back does short of leaving the app: a pushed route pops, a
  sheet or dialog closes, and an in-page mode guarded by `PopScope` (ANTA's
  search bar) is closed by its own handler. With nothing to handle it says
  `nothing to pop` and leaves the app running — a real `popRoute` on the root
  quits a desktop app.
- **An app you started yourself (Xcode, the IDE, a tap on the icon) can still
  be driven**: when no URI is recorded, the tool looks for the VM service the
  app announced in the platform log (simulator: `log show`; Android: logcat +
  `adb forward`) and records it — `qa: recovered the VM service URI from the
  ios log`. macOS has no such log; `qa relaunch -d macos` instead.
- **`doctor` warns about markers left pending** (`qa_seed.json pending in the
  documents directory`): a non-QA build ignores them and the next QA launch
  would silently apply a stale seed.
- **The agent cannot see native UI.** A permission prompt, a share sheet or
  the simulator's own dialogs are invisible to `dump`; `shot` (native on iOS)
  shows them. Android's adb path sees them and warns `foreground is …, not
  com.alexzamfir.anta`.
- **A `wait` on an ambiguous label fails at once** (see Targets). Prefer
  `id:` targets in step files.
- **Off-screen nodes never win a label.** The agent's tree includes rows a
  list has cached beyond the viewport (flagged `hidden`); a visible match is
  preferred over a hidden duplicate, `wait`/`expect` treat a hidden node as
  absent, and `tap` on one says `scroll-to it first`.
- **A refused reset fails the launch.** `[qa] reset refused: ANTA_QA_DB is
  "gym_notes"` means the build points at the owner database; `run`/`relaunch`
  exit 3 on it (the outcome is typed, not matched on wording) instead of
  reporting a reset that never happened.
- **A non-driver app does not stall the verbs.** The driver extension is
  looked for once per connection (15 s only right after a launch, when `main`
  is still registering it); a plain build fails fast with "not the driver
  build".
- **`relaunch` has no DTD.** Hot reload and the Dart MCP's `dtd connect` need
  the `flutter run` from `qa run` (or `qa attach`). `relaunch` records the VM
  URI, which is all the agent and `qa dtd --vm` need.
- **One `flutter run` at a time.** `run` on a second device kills the first
  run's tool process (not its app). Per-device VM/DTD files keep the verbs
  pointed at the right app; `relaunch` restores the agent on either side.
- **Typing goes through `TestTextInput`,** so there is never a soft keyboard,
  `type` refuses when no field is focused (exit 2: tap a field first), and
  `key enter` sends the field's own input action (`search`, `done`,
  `newline`…). `key done|search|newline` sends a specific action.
- **A tap right after a dialog or sheet closes falls through** to whatever is
  underneath. Put a `wait` (or a second `dump`) between them.
- **The in-app theme overrides the system theme.** Switch light and dark in
  ANTA's own settings.

iOS simulator:

- **`log` is the unified log** (`xcrun simctl spawn <udid> log show`, ~1 s,
  last 10 minutes, Flutter's own predicate). The app's `print`s do not go to
  stdout on iOS, which is why `relaunch` reads `[qa]` lines from the agent;
  the log fallback is scoped to the running pid (`processID == N`), so a
  previous launch's lines are never mistaken for this one's.
- **A reinstall moves the data container** to a new UUID directory (the
  contents survive). The tool queries `get_app_container` fresh every
  process; never cache that path in a script.
- **`--cold`/`--phone` are Android flags**; pick a different simulator with
  `--sim` instead. `boot` needs `--sim` (or `ANTA_QA_SIM`) when more than one
  iPhone is installed and none is booted.

macOS:

- **`shot` is the agent's render** (no window id is needed); there is no
  native capture without a window id, and `--via native` says so.
- **The sandbox container appears on first launch**, so a brand-new machine
  runs a plain `qa run -d macos` before any `--fresh`/`--seed`.
- **`app.log` is the app's stdout**, captured only for launches this tool
  made (`relaunch`/`launch`); a `qa run` launch logs into `run.log`.

Android (unchanged from the Windows-era harness; still true):

- **Right-edge swipes are Android's back gesture.** Every swipe this tool
  builds keeps 48 px clear of all four edges.
- **`adb shell input text` is ASCII only** and the device shell eats `#`, `(`,
  `)`, `&`, `$` and backticks; `qa type` quotes and refuses non-ASCII. Use
  `--via agent` for Unicode (needs the driver build from `qa run`).
- **`uiautomator dump` fails while an animation runs**; `dump` retries three
  times and names the cause. Never run two dumps at once.
- **`pgrep -f uiautomator` always matches itself**; every probe uses
  `pgrep -f '[u]iautomator'`.
- **`E/FirebearStorageCryptoHelper`** in `errors` is Firebase with no signed-in
  user; hidden as known noise.
- **`adb logcat -T` compares against the device clock**, which lags the host;
  stamps are backdated 15 s and marker waits scope to the app's pid.
- **`qa type` on adb warns when no keyboard is up** — with the driver build
  installed that is always, because the agent owns the text channel; use
  `--via agent`.
- **A `WARNING | Failed to …` line from the emulator is not fatal.** `boot`
  ignores INFO/WARNING chatter (it used to abort on a routine `.ini` warning
  on a fresh Mac) and, if it is re-run while an emulator it started is still
  offline, resumes waiting instead of calling the guest wedged.
- **A forwarded port answers before the app does.** After `relaunch`, adb
  accepts the TCP connection on the forwarded VM-service port while nothing
  listens behind it yet, so the WebSocket handshake fails with an
  `HttpException`, not a refused socket. The client treats any I/O error as
  "not answering yet" and retries; if a verb ever races it anyway, the next
  one recovers the URI from logcat (`qa: recovered the VM service URI from
  the android log`).
- **Do not simplify the Windows launcher** in `tool/qa/src/runner.dart`:
  `flutter.bat` writes nothing under `DETACHED_PROCESS`, an inherited stdout
  keeps the caller's shell from returning, and `flutter run` quits when stdin
  reports end-of-file — three separate traps, each a silent failure. On POSIX
  none of them apply and the wrapper simply `exec`s the tool (checked on macOS
  2026-09-16: a detached `flutter run` with stdin at `/dev/null` keeps
  running), so the recorded pid is the tool's own.
- **PowerShell 5.1 eats the inner quotes of a native command's arguments**;
  use `--%` with `\"` or `steps --file`.

**Notification-shade actions (Android, 2026-09-23).** `tap "<label>"` on the
native path resolves inside the **foreground app's** window, so a button on
a notification (Stop, Skip, Open note, Done) never matches by label. Open
the shade with **one** `swipe down --from 540,8 --dist 1400` (a second swipe
expands Quick Settings over the rows), then either `dump --all` and `tap
"#N"` from that dump, or tap raw pixels from the bounds a dump printed
earlier — uiautomator sometimes leaves the `NotificationShade` window out of
a dump entirely while a native `shot` shows it open. Verify the outcome in
`dumpsys notification --noredact` (a record's `id=`, `flags=`, `extras`)
rather than in the tree.

**Quick Settings tile (Android, 2026-09-23).** A tile the app declares is
not in the panel until the user adds it. `adb shell cmd statusbar add-tile
com.alexzamfir.anta/.QuickAlarmTileService` adds it from the host — a
device-UI setting, not app data, and the second sanctioned by-hand call
beside the read-only alarm queries — after which two `swipe down` open the
full panel and a native `look --all` names the tile by its label
(`"Quick alarm"`); tap it by pixels and switch to `--via agent` to see the
sheet it opened. A launcher shortcut is checked from the app drawer (`key
home` on the native path, `swipe up`, `longpress` the app icon, the
bubble's long label is the target) and, read-only, in `adb shell dumpsys
shortcut` under the package.

## Alarm-clock evidence (event alerts, Android)

The Alarm tier is armed with `AlarmManager.setAlarmClock` (the `alarm` fork,
event-alerts session OS-1, 2026-09-22), and the platform's own record is the
evidence — there is no `qa alerts` verb yet (the parent roadmap's Session 7).
Three **read-only** shell queries, run from the host, are the accepted
exception to "never drive adb by hand": they neither touch the app nor its
data.

```bash
adb shell dumpsys alarm | grep -A9 "RTC_WAKEUP #.*com.alexzamfir.anta"
adb shell settings get system next_alarm_formatted   # legacy key; may be empty on some ROMs
adb shell run-as com.alexzamfir.anta ls files        # debug builds only
```

What a passing entry looks like (emulator, API 36.1, 2026-09-22): the ANTA
entry prints an `Alarm clock:` block (`triggerTime=…` and
`showIntent=PendingIntent{… com.alexzamfir.anta startActivity}`), a
`flags=` mask that includes `0x2` (`WAKE_FROM_IDLE`), an `idle-options`
bundle with `temporaryAppAllowlistReasonCode=301`
(`REASON_ALARM_MANAGER_ALARM_CLOCK`), and it is listed under `Next wake from
idle:`. The `0x8` bit (`ALLOW_WHILE_IDLE_UNRESTRICTED`) the owner's-phone
checklist mentions is **not** in the mask on API 36 — the exemption rides the
idle options instead — so read the block, not one bit. A reminder entry
(`ScheduledNotificationReceiver`) prints no such block. The status bar's
alarm icon reads `"Alarm set for <time>."` in a native dump, and the
Quick Settings header row with the same text opens the Alerts hub. Locking
the emulator needs a keyguard: `locksettings get-disabled` prints `true` on
a stock AVD, `locksettings set-disabled false` gives it the swipe lock
screen for the check, and `set-disabled true` puts it back.

## Secrets and credentials files

- `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`
  and `lib/firebase_options.dart` are machine-local and gitignored. The
  Android one must sit in **`android/app/`**: one level up Gradle does not
  find it (`File google-services.json is missing`). `.gitignore` also ignores
  these names anywhere in the tree (and the `google_services.json` spelling,
  `key.properties`, keystores and service-account JSON), so a copy dropped in
  the wrong folder cannot be staged by `git add -A`.
- Never `cat` those files, paste their contents into a command, a doc, a
  commit message or a step file, or attach them to anything. To check one,
  print its structure with the values masked.
- Screenshots, dumps and logs live under `build/qa/`, which is ignored. Do not
  copy them into the repo or into `docs/`.

## Never

- Never kill, wipe, cold-boot or restart an emulator or simulator out from
  under the owner. `boot` refuses when a device is already attached; `xcrun
  simctl erase`/`shutdown` are not verbs here and must not be run by hand
  during a pass.
- Never `pm clear`, `uninstall`, delete app data or a simulator data
  container: the default database in each is the owner's.
- Never edit the default database from a QA run — that is what `ANTA_QA` is
  for. The `agent` doctor line turns FAIL when a non-QA build is being driven.
