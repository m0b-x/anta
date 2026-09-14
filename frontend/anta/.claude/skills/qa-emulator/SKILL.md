---
name: qa-emulator
description: Drive the ANTA app on the Android emulator (and later iOS simulator) from the command line - boot, launch in an isolated QA database, screenshot, read the accessibility tree, tap/type by label, and read runtime errors. USE FOR - running the app on a device, device passes, screenshots, tapping/typing by label, reading runtime errors, QA checklists. Load together with anta-context.
---

# QA emulator harness

One CLI drives the device. Run it from `frontend/anta`, through the wrapper:

```powershell
tool\qa\qa.cmd <verb> [args]      # PowerShell / cmd
./tool/qa/qa <verb> [args]        # Git Bash, macOS, Linux
```

The wrapper compiles `build/qa/qa.exe` the first time it is used (~30 s, once
per `flutter clean`) and runs the binary after that: a verb costs about 30 ms
of startup instead of ~2 s of JIT. When a file under `tool/qa/` changes, the
next verb rebuilds itself first (`qa: sources changed since qa.exe was
built — rebuilding…`, ~2.5 s warm) and then serves the verb, so there is
nothing to remember. `qa build-exe` forces it; `QA_NO_SELF_REBUILD=1` turns it
off; `dart run tool/qa/qa.dart <verb>` still works everywhere and never
self-rebuilds.

`dart run` prints `Running build hooks...` on stderr before every verb — that
is the Dart CLI, not this tool. The wrapper has no such noise.

Exit codes: `0` ok, `1` usage, `2` target not found or ambiguous, `3` device or
adb failure. Every verb takes `--help`; `-d/--device` (or `ANTA_QA_DEVICE`)
picks the serial, otherwise the sole attached device. Nothing is assumed: with
no usable device attached the verb fails with what is actually wrong (`no
device attached — run \`qa boot\``, `emulator-5554 is offline — …`,
`unauthorized — accept the USB-debugging prompt on the device`).

## Two driving layers

| | adb / uiautomator (this CLI) | Flutter Driver (Dart MCP) |
| --- | --- | --- |
| Works on | any build, debug or release | only the `test_driver/main_driver.dart` entry point, which `qa run` uses by default |
| Sees | the Android accessibility tree (`dump`), pixels (`shot`) | the widget tree (`widget_inspector get_widget_tree`) |
| Acts by | screen coordinates resolved from a label | Flutter finders: `ByTooltipMessage`, `BySemanticsLabel`, `ByValueKey`, `ByText`, `ByType` |
| Types | ASCII only (`adb shell input text`) | any Unicode (`enter_text`) |
| Waiting | polls dumps (`wait`, `scroll-to`) | frame-synced `waitFor`, `waitForTappable`, `scrollIntoView` |

Use this CLI to **see** (`dump`, `shot`) and to do anything the app does not
label. Use Driver to **act** when a tooltip, semantics label or key exists, and
always for non-ASCII text. `widget_inspector` works on any debug app;
`flutter_driver_command` returns "The flutter driver extension is not enabled"
unless the app was started from the driver entry point.

## Canonical loop

```powershell
$q = "tool\qa\qa.cmd"
& $q doctor                     # first, whenever anything looks off
& $q boot                       # starts the emulator only if none is attached
& $q run --fresh --seed tool/qa/fixtures/basic.json
& $q dtd                        # -> feed to the Dart MCP: dtd connect <uri>
& $q shot 00_start              # prints a path; Read that path
& $q dump                       # one line per node - find the label to tap
& $q tap "Search all notes" --wait id:search-field --shot 01_search
& $q errors                     # anything the app logged as an error
& $q unphone                    # only if you used boot --phone
```

Do not `kill-run` at the end unless you started the run — leave the app up.

## Fast loop

The wall clock is not the expensive part; **your round trips are**. Five tool
calls at model latency cost far more than the five adb calls inside them. So:

- **`steps` runs a whole flow in one call**, sharing one serial resolution, one
  screen-size cache and one dump cache. Each step prints `[2/5] wait
  id:search-field` and then its own output, indented. The first failure stops
  the run and says `steps: stopped at 2/5`; `--keep-going` runs the rest.

  ```bash
  ./tool/qa/qa steps 'tap "Search all notes"' 'wait id:search-field' \
                     'shot results' 'dump' 'key back'
  ./tool/qa/qa steps --file flow.txt      # one step per line, # comments ok
  ```

  **From PowerShell, use the stop-parsing token or `--file`.** PowerShell 5.1
  strips the inner double quotes out of a native command's arguments, so
  `& $q steps 'tap "Search all notes"'` reaches the tool as `tap Search all
  notes` and fails on step 2 with `Could not find a command named "all"`. Both
  of these work:

  ```powershell
  tool\qa\qa.cmd --% steps "tap \"Search all notes\"" "key back"
  tool\qa\qa.cmd steps --file flow.txt
  ```

  Git Bash passes `'tap "Search all notes"'` through unchanged.

- **Act and verify in one call.** `tap`, `longpress`, `type`, `key`, `swipe`,
  `launch` and `relaunch` all take `--wait <target>` (or `--wait-gone`,
  `--wait-timeout S`), `--shot <name>` and `--dump`, applied in that order. With
  no wait they pause `--settle` ms (default 300) before the shot. A `--wait`
  that times out still takes the `--shot` first and says so, so the failure
  arrives with the picture of why.

- **`relaunch` is the ~3 s reset** when you do not need Driver: it drops the
  markers, force-stops, `am start`s and waits for the `[qa]` lines. `run` is
  ~15 s and gives you DTD as well.

- **`#N` resolves against the dump you read**, from `build/qa/last_dump.xml`,
  not against a fresh one that may have renumbered — the output says
  `(#18 from the dump 4 s ago)`. `dump --cached` reprints it without touching
  the device; `x,y` targets skip the dump entirely. Label and `id:` targets
  always dump fresh.

- **`doctor` first when anything looks off.** One line per check, `ok`/`warn`/
  `FAIL` plus the fix; exit 3 if anything failed. `--fix` applies only the safe
  repairs (wake, unphone, kill a leftover `uiautomator`, clear a stale
  `run.pid`, reap orphaned services) and then re-runs the checks. It never
  restarts the emulator, never force-stops the app and never touches app data.

## Verbs

Every acting verb (`tap`, `longpress`, `type`, `key`, `swipe`, `launch`,
`relaunch`) also takes `--wait T` / `--wait-gone T` / `--wait-timeout S` /
`--settle MS` / `--shot NAME` / `--dump`.

| Verb | Example | Real output |
| --- | --- | --- |
| `devices` | `qa devices` | `emulator-5554  device  model:sdk_gphone64_x86_64` |
| `state [--json]` | `qa state` | `device=emulator-5554  app=pid 8911  resumed=com.alexzamfir.anta/.MainActivity  foreground=com.alexzamfir.anta  awake=yes  locked=no  ime=down  screen=1280x2856 @480dpi (427 x 952 dp)  run.log=yes  dtd=ws://127.0.0.1:60473/_SRrxC0lw0U=` — one batched shell call, ~130 ms |
| `doctor [--fix] [--json]` | `qa doctor` | twelve `ok  ` / `warn` / `FAIL` lines with a `→ fix` under each problem; see below |
| `boot [--avd N] [--cold] [--phone]` | `qa boot --phone` | `emulator already up: emulator-5554 (never killed or restarted by this tool)` then `wm size set to 1080x2400 (360x800 dp)` |
| `wake` | `qa wake` | `awake=yes  locked=no  foreground=com.alexzamfir.anta` |
| `unphone` | `qa unphone` | `wm size reset: 1280x2856 @480dpi (427 x 952 dp)` |
| `run [--fresh] [--seed F] [--define K=V] [--no-qa] [--no-driver]` | `qa run --fresh --seed tool/qa/fixtures/basic.json` | `pid=22648  log=…\build\qa\run.log` / `dtd=ws://…` / `vm=http://…` then the three `[qa]` lines (about 15 s warm, up to 4 min on a cold build) |
| `relaunch [--fresh] [--seed F]` | `qa relaunch --fresh --seed tool/qa/fixtures/basic.json` | `relaunched com.alexzamfir.anta/.MainActivity` then the `[qa]` lines, ~3 s — no Driver |
| `attach` | `qa attach` | same three lines, against an app already running |
| `stop` / `kill-run` | `qa kill-run` | `killed run pid 12180` |
| `dtd [--vm]` | `qa dtd` | `ws://127.0.0.1:59940/vZ2LA9BdQPg=` |
| `launch` | `qa launch --wait Folders` | `launched com.alexzamfir.anta/.MainActivity` then `found: #16  View  "Folders"  [60,324][334,420]` |
| `shot [name] [--scale F] [--full] [--out D]` | `qa shot home` | `D:\…\build\qa\shots\20260913_173744_home.png` |
| `dump [--all] [--json] [--cached]` | `qa dump` | see below; `--cached` adds `[cached, taken 8 s ago]` |
| `tap <target> [--nth N]` | `qa tap "#18"` | `tapped 640,535  #18  View  "All notes\n3"  id=drawer-all-notes  [0,462][1280,609]  click  (#18 from the dump just now)` |
| `longpress <target> [--ms]` | `qa longpress "Injury notes"` | `long-pressed 640,2440 for 800ms  …` |
| `text <target>` | `qa text "#11"` | the node's text |
| `wait <target> [--gone] [--timeout S]` | `qa wait "Clear search"` | `found: #12  Button  "Clear search"  [1136,156][1280,300]  click` |
| `scroll-to <target> [--max N] [--in T] [--up]` | `qa scroll-to "Warm-up protocol"` | `found after 0 swipe(s): #32  View  "Warm-up protocol…"` |
| `type "<text>" [--enter]` | `qa type "squat"` | `typed "squat"` |
| `key <name>` | `qa key back` | `sent KEYCODE_BACK` |
| `swipe <dir> [--from x,y] [--dist px] [--ms N]` | `qa swipe up` | `swiped up: 640,1428 -> 640,48 (300ms)` |
| `steps <line>… [--file F] [--keep-going]` | `qa steps 'tap "Training"' 'key back'` | `[1/2] tap "Training"` then the verb's output, indented two spaces |
| `logcat [--lines N] [--since-launch] [--all]` | `qa logcat --lines 40` | filtered device log |
| `errors [--lines N] [--all]` | `qa errors` | `no errors in …\build\qa\run.log (2 known-noise line(s) hidden; --all to show)` |
| `build-exe` | `qa build-exe` | `D:\…\build\qa\qa.exe  (2568 ms)` |

### Reading `doctor`

Real output, healthy emulator, 2026-09-14:

```
ok    adb server              D:\…\platform-tools\adb.exe answered (1 device row(s))
ok    device                  emulator-5554 (device)
ok    boot                    boot_completed=1 provisioned=1
ok    awake                   awake=yes locked=no
ok    screen                  1280x2856 @480dpi (427 x 952 dp)
ok    app installed           apk present and run-as works (debug build)
warn  app running             pid 8911, but the foreground is com.google.android.apps.nexuslauncher
      → run `qa launch` to bring it back to the front
ok    uiautomator             dump ok in 2003 ms
ok    /data space             29832 MB free
ok    host run state          run.pid 2804 is alive
ok    dtd                     ws://127.0.0.1:60473/_SRrxC0lw0U=
ok    qa.exe                  up to date
```

### Targets

A target is one of:

- `#12` — the flat node index, resolved against **the cached dump**
  (`build/qa/last_dump.xml`) so the index still means the node you read; the
  output appends `(#12 from the dump 4 s ago)`. With nothing cached it exits 2
  with ``no previous dump — run `dump` first or target by label``;
- `123,456` — raw device pixels, which costs no dump at all;
- `id:content` — a resource id, full or short;
- anything else — a **label**, matched against content description, then text,
  then resource id, in three passes: exact, case-insensitive, case-insensitive
  substring. The first pass with any hit wins.

An ambiguous label exits 2 and lists the candidates with the `--nth N` (0-based)
that picks each one. A tap on a node that is not itself clickable retargets to
the nearest clickable ancestor and says so.

A label that matches nothing exits 2 **with the screen it looked at**, so no
second call is needed to find out where you are:

```
qa: no node matches "Nothing here at all". on screen (com.alexzamfir.anta):
"Open navigation menu" | "Search all notes" | "Show menu" | "Folders" |
"All notes / 3" | "Recent" | "FOLDERS" | "Inbox / 0" |
"Money / Green label / 1" | "Training / Blue label / 2" | "New folder" |
"Import" | "3 folders" | "id:content" | "id:navigationBarBackground"
```

Labelled nodes come first and id-only nodes fill the rest. A `wait` timeout and
a `scroll-to` that ran out of swipes print the same listing plus
`foreground=<pkg>`.

### Reading a dump

`dump` prints `#index  Class  "content-desc"  text="…"  id=…  [l,t][r,b]  flags`,
labelled/clickable/scrollable nodes only (`--all` for the rest). Real output,
QA build seeded from `basic.json`:

```
#11  Button  "Open navigation menu"  id=nav-menu  [135,165][261,291]  click
#13  Button  "Search all notes"  id=search-open  [992,156][1136,300]  click
#19  View  "All notes
3"  id=drawer-all-notes  [0,462][1280,609]  click
#22  View  "Inbox
0"  [0,873][1280,1020]  click,long
#23  View  "Money
Green label
1"  [0,1020][1280,1167]  click,long
16 node(s) of 29 (pass --all for the rest)
```

The content description is what ANTA's `Semantics` labels and tooltips produce,
so it is almost always the localized string — tap by that, or by `id:` for
anything in `lib/constants/semantics_ids.dart`, which never moves with the
locale.

**Where the ids sit.** A tagged leaf control carries its id, its label and its
click flag on **one** node, because [`AutomationId`](../../../lib/widgets/automation_id.dart)
merges the pair. A tagged **container** — `editor-body`, `editor-toolbar`,
`label-picker` — deliberately keeps its own node above its children, so it
shows as an unlabelled `View` with only the id:

```
#12  Button  "Show menu"  id=editor-more  [1136,156][1280,300]  click
#15  View  id=editor-body  [0,396][1280,2634]
#19  View  id=editor-toolbar  [0,2634][1280,2784]
```

`tap id:<name>` works either way: a tap on a node that is not itself clickable
retargets to the nearest clickable ancestor.

### Reading a screenshot

`shot` prints one absolute path and nothing else. Read that path; the image
comes back as a picture. It is downscaled 0.5× by default (halves each side) so
it costs fewer tokens; pass `--full` when you need to judge exact pixels.

## Dart MCP tools

`qa run` and `qa attach` print the DTD URI and save it to `build/qa/dtd.txt`
(`qa dtd` reprints it; `qa dtd --vm` gives the VM service URI). Then:

- `dtd` tool, command `connect`, `uri: <the ws:// URI>` — connects, and lists
  the app: `name: Kind: Flutter - Device: sdk gphone64 x86 64 - Package: anta`.
- `get_runtime_errors` (`clearRuntimeErrors: true` to reset) — the app's
  uncaught exceptions. `no runtime errors found` is the pass condition for a
  device check.
- `hot_reload` / `hot_restart` — apply a code edit without rebuilding.
- `widget_inspector`, command `get_widget_tree` (`summaryOnly: true` for user
  code only) — find tooltips, keys and types for Driver finders.
- `flutter_driver_command` — call shapes proved on this app:
  - `{command: "get_health"}` → `{"status":"ok"}`
  - `{command: "waitFor", finderType: "ByTooltipMessage", text: "Search all notes", timeout: "5000"}`
  - `{command: "tap", finderType: "ByTooltipMessage", text: "Search all notes"}`
  - `{command: "waitFor", finderType: "ByText", text: "All notes"}`
  - `{command: "enter_text", text: "ăöü"}` — the Unicode path `qa type` refuses
  - `{command: "get_text", finderType: "ByValueKey", keyValueString: "…", keyValueType: "String"}`

**Which finder.** `ByTooltipMessage` for icon buttons, `ByText` for rows and
labels, `ByValueKey` where a key exists. **`BySemanticsLabel` finds almost
nothing in this app** and always has: it matches a `Semantics` widget that
declares that literal label, and ANTA's rows compose their label from `Text`
descendants while its buttons carry a tooltip (which lands on
`SemanticsData.tooltip`, not `label`). Android still reads the tooltip as the
content description, which is why `dump` and `tap` see it.

A `waitFor` that times out means the finder matched nothing — check with `dump`
which screen you are actually on before blaming the harness. Note that a
Driver timeout is itself reported by `get_runtime_errors` as a
`FlutterDriverExtension: Timeout while executing waitFor` entry, so clear the
errors after a probe that was expected to miss.

## Isolation model

Proved end to end on 2026-09-13: four QA runs and back, with the owner's
`gym_notes.db` unchanged to the byte (282,624 bytes, same mtime, `qa.db` beside
it) and the owner's root showing its own `All notes 14 / 123 / Training` again
on the next `--no-qa` run.

- QA builds carry `--dart-define=ANTA_QA=true --dart-define=ANTA_QA_DB=qa`
  (`qa run` adds them unless `--no-qa`). The app then uses the `qa` database
  under `gym_notes/` and a namespaced SharedPreferences prefix, so the owner's
  data is never touched.
- A QA launch reports what it did on the `[qa]` channel. `qa errors` shows
  these; so does `qa logcat`:

  ```
  I/flutter ( 7344): [qa] reset: cleared preferences and qa.db
  I/flutter ( 7344): [qa] seed: imported 4 folders, 3 notes
  I/flutter ( 7344): [qa] onboarding marked completed
  ```

  `--fresh` with no `--seed` prints only the reset and onboarding lines and
  lands on an empty folder root, never on onboarding. A plain `qa run` prints
  none of them and the QA data from the previous run is still there.

  **`run` and `relaunch` now wait for those lines and check them.** A `--fresh`
  that never produces `[qa] reset`, or a `--seed` that never produces
  `[qa] seed`, exits 3 rather than leaving you reading a database that is not
  the one you asked for; so does a seed the app rejected
  (`qa: the seed was not imported: seed: import failed: FormatException: …`).
  A fixture the importer accepts but finds nothing in is reported honestly as
  `[qa] seed: imported 0 folders, 0 notes` and is **not** a failure — check the
  count, not just the exit code.
- `--fresh` drops an empty `qa_reset` marker in the app documents dir; the next
  QA launch clears the QA prefs and deletes `gym_notes/qa.db*`.
- `--seed <file>` pushes a full-backup JSON as `qa_seed.json`; the next QA
  launch imports it. Fixtures live in `tool/qa/fixtures/*.json`.
- Both markers go in via `/data/local/tmp` and `adb shell run-as
  com.alexzamfir.anta cp …`, which only works because the app is a debug build.
- **Caveat**: while a QA build is installed, the launcher icon opens the *QA*
  database. The owner gets their data back on their next normal `flutter run`.

## Traps

- **Right-edge swipes are Android's back gesture.** Every swipe this tool
  builds keeps 48 px clear of all four edges. If you call `adb shell input
  swipe` by hand, do the same.
- **`adb shell input text` is ASCII only** and the device shell eats `#`, `(`,
  `)`, `&`, `$` and backticks. `qa type` single-quotes the argument and turns
  spaces into `%s`; non-ASCII is refused with a pointer to Driver `enter_text`.
  Newlines and tabs are refused too — use `key enter` / `key tab`.
- **`adb shell logcat -T "MM-DD HH:MM:SS.mmm"` fails**: the device shell splits
  the space. `qa logcat` uses host-side `adb logcat` instead.
- **`uiautomator dump` fails while an animation runs.** `dump` retries three
  times, 300 ms apart, and then says which of the two causes it is: a leftover
  `uiautomator` process (`run \`qa doctor --fix\``) or the animation. Never run
  two dumps at once: the second crashes with `UiAutomationService … already
  registered!`, which then sits in logcat looking like an app crash. `qa errors`
  scopes its logcat read to the app's own pid for exactly that reason.
- **`pgrep -f uiautomator` always matches itself.** `adb shell pgrep -f
  uiautomator` finds the very shell running it, so it reports a leftover on a
  perfectly clean device. Every probe here uses `pgrep -f '[u]iautomator'`,
  which matches the real process and not this command line.
- **`E/FirebearStorageCryptoHelper`** in `errors` is Firebase with no signed-in
  user, not an app fault — two lines, not one (`Exception encountered while
  decrypting bytes:` and `decryption failed`). `errors` hides both and says so:
  `no errors in … (2 known-noise line(s) hidden; --all to show)`.
- **`adb logcat -T` compares against the *device* clock, which lags the host.**
  A stamp taken on the host at launch is in the guest's future, so the lines
  the launch is about to print are filtered out and the wait reports that the
  app said nothing. Every recorded stamp is backdated 15 s
  (`logcatStampMargin`), and the `[qa]` marker wait scopes to the app's pid
  (`--pid=`) instead, which is immune to clock skew and to a previous launch's
  lines.
- **`qa dump`, `tap`, `wait`, `text`, `longpress` and `scroll-to` warn when the
  screen is not ANTA's**: `warning: foreground is
  com.google.android.apps.nexuslauncher, not com.alexzamfir.anta (crashed?
  keyguard? a system dialog?)`. `tap` still taps — system dialogs have to stay
  tappable.
- **`qa type` warns when no keyboard is up**: `warning: no keyboard is up — the
  text may go nowhere (tap a field first)`, from a `mInputShown` probe batched
  into the same shell call as the typing. Observed on `emulator-5554` on
  2026-09-14: the soft IME does not come up for ANTA's search field, the
  warning fires and the text genuinely does not land (`show_ime_with_hard_keyboard`
  made no difference). Use the Driver path — `flutter_driver_command` with
  `enter_text` — when typing has to work.
- **An `adb` call that never answers** now says so in one line: `adb did not
  answer in 30s (…) — the emulator's adbd may be degraded (quick-boot snapshot
  trap: the owner must cold-boot it; never do it from this tool). Run
  \`qa doctor\`.`
- **A tap right after a dialog or sheet closes falls through** to whatever is
  underneath. Put a `wait` (or a second `dump`) between them.
- **The in-app theme overrides `adb shell cmd uimode night`.** Switch light and
  dark in ANTA's own settings, not on the device.
- **TalkBack cannot be scripted.** The accessibility story is `uiautomator dump`
  here, plus `simulatedAccessibilityTraversal` in widget tests.
- **`wm size` must be reset.** `boot --phone` says so in its output; run
  `unphone` before you finish.
- **Under Git Bash set `MSYS_NO_PATHCONV=1`** for hand-written adb commands with
  `/sdcard` or `/data` paths. The Dart tool passes arguments directly and is
  unaffected. Both `tool/qa/qa.cmd` and `tool/qa/qa` work from Git Bash; the
  `.cmd` is the PowerShell entry.
- **A `.bat` invoked from a `.cmd` without `call` never comes back.** `dart` on
  PATH here is `dart.bat`, so `qa.cmd` says `call dart compile exe …`; without
  the `call`, control transfers and the wrapper ends before the verb ever runs,
  silently and with exit code 0. For the same reason the self-rebuild resolves
  a real `dart.exe` (the Flutter SDK's `bin/cache/dart-sdk/bin`) rather than the
  shim: `Process.start` goes through `CreateProcess`, which cannot run a batch
  file.
- **PowerShell 5.1 eats the inner quotes of a native command's arguments.**
  `& $q steps 'tap "Search all notes"'` arrives as three words and fails on the
  wrong step. Use `--%` with `\"` escapes, `steps --file`, or Git Bash.
- **`run` sometimes loses the VM service handshake** — `Error connecting to the
  service protocol` — usually right after a force-stop, or when a previous run
  was killed and left a `dart development-service` behind. `run` reaps those
  orphans first and gives up on the handshake after 20 s instead of the full
  4-minute timeout: just run it again. `qa kill-run` also reaps.
- **Do not simplify the Windows launcher.** Three separate traps are wired into
  `tool/qa/src/runner.dart` and each one was a silent failure: `flutter.bat`
  writes nothing at all under `ProcessStartMode.detached`; a child that
  inherits the calling shell's stdout keeps that shell from ever returning; and
  `flutter run` quits the second stdin reports end-of-file, so the wrapper
  feeds it from an idle pipe that never closes. Redirecting stdin to a file
  breaks that pipe and the run dies again.
- **`qa run` leaves the app running but the run can still end.** If `qa dtd`
  stops working, check `tail build/qa/run.log` for `Lost connection to device`
  and use `qa attach` to get a fresh DTD against the app that is still up.

## Never

- Never kill, wipe, cold-boot or restart the emulator out from under the owner.
  `boot` refuses when a device is already attached.
- Never `pm clear`, `uninstall`, or delete app data: the emulator holds the
  owner's real notes in the **default** database.
- Never edit the default database from a QA run — that is what `ANTA_QA` is for.
