# Verbs in full

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

Contents: Verbs (every verb's flags, an example and its real output) · Reading `doctor` · Targets · Reading a dump · Reading a screenshot.

Two moved lines point outside this file: the `devices` row's "see above" is the `qa devices` output, now in `harness-notes.md`; the `AutomationId` link was written from SKILL.md's folder — the file is `lib/widgets/automation_id.dart`.

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
